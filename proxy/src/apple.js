// Verifies Apple-signed App Store records: signed transactions, app
// transactions and App Store Server Notifications v2. Each is a JWS whose
// x5c header carries [leaf, intermediate, root]; the root must be Apple Root
// CA - G3, each certificate must be signed by the next, every certificate must
// be valid at the signing time, and the leaf must sign the JWS (ES256).

import {
  arrayEqual,
  base64ToBytes,
  base64UrlDecode,
  bytesToHex,
  importCertKey,
  isIssuedBy,
  isValidAt,
  jwsSignatureToRaw,
  parseCertificate,
  sha256,
} from './crypto.js';

// SHA-256 of the DER bytes of Apple Root CA - G3
// (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer). Apple puts
// the root itself in x5c, so matching this fingerprint is the same as comparing
// its bytes with an embedded copy.
const APPLE_ROOT_CA_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';

// Marker extensions Apple puts in its App Store signing certificates.
const OID_APPLE_RECEIPT_SIGNING = '1.2.840.113635.100.6.11.1'; // leaf
const OID_APPLE_WWDR_INTERMEDIATE = '1.2.840.113635.100.6.2.1'; // intermediate

const DEFAULT_BUNDLE_ID = 'dev.goodloop.Ramble';
const ACCEPTED_ENVIRONMENTS = ['Production', 'Sandbox']; // never Xcode or local testing

export class AppleVerifyError extends Error {
  constructor(message, reason = 'invalid_transaction') {
    super(message);
    this.name = 'AppleVerifyError';
    this.reason = reason;
  }
}

function fail(message) {
  throw new AppleVerifyError(message);
}

// deps.rootCertDer: a different trusted root (tests). deps.now: clock (ms).
export async function verifyAppleJWS(jws, deps = {}) {
  if (typeof jws !== 'string') fail('Not a JWS');
  const parts = jws.split('.');
  if (parts.length !== 3) fail('Not a JWS');

  let header, payload;
  try {
    header = JSON.parse(base64UrlDecode(parts[0]));
    payload = JSON.parse(base64UrlDecode(parts[1]));
  } catch {
    fail('Unreadable JWS');
  }
  if (header.alg !== 'ES256') fail(`Unexpected algorithm ${header.alg}`);
  if (!payload || typeof payload !== 'object') fail('Unreadable JWS payload');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) fail('x5c must hold leaf, intermediate and root');

  let leaf, intermediate, root;
  try {
    [leaf, intermediate, root] = header.x5c.map((c) => parseCertificate(base64ToBytes(c)));
  } catch (err) {
    fail(`Unreadable certificate: ${err.message}`);
  }

  // The root must be Apple's, byte for byte.
  if (deps.rootCertDer) {
    if (!arrayEqual(root.der, new Uint8Array(deps.rootCertDer))) fail('Chain does not end in the trusted root');
  } else if (bytesToHex(await sha256(root.der)) !== APPLE_ROOT_CA_G3_SHA256) {
    fail('Chain does not end in Apple Root CA - G3');
  }

  if (!(await isIssuedBy(root, root))) fail('Root is not self-signed');
  if (!(await isIssuedBy(intermediate, root))) fail('Intermediate not signed by root');
  if (!(await isIssuedBy(leaf, intermediate))) fail('Leaf not signed by intermediate');

  if (!intermediate.extensions.has(OID_APPLE_WWDR_INTERMEDIATE)) fail('Intermediate is not an Apple WWDR certificate');
  if (!leaf.extensions.has(OID_APPLE_RECEIPT_SIGNING)) fail('Leaf is not an App Store receipt signing certificate');

  // Signing time: signedDate (app transactions: receiptCreationDate), else now.
  const stamp = payload.signedDate ?? payload.receiptCreationDate;
  const signedAt = Number.isFinite(stamp) ? stamp : deps.now ? deps.now() : Date.now();
  for (const cert of [leaf, intermediate, root]) {
    if (!isValidAt(cert, signedAt)) fail('Certificate not valid at signing time');
  }

  if (leaf.curve !== 'P-256') fail('Leaf key is not P-256');
  const signature = jwsSignatureToRaw(parts[2]);
  if (signature.byteLength !== 64) fail('Bad ES256 signature length');
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    await importCertKey(leaf),
    signature,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) fail('Bad JWS signature');

  return payload;
}

function checkBundleAndEnvironment(bundleId, environment, env) {
  const expected = env?.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID;
  if (bundleId !== expected) fail(`Wrong bundle ID ${bundleId}`);
  if (!ACCEPTED_ENVIRONMENTS.includes(environment)) fail(`Environment ${environment} not accepted`);
}

// Returns the decoded JWSTransactionDecodedPayload.
export async function verifySignedTransaction(jws, env, deps = {}) {
  const payload = await verifyAppleJWS(jws, deps);
  checkBundleAndEnvironment(payload.bundleId, payload.environment, env);
  return payload;
}

// Returns the decoded AppTransaction payload, with `environment` filled in from
// `receiptType` when Apple only sends the latter.
export async function verifyAppTransaction(jws, env, deps = {}) {
  const payload = await verifyAppleJWS(jws, deps);
  const environment = payload.environment ?? payload.receiptType;
  checkBundleAndEnvironment(payload.bundleId, environment, env);
  return { ...payload, environment };
}

// body.signedPayload of an App Store Server Notification v2.
export async function verifyNotification(signedPayload, env, deps = {}) {
  const payload = await verifyAppleJWS(signedPayload, deps);
  const data = payload.data;
  if (!data || typeof data !== 'object') fail('Notification has no app data');
  checkBundleAndEnvironment(data.bundleId, data.environment, env);

  let transaction = null;
  if (data.signedTransactionInfo) {
    transaction = await verifySignedTransaction(data.signedTransactionInfo, env, deps);
    if (transaction.environment !== data.environment) fail('Transaction environment differs from notification');
  }

  return {
    notificationType: payload.notificationType,
    subtype: payload.subtype ?? null,
    notificationUUID: payload.notificationUUID ?? null,
    environment: data.environment,
    transaction,
  };
}
