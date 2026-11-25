import { Suspense, lazy, useId, useRef, useState, type KeyboardEvent } from 'react';
import { RotateCcw } from 'lucide-react';
import type { ResolvedTheme } from '../lib/theme';
import {
  TERMINAL_SCENARIOS,
  getScenarioById,
  type TerminalScenarioId,
} from '../lib/terminalScripts';

// xterm.js (~330 kB) is split out of the main bundle and streamed in after first paint.
const TerminalCanvas = lazy(() => import('./TerminalCanvas'));

interface XTermDemoProps {
  theme: ResolvedTheme;
  activeScenario: TerminalScenarioId;
  onSelectScenario: (id: TerminalScenarioId) => void;
}

function TerminalSkeleton() {
  return (
    <div aria-hidden="true" className="space-y-2.5 pt-1">
      <div className="h-3 w-56 rounded bg-slate-900/[0.06] dark:bg-white/[0.06]" />
      <div className="h-3 w-80 max-w-full rounded bg-slate-900/[0.045] dark:bg-white/[0.045]" />
      <div className="h-3 w-64 max-w-full rounded bg-slate-900/[0.045] dark:bg-white/[0.045]" />
    </div>
  );
}

export function XTermDemo({ theme, activeScenario, onSelectScenario }: XTermDemoProps) {
  const [replayNonce, setReplayNonce] = useState(0);
  const [isReadyForInput, setIsReadyForInput] = useState(false);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const baseId = useId();
  const panelId = `${baseId}-panel`;
  const scenario = getScenarioById(activeScenario);

  const selectByIndex = (index: number) => {
    const count = TERMINAL_SCENARIOS.length;
    const wrapped = (index + count) % count;
    onSelectScenario(TERMINAL_SCENARIOS[wrapped].id);
    tabRefs.current[wrapped]?.focus();
  };

  const handleTabKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const current = TERMINAL_SCENARIOS.findIndex((s) => s.id === activeScenario);
    if (event.key === 'ArrowRight') {
      event.preventDefault();
      selectByIndex(current + 1);
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      selectByIndex(current - 1);
    } else if (event.key === 'Home') {
      event.preventDefault();
      selectByIndex(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      selectByIndex(TERMINAL_SCENARIOS.length - 1);
    }
  };

  return (
    <div
      data-testid="moonset-terminal"
      data-scenario={activeScenario}
      className="overflow-hidden rounded-2xl border border-slate-900/[0.09] bg-[#F7F8FC] shadow-[0_24px_60px_-28px_rgba(15,23,42,0.18)] transition-colors dark:border-white/[0.1] dark:bg-[#0D0F17] dark:shadow-[0_28px_72px_-32px_rgba(0,0,0,0.75)]"
    >
      {/* Window chrome + scenario selector */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-900/[0.07] bg-white/75 px-4 py-2.5 dark:border-white/[0.07] dark:bg-[#121521]/90">
        <div className="flex min-w-0 items-center gap-3">
          <div aria-hidden="true" className="flex items-center gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
          </div>
          <span
            key={scenario.command}
            className="moonset-fade-in truncate font-mono text-xs text-slate-500 dark:text-slate-400"
          >
            {scenario.command}
          </span>
        </div>

        <div className="flex items-center gap-1.5">
          <div
            role="tablist"
            aria-label="终端演示场景"
            onKeyDown={handleTabKeyDown}
            className="flex items-center gap-0.5 rounded-lg bg-slate-900/[0.045] p-0.5 dark:bg-white/[0.05]"
          >
            {TERMINAL_SCENARIOS.map((item, idx) => {
              const selected = item.id === activeScenario;
              return (
                <button
                  key={item.id}
                  ref={(el) => {
                    tabRefs.current[idx] = el;
                  }}
                  id={`${baseId}-tab-${item.id}`}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  aria-controls={panelId}
                  tabIndex={selected ? 0 : -1}
                  onClick={() => onSelectScenario(item.id)}
                  className={`shrink-0 rounded-md px-2.5 py-1 font-mono text-xs font-medium whitespace-nowrap transition-[color,background-color,box-shadow] duration-200 ${
                    selected
                      ? 'bg-white text-slate-950 shadow-xs dark:bg-[#1E2235] dark:text-white'
                      : 'text-slate-600 hover:text-slate-950 dark:text-slate-400 dark:hover:text-white'
                  }`}
                >
                  {item.label}
                </button>
              );
            })}
          </div>

          <button
            type="button"
            onClick={() => setReplayNonce((n) => n + 1)}
            aria-label="重播当前终端演示"
            title="重播动画"
            className="group inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-900 dark:text-slate-400 dark:hover:bg-white/[0.07] dark:hover:text-white"
          >
            <RotateCcw className="h-3.5 w-3.5 transition-transform duration-500 group-hover:-rotate-180" />
          </button>
        </div>
      </div>

      {/* Live xterm.js canvas */}
      <div
        id={panelId}
        role="tabpanel"
        aria-labelledby={`${baseId}-tab-${activeScenario}`}
        className="moonset-xterm min-h-[452px] px-3 py-3 sm:min-h-[420px] sm:px-4"
      >
        <Suspense fallback={<TerminalSkeleton />}>
          <TerminalCanvas
            theme={theme}
            activeScenario={activeScenario}
            replayNonce={replayNonce}
            onSelectScenario={onSelectScenario}
            onRequestReplay={() => setReplayNonce((n) => n + 1)}
            onReadyForInputChange={setIsReadyForInput}
          />
        </Suspense>
      </div>

      {/* Caption & interactive hint */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-slate-900/[0.06] bg-white/55 px-4 py-2 text-xs text-slate-500 dark:border-white/[0.06] dark:bg-[#10121C]/80 dark:text-slate-400">
        <span key={scenario.id} className="moonset-fade-in">
          {scenario.caption}
        </span>
        <span className="hidden font-mono text-[11px] text-slate-400 sm:inline dark:text-slate-500">
          {isReadyForInput ? (
            '点击终端可键入 help · moonset doctor'
          ) : (
            <span className="inline-flex items-center gap-1.5">
              <span className="moonset-live-dot" aria-hidden="true" />
              正在播放 · 键入任意字符可随时接管交互
            </span>
          )}
        </span>
      </div>
    </div>
  );
}
