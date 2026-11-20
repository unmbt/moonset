///|
priv struct Reader {
  root : String
  git_root : String?
  head : String?
  use_git_tree : Bool
  tree : Map[String, String]
  sources : Map[String, String]
  visited_dirs : Map[String, Bool]
}

///|
fn slash(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn join(root : String, path : String) -> String {
  (if @path.Path(path).is_absolute() {
    @path.Path(path)
  } else {
    @path.Path(root).join(@path.Path(path))
  })
  .normalize()
  .to_string()
}

///|
fn parent(path : String) -> String {
  @path.Path(path).dirname().to_string()
}

///|
fn norm_cmp_path(path : String) -> String {
  let s = slash(path)
  let trimmed = if s.has_prefix("//?/") { s[4:].to_owned() } else { s }
  // Normalize Windows drive letter case (`d:/...` == `D:/...`)
  if trimmed.length() >= 2 && trimmed[1] == ':' {
    trimmed[:1].to_owned().to_upper() + trimmed[1:].to_owned()
  } else {
    trimmed
  }
}

///|
fn fail_input(
  message : String,
  path~ : String = "",
  code~ : String = "invalid-workspace",
) -> Unit raise @model.MoonsetError {
  raise @model.Invalid(@model.diagnostic(code, message, path~))
}

///|
/// Relative paths are confined lexically before any filesystem access.
fn relative(root : String, path : String) -> String raise {
  let result = slash(
    @path.Path(norm_cmp_path(path))
    .relative(base=@path.Path(norm_cmp_path(root)))
    .to_string(),
  )
  if result == ".." ||
    result.has_prefix("../") ||
    @path.Path(result).is_absolute() {
    fail_input("Path escapes release domain", path~)
  }
  if result == "." {
    ""
  } else {
    result
  }
}

///|
async fn git(root : String, args : Array[String]) -> String {
  let output = @shell.Cmd("git", args, cwd=root).output()
  if output.exit_code() != 0 {
    raise @model.Io("git " + args[0] + ": " + output.stderr())
  }
  output.stdout()
}

///|
fn parse_decimal_int(text : String) -> Int32? {
  if text == "" {
    return None
  }
  let mut acc : Int32 = 0
  for ch in text.to_array() {
    if ch < '0' || ch > '9' {
      return None
    }
    acc = acc * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(acc)
}

///|
async fn Reader::prefetch(self : Reader, paths : Array[String]) -> Unit {
  if !self.use_git_tree {
    return
  }
  guard (self.git_root, self.head) is (Some(root), Some(head)) else { return }
  let pending : Array[(String, String)] = []
  let seen_repo : Map[String, Bool] = Map([])
  for path in paths {
    let domain_path = relative(self.root, join(self.root, path))
    if self.sources.contains(domain_path) {
      continue
    }
    let repo_path = relative(root, join(self.root, domain_path))
    if self.tree.get(repo_path) is Some("100644" | "100755") &&
      !seen_repo.contains(repo_path) {
      seen_repo[repo_path] = true
      pending.push((domain_path, repo_path))
    }
  }
  if pending.is_empty() {
    return
  }
  let mut start = 0
  while start < pending.length() {
    let end = if start + 200 < pending.length() {
      start + 200
    } else {
      pending.length()
    }
    let chunk : Array[(String, String)] = []
    let lines : Array[String] = []
    for i in start..<end {
      let item = pending[i]
      chunk.push(item)
      lines.push(head + ":" + item.1)
    }
    let output = @shell.Cmd(
      "git",
      ["cat-file", "--batch"],
      cwd=root,
      stdin=@shell.Stdin::Text(lines.join("\n") + "\n"),
    ).output(max_output_bytes=33554432)
    if output.exit_code() != 0 {
      raise @model.Io("git cat-file --batch: " + output.stderr())
    }
    let bytes = output.stdout_bytes()
    let mut pos = 0
    for item in chunk {
      let domain_path = item.0
      let mut nl = pos
      while nl < bytes.length() && bytes[nl] != b'\n' {
        nl += 1
      }
      if nl >= bytes.length() {
        raise @model.Io("Malformed git cat-file --batch header")
      }
      let header = @utf8.decode_lossy(bytes[pos:nl]).trim().to_owned()
      pos = nl + 1
      if header.has_suffix(" missing") {
        continue
      }
      let size_str = header.split(" ").last().unwrap_or("").to_owned()
      guard parse_decimal_int(size_str) is Some(size) else {
        raise @model.Io("Malformed git cat-file --batch size: " + header)
      }
      if pos + size > bytes.length() {
        raise @model.Io("Truncated git cat-file --batch body")
      }
      self.sources[domain_path] = @utf8.decode_lossy(bytes[pos:pos + size])
      pos = pos + size
      if pos < bytes.length() && bytes[pos] == b'\n' {
        pos += 1
      }
    }
    start = end
  }
}

///|
async fn Reader::read(self : Reader, path : String) -> String? {
  let domain_path = relative(self.root, join(self.root, path))
  if self.sources.get(domain_path) is Some(cached) {
    return Some(cached)
  }
  let result = if self.use_git_tree {
    match (self.git_root, self.head) {
      (Some(root), Some(head)) => {
        let repo_path = relative(root, join(self.root, domain_path))
        if self.tree.get(repo_path) is Some("100644" | "100755") {
          Some(git(root, ["show", head + ":" + repo_path]))
        } else if self.tree.contains(repo_path) {
          fail_input(
            "Git snapshot input must be a regular file",
            path=domain_path,
          )
          None
        } else {
          None
        }
      }
      _ => None
    }
  } else {
    let absolute = join(self.root, domain_path)
    if @fs.exists(absolute) {
      ignore(relative(self.root, @fs.realpath(absolute)))
      Some(@fs.read_text(absolute))
    } else {
      None
    }
  }
  if result is Some(source) {
    self.sources[domain_path] = source
  }
  result
}

///|
async fn Reader::files(self : Reader, directory : String) -> Array[String] {
  let result = []
  if self.use_git_tree {
    if self.git_root is Some(root) {
      let rel_dir = relative(root, join(self.root, directory))
      let prefix = if rel_dir == "" { "" } else { rel_dir + "/" }
      for path in self.tree.keys() {
        if prefix == "" || path.has_prefix(prefix) {
          let rest = path[prefix.length():].to_owned()
          if !rest.contains("/") {
            result.push(rest)
          }
        }
      }
    }
  } else {
    let absolute = join(self.root, directory)
    if @fs.exists(absolute) {
      ignore(relative(self.root, @fs.realpath(absolute)))
      result.append(@fs.readdir(absolute, include_hidden=true))
    }
  }
  result.sort()
  result
}

///|
async fn Reader::dirs(self : Reader, directory : String) -> Array[String] {
  let result : Array[String] = []
  if self.use_git_tree {
    if self.git_root is Some(root) {
      let rel_dir = relative(root, join(self.root, directory))
      let prefix = if rel_dir == "" { "" } else { rel_dir + "/" }
      for path in self.tree.keys() {
        if prefix == "" || path.has_prefix(prefix) {
          let rest = path[prefix.length():].to_owned()
          if rest.find("/") is Some(sep) {
            let child = rest[:sep].to_owned()
            if !result.contains(child) {
              result.push(child)
            }
          }
        }
      }
    }
  } else {
    let absolute = join(self.root, directory)
    if @fs.exists(absolute) {
      let canonical_dir = @fs.realpath(absolute)
      ignore(relative(self.root, canonical_dir))
      if self.visited_dirs.contains(canonical_dir) {
        return result
      }
      self.visited_dirs[canonical_dir] = true
      for entry in @fs.readdir(absolute) {
        let child = join(absolute, entry)
        // Guard against broken symlinks and symlink loops
        let is_dir = (@fs.kind(child, follow_symlink=false) catch {
            _ => @fs.Regular
          }) ==
          @fs.Directory
        if is_dir {
          result.push(entry)
        }
      }
    }
  }
  result.sort()
  result
}

///|
async fn make_reader(
  root : String,
  since : String?,
) -> (Reader, Array[String], Array[@model.Diagnostic]) {
  let tree : Map[String, String] = Map([])
  let sources : Map[String, String] = Map([])
  let changed : Array[String] = []
  let warnings : Array[@model.Diagnostic] = []
  guard since is Some(reference) else {
    // Best-effort resolve HEAD commit even without `--since` so `pack` / `publish`
    // can validate `sourceCommit == HEAD` accurately.
    let git_root_opt : String? = try {
      let top = git(root, ["rev-parse", "--show-toplevel"]).trim().to_owned()
      if top == "" {
        None
      } else {
        Some(@fs.realpath(top) catch { _ => top })
      }
    } catch {
      _ => None
    }
    let head_opt : String? = match git_root_opt {
      Some(gr) =>
        try {
          let h = git(gr, ["rev-parse", "--verify", "HEAD^{commit}"])
            .trim()
            .to_owned()
          if h == "" {
            None
          } else {
            Some(h)
          }
        } catch {
          _ => None
        }
      None => None
    }
    return (
      {
        root,
        git_root: git_root_opt,
        head: head_opt,
        use_git_tree: false,
        tree,
        sources,
        visited_dirs: Map([]),
      },
      changed,
      warnings,
    )
  }
  let git_root_raw = git(root, ["rev-parse", "--show-toplevel"])
    .trim()
    .to_owned()
  let git_root = @fs.realpath(git_root_raw) catch { _ => git_root_raw }
  let head = git(git_root, ["rev-parse", "--verify", "HEAD^{commit}"])
    .trim()
    .to_owned()
  let ref_commit = git(git_root, [
      "rev-parse",
      "--verify",
      "--end-of-options",
      reference + "^{commit}",
    ])
    .trim()
    .to_owned()
  let base = git(git_root, ["merge-base", ref_commit, head]).trim().to_owned()
  for
    entry in git(git_root, ["ls-tree", "-r", "-z", "--full-tree", head]).split(
      "\u0000",
    ) {
    if entry == "" {
      continue
    }
    let row = entry.to_owned()
    guard row.find("\t") is Some(tab) else {
      raise @model.Io("Malformed git ls-tree output")
    }
    let mode = row.split(" ").next().unwrap_or("").to_owned()
    tree[row[tab + 1:].to_owned()] = mode
  }
  let diff = git(git_root, [
    "diff", "--name-status", "-z", "--find-renames", base, head, "--",
  ])
  let entries = diff.split("\u0000").map(x => x.to_owned()).collect()
  let domain_prefix = relative(git_root, root)
  let mut i = 0
  while i + 1 < entries.length() {
    let status = entries[i]
    let paths = if status.has_prefix("R") || status.has_prefix("C") {
      if i + 2 >= entries.length() {
        raise @model.Io("Malformed git diff output")
      }
      i += 3
      [entries[i - 2], entries[i - 1]]
    } else {
      i += 2
      [entries[i - 1]]
    }
    for path in paths {
      if domain_prefix == "" {
        if !changed.contains(path) {
          changed.push(path)
        }
      } else if path.has_prefix(domain_prefix + "/") {
        let domain_path = path[domain_prefix.length() + 1:].to_owned()
        if !changed.contains(domain_path) {
          changed.push(domain_path)
        }
      }
    }
  }
  changed.sort()
  if git(git_root, ["status", "--porcelain", "-z"]) != "" {
    warnings.push(
      @model.diagnostic(
        "uncommitted-excluded",
        "--since uses committed HEAD; working tree changes are excluded",
        path=root,
      ),
    )
  }
  (
    {
      root,
      git_root: Some(git_root),
      head: Some(head),
      use_git_tree: true,
      tree,
      sources,
      visited_dirs: Map([]),
    },
    changed,
    warnings,
  )
}
