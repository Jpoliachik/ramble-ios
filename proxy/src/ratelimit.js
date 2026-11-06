// Fixed-window rate limiter backed by D1. Stub: the signatures are the contract.

export async function hit(db, key, limit, windowSeconds, now = Date.now()) {
  return { ok: true };
}

export async function peek(db, key, limit, windowSeconds, now = Date.now()) {
  return { ok: true };
}

// Network address for limiter keys only. Never store or log it.
export function clientAddress(request) {
  return request.headers.get('CF-Connecting-IP') || 'unknown';
}
