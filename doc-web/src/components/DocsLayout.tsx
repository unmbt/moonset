import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronLeft, ChevronRight, ExternalLink, PanelLeft, Search, X } from 'lucide-react';
import { DOC_SECTIONS, getDocBySlug, getDocNeighbors } from '../lib/docsCatalog';
import { extractHeadings } from '../lib/markdown';
import { computeReadingProgress } from '../lib/scrollTimeline';
import { scrollToHeadingById } from '../lib/scrollTo';
import { useDocContent } from '../hooks/useDocContent';
import { MarkdownRenderer } from './MarkdownRenderer';
import { NotFound } from './NotFound';

interface DocsLayoutProps {
  slug: string;
  onNavigate: (route: string, hash?: string) => void;
  onOpenSearch: () => void;
}

function ArticleSkeleton() {
  return (
    <div aria-busy="true" aria-label="正在加载文档">
      <div className="moonset-shimmer h-9 w-3/5 rounded-lg bg-slate-900/[0.05] dark:bg-white/[0.05]" />
      <div className="mt-7 space-y-3">
        {[96, 100, 88, 94, 72, 0, 90, 100, 64].map((w, i) =>
          w === 0 ? (
            <div key={i} className="h-5" />
          ) : (
            <div
              key={i}
              style={{ width: `${w}%` }}
              className="moonset-shimmer h-3.5 rounded bg-slate-900/[0.04] dark:bg-white/[0.04]"
            />
          ),
        )}
      </div>
    </div>
  );
}

export function DocsLayout({ slug, onNavigate, onOpenSearch }: DocsLayoutProps) {
  const doc = getDocBySlug(slug);
  if (!doc) {
    return <NotFound path={`/docs/${slug}`} onNavigate={onNavigate} onOpenSearch={onOpenSearch} />;
  }
  return <DocsReader key="reader" slug={doc.slug} onNavigate={onNavigate} onOpenSearch={onOpenSearch} />;
}

function DocsReader({ slug, onNavigate, onOpenSearch }: DocsLayoutProps) {
  const doc = getDocBySlug(slug)!;
  const content = useDocContent(doc.repoPath);
  const headings = useMemo(() => (content ? extractHeadings(content) : []), [content]);
  const { prev, next } = useMemo(() => getDocNeighbors(doc.slug), [doc.slug]);

  const drawerRef = useRef<HTMLDialogElement>(null);
  const articleRef = useRef<HTMLElement>(null);
  const progressRef = useRef<HTMLDivElement>(null);
  const tocListRef = useRef<HTMLUListElement>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [activeHeadingId, setActiveHeadingId] = useState<string>('');
  const [tocIndicator, setTocIndicator] = useState<{ y: number; h: number } | null>(null);
  const manualJumpUntilRef = useRef<number>(0);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() => {
    const initial: Record<string, boolean> = {};
    for (const section of DOC_SECTIONS) initial[section.id] = section.defaultOpen ?? true;
    initial[doc.sectionId] = true;
    return initial;
  });

  // Ensure the active document's section is expanded when navigating
  useEffect(() => {
    setOpenGroups((prevGroups) =>
      prevGroups[doc.sectionId] ? prevGroups : { ...prevGroups, [doc.sectionId]: true },
    );
  }, [doc.sectionId]);

  // Scroll-spy for the outline + reading progress bar (rAF-throttled)
  useEffect(() => {
    let raf = 0;
    const update = () => {
      raf = 0;
      const article = articleRef.current;
      if (article && progressRef.current) {
        const rect = article.getBoundingClientRect();
        const progress = computeReadingProgress(rect.top, rect.height, window.innerHeight);
        progressRef.current.style.transform = `scaleX(${progress.toFixed(4)})`;
      }
      if (headings.length === 0) {
        setActiveHeadingId('');
        return;
      }
      if (performance.now() < manualJumpUntilRef.current) return;
      let current = headings[0].id;
      for (const h of headings) {
        const el = document.getElementById(h.id);
        if (!el) continue;
        if (el.getBoundingClientRect().top <= 130) current = h.id;
        else break;
      }
      setActiveHeadingId(current);
    };
    const onScroll = () => {
      if (!raf) raf = window.requestAnimationFrame(update);
    };
    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
      if (raf) window.cancelAnimationFrame(raf);
    };
  }, [headings]);

  // Sliding outline indicator follows the active heading link
  useLayoutEffect(() => {
    const list = tocListRef.current;
    const link = list?.querySelector<HTMLElement>(`[data-heading-id="${CSS.escape(activeHeadingId)}"]`);
    if (!list || !link) {
      setTocIndicator(null);
      return;
    }
    setTocIndicator({ y: link.offsetTop, h: link.offsetHeight });
  }, [activeHeadingId, headings]);

  // Native <dialog> drawer for the mobile sidebar (Esc, focus trap, backdrop)
  useEffect(() => {
    const dialog = drawerRef.current;
    if (!dialog) return;
    const root = document.documentElement;
    if (drawerOpen && !dialog.open) {
      dialog.showModal();
      root.dataset.smoothScrollLock = 'true';
      document.body.style.overflow = 'hidden';
    } else if (!drawerOpen && dialog.open) {
      dialog.close();
    }
    if (!drawerOpen) {
      delete root.dataset.smoothScrollLock;
      document.body.style.overflow = '';
    }
  }, [drawerOpen]);

  useEffect(
    () => () => {
      delete document.documentElement.dataset.smoothScrollLock;
      document.body.style.overflow = '';
    },
    [],
  );

  const sectionTitle = DOC_SECTIONS.find((s) => s.id === doc.sectionId)?.title ?? '文档';

  const selectDoc = (targetRoute: string) => {
    setDrawerOpen(false);
    onNavigate(targetRoute);
  };

  const searchTrigger = (
    <button
      type="button"
      onClick={() => {
        setDrawerOpen(false);
        onOpenSearch();
      }}
      className="group mb-5 flex h-9 w-full items-center gap-2 rounded-lg border border-slate-900/[0.1] bg-white px-3 text-left text-xs text-slate-400 transition-colors hover:border-slate-900/[0.18] dark:border-white/[0.1] dark:bg-[#10121C] dark:text-slate-500 dark:hover:border-white/[0.18]"
    >
      <Search aria-hidden="true" className="h-3.5 w-3.5" />
      <span className="flex-1">检索文档与规范…</span>
      <kbd className="rounded border border-slate-900/[0.08] px-1 font-mono text-[10px] text-slate-400 dark:border-white/[0.1]">
        ⇧⇧
      </kbd>
    </button>
  );

  const sidebarNav = (
    <nav aria-label="文档目录" className="space-y-5 pr-2">
      {DOC_SECTIONS.map((section) => {
        const expanded = openGroups[section.id] ?? true;
        return (
          <div key={section.id}>
            <button
              type="button"
              onClick={() =>
                setOpenGroups((prevGroups) => ({ ...prevGroups, [section.id]: !expanded }))
              }
              aria-expanded={expanded}
              className="flex w-full items-center justify-between px-2 py-1 text-xs font-semibold text-slate-900 transition-colors hover:text-indigo-600 dark:text-slate-100 dark:hover:text-indigo-300"
            >
              <span>{section.title}</span>
              <ChevronDown
                className={`h-3.5 w-3.5 text-slate-400 transition-transform duration-200 ${
                  expanded ? 'rotate-0' : '-rotate-90'
                }`}
              />
            </button>

            <div
              className={`grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.22,0.8,0.24,1)] ${
                expanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0'
              }`}
              inert={!expanded}
            >
              <ul className="mt-1.5 space-y-0.5 overflow-hidden">
                {section.items.map((item) => {
                  const active = item.slug === doc.slug;
                  return (
                    <li key={item.slug}>
                      <a
                        href={`#/docs/${item.slug}`}
                        onClick={(e) => {
                          e.preventDefault();
                          selectDoc(`/docs/${item.slug}`);
                        }}
                        aria-current={active ? 'page' : undefined}
                        className={`relative block rounded-lg px-2.5 py-1.5 text-[13px] transition-colors ${
                          active
                            ? 'bg-indigo-600/[0.09] font-medium text-indigo-700 dark:bg-indigo-400/[0.12] dark:text-indigo-300'
                            : 'text-slate-600 hover:bg-slate-900/[0.04] hover:text-slate-950 dark:text-slate-400 dark:hover:bg-white/[0.04] dark:hover:text-slate-100'
                        }`}
                      >
                        {item.title}
                      </a>
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>
        );
      })}

      <div className="border-t border-slate-900/[0.07] pt-4 dark:border-white/[0.07]">
        <a
          href="#/changelog"
          onClick={(e) => {
            e.preventDefault();
            selectDoc('/changelog');
          }}
          className="block rounded-lg px-2.5 py-1.5 text-[13px] text-slate-600 transition-colors hover:bg-slate-900/[0.04] hover:text-slate-950 dark:text-slate-400 dark:hover:bg-white/[0.04] dark:hover:text-slate-100"
        >
          更新日志 (CHANGELOG)
        </a>
      </div>
    </nav>
  );

  return (
    <div className="mx-auto max-w-7xl px-5 py-8 sm:px-6 lg:py-12">
      {/* Reading progress */}
      <div
        aria-hidden="true"
        className="pointer-events-none fixed inset-x-0 top-16 z-30 h-[2px] overflow-hidden"
      >
        <div
          ref={progressRef}
          className="h-full origin-left bg-gradient-to-r from-indigo-500 via-indigo-400 to-amber-400/80"
          style={{ transform: 'scaleX(0)' }}
        />
      </div>

      {/* Mobile sidebar toggle */}
      <div className="mb-6 flex items-center justify-between gap-3 border-b border-slate-900/[0.07] pb-3.5 lg:hidden dark:border-white/[0.07]">
        <button
          type="button"
          onClick={() => setDrawerOpen(true)}
          className="inline-flex shrink-0 items-center gap-2 rounded-lg border border-slate-900/[0.1] px-3 py-1.5 text-xs font-medium text-slate-700 dark:border-white/[0.1] dark:text-slate-200"
        >
          <PanelLeft className="h-3.5 w-3.5" />
          文档目录
        </button>
        <span className="truncate text-xs text-slate-500 dark:text-slate-400">
          {sectionTitle} · {doc.title}
        </span>
      </div>

      {/* Mobile slide-over drawer */}
      <dialog
        ref={drawerRef}
        aria-label="文档导航"
        onClose={() => setDrawerOpen(false)}
        onClick={(e) => {
          if (e.target === e.currentTarget) setDrawerOpen(false);
        }}
        className="moonset-dialog moonset-drawer lg:hidden"
      >
        <aside className="moonset-drawer-panel flex h-full flex-col border-r border-slate-900/[0.08] bg-[#FAFAFC] p-5 dark:border-white/[0.08] dark:bg-[#0B0D14]">
          <div className="mb-4 flex items-center justify-between">
            <span className="font-display text-sm font-semibold text-slate-950 dark:text-white">文档导航</span>
            <button
              type="button"
              onClick={() => setDrawerOpen(false)}
              aria-label="关闭目录"
              className="rounded-lg p-1 text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
          {searchTrigger}
          <div className="moonset-quiet-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain">
            {sidebarNav}
          </div>
        </aside>
      </dialog>

      {/* VitePress-like 3-column layout */}
      <div className="grid grid-cols-1 gap-10 lg:grid-cols-[232px_minmax(0,1fr)] xl:grid-cols-[232px_minmax(0,1fr)_196px]">
        <aside className="hidden lg:block">
          <div className="moonset-quiet-scroll sticky top-24 max-h-[calc(100vh-7.5rem)] overflow-y-auto">
            {searchTrigger}
            {sidebarNav}
          </div>
        </aside>

        <article ref={articleRef} className="min-w-0">
          <div className="mb-5 flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500 dark:text-slate-400">
            <div className="flex min-w-0 items-center gap-2">
              <span>文档</span>
              <span aria-hidden="true">/</span>
              <span>{sectionTitle}</span>
              <span aria-hidden="true" className="hidden sm:inline">/</span>
              <span className="hidden truncate font-mono text-[11px] sm:inline">{doc.repoPath}</span>
            </div>
            <a
              href={`https://github.com/unmbt/moonset/blob/master/${doc.repoPath}`}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-slate-500 transition-colors hover:text-indigo-600 dark:text-slate-400 dark:hover:text-indigo-300"
            >
              查看源文件
              <ExternalLink className="h-3 w-3" />
            </a>
          </div>

          {content === null ? (
            <ArticleSkeleton />
          ) : (
            <div key={doc.slug} className="moonset-fade-in">
              <MarkdownRenderer
                content={content}
                currentRepoPath={doc.repoPath}
                routeBase={`/docs/${doc.slug}`}
                onNavigate={onNavigate}
              />
            </div>
          )}

          <nav
            aria-label="上下篇文档导航"
            className="mt-14 grid grid-cols-1 gap-4 border-t border-slate-900/[0.08] pt-8 sm:grid-cols-2 dark:border-white/[0.08]"
          >
            {prev ? (
              <a
                href={`#/docs/${prev.slug}`}
                onClick={(e) => {
                  e.preventDefault();
                  onNavigate(`/docs/${prev.slug}`);
                }}
                className="group flex flex-col rounded-xl border border-slate-900/[0.08] p-4 transition-[border-color,transform] duration-200 hover:-translate-y-0.5 hover:border-indigo-500/40 dark:border-white/[0.08] dark:hover:border-indigo-400/40"
              >
                <span className="inline-flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                  <ChevronLeft className="h-3.5 w-3.5 transition-transform duration-200 group-hover:-translate-x-0.5" />
                  上一篇
                </span>
                <span className="mt-1.5 text-sm font-medium text-slate-950 transition-colors group-hover:text-indigo-600 dark:text-white dark:group-hover:text-indigo-300">
                  {prev.title}
                </span>
              </a>
            ) : (
              <div />
            )}

            {next ? (
              <a
                href={`#/docs/${next.slug}`}
                onClick={(e) => {
                  e.preventDefault();
                  onNavigate(`/docs/${next.slug}`);
                }}
                className="group flex flex-col items-end rounded-xl border border-slate-900/[0.08] p-4 text-right transition-[border-color,transform] duration-200 hover:-translate-y-0.5 hover:border-indigo-500/40 dark:border-white/[0.08] dark:hover:border-indigo-400/40"
              >
                <span className="inline-flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                  下一篇
                  <ChevronRight className="h-3.5 w-3.5 transition-transform duration-200 group-hover:translate-x-0.5" />
                </span>
                <span className="mt-1.5 text-sm font-medium text-slate-950 transition-colors group-hover:text-indigo-600 dark:text-white dark:group-hover:text-indigo-300">
                  {next.title}
                </span>
              </a>
            ) : (
              <div />
            )}
          </nav>
        </article>

        {/* Right sticky On-This-Page outline with sliding indicator */}
        <aside className="hidden xl:block">
          <div className="moonset-quiet-scroll sticky top-24 max-h-[calc(100vh-7.5rem)] overflow-y-auto pl-4">
            <div className="mb-3 text-xs font-semibold text-slate-900 dark:text-slate-100">本页目录</div>
            {content === null ? (
              <div className="space-y-2">
                {[70, 85, 60, 75].map((w, i) => (
                  <div
                    key={i}
                    style={{ width: `${w}%` }}
                    className="moonset-shimmer h-2.5 rounded bg-slate-900/[0.04] dark:bg-white/[0.04]"
                  />
                ))}
              </div>
            ) : headings.length === 0 ? (
              <p className="text-xs text-slate-400 dark:text-slate-500">本页无二级章节</p>
            ) : (
              <div className="relative">
                <span
                  aria-hidden="true"
                  className="absolute top-0 bottom-0 -left-4 w-px bg-slate-900/[0.08] dark:bg-white/[0.08]"
                />
                <span
                  aria-hidden="true"
                  className="absolute -left-4 w-[2px] rounded-full bg-indigo-600 transition-[transform,height,opacity] duration-300 ease-[cubic-bezier(0.22,0.8,0.24,1)] dark:bg-indigo-400"
                  style={{
                    top: 0,
                    height: tocIndicator?.h ?? 0,
                    transform: `translateY(${tocIndicator?.y ?? 0}px)`,
                    opacity: tocIndicator ? 1 : 0,
                  }}
                />
                <ul ref={tocListRef} className="relative space-y-1 text-xs">
                  {headings.map((h) => {
                    const active = h.id === activeHeadingId;
                    return (
                      <li key={h.id} className={h.level === 3 ? 'pl-3' : ''}>
                        <a
                          href={`#/docs/${doc.slug}#${h.id}`}
                          data-heading-id={h.id}
                          onClick={(e) => {
                            e.preventDefault();
                            manualJumpUntilRef.current = performance.now() + 900;
                            setActiveHeadingId(h.id);
                            history.replaceState(history.state, '', `#/docs/${doc.slug}#${h.id}`);
                            scrollToHeadingById(h.id);
                          }}
                          className={`block truncate py-0.5 transition-colors duration-200 ${
                            active
                              ? 'font-medium text-indigo-600 dark:text-indigo-400'
                              : 'text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100'
                          }`}
                        >
                          {h.text}
                        </a>
                      </li>
                    );
                  })}
                </ul>
              </div>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}
