// Old builds' cloud transcription for early subscribers: POST /transcribe.
// Works until LEGACY_RETIRES_AT, then 410 (see the router). Needs App Attest
// and an unexpired, unrevoked subscription record, adds to the monthly usage
// tally per original transaction (monitoring only), is refused when that
// purchase is suspended, and always uses Groq whatever model the old app asks
// for. See specs/relay-api.md "Old app versions".

import { recordUsage, suspendedResponse } from './account.js';
import { AppleVerifyError } from './apple.js';
import { bearerValue, fail, json, logId, unavailable } from './http.js';
import { MAX_SECONDS, MAX_UPLOAD_BYTES } from './notes.js';
import { TranscribeError } from './transcribe.js';

const DEFAULT_PREMIUM_PRODUCT = 'dev.goodloop.ramble.premium.monthly2';
const SUBSCRIPTION_REQUIRED = 'Premium subscription required';

/** Old builds' POST /transcribe and text POST /inbox answer 410 from then on. */
export const LEGACY_RETIRES_AT = Date.parse('2027-01-07T00:00:00Z');

export function legacyOpen(ctx) {
  return ctx.now < LEGACY_RETIRES_AT;
}

export async function legacyTranscribe(request, ctx) {
  const keyId = request.headers.get('X-App-Attest-Key-Id');
  const assertion = request.headers.get('X-App-Attest');
  if (!keyId || !assertion) return fail(403, 'App attestation required');
  if (Number(request.headers.get('Content-Length')) > MAX_UPLOAD_BYTES) {
    return fail(413, 'Recordings must be at most 20 MB.', 'too_large');
  }

  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_UPLOAD_BYTES) return fail(413, 'Recordings must be at most 20 MB.', 'too_large');
  const attested = await ctx.verifyAssertion(keyId, assertion, body, ctx.env);
  if (attested?.unavailable) return unavailable();
  if (!attested?.valid) {
    console.error(`[legacy] attestation failed key=${await logId(keyId)}`);
    return fail(403, 'App attestation failed');
  }

  let tx;
  try {
    tx = await ctx.apple.verifySignedTransaction(bearerValue(request), ctx.env, ctx.appleDeps);
  } catch (err) {
    if (err instanceof AppleVerifyError && err.reason !== 'unavailable') {
      return fail(403, SUBSCRIPTION_REQUIRED, err.reason || 'invalid_transaction');
    }
    return unavailable();
  }
  if (
    tx.productId !== (ctx.env.PREMIUM_PRODUCT_ID || DEFAULT_PREMIUM_PRODUCT) ||
    tx.revocationDate ||
    !(Number(tx.expiresDate) > ctx.now) ||
    !tx.originalTransactionId
  ) {
    return fail(403, SUBSCRIPTION_REQUIRED, 'invalid_transaction');
  }
  const purchaseId = `sub:${tx.originalTransactionId}`;
  const purchase = await ctx.db.prepare('SELECT suspended FROM purchases WHERE id = ?').bind(purchaseId).first();
  if (purchase?.suspended) return suspendedResponse();

  let audio;
  let options;
  try {
    const form = await new Response(body, { headers: { 'Content-Type': request.headers.get('Content-Type') || '' } }).formData();
    audio = form.get('audio');
    if (!audio || typeof audio === 'string') return fail(400, 'Missing "audio" file field');
    options = {
      language: String(form.get('language') || '').trim().toLowerCase() || null,
      removeFillerWords: form.get('remove_filler_words') === 'true',
      vocabulary: String(form.get('vocabulary') || '').slice(0, 900),
    };
  } catch {
    return fail(400, 'Invalid multipart form data');
  }
  const bytes = new Uint8Array(await audio.arrayBuffer());
  const measured = ctx.measureDuration(bytes);
  if (measured != null && measured > MAX_SECONDS) return fail(413, 'Recordings must be at most 60 minutes.', 'too_long');

  let out;
  try {
    out = await ctx.transcribe(
      bytes.buffer,
      { contentType: audio.type || 'audio/mp4', ...options, durationSeconds: measured },
      ctx.env,
      ctx.transcribeDeps,
    );
  } catch (err) {
    console.error(`[legacy] transcription failed provider=${err?.provider ?? '-'}: ${String(err?.message).slice(0, 200)}`);
    if (err instanceof TranscribeError && err.retryable === false) return fail(400, 'Transcription failed');
    return fail(503, 'Transcription service unavailable');
  }

  await recordUsage(ctx, purchaseId, out.durationSeconds ?? measured ?? 0);
  return json({ text: out.result === 'no_speech' ? '' : String(out.text ?? '') });
}
