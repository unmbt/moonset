/**
 * Pure, DOM-free interaction helpers shared by the docs site UI.
 * Everything here is deterministic so it can be unit-tested under node:test.
 */

export interface DoubleShiftDetector {
  /** Feed a keydown; returns false (double-Shift fires on the second key release). */
  keydown(key: string, timeMs: number, repeat?: boolean): boolean;
  /** Feed a keyup; returns true when a clean double-Shift tap just completed. */
  keyup(key: string, timeMs: number): boolean;
  reset(): void;
}

export const DOUBLE_SHIFT_INTERVAL_MS = 400;
export const SHIFT_TAP_MAX_HOLD_MS = 350;

/**
 * IntelliJ-style "Search Everywhere" trigger: two quick, clean Shift taps.
 * Any other key pressed in between (e.g. typing an uppercase letter) cancels the
 * sequence, and a Shift held for too long is not treated as a tap.
 */
export function createDoubleShiftDetector(
  intervalMs: number = DOUBLE_SHIFT_INTERVAL_MS,
  maxHoldMs: number = SHIFT_TAP_MAX_HOLD_MS,
): DoubleShiftDetector {
  let lastTapAt = Number.NEGATIVE_INFINITY;
  let pressedAt = Number.NEGATIVE_INFINITY;
  let clean = false;

  return {
    keydown(key, timeMs, repeat = false) {
      if (key === 'Shift') {
        if (!repeat) {
          clean = true;
          pressedAt = timeMs;
        }
        return false;
      }
      clean = false;
      lastTapAt = Number.NEGATIVE_INFINITY;
      return false;
    },
    keyup(key, timeMs) {
      if (key !== 'Shift') return false;
      if (!clean || timeMs - pressedAt > maxHoldMs) {
        clean = false;
        lastTapAt = Number.NEGATIVE_INFINITY;
        return false;
      }
      clean = false;
      if (timeMs - lastTapAt <= intervalMs) {
        lastTapAt = Number.NEGATIVE_INFINITY;
        return true;
      }
      lastTapAt = timeMs;
      return false;
    },
    reset() {
      lastTapAt = Number.NEGATIVE_INFINITY;
      pressedAt = Number.NEGATIVE_INFINITY;
      clean = false;
    },
  };
}

/**
 * Splits a CJK headline into phrases that end with punctuation so each phrase can
 * be rendered as an unbreakable inline-block (prevents orphans like 「更迭有 / 据。」).
 */
export function splitCjkPhrases(text: string): string[] {
  const parts = text.match(/[^，。；：、！？,;!?]+[，。；：、！？,;!?]*/g);
  if (!parts) return text ? [text] : [];
  return parts.filter((part) => part.length > 0);
}

export interface HighlightSegment {
  text: string;
  match: boolean;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Splits text into matched / unmatched segments for search-term highlighting.
 * Whitespace-separated terms are matched case-insensitively.
 */
export function splitHighlight(text: string, query: string): HighlightSegment[] {
  const terms = query
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .sort((a, b) => b.length - a.length)
    .map(escapeRegExp);
  if (!text) return [];
  if (terms.length === 0) return [{ text, match: false }];

  const pattern = new RegExp(`(${terms.join('|')})`, 'gi');
  const segments: HighlightSegment[] = [];
  let lastIndex = 0;
  for (const found of text.matchAll(pattern)) {
    const index = found.index ?? 0;
    if (found[0].length === 0) continue;
    if (index > lastIndex) {
      segments.push({ text: text.slice(lastIndex, index), match: false });
    }
    segments.push({ text: found[0], match: true });
    lastIndex = index + found[0].length;
  }
  if (lastIndex < text.length) {
    segments.push({ text: text.slice(lastIndex), match: false });
  }
  return segments;
}

export interface WheelClassification {
  /** True for classic notched mouse wheels that benefit from smoothing. */
  discrete: boolean;
  /** Timestamp of the latest fine-grained (trackpad-like) event. */
  lastFineAt: number;
}

export const DISCRETE_WHEEL_MIN_DELTA = 40;
export const TRACKPAD_STICKY_MS = 320;

/**
 * Distinguishes notched mouse wheels from precision touchpads / Magic Mouse.
 * Trackpads already have OS-level inertia, so layering another damping pass on
 * top of them feels laggy. Once a fine-grained event is seen, the gesture stays
 * classified as "trackpad" for a short sticky window so fast flicks don't flip.
 */
export function classifyWheelInput(
  deltaY: number,
  deltaMode: number,
  timeMs: number,
  lastFineAt: number,
  minDiscreteDelta: number = DISCRETE_WHEEL_MIN_DELTA,
  stickyMs: number = TRACKPAD_STICKY_MS,
): WheelClassification {
  if (deltaMode !== 0) {
    return { discrete: true, lastFineAt };
  }
  const magnitude = Math.abs(deltaY);
  if (magnitude >= minDiscreteDelta && timeMs - lastFineAt > stickyMs) {
    return { discrete: true, lastFineAt };
  }
  return { discrete: false, lastFineAt: timeMs };
}

/** Cubic ease-out used by count-up numbers. */
export function easeOutCubic(t: number): number {
  const clamped = Math.min(1, Math.max(0, t));
  return 1 - (1 - clamped) ** 3;
}

/** Interpolated integer value for an animated counter at normalized time t. */
export function countUpValue(target: number, t: number): number {
  return Math.round(target * easeOutCubic(t));
}

/** Formats an integer with thousands separators (1495 -> "1,495"). */
export function formatThousands(value: number): string {
  return Math.round(value).toLocaleString('en-US');
}
