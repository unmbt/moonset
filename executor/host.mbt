///|
pub fn error_message(error : Error) -> String {
  match error {
    @model.Invalid(diagnostic) => diagnostic.message
    @model.Io(message) => message
    other => other.to_string()
  }
}

///|
/// Injectable async host boundary so execution flows can be tested without real
/// filesystem mutations, Git repositories, or registry network calls.
pub(open) trait ExecutionHost {
  async fn exists(Self, String) -> Bool
  async fn is_dir(Self, String) -> Bool
  async fn read_text(Self, String) -> String
  async fn read_binary(Self, String) -> Bytes
  async fn write_text(Self, String, String) -> Unit
  async fn write_binary(Self, String, Bytes) -> Unit
  async fn readdir(Self, String) -> Array[String]
  async fn mkdir(Self, String) -> Unit
  async fn remove(Self, String) -> Unit
  async fn rename(Self, String, String) -> Unit
  async fn tmpdir(Self, String) -> String
  async fn rmdir(Self, String) -> Unit
  async fn run(Self, String, Array[String], String?) -> @adapters.ProcessResult
  fn getenv(Self, String) -> String?
  fn now(Self) -> UInt64
}

///|
pub struct NativeHost {}

///|
pub fn native_host() -> NativeHost {
  NativeHost::{ }
}

///|
pub extend NativeHost with ExecutionHost::{
  exists,
  is_dir,
  read_text,
  read_binary,
  write_text,
  write_binary,
  readdir,
  mkdir,
  remove,
  rename,
  tmpdir,
  rmdir,
  run,
  getenv,
  now,
}

///|
pub impl ExecutionHost for NativeHost with fn exists(_self, path) {
  @fs.exists(path) catch {
    _ => false
  }
}

///|
pub impl ExecutionHost for NativeHost with fn is_dir(_self, path) {
  (@fs.kind(path) == @fs.Directory) catch {
    _ => false
  }
}

///|
pub impl ExecutionHost for NativeHost with fn read_text(_self, path) {
  @fs.read_text(path) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn read_binary(_self, path) {
  @fs.read_binary(path) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn write_text(_self, path, text) {
  @fs.write_text(path, text) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn write_binary(_self, path, bytes) {
  @fs.write_binary(path, bytes) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn readdir(_self, path) {
  @fs.readdir(path, include_hidden=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn mkdir(_self, path) {
  @fs.mkdir(path, recursive=true, allow_exist=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn remove(_self, path) {
  @fs.remove(path, allow_missing=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn rename(_self, from, to) {
  @fs.rename(from, to, replace=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn tmpdir(_self, prefix) {
  @fs.tmpdir(prefix~) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
pub impl ExecutionHost for NativeHost with fn rmdir(_self, path) {
  @fs.rmdir(path, recursive=true, allow_missing=true) catch {
    _ => ()
  }
}

///|
pub impl ExecutionHost for NativeHost with fn run(_self, program, args, cwd) {
  let output = @shell.Cmd(program, args, cwd?).output() catch {
    error => raise @model.Io(error.to_string())
  }
  {
    exit_code: output.exit_code(),
    stdout: output.stdout(),
    stderr: output.stderr(),
  }
}

///|
pub impl ExecutionHost for NativeHost with fn getenv(_self, name) {
  @env.get_env_var(name)
}

///|
pub impl ExecutionHost for NativeHost with fn now(_self) {
  @env.now()
}

///|
pub fn absolute_path(root : String, relative_path : String) -> String {
  if relative_path == "" {
    root
  } else {
    @path.Path(root).join(@path.Path(relative_path)).to_string()
  }
}

///|
pub fn parent_dir(path : String) -> String {
  @path.Path(path).dirname().to_string()
}

///|
/// Convert the host UTC millisecond clock to the stable YYYY-MM-DD form used
/// by the builtin changelog generator.
pub fn utc_date(milliseconds : UInt64) -> String {
  let days = milliseconds.reinterpret_as_int64() / 86400000L
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let year0 = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let month0 = (5L * doy + 2L) / 153L
  let day = doy - (153L * month0 + 2L) / 5L + 1L
  let month = month0 + (if month0 < 10L { 3L } else { -9L })
  let year = year0 + (if month <= 2L { 1L } else { 0L })
  let pad = fn(value : Int64) -> String {
    if value < 10L {
      "0" + value.to_string()
    } else {
      value.to_string()
    }
  }
  year.to_string() + "-" + pad(month) + "-" + pad(day)
}

///|
pub fn[H : ExecutionHost] package_manager_program(
  host : H,
  name : String,
) -> String {
  if host.getenv("ComSpec") is Some(_) && (name == "npm" || name == "pnpm") {
    name + ".cmd"
  } else {
    name
  }
}

///|
pub fn manager_for_unit(
  snapshot : @model.WorkspaceSnapshot,
  unit : @model.ReleaseUnit,
) -> String {
  for workspace in snapshot.workspaces {
    if workspace.id == unit.workspace_id {
      return workspace.manager
    }
  }
  if unit.ecosystem == "cargo" {
    "cargo"
  } else if unit.ecosystem == "moonbit" {
    "moon"
  } else {
    "npm"
  }
}

///|
pub fn workspace_root_for_unit(
  snapshot : @model.WorkspaceSnapshot,
  unit : @model.ReleaseUnit,
) -> String {
  for workspace in snapshot.workspaces {
    if workspace.id == unit.workspace_id {
      return workspace.root
    }
  }
  unit.root
}

///|
pub fn bytes_fingerprint(bytes : Bytes) -> String {
  let mut hash : UInt64 = 14695981039346656037UL
  for byte in bytes.iter() {
    hash = (hash ^ byte.to_uint64()) * 1099511628211UL
  }
  "fnv1a64:" + hash.to_string(radix=16)
}
