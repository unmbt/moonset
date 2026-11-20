/*
 * Minimal cross-platform UTF-8 TTY native stub for moonset TUI.
 *
 * Windows: Uses SetConsoleCP/SetConsoleOutputCP(CP_UTF8), ENABLE_VIRTUAL_TERMINAL_PROCESSING,
 * WriteConsoleW (eliminating Chinese GBK/CP936 mojibake), and blocking ReadConsoleInputW
 * (0% idle CPU, full UTF-16 -> UTF-8 Chinese IME & surrogate pair support).
 *
 * POSIX: Uses termios (preserving OPOST, blocking VMIN=1/VTIME=0), 20ms select() for
 * Esc vs CSI sequence disambiguation, and full multi-byte UTF-8 input assembly.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <stdio.h>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif

static int g_raw_active = 0;
static int g_atexit_registered = 0;
static DWORD g_orig_in_mode = 0;
static DWORD g_orig_out_mode = 0;
static UINT g_orig_in_cp = 0;
static UINT g_orig_out_cp = 0;
static WCHAR g_pending_high_surrogate = 0;

static void moonset_tty_restore_atexit(void) {
  if (!g_raw_active) return;
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut != INVALID_HANDLE_VALUE && hOut != NULL) {
    DWORD written = 0;
    const WCHAR reset_seq[] = L"\x1b[0m\x1b[?25h";
    WriteConsoleW(hOut, reset_seq, (DWORD)(sizeof(reset_seq) / sizeof(WCHAR) - 1),
                  &written, NULL);
    SetConsoleMode(hOut, g_orig_out_mode);
  }
  if (hIn != INVALID_HANDLE_VALUE && hIn != NULL) {
    SetConsoleMode(hIn, g_orig_in_mode);
  }
  if (g_orig_in_cp != 0) SetConsoleCP(g_orig_in_cp);
  if (g_orig_out_cp != 0) SetConsoleOutputCP(g_orig_out_cp);
  g_raw_active = 0;
}

int moonset_tty_is_tty(void) {
  if (!_isatty(_fileno(stdin)) || !_isatty(_fileno(stdout))) {
    return 0;
  }
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hIn == INVALID_HANDLE_VALUE || hIn == NULL ||
      hOut == INVALID_HANDLE_VALUE || hOut == NULL) {
    return 0;
  }
  DWORD in_mode = 0, out_mode = 0;
  if (!GetConsoleMode(hIn, &in_mode) || !GetConsoleMode(hOut, &out_mode)) {
    return 0;
  }
  return 1;
}

int moonset_tty_enable_color(int is_stderr) {
  int fd = is_stderr ? _fileno(stderr) : _fileno(stdout);
  if (!_isatty(fd)) return 0;
  HANDLE h = GetStdHandle(is_stderr ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
  if (h == INVALID_HANDLE_VALUE || h == NULL) return 0;
  DWORD mode = 0;
  if (!GetConsoleMode(h, &mode)) return 0;
  if (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING) return 1;
  if (SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING |
                            ENABLE_PROCESSED_OUTPUT)) {
    return 1;
  }
  return 0;
}

int moonset_tty_enter_raw(void) {
  if (g_raw_active) return 0;
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hIn == INVALID_HANDLE_VALUE || hOut == INVALID_HANDLE_VALUE) return -1;
  if (!GetConsoleMode(hIn, &g_orig_in_mode)) return -1;
  if (!GetConsoleMode(hOut, &g_orig_out_mode)) return -1;
  g_orig_in_cp = GetConsoleCP();
  g_orig_out_cp = GetConsoleOutputCP();
  SetConsoleCP(CP_UTF8);
  SetConsoleOutputCP(CP_UTF8);
  DWORD new_out = g_orig_out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING |
                  ENABLE_PROCESSED_OUTPUT;
  SetConsoleMode(hOut, new_out);
  DWORD new_in = ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS;
  SetConsoleMode(hIn, new_in);
  g_pending_high_surrogate = 0;
  g_raw_active = 1;
  if (!g_atexit_registered) {
    atexit(moonset_tty_restore_atexit);
    g_atexit_registered = 1;
  }
  return 0;
}

int moonset_tty_leave_raw(void) {
  moonset_tty_restore_atexit();
  return 0;
}

int moonset_tty_cols(void) {
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (hOut != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(hOut, &info)) {
    int cols = (int)(info.srWindow.Right - info.srWindow.Left + 1);
    if (cols > 0) return cols;
  }
  return 80;
}

int moonset_tty_rows(void) {
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (hOut != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(hOut, &info)) {
    int rows = (int)(info.srWindow.Bottom - info.srWindow.Top + 1);
    if (rows > 0) return rows;
  }
  return 24;
}

void moonset_tty_write_utf8(const uint8_t *buf, int len) {
  if (buf == NULL || len <= 0) return;
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) return;
  DWORD mode = 0;
  if (GetConsoleMode(hOut, &mode)) {
    int wlen = MultiByteToWideChar(CP_UTF8, 0, (const char *)buf, len, NULL, 0);
    if (wlen > 0) {
      WCHAR stack_buf[512];
      WCHAR *wbuf = (wlen <= 512)
                        ? stack_buf
                        : (WCHAR *)malloc((size_t)wlen * sizeof(WCHAR));
      if (wbuf != NULL) {
        int converted =
            MultiByteToWideChar(CP_UTF8, 0, (const char *)buf, len, wbuf, wlen);
        if (converted > 0) {
          DWORD written = 0;
          WriteConsoleW(hOut, wbuf, (DWORD)converted, &written, NULL);
        }
        if (wbuf != stack_buf) free(wbuf);
        return;
      }
    }
  }
  DWORD written = 0;
  WriteFile(hOut, buf, (DWORD)len, &written, NULL);
}

static int emit_bytes(uint8_t *out, int max_len, const char *s, int n) {
  if (n > max_len) n = max_len;
  memcpy(out, s, (size_t)n);
  return n;
}

int moonset_tty_read_event(uint8_t *out_buf, int max_len) {
  if (out_buf == NULL || max_len <= 0) return -1;
  HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
  if (hIn == INVALID_HANDLE_VALUE || hIn == NULL) return -1;
  for (;;) {
    INPUT_RECORD rec;
    DWORD nread = 0;
    if (!ReadConsoleInputW(hIn, &rec, 1, &nread) || nread == 0) {
      return -1;
    }
    if (rec.EventType != KEY_EVENT) continue;
    KEY_EVENT_RECORD *ke = &rec.Event.KeyEvent;
    if (!ke->bKeyDown) continue;
    WORD vk = ke->wVirtualKeyCode;
    WCHAR wc = ke->uChar.UnicodeChar;
    DWORD ctrl = ke->dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED);
    DWORD alt = ke->dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED);

    if (ctrl && !alt && (vk == 'C' || wc == 0x03)) {
      g_pending_high_surrogate = 0;
      return emit_bytes(out_buf, max_len, "\x03", 1);
    }
    if (ctrl && !alt && (vk == 'E' || wc == 0x05)) {
      g_pending_high_surrogate = 0;
      return emit_bytes(out_buf, max_len, "\x05", 1);
    }
    if (ctrl && !alt && (vk == 'A' || wc == 0x01)) {
      g_pending_high_surrogate = 0;
      return emit_bytes(out_buf, max_len, "\x01", 1);
    }

    switch (vk) {
      case VK_UP:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[A", 3);
      case VK_DOWN:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[B", 3);
      case VK_RIGHT:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[C", 3);
      case VK_LEFT:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[D", 3);
      case VK_HOME:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[H", 3);
      case VK_END:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[F", 3);
      case VK_DELETE:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b[3~", 4);
      case VK_RETURN:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\r", 1);
      case VK_BACK:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x7f", 1);
      case VK_ESCAPE:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\x1b", 1);
      case VK_TAB:
        g_pending_high_surrogate = 0;
        return emit_bytes(out_buf, max_len, "\t", 1);
      default:
        break;
    }

    if (wc == 0) continue;

    /* Handle UTF-16 surrogate pairs (e.g. emoji or Extension-B CJK via IME) */
    if (wc >= 0xD800 && wc <= 0xDBFF) {
      g_pending_high_surrogate = wc;
      continue;
    }
    WCHAR pair[2];
    int pair_len = 0;
    if (wc >= 0xDC00 && wc <= 0xDFFF && g_pending_high_surrogate != 0) {
      pair[0] = g_pending_high_surrogate;
      pair[1] = wc;
      pair_len = 2;
      g_pending_high_surrogate = 0;
    } else {
      g_pending_high_surrogate = 0;
      pair[0] = wc;
      pair_len = 1;
    }
    int n = WideCharToMultiByte(CP_UTF8, 0, pair, pair_len, (char *)out_buf,
                                max_len, NULL, NULL);
    if (n > 0) return n;
  }
}

#else /* POSIX */

#include <errno.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>

static int g_raw_active = 0;
static int g_atexit_registered = 0;
static struct termios g_orig_termios;

static void moonset_tty_restore_atexit(void) {
  if (!g_raw_active) return;
  const char reset_seq[] = "\x1b[0m\x1b[?25h";
  ssize_t ignored = write(STDOUT_FILENO, reset_seq, sizeof(reset_seq) - 1);
  (void)ignored;
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
  g_raw_active = 0;
}

int moonset_tty_is_tty(void) {
  return (isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)) ? 1 : 0;
}

int moonset_tty_enable_color(int is_stderr) {
  return isatty(is_stderr ? STDERR_FILENO : STDOUT_FILENO) ? 1 : 0;
}

int moonset_tty_enter_raw(void) {
  if (g_raw_active) return 0;
  if (tcgetattr(STDIN_FILENO, &g_orig_termios) != 0) return -1;
  struct termios raw = g_orig_termios;
  raw.c_iflag &= ~(unsigned long)(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  /* Keep OPOST enabled so '\n' translates to '\r\n' cleanly */
  raw.c_cflag |= (unsigned long)(CS8);
  raw.c_lflag &= ~(unsigned long)(ECHO | ICANON | IEXTEN | ISIG);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) return -1;
  g_raw_active = 1;
  if (!g_atexit_registered) {
    atexit(moonset_tty_restore_atexit);
    g_atexit_registered = 1;
  }
  return 0;
}

int moonset_tty_leave_raw(void) {
  moonset_tty_restore_atexit();
  return 0;
}

int moonset_tty_cols(void) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
    return (int)ws.ws_col;
  }
  return 80;
}

int moonset_tty_rows(void) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0) {
    return (int)ws.ws_row;
  }
  return 24;
}

void moonset_tty_write_utf8(const uint8_t *buf, int len) {
  if (buf == NULL || len <= 0) return;
  int offset = 0;
  while (offset < len) {
    ssize_t n = write(STDOUT_FILENO, buf + offset, (size_t)(len - offset));
    if (n < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (n == 0) break;
    offset += (int)n;
  }
}

static int read_byte_timeout(uint8_t *b, int timeout_ms) {
  fd_set rfds;
  FD_ZERO(&rfds);
  FD_SET(STDIN_FILENO, &rfds);
  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  int r = select(STDIN_FILENO + 1, &rfds, NULL, NULL, &tv);
  if (r <= 0) return 0;
  ssize_t n = read(STDIN_FILENO, b, 1);
  return (n == 1) ? 1 : 0;
}

int moonset_tty_read_event(uint8_t *out_buf, int max_len) {
  if (out_buf == NULL || max_len <= 0) return -1;
  uint8_t b0 = 0;
  for (;;) {
    ssize_t n = read(STDIN_FILENO, &b0, 1);
    if (n < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    if (n == 0) return -1;
    break;
  }
  out_buf[0] = b0;
  int count = 1;

  if (b0 == 0x1b) {
    /* Disambiguate bare Escape from CSI / SS3 escape sequence (20ms timeout) */
    uint8_t b1 = 0;
    if (count < max_len && read_byte_timeout(&b1, 20)) {
      out_buf[count++] = b1;
      if (b1 == '[' || b1 == 'O') {
        while (count < max_len) {
          uint8_t next = 0;
          if (!read_byte_timeout(&next, 10)) break;
          out_buf[count++] = next;
          if ((next >= 'A' && next <= 'Z') || (next >= 'a' && next <= 'z') ||
              next == '~') {
            break;
          }
        }
      }
    }
    return count;
  }

  /* Assemble complete multi-byte UTF-8 scalar (CJK, emoji, etc.) */
  int expected = 1;
  if ((b0 & 0xE0) == 0xC0) expected = 2;
  else if ((b0 & 0xF0) == 0xE0) expected = 3;
  else if ((b0 & 0xF8) == 0xF0) expected = 4;

  while (count < expected && count < max_len) {
    uint8_t next = 0;
    ssize_t n = read(STDIN_FILENO, &next, 1);
    if (n < 0 && errno == EINTR) continue;
    if (n != 1) break;
    out_buf[count++] = next;
  }
  return count;
}

#endif
