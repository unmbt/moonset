import { useCallback, useEffect, useRef, useState, type MouseEvent } from 'react';
import { flushSync } from 'react-dom';
import {
  THEME_STORAGE_KEY,
  THEME_TRANSITION_DURATION_MS,
  THEME_TRANSITION_EASING,
  computeCircularRevealGeometry,
  nextThemePreference,
  parseStoredTheme,
  resolveTheme,
  resolveThemeTransitionOrigin,
  type ThemePreference,
} from './lib/theme';
import { AmbientBackground } from './components/AmbientBackground';
import { TopNav, type ActiveRouteSection } from './components/TopNav';
import { HeroSection } from './components/HeroSection';
import { ScrollStorySection } from './components/ScrollStorySection';
import { EcosystemFlowSection } from './components/EcosystemFlowSection';
import { ArchitectureBento } from './components/ArchitectureBento';
import { DocsLayout } from './components/DocsLayout';
import { ChangelogPage } from './components/ChangelogPage';
import { Footer } from './components/Footer';
import { useSmoothScroll } from './hooks/useSmoothScroll';

function parseHashRoute(hash: string): { path: string; anchor?: string } {
  const cleaned = hash.replace(/^#/, '');
  if (!cleaned || cleaned === '/') {
    return { path: '/' };
  }
  const normalized = cleaned.startsWith('/') ? cleaned : `/${cleaned}`;
  const [path, anchor] = normalized.split('#');
  return { path: path || '/', anchor };
}

function getActiveSection(path: string): ActiveRouteSection {
  if (path === '/changelog') return 'changelog';
  if (path.startsWith('/docs/decisions')) return 'decisions';
  if (path.startsWith('/docs')) return 'docs';
  return 'home';
}

export function App() {
  useSmoothScroll();
  const [route, setRoute] = useState<string>(() => parseHashRoute(window.location.hash).path);
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

  // Sync system prefers-color-scheme live changes
  useEffect(() => {
    if (!window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (event: MediaQueryListEvent) => {
      setSystemPrefersDark(event.matches);
    };
    setSystemPrefersDark(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  // Apply .dark class to <html> and persist explicit preference
  useEffect(() => {
    const root = document.documentElement;
    if (resolvedTheme === 'dark') {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }
    try {
      if (themePref === 'system') {
        localStorage.removeItem(THEME_STORAGE_KEY);
      } else {
        localStorage.setItem(THEME_STORAGE_KEY, themePref);
      }
    } catch {
      // Ignore storage access errors in private iframes
    }
  }, [resolvedTheme, themePref]);

  // Listen to browser hash navigation
  useEffect(() => {
    const onHashChange = () => {
      const parsed = parseHashRoute(window.location.hash);
      setRoute(parsed.path);
      if (parsed.anchor) {
        window.setTimeout(() => {
          document.getElementById(parsed.anchor!)?.scrollIntoView({ behavior: 'smooth' });
        }, 60);
      } else {
        window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
      }
    };
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  const navigate = useCallback((targetRoute: string, anchor?: string) => {
    const normalized = targetRoute.startsWith('/') ? targetRoute : `/${targetRoute}`;
    window.location.hash = `#${normalized}`;
    setRoute(normalized);

    if (anchor) {
      window.setTimeout(() => {
        const el = document.getElementById(anchor);
        el?.scrollIntoView({ behavior: 'smooth' });
      }, 60);
    } else {
      window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
    }
  }, []);

  const themeTransitionSeqRef = useRef(0);

  const handleToggleTheme = useCallback(
    (event?: MouseEvent<HTMLButtonElement>) => {
      const nextPref = nextThemePreference(themePref, systemPrefersDark);
      const nextResolved = resolveTheme(nextPref, systemPrefersDark);

      const applyThemeUpdate = () => {
        document.documentElement.classList.toggle('dark', nextResolved === 'dark');
        flushSync(() => {
          setThemePref(nextPref);
        });
      };

      const prefersReducedMotion =
        typeof window !== 'undefined' &&
        window.matchMedia &&
        window.matchMedia('(prefers-reduced-motion: reduce)').matches;

      const startViewTransition = (
        document as Document & {
          startViewTransition?: (updateCallback: () => void) => {
            ready: Promise<void>;
            finished: Promise<void>;
          };
        }
      ).startViewTransition?.bind(document);

      if (!startViewTransition || prefersReducedMotion) {
        setThemePref(nextPref);
        return;
      }

      const viewport = {
        width: window.innerWidth,
        height: window.innerHeight,
      };
      const fallbackRect = event?.currentTarget?.getBoundingClientRect();
      const origin = resolveThemeTransitionOrigin(
        event ? { clientX: event.clientX, clientY: event.clientY, detail: event.detail } : null,
        fallbackRect,
        viewport,
      );
      const { x, y, endRadius } = computeCircularRevealGeometry(origin, viewport);

      const root = document.documentElement;
      const seq = ++themeTransitionSeqRef.current;
      root.classList.add('theme-transitioning');

      let cleanupTimer: number | null = null;
      const cleanup = () => {
        if (cleanupTimer !== null) {
          window.clearTimeout(cleanupTimer);
          cleanupTimer = null;
        }
        if (themeTransitionSeqRef.current === seq) {
          root.classList.remove('theme-transitioning');
        }
      };

      cleanupTimer = window.setTimeout(cleanup, THEME_TRANSITION_DURATION_MS + 450);

      let transition: { ready: Promise<void>; finished: Promise<void> };
      try {
        transition = startViewTransition(() => {
          applyThemeUpdate();
        });
      } catch {
        cleanup();
        setThemePref(nextPref);
        return;
      }

      transition.ready
        .then(() => {
          root.animate(
            {
              clipPath: [
                `circle(0px at ${x}px ${y}px)`,
                `circle(${endRadius}px at ${x}px ${y}px)`,
              ],
            },
            {
              duration: THEME_TRANSITION_DURATION_MS,
              easing: THEME_TRANSITION_EASING,
              fill: 'both',
              pseudoElement: '::view-transition-new(root)',
            },
          );
        })
        .catch(() => {
          // Ignore AbortError when rapid clicks supersede an active view transition
        });

      transition.finished
        .catch(() => {
          // Ignore aborted transition rejections
        })
        .finally(cleanup);
    },
    [themePref, systemPrefersDark],
  );

  const activeSection = getActiveSection(route);
  const isDocsRoute = route.startsWith('/docs');
  const docSlug = isDocsRoute
    ? route.replace(/^\/docs\/?/, '') || 'quickstart'
    : 'quickstart';

  return (
    <div
      data-theme={resolvedTheme}
      className="relative flex min-h-screen flex-col text-slate-900 transition-colors dark:text-slate-100"
    >
      <AmbientBackground reactive={activeSection === 'home'} />

      <TopNav
        activeSection={activeSection}
        onNavigate={navigate}
        resolvedTheme={resolvedTheme}
        themePreference={themePref}
        onToggleTheme={handleToggleTheme}
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

        {isDocsRoute && <DocsLayout slug={docSlug} onNavigate={navigate} />}

        {activeSection === 'changelog' && (
          <ChangelogPage onNavigate={navigate} />
        )}
      </main>

      <Footer onNavigate={navigate} />
    </div>
  );
}
