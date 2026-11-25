import { forwardRef, useImperativeHandle, useRef } from 'react';
import type { ResolvedTheme } from '../lib/theme';
import {
  WAVE_DURATION_MS,
  WAVE_SAMPLES,
  WAVE_TAIL_MS,
  sampleWaveCrest,
  spawnCrestParticles,
  stepWaveParticles,
  type WaveGeometry,
  type WaveParticle,
  type WavePoint,
} from '../lib/themeTransition';

export interface ThemeWaveHandle {
  start: (geom: WaveGeometry, nextTheme: ResolvedTheme) => void;
  stop: () => void;
}

const DARK_PALETTE = {
  // Bioluminescent night tide ("月升潮起 · 蓝眼泪")
  ribbonBack: 'rgba(99, 102, 241, 0.32)',
  ribbonMid: 'rgba(56, 189, 248, 0.42)',
  crestHalo: 'rgba(56, 189, 248, 0.5)',
  crestGlow: 'rgba(129, 140, 248, 0.85)',
  crestCore: 'rgba(240, 249, 255, 0.96)',
  particles: ['#38bdf8', '#818cf8', '#7dd3fc', '#f0f9ff'],
};

const LIGHT_PALETTE = {
  // Sunlit morning surf with vivid ocean-blue & amber contrast against light canvas
  ribbonBack: 'rgba(56, 189, 248, 0.24)',
  ribbonMid: 'rgba(245, 158, 11, 0.28)',
  crestHalo: 'rgba(56, 189, 248, 0.42)',
  crestGlow: 'rgba(245, 158, 11, 0.78)',
  crestCore: 'rgba(255, 255, 255, 0.98)',
  particles: ['#0284c7', '#4f46e5', '#f59e0b', '#38bdf8'],
};

function traceSmoothCurve(ctx: CanvasRenderingContext2D, pts: WavePoint[]): void {
  if (pts.length < 2) return;
  ctx.moveTo(pts[0].x, pts[0].y);
  for (let i = 1; i < pts.length - 1; i++) {
    const mx = (pts[i].x + pts[i + 1].x) * 0.5;
    const my = (pts[i].y + pts[i + 1].y) * 0.5;
    ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my);
  }
  const last = pts[pts.length - 1];
  ctx.lineTo(last.x, last.y);
}

/**
 * Full-viewport high-DPI `<canvas>` overlay rendered above `::view-transition-new(root)`
 * during a theme switch. Draws layered glowing ocean wave crests and vivid physics-driven
 * seafoam / bioluminescent spray particles, then lets airborne particles dissolve
 * gracefully after the View Transition completes.
 */
export const ThemeWaveOverlay = forwardRef<ThemeWaveHandle>(function ThemeWaveOverlay(_props, ref) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef(0);
  const particlesRef = useRef<WaveParticle[]>([]);

  useImperativeHandle(ref, () => ({
    start(geom, nextTheme) {
      if (rafRef.current) {
        window.cancelAnimationFrame(rafRef.current);
        rafRef.current = 0;
      }

      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const { viewportWidth: vw, viewportHeight: vh } = geom;
      canvas.width = Math.max(1, Math.round(vw * dpr));
      canvas.height = Math.max(1, Math.round(vh * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const pool = particlesRef.current;
      pool.length = 0;

      const palette = nextTheme === 'dark' ? DARK_PALETTE : LIGHT_PALETTE;
      const trailDir = nextTheme === 'dark' ? 1 : -1;
      const totalMs = WAVE_DURATION_MS + WAVE_TAIL_MS;
      const startTime = performance.now();
      let lastTime = startTime;

      const render = (now: number) => {
        const elapsed = now - startTime;
        const dtSec = Math.min(0.05, Math.max(0.001, (now - lastTime) / 1000));
        lastTime = now;

        const t = Math.min(1, elapsed / WAVE_DURATION_MS);
        ctx.clearRect(0, 0, vw, vh);

        // 1. Emit rich seafoam & spray shower while the wave crest sweeps across the viewport
        if (elapsed < WAVE_DURATION_MS * 0.94) {
          const density = Math.max(10, Math.round((vw / 82) * (dtSec / 0.0167)));
          spawnCrestParticles(pool, density, t, geom, nextTheme);
        }

        // 2. Draw layered translucent wave ribbons & luminous seafoam crest along the live boundary
        if (elapsed < WAVE_DURATION_MS) {
          const edgeFade = Math.sin(t * Math.PI);
          const ribbonAlpha = Math.pow(edgeFade, 0.45);

          const backCrest = sampleWaveCrest(t, geom, nextTheme, WAVE_SAMPLES, 0.9, trailDir * 24);
          const wakeCrest = sampleWaveCrest(t, geom, nextTheme, WAVE_SAMPLES, -0.6, trailDir * 11);
          const mainCrest = sampleWaveCrest(t, geom, nextTheme, WAVE_SAMPLES);

          ctx.save();
          ctx.globalAlpha = ribbonAlpha;

          // Back-swell ribbon
          ctx.beginPath();
          traceSmoothCurve(ctx, backCrest);
          for (let i = mainCrest.length - 1; i >= 0; i--) {
            ctx.lineTo(mainCrest[i].x, mainCrest[i].y);
          }
          ctx.closePath();
          ctx.fillStyle = palette.ribbonBack;
          ctx.fill();

          // Mid translucent surf wake
          ctx.beginPath();
          traceSmoothCurve(ctx, wakeCrest);
          for (let i = mainCrest.length - 1; i >= 0; i--) {
            ctx.lineTo(mainCrest[i].x, mainCrest[i].y);
          }
          ctx.closePath();
          ctx.fillStyle = palette.ribbonMid;
          ctx.fill();

          // Three-tier luminous seafoam crest (soft outer aura -> glow -> crisp white foam core)
          ctx.lineCap = 'round';
          ctx.lineJoin = 'round';

          ctx.beginPath();
          traceSmoothCurve(ctx, mainCrest);
          ctx.strokeStyle = palette.crestHalo;
          ctx.lineWidth = 20;
          ctx.stroke();

          ctx.beginPath();
          traceSmoothCurve(ctx, mainCrest);
          ctx.strokeStyle = palette.crestGlow;
          ctx.lineWidth = 8;
          ctx.stroke();

          ctx.beginPath();
          traceSmoothCurve(ctx, mainCrest);
          ctx.strokeStyle = palette.crestCore;
          ctx.lineWidth = 2.6;
          ctx.stroke();

          ctx.restore();
        }

        // 3. Step & render physics-driven seafoam / bioluminescent spray particles
        stepWaveParticles(pool, dtSec, nextTheme);

        ctx.save();
        if (nextTheme === 'dark') {
          ctx.globalCompositeOperation = 'lighter';
        }
        for (let i = 0; i < pool.length; i++) {
          const p = pool[i];
          const progress = p.life / p.maxLife;
          const alpha =
            Math.sin(Math.min(1, progress * 3.8) * (Math.PI * 0.5)) *
            Math.pow(1 - progress, 1.2);
          if (alpha <= 0.01) continue;

          const color = palette.particles[p.colorIndex % palette.particles.length];
          const r = p.radius * (p.kind === 'foam' ? 1 + progress * 0.38 : 1 - progress * 0.25);

          if (p.kind === 'mist') {
            const grad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, Math.max(1, r));
            grad.addColorStop(0, color);
            grad.addColorStop(0.45, color);
            grad.addColorStop(1, 'rgba(0,0,0,0)');
            ctx.globalAlpha = alpha * (nextTheme === 'dark' ? 0.42 : 0.32);
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.arc(p.x, p.y, Math.max(1, r), 0, Math.PI * 2);
            ctx.fill();
          } else if (p.kind === 'foam') {
            // Soft luminous halo around each seafoam bubble
            ctx.globalAlpha = alpha * (nextTheme === 'dark' ? 0.28 : 0.22);
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(p.x, p.y, Math.max(1, r * 1.9), 0, Math.PI * 2);
            ctx.fill();

            // Main glowing bubble orb
            ctx.globalAlpha = alpha * (nextTheme === 'dark' ? 0.85 : 0.8);
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(p.x, p.y, Math.max(0.8, r), 0, Math.PI * 2);
            ctx.fill();

            // Specular highlight dot
            ctx.globalAlpha = alpha * 0.78;
            ctx.fillStyle = '#ffffff';
            ctx.beginPath();
            ctx.arc(p.x - r * 0.28, p.y - r * 0.28, Math.max(0.6, r * 0.36), 0, Math.PI * 2);
            ctx.fill();
          } else {
            // Vivid spray streak with soft glow + bright droplet head
            const tailX = p.x - p.vx * 0.036;
            const tailY = p.y - p.vy * 0.036;

            ctx.lineCap = 'round';
            ctx.globalAlpha = alpha * 0.42;
            ctx.strokeStyle = color;
            ctx.lineWidth = Math.max(2.6, r * 2.1);
            ctx.beginPath();
            ctx.moveTo(p.x, p.y);
            ctx.lineTo(tailX, tailY);
            ctx.stroke();

            ctx.globalAlpha = alpha * 0.98;
            ctx.strokeStyle = nextTheme === 'dark' ? '#f0f9ff' : color;
            ctx.lineWidth = Math.max(1.2, r * 0.95);
            ctx.beginPath();
            ctx.moveTo(p.x, p.y);
            ctx.lineTo(tailX, tailY);
            ctx.stroke();

            ctx.globalAlpha = alpha;
            ctx.fillStyle = '#ffffff';
            ctx.beginPath();
            ctx.arc(p.x, p.y, Math.max(0.9, r * 0.65), 0, Math.PI * 2);
            ctx.fill();
          }
        }
        ctx.restore();

        if (elapsed < totalMs || pool.length > 0) {
          rafRef.current = window.requestAnimationFrame(render);
        } else {
          ctx.clearRect(0, 0, vw, vh);
          rafRef.current = 0;
        }
      };

      rafRef.current = window.requestAnimationFrame(render);
    },

    stop() {
      if (rafRef.current) {
        window.cancelAnimationFrame(rafRef.current);
        rafRef.current = 0;
      }
      particlesRef.current.length = 0;
      const canvas = canvasRef.current;
      const ctx = canvas?.getContext('2d');
      if (canvas && ctx) {
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, canvas.width, canvas.height);
      }
    },
  }));

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      className="moonset-theme-wave pointer-events-none fixed inset-0 z-[60] h-full w-full"
    />
  );
});
