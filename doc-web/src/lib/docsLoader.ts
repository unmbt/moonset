import { ALL_DOCS, extractChineseReadme } from './docsCatalog';
import { stripFrontMatter } from './markdown';

/*
 * Repository docs are bundled from the real source of truth at build time, but
 * loaded lazily (one shared `docs-content` chunk, see vite.config.ts) so the home
 * page no longer pays for ~1 MB of Markdown on first paint.
 */
const docsGlob = import.meta.glob<string>('../../../docs/**/*.md', {
  query: '?raw',
  import: 'default',
});

const skillsGlob = import.meta.glob<string>('../../../skills/moonset/**/*.md', {
  query: '?raw',
  import: 'default',
});

const rootGlob = import.meta.glob<string>(['../../../CHANGELOG.md', '../../../README.mbt.md'], {
  query: '?raw',
  import: 'default',
});

function normalizeRepoPath(vitePath: string): string {
  const idx = vitePath.indexOf('/docs/');
  if (idx !== -1) return vitePath.slice(idx + 1);
  const skillsIdx = vitePath.indexOf('/skills/');
  if (skillsIdx !== -1) return vitePath.slice(skillsIdx + 1);
  if (vitePath.endsWith('CHANGELOG.md')) return 'CHANGELOG.md';
  if (vitePath.endsWith('README.mbt.md')) return 'README.mbt.md';
  return vitePath.replace(/^(\.\.\/)+/, '');
}

const LOADERS: Record<string, () => Promise<string>> = {};
for (const [key, loader] of Object.entries({ ...docsGlob, ...skillsGlob, ...rootGlob })) {
  LOADERS[normalizeRepoPath(key)] = loader;
}

const cache = new Map<string, string>();
const inflight = new Map<string, Promise<string>>();

export function getCachedDocContent(repoPath: string): string | undefined {
  return cache.get(repoPath);
}

export function loadDocContent(repoPath: string): Promise<string> {
  const cached = cache.get(repoPath);
  if (cached !== undefined) return Promise.resolve(cached);
  const pending = inflight.get(repoPath);
  if (pending) return pending;

  const loader = LOADERS[repoPath];
  if (!loader) {
    cache.set(repoPath, '');
    return Promise.resolve('');
  }

  const promise = loader()
    .then((raw) => {
      const content =
        repoPath === 'README.mbt.md' ? extractChineseReadme(raw) : stripFrontMatter(raw);
      cache.set(repoPath, content);
      inflight.delete(repoPath);
      return content;
    })
    .catch(() => {
      inflight.delete(repoPath);
      return '';
    });
  inflight.set(repoPath, promise);
  return promise;
}

/** Warms the docs chunk ahead of navigation (e.g. on link hover / idle). */
export function prefetchDocs(): void {
  void loadDocContent(ALL_DOCS[0].repoPath);
}

let allContentsPromise: Promise<Record<string, string>> | null = null;

/** Loads every catalogued document for full-text search. */
export function loadAllDocContents(): Promise<Record<string, string>> {
  if (!allContentsPromise) {
    allContentsPromise = Promise.all(
      ALL_DOCS.map(async (doc) => [doc.repoPath, await loadDocContent(doc.repoPath)] as const),
    ).then((entries) => Object.fromEntries(entries));
  }
  return allContentsPromise;
}
