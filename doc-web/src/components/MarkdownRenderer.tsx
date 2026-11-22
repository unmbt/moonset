import { memo, useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Check, Copy } from 'lucide-react';
import { rehypeHeadingIds, resolveRelativeDocSlug } from '../lib/markdown';
import { highlightCodeLines } from '../lib/highlight';
import { MermaidDiagram } from './MermaidDiagram';

interface MarkdownRendererProps {
  content: string;
  currentRepoPath: string;
  onNavigate: (route: string, hash?: string) => void;
}

const REMARK_PLUGINS = [remarkGfm];
const REHYPE_PLUGINS = [rehypeHeadingIds];

export function scrollToHeadingById(id: string): boolean {
  const el = document.getElementById(id);
  if (!el) return false;
  const headerOffset = 92;
  const targetTop = Math.max(
    0,
    el.getBoundingClientRect().top + window.scrollY - headerOffset,
  );
  window.scrollTo({ top: targetTop, behavior: 'smooth' });
  return true;
}

function extractText(node: ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') {
    return String(node);
  }
  if (Array.isArray(node)) {
    return node.map(extractText).join('');
  }
  if (node && typeof node === 'object' && 'props' in node) {
    const props = (node as { props?: { children?: ReactNode } }).props;
    return extractText(props?.children);
  }
  return '';
}

function CodeBlock({
  className,
  children,
}: {
  className?: string;
  children?: ReactNode;
}) {
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
          aria-label="复制代码块"
          className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] text-slate-500 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-900 dark:text-slate-400 dark:hover:bg-white/[0.07] dark:hover:text-white"
        >
          {copied ? (
            <>
              <Check className="h-3 w-3 text-emerald-600 dark:text-emerald-400" />
              <span>已复制</span>
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
              {line.length === 0 ? (
                '\n'
              ) : (
                line.map((token, tokenIndex) => {
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
                })
              )}
            </span>
          ))}
        </code>
      </pre>
    </div>
  );
}

export const MarkdownRenderer = memo(function MarkdownRenderer({
  content,
  currentRepoPath,
  onNavigate,
}: MarkdownRendererProps) {
  // Strip GitHub [!NOTE]/[!IMPORTANT] marker syntax cleanly into bold labels
  const normalizedContent = useMemo(
    () =>
      content.replace(
        /^>\s*\[!(NOTE|IMPORTANT|TIP|WARNING|CAUTION)\]\s*$/gm,
        (_, kind: string) => {
          const labelMap: Record<string, string> = {
            NOTE: '说明',
            IMPORTANT: '重要提示',
            TIP: '提示',
            WARNING: '注意',
            CAUTION: '警告',
          };
          return `> **${labelMap[kind] ?? kind}**`;
        },
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
              href={resolved.route ? `#${resolved.route}` : `#${resolved.hash ?? ''}`}
              onClick={(e) => {
                e.preventDefault();
                if (resolved.route) {
                  onNavigate(resolved.route, resolved.hash);
                } else if (resolved.hash) {
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
      pre({ children }: { children?: ReactNode }) {
        const child = Array.isArray(children) ? children[0] : children;
        if (
          child &&
          typeof child === 'object' &&
          'props' in child &&
          (child as { props?: { className?: string; children?: ReactNode } }).props
        ) {
          const props = (
            child as { props: { className?: string; children?: ReactNode } }
          ).props;
          return <CodeBlock className={props.className}>{props.children}</CodeBlock>;
        }
        return <CodeBlock>{children}</CodeBlock>;
      },
    }),
    [currentRepoPath, onNavigate],
  );

  return (
    <div className="moonset-prose">
      <ReactMarkdown
        remarkPlugins={REMARK_PLUGINS}
        rehypePlugins={REHYPE_PLUGINS}
        components={components}
      >
        {normalizedContent}
      </ReactMarkdown>
    </div>
  );
});
