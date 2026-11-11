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

version = "0.1.0-alpha.1"

readme = "README.mbt.md"

repository = "https://github.com/unmbt/moonset"

license = "MIT"

keywords = [ ]

preferred_target = "native"

description = "Spec-driven MoonBit workspace release planning"

import {
  "mizchi/semver@0.1.2",
  "mizchi/tui@0.10.2",
  "unmbt/moon-manifest@0.2.0-alpha.2",
}
