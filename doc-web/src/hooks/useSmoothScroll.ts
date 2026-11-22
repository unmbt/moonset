import { useEffect } from 'react';
import {
  DEFAULT_SMOOTH_SCROLL_CONFIG,
  accumulateScrollTarget,
  normalizeWheelDelta,
  softLimitWheelDelta,
  stepInertialScroll,
} from '../lib/smoothScroll';

function canElementScrollVertically(el: HTMLElement, deltaY: number): boolean {
  const style = window.getComputedStyle(el);
  const overflowY = style.overflowY;
  if (overflowY !== 'auto' && overflowY !== 'scroll' && overflowY !== 'overlay') {
    return false;
  }
  const maxScroll = el.scrollHeight - el.clientHeight;
  if (maxScroll <= 1) return false;
  if (deltaY < 0) return el.scrollTop > 0.5;
  if (deltaY > 0) return el.scrollTop < maxScroll - 0.5;
  return false;
}

function hasScrollableAncestor(target: EventTarget | null, deltaY: number): boolean {
  let node = target instanceof HTMLElement ? target : null;
  while (node && node !== document.body && node !== document.documentElement) {
    if (canElementScrollVertically(node, deltaY)) {
      return true;
    }
    node = node.parentElement;
  }
  return false;
}

/**
 * Artcraft-inspired silky inertial wheel scrolling with comfortable max velocity cap.
 * Automatically disables for prefers-reduced-motion and touch/coarse-pointer devices,
 * and yields cleanly to nested scrollable containers, keyboard navigation, and scrollbar drags.
 */
export function useSmoothScroll() {
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const prefersReduced =
      window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const isCoarsePointer =
      window.matchMedia &&
      window.matchMedia('(pointer: coarse)').matches;

    if (prefersReduced || isCoarsePointer) return;

    let currentY = window.scrollY;
    let targetY = window.scrollY;
    let lastAppliedY = window.scrollY;
    let rafId = 0;
    let lastTimestamp = 0;

    const stopLoop = () => {
      if (rafId) {
        window.cancelAnimationFrame(rafId);
        rafId = 0;
      }
      lastTimestamp = 0;
    };

    const tick = (now: number) => {
      rafId = 0;
      const dtMs = lastTimestamp ? now - lastTimestamp : 16.67;
      lastTimestamp = now;

      const maxScrollY = Math.max(
        0,
        document.documentElement.scrollHeight - window.innerHeight,
      );
      targetY = Math.min(maxScrollY, Math.max(0, targetY));

      const { nextY, settled } = stepInertialScroll(
        currentY,
        targetY,
        dtMs,
        DEFAULT_SMOOTH_SCROLL_CONFIG,
      );

      currentY = nextY;
      lastAppliedY = nextY;
      window.scrollTo(0, nextY);

      if (!settled) {
        rafId = window.requestAnimationFrame(tick);
      } else {
        lastTimestamp = 0;
      }
    };

    const onWheel = (e: WheelEvent) => {
      // Pause smooth page scrolling while an interactive modal/lightbox is open
      if (document.documentElement.dataset.smoothScrollLock === 'true') {
        return;
      }

      // Allow pinch-to-zoom and dominant horizontal scrolling natively
      if (e.ctrlKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        return;
      }

      const rawDelta = normalizeWheelDelta(
        e.deltaY,
        e.deltaMode,
        window.innerHeight,
      );
      if (rawDelta === 0) return;

      // Let inner scrollable panels (sidebar, xterm, modals) scroll natively
      if (hasScrollableAncestor(e.target, rawDelta)) {
        return;
      }

      const maxScrollY = Math.max(
        0,
        document.documentElement.scrollHeight - window.innerHeight,
      );
      if (maxScrollY <= 0) return;

      e.preventDefault();

      // Sync with actual scrollY if something moved externally while idle
      if (!rafId) {
        currentY = window.scrollY;
        targetY = window.scrollY;
      }

      const limited = softLimitWheelDelta(
        rawDelta,
        DEFAULT_SMOOTH_SCROLL_CONFIG.maxImpulsePx,
      );

      targetY = accumulateScrollTarget(
        currentY,
        targetY,
        limited,
        maxScrollY,
        DEFAULT_SMOOTH_SCROLL_CONFIG.maxLeadPx,
      );

      if (!rafId) {
        lastTimestamp = performance.now();
        rafId = window.requestAnimationFrame(tick);
      }
    };

    // Sync immediately whenever native scrollbar drag, keyboard scroll,
    // anchor jump, or route change moves scrollY externally.
    const onNativeScroll = () => {
      const actualY = window.scrollY;
      if (Math.abs(actualY - lastAppliedY) > 2) {
        stopLoop();
        currentY = actualY;
        targetY = actualY;
        lastAppliedY = actualY;
      }
    };

    window.addEventListener('wheel', onWheel, { passive: false });
    window.addEventListener('scroll', onNativeScroll, { passive: true });

    return () => {
      stopLoop();
      window.removeEventListener('wheel', onWheel);
      window.removeEventListener('scroll', onNativeScroll);
    };
  }, []);
}
