///|
pub(all) struct DoctorCheck {
  name : String
  ok : Bool
  message : String
  suggestion : String?
}

///|
pub(all) struct DoctorReport {
  ok : Bool
  checks : Array[DoctorCheck]
}

///|
pub fn DoctorCheck::to_json(self : DoctorCheck) -> Json {
  {
    "name": self.name,
    "ok": self.ok,
    "message": self.message,
    "suggestion": match self.suggestion {
      Some(value) => Json::string(value)
      None => Json::null()
    },
  }
}

///|
pub fn DoctorReport::to_json(self : DoctorReport) -> Json {
  {
    "schemaVersion": 1,
    "ok": self.ok,
    "checks": self.checks.map(x => x.to_json()),
  }
}

///|
async fn[H : ExecutionHost] apply_doctor_fixes(
  host : H,
  cwd : String,
  config_path : String?,
) -> Array[String] {
  let fixed : Array[String] = []
  let cfg = match config_path {
    Some(custom) =>
      if @path.Path(custom).is_absolute() {
        custom
      } else {
        absolute_path(cwd, custom)
      }
    None => absolute_path(cwd, ".changeset/config.json")
  }
  let dir = parent_dir(cfg)
  let default_cfg = "{\n  \"schemaVersion\": 1,\n  \"changelog\": {\"generator\": \"builtin\"},\n  \"access\": \"public\",\n  \"baseBranch\": \"main\",\n  \"commit\": {\"mode\": \"never\"},\n  \"formatter\": \"builtin\"\n}\n"
  if !host.exists(cfg) {
    host.mkdir(dir)
    host.write_text(cfg, default_cfg)
    fixed.push(cfg)
  }
  let readme = absolute_path(dir, "README.md")
  if !host.exists(readme) {
    host.mkdir(dir)
    host.write_text(
      readme, "# Changesets\n\nRun moonset add to record a release.\n",
    )
    fixed.push(readme)
  }
  let cs_ignore = absolute_path(dir, ".gitignore")
  if !host.exists(cs_ignore) {
    host.mkdir(dir)
    host.write_text(cs_ignore, "pre.json\n")
    fixed.push(cs_ignore)
  }
  let state_ignore = absolute_path(cwd, ".moonset/.gitignore")
  if !host.exists(state_ignore) {
    host.mkdir(parent_dir(state_ignore))
    host.write_text(
      state_ignore, "version-journal.json\npublish-state.json\npack-results.json\n",
    )
    fixed.push(state_ignore)
  }
  fixed
}

///|
pub async fn[H : ExecutionHost] run_doctor_with(
  host : H,
  cwd : String,
  config_path? : String,
  check_registry~ : Bool = false,
  fix~ : Bool = false,
) -> DoctorReport {
  let checks : Array[DoctorCheck] = []
  if fix {
    let fixed_paths = apply_doctor_fixes(host, cwd, config_path)
    checks.push({
      name: "fix",
      ok: true,
      message: if fixed_paths.is_empty() {
        "No missing initialization files needed repair"
      } else {
        "Initialized missing files: " + fixed_paths.join(", ")
      },
      suggestion: None,
    })
  }
  let git_ver = host.run("git", ["--version"], Some(cwd)) catch {
    error => { exit_code: 1, stdout: "", stderr: error_message(error), }
  }
  checks.push({
    name: "git",
    ok: git_ver.exit_code == 0,
    message: if git_ver.exit_code == 0 {
      git_ver.stdout.trim().to_owned()
    } else {
      "git is unavailable"
    },
    suggestion: if git_ver.exit_code == 0 {
      None
    } else {
      Some("Install Git and ensure it is on PATH")
    },
  })
  let moon_ver = host.run("moon", ["version"], Some(cwd)) catch {
    error => { exit_code: 1, stdout: "", stderr: error_message(error), }
  }
  checks.push({
    name: "moon",
    ok: moon_ver.exit_code == 0,
    message: if moon_ver.exit_code == 0 {
      moon_ver.stdout.trim().to_owned()
    } else {
      "moon toolchain is unavailable"
    },
    suggestion: if moon_ver.exit_code == 0 {
      None
    } else {
      Some("Install MoonBit toolchain and verify `moon version`")
    },
  })
  let discovered : Result[@workspace.LoadedWorkspace, Error] = Ok(
    @workspace.discover(cwd, config_path?),
  ) catch {
    error => Err(error)
  }
  match discovered {
    Ok(loaded) => {
      checks.push({
        name: "workspace",
        ok: true,
        message: "Discovered " +
        loaded.snapshot.units.length().to_string() +
        " units",
        suggestion: None,
      })
      let journal = absolute_path(
        loaded.snapshot.root,
        ".moonset/version-journal.json",
      )
      let has_journal = host.exists(journal)
      checks.push({
        name: "journal",
        ok: !has_journal,
        message: if has_journal {
          "Unfinished version journal detected"
        } else {
          "No pending recovery journal"
        },
        suggestion: if has_journal {
          Some("Run `moonset version --recover` to restore incomplete edits")
        } else {
          None
        },
      })
      let dirty = host.run(
        "git",
        ["status", "--porcelain"],
        Some(loaded.snapshot.root),
      ) catch {
        _ => { exit_code: 1, stdout: "", stderr: "", }
      }
      let is_clean = dirty.exit_code == 0 &&
        !has_dirty_worktree_changes(dirty.stdout)
      checks.push({
        name: "git-worktree",
        ok: dirty.exit_code == 0 && is_clean,
        message: if dirty.exit_code != 0 {
          "Not inside a Git repository"
        } else if is_clean {
          "Working tree is clean"
        } else {
          "Working tree has uncommitted changes"
        },
        suggestion: if is_clean {
          None
        } else {
          Some("Commit or stash changes before running publish or tag")
        },
      })
      if check_registry {
        let mut reg_ok = true
        let mut reg_msg = "Registry preflight checks passed"
        for unit in loaded.snapshot.units {
          if !unit.publish {
            continue
          }
          if unit.ecosystem == "moonbit" {
            let out = host.run(
              "moon",
              ["publish", "--dry-run"],
              Some(absolute_path(loaded.snapshot.root, unit.root)),
            ) catch {
              error =>
                { exit_code: 1, stdout: "", stderr: error_message(error), }
            }
            if out.exit_code != 0 {
              reg_ok = false
              reg_msg = "moon publish --dry-run failed for " + unit.id
              break
            }
          } else if unit.ecosystem == "npm" {
            let mgr = package_manager_program(
              host,
              manager_for_unit(loaded.snapshot, unit),
            )
            let out = host.run(
              mgr,
              ["whoami"],
              Some(absolute_path(loaded.snapshot.root, unit.root)),
            ) catch {
              error =>
                { exit_code: 1, stdout: "", stderr: error_message(error), }
            }
            if out.exit_code != 0 {
              reg_ok = false
              reg_msg = mgr + " whoami failed for " + unit.id
              break
            }
          } else if unit.ecosystem == "cargo" {
            let out = host.run(
              "cargo",
              ["publish", "--dry-run", "--allow-dirty"],
              Some(absolute_path(loaded.snapshot.root, unit.root)),
            ) catch {
              error =>
                { exit_code: 1, stdout: "", stderr: error_message(error), }
            }
            if out.exit_code != 0 {
              reg_ok = false
              reg_msg = "cargo publish --dry-run failed for " + unit.id
              break
            }
          }
        }
        checks.push({
          name: "registry",
          ok: reg_ok,
          message: reg_msg,
          suggestion: if reg_ok {
            None
          } else {
            Some("Check registry login credentials and manifest metadata")
          },
        })
      }
      if host.getenv("GITHUB_ACTIONS") is Some("true") ||
        loaded.snapshot.config.publisher_token_env is Some(_) {
        let mut env_ok = true
        let missing_vars : Array[String] = []
        if host.getenv("GITHUB_ACTIONS") is Some("true") &&
          host.getenv("GITHUB_REPOSITORY").unwrap_or("") == "" {
          env_ok = false
          missing_vars.push("GITHUB_REPOSITORY")
        }
        if loaded.snapshot.config.publisher_token_env is Some(token_var) &&
          host.getenv(token_var).unwrap_or("") == "" {
          env_ok = false
          missing_vars.push(token_var)
        }
        checks.push({
          name: "ci-env",
          ok: env_ok,
          message: if env_ok {
            "Required CI/Action environment variables are present"
          } else {
            "Missing environment variables: " + missing_vars.join(", ")
          },
          suggestion: if env_ok {
            None
          } else {
            Some(
              "Configure the missing repository/token environment variables in CI",
            )
          },
        })
      }
    }
    Err(error) =>
      checks.push({
        name: "workspace",
        ok: false,
        message: error.to_string(),
        suggestion: Some("Run `moonset init` or fix workspace/config errors"),
      })
  }
  { ok: checks.all(c => c.ok), checks, }
}

///|
pub async fn run_doctor(
  cwd : String,
  config_path? : String,
  check_registry~ : Bool = false,
  fix~ : Bool = false,
) -> DoctorReport {
  run_doctor_with(native_host(), cwd, config_path?, check_registry~, fix~)
}
