import { useState } from 'react';

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

/**
 * Vite.dev-inspired restrained luminous input-to-output pipeline visualization.
 */
export function EcosystemFlowSection() {
  const [focusedId, setFocusedId] = useState<string>('moon');

  const activeNode =
    [...INPUT_NODES, ...OUTPUT_NODES].find((n) => n.id === focusedId) ??
    INPUT_NODES[1];

  return (
    <section className="relative border-t border-slate-900/[0.06] py-24 sm:py-32 dark:border-white/[0.06]">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-xs font-medium tracking-wide text-indigo-600 dark:text-indigo-400">
            统一混合生态管线
          </p>
          <h2
            className="font-display mt-3 text-[clamp(1.85rem,3.2vw,2.65rem)] font-bold leading-[1.15] tracking-[-0.025em] text-slate-950 dark:text-white"
            style={{ textWrap: 'balance' }}
          >
            一套纯计算核，贯通多生态工作区。
          </h2>
          <p className="mt-4 text-sm leading-relaxed text-slate-600 sm:text-base dark:text-slate-400">
            无论单模块 MoonBit 库，还是横跨 MoonBit、npm/pnpm 与 Cargo 的混合仓库，所有变更意图皆汇入同一纯规划器，输出确定的发布图谱。
          </p>
        </div>

        {/* Pipeline diagram */}
        <div className="relative mt-14 grid grid-cols-1 items-center gap-6 lg:grid-cols-[1fr_220px_1fr] lg:gap-0">
          {/* Left column: Inputs */}
          <div className="space-y-3">
            {INPUT_NODES.map((node) => {
              const selected = focusedId === node.id;
              return (
                <button
                  key={node.id}
                  type="button"
                  onMouseEnter={() => setFocusedId(node.id)}
                  onFocus={() => setFocusedId(node.id)}
                  onClick={() => setFocusedId(node.id)}
                  className={`flex w-full items-center justify-between rounded-xl border px-4 py-3.5 text-left transition-all duration-150 ${
                    selected
                      ? 'border-indigo-500/45 bg-white shadow-xs dark:border-indigo-400/45 dark:bg-[#141726]'
                      : 'border-slate-900/[0.07] bg-white/60 hover:border-slate-900/[0.15] dark:border-white/[0.07] dark:bg-white/[0.02] dark:hover:border-white/[0.15]'
                  }`}
                >
                  <div>
                    <div className="font-mono text-xs font-medium text-slate-950 dark:text-white">
                      {node.label}
                    </div>
                    <div className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                      {node.sublabel}
                    </div>
                  </div>
                  <span
                    aria-hidden="true"
                    className={`h-1.5 w-1.5 rounded-full transition-colors ${
                      selected
                        ? 'bg-indigo-600 dark:bg-indigo-400'
                        : 'bg-slate-300 dark:bg-slate-700'
                    }`}
                  />
                </button>
              );
            })}
          </div>

          {/* Center SVG beams + Moonset core */}
          <div className="relative flex flex-col items-center justify-center py-6 lg:py-0">
            <svg
              aria-hidden="true"
              viewBox="0 0 220 260"
              className="hidden h-[260px] w-[220px] lg:block"
              fill="none"
            >
              {/* Static hairline guide paths */}
              <g className="text-slate-900/[0.1] dark:text-white/[0.1]" stroke="currentColor" strokeWidth="1">
                <path d="M 0 32 C 62 32, 68 130, 110 130" />
                <path d="M 0 96 C 62 96, 68 130, 110 130" />
                <path d="M 0 164 C 62 164, 68 130, 110 130" />
                <path d="M 0 228 C 62 228, 68 130, 110 130" />
                <path d="M 110 130 C 152 130, 158 32, 220 32" />
                <path d="M 110 130 C 152 130, 158 96, 220 96" />
                <path d="M 110 130 C 152 130, 158 164, 220 164" />
                <path d="M 110 130 C 152 130, 158 228, 220 228" />
              </g>

              {/* Animated light pulses */}
              <g stroke="url(#moonsetBeam)" strokeWidth="1.75" strokeLinecap="round">
                <path d="M 0 32 C 62 32, 68 130, 110 130" className="pipeline-flow-line" />
                <path d="M 0 96 C 62 96, 68 130, 110 130" className="pipeline-flow-line-slow" />
                <path d="M 0 164 C 62 164, 68 130, 110 130" className="pipeline-flow-line" />
                <path d="M 110 130 C 152 130, 158 32, 220 32" className="pipeline-flow-line-slow" />
                <path d="M 110 130 C 152 130, 158 96, 220 96" className="pipeline-flow-line" />
                <path d="M 110 130 C 152 130, 158 228, 220 228" className="pipeline-flow-line-slow" />
              </g>

              <defs>
                <linearGradient id="moonsetBeam" x1="0" y1="0" x2="220" y2="260" gradientUnits="userSpaceOnUse">
                  <stop offset="0%" stopColor="#6366F1" stopOpacity="0.1" />
                  <stop offset="50%" stopColor="#818CF8" stopOpacity="0.9" />
                  <stop offset="100%" stopColor="#F59E0B" stopOpacity="0.3" />
                </linearGradient>
              </defs>
            </svg>

            {/* Core emblem floating centered */}
            <div className="flex h-24 w-24 flex-col items-center justify-center rounded-2xl border border-indigo-500/30 bg-white shadow-[0_14px_40px_-16px_rgba(79,70,229,0.28)] lg:absolute dark:border-indigo-400/30 dark:bg-[#121524] dark:shadow-[0_14px_44px_-12px_rgba(99,102,241,0.4)]">
              <svg
                aria-hidden="true"
                viewBox="0 0 24 24"
                className="h-7 w-7 text-indigo-600 dark:text-indigo-400"
                fill="currentColor"
              >
                <path d="M15.2 4.2a8.2 8.2 0 1 0 4.6 14.9A6.8 6.8 0 0 1 15.2 4.2z" />
              </svg>
              <span className="font-mono mt-1.5 text-[11px] font-medium text-slate-700 dark:text-slate-200">
                pure core
              </span>
            </div>
          </div>

          {/* Right column: Outputs */}
          <div className="space-y-3">
            {OUTPUT_NODES.map((node) => {
              const selected = focusedId === node.id;
              return (
                <button
                  key={node.id}
                  type="button"
                  onMouseEnter={() => setFocusedId(node.id)}
                  onFocus={() => setFocusedId(node.id)}
                  onClick={() => setFocusedId(node.id)}
                  className={`flex w-full items-center justify-between rounded-xl border px-4 py-3.5 text-left transition-all duration-150 ${
                    selected
                      ? 'border-indigo-500/45 bg-white shadow-xs dark:border-indigo-400/45 dark:bg-[#141726]'
                      : 'border-slate-900/[0.07] bg-white/60 hover:border-slate-900/[0.15] dark:border-white/[0.07] dark:bg-white/[0.02] dark:hover:border-white/[0.15]'
                  }`}
                >
                  <div>
                    <div className="font-mono text-xs font-medium text-slate-950 dark:text-white">
                      {node.label}
                    </div>
                    <div className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                      {node.sublabel}
                    </div>
                  </div>
                  <span
                    aria-hidden="true"
                    className={`h-1.5 w-1.5 rounded-full transition-colors ${
                      selected
                        ? 'bg-amber-500 dark:bg-amber-400'
                        : 'bg-slate-300 dark:bg-slate-700'
                    }`}
                  />
                </button>
              );
            })}
          </div>
        </div>

        {/* Focused node architectural explanation strip */}
        <div className="mx-auto mt-8 max-w-2xl rounded-xl border border-slate-900/[0.07] bg-white/70 px-5 py-3.5 text-center text-sm text-slate-600 dark:border-white/[0.07] dark:bg-white/[0.025] dark:text-slate-300">
          <span className="font-mono font-medium text-slate-950 dark:text-white">
            {activeNode.label}
          </span>
          <span aria-hidden="true" className="mx-2.5 text-slate-300 dark:text-slate-700">
            /
          </span>
          <span>{activeNode.note}</span>
        </div>
      </div>
    </section>
  );
}
