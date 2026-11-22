import { extractChineseReadme } from './docsCatalog';

// Eagerly bundle all real repository docs and CHANGELOG at build time
// so static GitHub Pages deployments stay 100% synced with the repo source of truth.
const rawDocsGlob = import.meta.glob<string>('../../../docs/**/*.md', {
  query: '?raw',
  import: 'default',
  eager: true,
});

const rawRootFiles = import.meta.glob<string>(
  ['../../../CHANGELOG.md', '../../../README.mbt.md'],
  {
    query: '?raw',
    import: 'default',
    eager: true,
  },
);

function normalizeRepoPath(vitePath: string): string {
  const idx = vitePath.indexOf('/docs/');
  if (idx !== -1) {
    return vitePath.slice(idx + 1);
  }
  if (vitePath.endsWith('CHANGELOG.md')) return 'CHANGELOG.md';
  if (vitePath.endsWith('README.mbt.md')) return 'README.mbt.md';
  return vitePath.replace(/^(\.\.\/)+/, '');
}

const DOC_CONTENT_MAP: Record<string, string> = {};

for (const [key, content] of Object.entries(rawDocsGlob)) {
  DOC_CONTENT_MAP[normalizeRepoPath(key)] = content;
}

for (const [key, content] of Object.entries(rawRootFiles)) {
  const normalized = normalizeRepoPath(key);
  if (normalized === 'README.mbt.md') {
    DOC_CONTENT_MAP[normalized] = extractChineseReadme(content);
  } else {
    DOC_CONTENT_MAP[normalized] = content;
  }
}

export function getAllDocContents(): Record<string, string> {
  return DOC_CONTENT_MAP;
}

export function getDocContent(repoPath: string): string {
  return DOC_CONTENT_MAP[repoPath] ?? '';
}

export function getChangelogRaw(): string {
  return DOC_CONTENT_MAP['CHANGELOG.md'] ?? '';
}
