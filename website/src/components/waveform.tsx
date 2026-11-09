/*
  A faint band of rounded level bars, the horizon detail from the App Store
  screenshots. Deterministic (no randomness at render) so the static export
  and the client match. Busiest in the middle, quieter at the edges.
*/

const WIDTH = 1440;
const PITCH = 14;
const BAR = 6;

function bars(height: number) {
  const out: { x: number; h: number }[] = [];
  let k = 0;
  for (let x = PITCH / 2; x < WIDTH; x += PITCH, k++) {
    const r = Math.abs((Math.sin(k * 12.9898) * 43758.5453) % 1);
    const n = 0.42 + 0.16 * Math.sin(k * 0.61) + 0.1 * Math.sin(k * 0.23 + 2) + 0.38 * (r - 0.4);
    const t = x / WIDTH;
    const env = 0.35 + 0.65 * Math.exp(-Math.pow((t - 0.5) / 0.3, 2));
    out.push({ x, h: Math.max(BAR, height * env * n) });
  }
  return out;
}

export default function Waveform({ height = 96, className = "" }: { height?: number; className?: string }) {
  const H = height + 8;
  return (
    <svg
      viewBox={`0 0 ${WIDTH} ${H}`}
      preserveAspectRatio="xMidYMid slice"
      className={className}
      aria-hidden="true"
      fill="currentColor"
    >
      {bars(height).map(({ x, h }) => (
        <rect key={x} x={x - BAR / 2} y={(H - h) / 2} width={BAR} height={h} rx={BAR / 2} />
      ))}
    </svg>
  );
}
