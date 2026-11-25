import { useEffect, useLayoutEffect, useRef, useState, type MouseEvent } from 'react';
import { Menu, Moon, Search, Sun, X } from 'lucide-react';
import type { ResolvedTheme, ThemePreference } from '../lib/theme';
import { prefetchDocs } from '../lib/docsLoader';

export type ActiveRouteSection = 'home' | 'docs' | 'skills' | 'changelog';

interface TopNavProps {
  activeSection: ActiveRouteSection | null;
  onNavigate: (route: string) => void;
  resolvedTheme: ResolvedTheme;
  themePreference: ThemePreference;
  onToggleTheme: (event: MouseEvent<HTMLButtonElement>) => void;
  onOpenSearch: () => void;
}

const NAV_LINKS: Array<{ id: ActiveRouteSection; label: string; route: string }> = [
  { id: 'home', label: '首页', route: '/' },
  { id: 'docs', label: '文档', route: '/docs/quickstart' },
  { id: 'skills', label: 'Skills', route: '/docs/skills/moonset' },
  { id: 'changelog', label: '更新日志', route: '/changelog' },
];

export function TopNav({
  activeSection,
  onNavigate,
  resolvedTheme,
  themePreference,
  onToggleTheme,
  onOpenSearch,
}: TopNavProps) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const navRef = useRef<HTMLElement>(null);
  const linkRefs = useRef<Partial<Record<ActiveRouteSection, HTMLAnchorElement | null>>>({});
  const headerRef = useRef<HTMLElement>(null);
  const [indicator, setIndicator] = useState<{ x: number; w: number; visible: boolean }>({
    x: 0,
    w: 0,
    visible: false,
  });
  const [indicatorAnimated, setIndicatorAnimated] = useState(false);

  const themeLabel =
    resolvedTheme === 'dark'
      ? themePreference === 'system'
        ? '当前深色模式（跟随系统），点击切换浅色'
        : '当前深色模式，点击切换外观'
      : themePreference === 'system'
        ? '当前浅色模式（跟随系统），点击切换深色'
        : '当前浅色模式，点击切换外观';

  // Sliding active-link indicator measured from the real link geometry
  useLayoutEffect(() => {
    const measure = () => {
      const nav = navRef.current;
      const link = activeSection ? linkRefs.current[activeSection] : null;
      if (!nav || !link) {
        setIndicator((prev) => ({ ...prev, visible: false }));
        return;
      }
      const navRect = nav.getBoundingClientRect();
      const rect = link.getBoundingClientRect();
      setIndicator({ x: rect.left - navRect.left, w: rect.width, visible: true });
    };
    measure();
    window.addEventListener('resize', measure);
    document.fonts?.ready.then(measure).catch(() => undefined);
    return () => window.removeEventListener('resize', measure);
  }, [activeSection]);

  // Enable the slide transition only after the first placement (no initial fly-in)
  useEffect(() => {
    const id = window.requestAnimationFrame(() => setIndicatorAnimated(true));
    return () => window.cancelAnimationFrame(id);
  }, []);

  // Mobile menu: close on Escape or outside click
  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMobileOpen(false);
    };
    const onPointer = (e: PointerEvent) => {
      if (headerRef.current && !headerRef.current.contains(e.target as Node)) setMobileOpen(false);
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('pointerdown', onPointer);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('pointerdown', onPointer);
    };
  }, [mobileOpen]);

  const handleNav = (route: string) => {
    setMobileOpen(false);
    onNavigate(route);
  };

  return (
    <header
      ref={headerRef}
      className="moonset-site-header sticky top-0 z-40 border-b border-slate-900/[0.07] bg-[#FAFAFC]/80 backdrop-blur-md backdrop-saturate-150 transition-colors dark:border-white/[0.07] dark:bg-[#08090E]/78"
    >
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-6 px-5 sm:px-6">
        <a
          href="#/"
          onClick={(e) => {
            e.preventDefault();
            handleNav('/');
          }}
          className="group font-display inline-flex shrink-0 items-center gap-2.5 text-[1.125rem] font-bold tracking-tight whitespace-nowrap text-slate-950 dark:text-white"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            className="h-5 w-5 text-indigo-600 transition-transform duration-500 ease-out group-hover:-rotate-[18deg] dark:text-indigo-400"
            fill="currentColor"
          >
            <path d="M15.2 4.2a8.2 8.2 0 1 0 4.6 14.9A6.8 6.8 0 0 1 15.2 4.2z" />
          </svg>
          moonset
        </a>

        <nav
          ref={navRef}
          aria-label="主导航"
          className="relative hidden h-full items-center gap-7 md:flex"
        >
          {NAV_LINKS.map((link) => {
            const isActive = activeSection === link.id;
            return (
              <a
                key={link.id}
                ref={(el) => {
                  linkRefs.current[link.id] = el;
                }}
                href={`#${link.route}`}
                onClick={(e) => {
                  e.preventDefault();
                  handleNav(link.route);
                }}
                onPointerEnter={link.id === 'home' ? undefined : prefetchDocs}
                aria-current={isActive ? 'page' : undefined}
                className={`relative py-1 text-sm font-medium whitespace-nowrap transition-colors ${
                  isActive
                    ? 'text-slate-950 dark:text-white'
                    : 'text-slate-600 hover:text-slate-950 dark:text-slate-400 dark:hover:text-white'
                }`}
              >
                {link.label}
              </a>
            );
          })}
          <span
            aria-hidden="true"
            className={`pointer-events-none absolute -bottom-px left-0 h-[2px] rounded-full bg-indigo-600 dark:bg-indigo-400 ${
              indicatorAnimated ? 'transition-[transform,width,opacity] duration-300 ease-[cubic-bezier(0.22,0.8,0.24,1)]' : ''
            }`}
            style={{
              width: indicator.w,
              transform: `translateX(${indicator.x}px)`,
              opacity: indicator.visible ? 1 : 0,
            }}
          />
        </nav>

        <div className="flex shrink-0 items-center gap-1.5 sm:gap-2.5">
          <button
            type="button"
            onClick={onOpenSearch}
            onPointerEnter={prefetchDocs}
            aria-label="搜索文档（双击 Shift）"
            title="搜索文档（双击 Shift）"
            className="group hidden h-9 items-center gap-2 rounded-lg border border-slate-900/[0.09] bg-white/60 pr-1.5 pl-3 text-xs text-slate-500 transition-colors hover:border-slate-900/[0.16] hover:text-slate-800 lg:inline-flex dark:border-white/[0.09] dark:bg-white/[0.03] dark:text-slate-400 dark:hover:border-white/[0.16] dark:hover:text-slate-200"
          >
            <Search className="h-3.5 w-3.5" />
            <span className="pr-4">搜索文档</span>
            <kbd className="rounded-md border border-slate-900/[0.08] bg-slate-900/[0.03] px-1.5 py-0.5 font-mono text-[10px] tracking-wider text-slate-500 dark:border-white/[0.1] dark:bg-white/[0.04] dark:text-slate-400">
              ⇧⇧
            </kbd>
          </button>

          <button
            type="button"
            onClick={onOpenSearch}
            aria-label="搜索文档"
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-slate-600 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-950 lg:hidden dark:text-slate-400 dark:hover:bg-white/[0.06] dark:hover:text-white"
          >
            <Search className="h-[17px] w-[17px]" />
          </button>

          <button
            type="button"
            onClick={onToggleTheme}
            aria-label={themeLabel}
            title={themeLabel}
            className="relative inline-flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden rounded-lg text-slate-600 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-950 dark:text-slate-400 dark:hover:bg-white/[0.06] dark:hover:text-white"
          >
            <Sun
              className={`absolute h-[17px] w-[17px] transition-all duration-500 ${
                resolvedTheme === 'dark' ? 'rotate-0 scale-100 opacity-100' : '-rotate-90 scale-50 opacity-0'
              }`}
            />
            <Moon
              className={`absolute h-[17px] w-[17px] transition-all duration-500 ${
                resolvedTheme === 'dark' ? 'rotate-90 scale-50 opacity-0' : 'rotate-0 scale-100 opacity-100'
              }`}
            />
          </button>

          <a
            href="#/docs/quickstart"
            onClick={(e) => {
              e.preventDefault();
              handleNav('/docs/quickstart');
            }}
            onPointerEnter={prefetchDocs}
            className="hidden shrink-0 items-center rounded-lg bg-slate-950 px-4 py-2 text-xs font-medium whitespace-nowrap text-white transition-[background-color,transform] duration-200 hover:-translate-y-px hover:bg-slate-800 sm:inline-flex dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
          >
            快速开始
          </a>

          <button
            type="button"
            onClick={() => setMobileOpen((prev) => !prev)}
            aria-label={mobileOpen ? '关闭导航菜单' : '打开导航菜单'}
            aria-expanded={mobileOpen}
            aria-controls="mobile-nav"
            className="relative inline-flex h-10 w-10 items-center justify-center rounded-lg text-slate-700 transition-colors hover:bg-slate-900/[0.05] md:hidden dark:text-slate-300 dark:hover:bg-white/[0.06]"
          >
            <Menu
              className={`absolute h-5 w-5 transition-all duration-300 ${mobileOpen ? 'rotate-90 scale-50 opacity-0' : 'opacity-100'}`}
            />
            <X
              className={`absolute h-5 w-5 transition-all duration-300 ${mobileOpen ? 'opacity-100' : '-rotate-90 scale-50 opacity-0'}`}
            />
          </button>
        </div>
      </div>

      {/* Mobile navigation: animated disclosure (grid-rows 0fr → 1fr) */}
      <div
        id="mobile-nav"
        className={`grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.22,0.8,0.24,1)] md:hidden ${
          mobileOpen ? 'grid-rows-[1fr] opacity-100' : 'pointer-events-none grid-rows-[0fr] opacity-0'
        }`}
        inert={!mobileOpen}
      >
        <div className="overflow-hidden">
          <nav
            aria-label="移动端导航"
            className="flex flex-col gap-1 border-t border-slate-900/[0.07] px-5 py-4 dark:border-white/[0.07]"
          >
            {NAV_LINKS.map((link, idx) => {
              const isActive = activeSection === link.id;
              return (
                <a
                  key={link.id}
                  href={`#${link.route}`}
                  onClick={(e) => {
                    e.preventDefault();
                    handleNav(link.route);
                  }}
                  style={{ transitionDelay: mobileOpen ? `${60 + idx * 35}ms` : '0ms' }}
                  className={`rounded-lg px-3 py-2.5 text-sm font-medium transition-[background-color,color,opacity,transform] duration-300 ${
                    mobileOpen ? 'translate-y-0 opacity-100' : '-translate-y-1 opacity-0'
                  } ${
                    isActive
                      ? 'bg-indigo-600/10 text-indigo-700 dark:bg-indigo-400/12 dark:text-indigo-300'
                      : 'text-slate-700 hover:bg-slate-900/[0.04] dark:text-slate-300 dark:hover:bg-white/[0.05]'
                  }`}
                >
                  {link.label}
                </a>
              );
            })}
            <a
              href="https://github.com/unmbt/moonset"
              target="_blank"
              rel="noreferrer"
              className="mt-2 rounded-lg border border-slate-900/10 px-3 py-2.5 text-center text-sm font-medium text-slate-800 dark:border-white/10 dark:text-slate-200"
            >
              GitHub 仓库
            </a>
          </nav>
        </div>
      </div>
    </header>
  );
}
