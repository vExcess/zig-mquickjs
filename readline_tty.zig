//
// Readline TTY support
//
// Copyright (c) 2017-2025 Fabrice Bellard
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

// Ported from C to Zig by VExcess

const std = @import("std");
const builtin = @import("builtin");
const readline = @import("./readline.zig");
const cutils = @import("./cutils.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdarg.h");
});

extern "c" fn printf(fmt: [*c]const u8, ...) c_int;
extern "c" fn atexit(func: ?*const fn () callconv(.c) void) c_int;
extern "c" fn signal(signum: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*anyopaque;

const BOOL = cutils.BOOL;
const FALSE = cutils.FALSE;
const TRUE = cutils.TRUE;

const READLINE_RET_EXIT = readline.READLINE_RET_EXIT;
const READLINE_RET_NOT_HANDLED = readline.READLINE_RET_NOT_HANDLED;
const READLINE_RET_HANDLED = readline.READLINE_RET_HANDLED;
const READLINE_RET_ACCEPTED = readline.READLINE_RET_ACCEPTED;

const ReadlineState = readline.ReadlineState;
const readline_start = readline.readline_start;
const readline_handle_byte = readline.readline_handle_byte;

var ctrl_c_pressed: c_int = 0;

// ---------- START windows implementation START ----------
const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
const ENABLE_WINDOW_INPUT: u32 = 0x0008;
const ENABLE_PROCESSED_OUTPUT: u32 = 0x0001;
const ENABLE_WRAP_AT_EOL_OUTPUT: u32 = 0x0002;

const CTRL_C_EVENT: u32 = 0;

extern "c" fn _get_osfhandle(fd: c_int) isize;
extern "c" fn _setmode(fd: c_int, mode: c_int) c_int;
extern "system" fn SetConsoleMode(hConsoleHandle: isize, dwMode: u32) c_int;
extern "system" fn GetConsoleMode(hConsoleHandle: isize, lpMode: *u32) c_int;
extern "system" fn SetConsoleCtrlHandler(HandlerRoutine: ?*const fn (u32) callconv(.WINAPI) c_int, Add: c_int) c_int;

const COORD = extern struct { X: i16, Y: i16 };
const SMALL_RECT = extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 };
const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: u16,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};
extern "system" fn GetConsoleScreenBufferInfo(hConsoleOutput: isize, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) c_int;

// Windows 10 built-in VT100 emulation
const __ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
const __ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

pub const ctrl_handler = switch(builtin.os.tag) {
    .windows => (struct {
        fn ctrl_handler(dwCtrlType: u32) callconv(.WINAPI) BOOL {
            if (dwCtrlType == CTRL_C_EVENT) {
                ctrl_c_pressed += 1;
                if (ctrl_c_pressed >= 4) {
                    // just to be able to stop the process if it is hanged
                    return FALSE;
                } else {
                    return TRUE;
                }
            } else {
                return FALSE;
            }
        }
    }).ctrl_handler,
    else => @panic("windows only function"),
};

// if processed input is enabled, Ctrl-C is handled by ctrl_handler()
pub const set_processed_input = switch(builtin.os.tag) {
    .windows => (struct {
        fn set_processed_input(enable: BOOL) void {
            var mode: u32 = 0;
            const handle = _get_osfhandle(0);
            if (GetConsoleMode(handle, &mode) == 0) return;
            
            if (enable != 0) {
                mode |= ENABLE_PROCESSED_INPUT;
            } else {
                mode &= ~ENABLE_PROCESSED_INPUT;
            }
            _ = SetConsoleMode(handle, mode);
        }
    }).set_processed_input,
    else => @panic("windows only function"),
};
// ---------- END windows implementation END ----------

// ---------- START posix implementation START ----------
// init terminal so that we can grab keys
// XXX: merge with cp_utils.c
var oldtty: std.posix.termios = undefined;
var old_fd0_flags: i32 = 0;

pub const term_exit = switch(builtin.os.tag) {
    .windows => @panic("posix only function"),
    else => (struct {
        fn term_exit() callconv(.c) void {
            _ = std.posix.tcsetattr(0, std.posix.TCSA.NOW, oldtty) catch {};
            _ = std.posix.fcntl(0, std.posix.F.SETFL, @as(usize, @intCast(old_fd0_flags))) catch {};
        }
    }).term_exit,
};

pub const sigint_handler = switch(builtin.os.tag) {
    .windows => @panic("posix only function"),
    else => (struct {
        fn sigint_handler(signo: c_int) callconv(.c) void {
            _ = signo;
            ctrl_c_pressed += 1;
            if (ctrl_c_pressed >= 4) {
                // just to be able to stop the process if it is hanged
                const SIGINT = 2;
                const SIG_DFL = 0;
                _ = signal(SIGINT, @as(?*const fn(c_int) callconv(.c) void, @ptrFromInt(SIG_DFL))); 
            }
        }
    }).sigint_handler,
};

// ---------- END posix implementation END ----------

pub export const readline_tty_init = switch(builtin.os.tag) {
    .windows => (struct {
        // windows implementation
        fn readline_tty_init() callconv(.c) c_int {
            var handle = _get_osfhandle(0);
            _ = SetConsoleMode(handle, ENABLE_WINDOW_INPUT | __ENABLE_VIRTUAL_TERMINAL_INPUT);
            const _O_BINARY = 0x8000;
            _ = _setmode(0, _O_BINARY);

            handle = _get_osfhandle(1); // corresponding output
            _ = SetConsoleMode(handle, ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT | __ENABLE_VIRTUAL_TERMINAL_PROCESSING);

            _ = SetConsoleCtrlHandler(ctrl_handler, TRUE);

            var n_cols: c_int = 80;
            var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
            if (GetConsoleScreenBufferInfo(handle, &info) != 0) {
                n_cols = info.dwSize.X;
            }
            return n_cols;
        }
    }).readline_tty_init,
    else => (struct {
        // posix implementation
        fn readline_tty_init() callconv(.c) c_int {
            const P = std.posix;

            var tty = P.tcgetattr(0) catch @panic("tcgetattr failed");
            oldtty = tty;
            old_fd0_flags = @as(i32, @intCast(P.fcntl(0, P.F.GETFL, 0) catch 0));

            tty.iflag.IGNBRK = false; // Ignore break condition.
            tty.iflag.BRKINT = false; // Signal interrupt on break.
            tty.iflag.PARMRK = false; // Mark parity and framing errors.
            tty.iflag.ISTRIP = false; // Strip 8th bit off characters.
            tty.iflag.INLCR = false; // Map NL to CR on input.
            tty.iflag.IGNCR = false; // Ignore CR.
            tty.iflag.ICRNL = false; // Map CR to NL on input.
            tty.iflag.IXON = false; // Enable start/stop output control.
            
            tty.oflag.OPOST = true;
            
            tty.lflag.ECHO = false;
            tty.lflag.ECHONL = false;
            tty.lflag.ICANON = false;
            tty.lflag.IEXTEN = false;
            // tty.c_lflag &= ~ISIG; /* ctrl-C returns a signal

            tty.cflag.PARENB = false;
            tty.cflag.CSIZE = std.posix.CSIZE.CS8;

            tty.cc[@as(usize, @intFromEnum(P.V.MIN))] = 1;
            tty.cc[@as(usize, @intFromEnum(P.V.TIME))] = 0;

            _ = P.tcsetattr(0, P.TCSA.NOW, tty) catch {};

            var sa: std.posix.Sigaction = undefined;
            @memset(std.mem.asBytes(&sa), 0);
            sa.handler = .{ .handler = sigint_handler };
            sa.flags = 0;
            sa.mask = P.sigemptyset();
            P.sigaction(P.SIG.INT, &sa, null);

            _ = atexit(term_exit);

            //    fcntl(0, F_SETFL, O_NONBLOCK);
            var n_cols: c_int = 80;
            var ws: P.winsize = undefined;
            
            if (
                P.system.ioctl(0, P.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and
                ws.col >= 4 and ws.row >= 4            
            ) {
                n_cols = ws.col;
            }
            return n_cols;
        }
    }).readline_tty_init,
};

pub fn term_printf(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    const c_ap: [*c]c.struct___va_list_tag_1 = @ptrCast(&ap);
    _ = c.vprintf(fmt, c_ap);
    @cVaEnd(&ap);
}

pub fn term_flush() void {
    _= c.fflush(c.stdout);
}

export fn readline_tty(s: *ReadlineState, prompt: [*c]const u8, multi_line: BOOL) [*c]const u8 {
    _ = multi_line; // Appears unused in the original code as well
    var buf: [128]u8 = undefined;
    var ret_str: ?[*]const u8 = null;

    if (builtin.os.tag == .windows) {
        set_processed_input(FALSE);
        // ctrl-C is no longer handled by the system
    }

    readline_start(s, prompt, FALSE);
    var ctrl_c_count: c_int = 0;
    var exit_loop = false;

    while (ret_str == null and !exit_loop) {
        const len_result = std.posix.read(0, &buf) catch 0;
        if (len_result == 0) break;

        var i: usize = 0;
        while (i < len_result) : (i += 1) {
            const ch: c_int = buf[i];
            
            if (builtin.os.tag == .windows and ch == 3) {
                // ctrl-C
                ctrl_c_pressed += 1;
            } else {
                const ret = readline_handle_byte(s, ch);
                if (ret == READLINE_RET_EXIT) {
                    exit_loop = true;
                    break;
                } else if (ret == READLINE_RET_ACCEPTED) {
                    ret_str = s.term_cmd_buf;
                    exit_loop = true;
                    break;
                }
                ctrl_c_count = 0;
            }
        }

        if (exit_loop) break;

        if (ctrl_c_pressed != 0) {
            ctrl_c_pressed = 0;
            if (ctrl_c_count == 0) {
                _ = printf("(Press Ctrl-C again to quit)\n");
                ctrl_c_count += 1;
            } else {
                _ = printf("Exiting.\n");
                break;
            }
        }
    }

    if (builtin.os.tag == .windows) {
        set_processed_input(TRUE);
    }

    return if (ret_str) |ptr| ptr else null;
}

export fn readline_is_interrupted() BOOL {
    const ret: BOOL = if (ctrl_c_pressed != 0) TRUE else FALSE;
    ctrl_c_pressed = 0;
    return ret;
}