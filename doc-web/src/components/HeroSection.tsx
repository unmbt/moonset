import { useState } from 'react';
import { ArrowRight, Check, Copy } from 'lucide-react';
import type { ResolvedTheme } from '../lib/theme';
import type { TerminalScenarioId } from '../lib/terminalScripts';
import { XTermDemo } from './XTermDemo';
import { Phrases, delayStyle } from './motion';
import { MOONSET_VERSION } from '../lib/version';

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
    <section className="relative pt-14 pb-20 sm:pt-24 sm:pb-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-6">
        <div className="mx-auto max-w-3xl text-center">
          <div
            style={delayStyle(0)}
            className="moonset-enter mb-6 flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 text-xs font-medium tracking-wide text-slate-500 dark:text-slate-400"
          >
            <span className="inline-flex items-center gap-1.5 rounded-full border border-indigo-500/20 bg-indigo-500/[0.06] px-2.5 py-0.5 text-indigo-700 dark:border-indigo-400/25 dark:bg-indigo-400/[0.08] dark:text-indigo-300">
              <span className="moonset-live-dot" aria-hidden="true" />
              v{MOONSET_VERSION}
            </span>
            <span>MoonBit Workspace</span>
            <span aria-hidden="true" className="hidden sm:inline">
              ·
            </span>
            <span className="hidden sm:inline">Pure Release Planner</span>
          </div>

          <h1
            style={delayStyle(70)}
            className="moonset-enter moonset-cjk-heading font-display text-[clamp(2.25rem,4.8vw,4.15rem)] font-bold leading-[1.12] tracking-[-0.035em] text-slate-950 dark:text-white"
          >
            <Phrases text="月升则潮起，" />
            <br />
            <span className="moonset-hero-gradient">
              <Phrases text="版本有序，更迭有据。" />
            </span>
          </h1>

          <p
            style={{ ...delayStyle(140), textWrap: 'pretty' }}
            className="moonset-enter mx-auto mt-6 max-w-2xl text-[0.97rem] leading-relaxed text-slate-600 sm:text-[1.0625rem] dark:text-slate-400"
          >
            为 MoonBit workspace 而生的版本规划、Changelog 生成与多生态发布工具。
            理解 <code className="font-mono text-[0.9em] text-slate-800 dark:text-slate-200">moon.mod</code> 与混合仓库，以纯计算推演发布图谱，让每一次发版皆有章可循。
          </p>

          <div
            style={delayStyle(210)}
            className="moonset-enter mt-9 flex flex-col items-center justify-center gap-3.5 sm:flex-row"
          >
            <a
              href="#/docs/quickstart"
              onClick={(e) => {
                e.preventDefault();
                onNavigate('/docs/quickstart');
              }}
              className="group inline-flex h-11 shrink-0 items-center gap-2 rounded-xl bg-slate-950 px-6 text-sm font-medium whitespace-nowrap text-white shadow-[0_8px_24px_-12px_rgba(15,23,42,0.5)] transition-[background-color,transform,box-shadow] duration-200 hover:-translate-y-px hover:bg-slate-800 active:translate-y-0 dark:bg-white dark:text-slate-950 dark:shadow-[0_8px_28px_-12px_rgba(165,180,252,0.45)] dark:hover:bg-slate-200"
            >
              阅读文档
              <ArrowRight className="h-4 w-4 transition-transform duration-200 group-hover:translate-x-0.5" />
            </a>

            <div className="flex h-11 w-full max-w-full items-center gap-2 rounded-xl border border-slate-900/[0.1] bg-white/80 pr-2 pl-4 font-mono text-xs text-slate-700 backdrop-blur-xs sm:w-auto dark:border-white/[0.1] dark:bg-white/[0.04] dark:text-slate-300">
              <span aria-hidden="true" className="text-slate-400 select-none dark:text-slate-500">
                $
              </span>
              <span className="min-w-0 flex-1 truncate text-left select-all">{INSTALL_CMD}</span>
              <button
                type="button"
                onClick={handleCopy}
                aria-label={copied ? '已复制安装命令' : '复制安装命令'}
                className="relative inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-400 dark:hover:bg-white/[0.08] dark:hover:text-white"
              >
                <Copy
                  className={`absolute h-3.5 w-3.5 transition-all duration-200 ${copied ? 'scale-50 opacity-0' : 'scale-100 opacity-100'}`}
                />
                <Check
                  className={`absolute h-3.5 w-3.5 text-emerald-600 transition-all duration-200 dark:text-emerald-400 ${copied ? 'scale-100 opacity-100' : 'scale-50 opacity-0'}`}
                />
              </button>
            </div>
          </div>
        </div>

        {/* Dominant visual focal anchor: live xterm.js CLI & inline TUI showcase */}
        <div style={delayStyle(320)} className="moonset-enter-up mx-auto mt-14 max-w-4xl">
          <XTermDemo theme={theme} activeScenario={scenario} onSelectScenario={setScenario} />
        </div>
      </div>
    </section>
  );
}
