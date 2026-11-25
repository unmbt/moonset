import { ALL_DOCS, DOC_SECTIONS, searchDocs, type DocNavItem } from './docsCatalog';
import { extractHeadings, type DocHeading } from './markdown';

export interface HeadingIndexEntry {
  item: DocNavItem;
  heading: DocHeading;
}

export type PaletteHit =
  | {
      kind: 'doc';
      item: DocNavItem;
      sectionTitle: string;
      snippet: string;
      score: number;
    }
  | {
      kind: 'heading';
      item: DocNavItem;
      sectionTitle: string;
      heading: DocHeading;
      score: number;
    };

const SECTION_TITLES = new Map(DOC_SECTIONS.map((s) => [s.id, s.title]));

export function sectionTitleOf(item: DocNavItem): string {
  return SECTION_TITLES.get(item.sectionId) ?? '文档';
}

/** Builds a flat H2/H3 index across every catalogued document. */
export function buildHeadingIndex(contentByRepoPath: Record<string, string>): HeadingIndexEntry[] {
  const entries: HeadingIndexEntry[] = [];
  for (const item of ALL_DOCS) {
    const content = contentByRepoPath[item.repoPath];
    if (!content) continue;
    for (const heading of extractHeadings(content)) {
      entries.push({ item, heading });
    }
  }
  return entries;
}

/**
 * Combined command-palette search: whole documents first (title > subtitle > body),
 * followed by section headings so readers can jump straight to a specific clause.
 */
export function searchPalette(
  query: string,
  contentByRepoPath: Record<string, string>,
  headingIndex: HeadingIndexEntry[],
  limits: { docs?: number; headings?: number } = {},
): PaletteHit[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];

  const docHits: PaletteHit[] = searchDocs(query, contentByRepoPath)
    .slice(0, limits.docs ?? 8)
    .map((hit) => ({
      kind: 'doc' as const,
      item: hit.item,
      sectionTitle: hit.sectionTitle,
      snippet: hit.snippet,
      score: hit.score,
    }));

  const headingHits: PaletteHit[] = [];
  for (const entry of headingIndex) {
    const text = entry.heading.text.toLowerCase();
    const idx = text.indexOf(normalized);
    if (idx === -1) continue;
    const score = (idx === 0 ? 60 : 30) + (entry.heading.level === 2 ? 5 : 0);
    headingHits.push({
      kind: 'heading',
      item: entry.item,
      sectionTitle: sectionTitleOf(entry.item),
      heading: entry.heading,
      score,
    });
  }
  headingHits.sort((a, b) => b.score - a.score);

  return [...docHits, ...headingHits.slice(0, limits.headings ?? 8)];
}

/** Suggests likely documents for an unknown slug (used by the 404 view). */
export function suggestDocs(slug: string, limit = 4): DocNavItem[] {
  const tokens = slug
    .toLowerCase()
    .split(/[\s/_.-]+/)
    .filter((t) => t.length >= 2);

  const scored = ALL_DOCS.map((item) => {
    const haystack = `${item.slug} ${item.title} ${item.subtitle ?? ''}`.toLowerCase();
    const score = tokens.reduce((acc, token) => acc + (haystack.includes(token) ? 1 : 0), 0);
    return { item, score };
  })
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score)
    .map((entry) => entry.item);

  if (scored.length >= limit) return scored.slice(0, limit);
  const fallback = ALL_DOCS.filter(
    (item) => item.sectionId === 'guide' && !scored.includes(item),
  );
  return [...scored, ...fallback].slice(0, limit);
}
