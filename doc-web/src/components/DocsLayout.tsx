import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  PanelLeft,
  Search,
  X,
} from 'lucide-react';
import {
  DOC_SECTIONS,
  getDocBySlug,
  getDocNeighbors,
  searchDocs,
} from '../lib/docsCatalog';
import { getAllDocContents, getDocContent } from '../lib/docsLoader';
import { extractHeadings } from '../lib/markdown';
import { MarkdownRenderer, scrollToHeadingById } from './MarkdownRenderer';

interface DocsLayoutProps {
  slug: string;
  onNavigate: (route: string, hash?: string) => void;
}

export function DocsLayout({ slug, onNavigate }: DocsLayoutProps) {
  const doc = getDocBySlug(slug) ?? getDocBySlug('quickstart')!;
  const content = getDocContent(doc.repoPath);
  const allContents = useMemo(() => getAllDocContents(), []);
  const headings = useMemo(() => extractHeadings(content), [content]);
  const { prev, next } = useMemo(() => getDocNeighbors(doc.slug), [doc.slug]);

  const [searchQuery, setSearchQuery] = useState('');
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [activeHeadingId, setActiveHeadingId] = useState<string>('');
  const manualJumpUntilRef = useRef<number>(0);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() => {
    const initial: Record<string, boolean> = {};
    for (const section of DOC_SECTIONS) {
      initial[section.id] = section.defaultOpen ?? true;
    }
    if (doc.sectionId) {
      initial[doc.sectionId] = true;
    }
    return initial;
  });

  // Ensure the active document's section is expanded when navigating
  useEffect(() => {
    setOpenGroups((prevGroups) =>
      prevGroups[doc.sectionId]
        ? prevGroups
        : { ...prevGroups, [doc.sectionId]: true },
    );
  }, [doc.sectionId]);

  // Scroll-spy for right-side "On This Page" outline
  useEffect(() => {
    if (headings.length === 0) {
      setActiveHeadingId('');
      return;
    }

    const handleScroll = () => {
      if (performance.now() < manualJumpUntilRef.current) return;
      let current = headings[0].id;
      for (const h of headings) {
        const el = document.getElementById(h.id);
        if (!el) continue;
        if (el.getBoundingClientRect().top <= 130) {
          current = h.id;
        } else {
          break;
        }
      }
      setActiveHeadingId(current);
    };

    handleScroll();
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [headings]);

  const searchHits = useMemo(
    () => searchDocs(searchQuery, allContents),
    [searchQuery, allContents],
  );

  const sectionTitle =
    DOC_SECTIONS.find((s) => s.id === doc.sectionId)?.title ?? '文档';

  const selectDoc = (targetRoute: string) => {
    setMobileSidebarOpen(false);
    setSearchQuery('');
    onNavigate(targetRoute);
  };

  const sidebarContent = (
    <div className="flex h-full flex-col">
      {/* Instant full-text search */}
      <div className="relative mb-5">
        <Search
          aria-hidden="true"
          className="pointer-events-none absolute top-1/2 left-3 h-3.5 w-3.5 -translate-y-1/2 text-slate-400"
        />
        <input
          type="search"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="检索文档与规范…"
          aria-label="检索文档与规范"
          className="h-9 w-full rounded-lg border border-slate-900/[0.1] bg-white pl-8.5 pr-8 text-xs text-slate-900 placeholder:text-slate-400 focus:border-indigo-500 focus:outline-none dark:border-white/[0.1] dark:bg-[#10121C] dark:text-slate-100 dark:placeholder:text-slate-500 dark:focus:border-indigo-400"
        />
        {searchQuery && (
          <button
            type="button"
            onClick={() => setSearchQuery('')}
            aria-label="清空搜索"
            className="absolute top-1/2 right-2 -translate-y-1/2 text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {/* Search results or multi-level sidebar tree */}
      {searchQuery.trim() ? (
        <div className="moonset-quiet-scroll space-y-1.5 overflow-y-auto pr-1">
          <div className="px-2 pb-1 text-[11px] font-medium text-slate-500 dark:text-slate-400">
            找到 {searchHits.length} 篇匹配文档
          </div>
          {searchHits.length === 0 ? (
            <div className="rounded-lg border border-slate-900/[0.06] p-3 text-xs text-slate-500 dark:border-white/[0.06] dark:text-slate-400">
              没有找到包含 “{searchQuery}” 的内容。
            </div>
          ) : (
            searchHits.map((hit) => (
              <button
                key={hit.item.slug}
                type="button"
                onClick={() => selectDoc(`/docs/${hit.item.slug}`)}
                className="block w-full rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-slate-900/[0.045] dark:hover:bg-white/[0.05]"
              >
                <div className="text-xs font-medium text-slate-950 dark:text-white">
                  {hit.item.title}
                </div>
                <div className="mt-0.5 text-[11px] text-slate-500 dark:text-slate-400">
                  {hit.sectionTitle}
                </div>
                {hit.snippet && (
                  <p className="mt-1 line-clamp-2 text-[11px] leading-relaxed text-slate-500 dark:text-slate-400">
                    {hit.snippet}
                  </p>
                )}
              </button>
            ))
          )}
        </div>
      ) : (
        <nav aria-label="文档目录" className="moonset-quiet-scroll space-y-5 overflow-y-auto pr-2">
          {DOC_SECTIONS.map((section) => {
            const expanded = openGroups[section.id] ?? true;
            return (
              <div key={section.id}>
                <button
                  type="button"
                  onClick={() =>
                    setOpenGroups((prevGroups) => ({
                      ...prevGroups,
                      [section.id]: !expanded,
                    }))
                  }
                  aria-expanded={expanded}
                  className="flex w-full items-center justify-between px-2 py-1 text-xs font-semibold text-slate-900 transition-colors hover:text-indigo-600 dark:text-slate-100 dark:hover:text-indigo-300"
                >
                  <span>{section.title}</span>
                  <ChevronDown
                    className={`h-3.5 w-3.5 text-slate-400 transition-transform duration-150 ${
                      expanded ? 'rotate-0' : '-rotate-90'
                    }`}
                  />
                </button>

                {expanded && (
                  <ul className="mt-1.5 space-y-0.5">
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
                            className={`block rounded-lg px-2.5 py-1.5 text-[13px] transition-colors ${
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
                )}
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
      )}
    </div>
  );

  return (
    <div className="mx-auto max-w-7xl px-6 py-8 lg:py-12">
      {/* Mobile sidebar toggle */}
      <div className="mb-6 flex items-center justify-between border-b border-slate-900/[0.07] pb-3.5 lg:hidden dark:border-white/[0.07]">
        <button
          type="button"
          onClick={() => setMobileSidebarOpen(true)}
          className="inline-flex items-center gap-2 rounded-lg border border-slate-900/[0.1] px-3 py-1.5 text-xs font-medium text-slate-700 dark:border-white/[0.1] dark:text-slate-200"
        >
          <PanelLeft className="h-3.5 w-3.5" />
          文档目录
        </button>
        <span className="text-xs text-slate-500 dark:text-slate-400">
          {sectionTitle} · {doc.title}
        </span>
      </div>

      {/* Mobile slide-over drawer */}
      {mobileSidebarOpen && (
        <div className="fixed inset-0 z-50 flex lg:hidden">
          <button
            type="button"
            aria-label="关闭文档目录"
            onClick={() => setMobileSidebarOpen(false)}
            className="fixed inset-0 bg-slate-950/40 backdrop-blur-xs"
          />
          <aside className="relative z-10 flex h-full w-72 max-w-[82vw] flex-col border-r border-slate-900/[0.08] bg-[#FAFAFC] p-5 dark:border-white/[0.08] dark:bg-[#0B0D14]">
            <div className="mb-4 flex items-center justify-between">
              <span className="font-display text-sm font-semibold text-slate-950 dark:text-white">
                文档导航
              </span>
              <button
                type="button"
                onClick={() => setMobileSidebarOpen(false)}
                aria-label="关闭目录"
                className="rounded-lg p-1 text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="moonset-quiet-scroll min-h-0 flex-1 overflow-y-auto">{sidebarContent}</div>
          </aside>
        </div>
      )}

      {/* VitePress-like 3-column layout */}
      <div className="grid grid-cols-1 gap-10 lg:grid-cols-[232px_minmax(0,1fr)] xl:grid-cols-[232px_minmax(0,1fr)_196px]">
        {/* Left sticky sidebar */}
        <aside className="hidden lg:block">
          <div className="moonset-quiet-scroll sticky top-24 max-h-[calc(100vh-7.5rem)] overflow-y-auto">
            {sidebarContent}
          </div>
        </aside>

        {/* Center article */}
        <article className="min-w-0">
          <div className="mb-5 flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500 dark:text-slate-400">
            <div className="flex items-center gap-2">
              <span>文档</span>
              <span aria-hidden="true">/</span>
              <span>{sectionTitle}</span>
              <span aria-hidden="true">/</span>
              <span className="font-mono text-[11px]">{doc.repoPath}</span>
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

          <MarkdownRenderer
            content={content}
            currentRepoPath={doc.repoPath}
            onNavigate={onNavigate}
          />

          {/* Prev / Next pagination */}
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
                className="group flex flex-col rounded-xl border border-slate-900/[0.08] p-4 transition-colors hover:border-indigo-500/40 dark:border-white/[0.08] dark:hover:border-indigo-400/40"
              >
                <span className="inline-flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                  <ChevronLeft className="h-3.5 w-3.5" />
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
                className="group flex flex-col items-end rounded-xl border border-slate-900/[0.08] p-4 text-right transition-colors hover:border-indigo-500/40 dark:border-white/[0.08] dark:hover:border-indigo-400/40"
              >
                <span className="inline-flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                  下一篇
                  <ChevronRight className="h-3.5 w-3.5" />
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

        {/* Right sticky On-This-Page outline */}
        <aside className="hidden xl:block">
          <div className="moonset-quiet-scroll sticky top-24 max-h-[calc(100vh-7.5rem)] overflow-y-auto border-l border-slate-900/[0.07] pl-4 dark:border-white/[0.07]">
            <div className="mb-3 text-xs font-semibold text-slate-900 dark:text-slate-100">
              本页目录
            </div>
            {headings.length === 0 ? (
              <p className="text-xs text-slate-400 dark:text-slate-500">
                本页无二级章节
              </p>
            ) : (
              <ul className="space-y-1.5 text-xs">
                {headings.map((h) => {
                  const active = h.id === activeHeadingId;
                  return (
                    <li key={h.id} className={h.level === 3 ? 'pl-3' : ''}>
                      <a
                        href={`#${h.id}`}
                        onClick={(e) => {
                          e.preventDefault();
                          manualJumpUntilRef.current = performance.now() + 700;
                          setActiveHeadingId(h.id);
                          scrollToHeadingById(h.id);
                        }}
                        className={`block truncate py-0.5 transition-colors ${
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
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}
