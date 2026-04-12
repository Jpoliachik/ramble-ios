// Anonymous usage analytics via Cloudflare Analytics Engine.
//
// What we track: model popularity, request volume, file sizes, success/failure rates.
// What we DON'T track: audio content, transcription text, IP addresses, or any PII.
//
// Device IDs are SHA-256 hashed before writing so we can count unique devices
// without being able to identify anyone.

/**
 * Hash a device ID to a non-reversible string for anonymous unique-user counting.
 */
export async function hashDeviceId(deviceId) {
  const data = new TextEncoder().encode(deviceId);
  const hash = await crypto.subtle.digest('SHA-256', data);
  const bytes = new Uint8Array(hash);
  return Array.from(bytes.slice(0, 16))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Write a transcription event to Analytics Engine.
 *
 * Data point schema:
 *   index1  — hashed device ID (for unique-user queries)
 *   blob1   — model name (e.g. "whisper-large-v3-turbo")
 *   blob2   — provider (e.g. "groq", "deepgram", "openai")
 *   blob3   — outcome ("success" or "error")
 *   blob4   — error detail (empty on success)
 *   double1 — audio file size in bytes
 *   double2 — transcript character length (0 on error)
 *   double3 — processing duration in ms
 */
export async function writeTranscriptionEvent(env, { deviceId, model, audioSize, textLength, durationMs, error }) {
  if (!env.USAGE_ANALYTICS) return;

  const hashedId = await hashDeviceId(deviceId);

  const provider = model.startsWith('deepgram-')
    ? 'deepgram'
    : model.startsWith('openai-')
      ? 'openai'
      : 'groq';

  env.USAGE_ANALYTICS.writeDataPoint({
    indexes: [hashedId],
    blobs: [model, provider, error ? 'error' : 'success', error || ''],
    doubles: [audioSize || 0, textLength || 0, durationMs || 0],
  });
}
