import { useState } from 'react';
import { Phrases, Reveal } from './motion';

interface FlowNode {
  id: string;
  label: string;
  sublabel: string;
  note: string;
}

const INPUT_NODES: FlowNode[] = [
  {
    id: 'changeset',
    label: '.changeset/*.md',
    sublabel: 'Markdown 变更意图',
    note: '每个 PR 附带一份声明受影响包与 SemVer 级别的轻量文稿。',
  },
  {
    id: 'moon',
    label: 'moon.mod / moon.work',
    sublabel: 'MoonBit 工作区',
    note: '通过 unmbt/moon-manifest 无损读写，完整保留注释、字段顺序与格式。',
  },
  {
    id: 'npm',
    label: 'package.json / pnpm',
    sublabel: 'JS / TS 混合生态',
    note: '支持复杂 SemVer 范围保语义更新与隔离 staging 锁文件同步。',
  },
  {
    id: 'cargo',
    label: 'Cargo.toml',
    sublabel: 'Rust / crates.io',
    note: '与 MoonBit / npm 共享统一 ReleaseUnit 图谱，按 bridge 依赖传播版本。',
  },
];

const OUTPUT_NODES: FlowNode[] = [
  {
    id: 'changelog',
    label: 'CHANGELOG.md',
    sublabel: '内置 / Git / GitHub',
    note: '自动附带 Commit、关联 PR 与作者致谢，并支持 JSONL 外部自定义生成器。',
  },
  {
    id: 'mooncakes',
    label: 'mooncakes.io',
    sublabel: 'MoonBit 官方包注册表',
    note: '遵循 moon publish 流程，先 dry-run 预检，支持 moon view 幂等防重发。',
  },
  {
    id: 'registries',
    label: 'npm & crates.io',
    sublabel: '按目标精准分发',
    note: '支持 --registry / --tag 生态作用域路由与多平台产物矩阵校验。',
  },
  {
    id: 'actions',
    label: 'GitHub Actions',
    sublabel: 'PR Bot 与自动 Release',
    note: '模块化 setup / pr-check / pr-comment 与根发布 Action，零服务端维护。',
  },
];

const ROW_Y = [32, 96, 164, 228];
const CORE = { x: 110, y: 130 };

function inputPath(y: number) {
  return `M 0 ${y} C 62 ${y}, 68 ${CORE.y}, ${CORE.x} ${CORE.y}`;
}

function outputPath(y: number) {
  return `M ${CORE.x} ${CORE.y} C 152 ${CORE.y}, 158 ${y}, 220 ${y}`;
}

interface NodeButtonProps {
  node: FlowNode;
  selected: boolean;
  side: 'input' | 'output';
  onFocusNode: (id: string) => void;
}

function NodeButton({ node, selected, side, onFocusNode }: NodeButtonProps) {
  return (
    <button
      type="button"
      onMouseEnter={() => onFocusNode(node.id)}
      onFocus={() => onFocusNode(node.id)}
      onClick={() => onFocusNode(node.id)}
      aria-pressed={selected}
      className={`group flex w-full items-center justify-between rounded-xl border px-4 py-3.5 text-left transition-[border-color,background-color,box-shadow,transform] duration-300 ${
        selected
          ? `border-indigo-500/45 bg-white shadow-[0_10px_30px_-18px_rgba(79,70,229,0.45)] dark:border-indigo-400/45 dark:bg-[#141726] ${
              side === 'input' ? 'lg:translate-x-1' : 'lg:-translate-x-1'
            }`
          : 'border-slate-900/[0.07] bg-white/60 hover:border-slate-900/[0.15] dark:border-white/[0.07] dark:bg-white/[0.02] dark:hover:border-white/[0.15]'
      }`}
    >
      <div>
        <div className="font-mono text-xs font-medium text-slate-950 dark:text-white">{node.label}</div>
        <div className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">{node.sublabel}</div>
      </div>
      <span
        aria-hidden="true"
        className={`relative h-1.5 w-1.5 rounded-full transition-colors duration-300 ${
          selected
            ? side === 'input'
              ? 'bg-indigo-600 dark:bg-indigo-400'
              : 'bg-amber-500 dark:bg-amber-400'
            : 'bg-slate-300 dark:bg-slate-700'
        }`}
      >
        {selected && (
          <span
            className={`absolute inset-0 animate-ping rounded-full ${
              side === 'input' ? 'bg-indigo-500/60' : 'bg-amber-500/60'
            }`}
          />
        )}
      </span>
    </button>
  );
}

/**
 * Vite.dev-inspired luminous input → pure core → output pipeline. Hovering a node
 * lights up its own beam (and dims the rest) so the data flow reads causally.
 */
export function EcosystemFlowSection() {
  const [focusedId, setFocusedId] = useState<string>('moon');

  const activeNode =
    [...INPUT_NODES, ...OUTPUT_NODES].find((n) => n.id === focusedId) ?? INPUT_NODES[1];

  return (
    <section className="relative border-t border-slate-900/[0.06] py-24 sm:py-32 dark:border-white/[0.06]">
      <div className="mx-auto max-w-6xl px-5 sm:px-6">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="text-xs font-medium tracking-wide text-indigo-600 dark:text-indigo-400">
            统一混合生态管线
          </p>
          <h2 className="moonset-cjk-heading font-display mt-3 text-[clamp(1.85rem,3.2vw,2.65rem)] font-bold leading-[1.15] tracking-[-0.025em] text-slate-950 dark:text-white">
            <Phrases text="一套纯计算核，贯通多生态工作区。" />
          </h2>
          <p className="mt-4 text-sm leading-relaxed text-slate-600 sm:text-base dark:text-slate-400">
            无论单模块 MoonBit 库，还是横跨 MoonBit、npm/pnpm 与 Cargo 的混合仓库，所有变更意图皆汇入同一纯规划器，输出确定的发布图谱。
          </p>
        </Reveal>

        <Reveal
          delay={120}
          className="relative mt-14 grid grid-cols-1 items-center gap-6 lg:grid-cols-[1fr_220px_1fr] lg:gap-0"
        >
          <div className="space-y-3">
            {INPUT_NODES.map((node) => (
              <NodeButton
                key={node.id}
                node={node}
                side="input"
                selected={focusedId === node.id}
                onFocusNode={setFocusedId}
              />
            ))}
          </div>

          {/* Center SVG beams + moonset core */}
          <div className="relative flex flex-col items-center justify-center py-2 lg:py-0">
            {/* Mobile: vertical flow connector */}
            <div aria-hidden="true" className="relative mb-3 h-8 w-px overflow-hidden bg-slate-900/[0.1] lg:hidden dark:bg-white/[0.1]">
              <span className="moonset-flow-v absolute inset-x-0 top-0 h-full bg-gradient-to-b from-transparent via-indigo-500 to-transparent" />
            </div>

            <svg
              aria-hidden="true"
              viewBox="0 0 220 260"
              className="hidden h-[260px] w-[220px] lg:block"
              fill="none"
              data-pipeline-focus={focusedId}
            >
              <g className="text-slate-900/[0.1] dark:text-white/[0.1]" stroke="currentColor" strokeWidth="1">
                {ROW_Y.map((y, idx) => (
                  <path
                    key={`gi-${y}`}
                    d={inputPath(y)}
                    className={`pipeline-guide ${INPUT_NODES[idx].id === focusedId ? 'is-active' : ''}`}
                  />
                ))}
                {ROW_Y.map((y, idx) => (
                  <path
                    key={`go-${y}`}
                    d={outputPath(y)}
                    className={`pipeline-guide ${OUTPUT_NODES[idx].id === focusedId ? 'is-active' : ''}`}
                  />
                ))}
              </g>

              <g stroke="url(#moonsetBeam)" strokeWidth="1.75" strokeLinecap="round">
                {ROW_Y.map((y, idx) => {
                  const active = INPUT_NODES[idx].id === focusedId;
                  return (
                    <path
                      key={`bi-${y}`}
                      d={inputPath(y)}
                      className={`${idx % 2 === 0 ? 'pipeline-flow-line' : 'pipeline-flow-line-slow'} ${
                        active ? 'is-active' : ''
                      }`}
                    />
                  );
                })}
                {ROW_Y.map((y, idx) => {
                  const active = OUTPUT_NODES[idx].id === focusedId;
                  return (
                    <path
                      key={`bo-${y}`}
                      d={outputPath(y)}
                      className={`${idx % 2 === 0 ? 'pipeline-flow-line-slow' : 'pipeline-flow-line'} ${
                        active ? 'is-active' : ''
                      }`}
                    />
                  );
                })}
              </g>

              <defs>
                <linearGradient id="moonsetBeam" x1="0" y1="0" x2="220" y2="260" gradientUnits="userSpaceOnUse">
                  <stop offset="0%" stopColor="#6366F1" stopOpacity="0.15" />
                  <stop offset="50%" stopColor="#818CF8" stopOpacity="0.95" />
                  <stop offset="100%" stopColor="#F59E0B" stopOpacity="0.45" />
                </linearGradient>
              </defs>
            </svg>

            {/* Core emblem: pings whenever the focused node changes */}
            <div
              key={focusedId}
              className="moonset-core-ping flex h-24 w-24 flex-col items-center justify-center rounded-2xl border border-indigo-500/30 bg-white shadow-[0_14px_40px_-16px_rgba(79,70,229,0.28)] lg:absolute dark:border-indigo-400/30 dark:bg-[#121524] dark:shadow-[0_14px_44px_-12px_rgba(99,102,241,0.4)]"
            >
              <svg aria-hidden="true" viewBox="0 0 24 24" className="h-7 w-7 text-indigo-600 dark:text-indigo-400" fill="currentColor">
                <path d="M15.2 4.2a8.2 8.2 0 1 0 4.6 14.9A6.8 6.8 0 0 1 15.2 4.2z" />
              </svg>
              <span className="font-mono mt-1.5 text-[11px] font-medium text-slate-700 dark:text-slate-200">pure core</span>
            </div>

            <div aria-hidden="true" className="relative mt-3 h-8 w-px overflow-hidden bg-slate-900/[0.1] lg:hidden dark:bg-white/[0.1]">
              <span className="moonset-flow-v absolute inset-x-0 top-0 h-full bg-gradient-to-b from-transparent via-amber-500 to-transparent [animation-delay:600ms]" />
            </div>
          </div>

          <div className="space-y-3">
            {OUTPUT_NODES.map((node) => (
              <NodeButton
                key={node.id}
                node={node}
                side="output"
                selected={focusedId === node.id}
                onFocusNode={setFocusedId}
              />
            ))}
          </div>
        </Reveal>

        {/* Focused node explanation strip (cross-fades on change) */}
        <div
          aria-live="polite"
          className="mx-auto mt-8 max-w-2xl rounded-xl border border-slate-900/[0.07] bg-white/70 px-5 py-3.5 text-center text-sm text-slate-600 dark:border-white/[0.07] dark:bg-white/[0.025] dark:text-slate-300"
        >
          <span key={activeNode.id} className="moonset-fade-in inline">
            <span className="font-mono font-medium text-slate-950 dark:text-white">{activeNode.label}</span>
            <span aria-hidden="true" className="mx-2.5 text-slate-300 dark:text-slate-700">
              /
            </span>
            <span>{activeNode.note}</span>
          </span>
        </div>
      </div>
    </section>
  );
}
