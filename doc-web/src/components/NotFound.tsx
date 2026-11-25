import { ArrowLeft, ArrowRight, Search } from 'lucide-react';
import { sectionTitleOf, suggestDocs } from '../lib/search';
import { delayStyle } from './motion';

interface NotFoundProps {
  path: string;
  onNavigate: (route: string) => void;
  onOpenSearch: () => void;
}

/** Friendly 404 for unknown routes / doc slugs, with "did you mean" suggestions. */
export function NotFound({ path, onNavigate, onOpenSearch }: NotFoundProps) {
  const slug = path.replace(/^\/(docs\/)?/, '');
  const suggestions = suggestDocs(slug);

  return (
    <div className="mx-auto max-w-2xl px-6 py-20 sm:py-28">
      <div style={delayStyle(0)} className="moonset-enter font-mono text-xs text-slate-500 dark:text-slate-400">
        404 · <span className="break-all">{path}</span>
      </div>
      <h1
        style={delayStyle(60)}
        className="moonset-enter moonset-cjk-heading font-display mt-3 text-[clamp(2rem,4vw,2.8rem)] font-bold tracking-[-0.025em] text-slate-950 dark:text-white"
      >
        这一页，月色未至。
      </h1>
      <p
        style={delayStyle(120)}
        className="moonset-enter mt-4 text-[0.97rem] leading-relaxed text-slate-600 dark:text-slate-400"
      >
        链接可能已经改名或被移除。你是不是在找下面这些文档？
      </p>

      <ul style={delayStyle(180)} className="moonset-enter mt-8 grid gap-3 sm:grid-cols-2">
        {suggestions.map((item) => (
          <li key={item.slug}>
            <a
              href={`#/docs/${item.slug}`}
              onClick={(e) => {
                e.preventDefault();
                onNavigate(`/docs/${item.slug}`);
              }}
              className="group flex h-full flex-col rounded-xl border border-slate-900/[0.08] bg-white/70 p-4 transition-[border-color,transform] duration-200 hover:-translate-y-0.5 hover:border-indigo-500/40 dark:border-white/[0.08] dark:bg-white/[0.02] dark:hover:border-indigo-400/40"
            >
              <span className="text-[11px] text-slate-500 dark:text-slate-400">{sectionTitleOf(item)}</span>
              <span className="mt-1 inline-flex items-center gap-1.5 text-sm font-medium text-slate-950 transition-colors group-hover:text-indigo-600 dark:text-white dark:group-hover:text-indigo-300">
                {item.title}
                <ArrowRight className="h-3.5 w-3.5 -translate-x-1 opacity-0 transition-all duration-200 group-hover:translate-x-0 group-hover:opacity-100" />
              </span>
              {item.subtitle && (
                <span className="mt-1 text-xs text-slate-500 dark:text-slate-400">{item.subtitle}</span>
              )}
            </a>
          </li>
        ))}
      </ul>

      <div style={delayStyle(240)} className="moonset-enter mt-10 flex flex-wrap items-center gap-3">
        <a
          href="#/"
          onClick={(e) => {
            e.preventDefault();
            onNavigate('/');
          }}
          className="inline-flex h-10 items-center gap-1.5 rounded-xl bg-slate-950 px-4 text-sm font-medium text-white transition-colors hover:bg-slate-800 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
        >
          <ArrowLeft className="h-4 w-4" />
          返回首页
        </a>
        <button
          type="button"
          onClick={onOpenSearch}
          className="inline-flex h-10 items-center gap-2 rounded-xl border border-slate-900/[0.1] px-4 text-sm text-slate-700 transition-colors hover:border-slate-900/[0.2] dark:border-white/[0.1] dark:text-slate-300 dark:hover:border-white/[0.2]"
        >
          <Search className="h-4 w-4" />
          搜索文档
          <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono text-[10px] text-slate-500 dark:border-white/[0.12] dark:text-slate-400">
            ⇧⇧
          </kbd>
        </button>
      </div>
    </div>
  );
}
