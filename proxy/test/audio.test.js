// measureDurationSeconds on tiny synthetic MP4 and ADTS files.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { measureDurationSeconds } from '../src/audio.js';

// --- Builders ---

function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

function box(type, ...payload) {
  const body = concat(...payload);
  const out = new Uint8Array(8 + body.length);
  new DataView(out.buffer).setUint32(0, out.length);
  for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
  out.set(body, 8);
  return out;
}

// mvhd/mdhd payload: version 0 (32-bit) or 1 (64-bit times and duration).
function header(version, timescale, duration, trailing = 0) {
  if (version === 1) {
    const b = new Uint8Array(32 + trailing);
    const v = new DataView(b.buffer);
    b[0] = 1;
    v.setUint32(20, timescale);
    v.setBigUint64(24, BigInt(duration));
    return b;
  }
  const b = new Uint8Array(20 + trailing);
  const v = new DataView(b.buffer);
  v.setUint32(12, timescale);
  v.setUint32(16, duration);
  return b;
}

function hdlr(handler) {
  const b = new Uint8Array(24);
  for (let i = 0; i < 4; i++) b[8 + i] = handler.charCodeAt(i);
  return b;
}

const ftyp = box('ftyp', new TextEncoder().encode('M4A \0\0\0\0'));
const mdat = box('mdat', new Uint8Array(64));

function adtsFrame(rateIndex, frameLength = 20, blocks = 1) {
  const b = new Uint8Array(frameLength);
  b[0] = 0xff;
  b[1] = 0xf1; // MPEG-4, layer 0, no CRC
  b[2] = (1 << 6) | (rateIndex << 2); // AAC LC profile
  b[3] = (frameLength >> 11) & 0x03;
  b[4] = (frameLength >> 3) & 0xff;
  b[5] = ((frameLength & 0x07) << 5) | 0x1f;
  b[6] = 0xfc | ((blocks - 1) & 0x03);
  return b;
}

// --- Tests ---

describe('measureDurationSeconds: MP4', () => {
  it('reads mvhd version 0', () => {
    const file = concat(ftyp, box('moov', box('mvhd', header(0, 1000, 42_500, 80))), mdat);
    assert.equal(measureDurationSeconds(file), 42.5);
  });

  it('reads mvhd version 1', () => {
    const file = concat(ftyp, mdat, box('moov', box('mvhd', header(1, 16000, 16000 * 3600))));
    assert.equal(measureDurationSeconds(file), 3600);
  });

  it('falls back to the audio track mdhd when mvhd has no duration', () => {
    const video = box('trak', box('mdia', box('hdlr', hdlr('vide')), box('mdhd', header(0, 600, 600))));
    const audio = box('trak', box('mdia', box('hdlr', hdlr('soun')), box('mdhd', header(1, 16000, 16000 * 90))));
    const file = concat(ftyp, box('moov', box('mvhd', header(0, 1000, 0)), video, audio), mdat);
    assert.equal(measureDurationSeconds(file), 90);
  });

  it('handles a 64-bit box size and a size-0 last box', () => {
    const mvhd = box('mvhd', header(0, 10, 25));
    const big = new Uint8Array(16 + mvhd.length);
    const v = new DataView(big.buffer);
    v.setUint32(0, 1);
    big.set(new TextEncoder().encode('moov'), 4);
    v.setBigUint64(8, BigInt(big.length));
    big.set(mvhd, 16);
    assert.equal(measureDurationSeconds(concat(ftyp, big)), 2.5);

    const open = box('moov', mvhd);
    new DataView(open.buffer).setUint32(0, 0);
    assert.equal(measureDurationSeconds(concat(ftyp, open)), 2.5);
  });

  it('accepts an ArrayBuffer', () => {
    const file = concat(ftyp, box('moov', box('mvhd', header(0, 1, 7))));
    assert.equal(measureDurationSeconds(file.buffer), 7);
  });

  it('returns null without a moov', () => {
    assert.equal(measureDurationSeconds(concat(ftyp, mdat)), null);
  });
});

describe('measureDurationSeconds: ADTS', () => {
  it('counts frames x 1024 / sample rate', () => {
    // 16 kHz is index 8. 125 frames of 1024 samples = 8 seconds.
    const frames = Array.from({ length: 125 }, () => adtsFrame(8));
    assert.equal(measureDurationSeconds(concat(...frames)), 8);
  });

  it('counts multiple raw data blocks per frame', () => {
    const frames = Array.from({ length: 10 }, () => adtsFrame(8, 30, 2));
    assert.equal(measureDurationSeconds(concat(...frames)), (20 * 1024) / 16000);
  });

  it('stops at a truncated last frame', () => {
    const file = concat(adtsFrame(3), adtsFrame(3), adtsFrame(3).slice(0, 5));
    assert.equal(measureDurationSeconds(file), (2 * 1024) / 48000);
  });
});

describe('measureDurationSeconds: garbage', () => {
  it('never throws and returns null for unreadable input', () => {
    const cases = [
      undefined,
      null,
      'not bytes',
      new Uint8Array(0),
      new Uint8Array(4),
      new Uint8Array(1000), // all zero: size-0 box runs to the end, no moov
      new Uint8Array(1000).fill(0xff),
      new Uint8Array([0, 0, 0, 3, 0x6d, 0x6f, 0x6f, 0x76]), // size < header
      new Uint8Array([0xff, 0xf1, 0x7c, 0, 0, 0, 0, 0]), // ADTS with bad rate/length
    ];
    for (const input of cases) assert.equal(measureDurationSeconds(input), null);
  });

  it('survives truncation at every byte of a valid file', () => {
    const file = concat(ftyp, box('moov', box('mvhd', header(1, 1000, 5000)), box('trak', box('mdia', box('mdhd', header(0, 1, 5))))));
    for (let n = 0; n <= file.length; n++) {
      const out = measureDurationSeconds(file.slice(0, n));
      assert.ok(out === null || out === 5, `length ${n} gave ${out}`);
    }
  });

  it('survives random bytes', () => {
    let seed = 1;
    const rand = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) & 0xff;
    for (let i = 0; i < 200; i++) {
      const bytes = Uint8Array.from({ length: 64 + (i % 50) }, rand);
      const out = measureDurationSeconds(bytes);
      assert.ok(out === null || Number.isFinite(out));
    }
  });
});
