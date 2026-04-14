// Apple App Attest: challenge issuance, attestation registration,
// and per-request assertion verification.
// Uses node-app-attest for all cryptographic verification.

import { verifyAttestation, verifyAssertion as libVerifyAssertion } from 'node-app-attest';

const CHALLENGE_TTL_SECONDS = 300;
const BUNDLE_ID = 'dev.goodloop.ramble';
const TEAM_ID = 'SW6VLKWS7Q';

// --- Challenge Endpoint ---

export async function handleAttestChallenge(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  const challengeBytes = new Uint8Array(32);
  crypto.getRandomValues(challengeBytes);
  const challenge = Buffer.from(challengeBytes).toString('base64');

  await env.ATTEST_KV.put(`challenge:${challenge}`, deviceId, {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });

  console.log(`[attest] Challenge issued device=${deviceId}`);
  return { challenge };
}

// --- Attestation Registration Endpoint ---

export async function handleAttest(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  let body;
  try {
    body = await request.json();
  } catch {
    return { error: 'Invalid JSON body', status: 400 };
  }

  const { keyId, attestation, challenge } = body;
  if (!keyId || !attestation || !challenge) {
    return { error: 'Missing keyId, attestation, or challenge', status: 400 };
  }

  // Verify the challenge was issued by us and belongs to this device
  const storedDeviceId = await env.ATTEST_KV.get(`challenge:${challenge}`);
  if (!storedDeviceId) {
    return { error: 'Invalid or expired challenge', status: 403 };
  }
  if (storedDeviceId !== deviceId) {
    console.error(`[attest] Challenge device mismatch: issued=${storedDeviceId} requesting=${deviceId}`);
    return { error: 'Challenge was issued to a different device', status: 403 };
  }
  await env.ATTEST_KV.delete(`challenge:${challenge}`);

  try {
    const result = verifyAttestation({
      attestation: Buffer.from(attestation, 'base64'),
      challenge,
      keyId,
      bundleIdentifier: BUNDLE_ID,
      teamIdentifier: TEAM_ID,
      allowDevelopmentEnvironment: true,
    });

    // Store the credential for future assertion verification
    await env.ATTEST_KV.put(
      `key:${keyId}`,
      JSON.stringify({
        publicKey: result.publicKey,
        counter: 0,
        attestedAt: Date.now(),
        environment: result.environment,
      }),
    );

    console.log(`[attest] Device attested device=${deviceId} keyId=${keyId.substring(0, 8)}... env=${result.environment}`);
    return { status: 'ok' };
  } catch (err) {
    console.error(`[attest] Attestation rejected: ${err.message} device=${deviceId}`);
    return { error: `Attestation rejected: ${err.message}`, status: 403 };
  }
}

// --- Assertion Verification (called from transcribe handler) ---

export async function verifyAssertionForRequest(keyId, assertionB64, requestBody, env) {
  try {
    const storedRaw = await env.ATTEST_KV.get(`key:${keyId}`);
    if (!storedRaw) {
      return { valid: false, reason: 'Unknown key — device not attested' };
    }
    const stored = JSON.parse(storedRaw);

    const result = libVerifyAssertion({
      assertion: Buffer.from(assertionB64, 'base64'),
      payload: Buffer.from(requestBody),
      publicKey: stored.publicKey,
      bundleIdentifier: BUNDLE_ID,
      teamIdentifier: TEAM_ID,
      signCount: stored.counter,
    });

    // Update the stored counter
    stored.counter = result.signCount;
    await env.ATTEST_KV.put(`key:${keyId}`, JSON.stringify(stored));

    return { valid: true };
  } catch (err) {
    return { valid: false, reason: err.message };
  }
}
