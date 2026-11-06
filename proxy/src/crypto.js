// Crypto utilities: base64, a small DER reader, X.509 certificate parsing and
// chain checks, and ECDSA signature conversion. Used by Apple JWS verification
// (apple.js) and App Attest (attest.js). Everything runs on WebCrypto.

export function base64UrlDecode(str) {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return atob(padded);
}

export function base64UrlToBytes(str) {
  return binaryToBytes(base64UrlDecode(str));
}

export function base64ToArrayBuffer(base64) {
  return binaryToBytes(atob(base64)).buffer;
}

export function base64ToBytes(base64) {
  return binaryToBytes(atob(base64));
}

function binaryToBytes(binary) {
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function arrayBufferToBase64(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

export function bytesToHex(bytes) {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function arrayEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) { if (a[i] !== b[i]) return false; }
  return true;
}

export async function sha256(data) {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
}

// --- DER reader ---------------------------------------------------------------

// Reads one DER element at `offset`. Returns { tag, start, contentStart, end }
// where content is bytes[contentStart, end). Throws on malformed input.
export function readDer(bytes, offset = 0) {
  if (offset + 2 > bytes.length) throw new Error('DER: truncated');
  const tag = bytes[offset];
  let len = bytes[offset + 1];
  let contentStart = offset + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error('DER: bad length');
    if (contentStart + n > bytes.length) throw new Error('DER: truncated');
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + bytes[contentStart + i];
    contentStart += n;
  }
  const end = contentStart + len;
  if (end > bytes.length) throw new Error('DER: truncated');
  return { tag, start: offset, contentStart, end };
}

// The child elements of a constructed element (SEQUENCE, SET, [n]).
export function derChildren(bytes, el) {
  const out = [];
  let offset = el.contentStart;
  while (offset < el.end) {
    const child = readDer(bytes, offset);
    out.push(child);
    offset = child.end;
  }
  if (offset !== el.end) throw new Error('DER: bad nesting');
  return out;
}

export function derContent(bytes, el) {
  return bytes.slice(el.contentStart, el.end);
}

function derRaw(bytes, el) {
  return bytes.slice(el.start, el.end);
}

// Dotted string from an OBJECT IDENTIFIER element.
function derOid(bytes, el) {
  if (el.tag !== 0x06) throw new Error('DER: expected OID');
  const c = derContent(bytes, el);
  const parts = [];
  let value = 0;
  for (let i = 0; i < c.length; i++) {
    value = value * 128 + (c[i] & 0x7f);
    if (!(c[i] & 0x80)) {
      if (parts.length === 0) {
        const first = value < 80 ? Math.floor(value / 40) : 2;
        parts.push(first, value - first * 40);
      } else {
        parts.push(value);
      }
      value = 0;
    }
  }
  return parts.join('.');
}

// Milliseconds since epoch from a UTCTime or GeneralizedTime element.
function derTime(bytes, el) {
  const s = new TextDecoder().decode(derContent(bytes, el));
  let m;
  if (el.tag === 0x17) {
    m = /^(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$/.exec(s);
    if (!m) throw new Error('DER: bad UTCTime');
    const yy = Number(m[1]);
    m[1] = String(yy >= 50 ? 1900 + yy : 2000 + yy);
  } else if (el.tag === 0x18) {
    m = /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$/.exec(s);
    if (!m) throw new Error('DER: bad GeneralizedTime');
  } else {
    throw new Error('DER: expected time');
  }
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
}

// --- X.509 --------------------------------------------------------------------

export const OID = {
  ecPublicKey: '1.2.840.10045.2.1',
  p256: '1.2.840.10045.3.1.7',
  p384: '1.3.132.0.34',
  ecdsaSha256: '1.2.840.10045.4.3.2',
  ecdsaSha384: '1.2.840.10045.4.3.3',
};

const CURVES = { [OID.p256]: { name: 'P-256', size: 32 }, [OID.p384]: { name: 'P-384', size: 48 } };
const HASHES = { [OID.ecdsaSha256]: 'SHA-256', [OID.ecdsaSha384]: 'SHA-384' };

// Parses a DER X.509 certificate with an EC key. Throws on anything else.
// Returns { der, tbs, signatureHash, signature, issuer, subject, notBefore,
// notAfter, spki, curve, extensions: Map<oid, Uint8Array of extnValue content> }.
export function parseCertificate(der) {
  const bytes = der instanceof Uint8Array ? der : new Uint8Array(der);
  const certEl = readDer(bytes, 0);
  if (certEl.tag !== 0x30 || certEl.end !== bytes.length) throw new Error('X.509: not a certificate');
  const [tbsEl, sigAlgEl, sigEl] = derChildren(bytes, certEl);
  if (!tbsEl || !sigAlgEl || !sigEl || sigEl.tag !== 0x03) throw new Error('X.509: bad structure');

  const sigAlgOid = derOid(bytes, derChildren(bytes, sigAlgEl)[0]);
  const signatureHash = HASHES[sigAlgOid];
  if (!signatureHash) throw new Error(`X.509: unsupported signature algorithm ${sigAlgOid}`);
  const sigBits = derContent(bytes, sigEl);
  if (sigBits[0] !== 0) throw new Error('X.509: bad signature bits');

  const tbs = derChildren(bytes, tbsEl);
  let i = tbs[0].tag === 0xa0 ? 1 : 0; // optional [0] version
  i += 1; // serialNumber
  const innerSigAlgOid = derOid(bytes, derChildren(bytes, tbs[i++])[0]);
  if (innerSigAlgOid !== sigAlgOid) throw new Error('X.509: signature algorithm mismatch');
  const issuerEl = tbs[i++];
  const validity = derChildren(bytes, tbs[i++]);
  const subjectEl = tbs[i++];
  const spkiEl = tbs[i++];

  const spkiParts = derChildren(bytes, spkiEl);
  const keyAlg = derChildren(bytes, spkiParts[0]);
  if (derOid(bytes, keyAlg[0]) !== OID.ecPublicKey) throw new Error('X.509: not an EC key');
  const curve = CURVES[derOid(bytes, keyAlg[1])];
  if (!curve) throw new Error('X.509: unsupported curve');

  const extensions = new Map();
  for (; i < tbs.length; i++) {
    if (tbs[i].tag !== 0xa3) continue;
    const [extSeq] = derChildren(bytes, tbs[i]);
    for (const ext of derChildren(bytes, extSeq)) {
      const parts = derChildren(bytes, ext);
      const valueEl = parts[parts.length - 1];
      if (valueEl.tag !== 0x04) throw new Error('X.509: bad extension');
      extensions.set(derOid(bytes, parts[0]), derContent(bytes, valueEl));
    }
  }

  return {
    der: bytes,
    tbs: derRaw(bytes, tbsEl),
    signatureHash,
    signature: sigBits.slice(1),
    issuer: derRaw(bytes, issuerEl),
    subject: derRaw(bytes, subjectEl),
    notBefore: derTime(bytes, validity[0]),
    notAfter: derTime(bytes, validity[1]),
    spki: derRaw(bytes, spkiEl),
    curve: curve.name,
    curveSize: curve.size,
    extensions,
  };
}

export async function importCertKey(cert, extractable = false) {
  return crypto.subtle.importKey('spki', cert.spki, { name: 'ECDSA', namedCurve: cert.curve }, extractable, ['verify']);
}

// True when `cert` names `issuer` as its issuer and carries a valid signature
// from the issuer's key, using the hash its signature algorithm OID names.
// `issuerKey` may be passed instead of an issuer certificate when only the key
// is pinned: { key: CryptoKey, curveSize, subject? }.
export async function isIssuedBy(cert, issuer) {
  try {
    if (issuer.subject && !arrayEqual(cert.issuer, issuer.subject)) return false;
    const key = issuer.key || (await importCertKey(issuer));
    const raw = derSignatureToRaw(cert.signature, issuer.curveSize);
    return await crypto.subtle.verify({ name: 'ECDSA', hash: cert.signatureHash }, key, raw, cert.tbs);
  } catch {
    return false;
  }
}

export function isValidAt(cert, time) {
  return cert.notBefore <= time && time <= cert.notAfter;
}

// Convert a DER-encoded ECDSA signature to raw r||s format for WebCrypto.
export function derSignatureToRaw(derSig, componentSize = 32) {
  const bytes = derSig instanceof Uint8Array ? derSig : new Uint8Array(derSig);
  const seq = readDer(bytes, 0);
  if (seq.tag !== 0x30 || seq.end !== bytes.length) throw new Error('Invalid DER signature');
  const ints = derChildren(bytes, seq);
  if (ints.length !== 2 || ints[0].tag !== 0x02 || ints[1].tag !== 0x02) throw new Error('Invalid DER signature');
  const raw = new Uint8Array(componentSize * 2);
  ints.forEach((el, n) => {
    let v = derContent(bytes, el);
    while (v.length > componentSize && v[0] === 0) v = v.slice(1);
    if (v.length > componentSize) throw new Error('Invalid DER signature');
    raw.set(v, componentSize * (n + 1) - v.length);
  });
  return raw.buffer;
}

// Convert JWS ES256 signature (base64url-encoded r||s) to raw bytes
export function jwsSignatureToRaw(signatureB64url) {
  return base64UrlToBytes(signatureB64url).buffer;
}

// Import the P-256 public key from a DER X.509 certificate. null on failure.
export async function importPublicKeyFromCert(certDer) {
  try {
    const cert = parseCertificate(certDer);
    if (cert.curve !== 'P-256') return null;
    return await importCertKey(cert);
  } catch {
    return null;
  }
}
