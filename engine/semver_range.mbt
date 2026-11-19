///|
priv struct PartialSemVer {
  major : Int32?
  minor : Int32?
  patch : Int32?
  pre : String?
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
fn parse_semver_uint(text : String) -> Int32? {
  if text == "" {
    return None
  }
  if text.length() > 1 && text[0] == '0' {
    return None
  }
  let mut acc : Int32 = 0
  for ch in text.to_array() {
    if ch < '0' || ch > '9' {
      return None
    }
    if acc > 214748364 {
      return None
    }
    acc = acc * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(acc)
}

///|
fn is_wildcard_part(part : String) -> Bool {
  part == "*" || part == "x" || part == "X"
}

///|
fn parse_partial_semver(
  raw : String,
) -> PartialSemVer raise @model.MoonsetError {
  let mut text = raw.trim().to_owned()
  if text.has_prefix("v") || text.has_prefix("V") {
    text = text[1:].to_owned()
  }
  if text == "" {
    invalid("Empty version in range: " + raw, code="invalid-version")
  }
  if is_wildcard_part(text) {
    return { major: None, minor: None, patch: None, pre: None, }
  }
  // Strip build metadata (+...)
  let without_build = match text.find("+") {
    Some(idx) => {
      let build = text[idx + 1:].to_owned()
      if build == "" {
        invalid("Empty build metadata in range: " + raw, code="invalid-version")
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
  let major : Int32? = if is_wildcard_part(parts[0]) {
    None
  } else {
    match parse_semver_uint(parts[0]) {
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
    None
  } else {
    match parse_semver_uint(parts[1]) {
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
    None
  } else {
    match parse_semver_uint(parts[2]) {
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
  { major, minor, patch, pre, }
}

///|
fn semver_from_parts(
  major : Int32,
  minor : Int32,
  patch : Int32,
  pre? : String,
) -> @semver.SemVer raise @model.MoonsetError {
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
    (Some(ma), None, _) => "\{ma}"
    (Some(ma), Some(mi), None) => "\{ma}.\{mi}"
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
  for part in branch.split(" ") {
    let t = part.trim().to_owned()
    if t != "" {
      raw_tokens.push(t)
    }
  }
  if raw_tokens.is_empty() {
    invalid("Empty npm comparator set", code="invalid-version")
  }
  // Merge standalone operators like ">=" followed by "1.0.0"
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
    let left = parse_partial_semver(tokens[0])
    let right = parse_partial_semver(tokens[2])
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
    let ver = parse_partial_semver(rest)
    comparators.push({ op, ver, })
  }
  { is_hyphen: false, hyphen_left: None, hyphen_right: None, comparators, }
}

///|
fn parse_cargo_branch(
  branch : String,
) -> SemVerBranch raise @model.MoonsetError {
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
    if rest == "" || rest.contains(" ") {
      invalid(
        "Invalid Cargo version comparator: " + part,
        code="invalid-version",
      )
    }
    let ver = parse_partial_semver(rest)
    comparators.push({ op, ver, })
  }
  { is_hyphen: false, hyphen_left: None, hyphen_right: None, comparators, }
}

///|
fn caret_bounds(
  v : PartialSemVer,
) -> (@semver.SemVer, @semver.SemVer?) raise @model.MoonsetError {
  match (v.major, v.minor, v.patch) {
    (None, _, _) => (semver_from_parts(0, 0, 0), None)
    (Some(ma), None, _) =>
      (
        semver_from_parts(ma, 0, 0),
        Some(semver_from_parts(ma + 1, 0, 0, pre="0")),
      )
    (Some(ma), Some(mi), None) => {
      let lower = semver_from_parts(ma, mi, 0)
      let upper = if ma == 0 {
        semver_from_parts(0, mi + 1, 0, pre="0")
      } else {
        semver_from_parts(ma + 1, 0, 0, pre="0")
      }
      (lower, Some(upper))
    }
    (Some(ma), Some(mi), Some(pa)) => {
      let lower = semver_from_parts(ma, mi, pa, pre?=v.pre)
      let upper = if ma > 0 {
        semver_from_parts(ma + 1, 0, 0, pre="0")
      } else if mi > 0 {
        semver_from_parts(0, mi + 1, 0, pre="0")
      } else {
        semver_from_parts(0, 0, pa + 1, pre="0")
      }
      (lower, Some(upper))
    }
  }
}

///|
fn tilde_bounds(
  v : PartialSemVer,
) -> (@semver.SemVer, @semver.SemVer?) raise @model.MoonsetError {
  match (v.major, v.minor, v.patch) {
    (None, _, _) => (semver_from_parts(0, 0, 0), None)
    (Some(ma), None, _) =>
      (
        semver_from_parts(ma, 0, 0),
        Some(semver_from_parts(ma + 1, 0, 0, pre="0")),
      )
    (Some(ma), Some(mi), None) =>
      (
        semver_from_parts(ma, mi, 0),
        Some(semver_from_parts(ma, mi + 1, 0, pre="0")),
      )
    (Some(ma), Some(mi), Some(pa)) =>
      (
        semver_from_parts(ma, mi, pa, pre?=v.pre),
        Some(semver_from_parts(ma, mi + 1, 0, pre="0")),
      )
  }
}

///|
fn comparator_matches(
  ecosystem : String,
  comp : SemVerComparator,
  actual : @semver.SemVer,
) -> Bool raise @model.MoonsetError {
  let v = comp.ver
  let op = comp.op
  if op == "^" || (ecosystem == "cargo" && op == "" && v.major is Some(_)) {
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
        let high = semver_from_parts(ma + 1, 0, 0, pre="0")
        return actual.compare(low) >= 0 && actual.compare(high) < 0
      }
      (Some(ma), Some(mi), None) => {
        let low = semver_from_parts(ma, mi, 0)
        let high = semver_from_parts(ma, mi + 1, 0, pre="0")
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
        return actual.compare(semver_from_parts(ma + 1, 0, 0)) >= 0
      (Some(ma), Some(mi), None) =>
        return actual.compare(semver_from_parts(ma, mi + 1, 0)) >= 0
      (Some(ma), Some(mi), Some(pa)) =>
        return actual.compare(semver_from_parts(ma, mi, pa, pre?=v.pre)) > 0
    }
  }
  if op == "<=" {
    match (v.major, v.minor, v.patch) {
      (None, _, _) => return true
      (Some(ma), None, _) =>
        return actual.compare(semver_from_parts(ma + 1, 0, 0, pre="0")) < 0
      (Some(ma), Some(mi), None) =>
        return actual.compare(semver_from_parts(ma, mi + 1, 0, pre="0")) < 0
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
  actual : @semver.SemVer,
) -> Bool {
  match (v.major, v.minor, v.patch, v.pre) {
    (Some(ma), Some(mi), Some(pa), Some(_)) =>
      ma == actual.major && mi == actual.minor && pa == actual.patch
    _ => false
  }
}

///|
fn branch_matches(
  ecosystem : String,
  branch : SemVerBranch,
  actual : @semver.SemVer,
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
  let all_wild = branch.comparators.all(c => {
    (c.op == "" || c.op == "=") && c.ver.major is None
  })
  if !all_wild && actual.is_prerelease() {
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
  ecosystem : String,
  requirement : String,
) -> Array[SemVerBranch] raise @model.MoonsetError {
  let raw_branches = split_disjunction(requirement)
  let parsed : Array[SemVerBranch] = []
  for b in raw_branches {
    if ecosystem == "npm" {
      parsed.push(parse_npm_branch(b))
    } else {
      parsed.push(parse_cargo_branch(b))
    }
  }
  parsed
}

///|
/// Validate that a dependency requirement string is syntactically valid for the ecosystem.
pub fn validate_ecosystem_range(
  ecosystem : String,
  requirement : String,
) -> Unit raise @model.MoonsetError {
  let trimmed = requirement.trim().to_owned()
  if ecosystem == "moonbit" {
    ignore(parse_version(trimmed))
    return
  }
  if ecosystem == "npm" {
    if is_npm_protocol(trimmed) {
      return
    }
    ignore(parse_ecosystem_branches("npm", trimmed))
    return
  }
  if trimmed == "*" {
    return
  }
  ignore(parse_ecosystem_branches("cargo", trimmed))
}

///|
/// Return true when `target` satisfies `requirement` under the given ecosystem's SemVer range semantics.
pub fn matches_ecosystem_range(
  ecosystem : String,
  requirement : String,
  target : String,
) -> Bool raise @model.MoonsetError {
  let trimmed = requirement.trim().to_owned()
  if ecosystem == "moonbit" {
    return version_matches(trimmed, target)
  }
  if ecosystem == "npm" {
    if is_npm_protocol(trimmed) {
      return true
    }
    let actual = parse_version(target)
    let branches = parse_ecosystem_branches("npm", trimmed)
    for branch in branches {
      if branch_matches("npm", branch, actual) {
        return true
      }
    }
    return false
  }
  if trimmed == "*" {
    ignore(parse_version(target))
    return true
  }
  let actual = parse_version(target)
  let branches = parse_ecosystem_branches("cargo", trimmed)
  for branch in branches {
    if branch_matches("cargo", branch, actual) {
      return true
    }
  }
  false
}

///|
fn next_exclusive_upper(target : @semver.SemVer) -> String {
  if target.major > 0 {
    "\{target.major + 1}.0.0"
  } else if target.minor > 0 {
    "0.\{target.minor + 1}.0"
  } else {
    "0.0.\{target.patch + 1}"
  }
}

///|
fn render_branch(ecosystem : String, branch : SemVerBranch) -> String {
  if branch.is_hyphen {
    let l = branch.hyphen_left.map(partial_to_string).unwrap_or("0.0.0")
    let r = branch.hyphen_right.map(partial_to_string).unwrap_or("0.0.0")
    return l + " - " + r
  }
  let sep = if ecosystem == "cargo" { ", " } else { " " }
  branch.comparators.map(c => c.op + partial_to_string(c.ver)).join(sep)
}

///|
fn rewrite_branch_for_target(
  ecosystem : String,
  branch : SemVerBranch,
  target : String,
  parsed_target : @semver.SemVer,
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
    let rewritten = match comp.op {
      "^" => "^" + target
      "~" => "~" + target
      "=" => "=" + target
      ">=" => ">=" + target
      ">" => ">=" + target
      "<=" => "<=" + target
      "<" => "<" + next_exclusive_upper(parsed_target)
      "" => if comp.ver.major is None { "*" } else { target }
      _ => target
    }
    return rewritten
  }
  // Multi-comparator conjunction (e.g. ">=1.0.0 <2.0.0" or ">=1.0.0, <2.0.0")
  let sep = if ecosystem == "cargo" { ", " } else { " " }
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
/// preserving operator style and compound bounds whenever possible.
pub fn rewrite_ecosystem_range(
  ecosystem : String,
  requirement : String,
  target : String,
) -> String raise @model.MoonsetError {
  if ecosystem == "moonbit" {
    return target
  }
  let trimmed = requirement.trim().to_owned()
  if trimmed == "*" || (ecosystem == "npm" && is_npm_protocol(trimmed)) {
    return trimmed
  }
  let parsed_target = parse_version(target)
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
  // Disjunction (`||`): if any branch already matches `target`, update that branch;
  // otherwise append a compatible caret branch for `target`.
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
