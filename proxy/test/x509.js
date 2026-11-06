// Test-only X.509 builder: makes small EC certificate chains with node:crypto
// so the Apple JWS and App Attest verifiers can be tested against chains we
// control (a fake "Apple" root, a non-Apple root, missing marker extensions).

import { generateKeyPairSync, sign } from 'node:crypto';

function len(n) {
  if (n < 0x80) return [n];
  const out = [];
  while (n > 0) { out.unshift(n & 0xff); n >>= 8; }
  return [0x80 | out.length, ...out];
}
export function tlv(tag, ...parts) {
  const body = Buffer.concat(parts.map((p) => Buffer.from(p)));
  return Buffer.concat([Buffer.from([tag, ...len(body.length)]), body]);
}
const seq = (...p) => tlv(0x30, ...p);
export const octets = (b) => tlv(0x04, b);
function oid(dotted) {
  const [a, b, ...rest] = dotted.split('.').map(Number);
  const bytes = [40 * a + b];
  for (const v of rest) {
    const chunk = [v & 0x7f];
    for (let x = v >> 7; x > 0; x >>= 7) chunk.unshift(0x80 | (x & 0x7f));
    bytes.push(...chunk);
  }
  return tlv(0x06, bytes);
}
function time(ms) {
  const s = new Date(ms).toISOString().replace(/[-:T]/g, '').slice(0, 14);
  return tlv(0x18, Buffer.from(`${s}Z`)); // GeneralizedTime
}
const name = (cn) => seq(tlv(0x31, seq(oid('2.5.4.3'), tlv(0x0c, Buffer.from(cn)))));

export function ecKey(curve) {
  return generateKeyPairSync('ec', { namedCurve: curve === 'P-384' ? 'secp384r1' : 'prime256v1' });
}

// Makes a DER certificate for `key` signed by `issuer` ({ name, privateKey }),
// or self-signed when issuer is omitted. extensions: [[oid, Buffer value]].
export function makeCert({
  cn,
  key,
  issuer,
  hash = 'sha384',
  notBefore = Date.UTC(2020, 0, 1),
  notAfter = Date.UTC(2040, 0, 1),
  extensions = [],
}) {
  const signer = issuer || { cn, privateKey: key.privateKey };
  const sigAlg = seq(oid(hash === 'sha384' ? '1.2.840.10045.4.3.3' : '1.2.840.10045.4.3.2'));
  const spki = key.publicKey.export({ type: 'spki', format: 'der' });
  const exts = extensions.length
    ? [tlv(0xa3, seq(...extensions.map(([id, value]) => seq(oid(id), octets(value)))))]
    : [];
  const tbs = seq(
    tlv(0xa0, tlv(0x02, [2])),
    tlv(0x02, [1]),
    sigAlg,
    name(signer.cn),
    seq(time(notBefore), time(notAfter)),
    name(cn),
    spki,
    ...exts,
  );
  const signature = sign(hash, tbs, { key: signer.privateKey, dsaEncoding: 'der' });
  return seq(tbs, sigAlg, tlv(0x03, Buffer.concat([Buffer.from([0]), signature])));
}

// A CA: key pair plus certificate, usable as `issuer` for makeCert.
export function makeCA({ cn, issuer, curve = 'P-384', extensions = [], ...rest }) {
  const key = ecKey(curve);
  const der = makeCert({ cn, key, issuer, extensions, ...rest });
  return { cn, der, key, privateKey: key.privateKey };
}
