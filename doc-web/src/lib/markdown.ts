export interface DocHeading {
  id: string;
  text: string;
  level: 2 | 3;
}

export interface ChangelogEntry {
  text: string;
  commitHash?: string;
  commitUrl?: string;
  author?: string;
}

export interface ChangelogGroup {
  title: string;
  items: ChangelogEntry[];
}

export interface ChangelogRelease {
  version: string;
  date: string;
  groups: ChangelogGroup[];
}

/**
 * Deterministically converts a heading (Chinese or English) into an HTML id.
 */
export function slugifyHeading(text: string): string {
  const cleaned = text
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_~]/g, '')
    .trim()
    .toLowerCase();

  return cleaned
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

export function createHeadingIdFactory() {
  const counts = new Map<string, number>();
  let index = 0;
  return (rawText: string): string => {
    index += 1;
    const baseId = slugifyHeading(rawText) || `section-${index}`;
    const seen = counts.get(baseId) ?? 0;
    counts.set(baseId, seen + 1);
    return seen === 0 ? baseId : `${baseId}-${seen}`;
  };
}

interface HastNode {
  type?: string;
  tagName?: string;
  value?: string;
  properties?: Record<string, unknown>;
  children?: HastNode[];
}

function getHastText(node: HastNode): string {
  if (node.type === 'text' && typeof node.value === 'string') {
    return node.value;
  }
  if (Array.isArray(node.children)) {
    return node.children.map(getHastText).join('');
  }
  return '';
}

/**
 * Pure rehype plugin that assigns deterministic heading IDs to h2/h3 nodes
 * inside the unified AST pipeline (immune to React StrictMode double-renders).
 */
export function rehypeHeadingIds() {
  return (tree: HastNode) => {
    const nextId = createHeadingIdFactory();
    const visit = (node: HastNode) => {
      if (
        node.type === 'element' &&
        (node.tagName === 'h2' || node.tagName === 'h3')
      ) {
        const text = getHastText(node).trim();
        node.properties = node.properties ?? {};
        node.properties.id = nextId(text);
      }
      if (Array.isArray(node.children)) {
        for (const child of node.children) {
          visit(child);
        }
      }
    };
    visit(tree);
  };
}

/**
 * Extracts H2 and H3 headings from Markdown while ignoring fenced code blocks.
 */
export function extractHeadings(markdown: string): DocHeading[] {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const headings: DocHeading[] = [];
  const nextId = createHeadingIdFactory();
  let inFence = false;
  let fenceChar = '';

  for (const line of lines) {
    const trimmed = line.trimStart();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      const marker = trimmed.slice(0, 3);
      if (!inFence) {
        inFence = true;
        fenceChar = marker[0];
      } else if (marker[0] === fenceChar) {
        inFence = false;
        fenceChar = '';
      }
      continue;
    }
    if (inFence) continue;

    const match = /^(#{2,3})\s+(.+?)\s*#*$/.exec(line);
    if (!match) continue;

    const level = match[1].length as 2 | 3;
    const rawText = match[2]
      .replace(/`([^`]+)`/g, '$1')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/[*_~]/g, '')
      .trim();

    const id = nextId(rawText);
    headings.push({ id, text: rawText, level });
  }

  return headings;
}

/**
 * Resolves a relative Markdown link inside a doc page to an internal doc slug,
 * or returns null for external links / unsupported files.
 */
export function resolveRelativeDocSlug(
  currentDocPath: string,
  href: string,
): { route: string; hash?: string } | null {
  if (!href || href.startsWith('http://') || href.startsWith('https://') || href.startsWith('mailto:')) {
    return null;
  }
  if (href.startsWith('#')) {
    return { route: '', hash: href.slice(1) };
  }

  const [rawPath, hash] = href.split('#');
  const normalizedTarget = rawPath.trim();
  if (!normalizedTarget) return null;

  if (normalizedTarget.endsWith('CHANGELOG.md')) {
    return { route: '/changelog', hash };
  }

  if (normalizedTarget === 'decisions/' || normalizedTarget === 'decisions') {
    return { route: '/docs/decisions/overview', hash };
  }

  if (!normalizedTarget.endsWith('.md')) {
    return null;
  }

  // Normalize relative path against currentDocPath (e.g. "docs/README.md" or "docs/decisions/README.md")
  const baseParts = currentDocPath.split('/').slice(0, -1);
  const relParts = normalizedTarget.split('/');
  const combined = [...baseParts];

  for (const part of relParts) {
    if (!part || part === '.') continue;
    if (part === '..') {
      combined.pop();
    } else {
      combined.push(part);
    }
  }

  const resolvedPath = combined.join('/');
  if (resolvedPath === 'README.mbt.md') {
    return { route: '/docs/quickstart', hash };
  }
  if (resolvedPath === 'docs/README.md') {
    return { route: '/docs/overview', hash };
  }
  if (resolvedPath === 'docs/decisions/README.md') {
    return { route: '/docs/decisions/overview', hash };
  }
  if (resolvedPath === 'docs/changelog.md') {
    return { route: '/docs/changelog-spec', hash };
  }
  if (resolvedPath.startsWith('docs/decisions/') && resolvedPath.endsWith('.md')) {
    const file = resolvedPath.slice('docs/decisions/'.length, -3);
    return { route: `/docs/decisions/${file}`, hash };
  }
  if (resolvedPath.startsWith('docs/') && resolvedPath.endsWith('.md')) {
    const file = resolvedPath.slice('docs/'.length, -3);
    return { route: `/docs/${file}`, hash };
  }

  return null;
}

/**
 * Parses moonset's CHANGELOG.md into structured releases for the visual timeline.
 */
export function parseChangelog(markdown: string): ChangelogRelease[] {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const releases: ChangelogRelease[] = [];
  let currentRelease: ChangelogRelease | null = null;
  let currentGroup: ChangelogGroup | null = null;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    const releaseMatch = /^##\s+([^\s]+)(?:\s*-\s*(.+))?$/.exec(line);
    if (releaseMatch) {
      currentRelease = {
        version: releaseMatch[1].trim(),
        date: (releaseMatch[2] ?? '').trim(),
        groups: [],
      };
      releases.push(currentRelease);
      currentGroup = null;
      continue;
    }

    const groupMatch = /^###\s+(.+)$/.exec(line);
    if (groupMatch && currentRelease) {
      currentGroup = {
        title: groupMatch[1].trim(),
        items: [],
      };
      currentRelease.groups.push(currentGroup);
      continue;
    }

    const itemMatch = /^-\s+(.+)$/.exec(line);
    if (itemMatch && currentRelease) {
      if (!currentGroup) {
        currentGroup = { title: 'Changes', items: [] };
        currentRelease.groups.push(currentGroup);
      }
      const body = itemMatch[1];

      // Pattern 1: [`2095fc4`](url) Thanks [@User](url)! - Description
      const leadingCommit = /^\[`([0-9a-f]{7,12})`\]\(([^)]+)\)(?:\s+Thanks\s+\[@([^\]]+)\]\([^)]+\)!)?\s*-\s*(.+)$/.exec(body);
      if (leadingCommit) {
        currentGroup.items.push({
          commitHash: leadingCommit[1],
          commitUrl: leadingCommit[2],
          author: leadingCommit[3],
          text: leadingCommit[4].trim(),
        });
        continue;
      }

      // Pattern 2: Description ([badcec44](url))
      const trailingCommit = /^(.+?)\s*\(\[([0-9a-f]{7,12})\]\(([^)]+)\)\)\s*$/.exec(body);
      if (trailingCommit) {
        currentGroup.items.push({
          text: trailingCommit[1].trim(),
          commitHash: trailingCommit[2],
          commitUrl: trailingCommit[3],
        });
        continue;
      }

      currentGroup.items.push({ text: body });
    }
  }

  return releases;
}
