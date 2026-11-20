///|
extern "C" fn moonset_tty_is_tty_ffi() -> Int32 = "moonset_tty_is_tty"

///|
extern "C" fn moonset_tty_enable_color_ffi(is_stderr : Int32) -> Int32 = "moonset_tty_enable_color"

///|
extern "C" fn moonset_tty_enter_raw_ffi() -> Int32 = "moonset_tty_enter_raw"

///|
extern "C" fn moonset_tty_leave_raw_ffi() -> Int32 = "moonset_tty_leave_raw"

///|
extern "C" fn moonset_tty_cols_ffi() -> Int32 = "moonset_tty_cols"

///|
extern "C" fn moonset_tty_rows_ffi() -> Int32 = "moonset_tty_rows"

///|
#borrow(buf)
extern "C" fn moonset_tty_write_utf8_ffi(buf : FixedArray[Byte], len : Int32) = "moonset_tty_write_utf8"

///|
#borrow(buf)
extern "C" fn moonset_tty_read_event_ffi(
  buf : FixedArray[Byte],
  max_len : Int32,
) -> Int32 = "moonset_tty_read_event"

///|
fn tty_is_tty() -> Bool {
  moonset_tty_is_tty_ffi() != 0
}

///|
fn tty_enable_color(is_stderr : Bool) -> Bool {
  moonset_tty_enable_color_ffi(if is_stderr { 1 } else { 0 }) != 0
}

///|
fn tty_enter_raw() -> Bool {
  moonset_tty_enter_raw_ffi() == 0
}

///|
fn tty_leave_raw() -> Unit {
  ignore(moonset_tty_leave_raw_ffi())
}

///|
fn tty_cols() -> Int32 {
  moonset_tty_cols_ffi()
}

///|
fn tty_rows() -> Int32 {
  moonset_tty_rows_ffi()
}

///|
fn tty_write(text : String) -> Unit {
  let encoded = @utf8.encode(text)
  let len = encoded.length()
  if len == 0 {
    return
  }
  let buf : FixedArray[Byte] = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    buf[i] = encoded[i]
  }
  moonset_tty_write_utf8_ffi(buf, len)
}

///|
fn tty_read_raw_event() -> String {
  let buf : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  let n = moonset_tty_read_event_ffi(buf, 32)
  if n <= 0 {
    return "\u{0003}"
  }
  let bytes = Bytes::makei(n, i => buf[i])
  @utf8.decode_lossy(bytes)
}
