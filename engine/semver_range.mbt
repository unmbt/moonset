///|
priv struct PartialSemVer {
  major : Int32?
  minor : Int32?
  patch : Int32?
  pre : String?
  has_wildcard : Bool
}

///|
priv struct SemVerComparator {
  op : String
  ver : PartialSemVer
}

///|
priv struct SemVerBranch {
  is_hyphen : Bool
  hyphen_left : PartialSemVer?
  hyphen_right : PartialSemVer?
  comparators : Array[SemVerComparator]
}

///|
fn is_wildcard_part(part : String) -> Bool {
  part == "*" || part == "x" || part == "X"
}

///|
/// Return true when an npm dependency string uses a non-SemVer external/local
/// protocol (e.g. `catalog:`, `npm:`, `github:`, `git+`, `file:`, `link:`, `latest`, `""`).
pub fn is_npm_external_protocol(requirement : String) -> Bool {
  let t = requirement.trim().to_owned()
  t == "" ||
  t == "latest" ||
  t == "next" ||
  t.has_prefix("catalog:") ||
  t.has_prefix("npm:") ||
  t.has_prefix("file:") ||
  t.has_prefix("link:") ||
  t.has_prefix("portal:") ||
  t.has_prefix("patch:") ||
  t.has_prefix("jsr:") ||
  t.has_prefix("github:") ||
  t.has_prefix("gitlab:") ||
  t.has_prefix("bitbucket:") ||
  t.has_prefix("git+") ||
  t.has_prefix("git://") ||
  t.has_prefix("http://") ||
  t.has_prefix("https://")
}

///|
/// Return true when an npm requirement uses the pnpm/yarn `workspace:` protocol.
pub fn is_workspace_protocol(requirement : String) -> Bool {
  requirement.trim().has_prefix("workspace:")
}

///|
/// Resolve a `workspace:` requirement into an effective SemVer range given the
/// producer's current version, returning `(effective_range, is_shorthand)`.
/// - `workspace:*` -> `(current_version, true)`
/// - `workspace:^` -> `("^" + current_version, true)`
/// - `workspace:~` -> `("~" + current_version, true)`
/// - `workspace:<range>` -> `(<range>, false)`
fn resolve_workspace_protocol(
  requirement : String,
  producer_current_version : String?,
) -> (String, Bool) raise @model.MoonsetError {
  let trimmed = requirement.trim().to_owned()
  let inner = trimmed[10:].trim().to_owned()
  if inner == "" {
    invalid("Empty workspace: protocol range", code="invalid-version")
  }
  if inner == "*" {
    return (producer_current_version.unwrap_or("*"), true)
  }
  if inner == "^" {
    return (
      match producer_current_version {
        Some(v) => "^" + v
        None => "*"
      },
      true,
    )
  }
  if inner == "~" {
    return (
      match producer_current_version {
        Some(v) => "~" + v
        None => "*"
      },
      true,
    )
  }
  // Relative path form `workspace:../pkg`
  if inner.has_prefix(".") || inner.has_prefix("/") {
    return (producer_current_version.unwrap_or("*"), true)
  }
  // Explicit range like `workspace:^1.0.0`
  ignore(parse_ecosystem_branches(@model.Npm, inner))
  (inner, false)
}

///|
fn parse_partial_semver(
  raw : String,
  allow_v_prefix~ : Bool = true,
) -> PartialSemVer raise @model.MoonsetError {
  let mut text = raw.trim().to_owned()
  if allow_v_prefix && (text.has_prefix("v") || text.has_prefix("V")) {
    text = text[1:].to_owned()
  }
  if text == "" {
    invalid("Empty version in range: " + raw, code="invalid-version")
  }
  if is_wildcard_part(text) {
    return {
      major: None,
      minor: None,
      patch: None,
      pre: None,
      has_wildcard: true,
    }
  }
  // Validate and strip build metadata (+...)
  let without_build = match text.find("+") {
    Some(idx) => {
      let build = text[idx + 1:].to_owned()
      if build == "" {
        invalid("Empty build metadata in range: " + raw, code="invalid-version")
      }
      for seg_view in build.split(".") {
        let seg = seg_view.to_owned()
        if seg == "" {
          invalid(
            "Invalid build metadata in range: " + raw,
            code="invalid-version",
          )
        }
        for ch in seg.to_array() {
          let ok = (ch >= '0' && ch <= '9') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            ch == '-'
          if !ok {
            invalid(
              "Invalid build metadata in range: " + raw,
              code="invalid-version",
            )
          }
        }
      }
      text[:idx].to_owned()
    }
    None => text
  }
  // Split optional prerelease (-...)
  let (core, pre) = match without_build.find("-") {
    Some(idx) => {
      let pre_str = without_build[idx + 1:].to_owned()
      if pre_str == "" {
        invalid("Empty prerelease in range: " + raw, code="invalid-version")
      }
      ignore(parse_version("0.0.0-" + pre_str))
      (without_build[:idx].to_owned(), Some(pre_str))
    }
    None => (without_build, None)
  }
  let parts = core.split(".").map(x => x.to_owned()).collect()
  if parts.is_empty() || parts.length() > 3 {
    invalid("Invalid SemVer range token: " + raw, code="invalid-version")
  }
  let mut has_wildcard = false
  let major : Int32? = if is_wildcard_part(parts[0]) {
    has_wildcard = true
    None
  } else {
    match parse_uint32_checked(parts[0]) {
      Some(v) => Some(v)
      None => {
        invalid(
          "Invalid major version in range: " + raw,
          code="invalid-version",
        )
        None
      }
    }
  }
  let minor : Int32? = if parts.length() < 2 {
    None
  } else if is_wildcard_part(parts[1]) {
    has_wildcard = true
    None
  } else {
    match parse_uint32_checked(parts[1]) {
      Some(v) => Some(v)
      None => {
        invalid(
          "Invalid minor version in range: " + raw,
          code="invalid-version",
        )
        None
      }
    }
  }
  let patch : Int32? = if parts.length() < 3 {
    None
  } else if is_wildcard_part(parts[2]) {
    has_wildcard = true
    None
  } else {
    match parse_uint32_checked(parts[2]) {
      Some(v) => Some(v)
      None => {
        invalid(
          "Invalid patch version in range: " + raw,
          code="invalid-version",
        )
        None
      }
    }
  }
  if major is None && (minor is Some(_) || patch is Some(_)) {
    invalid("Invalid wildcard version in range: " + raw, code="invalid-version")
  }
  if minor is None && patch is Some(_) {
    invalid("Invalid wildcard version in range: " + raw, code="invalid-version")
  }
  if pre is Some(_) && (major is None || minor is None || patch is None) {
    invalid(
      "Prerelease requires full major.minor.patch in range: " + raw,
      code="invalid-version",
    )
  }
  { major, minor, patch, pre, has_wildcard, }
}

///|
fn safe_inc_int(n : Int32) -> Int32 raise @model.MoonsetError {
  if n >= 2147483647 {
    invalid("SemVer component overflow", code="invalid-version")
  }
  n + 1
}

///|
fn semver_from_parts(
  major : Int32,
  minor : Int32,
  patch : Int32,
  pre? : String,
) -> SemVerParts raise @model.MoonsetError {
  let base = "\{major}.\{minor}.\{patch}"
  let full = match pre {
    Some(p) if p != "" => base + "-" + p
    _ => base
  }
  parse_version(full)
}

///|
fn partial_to_string(v : PartialSemVer) -> String {
  match (v.major, v.minor, v.patch) {
    (None, _, _) => "*"
    (Some(ma), None, _) => if v.has_wildcard { "\{ma}.*" } else { "\{ma}" }
    (Some(ma), Some(mi), None) =>
      if v.has_wildcard {
        "\{ma}.\{mi}.*"
      } else {
        "\{ma}.\{mi}"
      }
    (Some(ma), Some(mi), Some(pa)) =>
      match v.pre {
        Some(p) => "\{ma}.\{mi}.\{pa}-\{p}"
        None => "\{ma}.\{mi}.\{pa}"
      }
  }
}

///|
fn split_disjunction(raw : String) -> Array[String] raise @model.MoonsetError {
  let trimmed = raw.trim().to_owned()
  if trimmed == "" {
    invalid("Empty version requirement", code="invalid-version")
  }
  let branches : Array[String] = []
  let chars = trimmed.to_array()
  let current : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '|' {
      if i + 1 < chars.length() && chars[i + 1] == '|' {
        let part = String::from_array(current).trim().to_owned()
        if part == "" {
          invalid(
            "Empty branch in SemVer range: " + raw,
            code="invalid-version",
          )
        }
        branches.push(part)
        current.clear()
        i += 2
        continue
      } else {
        invalid(
          "Invalid '|' operator in SemVer range (use '||'): " + raw,
          code="invalid-version",
        )
      }
    }
    current.push(chars[i])
    i += 1
  }
  let tail = String::from_array(current).trim().to_owned()
  if tail == "" {
    invalid("Empty branch in SemVer range: " + raw, code="invalid-version")
  }
  branches.push(tail)
  branches
}

///|
fn extract_operator(token : String) -> (String, String) {
  let t = token.trim().to_owned()
  if t.has_prefix(">=") {
    (">=", t[2:].trim().to_owned())
  } else if t.has_prefix("<=") {
    ("<=", t[2:].trim().to_owned())
  } else if t.has_prefix(">") {
    (">", t[1:].trim().to_owned())
  } else if t.has_prefix("<") {
    ("<", t[1:].trim().to_owned())
  } else if t.has_prefix("=") {
    ("=", t[1:].trim().to_owned())
  } else if t.has_prefix("^") {
    ("^", t[1:].trim().to_owned())
  } else if t.has_prefix("~") {
    ("~", t[1:].trim().to_owned())
  } else {
    ("", t)
  }
}

///|
fn tokenize_npm_branch(
  branch : String,
) -> Array[String] raise @model.MoonsetError {
  let raw_tokens : Array[String] = []
  let current : Array[Char] = []
  for ch in branch.to_array() {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      if !current.is_empty() {
        raw_tokens.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(ch)
    }
  }
  if !current.is_empty() {
    raw_tokens.push(String::from_array(current))
  }
  if raw_tokens.is_empty() {
    invalid("Empty npm comparator set", code="invalid-version")
  }
  let merged : Array[String] = []
  let mut i = 0
  while i < raw_tokens.length() {
    let tok = raw_tokens[i]
    if [">=", "<=", ">", "<", "=", "^", "~"].contains(tok) {
      if i + 1 >= raw_tokens.length() {
        invalid(
          "Dangling operator in npm version range: " + branch,
          code="invalid-version",
        )
      }
      merged.push(tok + raw_tokens[i + 1])
      i += 2
    } else {
      merged.push(tok)
      i += 1
    }
  }
  merged
}

///|
fn parse_npm_branch(branch : String) -> SemVerBranch raise @model.MoonsetError {
  let tokens = tokenize_npm_branch(branch)
  if tokens.length() == 3 && tokens[1] == "-" {
    let left = parse_partial_semver(tokens[0], allow_v_prefix=true)
    let right = parse_partial_semver(tokens[2], allow_v_prefix=true)
    return {
      is_hyphen: true,
      hyphen_left: Some(left),
      hyphen_right: Some(right),
      comparators: [],
    }
  }
  let comparators : Array[SemVerComparator] = []
  for tok in tokens {
    if tok == "-" {
      invalid("Malformed hyphen range: " + branch, code="invalid-version")
    }
    let (op, rest) = extract_operator(tok)
    if rest == "" {
      invalid(
        "Missing version after operator in: " + branch,
        code="invalid-version",
      )
    }
    let ver = parse_partial_semver(rest, allow_v_prefix=true)
    comparators.push({ op, ver, })
  }
  { is_hyphen: false, hyphen_left: None, hyphen_right: None, comparators, }
}

///|
fn parse_cargo_branch(
  branch : String,
) -> SemVerBranch raise @model.MoonsetError {
  if branch.contains("|") {
    invalid(
      "Cargo version requirements do not support '||' disjunctions: " + branch,
      code="invalid-version",
    )
  }
  let parts = branch.split(",").map(x => x.trim().to_owned()).collect()
  if parts.is_empty() {
    invalid("Empty Cargo version requirement", code="invalid-version")
  }
  let comparators : Array[SemVerComparator] = []
  for part in parts {
    if part == "" {
      invalid(
        "Empty comparator in Cargo version requirement: " + branch,
        code="invalid-version",
      )
    }
    let (op, rest) = extract_operator(part)
    if rest == "" || rest.contains(" ") || rest.contains("\t") {
      invalid(
        "Invalid Cargo version comparator: " + part,
        code="invalid-version",
      )
    }
    let ver = parse_partial_semver(rest, allow_v_prefix=false)
    comparators.push({ op, ver, })
  }
  { is_hyphen: false, hyphen_left: None, hyphen_right: None, comparators, }
}

///|
fn caret_bounds(
  v : PartialSemVer,
) -> (SemVerParts, SemVerParts?) raise @model.MoonsetError {
  match (v.major, v.minor, v.patch) {
    (None, _, _) => (semver_from_parts(0, 0, 0), None)
    (Some(ma), None, _) =>
      (
        semver_from_parts(ma, 0, 0),
        Some(semver_from_parts(safe_inc_int(ma), 0, 0, pre="0")),
      )
    (Some(ma), Some(mi), None) => {
      let lower = semver_from_parts(ma, mi, 0)
      let upper = if ma == 0 {
        semver_from_parts(0, safe_inc_int(mi), 0, pre="0")
      } else {
        semver_from_parts(safe_inc_int(ma), 0, 0, pre="0")
      }
      (lower, Some(upper))
    }
    (Some(ma), Some(mi), Some(pa)) => {
      let lower = semver_from_parts(ma, mi, pa, pre?=v.pre)
      let upper = if ma > 0 {
        semver_from_parts(safe_inc_int(ma), 0, 0, pre="0")
      } else if mi > 0 {
        semver_from_parts(0, safe_inc_int(mi), 0, pre="0")
      } else {
        semver_from_parts(0, 0, safe_inc_int(pa), pre="0")
      }
      (lower, Some(upper))
    }
  }
}

///|
fn tilde_bounds(
  v : PartialSemVer,
) -> (SemVerParts, SemVerParts?) raise @model.MoonsetError {
  match (v.major, v.minor, v.patch) {
    (None, _, _) => (semver_from_parts(0, 0, 0), None)
    (Some(ma), None, _) =>
      (
        semver_from_parts(ma, 0, 0),
        Some(semver_from_parts(safe_inc_int(ma), 0, 0, pre="0")),
      )
    (Some(ma), Some(mi), None) =>
      (
        semver_from_parts(ma, mi, 0),
        Some(semver_from_parts(ma, safe_inc_int(mi), 0, pre="0")),
      )
    (Some(ma), Some(mi), Some(pa)) =>
      (
        semver_from_parts(ma, mi, pa, pre?=v.pre),
        Some(semver_from_parts(ma, safe_inc_int(mi), 0, pre="0")),
      )
  }
}

///|
fn comparator_matches(
  ecosystem : @model.Ecosystem,
  comp : SemVerComparator,
  actual : SemVerParts,
) -> Bool raise @model.MoonsetError {
  let v = comp.ver
  let op = comp.op
  // In Cargo, bare `1.2` is caret `^1.2`, whereas wildcard `1.2.*` is `>=1.2.0, <1.3.0`.
  if op == "^" ||
    (
      ecosystem == @model.Cargo &&
      op == "" &&
      v.major is Some(_) &&
      !v.has_wildcard
    ) {
    let (lower, upper) = caret_bounds(v)
    let low_ok = actual.compare(lower) >= 0
    let high_ok = match upper {
      Some(u) => actual.compare(u) < 0
      None => true
    }
    return low_ok && high_ok
  }
  if op == "~" {
    let (lower, upper) = tilde_bounds(v)
    let low_ok = actual.compare(lower) >= 0
    let high_ok = match upper {
      Some(u) => actual.compare(u) < 0
      None => true
    }
    return low_ok && high_ok
  }
  if op == "=" || op == "" {
    match (v.major, v.minor, v.patch) {
      (None, _, _) => return true
      (Some(ma), None, _) => {
        let low = semver_from_parts(ma, 0, 0)
        let high = semver_from_parts(safe_inc_int(ma), 0, 0, pre="0")
        return actual.compare(low) >= 0 && actual.compare(high) < 0
      }
      (Some(ma), Some(mi), None) => {
        let low = semver_from_parts(ma, mi, 0)
        let high = semver_from_parts(ma, safe_inc_int(mi), 0, pre="0")
        return actual.compare(low) >= 0 && actual.compare(high) < 0
      }
      (Some(ma), Some(mi), Some(pa)) => {
        let expected = semver_from_parts(ma, mi, pa, pre?=v.pre)
        return actual.compare(expected) == 0
      }
    }
  }
  if op == ">=" {
    let low = match (v.major, v.minor, v.patch) {
      (None, _, _) => semver_from_parts(0, 0, 0)
      (Some(ma), None, _) => semver_from_parts(ma, 0, 0)
      (Some(ma), Some(mi), None) => semver_from_parts(ma, mi, 0)
      (Some(ma), Some(mi), Some(pa)) =>
        semver_from_parts(ma, mi, pa, pre?=v.pre)
    }
    return actual.compare(low) >= 0
  }
  if op == ">" {
    match (v.major, v.minor, v.patch) {
      (None, _, _) => return false
      (Some(ma), None, _) =>
        return actual.compare(semver_from_parts(safe_inc_int(ma), 0, 0)) >= 0
      (Some(ma), Some(mi), None) =>
        return actual.compare(semver_from_parts(ma, safe_inc_int(mi), 0)) >= 0
      (Some(ma), Some(mi), Some(pa)) =>
        return actual.compare(semver_from_parts(ma, mi, pa, pre?=v.pre)) > 0
    }
  }
  if op == "<=" {
    match (v.major, v.minor, v.patch) {
      (None, _, _) => return true
      (Some(ma), None, _) =>
        return actual.compare(
            semver_from_parts(safe_inc_int(ma), 0, 0, pre="0"),
          ) <
          0
      (Some(ma), Some(mi), None) =>
        return actual.compare(
            semver_from_parts(ma, safe_inc_int(mi), 0, pre="0"),
          ) <
          0
      (Some(ma), Some(mi), Some(pa)) =>
        return actual.compare(semver_from_parts(ma, mi, pa, pre?=v.pre)) <= 0
    }
  }
  if op == "<" {
    match (v.major, v.minor, v.patch) {
      (None, _, _) => return false
      (Some(ma), None, _) =>
        return actual.compare(semver_from_parts(ma, 0, 0, pre="0")) < 0
      (Some(ma), Some(mi), None) =>
        return actual.compare(semver_from_parts(ma, mi, 0, pre="0")) < 0
      (Some(ma), Some(mi), Some(pa)) =>
        return actual.compare(semver_from_parts(ma, mi, pa, pre?=v.pre)) < 0
    }
  }
  false
}

///|
fn partial_matches_prerelease_tuple(
  v : PartialSemVer,
  actual : SemVerParts,
) -> Bool {
  match (v.major, v.minor, v.patch, v.pre) {
    (Some(ma), Some(mi), Some(pa), Some(_)) =>
      ma == actual.major && mi == actual.minor && pa == actual.patch
    _ => false
  }
}

///|
fn branch_matches(
  ecosystem : @model.Ecosystem,
  branch : SemVerBranch,
  actual : SemVerParts,
) -> Bool raise @model.MoonsetError {
  if branch.is_hyphen {
    guard (branch.hyphen_left, branch.hyphen_right) is (Some(left), Some(right)) else {
      return false
    }
    if actual.is_prerelease() &&
      !partial_matches_prerelease_tuple(left, actual) &&
      !partial_matches_prerelease_tuple(right, actual) {
      return false
    }
    return comparator_matches(ecosystem, { op: ">=", ver: left, }, actual) &&
      comparator_matches(ecosystem, { op: "<=", ver: right, }, actual)
  }
  // Neither npm node-semver nor Cargo semver allows `*`/`x` to match prereleases.
  if actual.is_prerelease() {
    let allows_pre = branch.comparators.any(c => {
      partial_matches_prerelease_tuple(c.ver, actual)
    })
    if !allows_pre {
      return false
    }
  }
  for comp in branch.comparators {
    if !comparator_matches(ecosystem, comp, actual) {
      return false
    }
  }
  true
}

///|
fn parse_ecosystem_branches(
  ecosystem : @model.Ecosystem,
  requirement : String,
) -> Array[SemVerBranch] raise @model.MoonsetError {
  if ecosystem == @model.Cargo {
    return [parse_cargo_branch(requirement.trim().to_owned())]
  }
  let raw_branches = split_disjunction(requirement)
  let parsed : Array[SemVerBranch] = []
  for b in raw_branches {
    parsed.push(parse_npm_branch(b))
  }
  parsed
}

///|
/// Validate that a dependency requirement string is syntactically valid for the ecosystem.
pub fn validate_ecosystem_range(
  ecosystem : @model.Ecosystem,
  requirement : String,
) -> Unit raise @model.MoonsetError {
  let trimmed = requirement.trim().to_owned()
  match ecosystem {
    @model.MoonBit => ignore(parse_version(trimmed))
    @model.Npm => {
      if is_npm_external_protocol(trimmed) {
        return
      }
      if is_workspace_protocol(trimmed) {
        ignore(resolve_workspace_protocol(trimmed, None))
        return
      }
      ignore(parse_ecosystem_branches(@model.Npm, trimmed))
    }
    @model.Cargo => {
      if trimmed == "*" {
        return
      }
      ignore(parse_ecosystem_branches(@model.Cargo, trimmed))
    }
  }
}

///|
/// Return true when `target` satisfies `requirement` under the given ecosystem's SemVer range semantics.
pub fn matches_ecosystem_range(
  ecosystem : @model.Ecosystem,
  requirement : String,
  target : String,
  producer_current_version? : String,
) -> Bool raise @model.MoonsetError {
  let trimmed = requirement.trim().to_owned()
  match ecosystem {
    @model.MoonBit => version_matches(trimmed, target)
    @model.Npm => {
      if is_npm_external_protocol(trimmed) {
        return true
      }
      let effective = if is_workspace_protocol(trimmed) {
        let (resolved, _) = resolve_workspace_protocol(
          trimmed, producer_current_version,
        )
        resolved
      } else {
        trimmed
      }
      let actual = parse_version(target)
      let branches = parse_ecosystem_branches(@model.Npm, effective)
      for branch in branches {
        if branch_matches(@model.Npm, branch, actual) {
          return true
        }
      }
      false
    }
    @model.Cargo => {
      let actual = parse_version(target)
      if trimmed == "*" {
        return !actual.is_prerelease()
      }
      let branches = parse_ecosystem_branches(@model.Cargo, trimmed)
      for branch in branches {
        if branch_matches(@model.Cargo, branch, actual) {
          return true
        }
      }
      false
    }
  }
}

///|
fn next_exclusive_upper(
  target : SemVerParts,
) -> String raise @model.MoonsetError {
  if target.major > 0 {
    "\{safe_inc_int(target.major)}.0.0"
  } else if target.minor > 0 {
    "0.\{safe_inc_int(target.minor)}.0"
  } else {
    "0.0.\{safe_inc_int(target.patch)}"
  }
}

///|
fn render_branch(ecosystem : @model.Ecosystem, branch : SemVerBranch) -> String {
  if branch.is_hyphen {
    let l = branch.hyphen_left.map(partial_to_string).unwrap_or("0.0.0")
    let r = branch.hyphen_right.map(partial_to_string).unwrap_or("0.0.0")
    return l + " - " + r
  }
  let sep = if ecosystem == @model.Cargo { ", " } else { " " }
  branch.comparators.map(c => c.op + partial_to_string(c.ver)).join(sep)
}

///|
fn rewrite_branch_for_target(
  ecosystem : @model.Ecosystem,
  branch : SemVerBranch,
  target : String,
  parsed_target : SemVerParts,
) -> String raise @model.MoonsetError {
  if branch.is_hyphen {
    guard (branch.hyphen_left, branch.hyphen_right) is (Some(left), Some(right)) else {
      return target
    }
    let right_ok = comparator_matches(
      ecosystem,
      { op: "<=", ver: right, },
      parsed_target,
    )
    if right_ok {
      return target + " - " + partial_to_string(right)
    } else {
      return partial_to_string(left) + " - " + target
    }
  }
  if branch.comparators.length() == 1 {
    let comp = branch.comparators[0]
    return match comp.op {
      "^" => "^" + target
      "~" => "~" + target
      "=" => "=" + target
      ">=" => ">=" + target
      ">" => ">=" + target
      "<=" => "<=" + target
      "<" => "<" + next_exclusive_upper(parsed_target)
      "" =>
        if comp.ver.major is None {
          if parsed_target.is_prerelease() {
            target
          } else {
            "*"
          }
        } else {
          target
        }
      _ => target
    }
  }
  let sep = if ecosystem == @model.Cargo { ", " } else { " " }
  let parts : Array[String] = []
  let mut updated_lower = false
  for comp in branch.comparators {
    if comp.op == ">=" || comp.op == ">" || comp.op == "^" || comp.op == "~" {
      let next_op = if comp.op == ">" { ">=" } else { comp.op }
      parts.push(next_op + target)
      updated_lower = true
    } else if comp.op == "<" {
      if comparator_matches(ecosystem, comp, parsed_target) {
        parts.push("<" + partial_to_string(comp.ver))
      } else {
        parts.push("<" + next_exclusive_upper(parsed_target))
      }
    } else if comp.op == "<=" {
      if comparator_matches(ecosystem, comp, parsed_target) {
        parts.push("<=" + partial_to_string(comp.ver))
      } else {
        parts.push("<=" + target)
      }
    } else if comp.op == "=" {
      parts.push("=" + target)
      updated_lower = true
    } else {
      parts.push(target)
      updated_lower = true
    }
  }
  if !updated_lower {
    parts.push(">=" + target)
  }
  parts.join(sep)
}

///|
/// Rewrite a dependency range so that it targets and satisfies `target` while
/// preserving operator style, `workspace:` protocol prefixes, and compound bounds.
/// When `exact_pin` is true (used for snapshot releases), pins to exact `target`.
pub fn rewrite_ecosystem_range(
  ecosystem : @model.Ecosystem,
  requirement : String,
  target : String,
  exact_pin~ : Bool = false,
) -> String raise @model.MoonsetError {
  if ecosystem == @model.MoonBit {
    return target
  }
  let trimmed = requirement.trim().to_owned()
  if ecosystem == @model.Npm && is_npm_external_protocol(trimmed) {
    return trimmed
  }
  if ecosystem == @model.Npm && is_workspace_protocol(trimmed) {
    let (inner, is_shorthand) = resolve_workspace_protocol(trimmed, None)
    if is_shorthand {
      // Shorthand `workspace:*`, `workspace:^`, `workspace:~` stay untouched in package.json
      // (pnpm resolves them at pack/publish time).
      return trimmed
    }
    if exact_pin {
      return "workspace:" + target
    }
    return "workspace:" + rewrite_ecosystem_range(@model.Npm, inner, target)
  }
  if exact_pin {
    return target
  }
  let parsed_target = parse_version(target)
  if trimmed == "*" {
    return if parsed_target.is_prerelease() { target } else { "*" }
  }
  let branches = parse_ecosystem_branches(ecosystem, trimmed)
  if branches.length() == 1 {
    let candidate = rewrite_branch_for_target(
      ecosystem,
      branches[0],
      target,
      parsed_target,
    )
    if matches_ecosystem_range(ecosystem, candidate, target) {
      return candidate
    }
    return "^" + target
  }
  let mut matched_idx : Int32? = None
  for idx, branch in branches {
    if branch_matches(ecosystem, branch, parsed_target) {
      matched_idx = Some(idx)
    }
  }
  let rendered : Array[String] = []
  match matched_idx {
    Some(target_idx) =>
      for idx, branch in branches {
        if idx == target_idx {
          rendered.push(
            rewrite_branch_for_target(ecosystem, branch, target, parsed_target),
          )
        } else {
          rendered.push(render_branch(ecosystem, branch))
        }
      }
    None => {
      for branch in branches {
        rendered.push(render_branch(ecosystem, branch))
      }
      rendered.push("^" + target)
    }
  }
  let combined = rendered.join(" || ")
  if matches_ecosystem_range(ecosystem, combined, target) {
    combined
  } else {
    "^" + target
  }
}
