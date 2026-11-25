import { ArrowUpRight } from 'lucide-react';
import { MOONSET_VERSION } from '../lib/version';

interface FooterProps {
  onNavigate: (route: string) => void;
}

interface FooterLink {
  label: string;
  route?: string;
  href?: string;
}

const COLUMNS: Array<{ title: string; links: FooterLink[] }> = [
  {
    title: '文档',
    links: [
      { label: '快速开始', route: '/docs/quickstart' },
      { label: 'CLI 命令契约', route: '/docs/commands' },
      { label: '配置规范', route: '/docs/configuration' },
      { label: '常见问题', route: '/docs/faq' },
    ],
  },
  {
    title: '生态',
    links: [
      { label: '混合 Workspace', route: '/docs/mixed-workspaces' },
      { label: 'GitHub Actions', route: '/docs/automation' },
      { label: '编程 API 与插件', route: '/docs/api' },
      { label: 'mooncakes.io', href: 'https://mooncakes.io' },
    ],
  },
  {
    title: '项目',
    links: [
      { label: '架构决策 (ADR)', route: '/docs/decisions/overview' },
      { label: '更新日志', route: '/changelog' },
      { label: 'GitHub 仓库', href: 'https://github.com/unmbt/moonset' },
      { label: '问题反馈', href: 'https://github.com/unmbt/moonset/issues' },
    ],
  },
];

export function Footer({ onNavigate }: FooterProps) {
  return (
    <footer className="border-t border-slate-900/[0.07] text-sm text-slate-500 dark:border-white/[0.07] dark:text-slate-400">
      <div className="mx-auto grid max-w-6xl grid-cols-2 gap-10 px-5 py-14 sm:px-6 md:grid-cols-[1.4fr_1fr_1fr_1fr]">
        <div className="col-span-2 md:col-span-1">
          <a
            href="#/"
            onClick={(e) => {
              e.preventDefault();
              onNavigate('/');
            }}
            className="font-display inline-flex items-center gap-2 text-base font-bold tracking-tight text-slate-950 dark:text-white"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24" className="h-4.5 w-4.5 text-indigo-600 dark:text-indigo-400" fill="currentColor">
              <path d="M15.2 4.2a8.2 8.2 0 1 0 4.6 14.9A6.8 6.8 0 0 1 15.2 4.2z" />
            </svg>
            moonset
          </a>
          <p className="mt-3 max-w-xs text-[13px] leading-relaxed">
            月升则潮起，版本有序，更迭有据。为 MoonBit workspace 而生的版本规划与多生态发布工具。
          </p>
          <div className="mt-4 inline-flex items-center gap-2 rounded-full border border-slate-900/[0.08] px-2.5 py-1 font-mono text-[11px] dark:border-white/[0.08]">
            <span className="moonset-live-dot" aria-hidden="true" />
            v{MOONSET_VERSION} · MIT
          </div>
        </div>

        {COLUMNS.map((column) => (
          <nav key={column.title} aria-label={column.title}>
            <div className="text-xs font-semibold text-slate-900 dark:text-slate-100">{column.title}</div>
            <ul className="mt-4 space-y-2.5 text-[13px]">
              {column.links.map((link) => (
                <li key={link.label}>
                  {link.route ? (
                    <a
                      href={`#${link.route}`}
                      onClick={(e) => {
                        e.preventDefault();
                        onNavigate(link.route!);
                      }}
                      className="transition-colors hover:text-slate-950 dark:hover:text-white"
                    >
                      {link.label}
                    </a>
                  ) : (
                    <a
                      href={link.href}
                      target="_blank"
                      rel="noreferrer"
                      className="group inline-flex items-center gap-0.5 transition-colors hover:text-slate-950 dark:hover:text-white"
                    >
                      {link.label}
                      <ArrowUpRight className="h-3 w-3 opacity-50 transition-[opacity,transform] group-hover:-translate-y-px group-hover:translate-x-px group-hover:opacity-100" />
                    </a>
                  )}
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>

      <div className="border-t border-slate-900/[0.06] dark:border-white/[0.06]">
        <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-2 px-5 py-5 text-xs sm:flex-row sm:items-center sm:px-6">
          <span>MIT Licensed · Crafted for MoonBit</span>
          <span className="inline-flex items-center gap-1.5">
            随时双击
            <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono text-[10px] dark:border-white/[0.12]">Shift</kbd>
            搜索文档
          </span>
        </div>
      </div>
    </footer>
  );
}
