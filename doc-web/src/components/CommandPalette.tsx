import { useEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { BookOpen, CornerDownLeft, FileText, Hash, History, Home, Search } from 'lucide-react';
import { ALL_DOCS } from '../lib/docsCatalog';
import { loadAllDocContents } from '../lib/docsLoader';
import { splitHighlight } from '../lib/interaction';
import { buildHeadingIndex, searchPalette, sectionTitleOf } from '../lib/search';

interface CommandPaletteProps {
  open: boolean;
  onClose: () => void;
  onNavigate: (route: string, anchor?: string) => void;
}

interface PaletteEntry {
  key: string;
  icon: 'doc' | 'heading' | 'home' | 'changelog' | 'adr';
  title: string;
  meta: string;
  snippet?: string;
  route: string;
  anchor?: string;
}

const PAGE_ENTRIES: PaletteEntry[] = [
  { key: 'page:home', icon: 'home', title: '首页', meta: '页面', route: '/' },
  { key: 'page:changelog', icon: 'changelog', title: '更新日志', meta: '页面 · CHANGELOG.md', route: '/changelog' },
  { key: 'page:adr', icon: 'adr', title: '架构决策 (ADR) 总览', meta: '页面', route: '/docs/decisions/overview' },
];

const QUICK_SLUGS = ['quickstart', 'commands', 'configuration', 'mixed-workspaces', 'automation', 'api', 'faq'];

const ICONS: Record<PaletteEntry['icon'], ReactNode> = {
  doc: <FileText className="h-4 w-4" />,
  heading: <Hash className="h-4 w-4" />,
  home: <Home className="h-4 w-4" />,
  changelog: <History className="h-4 w-4" />,
  adr: <BookOpen className="h-4 w-4" />,
};

function Highlighted({ text, query }: { text: string; query: string }) {
  return (
    <>
      {splitHighlight(text, query).map((seg, i) =>
        seg.match ? (
          <mark
            key={i}
            className="rounded-[3px] bg-indigo-500/15 px-px text-inherit dark:bg-indigo-400/25"
          >
            {seg.text}
          </mark>
        ) : (
          <span key={i}>{seg.text}</span>
        ),
      )}
    </>
  );
}

/**
 * Global "Search Everywhere" palette (double-tap Shift). Searches document titles,
 * bodies and section headings, with full keyboard navigation.
 */
export function CommandPalette({ open, onClose, onNavigate }: CommandPaletteProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const [contents, setContents] = useState<Record<string, string> | null>(null);

  // Open / close the native modal dialog (focus trap, Esc and top layer for free)
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      dialog.showModal();
      setQuery('');
      setActiveIndex(0);
      window.requestAnimationFrame(() => inputRef.current?.focus());
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  // Lazy-load the full-text index the first time the palette opens
  useEffect(() => {
    if (!open || contents) return;
    let alive = true;
    loadAllDocContents().then((loaded) => {
      if (alive) setContents(loaded);
    });
    return () => {
      alive = false;
    };
  }, [open, contents]);

  // Freeze background page scroll while open
  useEffect(() => {
    if (!open) return;
    const root = document.documentElement;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    root.dataset.smoothScrollLock = 'true';
    return () => {
      document.body.style.overflow = prevOverflow;
      delete root.dataset.smoothScrollLock;
    };
  }, [open]);

  const headingIndex = useMemo(() => (contents ? buildHeadingIndex(contents) : []), [contents]);

  const entries = useMemo<PaletteEntry[]>(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      const quick = QUICK_SLUGS.map((slug) => ALL_DOCS.find((d) => d.slug === slug))
        .filter((d): d is NonNullable<typeof d> => Boolean(d))
        .map<PaletteEntry>((item) => ({
          key: `doc:${item.slug}`,
          icon: 'doc',
          title: item.title,
          meta: sectionTitleOf(item),
          snippet: item.subtitle,
          route: `/docs/${item.slug}`,
        }));
      return [...quick, ...PAGE_ENTRIES];
    }

    const lower = trimmed.toLowerCase();
    const pages = PAGE_ENTRIES.filter((p) => p.title.toLowerCase().includes(lower));
    const hits = searchPalette(trimmed, contents ?? {}, headingIndex).map<PaletteEntry>((hit) =>
      hit.kind === 'doc'
        ? {
            key: `doc:${hit.item.slug}`,
            icon: 'doc',
            title: hit.item.title,
            meta: hit.sectionTitle,
            snippet: hit.snippet,
            route: `/docs/${hit.item.slug}`,
          }
        : {
            key: `heading:${hit.item.slug}#${hit.heading.id}`,
            icon: 'heading',
            title: hit.heading.text,
            meta: `${hit.item.title} · ${hit.sectionTitle}`,
            route: `/docs/${hit.item.slug}`,
            anchor: hit.heading.id,
          },
    );
    return [...pages, ...hits];
  }, [query, contents, headingIndex]);

  useEffect(() => {
    setActiveIndex(0);
  }, [query]);

  // Keep the active option scrolled into view
  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>(`[data-index="${activeIndex}"]`);
    el?.scrollIntoView({ block: 'nearest' });
  }, [activeIndex]);

  const select = (entry: PaletteEntry | undefined) => {
    if (!entry) return;
    onClose();
    onNavigate(entry.route, entry.anchor);
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setActiveIndex((i) => (entries.length ? (i + 1) % entries.length : 0));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActiveIndex((i) => (entries.length ? (i - 1 + entries.length) % entries.length : 0));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      select(entries[activeIndex]);
    }
  };

  const trimmed = query.trim();
  const loading = Boolean(trimmed) && !contents;
  const activeId = entries[activeIndex] ? `palette-opt-${activeIndex}` : undefined;

  return (
    <dialog
      ref={dialogRef}
      aria-label="搜索文档"
      onClose={onClose}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      className="moonset-dialog moonset-palette"
    >
      <div
        className="flex h-full w-full items-start justify-center px-3 pt-[10vh] sm:px-6 sm:pt-[14vh]"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        <div className="moonset-palette-panel flex max-h-[min(72vh,620px)] w-full max-w-xl flex-col overflow-hidden rounded-2xl border border-slate-900/[0.1] bg-white/95 shadow-[0_32px_80px_-24px_rgba(15,23,42,0.45)] backdrop-blur-xl dark:border-white/[0.1] dark:bg-[#0F1119]/95 dark:shadow-[0_32px_90px_-20px_rgba(0,0,0,0.85)]">
          <div className="flex items-center gap-3 border-b border-slate-900/[0.07] px-4 dark:border-white/[0.07]">
            <Search aria-hidden="true" className="h-4 w-4 shrink-0 text-slate-400" />
            <input
              ref={inputRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="搜索文档、规范章节与命令…"
              aria-label="搜索文档"
              role="combobox"
              aria-expanded="true"
              aria-controls="palette-listbox"
              aria-activedescendant={activeId}
              autoComplete="off"
              spellCheck={false}
              className="h-14 min-w-0 flex-1 bg-transparent text-[15px] text-slate-900 placeholder:text-slate-400 focus:outline-none focus-visible:outline-none dark:text-slate-100 dark:placeholder:text-slate-500"
            />
            <kbd className="hidden shrink-0 rounded-md border border-slate-900/[0.1] px-1.5 py-0.5 font-mono text-[10px] text-slate-500 sm:inline dark:border-white/[0.12] dark:text-slate-400">
              Esc
            </kbd>
          </div>

          <div
            ref={listRef}
            id="palette-listbox"
            role="listbox"
            aria-label="搜索结果"
            className="moonset-quiet-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain p-2"
          >
            {!trimmed && (
              <div className="px-2.5 pt-1.5 pb-2 text-[11px] font-medium text-slate-500 dark:text-slate-400">
                快速跳转
              </div>
            )}

            {loading && entries.length === 0 && (
              <div className="space-y-2 p-2">
                {[0, 1, 2].map((i) => (
                  <div key={i} className="moonset-shimmer h-12 rounded-lg bg-slate-900/[0.035] dark:bg-white/[0.04]" />
                ))}
              </div>
            )}

            {!loading && trimmed && entries.length === 0 && (
              <div className="px-4 py-10 text-center text-sm text-slate-500 dark:text-slate-400">
                没有找到与 “<span className="text-slate-800 dark:text-slate-200">{trimmed}</span>” 相关的内容
              </div>
            )}

            {entries.map((entry, idx) => {
              const active = idx === activeIndex;
              return (
                <div
                  key={entry.key}
                  id={`palette-opt-${idx}`}
                  role="option"
                  aria-selected={active}
                  data-index={idx}
                  onMouseMove={() => {
                    if (!active) setActiveIndex(idx);
                  }}
                  onClick={() => select(entry)}
                  className={`group flex cursor-pointer items-start gap-3 rounded-xl px-3 py-2.5 transition-colors duration-100 ${
                    active
                      ? 'bg-indigo-600/[0.08] dark:bg-indigo-400/[0.12]'
                      : 'hover:bg-slate-900/[0.03] dark:hover:bg-white/[0.03]'
                  }`}
                >
                  <span
                    className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border transition-colors ${
                      active
                        ? 'border-indigo-500/30 bg-white text-indigo-600 dark:border-indigo-400/30 dark:bg-[#171a2a] dark:text-indigo-300'
                        : 'border-slate-900/[0.07] bg-slate-50 text-slate-500 dark:border-white/[0.07] dark:bg-white/[0.03] dark:text-slate-400'
                    }`}
                  >
                    {ICONS[entry.icon]}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="flex items-baseline justify-between gap-3">
                      <span className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">
                        <Highlighted text={entry.title} query={trimmed} />
                      </span>
                      <span className="shrink-0 truncate text-[11px] text-slate-400 dark:text-slate-500">
                        {entry.meta}
                      </span>
                    </span>
                    {entry.snippet && (
                      <span className="mt-0.5 line-clamp-2 block text-xs leading-relaxed text-slate-500 dark:text-slate-400">
                        <Highlighted text={entry.snippet} query={trimmed} />
                      </span>
                    )}
                  </span>
                  <CornerDownLeft
                    aria-hidden="true"
                    className={`mt-1.5 h-3.5 w-3.5 shrink-0 text-indigo-500 transition-opacity dark:text-indigo-300 ${
                      active ? 'opacity-100' : 'opacity-0'
                    }`}
                  />
                </div>
              );
            })}
          </div>

          <div className="hidden items-center justify-between gap-3 border-t border-slate-900/[0.07] px-4 py-2.5 text-[11px] text-slate-500 sm:flex dark:border-white/[0.07] dark:text-slate-400">
            <div className="flex items-center gap-3">
              <span className="inline-flex items-center gap-1">
                <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono dark:border-white/[0.12]">↑</kbd>
                <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono dark:border-white/[0.12]">↓</kbd>
                选择
              </span>
              <span className="inline-flex items-center gap-1">
                <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono dark:border-white/[0.12]">↵</kbd>
                打开
              </span>
            </div>
            <span className="inline-flex items-center gap-1">
              随时双击
              <kbd className="rounded border border-slate-900/[0.1] px-1 font-mono dark:border-white/[0.12]">Shift</kbd>
              唤起搜索
            </span>
          </div>
        </div>
      </div>
    </dialog>
  );
}
