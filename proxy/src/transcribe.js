// Transcription providers, fallback and formatting for uploaded notes.
// See specs/transcription.md. Stub: the signatures are the contract.

export class TranscribeError extends Error {
  constructor(message, { retryable, provider = null, status = null } = {}) {
    super(message);
    this.name = 'TranscribeError';
    this.retryable = retryable;
    this.provider = provider;
    this.status = status;
  }
}

// Resolves { result: 'transcript' | 'no_speech', text, provider, model }.
// Rejects with TranscribeError.
export async function transcribeNote(audio, opts, env, deps = {}) {
  throw new TranscribeError('Not implemented', { retryable: true });
}
