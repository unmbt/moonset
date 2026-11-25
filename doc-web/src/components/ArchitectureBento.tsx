import { ArrowRight, ArrowUpRight } from 'lucide-react';
import { formatThousands } from '../lib/interaction';
import { Phrases, Reveal, SpotlightCard, useCountUp, useInView } from './motion';

interface ArchitectureBentoProps {
  onNavigate: (route: string) => void;
}

const CARD_BASE =
  'flex flex-col justify-between rounded-2xl border border-slate-900/[0.08] bg-white/75 p-7 dark:border-white/[0.08] dark:bg-[#10121C]/75';

function BenchmarkStats() {
  const [ref, inView] = useInView<HTMLDivElement>({ threshold: 0.4 });
  const ms = useCountUp(1495, inView, 1600);
  const targets = useCountUp(2, inView, 900);

  return (
    <div
      ref={ref}
      className="mt-8 grid grid-cols-3 gap-6 border-t border-slate-900/[0.07] pt-6 font-mono tabular-nums dark:border-white/[0.07]"
    >
      <div>
        <div className="text-2xl font-semibold text-slate-950 dark:text-white">
          {formatThousands(ms)}
          <span className="ml-1 text-base text-slate-500 dark:text-slate-400">ms</span>
        </div>
        <div className="mt-1 font-sans text-xs text-slate-500 dark:text-slate-400">100 包 / 1000 changeset</div>
      </div>
      <div>
        <div className="text-2xl font-semibold text-slate-950 dark:text-white">
          {targets}
          <span className="ml-1 text-base text-slate-500 dark:text-slate-400">Targets</span>
        </div>
        <div className="mt-1 font-sans text-xs text-slate-500 dark:text-slate-400">native 与 wasm-gc 纯核</div>
      </div>
      <div>
        <div className="text-2xl font-semibold text-slate-950 dark:text-white">
          0<span className="ml-1 text-base text-slate-500 dark:text-slate-400">Shell</span>
        </div>
        <div className="mt-1 font-sans text-xs text-slate-500 dark:text-slate-400">参数数组隔离，无拼接注入</div>
      </div>
    </div>
  );
}

function CardLink({ label, route, onNavigate }: { label: string; route: string; onNavigate: (route: string) => void }) {
  return (
    <a
      href={`#${route}`}
      onClick={(e) => {
        e.preventDefault();
        onNavigate(route);
      }}
      className="group/link inline-flex items-center gap-1 text-xs font-medium text-indigo-600 dark:text-indigo-400"
    >
      {label}
      <ArrowRight className="h-3.5 w-3.5 transition-transform duration-200 group-hover/link:translate-x-0.5" />
    </a>
  );
}

export function ArchitectureBento({ onNavigate }: ArchitectureBentoProps) {
  return (
    <section className="relative border-t border-slate-900/[0.06] py-24 sm:py-32 dark:border-white/[0.06]">
      <div className="mx-auto max-w-6xl px-5 sm:px-6">
        <Reveal className="mb-14 flex flex-col justify-between gap-6 sm:flex-row sm:items-end">
          <div className="max-w-xl">
            <p className="text-xs font-medium tracking-wide text-indigo-600 dark:text-indigo-400">
              规格驱动 · 工程证据
            </p>
            <h2 className="moonset-cjk-heading font-display mt-3 text-[clamp(1.85rem,3.2vw,2.65rem)] font-bold leading-[1.15] tracking-[-0.025em] text-slate-950 dark:text-white">
              <Phrases text="先有契约，后有代码。" />
            </h2>
          </div>

          <a
            href="#/docs/overview"
            onClick={(e) => {
              e.preventDefault();
              onNavigate('/docs/overview');
            }}
            className="group inline-flex shrink-0 items-center gap-1.5 text-sm font-medium text-slate-700 underline decoration-slate-900/20 underline-offset-4 transition-colors hover:text-indigo-600 hover:decoration-indigo-500 dark:text-slate-300 dark:decoration-white/20 dark:hover:text-indigo-300"
          >
            查阅完整规格文档
            <ArrowUpRight className="h-4 w-4 transition-transform duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
          </a>
        </Reveal>

        {/* Asymmetric bento grid — cursor spotlight, staggered reveal */}
        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          <SpotlightCard className={`${CARD_BASE} md:col-span-2`}>
            <div>
              <div className="text-xs text-slate-500 dark:text-slate-400">01. 规模化性能基准 · NFR-005</div>
              <h3 className="font-display mt-2.5 text-xl font-semibold tracking-tight text-slate-950 dark:text-white">
                大规模 Workspace 毫秒级只读规划
              </h3>
              <p className="mt-2.5 max-w-xl text-sm leading-relaxed text-slate-600 dark:text-slate-400">
                批量 Git 快照读取与纯内存图计算，在 100 个包、1,000 份待处理 changeset 的压测工作区下，完整执行{' '}
                <code className="font-mono text-xs text-slate-800 dark:text-slate-200">status --since</code>{' '}
                实测仅需 1495 ms。
              </p>
            </div>
            <BenchmarkStats />
          </SpotlightCard>

          <SpotlightCard className={CARD_BASE} delay={80}>
            <div>
              <div className="text-xs text-slate-500 dark:text-slate-400">02. 扩展边界 · Phase 5</div>
              <h3 className="font-display mt-2.5 text-xl font-semibold tracking-tight text-slate-950 dark:text-white">
                MoonBit API 与 JSONL 插件
              </h3>
              <p className="mt-2.5 text-sm leading-relaxed text-slate-600 dark:text-slate-400">
                对外暴露稳定的{' '}
                <code className="font-mono text-xs text-slate-800 dark:text-slate-200">unmbt/moonset/api</code>{' '}
                与版本化 JSON 信封，任何语言皆可通过 JSONL 协议编写自定义 Changelog 生成器或发布适配器。
              </p>
            </div>
            <div className="mt-6 border-t border-slate-900/[0.07] pt-4 dark:border-white/[0.07]">
              <CardLink label="阅读编程 API 契约" route="/docs/api" onNavigate={onNavigate} />
            </div>
          </SpotlightCard>

          <SpotlightCard className={CARD_BASE} delay={60}>
            <div>
              <div className="text-xs text-slate-500 dark:text-slate-400">03. 预发布与快照 · ADR-009</div>
              <h3 className="font-display mt-2.5 text-xl font-semibold tracking-tight text-slate-950 dark:text-white">
                极简预发布与快照版本
              </h3>
              <p className="mt-2.5 text-sm leading-relaxed text-slate-600 dark:text-slate-400">
                遵循 Changesets v3 模型：通过{' '}
                <code className="font-mono text-xs text-slate-800 dark:text-slate-200">pre enter alpha</code>{' '}
                进入预发布，或使用{' '}
                <code className="font-mono text-xs text-slate-800 dark:text-slate-200">version --snapshot</code>{' '}
                在不消耗 changeset 的前提下生成 PR 验证版本。
              </p>
            </div>
            <div className="mt-6 border-t border-slate-900/[0.07] pt-4 dark:border-white/[0.07]">
              <CardLink
                label="查看 ADR-009"
                route="/docs/decisions/009-changesets-v3-pre-and-snapshot-model"
                onNavigate={onNavigate}
              />
            </div>
          </SpotlightCard>

          <SpotlightCard className={`${CARD_BASE} md:col-span-2`} delay={140}>
            <div>
              <div className="text-xs text-slate-500 dark:text-slate-400">04. 模块化设计 · 清晰依赖边界</div>
              <h3 className="font-display mt-2.5 text-xl font-semibold tracking-tight text-slate-950 dark:text-white">
                纯计算核与宿主 I/O 严格分层
              </h3>
              <p className="mt-2.5 text-sm leading-relaxed text-slate-600 dark:text-slate-400">
                所有异步文件与子进程调用均收口于 <code className="font-mono text-xs">moonbitlang/core/async</code> 与{' '}
                <code className="font-mono text-xs">executor::ExecutionHost</code>；GitHub Actions 薄壳不重复任何规划逻辑。
              </p>
            </div>

            <div className="mt-6 rounded-xl border border-slate-900/[0.06] bg-slate-50/85 p-4 font-mono text-xs dark:border-white/[0.06] dark:bg-[#0A0C13]">
              <div className="flex flex-wrap items-center gap-x-2.5 gap-y-2 text-slate-800 dark:text-slate-200">
                <span className="text-slate-500 dark:text-slate-400">cmd/moonset</span>
                <span aria-hidden="true" className="text-slate-400 dark:text-slate-600">→</span>
                <span>cli</span>
                <span aria-hidden="true" className="text-slate-400 dark:text-slate-600">→</span>
                <span className="text-indigo-600 dark:text-indigo-400">workspace · executor · adapters</span>
                <span aria-hidden="true" className="text-slate-400 dark:text-slate-600">→</span>
                <span>engine · changelog · model</span>
              </div>
              <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-slate-900/[0.06] pt-2.5 text-[11px] text-slate-500 dark:border-white/[0.06] dark:text-slate-400">
                <span>对外门面 · api / moonset.mbt</span>
                <span>纯核零 I/O · native + wasm-gc</span>
              </div>
            </div>
          </SpotlightCard>
        </div>

        {/* Closing calm CTA strip */}
        <Reveal className="mt-20 flex flex-col items-start justify-between gap-6 border-t border-slate-900/[0.08] pt-14 sm:flex-row sm:items-center dark:border-white/[0.08]">
          <div>
            <h3 className="moonset-cjk-heading font-display text-2xl font-bold tracking-tight text-slate-950 dark:text-white">
              <Phrases text="月落乌啼，版本不乱；潮生潮落，发布有章。" />
            </h3>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-400">
              从本地五步工作流到 GitHub Actions 自动化发布，完整契约皆可在线查阅。
            </p>
          </div>

          <div className="flex shrink-0 items-center gap-5">
            <a
              href="#/changelog"
              onClick={(e) => {
                e.preventDefault();
                onNavigate('/changelog');
              }}
              className="text-sm font-medium whitespace-nowrap text-slate-600 transition-colors hover:text-slate-950 dark:text-slate-400 dark:hover:text-white"
            >
              查看更新日志
            </a>
            <a
              href="#/docs/quickstart"
              onClick={(e) => {
                e.preventDefault();
                onNavigate('/docs/quickstart');
              }}
              className="group inline-flex h-10 shrink-0 items-center gap-1.5 rounded-xl bg-slate-950 px-5 text-sm font-medium whitespace-nowrap text-white transition-[background-color,transform] duration-200 hover:-translate-y-px hover:bg-slate-800 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
            >
              进入文档中心
              <ArrowRight className="h-4 w-4 transition-transform duration-200 group-hover:translate-x-0.5" />
            </a>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
