import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import { RotateCcw } from 'lucide-react';
import type { ResolvedTheme } from '../lib/theme';
import {
  TERMINAL_SCENARIOS,
  evaluateInteractiveCommand,
  getScenarioById,
  type TerminalScenarioId,
} from '../lib/terminalScripts';

interface XTermDemoProps {
  theme: ResolvedTheme;
  activeScenario: TerminalScenarioId;
  onSelectScenario: (id: TerminalScenarioId) => void;
}

const DARK_XTERM_THEME = {
  background: '#0D0F17',
  foreground: '#E6EAF5',
  cursor: '#818CF8',
  cursorAccent: '#0D0F17',
  selectionBackground: 'rgba(129, 140, 248, 0.28)',
  black: '#1E2233',
  red: '#F87171',
  green: '#4ADE80',
  yellow: '#FBBF24',
  blue: '#60A5FA',
  magenta: '#C084FC',
  cyan: '#38BDF8',
  white: '#E6EAF5',
  brightBlack: '#64748B',
  brightRed: '#FCA5A5',
  brightGreen: '#86EFAC',
  brightYellow: '#FDE68A',
  brightBlue: '#93C5FD',
  brightMagenta: '#D8B4FE',
  brightCyan: '#7DD3FC',
  brightWhite: '#FFFFFF',
};

const LIGHT_XTERM_THEME = {
  background: '#F7F8FC',
  foreground: '#171B26',
  cursor: '#4F46E5',
  cursorAccent: '#F7F8FC',
  selectionBackground: 'rgba(79, 70, 229, 0.16)',
  black: '#171B26',
  red: '#DC2626',
  green: '#15803D',
  yellow: '#B45309',
  blue: '#2563EB',
  magenta: '#7C3AED',
  cyan: '#0369A1',
  white: '#E2E8F0',
  brightBlack: '#64748B',
  brightRed: '#EF4444',
  brightGreen: '#16A34A',
  brightYellow: '#D97706',
  brightBlue: '#3B82F6',
  brightMagenta: '#9333EA',
  brightCyan: '#0284C7',
  brightWhite: '#0F172A',
};

const PROMPT = '\x1b[2m~/workspace/acme-moon\x1b[0m \x1b[36m$\x1b[0m ';

export function XTermDemo({
  theme,
  activeScenario,
  onSelectScenario,
}: XTermDemoProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const playbackCancelRef = useRef<(() => void) | null>(null);
  const inputBufferRef = useRef<string>('');
  const isPlayingRef = useRef<boolean>(false);
  const onSelectScenarioRef = useRef(onSelectScenario);
  onSelectScenarioRef.current = onSelectScenario;

  const [replayNonce, setReplayNonce] = useState(0);
  const [terminalReady, setTerminalReady] = useState(false);
  const [isReadyForInput, setIsReadyForInput] = useState(false);

  const scenario = getScenarioById(activeScenario);

  // Initialize xterm.js inside RAF so React StrictMode's immediate unmount
  // never races with xterm's internal Viewport.syncScrollArea RAF.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    let cancelled = false;
    let term: Terminal | null = null;
    let fitAddon: FitAddon | null = null;
    let resizeObserver: ResizeObserver | null = null;
    let dataDisposable: { dispose: () => void } | null = null;

    const openRafId = window.requestAnimationFrame(() => {
      if (cancelled || !containerRef.current) return;

      term = new Terminal({
        fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize: 13,
        lineHeight: 1.5,
        letterSpacing: 0,
        cursorBlink: true,
        cursorStyle: 'bar',
        convertEol: true,
        scrollback: 200,
        rows: 19,
        theme: theme === 'dark' ? DARK_XTERM_THEME : LIGHT_XTERM_THEME,
      });

      fitAddon = new FitAddon();
      term.loadAddon(fitAddon);
      term.open(containerRef.current);

      const safeFit = () => {
        if (cancelled || !fitAddon || !term) return;
        try {
          fitAddon.fit();
        } catch {
          // Ignore resize before layout settles
        }
      };

      window.requestAnimationFrame(() => safeFit());

      resizeObserver = new ResizeObserver(() => safeFit());
      resizeObserver.observe(containerRef.current);

      dataDisposable = term.onData((data) => {
        if (!term) return;
        if (isPlayingRef.current) {
          playbackCancelRef.current?.();
          isPlayingRef.current = false;
          setIsReadyForInput(true);
          term.write('\r\n' + PROMPT);
          inputBufferRef.current = '';
        }

        if (data === '\r') {
          const cmd = inputBufferRef.current;
          inputBufferRef.current = '';
          term.write('\r\n');
          const result = evaluateInteractiveCommand(cmd);
          if (result.clear) {
            term.clear();
            term.write(PROMPT);
            return;
          }
          if (result.switchScenario) {
            onSelectScenarioRef.current(result.switchScenario);
            setReplayNonce((n) => n + 1);
            return;
          }
          for (const line of result.lines) {
            term.writeln(line);
          }
          term.write(PROMPT);
          return;
        }

        if (data === '\x7f') {
          if (inputBufferRef.current.length > 0) {
            inputBufferRef.current = inputBufferRef.current.slice(0, -1);
            term.write('\b \b');
          }
          return;
        }

        if (data === '\x03') {
          inputBufferRef.current = '';
          term.write('^C\r\n' + PROMPT);
          return;
        }

        if (data >= ' ' && data !== '\x7f') {
          inputBufferRef.current += data;
          term.write(data);
        }
      });

      termRef.current = term;
      fitRef.current = fitAddon;
      setTerminalReady(true);
    });

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(openRafId);
      playbackCancelRef.current?.();
      dataDisposable?.dispose();
      resizeObserver?.disconnect();
      if (term) {
        term.dispose();
      }
      termRef.current = null;
      fitRef.current = null;
      setTerminalReady(false);
    };
    // Mount terminal once; theme & scenario updates happen in dedicated effects
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Sync xterm.js color palette synchronously before paint so View Transitions capture the new terminal theme
  useLayoutEffect(() => {
    const term = termRef.current;
    if (!term || !terminalReady) return;
    term.options.theme = theme === 'dark' ? DARK_XTERM_THEME : LIGHT_XTERM_THEME;
  }, [theme, terminalReady]);

  // Play active scenario script with realistic pacing
  useEffect(() => {
    const term = termRef.current;
    if (!term || !terminalReady) return;

    playbackCancelRef.current?.();
    let cancelled = false;
    const timers: number[] = [];

    const cancel = () => {
      cancelled = true;
      for (const id of timers) window.clearTimeout(id);
      timers.length = 0;
    };
    playbackCancelRef.current = cancel;

    const prefersReduced =
      typeof window !== 'undefined' &&
      window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    term.reset();
    inputBufferRef.current = '';
    isPlayingRef.current = true;
    setIsReadyForInput(false);

    if (prefersReduced) {
      for (const step of scenario.steps) {
        term.write(step.text);
      }
      term.write('\r\n' + PROMPT);
      isPlayingRef.current = false;
      setIsReadyForInput(true);
      return cancel;
    }

    const wait = (ms: number) =>
      new Promise<void>((resolve) => {
        const id = window.setTimeout(resolve, ms);
        timers.push(id);
      });

    (async () => {
      for (const step of scenario.steps) {
        if (cancelled) return;
        await wait(step.delayMs);
        if (cancelled) return;

        if (step.typewriter) {
          const chars = Array.from(step.text);
          const charDelay = step.charDelayMs ?? 30;
          for (const ch of chars) {
            if (cancelled) return;
            term.write(ch);
            await wait(charDelay);
          }
        } else {
          term.write(step.text);
        }
      }

      if (!cancelled) {
        await wait(240);
        if (cancelled) return;
        term.write('\r\n' + PROMPT);
        isPlayingRef.current = false;
        setIsReadyForInput(true);
      }
    })();

    return cancel;
  }, [scenario, replayNonce, terminalReady]);

  return (
    <div
      data-testid="moonset-terminal"
      data-scenario={activeScenario}
      className="overflow-hidden rounded-2xl border border-slate-900/[0.09] bg-[#F7F8FC] shadow-[0_24px_60px_-28px_rgba(15,23,42,0.18)] transition-colors dark:border-white/[0.1] dark:bg-[#0D0F17] dark:shadow-[0_28px_72px_-32px_rgba(0,0,0,0.75)]"
    >
      {/* Window chrome + scenario selector */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-900/[0.07] bg-white/75 px-4 py-2.5 dark:border-white/[0.07] dark:bg-[#121521]/90">
        <div className="flex items-center gap-3">
          <div aria-hidden="true" className="flex items-center gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
            <span className="h-2.5 w-2.5 rounded-full bg-slate-300 dark:bg-slate-700" />
          </div>
          <span className="font-mono text-xs text-slate-500 dark:text-slate-400">
            {scenario.command}
          </span>
        </div>

        <div className="flex items-center gap-1.5">
          <div
            role="tablist"
            aria-label="终端演示场景"
            className="flex items-center gap-0.5 rounded-lg bg-slate-900/[0.045] p-0.5 dark:bg-white/[0.05]"
          >
            {TERMINAL_SCENARIOS.map((item) => {
              const selected = item.id === activeScenario;
              return (
                <button
                  key={item.id}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  onClick={() => onSelectScenario(item.id)}
                  className={`rounded-md px-2.5 py-1 font-mono text-xs font-medium whitespace-nowrap shrink-0 transition-colors ${
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
            className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-900 dark:text-slate-400 dark:hover:bg-white/[0.07] dark:hover:text-white"
          >
            <RotateCcw className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      {/* Live xterm.js canvas */}
      <div className="moonset-xterm px-4 py-3">
        <div ref={containerRef} className="h-[396px] w-full" />
      </div>

      {/* Subtle footer caption & interactive hint */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-slate-900/[0.06] bg-white/55 px-4 py-2 text-xs text-slate-500 dark:border-white/[0.06] dark:bg-[#10121C]/80 dark:text-slate-400">
        <span>{scenario.caption}</span>
        <span className="font-mono text-[11px] text-slate-400 dark:text-slate-500">
          {isReadyForInput
            ? '点击终端可键入 help · moonset doctor'
            : '正在播放 · 键入任意字符可随时接管交互'}
        </span>
      </div>
    </div>
  );
}
