declare const __MOONSET_VERSION__: string | undefined;

/**
 * Current moonset package version, automatically synced from the repository's
 * root `moon.mod` at build/dev time via Vite `define`.
 */
export const MOONSET_VERSION: string =
  typeof __MOONSET_VERSION__ === 'string' && __MOONSET_VERSION__.length > 0
    ? __MOONSET_VERSION__
    : '0.3.0';
