import { createHighlighterCoreSync, type HighlighterCore } from 'shiki/core';
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
import langBash from 'shiki/langs/bash.mjs';
import langDiff from 'shiki/langs/diff.mjs';
import langJavascript from 'shiki/langs/javascript.mjs';
import langJson from 'shiki/langs/json.mjs';
import langMarkdown from 'shiki/langs/markdown.mjs';
import langMermaid from 'shiki/langs/mermaid.mjs';
import langMoonbit from 'shiki/langs/moonbit.mjs';
import langPowershell from 'shiki/langs/powershell.mjs';
import langRust from 'shiki/langs/rust.mjs';
import langToml from 'shiki/langs/toml.mjs';
import langTypescript from 'shiki/langs/typescript.mjs';
import langYaml from 'shiki/langs/yaml.mjs';
import themeDark from 'shiki/themes/github-dark-default.mjs';
import themeLight from 'shiki/themes/github-light.mjs';

export type SupportedCodeLanguage =
  | 'bash'
  | 'diff'
  | 'javascript'
  | 'json'
  | 'markdown'
  | 'mermaid'
  | 'moonbit'
  | 'powershell'
  | 'rust'
  | 'toml'
  | 'typescript'
  | 'yaml';

export interface HighlightedToken {
  content: string;
  lightColor?: string;
  darkColor?: string;
  italic?: boolean;
  bold?: boolean;
  underline?: boolean;
}

export interface HighlightResult {
  language: SupportedCodeLanguage | null;
  lines: HighlightedToken[][];
}

const LANGUAGE_ALIASES: Record<string, SupportedCodeLanguage> = {
  bash: 'bash',
  sh: 'bash',
  shell: 'bash',
  shellscript: 'bash',
  zsh: 'bash',
  diff: 'diff',
  patch: 'diff',
  javascript: 'javascript',
  js: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  json: 'json',
  jsonc: 'json',
  jsonl: 'json',
  markdown: 'markdown',
  md: 'markdown',
  mermaid: 'mermaid',
  moonbit: 'moonbit',
  mbt: 'moonbit',
  mbti: 'moonbit',
  mbtx: 'moonbit',
  powershell: 'powershell',
  ps1: 'powershell',
  pwsh: 'powershell',
  rust: 'rust',
  rs: 'rust',
  toml: 'toml',
  typescript: 'typescript',
  ts: 'typescript',
  mts: 'typescript',
  yaml: 'yaml',
  yml: 'yaml',
};

export function normalizeCodeLanguage(
  rawLang: string | null | undefined,
): SupportedCodeLanguage | null {
  if (!rawLang) return null;
  const key = rawLang.trim().toLowerCase();
  if (!key || key === 'text' || key === 'txt' || key === 'plaintext' || key === 'plain') {
    return null;
  }
  return LANGUAGE_ALIASES[key] ?? null;
}

let cachedHighlighter: HighlighterCore | null = null;

function getHighlighter(): HighlighterCore {
  if (cachedHighlighter) return cachedHighlighter;

  cachedHighlighter = createHighlighterCoreSync({
    themes: [themeLight, themeDark],
    langs: [
      langBash,
      langDiff,
      langJavascript,
      langJson,
      langMarkdown,
      langMermaid,
      langMoonbit,
      langPowershell,
      langRust,
      langToml,
      langTypescript,
      langYaml,
    ],
    engine: createJavaScriptRegexEngine({ forgiving: true }),
  });

  return cachedHighlighter;
}

function plainLines(code: string): HighlightedToken[][] {
  return code.split('\n').map((line) => [{ content: line }]);
}

/**
 * Synchronously tokenizes a fenced code block via Shiki's JS RegExp engine
 * into dual-theme (light/dark) structured React-safe tokens.
 */
export function highlightCodeLines(
  code: string,
  rawLang?: string | null,
): HighlightResult {
  const language = normalizeCodeLanguage(rawLang);
  if (!language) {
    return {
      language: null,
      lines: plainLines(code),
    };
  }

  try {
    const highlighter = getHighlighter();
    const { tokens } = highlighter.codeToTokens(code, {
      lang: language,
      themes: {
        light: 'github-light',
        dark: 'github-dark-default',
      },
      defaultColor: false,
    });

    const lines: HighlightedToken[][] = tokens.map((line) =>
      line.map((token) => {
        const style = token.htmlStyle ?? {};
        return {
          content: token.content,
          lightColor: style['--shiki-light'],
          darkColor: style['--shiki-dark'],
          italic:
            style['--shiki-light-font-style'] === 'italic' ||
            style['--shiki-dark-font-style'] === 'italic',
          bold:
            style['--shiki-light-font-weight'] === 'bold' ||
            style['--shiki-dark-font-weight'] === 'bold',
          underline:
            style['--shiki-light-text-decoration'] === 'underline' ||
            style['--shiki-dark-text-decoration'] === 'underline',
        };
      }),
    );

    return { language, lines };
  } catch {
    return {
      language: null,
      lines: plainLines(code),
    };
  }
}
