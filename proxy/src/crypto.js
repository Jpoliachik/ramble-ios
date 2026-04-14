// Crypto utilities for JWS verification (Apple StoreKit subscription validation).
// App Attest verification is handled by node-app-attest.

export function base64UrlDecode(str) {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  return atob(padded);
}

export function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// Convert JWS ES256 signature (base64url-encoded r||s) to raw bytes
export function jwsSignatureToRaw(signatureB64url) {
  const decoded = base64UrlDecode(signatureB64url);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i++) {
    bytes[i] = decoded.charCodeAt(i);
  }
  return bytes.buffer;
}

// Extract SubjectPublicKeyInfo from a DER-encoded X.509 certificate and
// import as a P-256 ECDSA key. Used for JWS leaf cert verification.
export async function importPublicKeyFromCert(certDer) {
  try {
    const certBytes = new Uint8Array(certDer);
    const ecPublicKeyOid = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];

    let oidIndex = -1;
    for (let i = 0; i < certBytes.length - ecPublicKeyOid.length; i++) {
      let match = true;
      for (let j = 0; j < ecPublicKeyOid.length; j++) {
        if (certBytes[i + j] !== ecPublicKeyOid[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        oidIndex = i;
        break;
      }
    }

    if (oidIndex === -1) return null;

    let spkiStart = -1;
    for (let i = oidIndex - 1; i >= Math.max(0, oidIndex - 10); i--) {
      if (certBytes[i] === 0x30) {
        const lenInfo = readAsn1Length(certBytes, i + 1);
        if (lenInfo && i + 1 + lenInfo.bytesUsed + lenInfo.length > oidIndex + ecPublicKeyOid.length + 20) {
          spkiStart = i;
          break;
        }
      }
    }

    if (spkiStart === -1) return null;

    const spkiLenInfo = readAsn1Length(certBytes, spkiStart + 1);
    if (!spkiLenInfo) return null;

    const spkiEnd = spkiStart + 1 + spkiLenInfo.bytesUsed + spkiLenInfo.length;
    const spkiBytes = certBytes.slice(spkiStart, spkiEnd);

    return await crypto.subtle.importKey(
      'spki',
      spkiBytes.buffer,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    );
  } catch {
    return null;
  }
}

function readAsn1Length(bytes, offset) {
  if (offset >= bytes.length) return null;
  const first = bytes[offset];
  if (first < 0x80) {
    return { length: first, bytesUsed: 1 };
  }
  const numBytes = first & 0x7f;
  if (numBytes === 0 || offset + numBytes >= bytes.length) return null;
  let length = 0;
  for (let i = 1; i <= numBytes; i++) {
    length = (length << 8) | bytes[offset + i];
  }
  return { length, bytesUsed: 1 + numBytes };
}
