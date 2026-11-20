///|
/// Self-contained TOML value representation with exact UTF-8 byte spans for
/// lossless in-place editing of `Cargo.toml` manifests.
priv enum TomlVal {
  Str(String, @model.TextSpan)
  Bool(Bool)
  Arr(Array[TomlVal])
  Tbl(Map[String, TomlVal])
}

///|
priv struct TomlDoc {
  root : Map[String, TomlVal]
}

///|
priv struct TomlParser {
  bytes : Bytes
  mut pos : Int32
}

///|
fn TomlParser::new(source : String) -> TomlParser {
  { bytes: @utf8.encode(source), pos: 0, }
}

///|
fn TomlParser::eof(self : TomlParser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn TomlParser::peek(self : TomlParser) -> Int32 {
  if self.pos < self.bytes.length() {
    self.bytes[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn TomlParser::peek_at(self : TomlParser, offset : Int32) -> Int32 {
  let idx = self.pos + offset
  if idx >= 0 && idx < self.bytes.length() {
    self.bytes[idx].to_int()
  } else {
    -1
  }
}

///|
fn TomlParser::skip_hws(self : TomlParser) -> Unit {
  while !self.eof() {
    let b = self.peek()
    if b == 0x20 || b == 0x09 {
      self.pos += 1
    } else {
      break
    }
  }
}

///|
fn TomlParser::skip_ws_and_comments(self : TomlParser) -> Unit {
  while !self.eof() {
    let b = self.peek()
    if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
      self.pos += 1
    } else if b == 0x23 {
      // `#` comment until newline
      while !self.eof() && self.peek() != 0x0A {
        self.pos += 1
      }
    } else {
      break
    }
  }
}

///|
fn TomlParser::skip_to_eol(self : TomlParser) -> Unit {
  while !self.eof() && self.peek() != 0x0A {
    self.pos += 1
  }
  if !self.eof() && self.peek() == 0x0A {
    self.pos += 1
  }
}

///|
fn is_bare_key_byte(b : Int32) -> Bool {
  (b >= 0x41 && b <= 0x5A) ||
  (b >= 0x61 && b <= 0x7A) ||
  (b >= 0x30 && b <= 0x39) ||
  b == 0x5F ||
  b == 0x2D
}

///|
fn TomlParser::parse_basic_string(
  self : TomlParser,
) -> (String, @model.TextSpan)? {
  if self.peek() != 0x22 {
    return None
  }
  // Check multiline basic string `"""`
  if self.peek_at(1) == 0x22 && self.peek_at(2) == 0x22 {
    self.pos += 3
    // Trim immediate newline after opening `"""` per TOML spec
    if self.peek() == 0x0D && self.peek_at(1) == 0x0A {
      self.pos += 2
    } else if self.peek() == 0x0A {
      self.pos += 1
    }
    let start = self.pos
    while !self.eof() {
      let b = self.peek()
      if b == 0x5C {
        self.pos += 2
        continue
      }
      if b == 0x22 && self.peek_at(1) == 0x22 && self.peek_at(2) == 0x22 {
        let end = self.pos
        self.pos += 3
        let raw = @utf8.decode_lossy(self.bytes[start:end])
        return Some((raw, { start, end, }))
      }
      self.pos += 1
    }
    return None
  }
  self.pos += 1
  let start = self.pos
  let buf : Array[Byte] = []
  while !self.eof() {
    let b = self.peek()
    if b == 0x0A || b == 0x0D {
      return None
    }
    if b == 0x5C {
      self.pos += 1
      if self.eof() {
        return None
      }
      let esc = self.peek()
      self.pos += 1
      match esc {
        0x6E => buf.push(b'\n')
        0x72 => buf.push(b'\r')
        0x74 => buf.push(b'\t')
        0x22 => buf.push(b'"')
        0x5C => buf.push(b'\\')
        _ => buf.push(esc.to_byte())
      }
      continue
    }
    if b == 0x22 {
      let end = self.pos
      self.pos += 1
      let decoded = @utf8.decode_lossy(Bytes::from_array(buf))
      return Some((decoded, { start, end, }))
    }
    buf.push(b.to_byte())
    self.pos += 1
  }
  None
}

///|
fn TomlParser::parse_literal_string(
  self : TomlParser,
) -> (String, @model.TextSpan)? {
  if self.peek() != 0x27 {
    return None
  }
  if self.peek_at(1) == 0x27 && self.peek_at(2) == 0x27 {
    self.pos += 3
    if self.peek() == 0x0D && self.peek_at(1) == 0x0A {
      self.pos += 2
    } else if self.peek() == 0x0A {
      self.pos += 1
    }
    let start = self.pos
    while !self.eof() {
      if self.peek() == 0x27 &&
        self.peek_at(1) == 0x27 &&
        self.peek_at(2) == 0x27 {
        let end = self.pos
        self.pos += 3
        let raw = @utf8.decode_lossy(self.bytes[start:end])
        return Some((raw, { start, end, }))
      }
      self.pos += 1
    }
    return None
  }
  self.pos += 1
  let start = self.pos
  while !self.eof() {
    let b = self.peek()
    if b == 0x0A || b == 0x0D {
      return None
    }
    if b == 0x27 {
      let end = self.pos
      self.pos += 1
      return Some((@utf8.decode_lossy(self.bytes[start:end]), { start, end, }))
    }
    self.pos += 1
  }
  None
}

///|
fn TomlParser::parse_key_segment(self : TomlParser) -> String? {
  self.skip_hws()
  let b = self.peek()
  if b == 0x22 {
    return self.parse_basic_string().map(p => p.0)
  }
  if b == 0x27 {
    return self.parse_literal_string().map(p => p.0)
  }
  let start = self.pos
  while !self.eof() && is_bare_key_byte(self.peek()) {
    self.pos += 1
  }
  if self.pos == start {
    None
  } else {
    Some(@utf8.decode_lossy(self.bytes[start:self.pos]))
  }
}

///|
fn TomlParser::parse_key_path(self : TomlParser) -> Array[String]? {
  let parts : Array[String] = []
  guard self.parse_key_segment() is Some(first) else { return None }
  parts.push(first)
  for ;; {
    self.skip_hws()
    if self.peek() == 0x2E {
      self.pos += 1
      guard self.parse_key_segment() is Some(next) else { return None }
      parts.push(next)
    } else {
      break
    }
  }
  Some(parts)
}

///|
fn insert_nested(
  table : Map[String, TomlVal],
  keys : Array[String],
  value : TomlVal,
) -> Unit {
  if keys.is_empty() {
    return
  }
  let mut cur = table
  for i in 0..<(keys.length() - 1) {
    let k = keys[i]
    match cur.get(k) {
      Some(Tbl(sub)) => cur = sub
      _ => {
        let sub : Map[String, TomlVal] = Map([])
        cur[k] = Tbl(sub)
        cur = sub
      }
    }
  }
  cur[keys[keys.length() - 1]] = value
}

///|
fn ensure_table(
  root : Map[String, TomlVal],
  keys : Array[String],
) -> Map[String, TomlVal] {
  let mut cur = root
  for k in keys {
    match cur.get(k) {
      Some(Tbl(sub)) => cur = sub
      _ => {
        let sub : Map[String, TomlVal] = Map([])
        cur[k] = Tbl(sub)
        cur = sub
      }
    }
  }
  cur
}

///|
fn TomlParser::parse_value(self : TomlParser) -> TomlVal? {
  self.skip_hws()
  let b = self.peek()
  if b == 0x22 {
    return self.parse_basic_string().map(p => Str(p.0, p.1))
  }
  if b == 0x27 {
    return self.parse_literal_string().map(p => Str(p.0, p.1))
  }
  if b == 0x5B {
    // Array `[ ... ]`
    self.pos += 1
    let items : Array[TomlVal] = []
    for ;; {
      self.skip_ws_and_comments()
      if self.eof() {
        return None
      }
      if self.peek() == 0x5D {
        self.pos += 1
        return Some(Arr(items))
      }
      match self.parse_value() {
        Some(v) => items.push(v)
        None =>
          // Skip unrecognized token to stay resilient on non-release Cargo fields
          while !self.eof() &&
                self.peek() != 0x2C &&
                self.peek() != 0x5D &&
                self.peek() != 0x0A {
            self.pos += 1
          }
      }
      self.skip_ws_and_comments()
      if self.peek() == 0x2C {
        self.pos += 1
      } else if self.peek() == 0x5D {
        self.pos += 1
        return Some(Arr(items))
      }
    }
  }
  if b == 0x7B {
    // Inline table `{ k = v, ... }`
    self.pos += 1
    let map : Map[String, TomlVal] = Map([])
    for ;; {
      self.skip_ws_and_comments()
      if self.eof() {
        return None
      }
      if self.peek() == 0x7D {
        self.pos += 1
        return Some(Tbl(map))
      }
      guard self.parse_key_path() is Some(kpath) else {
        while !self.eof() && self.peek() != 0x7D && self.peek() != 0x0A {
          self.pos += 1
        }
        if self.peek() == 0x7D {
          self.pos += 1
        }
        return Some(Tbl(map))
      }
      self.skip_hws()
      if self.peek() != 0x3D {
        return None
      }
      self.pos += 1
      if self.parse_value() is Some(v) {
        insert_nested(map, kpath, v)
      }
      self.skip_ws_and_comments()
      if self.peek() == 0x2C {
        self.pos += 1
      } else if self.peek() == 0x7D {
        self.pos += 1
        return Some(Tbl(map))
      }
    }
  }
  // Bare scalar (boolean, number, date)
  let start = self.pos
  while !self.eof() {
    let c = self.peek()
    if c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x2C ||
      c == 0x5D ||
      c == 0x7D ||
      c == 0x23 {
      break
    }
    self.pos += 1
  }
  if self.pos == start {
    return None
  }
  let raw = @utf8.decode_lossy(self.bytes[start:self.pos])
  if raw == "true" {
    Some(Bool(true))
  } else if raw == "false" {
    Some(Bool(false))
  } else {
    Some(Str(raw, { start, end: self.pos, }))
  }
}

///|
fn parse_toml(source : String) -> TomlDoc {
  let clean = if source.has_prefix("\uFEFF") {
    source[1:].to_owned()
  } else {
    source
  }
  let parser = TomlParser::new(clean)
  let root : Map[String, TomlVal] = Map([])
  let mut current = root
  while !parser.eof() {
    parser.skip_ws_and_comments()
    if parser.eof() {
      break
    }
    if parser.peek() == 0x5B {
      // `[table]` or `[[array.of.tables]]`
      if parser.peek_at(1) == 0x5B {
        parser.pos += 2
        let _ = parser.parse_key_path()
        parser.skip_to_eol()
        // Point array-of-tables entries to a scratch table so they never pollute [package]
        current = Map([])
        continue
      }
      parser.pos += 1
      match parser.parse_key_path() {
        Some(path) => {
          parser.skip_hws()
          if parser.peek() == 0x5D {
            parser.pos += 1
          }
          current = ensure_table(root, path)
        }
        None => ()
      }
      parser.skip_to_eol()
      continue
    }
    match parser.parse_key_path() {
      Some(kpath) => {
        parser.skip_hws()
        if parser.peek() == 0x3D {
          parser.pos += 1
          if parser.parse_value() is Some(val) {
            insert_nested(current, kpath, val)
          }
        }
        parser.skip_to_eol()
      }
      None => parser.skip_to_eol()
    }
  }
  { root, }
}

///|
fn TomlDoc::get_table(
  self : TomlDoc,
  path : Array[String],
) -> Map[String, TomlVal]? {
  let mut cur = self.root
  for key in path {
    match cur.get(key) {
      Some(Tbl(sub)) => cur = sub
      _ => return None
    }
  }
  Some(cur)
}

///|
fn toml_string(
  table : Map[String, TomlVal],
  key : String,
) -> (String, @model.TextSpan)? {
  match table.get(key) {
    Some(Str(value, span)) => Some((value, span))
    _ => None
  }
}

///|
fn toml_bool(table : Map[String, TomlVal], key : String) -> Bool? {
  match table.get(key) {
    Some(Bool(v)) => Some(v)
    _ => None
  }
}

///|
fn toml_string_array(
  table : Map[String, TomlVal],
  key : String,
) -> Array[String] {
  match table.get(key) {
    Some(Arr(items)) => {
      let out : Array[String] = []
      for item in items {
        if item is Str(s, _) && s != "" {
          out.push(s)
        }
      }
      out
    }
    _ => []
  }
}

///|
fn toml_is_workspace_inherited(val : TomlVal?) -> Bool {
  match val {
    Some(Tbl(sub)) => toml_bool(sub, "workspace") == Some(true)
    _ => false
  }
}
