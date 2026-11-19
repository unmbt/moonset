// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "unmbt/moonset"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/moonset"

license = "MIT"

keywords = [
  "cli",
  "changeset",
  "versioning",
  "changelog",
  "workspace",
  "moonbit",
]

preferred_target = "native"

description = "Spec-driven MoonBit workspace release planning"

import {
  "mizchi/tui@0.10.2",
  "mizchi/crater-core@0.19.0",
  "mizchi/crater-layout@0.19.1",
  "mizchi/css@0.7.4",
  "mizchi/syntree@0.2.4",
  "mizchi/tui-terminal-buffer@0.1.4",
  "mizchi/semver@0.1.2",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.7",
  "unmbt/moon-manifest@0.2.0-alpha.2",
}
