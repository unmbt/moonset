import { useState, type MouseEvent } from 'react';
import { Menu, Moon, Sun, X } from 'lucide-react';
import type { ResolvedTheme, ThemePreference } from '../lib/theme';

export type ActiveRouteSection = 'home' | 'docs' | 'decisions' | 'changelog';

interface TopNavProps {
  activeSection: ActiveRouteSection;
  onNavigate: (route: string) => void;
  resolvedTheme: ResolvedTheme;
  themePreference: ThemePreference;
  onToggleTheme: (event: MouseEvent<HTMLButtonElement>) => void;
}

const NAV_LINKS: Array<{
  id: ActiveRouteSection;
  label: string;
  route: string;
}> = [
  { id: 'home', label: '首页', route: '/' },
  { id: 'docs', label: '文档', route: '/docs/quickstart' },
  { id: 'decisions', label: '架构决策', route: '/docs/decisions/overview' },
  { id: 'changelog', label: '更新日志', route: '/changelog' },
];

export function TopNav({
  activeSection,
  onNavigate,
  resolvedTheme,
  themePreference,
  onToggleTheme,
}: TopNavProps) {
  const [mobileOpen, setMobileOpen] = useState(false);

  const themeLabel =
    resolvedTheme === 'dark'
      ? themePreference === 'system'
        ? '当前深色模式（跟随系统），点击切换浅色'
        : '当前深色模式，点击切换外观'
      : themePreference === 'system'
        ? '当前浅色模式（跟随系统），点击切换深色'
        : '当前浅色模式，点击切换外观';

  const handleNav = (route: string) => {
    setMobileOpen(false);
    onNavigate(route);
  };

  return (
    <header className="sticky top-0 z-40 border-b border-slate-900/[0.07] bg-[#FAFAFC]/82 backdrop-blur-md transition-colors dark:border-white/[0.07] dark:bg-[#08090E]/82">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-8 px-6">
        {/* Zone 1: Single clean wordmark */}
        <a
          href="#/"
          onClick={(e) => {
            e.preventDefault();
            handleNav('/');
          }}
          className="font-display inline-flex shrink-0 items-center gap-2.5 text-[1.125rem] font-bold tracking-tight whitespace-nowrap text-slate-950 transition-opacity hover:opacity-80 dark:text-white"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            className="h-5 w-5 text-indigo-600 dark:text-indigo-400"
            fill="currentColor"
          >
            <path d="M15.2 4.2a8.2 8.2 0 1 0 4.6 14.9A6.8 6.8 0 0 1 15.2 4.2z" />
          </svg>
          moonset
        </a>

        {/* Zone 2: Clean single-line navigation links */}
        <nav
          aria-label="主导航"
          className="hidden items-center gap-7 md:flex"
        >
          {NAV_LINKS.map((link) => {
            const isActive = activeSection === link.id;
            return (
              <a
                key={link.id}
                href={`#${link.route}`}
                onClick={(e) => {
                  e.preventDefault();
                  handleNav(link.route);
                }}
                aria-current={isActive ? 'page' : undefined}
                className={`relative py-1 text-sm font-medium whitespace-nowrap shrink-0 transition-colors ${
                  isActive
                    ? 'text-slate-950 dark:text-white'
                    : 'text-slate-600 hover:text-slate-950 dark:text-slate-400 dark:hover:text-white'
                }`}
              >
                {link.label}
                {isActive && (
                  <span
                    aria-hidden="true"
                    className="absolute inset-x-0 -bottom-[21px] h-[1.5px] bg-indigo-600 dark:bg-indigo-400"
                  />
                )}
              </a>
            );
          })}
        </nav>

        {/* Zone 3: Theme switcher + single primary action */}
        <div className="flex shrink-0 items-center gap-3">
          <button
            type="button"
            onClick={onToggleTheme}
            aria-label={themeLabel}
            title={themeLabel}
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-slate-600 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 dark:text-slate-400 dark:hover:bg-white/[0.06] dark:hover:text-white"
          >
            {resolvedTheme === 'dark' ? (
              <Sun className="h-[17px] w-[17px]" />
            ) : (
              <Moon className="h-[17px] w-[17px]" />
            )}
          </button>

          <a
            href="#/docs/quickstart"
            onClick={(e) => {
              e.preventDefault();
              handleNav('/docs/quickstart');
            }}
            className="hidden shrink-0 items-center rounded-lg bg-slate-950 px-4 py-2 text-xs font-medium whitespace-nowrap text-white transition-colors hover:bg-slate-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 sm:inline-flex dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
          >
            快速开始
          </a>

          <button
            type="button"
            onClick={() => setMobileOpen((prev) => !prev)}
            aria-label={mobileOpen ? '关闭导航菜单' : '打开导航菜单'}
            aria-expanded={mobileOpen}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-slate-700 hover:bg-slate-900/[0.05] md:hidden dark:text-slate-300 dark:hover:bg-white/[0.06]"
          >
            {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {/* Mobile navigation drawer */}
      {mobileOpen && (
        <div className="border-t border-slate-900/[0.07] bg-[#FAFAFC] px-6 py-4 md:hidden dark:border-white/[0.07] dark:bg-[#08090E]">
          <nav aria-label="移动端导航" className="flex flex-col gap-1">
            {NAV_LINKS.map((link) => {
              const isActive = activeSection === link.id;
              return (
                <a
                  key={link.id}
                  href={`#${link.route}`}
                  onClick={(e) => {
                    e.preventDefault();
                    handleNav(link.route);
                  }}
                  className={`rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
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
      )}
    </header>
  );
}
