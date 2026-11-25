import { useEffect, useRef } from 'react';

const GRAIN_TEXTURE =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0.5 0 0 0 0 0.5 0 0 0 0 0.5 0 0 0 1 0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

interface AmbientBackgroundProps {
  /** Whether to enable scroll-reactive phase drift (home page) */
  reactive?: boolean;
}

/**
 * Restrained lunar atmospheric background with compositor-only scroll parallax.
 * Gently shifts light field angle & lunar arc rotation as the reader scrolls.
 */
export function AmbientBackground({ reactive = true }: AmbientBackgroundProps) {
  const primaryGlowRef = useRef<HTMLDivElement>(null);
  const secondaryGlowRef = useRef<HTMLDivElement>(null);
  const orbitalSvgRef = useRef<SVGSVGElement>(null);

  useEffect(() => {
    if (!reactive) return;
    const prefersReduced =
      typeof window !== 'undefined' &&
      window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReduced) return;

    let frame = 0;

    const update = () => {
      frame = 0;
      const maxScroll = Math.max(
        1,
        document.documentElement.scrollHeight - window.innerHeight,
      );
      const ratio = Math.min(1, Math.max(0, window.scrollY / maxScroll));

      if (primaryGlowRef.current) {
        const tx = Math.sin(ratio * Math.PI * 1.4) * 90;
        const ty = ratio * 160;
        const scale = 1 + Math.sin(ratio * Math.PI) * 0.14;
        primaryGlowRef.current.style.transform = `translate3d(${tx.toFixed(1)}px, ${ty.toFixed(1)}px, 0) scale(${scale.toFixed(3)})`;
      }
      if (secondaryGlowRef.current) {
        const tx = -Math.cos(ratio * Math.PI) * 80;
        const ty = -ratio * 120;
        secondaryGlowRef.current.style.transform = `translate3d(${tx.toFixed(1)}px, ${ty.toFixed(1)}px, 0)`;
      }
      if (orbitalSvgRef.current) {
        const deg = ratio * 38;
        orbitalSvgRef.current.style.transform = `translate3d(-50%, 0, 0) rotate(${deg.toFixed(2)}deg)`;
      }
    };

    const onScroll = () => {
      if (!frame) {
        frame = window.requestAnimationFrame(update);
      }
    };

    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [reactive]);

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed inset-0 -z-10 overflow-hidden select-none"
    >
      {/* Subtle top-center lunar aura */}
      <div
        ref={primaryGlowRef}
        className="absolute -top-48 left-1/2 h-[540px] w-[780px] -translate-x-1/2 rounded-full opacity-55 blur-[120px] transition-opacity duration-500 will-change-transform dark:opacity-70"
        style={{
          background:
            'radial-gradient(ellipse at center, rgba(99, 102, 241, 0.22) 0%, rgba(129, 140, 248, 0.08) 48%, transparent 74%)',
        }}
      />

      {/* Subtle warm moonlight horizon counterbalance */}
      <div
        ref={secondaryGlowRef}
        className="absolute right-[-12%] bottom-[-18%] h-[460px] w-[560px] rounded-full opacity-40 blur-[130px] will-change-transform dark:opacity-40"
        style={{
          background:
            'radial-gradient(ellipse at center, rgba(245, 158, 11, 0.14) 0%, rgba(99, 102, 241, 0.06) 52%, transparent 74%)',
        }}
      />

      {/* Faint architectural orbital arcs (ultra-low contrast, tactile precision) */}
      <svg
        ref={orbitalSvgRef}
        viewBox="0 0 1200 1200"
        className="absolute top-[-340px] left-1/2 h-[1160px] w-[1160px] -translate-x-1/2 text-slate-900/[0.045] will-change-transform dark:text-indigo-200/[0.055]"
        fill="none"
      >
        <circle cx="600" cy="600" r="360" stroke="currentColor" strokeWidth="1" />
        <circle
          cx="600"
          cy="600"
          r="480"
          stroke="currentColor"
          strokeWidth="1"
          strokeDasharray="4 10"
        />
        <circle cx="600" cy="600" r="590" stroke="currentColor" strokeWidth="0.75" />
        <line x1="600" y1="10" x2="600" y2="1190" stroke="currentColor" strokeWidth="0.5" />
        <line x1="10" y1="600" x2="1190" y2="600" stroke="currentColor" strokeWidth="0.5" />
      </svg>

      {/* Ultra-fine film grain adds tactile depth to the flat canvas (esp. dark mode) */}
      <div
        className="absolute inset-0 opacity-[0.025] mix-blend-multiply dark:opacity-[0.045] dark:mix-blend-screen"
        style={{ backgroundImage: GRAIN_TEXTURE, backgroundSize: '160px 160px' }}
      />
    </div>
  );
}
