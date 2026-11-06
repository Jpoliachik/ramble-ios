// Verifies Apple-signed App Store records (JWS with an x5c chain to Apple's
// root CA). Stub: the signatures are the contract.

export class AppleVerifyError extends Error {
  constructor(message, reason = 'invalid_transaction') {
    super(message);
    this.name = 'AppleVerifyError';
    this.reason = reason;
  }
}

export async function verifyAppleJWS(jws, deps = {}) {
  throw new AppleVerifyError('Not implemented');
}

export async function verifySignedTransaction(jws, env, deps = {}) {
  throw new AppleVerifyError('Not implemented');
}

export async function verifyAppTransaction(jws, env, deps = {}) {
  throw new AppleVerifyError('Not implemented');
}

export async function verifyNotification(signedPayload, env, deps = {}) {
  throw new AppleVerifyError('Not implemented');
}
