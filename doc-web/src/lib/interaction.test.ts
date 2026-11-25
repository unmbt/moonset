import test from 'node:test';
import assert from 'node:assert/strict';
import {
  classifyWheelInput,
  countUpValue,
  createDoubleShiftDetector,
  easeOutCubic,
  formatThousands,
  splitCjkPhrases,
  splitHighlight,
} from './interaction';
import { buildHeadingIndex, searchPalette, suggestDocs } from './search';
import { computeReadingProgress } from './scrollTimeline';
import {
  WAVE_KEYFRAME_COUNT,
  WAVE_SAMPLES,
  buildWaveClipKeyframes,
  computeWaveAmplitude,
  computeWaveY,
  evaluateCubicBezier,
  spawnCrestParticles,
  stepWaveParticles,
  type WaveParticle,
} from './themeTransition';

test('double Shift fires only for two quick clean taps', () => {
  const d = createDoubleShiftDetector(400, 350);
  d.keydown('Shift', 0);
  assert.equal(d.keyup('Shift', 80), false);
  d.keydown('Shift', 200);
  assert.equal(d.keyup('Shift', 260), true);

  // Too slow between taps
  d.keydown('Shift', 1000);
  d.keyup('Shift', 1060);
  d.keydown('Shift', 1600);
  assert.equal(d.keyup('Shift', 1660), false);

  // Typing an uppercase letter in between cancels the sequence
  d.reset();
  d.keydown('Shift', 3000);
  d.keyup('Shift', 3050);
  d.keydown('Shift', 3100);
  d.keydown('A', 3120);
  assert.equal(d.keyup('Shift', 3150), false);

  // Holding Shift too long is not a tap
  d.reset();
  d.keydown('Shift', 5000);
  d.keyup('Shift', 5050);
  d.keydown('Shift', 5100);
  d.keydown('Shift', 5300, true);
  assert.equal(d.keyup('Shift', 5600), false);

  // A third tap after a fire starts a fresh sequence
  d.reset();
  d.keydown('Shift', 7000);
  d.keyup('Shift', 7040);
  d.keydown('Shift', 7100);
  assert.equal(d.keyup('Shift', 7140), true);
  d.keydown('Shift', 7200);
  assert.equal(d.keyup('Shift', 7240), false);
});

test('CJK headline phrases split after punctuation', () => {
  assert.deepEqual(splitCjkPhrases('月升则潮起，版本有序，更迭有据。'), [
    '月升则潮起，',
    '版本有序，',
    '更迭有据。',
  ]);
  assert.deepEqual(splitCjkPhrases('先有契约，后有代码。'), ['先有契约，', '后有代码。']);
  assert.deepEqual(splitCjkPhrases('no punctuation'), ['no punctuation']);
  assert.deepEqual(splitCjkPhrases(''), []);
});

test('search highlight splits case-insensitive multi-term matches', () => {
  assert.deepEqual(splitHighlight('Moonset Status verbose', 'status'), [
    { text: 'Moonset ', match: false },
    { text: 'Status', match: true },
    { text: ' verbose', match: false },
  ]);
  const multi = splitHighlight('版本规划与发布', '规划 发布');
  assert.deepEqual(
    multi.filter((s) => s.match).map((s) => s.text),
    ['规划', '发布'],
  );
  assert.deepEqual(splitHighlight('a(b)c', '(b)'), [
    { text: 'a', match: false },
    { text: '(b)', match: true },
    { text: 'c', match: false },
  ]);
  assert.deepEqual(splitHighlight('plain', '  '), [{ text: 'plain', match: false }]);
});

test('wheel classifier smooths notched wheels but leaves trackpads native', () => {
  // Line-mode wheel (Firefox) is always discrete
  assert.equal(classifyWheelInput(3, 1, 0, -Infinity).discrete, true);
  // Chromium notched wheel: 100px pixel deltas
  assert.equal(classifyWheelInput(100, 0, 0, -Infinity).discrete, true);
  // Trackpad: small deltas
  const fine = classifyWheelInput(6, 0, 1000, -Infinity);
  assert.equal(fine.discrete, false);
  assert.equal(fine.lastFineAt, 1000);
  // A fast flick right after fine events stays native (sticky window)
  assert.equal(classifyWheelInput(120, 0, 1100, fine.lastFineAt).discrete, false);
  // Long after the gesture, a big delta is discrete again
  assert.equal(classifyWheelInput(120, 0, 2000, fine.lastFineAt).discrete, true);
});

test('count-up easing is monotonic and lands exactly on target', () => {
  assert.equal(easeOutCubic(0), 0);
  assert.equal(easeOutCubic(1), 1);
  assert.ok(easeOutCubic(0.5) > 0.5);
  assert.equal(countUpValue(1495, 1), 1495);
  assert.equal(countUpValue(1495, 0), 0);
  assert.ok(countUpValue(1495, 0.3) < countUpValue(1495, 0.6));
  assert.equal(formatThousands(1495), '1,495');
});

test('reading progress maps article scroll to [0, 1]', () => {
  assert.equal(computeReadingProgress(200, 3000, 900), 0);
  assert.equal(computeReadingProgress(64, 3000, 900), 0);
  const mid = computeReadingProgress(64 - 1082, 3000, 900);
  assert.ok(Math.abs(mid - 0.5) < 0.001);
  assert.equal(computeReadingProgress(-5000, 3000, 900), 1);
  // Short article that fits entirely on screen
  assert.equal(computeReadingProgress(64, 400, 900), 1);
});

test('palette search returns documents and deep-linkable headings', () => {
  const contents = {
    'docs/commands.md': '# CLI\n\n## moonset status\n\ntext about publish-plan\n\n### 退出码\n',
    'docs/configuration.md': '# 配置\n\n## baseBranch 字段\n',
  };
  const index = buildHeadingIndex(contents);
  assert.ok(index.some((e) => e.heading.text === 'moonset status'));

  const hits = searchPalette('status', contents, index);
  assert.ok(hits.some((h) => h.kind === 'doc' && h.item.slug === 'commands'));
  const heading = hits.find((h) => h.kind === 'heading');
  assert.ok(heading && heading.kind === 'heading');
  assert.equal(heading.item.slug, 'commands');
  assert.equal(heading.heading.text, 'moonset status');

  assert.deepEqual(searchPalette('   ', contents, index), []);
});

test('unknown slugs get relevant suggestions with a guide fallback', () => {
  const suggestions = suggestDocs('decisions/009-pre-snapshot');
  assert.ok(suggestions.length > 0);
  assert.ok(suggestions[0].slug.includes('009'));
  assert.equal(suggestDocs('zzzz-unknown').length, 4);
});

test('ocean wave theme transition surges up for dark, down for light, and drives particles', () => {
  const geom = {
    originX: 1200,
    originY: 32,
    viewportWidth: 1440,
    viewportHeight: 900,
  };

  // Bézier progress curve lands cleanly on [0, 1], rises monotonically, and eases out smoothly
  assert.equal(evaluateCubicBezier(0), 0);
  assert.equal(evaluateCubicBezier(1), 1);
  assert.ok(evaluateCubicBezier(0.25) < evaluateCubicBezier(0.5));
  assert.ok(evaluateCubicBezier(0.5) > 0.55); // asymmetric tidal ease-out surge
  assert.ok(evaluateCubicBezier(0.5) < evaluateCubicBezier(0.75));

  // Amplitude is 0 at boundaries and swells smoothly in the middle
  assert.equal(computeWaveAmplitude(0, geom.viewportHeight), 0);
  assert.ok(computeWaveAmplitude(0.5, geom.viewportHeight) > 40);
  assert.ok(computeWaveAmplitude(1, geom.viewportHeight) < 0.001);

  // Dark tide surges upward from below viewport to above viewport
  assert.ok(computeWaveY(720, 0, geom, 'dark') > geom.viewportHeight);
  assert.ok(computeWaveY(720, 1, geom, 'dark') < 0);

  // Light tide cascades downward from above viewport to below viewport
  assert.ok(computeWaveY(720, 0, geom, 'light') < 0);
  assert.ok(computeWaveY(720, 1, geom, 'light') > geom.viewportHeight);

  // Every WAAPI clip-path keyframe has identical M + (SAMPLES+2) L + Z command signature
  const darkFrames = buildWaveClipKeyframes(geom, 'dark');
  const lightFrames = buildWaveClipKeyframes(geom, 'light');
  assert.equal(darkFrames.length, WAVE_KEYFRAME_COUNT + 1);
  assert.equal(lightFrames.length, WAVE_KEYFRAME_COUNT + 1);
  const sig = (d: string) => d.replace(/[^MLZ]/g, '');
  const expectedSig = `M${'L'.repeat(WAVE_SAMPLES + 2)}Z`;
  assert.equal(sig(darkFrames[0]), expectedSig);
  assert.equal(sig(darkFrames[Math.floor(darkFrames.length / 2)]), expectedSig);
  assert.equal(sig(darkFrames[darkFrames.length - 1]), expectedSig);
  assert.equal(sig(lightFrames[Math.floor(lightFrames.length / 2)]), expectedSig);

  // Particle emitter spawns along the crest and physics loop ages & expires them cleanly
  const pool: WaveParticle[] = [];
  let seed = 0.13;
  const deterministicRand = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  spawnCrestParticles(pool, 20, 0.5, geom, 'dark', 100, deterministicRand);
  assert.equal(pool.length, 20);
  const y0 = pool[0].y;
  stepWaveParticles(pool, 0.016, 'dark');
  assert.notEqual(pool[0].y, y0);

  // Advance enough time for all particles to expire
  for (let i = 0; i < 60; i++) {
    stepWaveParticles(pool, 0.04, 'dark');
  }
  assert.equal(pool.length, 0);
});
