import { useState } from 'react';
import { ArrowRight, Check, Copy } from 'lucide-react';
import type { ResolvedTheme } from '../lib/theme';
import type { TerminalScenarioId } from '../lib/terminalScripts';
import { XTermDemo } from './XTermDemo';

interface HeroSectionProps {
  theme: ResolvedTheme;
  onNavigate: (route: string) => void;
}

const INSTALL_CMD = 'moon install unmbt/moonset/cmd/moonset';

export function HeroSection({ theme, onNavigate }: HeroSectionProps) {
  const [scenario, setScenario] = useState<TerminalScenarioId>('add');
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(INSTALL_CMD);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="relative pt-16 pb-20 sm:pt-24 sm:pb-28">
      <div className="mx-auto max-w-6xl px-6">
        {/* Centered restrained editorial opening */}
        <div className="mx-auto max-w-3xl text-center">
          <div className="mb-6 flex items-center justify-center gap-2.5 text-xs font-medium tracking-wide text-slate-500 dark:text-slate-400">
            <span>MoonBit Workspace</span>
            <span aria-hidden="true">·</span>
            <span>Pure Release Planner</span>
            <span aria-hidden="true">·</span>
            <span>v0.2.0</span>
          </div>

          <h1
            className="font-display text-[clamp(2.35rem,4.8vw,4.15rem)] font-bold leading-[1.1] tracking-[-0.035em] text-slate-950 dark:text-white"
            style={{ textWrap: 'balance' }}
          >
            月升则潮起，
            <br />
            版本有序，更迭有据。
          </h1>

          <p
            className="mx-auto mt-6 max-w-2xl text-base leading-relaxed text-slate-600 sm:text-[1.0625rem] dark:text-slate-400"
            style={{ textWrap: 'balance' }}
          >
            为 MoonBit workspace 而生的版本规划、Changelog 生成与多生态发布工具。
            理解 <code className="font-mono text-[0.9em] text-slate-800 dark:text-slate-200">moon.mod</code> 与混合仓库，以纯计算推演发布图谱，让每一次发版皆有章可循。
          </p>

          {/* Restrained single primary CTA + quiet copyable install strip */}
          <div className="mt-9 flex flex-col items-center justify-center gap-3.5 sm:flex-row">
            <a
              href="#/docs/quickstart"
              onClick={(e) => {
                e.preventDefault();
                onNavigate('/docs/quickstart');
              }}
              className="inline-flex h-11 shrink-0 items-center gap-2 rounded-xl bg-slate-950 px-6 text-sm font-medium whitespace-nowrap text-white transition-colors hover:bg-slate-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
            >
              阅读文档
              <ArrowRight className="h-4 w-4" />
            </a>

            <div className="flex h-11 max-w-full items-center gap-2 rounded-xl border border-slate-900/[0.1] bg-white/80 pl-4 pr-2 font-mono text-xs text-slate-700 backdrop-blur-xs dark:border-white/[0.1] dark:bg-white/[0.04] dark:text-slate-300">
              <span className="truncate select-all">{INSTALL_CMD}</span>
              <button
                type="button"
                onClick={handleCopy}
                aria-label="复制安装命令"
                className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-400 dark:hover:bg-white/[0.08] dark:hover:text-white"
              >
                {copied ? (
                  <Check className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" />
                ) : (
                  <Copy className="h-3.5 w-3.5" />
                )}
              </button>
            </div>
          </div>
        </div>

        {/* Dominant visual focal anchor: Live xterm.js CLI & inline TUI showcase */}
        <div className="mx-auto mt-14 max-w-4xl">
          <XTermDemo
            theme={theme}
            activeScenario={scenario}
            onSelectScenario={setScenario}
          />
        </div>
      </div>
    </section>
  );
}
