import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from 'react';
import { createPortal } from 'react-dom';
import { Maximize2, Minus, Plus, RotateCcw, X } from 'lucide-react';
import {
  DEFAULT_PAN_ZOOM_LIMITS,
  INITIAL_PAN_ZOOM_STATE,
  applyPanDelta,
  clampScale,
  computePinchSnapshot,
  computeWheelZoomScale,
  stepPinchTransform,
  zoomAtPoint,
  type PanZoomState,
  type PinchSnapshot,
  type Point2D,
} from '../lib/panZoom';

interface MermaidDiagramProps {
  source: string;
}

type MermaidThemeMode = 'light' | 'dark';

let renderQueue: Promise<unknown> = Promise.resolve();
let renderCounter = 0;

function readDocumentTheme(): MermaidThemeMode {
  if (typeof document === 'undefined') return 'light';
  return document.documentElement.classList.contains('dark') ? 'dark' : 'light';
}

function getMermaidThemeVariables(mode: MermaidThemeMode) {
  if (mode === 'dark') {
    return {
      darkMode: true,
      background: 'transparent',
      fontFamily: "'Plus Jakarta Sans', 'Noto Sans SC', system-ui, sans-serif",
      fontSize: '14px',
      primaryColor: '#171B2B',
      primaryTextColor: '#EEF0F7',
      primaryBorderColor: '#4F5B88',
      lineColor: '#818CF8',
      secondaryColor: '#121624',
      secondaryTextColor: '#CBD5E1',
      secondaryBorderColor: '#334155',
      tertiaryColor: '#111522',
      tertiaryTextColor: '#E2E8F0',
      tertiaryBorderColor: '#334155',
      clusterBkg: '#101320',
      clusterBorder: '#334155',
      edgeLabelBackground: '#0C0E16',
      nodeTextColor: '#EEF0F7',
      textColor: '#EEF0F7',
    };
  }
  return {
    darkMode: false,
    background: 'transparent',
    fontFamily: "'Plus Jakarta Sans', 'Noto Sans SC', system-ui, sans-serif",
    fontSize: '14px',
    primaryColor: '#FFFFFF',
    primaryTextColor: '#10131C',
    primaryBorderColor: '#A5B4FC',
    lineColor: '#4F46E5',
    secondaryColor: '#F1F5F9',
    secondaryTextColor: '#1E293B',
    secondaryBorderColor: '#CBD5E1',
    tertiaryColor: '#EEF2FF',
    tertiaryTextColor: '#1E1B4B',
    tertiaryBorderColor: '#C7D2FE',
    clusterBkg: '#F8FAFC',
    clusterBorder: '#CBD5E1',
    edgeLabelBackground: '#F4F5FA',
    nodeTextColor: '#10131C',
    textColor: '#10131C',
  };
}

/**
 * Serializes Mermaid initialization & SVG rendering so multiple diagrams on the
 * same page never race over Mermaid's global theme configuration.
 */
function renderMermaidSvg(source: string, mode: MermaidThemeMode): Promise<string> {
  const job = renderQueue.then(async () => {
    const mermaidModule = await import('mermaid');
    const mermaid = mermaidModule.default;

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'base',
      themeVariables: getMermaidThemeVariables(mode),
      flowchart: {
        useMaxWidth: true,
        htmlLabels: true,
        curve: 'basis',
        padding: 14,
      },
    });

    const diagramId = `moonset-mmd-${++renderCounter}`;
    const { svg } = await mermaid.render(diagramId, source);
    return svg;
  });

  renderQueue = job.catch(() => undefined);
  return job;
}

/**
 * Safely parses SVG markup via HTML5 DOMParser (which natively supports Mermaid's
 * <foreignObject> HTML labels such as <br>), strips executable elements/attributes,
 * and mounts the sanitized SVG DOM node into `container` without raw innerHTML injection.
 */
function mountSanitizedSvg(
  container: HTMLDivElement,
  svgMarkup: string,
  mode: 'inline' | 'lightbox' = 'inline',
) {
  container.replaceChildren();
  if (!svgMarkup) return;

  const parser = new DOMParser();
  const parsed = parser.parseFromString(svgMarkup, 'text/html');
  const svgEl = parsed.body.querySelector('svg');
  if (!svgEl) return;

  // Defensive strip of script elements & inline event handlers
  svgEl.querySelectorAll('script').forEach((node) => node.remove());
  const allElements = [svgEl, ...Array.from(svgEl.querySelectorAll('*'))];
  for (const el of allElements) {
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      const val = attr.value.trim().toLowerCase();
      if (name.startsWith('on')) {
        el.removeAttribute(attr.name);
      } else if (
        (name === 'href' || name === 'xlink:href') &&
        val.startsWith('javascript:')
      ) {
        el.removeAttribute(attr.name);
      }
    }
  }

  // Normalize sizing from viewBox so inline cards fit cleanly and lightbox stays crisp at any zoom
  const viewBoxAttr = svgEl.getAttribute('viewBox');
  const vbParts = viewBoxAttr
    ? viewBoxAttr
        .trim()
        .split(/[\s,]+/)
        .map(Number)
    : [];
  const vbWidth = vbParts.length === 4 && Number.isFinite(vbParts[2]) ? vbParts[2] : 0;
  const vbHeight = vbParts.length === 4 && Number.isFinite(vbParts[3]) ? vbParts[3] : 0;

  if (mode === 'lightbox' && vbWidth > 0 && vbHeight > 0) {
    // Fit comfortably inside the lightbox stage at scale=1 while remaining crisp vector SVG
    const maxW = Math.max(280, Math.min(window.innerWidth * 0.84, 1020));
    const maxH = Math.max(240, Math.min(window.innerHeight * 0.68, 620));
    const fitRatio = Math.min(maxW / vbWidth, maxH / vbHeight, 1.35);
    svgEl.removeAttribute('height');
    svgEl.setAttribute('width', String(Math.round(vbWidth * fitRatio)));
    svgEl.style.width = `${Math.round(vbWidth * fitRatio)}px`;
    svgEl.style.height = `${Math.round(vbHeight * fitRatio)}px`;
    svgEl.style.maxWidth = 'none';
    svgEl.style.display = 'block';
  } else {
    svgEl.style.maxWidth = '100%';
    svgEl.style.height = 'auto';
    svgEl.style.display = 'block';
  }

  const imported = document.importNode(svgEl, true);
  container.appendChild(imported);
}

interface MermaidLightboxProps {
  svgMarkup: string;
  onClose: () => void;
}

function MermaidLightbox({ svgMarkup, onClose }: MermaidLightboxProps) {
  const titleId = useId();
  const viewportRef = useRef<HTMLDivElement>(null);
  const svgHostRef = useRef<HTMLDivElement>(null);

  const [transform, setTransform] = useState<PanZoomState>(INITIAL_PAN_ZOOM_STATE);
  const transformRef = useRef<PanZoomState>(INITIAL_PAN_ZOOM_STATE);
  transformRef.current = transform;

  const [isDragging, setIsDragging] = useState(false);

  // Active pointer tracking for unified mouse drag, 1-finger pan, and 2-finger pinch-zoom
  const pointersRef = useRef<Map<number, Point2D>>(new Map());
  const dragStartPointerRef = useRef<Point2D | null>(null);
  const pinchStartRef = useRef<{
    state: PanZoomState;
    pinch: PinchSnapshot;
  } | null>(null);
  const lastTapRef = useRef<{ time: number; point: Point2D } | null>(null);

  // Mount sanitized SVG into lightbox stage
  useEffect(() => {
    const host = svgHostRef.current;
    if (!host) return;
    mountSanitizedSvg(host, svgMarkup, 'lightbox');
  }, [svgMarkup]);

  // Lock background page scroll & custom inertial smooth-scroll while lightbox is open
  useEffect(() => {
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    document.documentElement.dataset.smoothScrollLock = 'true';
    return () => {
      document.body.style.overflow = prevOverflow;
      delete document.documentElement.dataset.smoothScrollLock;
    };
  }, []);

  const getViewportCenter = useCallback((): Point2D => {
    const rect = viewportRef.current?.getBoundingClientRect();
    if (!rect) return { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    return {
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2,
    };
  }, []);

  const resetView = useCallback(() => {
    setTransform(INITIAL_PAN_ZOOM_STATE);
  }, []);

  const stepZoom = useCallback(
    (factor: number) => {
      const center = getViewportCenter();
      setTransform((prev) =>
        zoomAtPoint(prev, prev.scale * factor, center, center, DEFAULT_PAN_ZOOM_LIMITS),
      );
    },
    [getViewportCenter],
  );

  // Keyboard shortcuts: Esc to close, +/- to zoom, 0 to reset
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
      } else if (e.key === '+' || e.key === '=') {
        e.preventDefault();
        stepZoom(1.25);
      } else if (e.key === '-' || e.key === '_') {
        e.preventDefault();
        stepZoom(0.8);
      } else if (e.key === '0') {
        e.preventDefault();
        resetView();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, stepZoom, resetView]);

  // Non-passive wheel listener on interactive stage for smooth cursor-anchored zooming
  useEffect(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      e.stopPropagation();

      const center = getViewportCenter();
      const focal: Point2D = { x: e.clientX, y: e.clientY };

      setTransform((prev) => {
        const nextScale = computeWheelZoomScale(
          prev.scale,
          e.deltaY,
          DEFAULT_PAN_ZOOM_LIMITS,
        );
        return zoomAtPoint(prev, nextScale, focal, center, DEFAULT_PAN_ZOOM_LIMITS);
      });
    };

    viewport.addEventListener('wheel', onWheel, { passive: false });
    return () => viewport.removeEventListener('wheel', onWheel);
  }, [getViewportCenter]);

  const handlePointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;

    const viewport = viewportRef.current;
    try {
      viewport?.setPointerCapture(e.pointerId);
    } catch {
      // Ignore synthetic or already-released pointer capture errors
    }

    const point: Point2D = { x: e.clientX, y: e.clientY };
    pointersRef.current.set(e.pointerId, point);

    if (pointersRef.current.size === 1) {
      // Detect quick double-tap on touch devices to toggle zoom / reset
      if (e.pointerType === 'touch') {
        const now = performance.now();
        const prevTap = lastTapRef.current;
        if (
          prevTap &&
          now - prevTap.time < 300 &&
          Math.hypot(point.x - prevTap.point.x, point.y - prevTap.point.y) < 32
        ) {
          lastTapRef.current = null;
          const center = getViewportCenter();
          setTransform((prev) =>
            Math.abs(prev.scale - 1) > 0.1 || Math.hypot(prev.x, prev.y) > 10
              ? INITIAL_PAN_ZOOM_STATE
              : zoomAtPoint(prev, 2, point, center, DEFAULT_PAN_ZOOM_LIMITS),
          );
          return;
        }
        lastTapRef.current = { time: now, point };
      }

      dragStartPointerRef.current = point;
      pinchStartRef.current = null;
      setIsDragging(true);
    } else if (pointersRef.current.size === 2) {
      const [p1, p2] = Array.from(pointersRef.current.values());
      pinchStartRef.current = {
        state: transformRef.current,
        pinch: computePinchSnapshot(p1, p2),
      };
      dragStartPointerRef.current = null;
      lastTapRef.current = null;
      setIsDragging(true);
    }
  };

  const handlePointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!pointersRef.current.has(e.pointerId)) return;

    const point: Point2D = { x: e.clientX, y: e.clientY };
    pointersRef.current.set(e.pointerId, point);

    if (pointersRef.current.size === 2 && pinchStartRef.current) {
      const [p1, p2] = Array.from(pointersRef.current.values());
      const currentPinch = computePinchSnapshot(p1, p2);
      const center = getViewportCenter();
      const { state: startState, pinch: startPinch } = pinchStartRef.current;

      setTransform(
        stepPinchTransform(
          startState,
          startPinch,
          currentPinch,
          center,
          DEFAULT_PAN_ZOOM_LIMITS,
        ),
      );
      return;
    }

    if (pointersRef.current.size === 1 && dragStartPointerRef.current) {
      const dx = point.x - dragStartPointerRef.current.x;
      const dy = point.y - dragStartPointerRef.current.y;
      dragStartPointerRef.current = point;
      setTransform((prev) => applyPanDelta(prev, dx, dy));
    }
  };

  const handlePointerEnd = (e: ReactPointerEvent<HTMLDivElement>) => {
    const viewport = viewportRef.current;
    try {
      if (viewport?.hasPointerCapture(e.pointerId)) {
        viewport.releasePointerCapture(e.pointerId);
      }
    } catch {
      // Ignore synthetic pointer release errors
    }
    pointersRef.current.delete(e.pointerId);

    if (pointersRef.current.size === 2) {
      const [p1, p2] = Array.from(pointersRef.current.values());
      pinchStartRef.current = {
        state: transformRef.current,
        pinch: computePinchSnapshot(p1, p2),
      };
      dragStartPointerRef.current = null;
    } else if (pointersRef.current.size === 1) {
      const [remaining] = Array.from(pointersRef.current.values());
      dragStartPointerRef.current = remaining;
      pinchStartRef.current = null;
    } else {
      dragStartPointerRef.current = null;
      pinchStartRef.current = null;
      setIsDragging(false);
    }
  };

  const handleDoubleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    const center = getViewportCenter();
    const focal: Point2D = { x: e.clientX, y: e.clientY };
    setTransform((prev) =>
      Math.abs(prev.scale - 1) > 0.1 || Math.hypot(prev.x, prev.y) > 10
        ? INITIAL_PAN_ZOOM_STATE
        : zoomAtPoint(prev, 2, focal, center, DEFAULT_PAN_ZOOM_LIMITS),
    );
  };

  const zoomPercent = Math.round(clampScale(transform.scale) * 100);

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      data-testid="mermaid-lightbox"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/65 backdrop-blur-sm sm:p-6"
    >
      <div
        data-testid="mermaid-lightbox-panel"
        className="relative flex h-[100dvh] w-screen flex-col overflow-hidden bg-[#FAFAFC] shadow-2xl sm:h-[min(86vh,800px)] sm:w-[min(92vw,1180px)] sm:rounded-2xl sm:border sm:border-slate-900/[0.12] dark:bg-[#0A0C14] sm:dark:border-white/[0.12]"
      >
        {/* Top bar */}
        <div className="flex shrink-0 items-center justify-between gap-3 border-b border-slate-900/[0.08] bg-white/85 px-4 py-3 backdrop-blur-md dark:border-white/[0.08] dark:bg-[#0E111B]/90">
          <div className="flex min-w-0 items-center gap-2.5">
            <span
              id={titleId}
              className="font-mono text-xs font-medium text-slate-800 dark:text-slate-200"
            >
              mermaid
            </span>
            <span className="hidden text-xs text-slate-400 sm:inline dark:text-slate-500">
              滚轮缩放 · 拖拽平移 · 双击重置
            </span>
          </div>

          <div className="flex shrink-0 items-center gap-1">
            <div className="mr-1 inline-flex items-center rounded-lg border border-slate-900/[0.08] bg-slate-900/[0.03] p-0.5 dark:border-white/[0.08] dark:bg-white/[0.04]">
              <button
                type="button"
                onClick={() => stepZoom(0.8)}
                aria-label="缩小流程图"
                title="缩小 (-)"
                className="inline-flex h-7 w-7 items-center justify-center rounded-md text-slate-600 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/[0.08] dark:hover:text-white"
              >
                <Minus className="h-3.5 w-3.5" />
              </button>
              <span
                data-testid="mermaid-zoom-label"
                className="min-w-[3.25rem] text-center font-mono text-[11px] tabular-nums text-slate-600 dark:text-slate-300"
              >
                {zoomPercent}%
              </span>
              <button
                type="button"
                onClick={() => stepZoom(1.25)}
                aria-label="放大流程图"
                title="放大 (+)"
                className="inline-flex h-7 w-7 items-center justify-center rounded-md text-slate-600 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/[0.08] dark:hover:text-white"
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </div>

            <button
              type="button"
              onClick={resetView}
              aria-label="重置视图"
              title="重置视图 (0)"
              className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-600 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/[0.08] dark:hover:text-white"
            >
              <RotateCcw className="h-3.5 w-3.5" />
            </button>

            <button
              type="button"
              onClick={onClose}
              aria-label="关闭流程图预览"
              title="关闭 (Esc)"
              className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-600 transition-colors hover:bg-slate-900/[0.06] hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/[0.08] dark:hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Interactive Pan / Zoom / Pinch Stage */}
        <div
          ref={viewportRef}
          data-testid="mermaid-stage"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerEnd}
          onPointerCancel={handlePointerEnd}
          onDoubleClick={handleDoubleClick}
          className={`moonset-mermaid-stage relative flex flex-1 select-none items-center justify-center overflow-hidden touch-none ${
            isDragging ? 'cursor-grabbing' : 'cursor-grab'
          }`}
        >
          <div
            ref={svgHostRef}
            data-testid="mermaid-stage-content"
            data-scale={transform.scale.toFixed(3)}
            data-tx={transform.x.toFixed(1)}
            data-ty={transform.y.toFixed(1)}
            style={{
              transform: `translate3d(${transform.x}px, ${transform.y}px, 0) scale(${transform.scale})`,
              transformOrigin: 'center center',
            }}
            className="will-change-transform p-6 sm:p-10"
          />

          {/* Subtle mobile gesture hint at bottom */}
          <div className="pointer-events-none absolute inset-x-0 bottom-4 flex justify-center sm:hidden">
            <span className="rounded-full border border-slate-900/[0.08] bg-white/85 px-3 py-1 text-[11px] text-slate-500 backdrop-blur-md dark:border-white/[0.1] dark:bg-[#111421]/85 dark:text-slate-400">
              单指拖动 · 双指缩放 · 双击重置
            </span>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}

export function MermaidDiagram({ source }: MermaidDiagramProps) {
  const inlineHostRef = useRef<HTMLDivElement>(null);
  const [themeMode, setThemeMode] = useState<MermaidThemeMode>(readDocumentTheme);
  const [svgMarkup, setSvgMarkup] = useState<string>('');
  const [renderError, setRenderError] = useState<string | null>(null);
  const [lightboxOpen, setLightboxOpen] = useState(false);

  // Keep Mermaid SVG palette synchronized when Light/Dark mode toggles
  useEffect(() => {
    const root = document.documentElement;
    const sync = () => setThemeMode(readDocumentTheme());
    sync();

    const observer = new MutationObserver(sync);
    observer.observe(root, { attributes: true, attributeFilter: ['class'] });
    return () => observer.disconnect();
  }, []);

  // Render diagram SVG asynchronously via serialized Mermaid queue
  useEffect(() => {
    let cancelled = false;
    setRenderError(null);

    renderMermaidSvg(source, themeMode)
      .then((svg) => {
        if (!cancelled) {
          setSvgMarkup(svg);
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setRenderError(err instanceof Error ? err.message : 'Mermaid render failed');
          setSvgMarkup('');
        }
      });

    return () => {
      cancelled = true;
    };
  }, [source, themeMode]);

  // Mount sanitized SVG into inline preview container
  useEffect(() => {
    const host = inlineHostRef.current;
    if (!host || !svgMarkup) return;
    mountSanitizedSvg(host, svgMarkup);
  }, [svgMarkup]);

  return (
    <>
      <div
        data-code-lang="mermaid"
        data-mermaid-ready={svgMarkup ? 'true' : 'false'}
        className="group relative my-5 overflow-hidden rounded-xl border border-slate-900/[0.08] bg-[#F4F5FA] dark:border-white/[0.08] dark:bg-[#0C0E16]"
      >
        <div className="flex items-center justify-between border-b border-slate-900/[0.06] px-4 py-2 text-[11px] text-slate-500 dark:border-white/[0.06] dark:text-slate-400">
          <span className="font-mono">mermaid</span>
          <button
            type="button"
            disabled={!svgMarkup}
            onClick={() => setLightboxOpen(true)}
            aria-label="展开查看流程图"
            className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] text-slate-500 transition-colors hover:bg-slate-900/[0.05] hover:text-slate-900 disabled:opacity-40 dark:text-slate-400 dark:hover:bg-white/[0.07] dark:hover:text-white"
          >
            <Maximize2 className="h-3 w-3" />
            <span>展开</span>
          </button>
        </div>

        {renderError ? (
          <pre className="overflow-x-auto p-4 font-mono text-[13px] leading-[1.68] text-slate-700 dark:text-slate-300">
            <code>{source}</code>
          </pre>
        ) : (
          <div
            onClick={() => {
              if (svgMarkup) setLightboxOpen(true);
            }}
            title="点击展开交互预览"
            className="flex min-h-[120px] cursor-zoom-in items-center justify-center overflow-x-auto p-5 sm:p-6"
          >
            {!svgMarkup ? (
              <span className="font-mono text-xs text-slate-400 dark:text-slate-500">
                正在渲染流程图…
              </span>
            ) : (
              <div
                ref={inlineHostRef}
                className="moonset-mermaid-inline flex w-full justify-center"
              />
            )}
          </div>
        )}
      </div>

      {lightboxOpen && svgMarkup && (
        <MermaidLightbox
          svgMarkup={svgMarkup}
          onClose={() => setLightboxOpen(false)}
        />
      )}
    </>
  );
}
