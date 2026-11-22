import { useEffect, useRef, useState } from 'react';
import {
  computeSectionProgress,
  computeTimelineState,
} from '../lib/scrollTimeline';

interface StoryChapter {
  index: string;
  title: string;
  command: string;
  summary: string;
  detail: string;
  docRoute: string;
}

const CHAPTERS: StoryChapter[] = [
  {
    index: '01.',
    title: '变更即文稿',
    command: 'moonset add',
    summary: '提交改动之时顺手落笔，一份朴素的 Markdown 即可清晰表达影响范围与语义级别。',
    detail:
      '内置跨平台 UTF-8 原生内联 TUI，按 Git 改动自动分组选包，支持固定组与联动组提示，无须离开主屏或担心中文列宽折行。',
    docRoute: '/docs/commands',
  },
  {
    index: '02.',
    title: '规划器至纯',
    command: 'moonset status --verbose',
    summary: '版本推演是不触碰磁盘、Git 与网络的纯函数计算，结果完全确定、可复现、可审计。',
    detail:
      'model、engine、changelog 三个核心包同时通过 native 与 wasm-gc 双目标验证。fixed、linked、bridge 跨生态依赖传播与预发布状态皆在内存中推演完毕。',
    docRoute: '/docs/architecture',
  },
  {
    index: '03.',
    title: '写盘有度，原子恢复',
    command: 'moonset version',
    summary: '全量校验全部配置与 changeset，任一输入无效则整体中止；落盘全程走隔离 staging 与原子替换。',
    detail:
      '通过 unmbt/moon-manifest 无损编辑 moon.mod，保留注释与格式；同步更新 npm/Cargo 依赖范围并写入 .moonset/version-journal.json，中断后可安全恢复。',
    docRoute: '/docs/data-model',
  },
  {
    index: '04.',
    title: '零运维双 Job 隔离 PR Bot',
    command: 'unmbt/moonset/pr-check@v1',
    summary: '无需自建服务端或托管 GitHub App，1 分钟接入 Fork PR 安全的自动检查与评论更新。',
    detail:
      'check Job 以只读权限运行可信静态分析，严禁执行 PR 分支代码；comment Job 仅消费经转义截断的 Markdown 产物，兼顾易用性与供应链安全红线。',
    docRoute: '/docs/automation',
  },
  {
    index: '05.',
    title: '多生态拓扑发布与独立打标',
    command: 'moonset publish --yes',
    summary: '发布与 version 严格解耦，严格依照构建/发布分离 DAG 推送至 Mooncakes、npm 与 crates.io。',
    detail:
      '逐目标记录 .moonset/publish-state.json 与幂等校验，网络中断后再次运行自动跳过已发布单元；tag 与 GitHub Releases 可独立重试。',
    docRoute: '/docs/mixed-workspaces',
  },
];

interface ScrollStorySectionProps {
  onNavigate: (route: string) => void;
}

function StageArtifact({ activeIndex }: { activeIndex: number }) {
  return (
    <div className="relative overflow-hidden rounded-2xl border border-slate-900/[0.08] bg-white/85 p-6 backdrop-blur-sm transition-colors sm:p-8 dark:border-white/[0.09] dark:bg-[#10121C]/90">
      {/* Subtle top metadata line */}
      <div className="mb-6 flex items-center justify-between border-b border-slate-900/[0.07] pb-4 text-xs text-slate-500 dark:border-white/[0.07] dark:text-slate-400">
        <span className="font-mono">{CHAPTERS[activeIndex].command}</span>
        <span className="font-mono tabular-nums">
          {String(activeIndex + 1).padStart(2, '0')} / {String(CHAPTERS.length).padStart(2, '0')}
        </span>
      </div>

      {/* Stage 0: Changeset markdown */}
      {activeIndex === 0 && (
        <div className="space-y-4">
          <div className="font-mono text-xs text-slate-500 dark:text-slate-400">
            .changeset/quiet-storks-teach.md
          </div>
          <pre className="overflow-x-auto rounded-xl border border-slate-900/[0.07] bg-slate-50/90 p-5 font-mono text-[13px] leading-relaxed text-slate-800 dark:border-white/[0.07] dark:bg-[#0A0C13] dark:text-slate-200">
{`---
"unmbt/acme/core": minor
"npm:@acme/sdk": patch
---

新增流式解析器 API，并同步更新 TypeScript SDK 绑定。

- 支持按行增量解码与背压控制
- 修复 Windows CRLF 换行列宽计算`}
          </pre>
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
            <span>自动生成可读文件名 · 避让冲突</span>
            <span className="font-mono">UTF-8 Front Matter</span>
          </div>
        </div>
      )}

      {/* Stage 1: Pure planner table */}
      {activeIndex === 1 && (
        <div className="space-y-5">
          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-slate-400">
            <span>Release Plan · schemaVersion 1</span>
            <span className="font-mono text-indigo-600 dark:text-indigo-400">
              stage: analysis · 0 writes
            </span>
          </div>
          <div className="overflow-hidden rounded-xl border border-slate-900/[0.07] dark:border-white/[0.07]">
            <table className="w-full text-left font-mono text-xs tabular-nums">
              <thead className="bg-slate-50 text-slate-500 dark:bg-white/[0.03] dark:text-slate-400">
                <tr>
                  <th className="px-3.5 py-2.5 font-medium">UnitId</th>
                  <th className="px-3.5 py-2.5 font-medium">Next</th>
                  <th className="px-3.5 py-2.5 font-medium">Propagation</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-900/[0.06] text-slate-800 dark:divide-white/[0.06] dark:text-slate-200">
                <tr>
                  <td className="px-3.5 py-2.5">unmbt/acme/core</td>
                  <td className="px-3.5 py-2.5 text-indigo-600 dark:text-indigo-400">0.3.0</td>
                  <td className="px-3.5 py-2.5 text-slate-500 dark:text-slate-400">direct minor</td>
                </tr>
                <tr>
                  <td className="px-3.5 py-2.5">unmbt/acme/cli</td>
                  <td className="px-3.5 py-2.5 text-indigo-600 dark:text-indigo-400">0.3.0</td>
                  <td className="px-3.5 py-2.5 text-slate-500 dark:text-slate-400">fixed group</td>
                </tr>
                <tr>
                  <td className="px-3.5 py-2.5">npm:@acme/sdk</td>
                  <td className="px-3.5 py-2.5 text-amber-600 dark:text-amber-400">0.2.1</td>
                  <td className="px-3.5 py-2.5 text-slate-500 dark:text-slate-400">bridge dep</td>
                </tr>
                <tr>
                  <td className="px-3.5 py-2.5">cargo:acme-ffi</td>
                  <td className="px-3.5 py-2.5 text-amber-600 dark:text-amber-400">0.2.1</td>
                  <td className="px-3.5 py-2.5 text-slate-500 dark:text-slate-400">internal range</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div className="text-xs text-slate-500 dark:text-slate-400">
            纯核心包兼容 <code className="font-mono">native</code> 与 <code className="font-mono">wasm-gc</code> 双目标，无需 mock 文件系统即可全量单测。
          </div>
        </div>
      )}

      {/* Stage 2: Atomic diff & journal */}
      {activeIndex === 2 && (
        <div className="space-y-4">
          <div className="font-mono text-xs text-slate-500 dark:text-slate-400">
            core/moon.mod · lossless AST patch
          </div>
          <pre className="overflow-x-auto rounded-xl border border-slate-900/[0.07] bg-slate-50/90 p-5 font-mono text-[13px] leading-relaxed dark:border-white/[0.07] dark:bg-[#0A0C13]">
            <span className="block text-slate-500 dark:text-slate-400">{'name = "unmbt/acme/core"'}</span>
            <span className="block text-rose-600 dark:text-rose-400">{'- version = "0.2.0"'}</span>
            <span className="block text-emerald-700 dark:text-emerald-400">{'+ version = "0.3.0"'}</span>
            <span className="block text-slate-500 dark:text-slate-400">{'// existing comments & field ordering preserved'}</span>
          </pre>
          <div className="grid grid-cols-2 gap-3 pt-1 font-mono text-xs">
            <div className="rounded-lg border border-slate-900/[0.07] bg-slate-50/70 px-3.5 py-2.5 dark:border-white/[0.07] dark:bg-white/[0.02]">
              <div className="text-slate-400">Journal</div>
              <div className="mt-1 text-slate-800 dark:text-slate-200">version-journal.json</div>
            </div>
            <div className="rounded-lg border border-slate-900/[0.07] bg-slate-50/70 px-3.5 py-2.5 dark:border-white/[0.07] dark:bg-white/[0.02]">
              <div className="text-slate-400">State</div>
              <div className="mt-1 text-slate-800 dark:text-slate-200">release-state.json</div>
            </div>
          </div>
        </div>
      )}

      {/* Stage 3: Dual-Job PR Bot */}
      {activeIndex === 3 && (
        <div className="space-y-4">
          <div className="text-xs text-slate-500 dark:text-slate-400">
            pull_request_target · 双 Job 最小权限隔离架构
          </div>
          <div className="space-y-3">
            <div className="rounded-xl border border-slate-900/[0.08] bg-slate-50/80 p-4 dark:border-white/[0.08] dark:bg-[#0A0C13]">
              <div className="flex items-center justify-between text-xs font-medium text-slate-900 dark:text-slate-100">
                <span>Job 1 · pr-check</span>
                <span className="font-mono text-slate-500 dark:text-slate-400">contents: read</span>
              </div>
              <p className="mt-1.5 text-xs leading-relaxed text-slate-600 dark:text-slate-400">
                <code className="font-mono">persist-credentials: false</code> · 仅以可信预编译二进制执行只读分析，不运行任何 PR 分支脚本。
              </p>
            </div>
            <div className="flex justify-center font-mono text-xs text-slate-400">
              ↓ escaped markdown &amp; state outputs
            </div>
            <div className="rounded-xl border border-indigo-500/25 bg-indigo-500/[0.04] p-4 dark:border-indigo-400/25 dark:bg-indigo-400/[0.06]">
              <div className="flex items-center justify-between text-xs font-medium text-slate-900 dark:text-slate-100">
                <span>Job 2 · pr-comment</span>
                <span className="font-mono text-indigo-600 dark:text-indigo-400">pull-requests: write</span>
              </div>
              <p className="mt-1.5 text-xs leading-relaxed text-slate-600 dark:text-slate-400">
                幂等更新单条 PR 评论，自动附带版本变更预览表与一键新增 changeset 链接。
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Stage 4: Multi-ecosystem publish DAG */}
      {activeIndex === 4 && (
        <div className="space-y-4">
          <div className="text-xs text-slate-500 dark:text-slate-400">
            Execution Graph · Build / Publish 分离拓扑
          </div>
          <div className="space-y-2.5 font-mono text-xs">
            {[
              { step: '01', unit: 'unmbt/acme/core@0.3.0', target: 'mooncakes.io', status: 'idempotent ok' },
              { step: '02', unit: 'unmbt/acme/cli@0.3.0', target: 'mooncakes.io', status: 'depends on core' },
              { step: '03', unit: 'npm:@acme/sdk@0.2.1', target: 'npmjs.org', status: 'dist-tag latest' },
              { step: '04', unit: 'cargo:acme-ffi@0.2.1', target: 'crates.io', status: 'verified pack' },
            ].map((row) => (
              <div
                key={row.unit}
                className="flex items-center justify-between gap-3 rounded-lg border border-slate-900/[0.07] bg-slate-50/75 px-3.5 py-2.5 tabular-nums dark:border-white/[0.07] dark:bg-[#0A0C13]"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="text-indigo-600 dark:text-indigo-400">{row.step}</span>
                  <span className="truncate text-slate-900 dark:text-slate-100">{row.unit}</span>
                </div>
                <span className="shrink-0 text-slate-500 dark:text-slate-400">{row.target}</span>
              </div>
            ))}
          </div>
          <div className="text-xs text-slate-500 dark:text-slate-400">
            支持多平台产物矩阵校验与断点续跑，发布凭据仅由环境变量或 CI OIDC 注入。
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * Artcraft-inspired scroll-driven editorial narrative with sticky left artifact stage
 * and continuous vertical progress timeline & illuminating text on the right.
 */
export function ScrollStorySection({ onNavigate }: ScrollStorySectionProps) {
  const sectionRef = useRef<HTMLElement>(null);
  const itemRefs = useRef<Array<HTMLElement | null>>([]);
  const [scrollProgress, setScrollProgress] = useState(0);
  const [activeIndex, setActiveIndex] = useState(0);
  const [weights, setWeights] = useState<number[]>([1, 0.35, 0.2, 0.2, 0.2]);

  useEffect(() => {
    let rafId = 0;

    const handleScroll = () => {
      rafId = 0;
      const section = sectionRef.current;
      if (!section) return;
      const rect = section.getBoundingClientRect();
      const progress = computeSectionProgress(
        rect.top,
        rect.height,
        window.innerHeight,
      );
      const state = computeTimelineState(progress, CHAPTERS.length);
      setScrollProgress(state.progress);
      setActiveIndex(state.activeIndex);
      setWeights(state.weights);
    };

    const onScroll = () => {
      if (!rafId) {
        rafId = window.requestAnimationFrame(handleScroll);
      }
    };

    handleScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
      if (rafId) window.cancelAnimationFrame(rafId);
    };
  }, []);

  const jumpToChapter = (idx: number) => {
    setActiveIndex(idx);
    const target = itemRefs.current[idx];
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  };

  return (
    <section
      ref={sectionRef}
      data-testid="scroll-story-section"
      data-active-chapter={activeIndex}
      className="relative border-t border-slate-900/[0.06] py-24 sm:py-32 dark:border-white/[0.06]"
    >
      <div className="mx-auto max-w-6xl px-6">
        {/* Section opening */}
        <div className="mb-16 max-w-2xl">
          <p className="text-xs font-medium tracking-wide text-indigo-600 dark:text-indigo-400">
            从一次提交到全生态发布
          </p>
          <h2
            className="font-display mt-3 text-[clamp(1.85rem,3.4vw,2.75rem)] font-bold leading-[1.15] tracking-[-0.025em] text-slate-950 dark:text-white"
            style={{ textWrap: 'balance' }}
          >
            把发版的复杂性，收束为五段清澈的节律。
          </h2>
        </div>

        {/* 2-column sticky stage + scroll-illuminated timeline */}
        <div className="grid grid-cols-1 items-start gap-12 lg:grid-cols-[1.05fr_0.95fr] lg:gap-16">
          {/* Left sticky visual stage */}
          <div className="lg:sticky lg:top-28">
            <StageArtifact activeIndex={activeIndex} />
          </div>

          {/* Right scroll-driven timeline rail */}
          <div className="relative pl-8 sm:pl-10">
            {/* Base vertical rail (x: 7px..9px, center: 8.0px) */}
            <div
              aria-hidden="true"
              data-testid="timeline-base-rail"
              className="absolute top-3 bottom-3 left-[7px] w-[2px] rounded-full bg-slate-900/[0.08] dark:bg-white/[0.08]"
            />

            {/* Continuous scroll-linked indigo beam (x: 7px..9px, center: 8.0px) */}
            <div
              aria-hidden="true"
              data-testid="timeline-progress-beam"
              className="absolute top-3 left-[7px] w-[2px] origin-top rounded-full bg-gradient-to-b from-indigo-500 via-indigo-400 to-amber-400/80 transition-transform duration-150 will-change-transform"
              style={{
                height: 'calc(100% - 1.5rem)',
                transform: `scaleY(${Math.max(0.06, scrollProgress).toFixed(3)})`,
              }}
            />

            <ol className="space-y-12 sm:space-y-20">
              {CHAPTERS.map((chapter, idx) => {
                const isActive = idx === activeIndex;
                const weight = weights[idx] ?? 0.35;
                // Keep text always readable (>= 0.42 opacity) while illuminating smoothly on scroll
                const textOpacity = 0.42 + weight * 0.58;
                const shiftY = (1 - weight) * 6;

                return (
                  <li
                    key={chapter.index}
                    ref={(el) => {
                      itemRefs.current[idx] = el;
                    }}
                    className="relative py-4 lg:py-8"
                  >
                    {/* Timeline node (14px circle, x: 1px..15px, center: 8.0px) */}
                    <button
                      type="button"
                      onClick={() => jumpToChapter(idx)}
                      aria-label={`跳转到第 ${idx + 1} 步：${chapter.title}`}
                      data-testid={`timeline-dot-${idx}`}
                      className={`absolute top-6 -left-[31px] flex h-3.5 w-3.5 items-center justify-center rounded-full border transition-all duration-200 sm:-left-[39px] ${
                        isActive
                          ? 'scale-110 border-indigo-600 bg-indigo-600 dark:border-indigo-400 dark:bg-indigo-400'
                          : 'border-slate-300 bg-[#FAFAFC] hover:border-indigo-500 dark:border-slate-700 dark:bg-[#08090E]'
                      }`}
                    />

                    <div
                      className="transition-transform duration-200 will-change-transform"
                      style={{
                        opacity: textOpacity,
                        transform: `translate3d(0, ${shiftY.toFixed(1)}px, 0)`,
                      }}
                    >
                      <button
                        type="button"
                        onClick={() => jumpToChapter(idx)}
                        className="group text-left focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-indigo-500"
                      >
                        <div className="flex items-baseline gap-3">
                          <span className="font-mono text-xs font-medium text-indigo-600 tabular-nums dark:text-indigo-400">
                            {chapter.index}
                          </span>
                          <h3 className="font-display text-xl font-semibold tracking-tight text-slate-950 transition-colors group-hover:text-indigo-600 sm:text-2xl dark:text-white dark:group-hover:text-indigo-300">
                            {chapter.title}
                          </h3>
                        </div>
                      </button>

                      <p className="mt-3 text-[0.98rem] leading-relaxed text-slate-700 dark:text-slate-300">
                        {chapter.summary}
                      </p>

                      <p className="mt-2.5 text-sm leading-relaxed text-slate-500 dark:text-slate-400">
                        {chapter.detail}
                      </p>

                      <div className="mt-4 flex items-center gap-4 text-xs">
                        <code className="font-mono text-slate-700 dark:text-slate-300">
                          {chapter.command}
                        </code>
                        <span aria-hidden="true" className="text-slate-300 dark:text-slate-700">
                          ·
                        </span>
                        <a
                          href={`#${chapter.docRoute}`}
                          onClick={(e) => {
                            e.preventDefault();
                            onNavigate(chapter.docRoute);
                          }}
                          className="font-medium text-indigo-600 underline decoration-indigo-500/35 underline-offset-4 transition-colors hover:decoration-indigo-500 dark:text-indigo-400"
                        >
                          查看规范
                        </a>
                      </div>
                    </div>
                  </li>
                );
              })}
            </ol>
          </div>
        </div>
      </div>
    </section>
  );
}
