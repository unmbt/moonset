export interface Point2D {
  x: number;
  y: number;
}

export interface PanZoomState {
  scale: number;
  x: number;
  y: number;
}

export interface PanZoomLimits {
  minScale: number;
  maxScale: number;
}

export interface PinchSnapshot {
  distance: number;
  midpoint: Point2D;
}

export const DEFAULT_PAN_ZOOM_LIMITS: PanZoomLimits = {
  minScale: 0.4,
  maxScale: 6,
};

export const INITIAL_PAN_ZOOM_STATE: PanZoomState = {
  scale: 1,
  x: 0,
  y: 0,
};

export function clampScale(
  scale: number,
  limits: PanZoomLimits = DEFAULT_PAN_ZOOM_LIMITS,
): number {
  if (!Number.isFinite(scale)) return 1;
  return Math.min(limits.maxScale, Math.max(limits.minScale, scale));
}

export function computeWheelZoomScale(
  currentScale: number,
  deltaY: number,
  limits: PanZoomLimits = DEFAULT_PAN_ZOOM_LIMITS,
): number {
  if (!Number.isFinite(deltaY) || deltaY === 0) {
    return clampScale(currentScale, limits);
  }
  const clampedDelta = Math.max(-240, Math.min(240, deltaY));
  const factor = Math.exp(-clampedDelta * 0.0022);
  return clampScale(currentScale * factor, limits);
}

/**
 * Zooms to `targetScale` while keeping the content point under `focalPoint`
 * anchored at the same visual position inside the viewport.
 */
export function zoomAtPoint(
  state: PanZoomState,
  targetScale: number,
  focalPoint: Point2D,
  viewportCenter: Point2D,
  limits: PanZoomLimits = DEFAULT_PAN_ZOOM_LIMITS,
): PanZoomState {
  const nextScale = clampScale(targetScale, limits);
  if (state.scale <= 0) {
    return { scale: nextScale, x: state.x, y: state.y };
  }
  const ratio = nextScale / state.scale;
  const localX = focalPoint.x - viewportCenter.x;
  const localY = focalPoint.y - viewportCenter.y;

  return {
    scale: nextScale,
    x: localX - (localX - state.x) * ratio,
    y: localY - (localY - state.y) * ratio,
  };
}

export function applyPanDelta(
  state: PanZoomState,
  dx: number,
  dy: number,
): PanZoomState {
  return {
    scale: state.scale,
    x: state.x + (Number.isFinite(dx) ? dx : 0),
    y: state.y + (Number.isFinite(dy) ? dy : 0),
  };
}

export function computePinchSnapshot(p1: Point2D, p2: Point2D): PinchSnapshot {
  return {
    distance: Math.hypot(p2.x - p1.x, p2.y - p1.y),
    midpoint: {
      x: (p1.x + p2.x) / 2,
      y: (p1.y + p2.y) / 2,
    },
  };
}

/**
 * Simultaneously applies two-finger pinch scaling and two-finger midpoint panning
 * relative to the gesture start snapshot.
 */
export function stepPinchTransform(
  startState: PanZoomState,
  startPinch: PinchSnapshot,
  currentPinch: PinchSnapshot,
  viewportCenter: Point2D,
  limits: PanZoomLimits = DEFAULT_PAN_ZOOM_LIMITS,
): PanZoomState {
  const safeStartDist = Math.max(1, startPinch.distance);
  const nextScale = clampScale(
    startState.scale * (currentPinch.distance / safeStartDist),
    limits,
  );
  const ratio = nextScale / Math.max(0.0001, startState.scale);

  const startLocalX = startPinch.midpoint.x - viewportCenter.x;
  const startLocalY = startPinch.midpoint.y - viewportCenter.y;
  const currLocalX = currentPinch.midpoint.x - viewportCenter.x;
  const currLocalY = currentPinch.midpoint.y - viewportCenter.y;

  return {
    scale: nextScale,
    x: currLocalX - (startLocalX - startState.x) * ratio,
    y: currLocalY - (startLocalY - startState.y) * ratio,
  };
}
