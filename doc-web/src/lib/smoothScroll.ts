export interface SmoothScrollConfig {
  /** Exponential damping factor (higher = snappier, lower = longer glide). */
  damping: number;
  /** Maximum impulse accepted per wheel event after soft-limiting (px). */
  maxImpulsePx: number;
  /** Maximum vertical travel speed to keep fast scrolling visually comfortable (px/s). */
  maxVelocityPxPerSec: number;
  /** Maximum lead distance ahead of current scroll position (px). */
  maxLeadPx: number;
  /** Settle threshold in pixels below which animation stops. */
  stopThresholdPx: number;
}

export const DEFAULT_SMOOTH_SCROLL_CONFIG: SmoothScrollConfig = {
  damping: 7.8,
  maxImpulsePx: 190,
  maxVelocityPxPerSec: 1950,
  maxLeadPx: 680,
  stopThresholdPx: 0.35,
};

/**
 * Normalizes WheelEvent deltaY across pixel (0), line (1), and page (2) modes.
 */
export function normalizeWheelDelta(
  deltaY: number,
  deltaMode: number,
  viewportHeight: number,
): number {
  if (!Number.isFinite(deltaY)) return 0;
  if (deltaMode === 1) return deltaY * 36;
  if (deltaMode === 2) return deltaY * Math.max(300, viewportHeight * 0.85);
  return deltaY;
}

/**
 * Applies a smooth hyperbolic-tangent limiter so gentle scrolling stays 1:1
 * while aggressive high-speed wheel flicks asymptote to a comfortable ceiling.
 */
export function softLimitWheelDelta(deltaPx: number, maxImpulsePx: number): number {
  if (deltaPx === 0 || maxImpulsePx <= 0) return 0;
  return maxImpulsePx * Math.tanh(deltaPx / maxImpulsePx);
}

/**
 * Advances target scroll position with bounded lead distance so rapid scrolling
 * does not queue multi-second runaway inertia.
 */
export function accumulateScrollTarget(
  currentY: number,
  targetY: number,
  limitedDeltaPx: number,
  maxScrollY: number,
  maxLeadPx: number,
): number {
  const nextRaw = targetY + limitedDeltaPx;
  const clampedLead = Math.min(
    currentY + maxLeadPx,
    Math.max(currentY - maxLeadPx, nextRaw),
  );
  return Math.min(Math.max(0, maxScrollY), Math.max(0, clampedLead));
}

export interface ScrollStepResult {
  nextY: number;
  settled: boolean;
}

/**
 * Advances inertial scroll by one frame using frame-rate-independent damping
 * and a hard comfortable velocity cap (px/s).
 */
export function stepInertialScroll(
  currentY: number,
  targetY: number,
  dtMs: number,
  config: SmoothScrollConfig = DEFAULT_SMOOTH_SCROLL_CONFIG,
): ScrollStepResult {
  const clampedTarget = Math.max(0, targetY);
  const diff = clampedTarget - currentY;

  if (Math.abs(diff) <= config.stopThresholdPx) {
    return { nextY: clampedTarget, settled: true };
  }

  // Clamp dt to avoid giant jumps after tab backgrounding
  const dtSec = Math.min(0.05, Math.max(0.001, dtMs / 1000));
  const factor = 1 - Math.exp(-config.damping * dtSec);
  const desiredStep = diff * factor;
  const maxStep = config.maxVelocityPxPerSec * dtSec;
  const clampedStep =
    Math.abs(desiredStep) > maxStep
      ? Math.sign(desiredStep) * maxStep
      : desiredStep;

  const nextY = currentY + clampedStep;
  const remaining = Math.abs(clampedTarget - nextY);
  if (remaining <= config.stopThresholdPx) {
    return { nextY: clampedTarget, settled: true };
  }

  return { nextY, settled: false };
}
