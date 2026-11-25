import {
  Children,
  cloneElement,
  isValidElement,
  memo,
  useMemo,
  useState,
  type CSSProperties,
  type ReactElement,
  type ReactNode,
} from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Check, Copy, Info, Lightbulb, MessageSquareWarning, OctagonAlert, TriangleAlert } from 'lucide-react';
import { rehypeHeadingIds, resolveRelativeDocSlug } from '../lib/markdown';
import { highlightCodeLines } from '../lib/highlight';
import { scrollToHeadingById } from '../lib/scrollTo';
import { MermaidDiagram } from './MermaidDiagram';

interface MarkdownRendererProps {
  content: string;
  currentRepoPath: string;
  /** SPA route of the current page, used to build shareable heading permalinks. */
  routeBase: string;
  onNavigate: (route: string, hash?: string) => void;
}

const REMARK_PLUGINS = [remarkGfm];
const REHYPE_PLUGINS = [rehypeHeadingIds];

type CalloutKind = 'note' | 'tip' | 'important' | 'warning' | 'caution';

const CALLOUTS: Record<CalloutKind, { label: string; icon: ReactNode }> = {
  note: { label: '说明', icon: <Info className="h-4 w-4" /> },
  tip: { label: '提示', icon: <Lightbulb className="h-4 w-4" /> },
  important: { label: '重要提示', icon: <MessageSquareWarning className="h-4 w-4" /> },
  warning: { label: '注意', icon: <TriangleAlert className="h-4 w-4" /> },
  caution: { label: '警告', icon: <OctagonAlert className="h-4 w-4" /> },
};

// GitHub alert markers are rewritten to a sentinel strong label the renderer can detect.
const CALLOUT_SENTINEL = (kind: string) => `**[!${kind}]**`;
const CALLOUT_RE = /^\[!(NOTE|IMPORTANT|TIP|WARNING|CAUTION)\]$/;

function extractText(node: ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(extractText).join('');
  if (node && typeof node === 'object' && 'props' in node) {
    const props = (node as { props?: { children?: ReactNode } }).props;
    return extractText(props?.children);
  }
  return '';
}

/**
 * Detects a GitHub-style alert blockquote and returns its kind plus the body with
 * the marker removed (dropping the first paragraph entirely if it only held the marker).
 */
function parseCallout(children: ReactNode): { kind: CalloutKind; body: ReactNode[] } | null {
  const items = Children.toArray(children);
  const firstIdx = items.findIndex((child) => isValidElement(child));
  if (firstIdx === -1) return null;
  const first = items[firstIdx] as ReactElement<{ children?: ReactNode }>;
  if (first.type !== 'p') return null;

  const inner = Children.toArray(first.props.children);
  const marker = inner[0];
  if (!isValidElement(marker) || marker.type !== 'strong') return null;
  const match = CALLOUT_RE.exec(extractText(marker).trim());
  if (!match) return null;

  const rest = inner.slice(1);
  if (typeof rest[0] === 'string') rest[0] = rest[0].replace(/^\s+/, '');
  const restIsEmpty = rest.every((node) => typeof node === 'string' && node.trim() === '');

  const body = [...items];
  if (restIsEmpty) body.splice(firstIdx, 1);
  else body[firstIdx] = cloneElement(first, {}, ...rest);

  return { kind: match[1].toLowerCase() as CalloutKind, body };
}

function CodeBlock({ className, children }: { className?: string; children?: ReactNode }) {
  const [copied, setCopied] = useState(false);
  const rawCode = extractText(children).replace(/\n$/, '');
  const langMatch = /language-([\w+-]+)/.exec(className ?? '');
  const lang = langMatch ? langMatch[1] : '';

  const isMermaid = lang.toLowerCase() === 'mermaid';
  const highlighted = useMemo(
    () => (isMermaid ? null : highlightCodeLines(rawCode, lang)),
    [isMermaid, rawCode, lang],
  );

  if (isMermaid || !highlighted) {
    return <MermaidDiagram source={rawCode} />;
  }

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(rawCode);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };

  return (
    <div
      data-code-lang={highlighted.language ?? (lang || 'text')}
      className="group relative my-5 overflow-hidden rounded-xl border border-slate-900/[0.08] bg-[#F4F5FA] dark:border-white/[0.08] dark:bg-[#0C0E16]"
    >
      <div className="flex items-center justify-between border-b border-slate-900/[0.06] px-4 py-2 text-[11px] text-slate-500 dark:border-white/[0.06] dark:text-slate-400">
        <span className="font-mono">{lang || 'text'}</span>
        <button
          type="button"
          onClick={handleCopy}
          aria-label={copied ? '已复制代码块' : '复制代码块'}
          className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] text-slate-500 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-900 dark:text-slate-400 dark:hover:bg-white/[0.07] dark:hover:text-white"
        >
          {copied ? (
            <>
              <Check className="moonset-fade-in h-3 w-3 text-emerald-600 dark:text-emerald-400" />
              <span className="moonset-fade-in">已复制</span>
            </>
          ) : (
            <>
              <Copy className="h-3 w-3" />
              <span>复制</span>
            </>
          )}
        </button>
      </div>
      <pre className="overflow-x-auto p-4 font-mono text-[13px] leading-[1.68] text-slate-800 dark:text-slate-200">
        <code className="block">
          {highlighted.lines.map((line, lineIndex) => (
            <span key={lineIndex} className="block min-h-[1.68em]">
              {line.length === 0
                ? '\n'
                : line.map((token, tokenIndex) => {
                    const hasThemeColor = Boolean(token.lightColor || token.darkColor);
                    if (!hasThemeColor && !token.italic && !token.bold && !token.underline) {
                      return <span key={tokenIndex}>{token.content}</span>;
                    }
                    const tokenStyle = hasThemeColor
                      ? ({
                          ...(token.lightColor ? { '--shiki-light': token.lightColor } : {}),
                          ...(token.darkColor ? { '--shiki-dark': token.darkColor } : {}),
                        } as CSSProperties)
                      : undefined;
                    const tokenClasses = [
                      hasThemeColor ? 'moonset-shiki-token' : '',
                      token.italic ? 'italic' : '',
                      token.bold ? 'font-semibold' : '',
                      token.underline ? 'underline' : '',
                    ]
                      .filter(Boolean)
                      .join(' ');
                    return (
                      <span key={tokenIndex} className={tokenClasses} style={tokenStyle}>
                        {token.content}
                      </span>
                    );
                  })}
            </span>
          ))}
        </code>
      </pre>
    </div>
  );
}

function Heading({
  level,
  id,
  routeBase,
  children,
}: {
  level: 2 | 3;
  id?: string;
  routeBase: string;
  children?: ReactNode;
}) {
  const [copied, setCopied] = useState(false);
  const Tag = level === 2 ? 'h2' : 'h3';
  const text = extractText(children);

  return (
    <Tag id={id} className="moonset-heading">
      {children}
      {id && (
        <a
          href={`#${routeBase}#${id}`}
          aria-label={`复制「${text}」的链接`}
          title="复制本节链接"
          data-copied={copied ? 'true' : 'false'}
          className="moonset-heading-anchor"
          onClick={(e) => {
            e.preventDefault();
            const hash = `#${routeBase}#${id}`;
            history.replaceState(history.state, '', hash);
            const url = `${window.location.origin}${window.location.pathname}${window.location.search}${hash}`;
            navigator.clipboard?.writeText(url).catch(() => undefined);
            scrollToHeadingById(id);
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1400);
          }}
        >
          {copied ? '✓' : '#'}
        </a>
      )}
    </Tag>
  );
}

export const MarkdownRenderer = memo(function MarkdownRenderer({
  content,
  currentRepoPath,
  routeBase,
  onNavigate,
}: MarkdownRendererProps) {
  const normalizedContent = useMemo(
    () =>
      content.replace(
        /^>\s*\[!(NOTE|IMPORTANT|TIP|WARNING|CAUTION)\]\s*$/gm,
        (_, kind: string) => `> ${CALLOUT_SENTINEL(kind)}`,
      ),
    [content],
  );

  const components = useMemo(
    () => ({
      a({ href, children }: { href?: string; children?: ReactNode }) {
        const target = href ?? '';
        const resolved = resolveRelativeDocSlug(currentRepoPath, target);
        if (resolved) {
          return (
            <a
              href={resolved.route ? `#${resolved.route}` : `#${routeBase}#${resolved.hash ?? ''}`}
              onClick={(e) => {
                e.preventDefault();
                if (resolved.route) {
                  onNavigate(resolved.route, resolved.hash);
                } else if (resolved.hash) {
                  history.replaceState(history.state, '', `#${routeBase}#${resolved.hash}`);
                  scrollToHeadingById(resolved.hash);
                }
              }}
            >
              {children}
            </a>
          );
        }
        const isExternal = target.startsWith('http://') || target.startsWith('https://');
        return (
          <a
            href={target}
            target={isExternal ? '_blank' : undefined}
            rel={isExternal ? 'noreferrer' : undefined}
          >
            {children}
          </a>
        );
      },
      h2({ id, children }: { id?: string; children?: ReactNode }) {
        return (
          <Heading level={2} id={id} routeBase={routeBase}>
            {children}
          </Heading>
        );
      },
      h3({ id, children }: { id?: string; children?: ReactNode }) {
        return (
          <Heading level={3} id={id} routeBase={routeBase}>
            {children}
          </Heading>
        );
      },
      blockquote({ children }: { children?: ReactNode }) {
        const callout = parseCallout(children);
        if (!callout) return <blockquote>{children}</blockquote>;
        const meta = CALLOUTS[callout.kind];
        return (
          <div className="moonset-callout" data-kind={callout.kind} role="note">
            <div className="moonset-callout-title">
              {meta.icon}
              <span>{meta.label}</span>
            </div>
            {callout.body}
          </div>
        );
      },
      code({ className, children }: { className?: string; children?: ReactNode }) {
        // Short inline tokens (identifiers, flags, targets like `wasm-gc`) never split mid-word
        const text = extractText(children);
        const keepTogether = !className && text.length <= 28 && !/\s/.test(text);
        return (
          <code className={className ?? (keepTogether ? 'moonset-code-nowrap' : undefined)}>
            {children}
          </code>
        );
      },
      pre({ children }: { children?: ReactNode }) {
        const child = Array.isArray(children) ? children[0] : children;
        if (
          child &&
          typeof child === 'object' &&
          'props' in child &&
          (child as { props?: { className?: string; children?: ReactNode } }).props
        ) {
          const props = (child as { props: { className?: string; children?: ReactNode } }).props;
          return <CodeBlock className={props.className}>{props.children}</CodeBlock>;
        }
        return <CodeBlock>{children}</CodeBlock>;
      },
    }),
    [currentRepoPath, routeBase, onNavigate],
  );

  return (
    <div className="moonset-prose">
      <ReactMarkdown remarkPlugins={REMARK_PLUGINS} rehypePlugins={REHYPE_PLUGINS} components={components}>
        {normalizedContent}
      </ReactMarkdown>
    </div>
  );
});
