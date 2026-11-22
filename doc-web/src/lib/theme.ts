export type ThemePreference = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';

export const THEME_STORAGE_KEY = 'moonset-theme';

export function resolveTheme(
  preference: ThemePreference,
  systemPrefersDark: boolean,
): ResolvedTheme {
  if (preference === 'dark') return 'dark';
  if (preference === 'light') return 'light';
  return systemPrefersDark ? 'dark' : 'light';
}

/**
 * Toggles theme with immediate visible feedback on first click while preserving
 * system-sync as the natural return state.
 *
 * Example when system is dark:
 *   system (dark) -> light -> system (dark)
 * Example when system is light:
 *   system (light) -> dark -> system (light)
 */
export function nextThemePreference(
  current: ThemePreference,
  systemPrefersDark: boolean,
): ThemePreference {
  if (current === 'system') {
    return systemPrefersDark ? 'light' : 'dark';
  }
  const oppositeOfSystem: ThemePreference = systemPrefersDark ? 'light' : 'dark';
  if (current === oppositeOfSystem) {
    return 'system';
  }
  return oppositeOfSystem;
}

export function parseStoredTheme(raw: string | null | undefined): ThemePreference {
  if (raw === 'light' || raw === 'dark' || raw === 'system') {
    return raw;
  }
  return 'system';
}

export interface ThemeTransitionOrigin {
  x: number;
  y: number;
}

export interface CircularRevealGeometry {
  x: number;
  y: number;
  endRadius: number;
}

/**
 * Fluid asymmetric ease-in-out bezier curve for circular View Transition reveal:
 * graceful bloom out of the clicked point, swift sweep across the viewport,
 * and weightless deceleration into the farthest corner.
 */
export const THEME_TRANSITION_DURATION_MS = 640;
export const THEME_TRANSITION_EASING = 'cubic-bezier(0.4, 0, 0.16, 1)';

export function resolveThemeTransitionOrigin(
  pointer: { clientX: number; clientY: number; detail?: number } | null | undefined,
  fallbackRect: { left: number; top: number; width: number; height: number } | null | undefined,
  viewport: { width: number; height: number },
): ThemeTransitionOrigin {
  const hasPointerCoords =
    pointer != null &&
    Number.isFinite(pointer.clientX) &&
    Number.isFinite(pointer.clientY) &&
    (pointer.clientX !== 0 || pointer.clientY !== 0) &&
    (pointer.detail === undefined || pointer.detail > 0);

  if (hasPointerCoords) {
    return { x: pointer.clientX, y: pointer.clientY };
  }

  if (fallbackRect && fallbackRect.width > 0 && fallbackRect.height > 0) {
    return {
      x: fallbackRect.left + fallbackRect.width / 2,
      y: fallbackRect.top + fallbackRect.height / 2,
    };
  }

  return {
    x: Math.max(0, viewport.width) / 2,
    y: Math.max(0, viewport.height) / 2,
  };
}

export function computeCircularRevealGeometry(
  origin: ThemeTransitionOrigin,
  viewport: { width: number; height: number },
): CircularRevealGeometry {
  const width = Math.max(0, Number.isFinite(viewport.width) ? viewport.width : 0);
  const height = Math.max(0, Number.isFinite(viewport.height) ? viewport.height : 0);
  const rawX = Number.isFinite(origin.x) ? origin.x : width / 2;
  const rawY = Number.isFinite(origin.y) ? origin.y : height / 2;

  const x = Math.min(Math.max(rawX, 0), width);
  const y = Math.min(Math.max(rawY, 0), height);

  const dx = Math.max(x, width - x);
  const dy = Math.max(y, height - y);
  const endRadius = Math.hypot(dx, dy);

  return { x, y, endRadius };
}

