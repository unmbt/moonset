import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import type { ResolvedTheme } from '../lib/theme';
import {
  evaluateInteractiveCommand,
  getScenarioById,
  type TerminalScenarioId,
} from '../lib/terminalScripts';

export interface TerminalCanvasProps {
  theme: ResolvedTheme;
  activeScenario: TerminalScenarioId;
  replayNonce: number;
  onSelectScenario: (id: TerminalScenarioId) => void;
  onRequestReplay: () => void;
  onReadyForInputChange: (ready: boolean) => void;
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
const TERMINAL_FONT =
  "'JetBrains Mono Variable', 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace";

/**
 * Fixed row budgets guarantee every scenario (longest: `add`, 18 lines) stays fully
 * visible from the typed command to the final prompt — the beginning never scrolls
 * out of view. Narrow screens wrap long lines, so they get a smaller font and more rows.
 */
export const TERMINAL_LAYOUT = {
  wide: { rows: 19, fontSize: 13 },
  narrow: { rows: 25, fontSize: 11 },
  narrowBreakpointPx: 560,
  lineHeight: 1.25,
} as const;

function waitForTerminalFont(timeoutMs: number): Promise<void> {
  if (typeof document === 'undefined' || !document.fonts?.load) return Promise.resolve();
  return Promise.race([
    document.fonts.load(`13px 'JetBrains Mono Variable'`).then(() => undefined),
    new Promise<void>((resolve) => window.setTimeout(resolve, timeoutMs)),
  ]).catch(() => undefined);
}

export default function TerminalCanvas({
  theme,
  activeScenario,
  replayNonce,
  onSelectScenario,
  onRequestReplay,
  onReadyForInputChange,
}: TerminalCanvasProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const playbackCancelRef = useRef<(() => void) | null>(null);
  const inputBufferRef = useRef<string>('');
  const isPlayingRef = useRef<boolean>(false);
  const callbacksRef = useRef({ onSelectScenario, onRequestReplay, onReadyForInputChange });
  callbacksRef.current = { onSelectScenario, onRequestReplay, onReadyForInputChange };
  const themeRef = useRef(theme);
  themeRef.current = theme;

  const [terminalReady, setTerminalReady] = useState(false);
  const scenario = getScenarioById(activeScenario);

  // Initialize xterm.js once the mono font is available so glyph metrics are exact.
  useEffect(() => {
    let cancelled = false;
    let term: Terminal | null = null;
    let resizeObserver: ResizeObserver | null = null;
    let dataDisposable: { dispose: () => void } | null = null;
    let rafId = 0;

    waitForTerminalFont(1500).then(() => {
      rafId = window.requestAnimationFrame(() => {
        const host = containerRef.current;
        if (cancelled || !host) return;

        const narrow = host.clientWidth < TERMINAL_LAYOUT.narrowBreakpointPx;
        const layout = narrow ? TERMINAL_LAYOUT.narrow : TERMINAL_LAYOUT.wide;

        term = new Terminal({
          fontFamily: TERMINAL_FONT,
          fontSize: layout.fontSize,
          lineHeight: TERMINAL_LAYOUT.lineHeight,
          letterSpacing: 0,
          cursorBlink: true,
          cursorStyle: 'bar',
          convertEol: true,
          scrollback: 200,
          rows: layout.rows,
          theme: themeRef.current === 'dark' ? DARK_XTERM_THEME : LIGHT_XTERM_THEME,
        });
        const fitAddon = new FitAddon();
        term.loadAddon(fitAddon);
        term.open(host);

        let lastWidth = -1;
        const applyLayout = () => {
          if (cancelled || !term) return;
          const width = host.clientWidth;
          if (width === lastWidth) return;
          lastWidth = width;
          const isNarrow = width < TERMINAL_LAYOUT.narrowBreakpointPx;
          const next = isNarrow ? TERMINAL_LAYOUT.narrow : TERMINAL_LAYOUT.wide;
          if (term.options.fontSize !== next.fontSize) {
            term.options.fontSize = next.fontSize;
          }
          try {
            const dims = fitAddon.proposeDimensions();
            const cols = dims && Number.isFinite(dims.cols) ? Math.max(24, dims.cols) : term.cols;
            if (cols !== term.cols || next.rows !== term.rows) {
              term.resize(cols, next.rows);
            }
          } catch {
            // Ignore measurements taken before layout settles
          }
        };

        window.requestAnimationFrame(applyLayout);
        resizeObserver = new ResizeObserver(() => applyLayout());
        resizeObserver.observe(host);

        dataDisposable = term.onData((data) => {
          if (!term) return;
          if (isPlayingRef.current) {
            playbackCancelRef.current?.();
            isPlayingRef.current = false;
            callbacksRef.current.onReadyForInputChange(true);
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
              callbacksRef.current.onSelectScenario(result.switchScenario);
              callbacksRef.current.onRequestReplay();
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
        setTerminalReady(true);
      });
    });

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(rafId);
      playbackCancelRef.current?.();
      dataDisposable?.dispose();
      resizeObserver?.disconnect();
      term?.dispose();
      termRef.current = null;
      setTerminalReady(false);
    };
  }, []);

  // Sync palette before paint so View Transitions capture the new terminal theme
  useLayoutEffect(() => {
    const term = termRef.current;
    if (!term || !terminalReady) return;
    term.options.theme = theme === 'dark' ? DARK_XTERM_THEME : LIGHT_XTERM_THEME;
  }, [theme, terminalReady]);

  // Play the active scenario script with realistic pacing
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

    const reduced =
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    term.reset();
    inputBufferRef.current = '';
    isPlayingRef.current = true;
    callbacksRef.current.onReadyForInputChange(false);

    if (reduced) {
      for (const step of scenario.steps) term.write(step.text);
      term.write('\r\n' + PROMPT);
      isPlayingRef.current = false;
      callbacksRef.current.onReadyForInputChange(true);
      return cancel;
    }

    const wait = (ms: number) =>
      new Promise<void>((resolve) => {
        timers.push(window.setTimeout(resolve, ms));
      });

    (async () => {
      for (const step of scenario.steps) {
        if (cancelled) return;
        await wait(step.delayMs);
        if (cancelled) return;
        if (step.typewriter) {
          const charDelay = step.charDelayMs ?? 30;
          for (const ch of Array.from(step.text)) {
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
        callbacksRef.current.onReadyForInputChange(true);
      }
    })();

    return cancel;
  }, [scenario, replayNonce, terminalReady]);

  return (
    <div
      ref={containerRef}
      data-terminal-ready={terminalReady ? 'true' : 'false'}
      className={`w-full transition-opacity duration-500 ${terminalReady ? 'opacity-100' : 'opacity-0'}`}
    />
  );
}
