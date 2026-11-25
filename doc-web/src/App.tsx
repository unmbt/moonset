import {
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useRef,
  useState,
  type MouseEvent,
} from 'react';
import { flushSync } from 'react-dom';
import {
  THEME_STORAGE_KEY,
  nextThemePreference,
  parseStoredTheme,
  resolveTheme,
  resolveThemeTransitionOrigin,
  type ThemePreference,
} from './lib/theme';
import {
  WAVE_DURATION_MS,
  buildWaveClipKeyframes,
  type WaveGeometry,
} from './lib/themeTransition';
import { getDocBySlug } from './lib/docsCatalog';
import { createDoubleShiftDetector } from './lib/interaction';
import { restoreScrollWhenReady, scrollToAnchorWhenReady } from './lib/scrollTo';
import { AmbientBackground } from './components/AmbientBackground';
import { TopNav, type ActiveRouteSection } from './components/TopNav';
import { HeroSection } from './components/HeroSection';
import { ScrollStorySection } from './components/ScrollStorySection';
import { EcosystemFlowSection } from './components/EcosystemFlowSection';
import { ArchitectureBento } from './components/ArchitectureBento';
import { CommandPalette } from './components/CommandPalette';
import { NotFound } from './components/NotFound';
import { Footer } from './components/Footer';
import { ThemeWaveOverlay, type ThemeWaveHandle } from './components/ThemeWaveOverlay';
import { prefersReducedMotion } from './components/motion';
import { useSmoothScroll } from './hooks/useSmoothScroll';

// Docs & changelog pull in react-markdown + shiki; split them off the home page bundle.
const DocsLayout = lazy(() =>
  import('./components/DocsLayout').then((m) => ({ default: m.DocsLayout })),
);
const ChangelogPage = lazy(() =>
  import('./components/ChangelogPage').then((m) => ({ default: m.ChangelogPage })),
);

const BASE_TITLE = 'moonset — 月升则潮起，版本有序，更迭有据';
const SCROLL_MEMORY_KEY = 'moonset-scroll-memory';

function parseHashRoute(hash: string): { path: string; anchor?: string } {
  const cleaned = hash.replace(/^#/, '');
  if (!cleaned || cleaned === '/') return { path: '/' };
  const normalized = cleaned.startsWith('/') ? cleaned : `/${cleaned}`;
  const [path, anchor] = normalized.split('#');
  return { path: path || '/', anchor: anchor ? decodeURIComponent(anchor) : undefined };
}

function getActiveSection(path: string): ActiveRouteSection | 'unknown' {
  if (path === '/') return 'home';
  if (path === '/changelog') return 'changelog';
  if (path.startsWith('/docs/skills')) return 'skills';
  if (path === '/docs' || path.startsWith('/docs/')) return 'docs';
  return 'unknown';
}

function computeTitle(path: string): string {
  const section = getActiveSection(path);
  if (section === 'home') return BASE_TITLE;
  if (section === 'changelog') return '更新日志 · moonset';
  if (section === 'docs' || section === 'skills') {
    const slug = path.replace(/^\/docs\/?/, '') || 'quickstart';
    const doc = getDocBySlug(slug);
    return doc ? `${doc.title} · moonset 文档` : '页面未找到 · moonset';
  }
  return '页面未找到 · moonset';
}

function loadScrollMemory(): Map<string, number> {
  try {
    const raw = sessionStorage.getItem(SCROLL_MEMORY_KEY);
    if (raw) return new Map(JSON.parse(raw) as Array<[string, number]>);
  } catch {
    // Ignore unavailable / corrupted session storage
  }
  return new Map();
}

function RouteFallback() {
  return (
    <div aria-busy="true" className="mx-auto max-w-3xl px-6 py-16">
      <div className="moonset-shimmer h-8 w-2/3 rounded-lg bg-slate-900/[0.05] dark:bg-white/[0.05]" />
      <div className="mt-6 space-y-3">
        {[92, 100, 84, 96, 70].map((w, i) => (
          <div
            key={i}
            style={{ width: `${w}%` }}
            className="moonset-shimmer h-3.5 rounded bg-slate-900/[0.04] dark:bg-white/[0.04]"
          />
        ))}
      </div>
    </div>
  );
}

type ViewTransitionLike = { ready: Promise<void>; finished: Promise<void> };
type StartViewTransition = (update: () => void) => ViewTransitionLike;

function getStartViewTransition(): StartViewTransition | undefined {
  const doc = document as Document & { startViewTransition?: StartViewTransition };
  return doc.startViewTransition?.bind(document);
}

export function App() {
  useSmoothScroll();
  const [route, setRoute] = useState<string>(() => parseHashRoute(window.location.hash).path);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [systemPrefersDark, setSystemPrefersDark] = useState<boolean>(() =>
    typeof window !== 'undefined' && window.matchMedia
      ? window.matchMedia('(prefers-color-scheme: dark)').matches
      : false,
  );
  const [themePref, setThemePref] = useState<ThemePreference>(() => {
    try {
      return parseStoredTheme(localStorage.getItem(THEME_STORAGE_KEY));
    } catch {
      return 'system';
    }
  });

  const resolvedTheme = resolveTheme(themePref, systemPrefersDark);
  const routeRef = useRef(route);
  routeRef.current = route;
  const scrollMemoryRef = useRef<Map<string, number>>(loadScrollMemory());
  const suppressHashRef = useRef<string | null>(null);
  const cancelPendingScrollRef = useRef<(() => void) | null>(null);

  // Sync system prefers-color-scheme live changes
  useEffect(() => {
    if (!window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (event: MediaQueryListEvent) => setSystemPrefersDark(event.matches);
    setSystemPrefersDark(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  // Apply .dark class to <html> and persist explicit preference
  useEffect(() => {
    document.documentElement.classList.toggle('dark', resolvedTheme === 'dark');
    try {
      if (themePref === 'system') localStorage.removeItem(THEME_STORAGE_KEY);
      else localStorage.setItem(THEME_STORAGE_KEY, themePref);
    } catch {
      // Ignore storage access errors in private iframes
    }
  }, [resolvedTheme, themePref]);

  // Per-route document title (tabs, history entries, shared links)
  useEffect(() => {
    document.title = computeTitle(route);
  }, [route]);

  // Remember scroll offsets per route so Back / Forward lands where the reader left off
  useEffect(() => {
    if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
    let raf = 0;
    const onScroll = () => {
      if (raf) return;
      raf = window.requestAnimationFrame(() => {
        raf = 0;
        scrollMemoryRef.current.set(routeRef.current, window.scrollY);
      });
    };
    const persist = () => {
      try {
        const entries = Array.from(scrollMemoryRef.current.entries()).slice(-40);
        sessionStorage.setItem(SCROLL_MEMORY_KEY, JSON.stringify(entries));
      } catch {
        // Ignore quota / privacy mode errors
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('pagehide', persist);
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('pagehide', persist);
      if (raf) window.cancelAnimationFrame(raf);
    };
  }, []);

  // Initial deep link with an in-page anchor (e.g. #/docs/commands#退出码)
  useEffect(() => {
    const { anchor } = parseHashRoute(window.location.hash);
    if (anchor) cancelPendingScrollRef.current = scrollToAnchorWhenReady(anchor);
  }, []);

  /**
   * Commits a route change inside a View Transition (soft cross-fade, header pinned),
   * then runs the post-navigation scroll behaviour against the freshly rendered DOM.
   */
  const commitRoute = useCallback((path: string, afterCommit: () => void) => {
    cancelPendingScrollRef.current?.();
    cancelPendingScrollRef.current = null;
    scrollMemoryRef.current.set(routeRef.current, window.scrollY);

    if (path === routeRef.current) {
      afterCommit();
      return;
    }

    const apply = () => {
      flushSync(() => setRoute(path));
      afterCommit();
    };

    const root = document.documentElement;
    const startViewTransition = getStartViewTransition();
    if (
      !startViewTransition ||
      prefersReducedMotion() ||
      root.classList.contains('theme-transitioning')
    ) {
      apply();
      return;
    }

    root.dataset.vt = 'route';
    try {
      const transition = startViewTransition(apply);
      transition.finished
        .catch(() => undefined)
        .finally(() => {
          if (root.dataset.vt === 'route') delete root.dataset.vt;
        });
    } catch {
      delete root.dataset.vt;
      apply();
    }
  }, []);

  // Browser Back / Forward (and manual hash edits)
  useEffect(() => {
    const onHashChange = () => {
      if (suppressHashRef.current !== null && window.location.hash === suppressHashRef.current) {
        suppressHashRef.current = null;
        return;
      }
      suppressHashRef.current = null;
      const parsed = parseHashRoute(window.location.hash);
      commitRoute(parsed.path, () => {
        if (parsed.anchor) {
          cancelPendingScrollRef.current = scrollToAnchorWhenReady(parsed.anchor);
        } else {
          const saved = scrollMemoryRef.current.get(parsed.path) ?? 0;
          cancelPendingScrollRef.current = restoreScrollWhenReady(saved);
        }
      });
    };
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, [commitRoute]);

  const navigate = useCallback(
    (targetRoute: string, anchor?: string) => {
      const normalized = targetRoute.startsWith('/') ? targetRoute : `/${targetRoute}`;
      const nextHash = `#${normalized}${anchor ? `#${anchor}` : ''}`;
      if (window.location.hash !== nextHash) {
        suppressHashRef.current = nextHash;
        window.location.hash = nextHash;
      }
      commitRoute(normalized, () => {
        if (anchor) {
          cancelPendingScrollRef.current = scrollToAnchorWhenReady(anchor);
        } else {
          window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
        }
      });
    },
    [commitRoute],
  );

  // Double-tap Shift opens the search palette from anywhere (IntelliJ-style)
  useEffect(() => {
    const detector = createDoubleShiftDetector();
    const onKeyDown = (event: KeyboardEvent) => {
      detector.keydown(event.key, event.timeStamp, event.repeat);
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (detector.keyup(event.key, event.timeStamp)) {
        setPaletteOpen((open) => !open);
      }
    };
    const onBlur = () => detector.reset();
    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
    window.addEventListener('blur', onBlur);
    return () => {
      window.removeEventListener('keydown', onKeyDown, true);
      window.removeEventListener('keyup', onKeyUp, true);
      window.removeEventListener('blur', onBlur);
    };
  }, []);

  const openPalette = useCallback(() => setPaletteOpen(true), []);
  const closePalette = useCallback(() => setPaletteOpen(false), []);

  const themeTransitionSeqRef = useRef(0);
  const waveRef = useRef<ThemeWaveHandle>(null);

  const handleToggleTheme = useCallback(
    (event?: MouseEvent<HTMLButtonElement>) => {
      const nextPref = nextThemePreference(themePref, systemPrefersDark);
      const nextResolved = resolveTheme(nextPref, systemPrefersDark);

      const applyThemeUpdate = () => {
        document.documentElement.classList.toggle('dark', nextResolved === 'dark');
        flushSync(() => setThemePref(nextPref));
      };

      const startViewTransition = getStartViewTransition();
      if (!startViewTransition || prefersReducedMotion()) {
        setThemePref(nextPref);
        return;
      }

      const viewport = { width: window.innerWidth, height: window.innerHeight };
      const fallbackRect = event?.currentTarget?.getBoundingClientRect();
      const origin = resolveThemeTransitionOrigin(
        event ? { clientX: event.clientX, clientY: event.clientY, detail: event.detail } : null,
        fallbackRect,
        viewport,
      );
      const geom: WaveGeometry = {
        originX: origin.x,
        originY: origin.y,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
      };

      const root = document.documentElement;
      const seq = ++themeTransitionSeqRef.current;
      waveRef.current?.stop();

      root.dataset.vt = 'theme';
      root.classList.add('theme-transitioning');
      const clipKeyframes = buildWaveClipKeyframes(geom, nextResolved);

      let cleanupTimer: number | null = null;
      const cleanup = () => {
        if (cleanupTimer !== null) {
          window.clearTimeout(cleanupTimer);
          cleanupTimer = null;
        }
        if (themeTransitionSeqRef.current === seq) {
          // Leave waveRef running so airborne seafoam particles dissolve cleanly past the transition
          if (root.dataset.vt === 'theme') delete root.dataset.vt;
          root.classList.remove('theme-transitioning');
        }
      };
      cleanupTimer = window.setTimeout(cleanup, WAVE_DURATION_MS + 500);

      let transition: ViewTransitionLike;
      try {
        transition = startViewTransition(applyThemeUpdate);
      } catch {
        waveRef.current?.stop();
        cleanup();
        setThemePref(nextPref);
        return;
      }

      transition.ready
        .then(() => {
          if (themeTransitionSeqRef.current !== seq) return;
          root.animate(
            { clipPath: clipKeyframes },
            {
              duration: WAVE_DURATION_MS,
              easing: 'linear',
              fill: 'both',
              pseudoElement: '::view-transition-new(root)',
            },
          );
          waveRef.current?.start(geom, nextResolved);
        })
        .catch(() => {
          // Ignore AbortError when rapid clicks supersede an active view transition
        });

      transition.finished.catch(() => undefined).finally(cleanup);
    },
    [themePref, systemPrefersDark],
  );

  const activeSection = getActiveSection(route);
  const isDocsRoute = activeSection === 'docs' || activeSection === 'skills';
  const docSlug = isDocsRoute ? route.replace(/^\/docs\/?/, '') || 'quickstart' : 'quickstart';

  return (
    <div
      data-theme={resolvedTheme}
      className="relative flex min-h-screen flex-col text-slate-900 transition-colors dark:text-slate-100"
    >
      <AmbientBackground reactive={activeSection === 'home'} />

      <TopNav
        activeSection={activeSection === 'unknown' ? null : activeSection}
        onNavigate={navigate}
        resolvedTheme={resolvedTheme}
        themePreference={themePref}
        onToggleTheme={handleToggleTheme}
        onOpenSearch={openPalette}
      />

      <main className="flex-1">
        {activeSection === 'home' && (
          <>
            <HeroSection theme={resolvedTheme} onNavigate={navigate} />
            <ScrollStorySection onNavigate={navigate} />
            <EcosystemFlowSection />
            <ArchitectureBento onNavigate={navigate} />
          </>
        )}

        {isDocsRoute && (
          <Suspense fallback={<RouteFallback />}>
            <DocsLayout slug={docSlug} onNavigate={navigate} onOpenSearch={openPalette} />
          </Suspense>
        )}

        {activeSection === 'changelog' && (
          <Suspense fallback={<RouteFallback />}>
            <ChangelogPage onNavigate={navigate} />
          </Suspense>
        )}

        {activeSection === 'unknown' && (
          <NotFound path={route} onNavigate={navigate} onOpenSearch={openPalette} />
        )}
      </main>

      <Footer onNavigate={navigate} />

      <CommandPalette open={paletteOpen} onClose={closePalette} onNavigate={navigate} />

      <ThemeWaveOverlay ref={waveRef} />
    </div>
  );
}
