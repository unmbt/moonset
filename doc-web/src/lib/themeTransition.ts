import type { ResolvedTheme } from './theme';

/** Duration of the main View Transition ocean wave sweep across the viewport (ms). */
export const WAVE_DURATION_MS = 1380;
/** Extra tail time after the wave finishes so airborne seafoam particles dissolve naturally (ms). */
export const WAVE_TAIL_MS = 560;
/** Number of horizontal sample columns along the wave crest. */
export const WAVE_SAMPLES = 36;
/** Evenly-sampled WAAPI keyframes for smooth native refresh-rate interpolation. */
export const WAVE_KEYFRAME_COUNT = 84;
/**
 * Expressive tidal Bézier curve `[x1, y1, x2, y2]`: deliberate swell pickup,
 * dramatic surge across the viewport, and weightless deceleration into settle.
 */
export const WAVE_BEZIER = [0.38, 0.02, 0.16, 1] as const;

export interface WaveGeometry {
  originX: number;
  originY: number;
  viewportWidth: number;
  viewportHeight: number;
}

export interface WavePoint {
  x: number;
  y: number;
}

export interface WaveParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  life: number;
  maxLife: number;
  kind: 'spark' | 'foam' | 'mist';
  colorIndex: number;
  wobblePhase: number;
}

const TWO_PI = Math.PI * 2;
const EDGE_PAD_PX = 24;

function sampleBezierAxis(u: number, p1: number, p2: number): number {
  const inv = 1 - u;
  return 3 * inv * inv * u * p1 + 3 * inv * u * u * p2 + u * u * u;
}

function sampleBezierDerivative(u: number, p1: number, p2: number): number {
  const inv = 1 - u;
  return 3 * inv * inv * p1 + 6 * inv * u * (p2 - p1) + 3 * u * u * (1 - p2);
}

/**
 * Evaluates a CSS-standard `cubic-bezier(x1, y1, x2, y2)` easing curve at `t ∈ [0, 1]`
 * using Newton-Raphson iteration with bisection fallback.
 */
export function evaluateCubicBezier(
  t: number,
  x1: number = WAVE_BEZIER[0],
  y1: number = WAVE_BEZIER[1],
  x2: number = WAVE_BEZIER[2],
  y2: number = WAVE_BEZIER[3],
): number {
  if (t <= 0) return 0;
  if (t >= 1) return 1;

  let u = t;
  for (let i = 0; i < 6; i++) {
    const err = sampleBezierAxis(u, x1, x2) - t;
    if (Math.abs(err) < 1e-6) break;
    const slope = sampleBezierDerivative(u, x1, x2);
    if (Math.abs(slope) < 1e-6) break;
    u = Math.min(1, Math.max(0, u - err / slope));
  }

  // Bisection safeguard if Newton step didn't fully converge
  if (Math.abs(sampleBezierAxis(u, x1, x2) - t) > 1e-5) {
    let lo = 0;
    let hi = 1;
    u = t;
    for (let i = 0; i < 12; i++) {
      const midX = sampleBezierAxis(u, x1, x2);
      if (Math.abs(midX - t) < 1e-6) break;
      if (midX < t) lo = u;
      else hi = u;
      u = (lo + hi) * 0.5;
    }
  }

  return sampleBezierAxis(u, y1, y2);
}

function fmt(n: number): string {
  return n.toFixed(1);
}

/**
 * Computes the vertical amplitude (px) of the wave swell at normalized time `t ∈ [0, 1]`.
 * Peaks richly mid-sweep and tapers to 0 at both edges so the screen begins 0% revealed
 * and finishes 100% revealed cleanly.
 */
export function computeWaveAmplitude(t: number, viewportHeight: number): number {
  const c = Math.min(1, Math.max(0, t));
  const envelope = Math.sin(c * Math.PI);
  const maxAmp = Math.min(86, Math.max(40, viewportHeight * 0.092));
  return maxAmp * Math.pow(envelope, 0.68);
}

/**
 * Evaluates the living multi-harmonic ocean wave crest Y-coordinate at horizontal
 * position `x` and normalized sweep time `t ∈ [0, 1]`.
 *
 * - Switching to `dark` ("月升潮起 · 涨潮"): surges upward from bottom (`vh`) to top (`0`).
 * - Switching to `light` ("潮落晨起 · 晨潮"): cascades downward from top (`0`) to bottom (`vh`).
 */
export function computeWaveY(
  x: number,
  t: number,
  geom: WaveGeometry,
  nextTheme: ResolvedTheme,
  phaseOffset: number = 0,
): number {
  const c = Math.min(1, Math.max(0, t));
  const { viewportWidth: vw, viewportHeight: vh, originX } = geom;
  const nx = vw > 0 ? x / vw : 0;
  const originNx = vw > 0 ? Math.min(1, Math.max(0, originX / vw)) : 0.8;

  const eased = evaluateCubicBezier(c);
  const margin = Math.min(112, Math.max(56, vh * 0.12));
  const baseY =
    nextTheme === 'dark'
      ? vh + margin - eased * (vh + margin * 2)
      : -margin + eased * (vh + margin * 2);

  const amp = computeWaveAmplitude(eased, vh);
  // 3 traveling harmonics create natural rolling ocean swells instead of a static sine curve
  const h1 = Math.sin(TWO_PI * 1.25 * (nx - originNx * 0.4) + c * 6.2 + phaseOffset);
  const h2 = Math.sin(TWO_PI * 2.65 * nx - c * 10.0 + phaseOffset * 1.4);
  const h3 = Math.sin(TWO_PI * 4.8 * nx + c * 14.0 - phaseOffset * 0.8);
  const swell = amp * (0.56 * h1 + 0.3 * h2 + 0.14 * h3);

  // Subtle diagonal tilt biased toward the horizontal click column so the tide feels pulled by it
  const tiltAmp = Math.sin(eased * Math.PI) * Math.min(52, vw * 0.038);
  const tilt = (originNx - nx) * tiltAmp * (nextTheme === 'dark' ? -1 : 1);

  return baseY + swell + tilt;
}

/** Samples evenly-spaced points along the wave crest spanning slightly past both side edges. */
export function sampleWaveCrest(
  t: number,
  geom: WaveGeometry,
  nextTheme: ResolvedTheme,
  samples: number = WAVE_SAMPLES,
  phaseOffset: number = 0,
  verticalOffset: number = 0,
): WavePoint[] {
  const count = Math.max(2, samples);
  const startX = -EDGE_PAD_PX;
  const spanX = geom.viewportWidth + EDGE_PAD_PX * 2;
  const points: WavePoint[] = [];

  for (let i = 0; i <= count; i++) {
    const x = startX + (spanX * i) / count;
    const y = computeWaveY(x, t, geom, nextTheme, phaseOffset) + verticalOffset;
    points.push({ x, y });
  }
  return points;
}

/**
 * Builds a fixed-signature `clip-path: path("M ... L ... Z")` enclosing the revealed
 * ocean side of the wave crest. Because every keyframe emits the exact same number
 * of `L` vertices, WAAPI interpolates the rolling wave smoothly at native refresh rate.
 */
export function buildWaveClipPath(
  t: number,
  geom: WaveGeometry,
  nextTheme: ResolvedTheme,
  samples: number = WAVE_SAMPLES,
): string {
  const crest = sampleWaveCrest(t, geom, nextTheme, samples);
  const left = fmt(-EDGE_PAD_PX);
  const right = fmt(geom.viewportWidth + EDGE_PAD_PX);
  const anchorY = fmt(nextTheme === 'dark' ? geom.viewportHeight + EDGE_PAD_PX : -EDGE_PAD_PX);

  let d = `M${left} ${anchorY}`;
  for (let i = 0; i < crest.length; i++) {
    d += `L${fmt(crest[i].x)} ${fmt(crest[i].y)}`;
  }
  d += `L${right} ${anchorY}Z`;
  return `path("${d}")`;
}

/** Precomputes evenly-sampled WAAPI `clipPath` keyframes over `[0, 1]`. */
export function buildWaveClipKeyframes(
  geom: WaveGeometry,
  nextTheme: ResolvedTheme,
  steps: number = WAVE_KEYFRAME_COUNT,
  samples: number = WAVE_SAMPLES,
): string[] {
  const count = Math.max(2, steps);
  const frames: string[] = [];
  for (let i = 0; i <= count; i++) {
    frames.push(buildWaveClipPath(i / count, geom, nextTheme, samples));
  }
  return frames;
}

/**
 * Emits prominent seafoam spray, glowing bubbles, and bioluminescent mist particles
 * right along the active moving ocean crest.
 */
export function spawnCrestParticles(
  pool: WaveParticle[],
  count: number,
  t: number,
  geom: WaveGeometry,
  nextTheme: ResolvedTheme,
  maxPoolSize: number = 480,
  rand: () => number = Math.random,
): void {
  if (count <= 0 || pool.length >= maxPoolSize) return;
  const travelDir = nextTheme === 'dark' ? -1 : 1; // upward for rising night tide, downward for dawn tide
  const toSpawn = Math.min(count, maxPoolSize - pool.length);

  for (let i = 0; i < toSpawn; i++) {
    const x = rand() * geom.viewportWidth;
    const crestY = computeWaveY(x, t, geom, nextTheme);
    if (crestY < -50 || crestY > geom.viewportHeight + 50) continue;

    const roll = rand();
    const kind: WaveParticle['kind'] = roll < 0.44 ? 'spark' : roll < 0.82 ? 'foam' : 'mist';

    if (kind === 'spark') {
      // Crisp bright sea-spray droplets arching out ahead of the crest
      pool.push({
        x,
        y: crestY + (rand() - 0.5) * 18,
        vx: (rand() - 0.5) * 210,
        vy: travelDir * (160 + rand() * 310),
        radius: 1.8 + rand() * 2.5,
        life: 0,
        maxLife: 0.45 + rand() * 0.45,
        kind,
        colorIndex: Math.floor(rand() * 4),
        wobblePhase: rand() * TWO_PI,
      });
    } else if (kind === 'foam') {
      // Luminous seafoam bubbles tumbling in the turbulent wake behind the crest
      pool.push({
        x,
        y: crestY - travelDir * (4 + rand() * 48),
        vx: (rand() - 0.5) * 95,
        vy: travelDir * (40 + rand() * 120),
        radius: 3.8 + rand() * 5.6,
        life: 0,
        maxLife: 0.55 + rand() * 0.52,
        kind,
        colorIndex: Math.floor(rand() * 4),
        wobblePhase: rand() * TWO_PI,
      });
    } else {
      // Larger glowing bioluminescent mist / surf bokeh riding the wave peaks
      pool.push({
        x,
        y: crestY - travelDir * (rand() * 34),
        vx: (rand() - 0.5) * 58,
        vy: travelDir * (20 + rand() * 70),
        radius: 14 + rand() * 16,
        life: 0,
        maxLife: 0.52 + rand() * 0.5,
        kind,
        colorIndex: Math.floor(rand() * 4),
        wobblePhase: rand() * TWO_PI,
      });
    }
  }
}

/**
 * Advances particle physics by `dtSec` seconds (drag, lateral wave wobble,
 * and gentle arc pull), mutating `pool` in-place and compacting expired particles.
 */
export function stepWaveParticles(
  pool: WaveParticle[],
  dtSec: number,
  nextTheme: ResolvedTheme,
): void {
  const dt = Math.min(0.05, Math.max(0, dtSec));
  if (dt === 0) return;

  const drag = Math.exp(-2.1 * dt);
  const pullY = nextTheme === 'dark' ? 130 : -95;

  let write = 0;
  for (let i = 0; i < pool.length; i++) {
    const p = pool[i];
    p.life += dt;
    if (p.life >= p.maxLife) continue;

    p.vx *= drag;
    p.vy = p.vy * drag + pullY * dt * (p.kind === 'spark' ? 1 : 0.32);
    p.wobblePhase += dt * 6.5;
    p.x += (p.vx + Math.sin(p.wobblePhase) * (p.kind === 'foam' ? 24 : 10)) * dt;
    p.y += p.vy * dt;

    pool[write++] = p;
  }
  pool.length = write;
}
