interface FooterProps {
  onNavigate: (route: string) => void;
}

export function Footer({ onNavigate }: FooterProps) {
  return (
    <footer className="border-t border-slate-900/[0.07] py-10 text-xs text-slate-500 dark:border-white/[0.07] dark:text-slate-400">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-4 px-6 sm:flex-row sm:items-center">
        <div className="flex items-center gap-3">
          <span className="font-display text-sm font-semibold text-slate-900 dark:text-slate-100">
            moonset
          </span>
          <span aria-hidden="true">·</span>
          <span>MIT Licensed · Crafted for MoonBit</span>
        </div>

        <div className="flex flex-wrap items-center gap-5">
          <a
            href="#/docs/quickstart"
            onClick={(e) => {
              e.preventDefault();
              onNavigate('/docs/quickstart');
            }}
            className="transition-colors hover:text-slate-950 dark:hover:text-white"
          >
            文档
          </a>
          <a
            href="#/docs/decisions/overview"
            onClick={(e) => {
              e.preventDefault();
              onNavigate('/docs/decisions/overview');
            }}
            className="transition-colors hover:text-slate-950 dark:hover:text-white"
          >
            ADR
          </a>
          <a
            href="#/changelog"
            onClick={(e) => {
              e.preventDefault();
              onNavigate('/changelog');
            }}
            className="transition-colors hover:text-slate-950 dark:hover:text-white"
          >
            更新日志
          </a>
          <a
            href="https://github.com/unmbt/moonset"
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-slate-950 dark:hover:text-white"
          >
            GitHub
          </a>
        </div>
      </div>
    </footer>
  );
}
