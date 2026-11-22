export type TerminalScenarioId = 'add' | 'status' | 'version' | 'publish';

export interface TerminalStep {
  /** Text chunk written to xterm.js (supports ANSI escape codes) */
  text: string;
  /** Delay in milliseconds before writing this chunk */
  delayMs: number;
  /** Whether to stream character-by-character like human typing */
  typewriter?: boolean;
  /** Milliseconds per character when typewriter is true */
  charDelayMs?: number;
}

export interface TerminalScenario {
  id: TerminalScenarioId;
  label: string;
  command: string;
  caption: string;
  steps: TerminalStep[];
}

// ANSI color helpers (semantic 16-color palette mapped cleanly to both Light & Dark xterm themes)
const R = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM = '\x1b[2m';
const CYAN = '\x1b[36m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const MAGENTA = '\x1b[35m';
const BLUE = '\x1b[34m';
const RED = '\x1b[31m';

export const TERMINAL_SCENARIOS: TerminalScenario[] = [
  {
    id: 'add',
    label: 'add',
    command: 'moonset add',
    caption: '内联 UTF-8 原生 TUI，按变更分组交互式撰写 changeset',
    steps: [
      { text: `${DIM}~/workspace/acme-moon${R} ${CYAN}$${R} `, delayMs: 100 },
      { text: 'moonset add', delayMs: 140, typewriter: true, charDelayMs: 36 },
      { text: '\r\n', delayMs: 220 },
      { text: `${DIM}┌${R}  ${BOLD}moonset add${R} ${DIM}· workspace: 4 packages (2 changed)${R}\r\n`, delayMs: 100 },
      { text: `${GREEN}◇${R}  Which packages would you like to include?\r\n`, delayMs: 160 },
      { text: `${DIM}│${R}  ${BOLD}changed packages${R}\r\n`, delayMs: 80 },
      { text: `${DIM}│${R}    ${GREEN}◼${R} unmbt/acme/core ${DIM}@0.2.0${R}\r\n`, delayMs: 100 },
      { text: `${DIM}│${R}    ${GREEN}◼${R} npm:@acme/sdk   ${DIM}@0.2.0${R}\r\n`, delayMs: 100 },
      { text: `${DIM}│${R}  ${DIM}unchanged: unmbt/acme/cli @0.2.0${R}\r\n`, delayMs: 70 },
      { text: `${GREEN}◇${R}  Which packages should have a ${CYAN}minor${R} bump?\r\n`, delayMs: 180 },
      { text: `${DIM}│${R}    ${CYAN}●${R} unmbt/acme/core ${DIM}(0.2.0 → ${CYAN}0.3.0${DIM})${R}\r\n`, delayMs: 130 },
      { text: `${DIM}│${R}    ${DIM}○ npm:@acme/sdk (remaining → patch 0.2.1)${R}\r\n`, delayMs: 110 },
      { text: `${GREEN}◇${R}  Please enter a summary for this change\r\n`, delayMs: 150 },
      { text: `${DIM}│${R}  `, delayMs: 80 },
      { text: '新增流式解析器 API，并同步更新 TypeScript SDK 绑定', delayMs: 120, typewriter: true, charDelayMs: 20 },
      { text: '\r\n', delayMs: 200 },
      { text: `${GREEN}✓${R}  ${BOLD}Summary of changesets${R}\r\n`, delayMs: 120 },
      { text: `${DIM}│${R}  ${CYAN}minor${R}  unmbt/acme/core ${DIM}0.2.0 → 0.3.0${R}\r\n`, delayMs: 80 },
      { text: `${DIM}│${R}  ${YELLOW}patch${R}  npm:@acme/sdk   ${DIM}0.2.0 → 0.2.1${R}\r\n`, delayMs: 80 },
      { text: `${DIM}└${R}  Created ${MAGENTA}.changeset/quiet-storks-teach.md${R}\r\n`, delayMs: 100 },
    ],
  },
  {
    id: 'status',
    label: 'status',
    command: 'moonset status --verbose',
    caption: '绝对只读的纯规划器：在毫秒内完成跨生态版本与依赖图推演',
    steps: [
      { text: `${DIM}~/workspace/acme-moon${R} ${CYAN}$${R} `, delayMs: 120 },
      { text: 'moonset status --verbose', delayMs: 160, typewriter: true, charDelayMs: 32 },
      { text: '\r\n\r\n', delayMs: 240 },
      { text: `${BOLD}Workspace${R}  acme-moon ${DIM}(MoonBit · npm · Cargo mixed)${R}\r\n`, delayMs: 120 },
      { text: `${BOLD}Changesets${R} 2 pending ${DIM}(quiet-storks-teach, calm-tides-glow)${R}\r\n\r\n`, delayMs: 140 },
      { text: `${DIM}UnitId                    Ecosystem  Current  Next    Bump   Reason${R}\r\n`, delayMs: 100 },
      { text: `${DIM}────────────────────────────────────────────────────────────────────────${R}\r\n`, delayMs: 70 },
      { text: `unmbt/acme/core           ${BLUE}moonbit${R}    0.2.0    ${CYAN}0.3.0${R}   minor  direct changeset\r\n`, delayMs: 110 },
      { text: `unmbt/acme/cli            ${BLUE}moonbit${R}    0.2.0    ${CYAN}0.3.0${R}   minor  fixed group [core, cli]\r\n`, delayMs: 110 },
      { text: `npm:@acme/sdk             ${GREEN}npm${R}        0.2.0    ${YELLOW}0.2.1${R}   patch  bridge dep → core\r\n`, delayMs: 110 },
      { text: `cargo:acme-ffi            ${MAGENTA}cargo${R}      0.2.0    ${YELLOW}0.2.1${R}   patch  internal dependency\r\n\r\n`, delayMs: 110 },
      { text: `${GREEN}✓${R} Read-only pure planner completed in ${BOLD}14ms${R} ${DIM}(0 writes, 0 network)${R}\r\n`, delayMs: 140 },
    ],
  },
  {
    id: 'version',
    label: 'version',
    command: 'moonset version --dry-run',
    caption: '全量校验 + 隔离 staging + 原子替换与 journal 恢复保护',
    steps: [
      { text: `${DIM}~/workspace/acme-moon${R} ${CYAN}$${R} `, delayMs: 120 },
      { text: 'moonset version --dry-run', delayMs: 160, typewriter: true, charDelayMs: 32 },
      { text: '\r\n\r\n', delayMs: 240 },
      { text: `${CYAN}▸${R} Validating .changeset/config.json ${DIM}(schemaVersion: 1)${R}\r\n`, delayMs: 130 },
      { text: `${CYAN}▸${R} Staging manifests & lockfiles in isolated temp directory\r\n`, delayMs: 180 },
      { text: `  ${GREEN}M${R} core/moon.mod              ${DIM}0.2.0 → 0.3.0 (lossless AST edit)${R}\r\n`, delayMs: 110 },
      { text: `  ${GREEN}M${R} cli/moon.mod               ${DIM}0.2.0 → 0.3.0 (+ dep range ^0.3.0)${R}\r\n`, delayMs: 110 },
      { text: `  ${GREEN}M${R} packages/sdk/package.json  ${DIM}0.2.0 → 0.2.1${R}\r\n`, delayMs: 110 },
      { text: `  ${GREEN}M${R} crates/ffi/Cargo.toml      ${DIM}0.2.0 → 0.2.1${R}\r\n`, delayMs: 110 },
      { text: `  ${BLUE}A${R} CHANGELOG.md               ${DIM}+18 lines (github generator)${R}\r\n`, delayMs: 110 },
      { text: `  ${RED}D${R} .changeset/quiet-storks-teach.md\r\n`, delayMs: 90 },
      { text: `  ${MAGENTA}W${R} .moonset/release-state.json\r\n\r\n`, delayMs: 110 },
      { text: `${YELLOW}ℹ${R} Dry-run mode active — workspace untouched. Run ${BOLD}moonset version${R} to apply.\r\n`, delayMs: 140 },
    ],
  },
  {
    id: 'publish',
    label: 'publish',
    command: 'moonset publish --yes && moonset tag --push',
    caption: '按拓扑 DAG 顺序发布至 Mooncakes、npm 与 crates.io，失败可断点续跑',
    steps: [
      { text: `${DIM}~/workspace/acme-moon${R} ${CYAN}$${R} `, delayMs: 120 },
      { text: 'moonset publish --yes', delayMs: 160, typewriter: true, charDelayMs: 36 },
      { text: '\r\n\r\n', delayMs: 240 },
      { text: `${BOLD}Release DAG${R} ${DIM}(4 units · 3 registries · idempotency verified)${R}\r\n`, delayMs: 140 },
      { text: `  ${GREEN}✓${R} [1/4] unmbt/acme/core@0.3.0   ${DIM}→ mooncakes.io${R}  ${GREEN}published${R}\r\n`, delayMs: 210 },
      { text: `  ${GREEN}✓${R} [2/4] unmbt/acme/cli@0.3.0    ${DIM}→ mooncakes.io${R}  ${GREEN}published${R}\r\n`, delayMs: 200 },
      { text: `  ${GREEN}✓${R} [3/4] npm:@acme/sdk@0.2.1     ${DIM}→ registry.npmjs.org${R}  ${GREEN}published${R}\r\n`, delayMs: 210 },
      { text: `  ${GREEN}✓${R} [4/4] cargo:acme-ffi@0.2.1    ${DIM}→ crates.io${R}  ${GREEN}published${R}\r\n\r\n`, delayMs: 200 },
      { text: `${CYAN}▸${R} Creating annotated Git tags & syncing GitHub Releases\r\n`, delayMs: 180 },
      { text: `  ${MAGENTA}tag${R} unmbt/acme/core@0.3.0  ${MAGENTA}tag${R} npm:@acme/sdk@0.2.1  ${MAGENTA}tag${R} v0.3.0\r\n\r\n`, delayMs: 140 },
      { text: `${GREEN}✓${R} All 4 targets released cleanly. State checkpoint saved.\r\n`, delayMs: 120 },
    ],
  },
];

export function getScenarioById(id: TerminalScenarioId): TerminalScenario {
  return TERMINAL_SCENARIOS.find((s) => s.id === id) ?? TERMINAL_SCENARIOS[0];
}

/**
 * Evaluates user-typed commands inside the interactive xterm.js prompt.
 */
export function evaluateInteractiveCommand(rawInput: string): {
  lines: string[];
  clear?: boolean;
  switchScenario?: TerminalScenarioId;
} {
  const input = rawInput.trim();
  if (!input) return { lines: [] };

  if (input === 'clear' || input === 'cls') {
    return { lines: [], clear: true };
  }

  if (input === 'help' || input === 'moonset --help' || input === 'moonset -h') {
    return {
      lines: [
        `${BOLD}moonset${R} v0.2.0 — MoonBit workspace release & changelog companion`,
        '',
        `  ${CYAN}moonset add${R}              交互式创建 changeset (播放 TUI 演示)`,
        `  ${CYAN}moonset status${R}           只读预览待发布计划 (播放规划演示)`,
        `  ${CYAN}moonset version --dry-run${R} 预览清单与 Changelog 变更`,
        `  ${CYAN}moonset publish${R}          多生态拓扑发布演示`,
        `  ${CYAN}moonset doctor${R}           诊断本机工具链、Git 与 workspace`,
        `  ${CYAN}moonset pre status${R}       查看预发布模式状态`,
        `  ${CYAN}clear${R}                    清空终端`,
      ],
    };
  }

  if (input === 'moonset -V' || input === 'moonset --version') {
    return {
      lines: [`moonset 0.2.0 (native · pure-core wasm-gc compatible)`],
    };
  }

  if (input.startsWith('moonset add')) {
    return { lines: [], switchScenario: 'add' };
  }
  if (input.startsWith('moonset status')) {
    return { lines: [], switchScenario: 'status' };
  }
  if (input.startsWith('moonset version')) {
    return { lines: [], switchScenario: 'version' };
  }
  if (input.startsWith('moonset publish')) {
    return { lines: [], switchScenario: 'publish' };
  }

  if (input.startsWith('moonset doctor')) {
    return {
      lines: [
        `${BOLD}moonset doctor${R} ${DIM}· read-only diagnostics${R}`,
        `  ${GREEN}✓${R} moon toolchain      0.1.20261104 (moonc v0.10.20)`,
        `  ${GREEN}✓${R} git repository      clean working tree · baseBranch=main`,
        `  ${GREEN}✓${R} .changeset/config   schemaVersion=1 valid`,
        `  ${GREEN}✓${R} workspace units     4 units (2 moonbit · 1 npm · 1 cargo)`,
        `  ${GREEN}✓${R} formatter           biome detected (optional)`,
      ],
    };
  }

  if (input.startsWith('moonset pre')) {
    return {
      lines: [
        `${BOLD}Prerelease mode${R}: ${DIM}inactive (stable)${R}`,
        `Run ${CYAN}moonset pre enter alpha${R} to enter Changesets v3 prerelease mode.`,
      ],
    };
  }

  return {
    lines: [
      `${YELLOW}command not recognized:${R} ${input}`,
      `Type ${CYAN}help${R} to see interactive commands, or click a scenario tab above.`,
    ],
  };
}
