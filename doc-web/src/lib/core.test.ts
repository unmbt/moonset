import test from 'node:test';
import assert from 'node:assert/strict';
import {
  computeCircularRevealGeometry,
  nextThemePreference,
  parseStoredTheme,
  resolveTheme,
  resolveThemeTransitionOrigin,
} from './theme';
import {
  computeSectionProgress,
  computeTimelineState,
} from './scrollTimeline';
import {
  extractHeadings,
  parseChangelog,
  rehypeHeadingIds,
  resolveRelativeDocSlug,
  slugifyHeading,
  stripFrontMatter,
} from './markdown';
import {
  ALL_DOCS,
  DOC_SECTIONS,
  getDocBySlug,
  getDocNeighbors,
  searchDocs,
} from './docsCatalog';
import { evaluateInteractiveCommand, getScenarioById } from './terminalScripts';
import {
  DEFAULT_SMOOTH_SCROLL_CONFIG,
  accumulateScrollTarget,
  normalizeWheelDelta,
  softLimitWheelDelta,
  stepInertialScroll,
} from './smoothScroll';
import {
  highlightCodeLines,
  normalizeCodeLanguage,
} from './highlight';
import {
  INITIAL_PAN_ZOOM_STATE,
  applyPanDelta,
  clampScale,
  computePinchSnapshot,
  computeWheelZoomScale,
  stepPinchTransform,
  zoomAtPoint,
} from './panZoom';

test('theme defaults to system and toggles with immediate visual change', () => {
  assert.equal(parseStoredTheme(null), 'system');
  assert.equal(resolveTheme('system', true), 'dark');
  assert.equal(resolveTheme('system', false), 'light');

  // When system is dark: system -> light -> system
  const step1Dark = nextThemePreference('system', true);
  assert.equal(step1Dark, 'light');
  assert.equal(resolveTheme(step1Dark, true), 'light');
  assert.equal(nextThemePreference(step1Dark, true), 'system');

  // When system is light: system -> dark -> system
  const step1Light = nextThemePreference('system', false);
  assert.equal(step1Light, 'dark');
  assert.equal(resolveTheme(step1Light, false), 'dark');
  assert.equal(nextThemePreference(step1Light, false), 'system');
});

test('circular View Transition origin and radius geometry cover full viewport from click or keyboard', () => {
  const viewport = { width: 1440, height: 900 };
  const buttonRect = { left: 1200, top: 14, width: 36, height: 36 };

  // Pointer click uses exact click coordinates
  const pointerOrigin = resolveThemeTransitionOrigin(
    { clientX: 1215, clientY: 31, detail: 1 },
    buttonRect,
    viewport,
  );
  assert.deepEqual(pointerOrigin, { x: 1215, y: 31 });

  // Keyboard activation (detail=0, 0,0) falls back to button center
  const keyboardOrigin = resolveThemeTransitionOrigin(
    { clientX: 0, clientY: 0, detail: 0 },
    buttonRect,
    viewport,
  );
  assert.deepEqual(keyboardOrigin, { x: 1218, y: 32 });

  // Radius from top-right button reaches bottom-left corner (0, 900)
  const geom = computeCircularRevealGeometry(pointerOrigin, viewport);
  assert.equal(geom.x, 1215);
  assert.equal(geom.y, 31);
  assert.ok(Math.abs(geom.endRadius - Math.hypot(1215, 900 - 31)) < 0.001);

  // Out-of-bounds origin is clamped to viewport bounds
  const clamped = computeCircularRevealGeometry({ x: -40, y: 1200 }, viewport);
  assert.equal(clamped.x, 0);
  assert.equal(clamped.y, 900);
  assert.ok(Math.abs(clamped.endRadius - Math.hypot(1440, 900)) < 0.001);
});

test('scroll timeline computes bounded progress and active chapters', () => {
  assert.equal(computeSectionProgress(200, 2000, 800), 0);
  assert.equal(computeSectionProgress(-600, 2000, 800), 0.5);
  assert.equal(computeSectionProgress(-1600, 2000, 800), 1);

  const start = computeTimelineState(0, 5);
  assert.equal(start.activeIndex, 0);
  assert.equal(start.weights[0], 1);

  const mid = computeTimelineState(0.5, 5);
  assert.equal(mid.activeIndex, 2);
  assert.equal(mid.weights[2], 1);

  const end = computeTimelineState(1, 5);
  assert.equal(end.activeIndex, 4);
  assert.equal(end.weights[4], 1);
});

test('markdown heading extraction ignores fenced code blocks and deduplicates IDs', () => {
  const md = [
    '# Title',
    '## 快速开始',
    '```bash',
    '## not a heading',
    '```',
    '### CLI `status` 命令',
    '## 快速开始',
  ].join('\n');

  const headings = extractHeadings(md);
  assert.equal(headings.length, 3);
  assert.equal(headings[0].id, slugifyHeading('快速开始'));
  assert.equal(headings[1].text, 'CLI status 命令');
  assert.equal(headings[2].id, `${slugifyHeading('快速开始')}-1`);

  // Verify rehypeHeadingIds assigns identical IDs to HAST heading nodes
  const ast: {
    type: string;
    children: Array<{
      type: string;
      tagName: string;
      properties: Record<string, unknown>;
      children: unknown[];
    }>;
  } = {
    type: 'root',
    children: [
      { type: 'element', tagName: 'h2', properties: {}, children: [{ type: 'text', value: '快速开始' }] },
      {
        type: 'element',
        tagName: 'h3',
        properties: {},
        children: [
          { type: 'text', value: 'CLI ' },
          { type: 'element', tagName: 'code', children: [{ type: 'text', value: 'status' }] },
          { type: 'text', value: ' 命令' },
        ],
      },
      { type: 'element', tagName: 'h2', properties: {}, children: [{ type: 'text', value: '快速开始' }] },
    ],
  };
  rehypeHeadingIds()(ast as never);
  assert.deepEqual(
    ast.children.map((node) => node.properties.id),
    headings.map((h) => h.id),
  );
});

test('relative doc link resolution maps markdown paths to SPA routes', () => {
  assert.deepEqual(
    resolveRelativeDocSlug('docs/README.md', 'commands.md'),
    { route: '/docs/commands', hash: undefined },
  );
  assert.deepEqual(
    resolveRelativeDocSlug('docs/README.md', 'decisions/009-changesets-v3-pre-and-snapshot-model.md'),
    { route: '/docs/decisions/009-changesets-v3-pre-and-snapshot-model', hash: undefined },
  );
  assert.deepEqual(
    resolveRelativeDocSlug('docs/decisions/README.md', '010-inline-tui-and-terminal-color.md'),
    { route: '/docs/decisions/010-inline-tui-and-terminal-color', hash: undefined },
  );
  assert.deepEqual(
    resolveRelativeDocSlug('docs/README.md', '../CHANGELOG.md'),
    { route: '/changelog', hash: undefined },
  );
  assert.equal(
    resolveRelativeDocSlug('docs/README.md', 'https://github.com/unmbt/moonset'),
    null,
  );
  assert.deepEqual(
    resolveRelativeDocSlug('skills/moonset/SKILL.md', './references/cli-reference.md'),
    { route: '/docs/skills/cli-reference', hash: undefined },
  );
  assert.deepEqual(
    resolveRelativeDocSlug('skills/moonset/references/cli-reference.md', '../SKILL.md'),
    { route: '/docs/skills/moonset', hash: undefined },
  );

  assert.equal(
    stripFrontMatter('---\nname: moonset\ndescription: test\n---\n\n# moonset Agent Guide\n'),
    '# moonset Agent Guide\n',
  );
  assert.equal(stripFrontMatter('# No front matter\n'), '# No front matter\n');
});

test('changelog parser extracts versions, dates, groups, and commit links', () => {
  const sample = `# Changelog

## 0.2.0 - 2026-11-19

### Minor Changes

- [\`2095fc4\`](https://github.com/unmbt/moonset/commit/2095fc4) Thanks [@Wyatex](https://github.com/Wyatex)! - Add glob matching and formatter support.

## 0.1.0 - 2026-11-18

### Features

- Initial release. ([badcec44](https://github.com/unmbt/moonset/commit/badcec44))
`;

  const parsed = parseChangelog(sample);
  assert.equal(parsed.length, 2);
  assert.equal(parsed[0].version, '0.2.0');
  assert.equal(parsed[0].date, '2026-11-19');
  assert.equal(parsed[0].groups[0].items[0].commitHash, '2095fc4');
  assert.equal(parsed[0].groups[0].items[0].author, 'Wyatex');
  assert.equal(parsed[1].groups[0].items[0].commitHash, 'badcec44');
});

test('docs catalog search and neighbor navigation work accurately', () => {
  assert.ok(ALL_DOCS.length >= 25);
  assert.equal(getDocBySlug('commands')?.repoPath, 'docs/commands.md');
  assert.equal(getDocBySlug('skills/moonset')?.repoPath, 'skills/moonset/SKILL.md');

  const sectionIds = DOC_SECTIONS.map((s) => s.id);
  assert.equal(sectionIds.indexOf('skills'), sectionIds.indexOf('ecosystem') + 1);
  assert.equal(sectionIds.indexOf('decisions'), sectionIds.indexOf('skills') + 1);

  const neighbors = getDocNeighbors('commands');
  assert.ok(neighbors.prev);
  assert.ok(neighbors.next);

  const hits = searchDocs('commands', {
    'docs/commands.md': 'moonset status --verbose and publish-plan commands',
  });
  assert.ok(hits.length >= 1);
  assert.equal(hits[0].item.slug, 'commands');
});

test('interactive terminal evaluator handles help, doctor, and scenario switching', () => {
  assert.equal(getScenarioById('add').id, 'add');
  assert.equal(evaluateInteractiveCommand('clear').clear, true);
  assert.equal(evaluateInteractiveCommand('moonset status').switchScenario, 'status');
  assert.ok(evaluateInteractiveCommand('moonset doctor').lines.length >= 4);
  assert.ok(evaluateInteractiveCommand('help').lines.some((l) => l.includes('moonset add')));
});

test('smooth scroll soft-limits fast wheel bursts and caps maximum vertical velocity', () => {
  assert.equal(normalizeWheelDelta(3, 1, 900), 108);
  assert.ok(softLimitWheelDelta(1200, 190) <= 190);
  assert.ok(softLimitWheelDelta(-1200, 190) >= -190);
  // Small deltas stay close to 1:1
  assert.ok(Math.abs(softLimitWheelDelta(20, 190) - 20) < 0.5);

  // Lead distance is bounded so rapid scrolling doesn't queue infinite runaway inertia
  const boundedTarget = accumulateScrollTarget(500, 1100, 180, 5000, 680);
  assert.equal(boundedTarget, 1180);

  // Velocity cap holds even for large remaining distance
  const dtMs = 16;
  const maxAllowedStep = DEFAULT_SMOOTH_SCROLL_CONFIG.maxVelocityPxPerSec * (dtMs / 1000);
  const step = stepInertialScroll(0, 5000, dtMs, DEFAULT_SMOOTH_SCROLL_CONFIG);
  assert.equal(step.settled, false);
  assert.ok(step.nextY <= maxAllowedStep + 0.001);

  // Settles cleanly when within stop threshold
  const done = stepInertialScroll(99.8, 100, 16, DEFAULT_SMOOTH_SCROLL_CONFIG);
  assert.equal(done.settled, true);
  assert.equal(done.nextY, 100);
});

test('shiki highlighter normalizes aliases and produces dual-theme syntax tokens losslessly', () => {
  assert.equal(normalizeCodeLanguage('sh'), 'bash');
  assert.equal(normalizeCodeLanguage('YML'), 'yaml');
  assert.equal(normalizeCodeLanguage('mbt'), 'moonbit');
  assert.equal(normalizeCodeLanguage('ps1'), 'powershell');
  assert.equal(normalizeCodeLanguage('jsonc'), 'json');
  assert.equal(normalizeCodeLanguage('text'), null);
  assert.equal(normalizeCodeLanguage('unknown-lang'), null);

  const samples: Array<{ lang: string; code: string }> = [
    { lang: 'bash', code: 'moon install unmbt/moonset/cmd/moonset\nmoonset status --verbose' },
    { lang: 'json', code: '{\n  "baseBranch": "main",\n  "access": "public"\n}' },
    { lang: 'yaml', code: 'name: Release\non:\n  push:\n    branches: [main]' },
    { lang: 'moonbit', code: 'pub fn plan(version : String) -> Int {\n  42\n}' },
    { lang: 'powershell', code: 'irm https://example.com/install.ps1 | iex' },
  ];

  for (const sample of samples) {
    const res = highlightCodeLines(sample.code, sample.lang);
    assert.equal(res.language, sample.lang);
    const roundTripped = res.lines.map((line) => line.map((t) => t.content).join('')).join('\n');
    assert.equal(roundTripped, sample.code);

    const flatTokens = res.lines.flat();
    const lightColors = new Set(flatTokens.map((t) => t.lightColor).filter(Boolean));
    const darkColors = new Set(flatTokens.map((t) => t.darkColor).filter(Boolean));
    assert.ok(lightColors.size >= 2, `expected multiple light token colors for ${sample.lang}`);
    assert.ok(darkColors.size >= 2, `expected multiple dark token colors for ${sample.lang}`);
  }

  // Plain text falls back cleanly without throwing
  const plain = highlightCodeLines('hello\nworld', 'text');
  assert.equal(plain.language, null);
  assert.equal(plain.lines.length, 2);
  assert.equal(plain.lines[0][0].content, 'hello');
});

test('pan-zoom gesture math anchors focal point on wheel zoom and supports two-finger pinch + pan', () => {
  assert.equal(clampScale(0.05), 0.4);
  assert.equal(clampScale(20), 6);

  // Wheel up zooms in, wheel down zooms out
  assert.ok(computeWheelZoomScale(1, -120) > 1);
  assert.ok(computeWheelZoomScale(1, 120) < 1);

  // Cursor-anchored zoom keeps the content point under the pointer stationary
  const center = { x: 500, y: 400 };
  const focal = { x: 700, y: 500 }; // (+200, +100) from center
  const zoomed = zoomAtPoint(INITIAL_PAN_ZOOM_STATE, 2, focal, center);
  assert.equal(zoomed.scale, 2);
  assert.equal(zoomed.x, -200);
  assert.equal(zoomed.y, -100);

  // Dragging adds pan delta cleanly
  const panned = applyPanDelta(zoomed, 35, -20);
  assert.equal(panned.x, -165);
  assert.equal(panned.y, -120);

  // Two-finger pinch doubling finger distance doubles scale and tracks midpoint shift
  const startPinch = computePinchSnapshot({ x: 450, y: 400 }, { x: 550, y: 400 });
  const endPinch = computePinchSnapshot({ x: 420, y: 430 }, { x: 620, y: 430 });
  assert.equal(startPinch.distance, 100);
  assert.deepEqual(startPinch.midpoint, { x: 500, y: 400 });
  assert.equal(endPinch.distance, 200);
  assert.deepEqual(endPinch.midpoint, { x: 520, y: 430 });

  const pinched = stepPinchTransform(INITIAL_PAN_ZOOM_STATE, startPinch, endPinch, center);
  assert.equal(pinched.scale, 2);
  assert.equal(pinched.x, 20);
  assert.equal(pinched.y, 30);
});
