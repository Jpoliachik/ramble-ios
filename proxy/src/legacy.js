// Old builds' cloud transcription for early subscribers: POST /transcribe.
// Works until LEGACY_UNTIL, then 410 (see the router). Needs App Attest and
// an unexpired subscription record checked like POST /entitlement, counts
// toward 100 hours a month per original transaction, and always uses the
// default provider chain whatever model the old app asks for.
// See specs/relay-api.md "Old app versions".

import { AppleVerifyError } from './apple.js';
import { limit } from './auth.js';
import { bearerValue, fail, json, logId, nextMonthStart, unavailable, utcMonth } from './http.js';
import { MAX_SECONDS, MAX_UPLOAD_BYTES } from './notes.js';
import { FAIR_USE_SECONDS } from './ops.js';
import { TranscribeError } from './transcribe.js';

const DEFAULT_PREMIUM_PRODUCT = 'dev.goodloop.ramble.premium.monthly2';
const SUBSCRIPTION_REQUIRED = 'Premium subscription required';

export function legacyOpen(ctx) {
  const until = Date.parse(ctx.env.LEGACY_UNTIL ?? '');
  return !Number.isFinite(until) || ctx.now < until;
}

export async function legacyTranscribe(request, ctx) {
  const keyId = request.headers.get('X-App-Attest-Key-Id');
  const assertion = request.headers.get('X-App-Attest');
  if (!keyId || !assertion) return fail(403, 'App attestation required');
  if (Number(request.headers.get('Content-Length')) > MAX_UPLOAD_BYTES) {
    return fail(413, 'Recordings must be at most 20 MB.', 'too_large');
  }
  const limited = await limit(ctx, ['notes_hour', `attest:${keyId}`], ['notes_day', `attest:${keyId}`]);
  if (limited) return limited;

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
  const revoked = await ctx.db.prepare('SELECT revoked_at FROM purchases WHERE id = ?').bind(purchaseId).first();
  if (revoked?.revoked_at != null) return fail(403, SUBSCRIPTION_REQUIRED, 'invalid_transaction');

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

  const month = utcMonth(ctx.now);
  const used = await ctx.db
    .prepare('SELECT seconds FROM fair_use WHERE purchase_id = ? AND month = ?')
    .bind(purchaseId, month)
    .first();
  if ((used?.seconds ?? 0) >= FAIR_USE_SECONDS) {
    const retryAfter = Math.ceil((nextMonthStart(ctx.now) - ctx.now) / 1000);
    return fail(402, 'This subscription used its 100 hours of audio this month.', 'fair_use', {}, { 'Retry-After': String(retryAfter) });
  }

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

  const seconds = out.durationSeconds ?? measured ?? 0;
  await ctx.db
    .prepare(
      `INSERT INTO fair_use (purchase_id, month, seconds) VALUES (?, ?, ?)
         ON CONFLICT (purchase_id, month) DO UPDATE SET seconds = seconds + excluded.seconds`,
    )
    .bind(purchaseId, month, seconds)
    .run();
  return json({ text: out.result === 'no_speech' ? '' : String(out.text ?? '') });
}
