export interface DocNavItem {
  slug: string;
  title: string;
  subtitle?: string;
  repoPath: string;
  sectionId: string;
}

export interface DocNavSection {
  id: string;
  title: string;
  defaultOpen?: boolean;
  items: DocNavItem[];
}

export const DOC_SECTIONS: DocNavSection[] = [
  {
    id: 'guide',
    title: '指南',
    defaultOpen: true,
    items: [
      {
        slug: 'quickstart',
        title: '快速开始',
        subtitle: '安装、工作流与快速上手',
        repoPath: 'README.mbt.md',
        sectionId: 'guide',
      },
      {
        slug: 'overview',
        title: '文档与 SDD 契约',
        subtitle: '阅读顺序、基线与工作规则',
        repoPath: 'docs/README.md',
        sectionId: 'guide',
      },
      {
        slug: 'roadmap',
        title: '路线图',
        subtitle: 'Phase 0–6 里程碑与演进计划',
        repoPath: 'docs/roadmap.md',
        sectionId: 'guide',
      },
      {
        slug: 'faq',
        title: '常见问题 FAQ',
        subtitle: '权限、Runner、凭证与排障',
        repoPath: 'docs/faq.md',
        sectionId: 'guide',
      },
    ],
  },
  {
    id: 'spec',
    title: '核心规范',
    defaultOpen: true,
    items: [
      {
        slug: 'commands',
        title: 'CLI 命令契约',
        subtitle: '子命令、参数、JSON 信封与退出码',
        repoPath: 'docs/commands.md',
        sectionId: 'spec',
      },
      {
        slug: 'configuration',
        title: '配置规范',
        subtitle: '.changeset/config.json 全字段契约',
        repoPath: 'docs/configuration.md',
        sectionId: 'spec',
      },
      {
        slug: 'data-model',
        title: '数据模型',
        subtitle: 'ReleaseUnit、Plan 与持久化状态',
        repoPath: 'docs/data-model.md',
        sectionId: 'spec',
      },
      {
        slug: 'changelog-spec',
        title: 'Changelog 规范',
        subtitle: '内置生成器与格式契约',
        repoPath: 'docs/changelog.md',
        sectionId: 'spec',
      },
      {
        slug: 'requirements',
        title: '需求规格',
        subtitle: 'FR / NFR / SEC 验收矩阵',
        repoPath: 'docs/requirements.md',
        sectionId: 'spec',
      },
    ],
  },
  {
    id: 'ecosystem',
    title: '架构与生态',
    defaultOpen: true,
    items: [
      {
        slug: 'architecture',
        title: '系统架构',
        subtitle: '纯核分层与宿主能力边界',
        repoPath: 'docs/architecture.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'mixed-workspaces',
        title: '混合 Workspace',
        subtitle: 'MoonBit · npm/pnpm · Cargo 协同',
        repoPath: 'docs/mixed-workspaces.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'automation',
        title: 'GitHub Actions 自动化',
        subtitle: 'PR Bot 双 Job 隔离与发布流水线',
        repoPath: 'docs/automation.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'api',
        title: '编程 API 与插件',
        subtitle: 'unmbt/moonset/api 与 JSONL 协议',
        repoPath: 'docs/api.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'test-strategy',
        title: '测试策略',
        subtitle: '双目标纯核测试与集成验证',
        repoPath: 'docs/test-strategy.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'sdd',
        title: 'SDD 开发流程',
        subtitle: '先有契约，后有代码',
        repoPath: 'docs/sdd.md',
        sectionId: 'ecosystem',
      },
      {
        slug: 'references',
        title: '参考实现评估',
        subtitle: '工具链与生态设计取舍',
        repoPath: 'docs/references.md',
        sectionId: 'ecosystem',
      },
    ],
  },
  {
    id: 'decisions',
    title: '架构决策 (ADR)',
    defaultOpen: false,
    items: [
      {
        slug: 'decisions/overview',
        title: 'ADR 总览',
        repoPath: 'docs/decisions/README.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/001-changeset-source',
        title: 'ADR-001 Changeset 源数据',
        repoPath: 'docs/decisions/001-changeset-source.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/002-pure-planner',
        title: 'ADR-002 纯规划器分离',
        repoPath: 'docs/decisions/002-pure-planner.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/003-core-async',
        title: 'ADR-003 迁移至 core/async',
        repoPath: 'docs/decisions/003-core-async.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/004-tagging',
        title: 'ADR-004 标签与发布分离',
        repoPath: 'docs/decisions/004-tagging.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/005-extension-boundary',
        title: 'ADR-005 扩展 API 与 JSONL',
        repoPath: 'docs/decisions/005-extension-boundary.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/006-mixed-workspaces',
        title: 'ADR-006 混合生态发布单元',
        repoPath: 'docs/decisions/006-mixed-workspaces.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/007-pr-bot-as-action',
        title: 'ADR-007 模块化 PR Bot Action',
        repoPath: 'docs/decisions/007-pr-bot-as-action.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/008-v030-api-and-adapter-convergence',
        title: 'ADR-008 API 与适配器收敛',
        repoPath: 'docs/decisions/008-v030-api-and-adapter-convergence.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/009-changesets-v3-pre-and-snapshot-model',
        title: 'ADR-009 极简预发布与快照',
        repoPath: 'docs/decisions/009-changesets-v3-pre-and-snapshot-model.md',
        sectionId: 'decisions',
      },
      {
        slug: 'decisions/010-inline-tui-and-terminal-color',
        title: 'ADR-010 内联 TUI 与终端色彩',
        repoPath: 'docs/decisions/010-inline-tui-and-terminal-color.md',
        sectionId: 'decisions',
      },
    ],
  },
];

export const ALL_DOCS: DocNavItem[] = DOC_SECTIONS.flatMap((section) => section.items);

export function getDocBySlug(slug: string): DocNavItem | undefined {
  return ALL_DOCS.find((doc) => doc.slug === slug);
}

export function getDocNeighbors(slug: string): {
  prev?: DocNavItem;
  next?: DocNavItem;
} {
  const index = ALL_DOCS.findIndex((doc) => doc.slug === slug);
  if (index === -1) return {};
  return {
    prev: index > 0 ? ALL_DOCS[index - 1] : undefined,
    next: index < ALL_DOCS.length - 1 ? ALL_DOCS[index + 1] : undefined,
  };
}

export interface SearchHit {
  item: DocNavItem;
  sectionTitle: string;
  snippet: string;
  score: number;
}

export function searchDocs(
  query: string,
  contentByRepoPath: Record<string, string>,
): SearchHit[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];

  const sectionNameMap = new Map(DOC_SECTIONS.map((s) => [s.id, s.title]));
  const hits: SearchHit[] = [];

  for (const item of ALL_DOCS) {
    const rawContent = contentByRepoPath[item.repoPath] ?? '';
    const titleLower = item.title.toLowerCase();
    const subtitleLower = (item.subtitle ?? '').toLowerCase();
    const contentLower = rawContent.toLowerCase();

    let score = 0;
    if (titleLower.includes(normalized)) score += 100;
    if (subtitleLower.includes(normalized)) score += 40;
    const bodyIdx = contentLower.indexOf(normalized);
    if (bodyIdx !== -1) score += 20;

    if (score > 0) {
      let snippet = item.subtitle ?? '';
      if (bodyIdx !== -1) {
        const start = Math.max(0, bodyIdx - 36);
        const end = Math.min(rawContent.length, bodyIdx + normalized.length + 72);
        snippet = rawContent
          .slice(start, end)
          .replace(/[#`*>\[\]]/g, '')
          .replace(/\s+/g, ' ')
          .trim();
        if (start > 0) snippet = `…${snippet}`;
        if (end < rawContent.length) snippet = `${snippet}…`;
      }
      hits.push({
        item,
        sectionTitle: sectionNameMap.get(item.sectionId) ?? '文档',
        snippet,
        score,
      });
    }
  }

  return hits.sort((a, b) => b.score - a.score).slice(0, 12);
}

/**
 * Extracts the Chinese primary section from README.mbt.md so the Quickstart
 * page reads naturally without duplicating the English half.
 */
export function extractChineseReadme(raw: string): string {
  const startMarker = '## 🇨🇳 中文';
  const endMarker = '<a id="-english"></a>';
  const startIdx = raw.indexOf(startMarker);
  const endIdx = raw.indexOf(endMarker);
  if (startIdx === -1) return raw;
  const slice = endIdx > startIdx ? raw.slice(startIdx + startMarker.length, endIdx) : raw.slice(startIdx + startMarker.length);
  return `# moonset 快速开始\n\n> 月升则潮起，版本有序，更迭有据 — 为 MoonBit workspace 而生的版本与 Changelog 管理工具。\n\n${slice.replace(/<div align="right">[\s\S]*?<\/div>/g, '').replace(/\n---\s*$/, '').trim()}`;
}
