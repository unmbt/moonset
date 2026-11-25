import {
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
  type PointerEvent as ReactPointerEvent,
} from 'react';
import { countUpValue, splitCjkPhrases } from '../lib/interaction';

export function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

/** Inline style carrying a staggered entrance / reveal delay. */
export function delayStyle(ms: number, extra?: CSSProperties): CSSProperties {
  return { ...extra, ['--enter-delay' as string]: `${ms}ms` } as CSSProperties;
}

interface InViewOptions {
  rootMargin?: string;
  threshold?: number;
  once?: boolean;
}

export function useInView<T extends Element>({
  rootMargin = '0px 0px -10% 0px',
  threshold = 0.12,
  once = true,
}: InViewOptions = {}) {
  const ref = useRef<T | null>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (typeof IntersectionObserver === 'undefined') {
      setInView(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setInView(true);
            if (once) observer.disconnect();
          } else if (!once) {
            setInView(false);
          }
        }
      },
      { rootMargin, threshold },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [rootMargin, threshold, once]);

  return [ref, inView] as const;
}

type RevealTag = 'div' | 'section' | 'li' | 'article' | 'header';

interface RevealProps {
  as?: RevealTag;
  delay?: number;
  className?: string;
  style?: CSSProperties;
  children?: ReactNode;
  id?: string;
}

/** Fades & lifts its content in once when it scrolls into view. */
export function Reveal({ as = 'div', delay = 0, className = '', style, children, id }: RevealProps) {
  const [ref, inView] = useInView<HTMLElement>();
  const Tag = as as 'div';
  return (
    <Tag
      id={id}
      ref={ref as React.RefObject<HTMLDivElement>}
      data-reveal={inView ? 'in' : 'out'}
      className={`moonset-reveal ${className}`}
      style={delayStyle(delay, style)}
    >
      {children}
    </Tag>
  );
}

/**
 * Renders a CJK headline as unbreakable punctuation-terminated phrases so lines
 * never wrap in the middle of a word (e.g. 「更迭有 / 据。」).
 */
export function Phrases({ text }: { text: string }) {
  return (
    <>
      {splitCjkPhrases(text).map((phrase, idx) => (
        <span key={idx} className="inline-block">
          {phrase}
        </span>
      ))}
    </>
  );
}

/** Animated integer counter that starts once `active` becomes true. */
export function useCountUp(target: number, active: boolean, durationMs = 1400): number {
  const [value, setValue] = useState(() => (prefersReducedMotion() ? target : 0));

  useEffect(() => {
    if (!active) return;
    if (prefersReducedMotion()) {
      setValue(target);
      return;
    }
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = (now - start) / durationMs;
      setValue(countUpValue(target, t));
      if (t < 1) raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(raf);
  }, [active, target, durationMs]);

  return value;
}

interface SpotlightCardProps {
  className?: string;
  children?: ReactNode;
  delay?: number;
  /** Whether the card also fades/lifts in on scroll. Set false when already revealed or sticky. */
  reveal?: boolean;
}

/**
 * Card with a cursor-following spotlight and luminous border on hover.
 * Pointer tracking writes CSS variables directly (no React re-render).
 */
export function SpotlightCard({
  className = '',
  children,
  delay = 0,
  reveal = true,
}: SpotlightCardProps) {
  const [ref, inView] = useInView<HTMLDivElement>();

  const handlePointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    const el = event.currentTarget;
    const rect = el.getBoundingClientRect();
    el.style.setProperty('--spot-x', `${event.clientX - rect.left}px`);
    el.style.setProperty('--spot-y', `${event.clientY - rect.top}px`);
  };

  if (!reveal) {
    return (
      <div
        onPointerMove={handlePointerMove}
        className={`moonset-spotlight relative ${className}`}
      >
        {children}
      </div>
    );
  }

  return (
    <div
      ref={ref}
      data-reveal={inView ? 'in' : 'out'}
      onPointerMove={handlePointerMove}
      style={delayStyle(delay)}
      className={`moonset-reveal moonset-spotlight relative ${className}`}
    >
      {children}
    </div>
  );
}
