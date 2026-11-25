import { useEffect, useState } from 'react';
import { getCachedDocContent, loadDocContent } from '../lib/docsLoader';

/** Returns the Markdown for `repoPath`, or null while the docs chunk is loading. */
export function useDocContent(repoPath: string): string | null {
  const [state, setState] = useState<{ path: string; content: string | null }>(() => ({
    path: repoPath,
    content: getCachedDocContent(repoPath) ?? null,
  }));

  useEffect(() => {
    let alive = true;
    const cached = getCachedDocContent(repoPath);
    if (cached !== undefined) {
      setState({ path: repoPath, content: cached });
      return;
    }
    setState({ path: repoPath, content: null });
    loadDocContent(repoPath).then((content) => {
      if (alive) setState({ path: repoPath, content });
    });
    return () => {
      alive = false;
    };
  }, [repoPath]);

  if (state.path === repoPath) return state.content;
  return getCachedDocContent(repoPath) ?? null;
}
