///|
priv struct Reader {
  root : String
  git_root : String?
  head : String?
  tree : Map[String, String]
  sources : Map[String, String]
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
    @path.Path(path).relative(base=@path.Path(root)).to_string(),
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
async fn Reader::read(self : Reader, path : String) -> String? {
  let domain_path = relative(self.root, join(self.root, path))
  let result = match (self.git_root, self.head) {
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
    _ => {
      let absolute = join(self.root, domain_path)
      if @fs.exists(absolute) {
        ignore(relative(self.root, @fs.realpath(absolute)))
        Some(@fs.read_text(absolute))
      } else {
        None
      }
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
  match self.git_root {
    Some(root) => {
      let prefix = relative(root, join(self.root, directory)) + "/"
      for path in self.tree.keys() {
        if path.has_prefix(prefix) {
          let rest = path[prefix.length():].to_owned()
          if !rest.contains("/") {
            result.push(rest)
          }
        }
      }
    }
    None => {
      let absolute = join(self.root, directory)
      if @fs.exists(absolute) {
        ignore(relative(self.root, @fs.realpath(absolute)))
        result.append(@fs.readdir(absolute, include_hidden=true))
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
    return (
      { root, git_root: None, head: None, tree, sources, },
      changed,
      warnings,
    )
  }
  let git_root = git(root, ["rev-parse", "--show-toplevel"]).trim().to_owned()
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
    { root, git_root: Some(git_root), head: Some(head), tree, sources, },
    changed,
    warnings,
  )
}
