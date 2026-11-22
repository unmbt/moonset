export interface ScrollState {
  progress: number;
  activeIndex: number;
  weights: number[];
}

export function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0;
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

/**
 * Computes normalized [0, 1] scroll progress through a sticky narrative section.
 */
export function computeSectionProgress(
  sectionTop: number,
  sectionHeight: number,
  viewportHeight: number,
): number {
  const scrollableDistance = Math.max(1, sectionHeight - viewportHeight);
  return clamp01(-sectionTop / scrollableDistance);
}

/**
 * Maps continuous [0, 1] progress into an active chapter index and per-chapter
 * illumination weights for scroll-driven typography and timeline styling.
 */
export function computeTimelineState(progress: number, count: number): ScrollState {
  if (count <= 0) {
    return { progress: 0, activeIndex: 0, weights: [] };
  }
  const clamped = clamp01(progress);
  const scaled = clamped * (count - 1);
  const activeIndex = Math.min(count - 1, Math.max(0, Math.round(scaled)));

  const weights = Array.from({ length: count }, (_, idx) => {
    const distance = Math.abs(scaled - idx);
    // Smooth bell falloff over 1.15 chapter intervals
    const raw = Math.max(0, 1 - distance / 1.15);
    return Number((raw * raw * (3 - 2 * raw)).toFixed(3));
  });

  return {
    progress: clamped,
    activeIndex,
    weights,
  };
}
