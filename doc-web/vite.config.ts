import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

function readMoonsetVersion(): string {
  try {
    const raw = fs.readFileSync(path.join(repoRoot, 'moon.mod'), 'utf8');
    const match = /^\s*version\s*=\s*"([^"]+)"/m.exec(raw);
    if (match) return match[1];
  } catch {
    // Fallback if moon.mod is unavailable
  }
  return '0.3.0';
}

function resolveBasePath(): string {
  const raw = process.env.VITE_BASE_PATH;
  if (raw === undefined) return './';
  const trimmed = raw.trim();
  if (!trimmed || trimmed === '/') return '/';
  return trimmed.endsWith('/') ? trimmed : `${trimmed}/`;
}

export default defineConfig({
  root: __dirname,
  base: resolveBasePath(),
  define: {
    __MOONSET_VERSION__: JSON.stringify(readMoonsetVersion()),
  },
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 3000,
    host: '0.0.0.0',
    hmr: false,
    fs: {
      allow: [repoRoot],
    },
  },
  preview: {
    port: 3000,
    host: '0.0.0.0',
  },
  build: {
    outDir: path.resolve(__dirname, 'dist'),
    emptyOutDir: true,
    sourcemap: false,
    // Mermaid's optional layout engines (elk, cytoscape) are large but only lazy-loaded
    // when a page actually contains such a diagram.
    chunkSizeWarningLimit: 1600,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('@xterm/xterm') || id.includes('@xterm/addon-fit')) {
            return 'xterm';
          }
          if (id.includes('react-markdown') || id.includes('remark-gfm')) {
            return 'markdown';
          }
          // All repository Markdown (docs/, README, CHANGELOG) ships as one lazily
          // fetched chunk: first doc visit warms every page and full-text search.
          if (/\.md\?raw$/.test(id)) {
            return 'docs-content';
          }
        },
      },
    },
  },
});
