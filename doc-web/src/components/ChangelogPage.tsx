import { useMemo } from 'react';
import { ExternalLink } from 'lucide-react';
import { getChangelogRaw } from '../lib/docsLoader';
import { parseChangelog } from '../lib/markdown';

interface ChangelogPageProps {
  onNavigate: (route: string) => void;
}

function renderInlineCode(text: string) {
  const parts = text.split(/(`[^`]+`)/g);
  return parts.map((part, i) => {
    if (part.startsWith('`') && part.endsWith('`') && part.length > 2) {
      return (
        <code
          key={i}
          className="rounded border border-slate-900/[0.08] bg-slate-900/[0.04] px-1.5 py-0.5 font-mono text-[0.84em] text-slate-900 dark:border-white/[0.08] dark:bg-white/[0.05] dark:text-slate-100"
        >
          {part.slice(1, -1)}
        </code>
      );
    }
    return <span key={i}>{part}</span>;
  });
}

export function ChangelogPage({ onNavigate }: ChangelogPageProps) {
  const releases = useMemo(() => parseChangelog(getChangelogRaw()), []);

  return (
    <div className="mx-auto max-w-4xl px-6 py-14 sm:py-20">
      <div className="border-b border-slate-900/[0.08] pb-10 dark:border-white/[0.08]">
        <div className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400">
          <span>版本演进</span>
          <span aria-hidden="true">·</span>
          <span className="font-mono">CHANGELOG.md</span>
        </div>
        <h1 className="font-display mt-3 text-[clamp(2rem,3.6vw,2.85rem)] font-bold tracking-[-0.025em] text-slate-950 dark:text-white">
          更新日志
        </h1>
        <p className="mt-3 max-w-2xl text-sm leading-relaxed text-slate-600 sm:text-base dark:text-slate-400">
          由 <code className="font-mono text-xs text-slate-800 dark:text-slate-200">moonset</code> 自身以 dogfooding 方式维护的发布记录，完整追踪每次功能演进与契约落地。
        </p>
      </div>

      {/* Editorial release timeline */}
      <div className="relative mt-12 pl-7 sm:pl-9">
        <div
          aria-hidden="true"
          className="absolute top-2 bottom-2 left-2 w-px bg-slate-900/[0.09] dark:bg-white/[0.09]"
        />

        <div className="space-y-14">
          {releases.map((release, idx) => (
            <section key={release.version} className="relative">
              <span
                aria-hidden="true"
                className={`absolute top-2 -left-[25px] h-3 w-3 rounded-full border sm:-left-[33px] ${
                  idx === 0
                    ? 'border-indigo-600 bg-indigo-600 dark:border-indigo-400 dark:bg-indigo-400'
                    : 'border-slate-300 bg-[#FAFAFC] dark:border-slate-700 dark:bg-[#08090E]'
                }`}
              />

              <div className="flex flex-wrap items-baseline justify-between gap-3">
                <div className="flex items-baseline gap-3">
                  <h2 className="font-display text-2xl font-bold tracking-tight text-slate-950 tabular-nums dark:text-white">
                    v{release.version}
                  </h2>
                  {release.date && (
                    <time className="font-mono text-xs text-slate-500 tabular-nums dark:text-slate-400">
                      {release.date}
                    </time>
                  )}
                </div>

                <a
                  href={`https://github.com/unmbt/moonset/releases/tag/v${release.version}`}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 text-xs text-slate-500 transition-colors hover:text-indigo-600 dark:text-slate-400 dark:hover:text-indigo-300"
                >
                  GitHub Release
                  <ExternalLink className="h-3 w-3" />
                </a>
              </div>

              <div className="mt-6 space-y-6">
                {release.groups.map((group) => (
                  <div
                    key={group.title}
                    className="rounded-2xl border border-slate-900/[0.08] bg-white/75 p-6 dark:border-white/[0.08] dark:bg-[#10121C]/75"
                  >
                    <h3 className="text-lg font-semibold tracking-wide text-slate-900 dark:text-slate-100">
                      {group.title}
                    </h3>
                    <ul className="mt-4 space-y-3.5 text-sm leading-relaxed text-slate-700 dark:text-slate-300">
                      {group.items.map((item, itemIdx) => (
                        <li key={itemIdx} className="space-y-1.5">
                          <p>{renderInlineCode(item.text)}</p>
                          {(item.commitHash || item.author) && (
                            <div className="flex items-center gap-2 font-mono text-xs text-slate-500 dark:text-slate-400">
                              {item.commitHash && item.commitUrl && (
                                <a
                                  href={item.commitUrl}
                                  target="_blank"
                                  rel="noreferrer"
                                  className="text-indigo-600 hover:underline dark:text-indigo-400"
                                >
                                  {item.commitHash}
                                </a>
                              )}
                              {item.commitHash && item.author && (
                                <span aria-hidden="true">·</span>
                              )}
                              {item.author && <span>@{item.author}</span>}
                            </div>
                          )}
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      </div>

      <div className="mt-16 flex items-center justify-between border-t border-slate-900/[0.08] pt-8 text-sm dark:border-white/[0.08]">
        <a
          href="#/docs/changelog-spec"
          onClick={(e) => {
            e.preventDefault();
            onNavigate('/docs/changelog-spec');
          }}
          className="font-medium text-indigo-600 hover:underline dark:text-indigo-400"
        >
          了解 Changelog 生成规范 →
        </a>
        <a
          href="#/docs/roadmap"
          onClick={(e) => {
            e.preventDefault();
            onNavigate('/docs/roadmap');
          }}
          className="text-slate-600 hover:text-slate-950 dark:text-slate-400 dark:hover:text-white"
        >
          查看路线图
        </a>
      </div>
    </div>
  );
}
