// Reads the length of an uploaded recording from its container.
// Supports MP4/M4A (mvhd, falling back to the audio track's mdhd) and raw
// ADTS AAC (frame count). Never throws: unreadable input gives null.

// Seconds of audio, or null if the container can't be read.
export function measureDurationSeconds(bytes) {
  try {
    if (!(bytes instanceof Uint8Array)) {
      if (bytes instanceof ArrayBuffer) bytes = new Uint8Array(bytes);
      else return null;
    }
    if (bytes.length < 8) return null;
    if (isAdtsSync(bytes, 0)) return adtsDuration(bytes);
    return mp4Duration(bytes);
  } catch {
    return null;
  }
}

// --- MP4 / M4A ---

function mp4Duration(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const moov = findBox(bytes, view, 0, bytes.length, 'moov');
  if (!moov) return null;

  const mvhd = findBox(bytes, view, moov.start, moov.end, 'mvhd');
  const fromMvhd = mvhd ? readHeaderDuration(view, mvhd) : null;
  if (fromMvhd !== null) return fromMvhd;

  // mvhd missing or zero (some writers leave it empty): use the audio track.
  for (const trak of childBoxes(bytes, view, moov.start, moov.end, 'trak')) {
    const mdia = findBox(bytes, view, trak.start, trak.end, 'mdia');
    if (!mdia) continue;
    const hdlr = findBox(bytes, view, mdia.start, mdia.end, 'hdlr');
    // hdlr: version/flags (4), pre_defined (4), handler_type (4).
    if (hdlr && hdlr.end - hdlr.start >= 12 && fourcc(bytes, hdlr.start + 8) !== 'soun') continue;
    const mdhd = findBox(bytes, view, mdia.start, mdia.end, 'mdhd');
    const seconds = mdhd ? readHeaderDuration(view, mdhd) : null;
    if (seconds !== null) return seconds;
  }
  return null;
}

// mvhd and mdhd share the layout we need:
// v0: version/flags(4) created(4) modified(4) timescale(4) duration(4)
// v1: version/flags(4) created(8) modified(8) timescale(4) duration(8)
function readHeaderDuration(view, box) {
  const size = box.end - box.start;
  const version = view.getUint8(box.start);
  let timescale;
  let duration;
  if (version === 1) {
    if (size < 32) return null;
    timescale = view.getUint32(box.start + 20);
    const raw = view.getBigUint64(box.start + 24);
    if (raw === 0xffffffffffffffffn) return null; // "unknown"
    duration = Number(raw);
  } else if (version === 0) {
    if (size < 20) return null;
    timescale = view.getUint32(box.start + 12);
    duration = view.getUint32(box.start + 16);
    if (duration === 0xffffffff) return null; // "unknown"
  } else {
    return null;
  }
  if (!timescale || !duration) return null;
  const seconds = duration / timescale;
  return Number.isFinite(seconds) ? seconds : null;
}

// The first box of `type` directly inside [start, end), or null.
function findBox(bytes, view, start, end, type) {
  for (const box of childBoxes(bytes, view, start, end, type)) return box;
  return null;
}

// Child boxes of `type` in [start, end). Each yields { start, end } of the
// box's payload. Stops at the first malformed header, so garbage or truncated
// input ends the walk instead of looping.
function* childBoxes(bytes, view, start, end, type) {
  let offset = start;
  while (offset + 8 <= end) {
    let size = view.getUint32(offset);
    const boxType = fourcc(bytes, offset + 4);
    let header = 8;
    if (size === 1) {
      if (offset + 16 > end) return;
      size = Number(view.getBigUint64(offset + 8));
      header = 16;
    } else if (size === 0) {
      size = end - offset; // box runs to the end of its parent
    }
    if (size < header) return;
    const boxEnd = Math.min(offset + size, end);
    if (boxType === type) yield { start: offset + header, end: boxEnd };
    offset += size; // size >= 8, so the walk always moves forward
  }
}

function fourcc(bytes, offset) {
  return String.fromCharCode(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
}

// --- ADTS AAC ---

const ADTS_SAMPLE_RATES = [
  96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350,
];

function isAdtsSync(bytes, offset) {
  // 12-bit syncword 0xFFF and layer bits 00.
  return offset + 1 < bytes.length && bytes[offset] === 0xff && (bytes[offset + 1] & 0xf6) === 0xf0;
}

function adtsDuration(bytes) {
  let offset = 0;
  let frames = 0;
  let sampleRate = null;
  while (offset + 7 <= bytes.length && isAdtsSync(bytes, offset)) {
    const rateIndex = (bytes[offset + 2] >> 2) & 0x0f;
    const rate = ADTS_SAMPLE_RATES[rateIndex];
    if (!rate) break;
    sampleRate ??= rate;
    const frameLength =
      ((bytes[offset + 3] & 0x03) << 11) | (bytes[offset + 4] << 3) | (bytes[offset + 5] >> 5);
    if (frameLength < 7) break;
    // Raw data blocks per frame minus one; each block is 1024 samples.
    const blocks = (bytes[offset + 6] & 0x03) + 1;
    frames += blocks;
    offset += frameLength;
  }
  if (!frames || !sampleRate) return null;
  return (frames * 1024) / sampleRate;
}
