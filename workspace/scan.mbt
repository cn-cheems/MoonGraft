///|
pub(all) suberror WorkspaceError {
  WorkspaceError(String)
}

///|
fn windows_host() -> Bool {
  @env.get_env_var("OS") == Some("Windows_NT")
}

///|
async fn require_directory(path : String) -> Unit {
  guard @fs.kind(path, follow_symlink=false) == Directory else {
    raise WorkspaceError("Expected an ordinary directory, not a link: " + path)
  }
}

///|
/// Read an ordinary file with an enforced byte limit, including if it grows.
pub async fn read_bytes(path : String, limit~ : Int32 = 2097152) -> Bytes {
  guard limit >= 0 && limit <= 160000000 else {
    raise WorkspaceError("Byte limit must be between 0 and 160000000")
  }
  guard @fs.kind(path, follow_symlink=false) == Regular else {
    raise WorkspaceError("Expected an ordinary file, not a link: " + path)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() == Regular && file.size() <= limit.to_int64() else {
    raise WorkspaceError(
      "File exceeds its byte limit or is not regular: " + path,
    )
  }
  let output : Array[Byte] = []
  while true {
    match
      file.read_some(max_len=Int32::min(65536, limit - output.length() + 1)) {
      None => break
      Some(bytes) => {
        guard output.length() + bytes.length() <= limit else {
          raise WorkspaceError("File grew beyond its byte limit: " + path)
        }
        for byte in bytes {
          output.push(byte)
        }
      }
    }
  }
  Bytes::from_array(output)
}

///|
pub async fn read_text(path : String) -> String {
  @utf8.decode(read_bytes(path, limit=160000000), ignore_bom=false)
}

///|
pub async fn read_file(path : String, logical_path : String) -> @graft.File {
  let content = read_bytes(path)
  let executable = if windows_host() { false } else { @fs.can_execute(path) }
  @graft.File::new(logical_path, content, executable~)
}

///|
/// Exclusive creation; existing archives are never truncated.
pub async fn write_new(path : String, text : String) -> Unit {
  @fs.write_file(path, text, create_mode=CreateNew)
}

///|
async fn scan_into(
  root : String,
  relative : String,
  files : Array[@graft.File],
  total : Ref[Int32],
) -> Unit {
  let directory = if relative.is_empty() { root } else { root + "/" + relative }
  require_directory(directory)
  let names = @fs.readdir(directory, include_hidden=true, sort=true)
  guard relative.is_empty() || !names.is_empty() else {
    raise WorkspaceError(
      "Empty directories cannot be represented; input refused: " + directory,
    )
  }
  for name in names {
    // Explicit working-tree boundary: only root Git metadata is excluded.
    if relative.is_empty() && name == ".git" {
      continue
    }
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    ignore(@graft.File::new(path, b""))
    let full = root + "/" + path
    match @fs.kind(full, follow_symlink=false) {
      Directory => scan_into(root, path, files, total)
      Regular => {
        guard files.length() < 2048 else {
          raise WorkspaceError("More than 2048 files: " + root)
        }
        let content = read_bytes(
          full,
          limit=Int32::min(2097152, 16777216 - total.val),
        )
        total.val += content.length()
        let executable = if windows_host() {
          false
        } else {
          @fs.can_execute(full)
        }
        files.push(@graft.File::new(path, content, executable~))
      }
      _ =>
        raise WorkspaceError(
          "Links and special files are unsupported; input refused: " + full,
        )
    }
  }
}

///|
/// Scan a trusted, quiescent working directory. Only root `.git` is excluded.
/// No .gitignore rules or hidden-file exclusions are applied.
pub async fn scan(root : String) -> @graft.Tree {
  let files = []
  scan_into(root, "", files, Ref(0))
  @graft.Tree::new(files)
}

///|
/// Prevent export bundles from being created inside the project being upgraded.
pub async fn require_outside(destination : String, source : String) -> Unit {
  let normalized = destination.replace(old="\\", new="/")
  guard !normalized.has_suffix("/") else {
    raise WorkspaceError(
      "Destination must name a new directory without a trailing separator",
    )
  }
  let parts = normalized.split("/").map(s => s.to_owned()).to_array()
  let name = parts[parts.length() - 1]
  ignore(@graft.File::new(name, b""))
  let parent = if parts.length() == 1 {
    "."
  } else {
    parts[:parts.length() - 1].to_owned().join("/")
  }
  let real_parent = @fs.realpath(parent).replace(old="\\", new="/")
  let real_source = @fs.realpath(source).replace(old="\\", new="/")
  let target = real_parent + "/" + name
  let a = if windows_host() { target.to_lower() } else { target }
  let b = if windows_host() { real_source.to_lower() } else { real_source }
  guard a != b && !a.has_prefix(b + "/") else {
    raise WorkspaceError(
      "Export destination must be outside the source project: " + destination,
    )
  }
}
