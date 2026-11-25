import { useMemo, useState } from 'react';
import { Check, ExternalLink, Link2 } from 'lucide-react';
import { parseChangelog } from '../lib/markdown';
import { scrollToHeadingById } from '../lib/scrollTo';
import { useDocContent } from '../hooks/useDocContent';
import { Reveal, SpotlightCard, delayStyle } from './motion';

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
          className="rounded border border-slate-900/[0.08] bg-slate-900/[0.04] px-1.5 py-0.5 font-mono text-[0.84em] text-slate-900 dark:border-transparent dark:bg-white/[0.06] dark:text-slate-100"
        >
          {part.slice(1, -1)}
        </code>
      );
    }
    return <span key={i}>{part}</span>;
  });
}

function versionAnchor(version: string): string {
  return `v${version.replace(/[^\w-]+/g, '-')}`;
}

function VersionPermalink({ anchor, version }: { anchor: string; version: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <a
      href={`#/changelog#${anchor}`}
      aria-label={`复制 v${version} 的链接`}
      title="复制版本链接"
      onClick={(e) => {
        e.preventDefault();
        const hash = `#/changelog#${anchor}`;
        history.replaceState(history.state, '', hash);
        navigator.clipboard
          ?.writeText(`${window.location.origin}${window.location.pathname}${hash}`)
          .catch(() => undefined);
        scrollToHeadingById(anchor);
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1400);
      }}
      className="inline-flex h-6 w-6 items-center justify-center rounded-md text-slate-400 opacity-0 transition-all group-hover:opacity-100 hover:bg-slate-900/[0.05] hover:text-indigo-600 focus-visible:opacity-100 dark:hover:bg-white/[0.06] dark:hover:text-indigo-300"
    >
      {copied ? <Check className="h-3.5 w-3.5 text-emerald-500" /> : <Link2 className="h-3.5 w-3.5" />}
    </a>
  );
}

export function ChangelogPage({ onNavigate }: ChangelogPageProps) {
  const raw = useDocContent('CHANGELOG.md');
  const releases = useMemo(() => (raw ? parseChangelog(raw) : []), [raw]);

  return (
    <div className="mx-auto max-w-4xl px-5 py-14 sm:px-6 sm:py-20">
      <div className="border-b border-slate-900/[0.08] pb-10 dark:border-white/[0.08]">
        <div
          style={delayStyle(0)}
          className="moonset-enter flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400"
        >
          <span>版本演进</span>
          <span aria-hidden="true">·</span>
          <span className="font-mono">CHANGELOG.md</span>
        </div>
        <h1
          style={delayStyle(60)}
          className="moonset-enter moonset-cjk-heading font-display mt-3 text-[clamp(2rem,3.6vw,2.85rem)] font-bold tracking-[-0.025em] text-slate-950 dark:text-white"
        >
          更新日志
        </h1>
        <p
          style={delayStyle(120)}
          className="moonset-enter mt-3 max-w-2xl text-sm leading-relaxed text-slate-600 sm:text-base dark:text-slate-400"
        >
          由 <code className="font-mono text-xs text-slate-800 dark:text-slate-200">moonset</code> 自身以 dogfooding 方式维护的发布记录，完整追踪每次功能演进与契约落地。
        </p>

        {releases.length > 1 && (
          <nav
            aria-label="版本快速跳转"
            style={delayStyle(180)}
            className="moonset-enter mt-6 flex flex-wrap gap-2"
          >
            {releases.map((release, idx) => (
              <a
                key={release.version}
                href={`#/changelog#${versionAnchor(release.version)}`}
                onClick={(e) => {
                  e.preventDefault();
                  history.replaceState(history.state, '', `#/changelog#${versionAnchor(release.version)}`);
                  scrollToHeadingById(versionAnchor(release.version));
                }}
                className={`rounded-full border px-3 py-1 font-mono text-xs tabular-nums transition-colors ${
                  idx === 0
                    ? 'border-indigo-500/30 bg-indigo-500/[0.06] text-indigo-700 hover:bg-indigo-500/[0.1] dark:border-indigo-400/30 dark:bg-indigo-400/[0.08] dark:text-indigo-300'
                    : 'border-slate-900/[0.1] text-slate-600 hover:border-slate-900/[0.2] hover:text-slate-950 dark:border-white/[0.1] dark:text-slate-400 dark:hover:border-white/[0.2] dark:hover:text-white'
                }`}
              >
                v{release.version}
              </a>
            ))}
          </nav>
        )}
      </div>

      {/* Editorial release timeline */}
      <div className="relative mt-12 pl-7 sm:pl-9">
        <div
          aria-hidden="true"
          className="absolute top-2 bottom-2 left-2 w-px bg-gradient-to-b from-indigo-500/50 via-slate-900/[0.09] to-transparent dark:from-indigo-400/50 dark:via-white/[0.09]"
        />

        {raw === null ? (
          <div className="space-y-4" aria-busy="true">
            <div className="moonset-shimmer h-7 w-40 rounded-lg bg-slate-900/[0.05] dark:bg-white/[0.05]" />
            <div className="moonset-shimmer h-40 rounded-2xl bg-slate-900/[0.035] dark:bg-white/[0.035]" />
          </div>
        ) : (
          <div className="space-y-14">
            {releases.map((release, idx) => {
              const anchor = versionAnchor(release.version);
              return (
                <Reveal as="section" key={release.version} className="relative" delay={Math.min(idx, 3) * 60}>
                  <span
                    aria-hidden="true"
                    className={`absolute top-2.5 -left-[25px] h-3 w-3 rounded-full border sm:-left-[33px] ${
                      idx === 0
                        ? 'border-indigo-600 bg-indigo-600 shadow-[0_0_0_4px_rgba(79,70,229,0.15)] dark:border-indigo-400 dark:bg-indigo-400 dark:shadow-[0_0_0_4px_rgba(129,140,248,0.18)]'
                        : 'border-slate-300 bg-[#FAFAFC] dark:border-slate-700 dark:bg-[#08090E]'
                    }`}
                  />

                  <div className="flex flex-wrap items-baseline justify-between gap-3">
                    <div className="group flex items-baseline gap-3">
                      <h2
                        id={anchor}
                        className="scroll-mt-24 font-display text-2xl font-bold tracking-tight text-slate-950 tabular-nums dark:text-white"
                      >
                        v{release.version}
                      </h2>
                      {release.date && (
                        <time className="font-mono text-xs text-slate-500 tabular-nums dark:text-slate-400">
                          {release.date}
                        </time>
                      )}
                      {idx === 0 && (
                        <span className="rounded-full bg-indigo-500/10 px-2 py-0.5 text-[10px] font-medium text-indigo-700 dark:bg-indigo-400/15 dark:text-indigo-300">
                          Latest
                        </span>
                      )}
                      <VersionPermalink anchor={anchor} version={release.version} />
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
                      <SpotlightCard
                        key={group.title}
                        reveal={false}
                        className="rounded-2xl border border-slate-900/[0.08] bg-white/75 p-6 dark:border-white/[0.08] dark:bg-[#10121C]/75"
                      >
                        <h3 className="text-base font-semibold tracking-wide text-slate-900 dark:text-slate-100">
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
                                  {item.commitHash && item.author && <span aria-hidden="true">·</span>}
                                  {item.author && <span>@{item.author}</span>}
                                </div>
                              )}
                            </li>
                          ))}
                        </ul>
                      </SpotlightCard>
                    ))}
                  </div>
                </Reveal>
              );
            })}
          </div>
        )}
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
