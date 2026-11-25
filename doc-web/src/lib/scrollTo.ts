/**
 * DOM scrolling helpers that cooperate with lazily rendered routes: they wait
 * (bounded) for target elements / document height to exist before scrolling.
 */

export const HEADER_OFFSET_PX = 92;

export function scrollToHeadingById(id: string, behavior: ScrollBehavior = 'smooth'): boolean {
  const el = document.getElementById(id);
  if (!el) return false;
  const targetTop = Math.max(0, el.getBoundingClientRect().top + window.scrollY - HEADER_OFFSET_PX);
  window.scrollTo({ top: targetTop, behavior });
  return true;
}

/** Scrolls to an anchor as soon as it is rendered (e.g. after a lazy doc chunk loads). */
export function scrollToAnchorWhenReady(id: string, timeoutMs = 2500): () => void {
  let raf = 0;
  const deadline = performance.now() + timeoutMs;
  const attempt = () => {
    if (scrollToHeadingById(id)) return;
    if (performance.now() < deadline) raf = window.requestAnimationFrame(attempt);
  };
  raf = window.requestAnimationFrame(attempt);
  return () => window.cancelAnimationFrame(raf);
}

/** Restores a remembered scroll offset once the page is tall enough to reach it. */
export function restoreScrollWhenReady(y: number, timeoutMs = 1500): () => void {
  let raf = 0;
  const deadline = performance.now() + timeoutMs;
  const attempt = () => {
    const maxY = document.documentElement.scrollHeight - window.innerHeight;
    if (maxY >= y - 2 || performance.now() >= deadline) {
      window.scrollTo({ top: Math.min(y, Math.max(0, maxY)), behavior: 'instant' as ScrollBehavior });
      return;
    }
    raf = window.requestAnimationFrame(attempt);
  };
  raf = window.requestAnimationFrame(attempt);
  return () => window.cancelAnimationFrame(raf);
}
