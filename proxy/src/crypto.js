// Crypto utilities for certificate parsing, DER/ASN.1 handling,
// and signature conversion. Used by JWS verification and App Attest.

export function base64UrlDecode(str) {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return atob(padded);
}

export function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
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

export function readAsn1Length(bytes, offset) {
  if (offset >= bytes.length) return null;
  const first = bytes[offset];
  if (first < 0x80) return { length: first, bytesUsed: 1 };
  const numBytes = first & 0x7f;
  if (numBytes === 0 || offset + numBytes >= bytes.length) return null;
  let length = 0;
  for (let i = 1; i <= numBytes; i++) length = (length << 8) | bytes[offset + i];
  return { length, bytesUsed: 1 + numBytes };
}

// Convert DER-encoded ECDSA signature to raw r||s format for WebCrypto.
export function derSignatureToRaw(derSig, componentSize = 32) {
  if (derSig[0] !== 0x30) throw new Error('Invalid DER signature');
  let offset = 2;
  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER tag for r');
  offset++;
  const rLen = derSig[offset]; offset++;
  let r = derSig.slice(offset, offset + rLen); offset += rLen;
  if (derSig[offset] !== 0x02) throw new Error('Expected INTEGER tag for s');
  offset++;
  const sLen = derSig[offset]; offset++;
  let s = derSig.slice(offset, offset + sLen);
  while (r.length > componentSize && r[0] === 0) r = r.slice(1);
  while (s.length > componentSize && s[0] === 0) s = s.slice(1);
  const raw = new Uint8Array(componentSize * 2);
  raw.set(r, componentSize - r.length);
  raw.set(s, componentSize * 2 - s.length);
  return raw.buffer;
}

// Convert JWS ES256 signature (base64url-encoded r||s) to raw bytes
export function jwsSignatureToRaw(signatureB64url) {
  const decoded = base64UrlDecode(signatureB64url);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i++) bytes[i] = decoded.charCodeAt(i);
  return bytes.buffer;
}

// --- SPKI extraction helpers (shared by P-256 and P-384 importers) ---

function findSpki(certBytes) {
  const ecPublicKeyOid = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];
  let oidIndex = -1;
  for (let i = 0; i < certBytes.length - ecPublicKeyOid.length; i++) {
    let match = true;
    for (let j = 0; j < ecPublicKeyOid.length; j++) {
      if (certBytes[i + j] !== ecPublicKeyOid[j]) { match = false; break; }
    }
    if (match) { oidIndex = i; break; }
  }
  if (oidIndex === -1) return null;

  for (let i = oidIndex - 1; i >= Math.max(0, oidIndex - 10); i--) {
    if (certBytes[i] === 0x30) {
      const lenInfo = readAsn1Length(certBytes, i + 1);
      if (lenInfo && i + 1 + lenInfo.bytesUsed + lenInfo.length > oidIndex + ecPublicKeyOid.length + 20) {
        const spkiLenInfo = readAsn1Length(certBytes, i + 1);
        if (!spkiLenInfo) return null;
        const spkiEnd = i + 1 + spkiLenInfo.bytesUsed + spkiLenInfo.length;
        return certBytes.slice(i, spkiEnd);
      }
    }
  }
  return null;
}

// Import P-256 public key from DER X.509 certificate
export async function importPublicKeyFromCert(certDer) {
  try {
    const spkiBytes = findSpki(new Uint8Array(certDer));
    if (!spkiBytes) return null;
    return await crypto.subtle.importKey('spki', spkiBytes.buffer, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  } catch { return null; }
}

// Same as above but exportable (for extracting raw key bytes during attestation)
export async function importPublicKeyFromCertExportable(certDer) {
  try {
    const spkiBytes = findSpki(new Uint8Array(certDer));
    if (!spkiBytes) return null;
    return await crypto.subtle.importKey('spki', spkiBytes.buffer, { name: 'ECDSA', namedCurve: 'P-256' }, true, ['verify']);
  } catch { return null; }
}

// Import P-384 public key from DER X.509 certificate (for Apple Root CA / intermediate)
export async function importP384PublicKeyFromCert(certDer) {
  try {
    const spkiBytes = findSpki(new Uint8Array(certDer));
    if (!spkiBytes) return null;
    return await crypto.subtle.importKey('spki', spkiBytes.buffer, { name: 'ECDSA', namedCurve: 'P-384' }, false, ['verify']);
  } catch { return null; }
}

// Verify that a DER certificate was signed by the given issuer public key.
export async function verifyCertSignature(certDer, issuerKey, curve, hash) {
  try {
    const bytes = certDer instanceof Uint8Array ? certDer : new Uint8Array(certDer);
    if (bytes[0] !== 0x30) return false;
    const outerLen = readAsn1Length(bytes, 1);
    if (!outerLen) return false;

    let tbsStart = 1 + outerLen.bytesUsed;
    if (bytes[tbsStart] !== 0x30) return false;
    const tbsLen = readAsn1Length(bytes, tbsStart + 1);
    if (!tbsLen) return false;
    const tbsEnd = tbsStart + 1 + tbsLen.bytesUsed + tbsLen.length;
    const tbsBytes = bytes.slice(tbsStart, tbsEnd);

    let sigAlgStart = tbsEnd;
    if (bytes[sigAlgStart] !== 0x30) return false;
    const sigAlgLen = readAsn1Length(bytes, sigAlgStart + 1);
    if (!sigAlgLen) return false;
    const sigAlgEnd = sigAlgStart + 1 + sigAlgLen.bytesUsed + sigAlgLen.length;

    if (bytes[sigAlgEnd] !== 0x03) return false;
    const sigBitLen = readAsn1Length(bytes, sigAlgEnd + 1);
    if (!sigBitLen) return false;
    const sigStart = sigAlgEnd + 1 + sigBitLen.bytesUsed + 1;
    const sigEnd = sigAlgEnd + 1 + sigBitLen.bytesUsed + sigBitLen.length;
    const signatureDer = bytes.slice(sigStart, sigEnd);

    const useCurve = curve || 'P-256';
    const useHash = hash || 'SHA-256';
    const componentSize = useCurve === 'P-384' ? 48 : 32;
    const rawSig = derSignatureToRaw(signatureDer, componentSize);

    return await crypto.subtle.verify({ name: 'ECDSA', hash: useHash }, issuerKey, rawSig, tbsBytes);
  } catch {
    return false;
  }
}
