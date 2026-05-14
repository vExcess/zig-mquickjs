//
// readline utility
//
// Copyright (c) 2003-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
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
const mqjs = @import("./mqjs.zig");
const readline_tty = @import("./readline_tty.zig");
const cutils = @import("./cutils.zig");

const strlen = cutils.strlen;
const min_int = cutils.min_int;
const UTF8_CHAR_LEN_MAX = cutils.UTF8_CHAR_LEN_MAX;
const utf8_get = cutils.utf8_get;
const unicode_to_utf8 = cutils.unicode_to_utf8;

const FALSE = 0;
const TRUE = 1;

const ReadLineFunc = *const fn(*anyopaque, [*c]const u8) callconv(.c) void;
const ReadLineGetColor = *const fn([*c]c_int, [*c]const u8, c_int, c_int) callconv(.c) c_int;

pub const ReadlineState = extern struct {
    term_cmd_buf_index: c_int, // byte position in the command line
    term_cmd_buf_len: c_int, // byte length of the command line

    utf8_val: u32,
    term_cmd_updated: u8, // if the command line was updated
    utf8_state: u8,
    term_esc_state: u8,
    term_esc_param: c_int,
    term_esc_param1: c_int,
    term_esc_param2: c_int,
    term_cursor_x: c_int, // 0 <= term_cursor_x < term_width
    term_cursor_pos: c_int, // linear position

    term_hist_entry: c_int, // position in term_history  or -1
    term_history_size: c_int, // size of term_historyf
    term_is_password: u8,
    term_prompt: [*c]const u8,
    // the following fields must be initialized by the user
    term_width: c_int,
    term_cmd_buf_size: c_int,
    term_kill_buf_len: c_int,
    term_cmd_buf: [*c]u8, // allocated length is term_cmd_buf_size
    term_kill_buf: [*c]u8, // allocated length is term_cmd_buf_size
    term_history_buf_size: c_int,
    term_history: [*c]u8,
    get_color: ?ReadLineGetColor, // NULL if no colorization
};

const COLOR_NONE           =  0;
const COLOR_BLACK          =  1;
const COLOR_RED            =  2;
const COLOR_GREEN          =  3;
const COLOR_YELLOW         =  4;
const COLOR_BLUE           =  5;
const COLOR_MAGENTA        =  6;
const COLOR_CYAN           =  7;
const COLOR_WHITE          =  8;
const COLOR_GRAY           =  9;
const COLOR_BRIGHT_RED     = 10;
const COLOR_BRIGHT_GREEN   = 11;
const COLOR_BRIGHT_YELLOW  = 12;
const COLOR_BRIGHT_BLUE    = 13;
const COLOR_BRIGHT_MAGENTA = 14;
const COLOR_BRIGHT_CYAN    = 15;
const COLOR_BRIGHT_WHITE   = 16;

export const term_colors = [_][*c]const u8{
    "\x1b[0m",
    "\x1b[30m",
    "\x1b[31m",
    "\x1b[32m",
    "\x1b[33m",
    "\x1b[34m",
    "\x1b[35m",
    "\x1b[36m",
    "\x1b[37m",
    "\x1b[30;1m",
    "\x1b[31;1m",
    "\x1b[32;1m",
    "\x1b[33;1m",
    "\x1b[34;1m",
    "\x1b[35;1m",
    "\x1b[36;1m",
    "\x1b[37;1m",
};

const READLINE_RET_EXIT        = -1; 
const READLINE_RET_NOT_HANDLED =  0; // command not handled
const READLINE_RET_HANDLED     =  1; // command handled
const READLINE_RET_ACCEPTED    =  2; // return pressed
// return READLINE_RET_x
// return > 0 if command handled, -1 if exit */
// XXX: could process buffers to avoid redisplaying at each char input (copy paste case)
export fn readline_handle_byte(s: *ReadlineState, _c: c_int) c_int {
    var c = @as(u32, @intCast(_c));
    if (c >= 0xc0 and c < 0xf8) {
        s.utf8_state = 1 + (if (c >= 0xe0) @as(@TypeOf(s.utf8_state), 1) else @as(@TypeOf(s.utf8_state), 0)) + (if (c >= 0xf0) @as(@TypeOf(s.utf8_state), 1) else @as(@TypeOf(s.utf8_state), 0));
        s.utf8_val = c & ((@as(u32, 1) << @as(u5, @intCast(6 - s.utf8_state))) - 1);
        return READLINE_RET_HANDLED;
    }
    if (s.utf8_state != 0) {
        if (c >= 0x80 and c < 0xc0) {
            s.utf8_val = (s.utf8_val << 6) | (c & 0x3F);
            s.utf8_state -= 1;
            if (s.utf8_state != 0) {
                return READLINE_RET_HANDLED;
            }
            c = s.utf8_val;
        }
        s.utf8_state = 0;
    }
    return readline_handle_char(s, @intCast(c));
}

export fn readline_start(s: *ReadlineState, prompt: [*c]const u8, is_password: c_int) void {
    s.term_prompt = prompt;
    s.term_is_password = @as(u8, @intCast(is_password));
    s.term_hist_entry = -1;
    s.term_cmd_buf_index = 0;
    s.term_cmd_buf_len = 0;
    term_show_prompt(s);
}

// the following functions must be provided
const readline_find_completion = mqjs.readline_find_completion;
const term_printf = readline_tty.term_printf;
const term_flush = readline_tty.term_flush;


const IS_NORM = 0;
const IS_ESC = 1;
const IS_CSI = 2;

fn term_show_prompt2(s: *ReadlineState) void {
    _ = term_printf("%s", s.term_prompt);
    term_flush();
    // XXX: assuming no unicode chars
    s.term_cursor_x = @rem(@as(c_int, @intCast(strlen(s.term_prompt))), s.term_width);
    s.term_cursor_pos = 0;
    s.term_esc_state = IS_NORM;
    s.utf8_state = 0;
}

fn term_show_prompt(s: *ReadlineState) void {
    term_show_prompt2(s);
    s.term_cmd_buf_index = 0;
    s.term_cmd_buf_len = 0;
}

fn print_csi(n: c_int, code: c_int) void {
    if (n == 1) {
        term_printf("\x1b[%c", code);
    } else {
        term_printf("\x1b[%d%c", n, code);
    }
}

fn print_color(color: c_int) void {
    term_printf("%s", term_colors[@as(usize, @intCast(color))]);
}

fn move_cursor(s: *ReadlineState, _delta: c_int) void {
    var delta = _delta;
    if (delta > 0) {
        while (delta != 0) {
            if (s.term_cursor_x == (s.term_width - 1)) {
                term_printf("\r\n"); // translated to CRLF
                s.term_cursor_x = 0;
                delta -= 1;
            } else {
                const l = min_int(s.term_width - 1 - s.term_cursor_x, delta);
                print_csi(l, 'C'); // right
                delta -= l;
                s.term_cursor_x += l;
            }
        }
    } else if (delta < 0) {
        delta = -delta;
        while (delta != 0) {
            if (s.term_cursor_x == 0) {
                print_csi(1, 'A'); // up
                print_csi(s.term_width - 1, 'C'); // right
                delta -= 1;
                s.term_cursor_x = s.term_width - 1;
            } else {
                const l = min_int(delta, s.term_cursor_x);
                print_csi(l, 'D'); // left
                delta -= l;
                s.term_cursor_x -= l;
            }
        }
    }
}

fn char_width(ch: c_int) c_int {
    // XXX: complete or find a way to use wcwidth()
    if (ch < 0x100) {
        return 1;
    } else if (
        (ch >= 0x4E00 and ch <= 0x9FFF) or // CJK
        (ch >= 0xFF01 and ch <= 0xFF5E) or // fullwidth ASCII
        (ch >= 0x1F600 and ch <= 0x1F64F) // emoji
    ) {
        return 2;
    } else {
        return 1;
    }
}

// update the displayed command line
fn term_update(s: *ReadlineState) void {
    var new_cursor_pos: c_int = 0;
    var c_len: usize = undefined;
    var buf: [UTF8_CHAR_LEN_MAX + 1]u8 = undefined;

    if (s.term_cmd_updated != FALSE) {
        move_cursor(s, -s.term_cursor_pos);
        s.term_cursor_pos = 0;
        var last_color: c_int = COLOR_NONE;
        var color_len: c_int = 0;
        
        s.term_cmd_buf[@as(usize, @intCast(s.term_cmd_buf_len))] = 0; // add a trailing '\0' to ease colorization

        var i: c_int = 0;
        while (i < s.term_cmd_buf_len) : (i += @as(c_int, @intCast(c_len))) {
            if (i == s.term_cmd_buf_index) {
                new_cursor_pos = s.term_cursor_pos;
            }
            
            const c = utf8_get(s.term_cmd_buf + @as(usize, @intCast(i)), &c_len);
            var len: c_int = undefined;

            if (s.term_is_password != FALSE) {
                len = 1;
                buf[0] = '*';
                buf[1] = 0;
            } else {
                len = char_width(c);
                @memcpy(buf[0..c_len], s.term_cmd_buf[@as(usize, @intCast(i))..][0..c_len]);
                buf[c_len] = 0;
            }
            // the wide char does not fit so we display it on the next
            // line by enlarging the previous char
            if (s.term_cursor_x + len > s.term_width and i > 0) {
                while (s.term_cursor_x < s.term_width) {
                    term_printf(" ");
                    s.term_cursor_x += 1;
                    s.term_cursor_pos += 1;
                }
                s.term_cursor_x = 0;
            }
            s.term_cursor_pos += len;
            s.term_cursor_x += len;
            if (s.term_cursor_x >= s.term_width) {
                s.term_cursor_x = 0;
            }
            if (s.term_is_password == FALSE and s.get_color != null) {
                if (color_len == 0) {
                    const new_color = s.get_color.?(
                        &color_len,
                        @as([*c]const u8, @ptrCast(s.term_cmd_buf)),
                        i,
                        s.term_cmd_buf_len
                    );
                    if (new_color != last_color) {
                        last_color = new_color;
                        print_color(COLOR_NONE); // reset last color
                        print_color(last_color);
                    }
                }
                color_len -= 1;
            }
            term_printf("%s", &buf);
        }
        if (last_color != COLOR_NONE) {
            print_color(COLOR_NONE);
        }
        if (i == s.term_cmd_buf_index) {
            new_cursor_pos = s.term_cursor_pos;
        }
        if (s.term_cursor_x == 0) {
            // show the cursor on the next line
            term_printf(" \x08"); 
        }
        // remove the trailing characters
        print_csi(1, 'J'); 
        s.term_cmd_updated = FALSE;
    } else {
        // compute the new cursor pos without display
        var cursor_x = @rem((s.term_cursor_x - s.term_cursor_pos), s.term_width);
        if (cursor_x < 0) {
            cursor_x += s.term_width;
        }
        new_cursor_pos = 0;

        var i: c_int = 0;
        while (i < s.term_cmd_buf_index) : (i += @as(c_int, @intCast(c_len))) {
            var ch = utf8_get(s.term_cmd_buf + @as(usize, @intCast(i)), &c_len);
            if (s.term_is_password != FALSE) ch = '*';
            const len = char_width(ch);
            // the wide char does not fit so we display it on the next
            // line by enlarging the previous char
            if (cursor_x + len > s.term_width and i > 0) {
                new_cursor_pos += s.term_width - cursor_x;
                cursor_x = 0;
            }
            new_cursor_pos += len;
            cursor_x += len;
            if (cursor_x >= s.term_width) cursor_x = 0;
        }
    }
    move_cursor(s, new_cursor_pos - s.term_cursor_pos);
    s.term_cursor_pos = new_cursor_pos;
    term_flush();
}

fn term_kill_region(s: *ReadlineState, to: c_int, kill: c_int) void {
    var start = s.term_cmd_buf_index;
    var end = s.term_cmd_buf_index;

    if (to < start) {
        start = to;
    } else {
        end = to;
    }
    
    if (end > s.term_cmd_buf_len) {
        end = s.term_cmd_buf_len;
    }

    if (start < end) {
        const len = end - start;
        if (kill != 0) {
            @memcpy(s.term_kill_buf[0..@as(usize, @intCast(len))], s.term_cmd_buf[@as(usize, @intCast(start))..][0..@as(usize, @intCast(len))]);
            s.term_kill_buf_len = len;
        }
        const cpyAmt = s.term_cmd_buf_len - end;
        @memmove(s.term_cmd_buf[@as(usize, @intCast(start))..@as(usize, @intCast((start + cpyAmt)))], s.term_cmd_buf[@as(usize, @intCast(end))..@as(usize, @intCast(end + cpyAmt))]);
        s.term_cmd_buf_len -= len;
        s.term_cmd_buf_index = start;
        s.term_cmd_updated = TRUE;
    }
}

fn term_insert_region(s: *ReadlineState, p: [*c]const u8, len: c_int) void {
    const pos = s.term_cmd_buf_index;

    if (pos + len < s.term_cmd_buf_size) {
        const nchars = s.term_cmd_buf_len - pos;
        if (nchars > 0) {
            @memmove(s.term_cmd_buf[@as(usize, @intCast(pos + len))..][0..@as(usize, @intCast(nchars))], s.term_cmd_buf[@as(usize, @intCast(pos))..][0..@as(usize, @intCast(nchars))]);
        }
        @memcpy(s.term_cmd_buf[@as(usize, @intCast(pos))..@as(usize, @intCast(pos + len))], p[0..@as(usize, @intCast(len))]);
        s.term_cmd_buf_len += len;
        s.term_cmd_buf_index += len;
        s.term_cmd_updated = TRUE;
    }
}

fn term_insert_char(s: *ReadlineState, ch: c_int) void {
    var buf: [UTF8_CHAR_LEN_MAX + 1]u8 = undefined;
    const len = unicode_to_utf8(&buf, @intCast(ch));
    term_insert_region(s, &buf, @intCast(len));
}

fn is_utf8_ext(ch: c_int) bool {
    return (ch >= 0x80 and ch < 0xc0);
}

fn term_backward_char(s: *ReadlineState) void {
    if (s.term_cmd_buf_index > 0) {
        s.term_cmd_buf_index -= 1;
        while (s.term_cmd_buf_index > 0 and 
               is_utf8_ext(s.term_cmd_buf[@as(usize, @intCast(s.term_cmd_buf_index))])) {
            s.term_cmd_buf_index -= 1;
        }
    }
}

fn term_forward_char(s: *ReadlineState) void {
    var c_len: usize = undefined;
    if (s.term_cmd_buf_index < s.term_cmd_buf_len) {
        _ = utf8_get(s.term_cmd_buf + @as(usize, @intCast(s.term_cmd_buf_index)), &c_len);
        s.term_cmd_buf_index += @intCast(c_len);
    }
}

fn term_delete_char(s: *ReadlineState) void {
    var c_len: usize = undefined;
    if (s.term_cmd_buf_index < s.term_cmd_buf_len) {
        _ = utf8_get(s.term_cmd_buf + @as(usize, @intCast(s.term_cmd_buf_index)), &c_len);
        term_kill_region(s, s.term_cmd_buf_index + @as(c_int, @intCast(c_len)), 0);
    }
}

fn term_backspace(s: *ReadlineState) void {
    if (s.term_cmd_buf_index > 0) {
        term_backward_char(s);
        term_delete_char(s);
    }
}

fn skip_word_backward(s: *ReadlineState) c_int {
    var pos = s.term_cmd_buf_index;

    // skip whitespace backwards
    while (pos > 0 and std.ascii.isWhitespace(s.term_cmd_buf[@as(usize, @intCast(pos - 1))])) {
        pos -= 1;
    }

    // skip word backwards
    while (pos > 0 and !std.ascii.isWhitespace(s.term_cmd_buf[@as(usize, @intCast(pos - 1))])) {
        pos -= 1;
    }

    return pos;
}

fn skip_word_forward(s: *ReadlineState) c_int {
    var pos = s.term_cmd_buf_index;

    // skip whitespace
    while (pos < s.term_cmd_buf_len and std.ascii.isWhitespace(s.term_cmd_buf[@as(usize, @intCast(pos))])) {
        pos += 1;
    }
    
    // skip word
    while (pos < s.term_cmd_buf_len and !std.ascii.isWhitespace(s.term_cmd_buf[@as(usize, @intCast(pos))])) {
        pos += 1;
    }
    
    return pos;
}

fn term_skip_word_backward(s: *ReadlineState) void {
    s.term_cmd_buf_index = skip_word_backward(s);
}

fn term_skip_word_forward(s: *ReadlineState) void {
    s.term_cmd_buf_index = skip_word_forward(s);
}

fn term_yank(s: *ReadlineState) void {
    term_insert_region(s, s.term_kill_buf, s.term_kill_buf_len);
}

fn term_kill_word(s: *ReadlineState) void {
    term_kill_region(s, skip_word_forward(s), 1);
}

fn term_kill_word_backward(s: *ReadlineState) void {
    term_kill_region(s, skip_word_backward(s), 1);
}

fn term_bol(s: *ReadlineState) void {
    s.term_cmd_buf_index = 0;
}

fn term_eol(s: *ReadlineState) void {
    s.term_cmd_buf_index = s.term_cmd_buf_len;
}

fn update_cmdline_from_history(s: *ReadlineState) void {
    const hist_entry_size = strlen(s.term_history + @as(usize, @intCast(s.term_hist_entry)));
    @memcpy(s.term_cmd_buf[0..][0..hist_entry_size], s.term_history[@as(usize, @intCast(s.term_hist_entry))..][0..hist_entry_size]);
    s.term_cmd_buf_len = @intCast(hist_entry_size);
    s.term_cmd_buf_index = s.term_cmd_buf_len;
    s.term_cmd_updated = TRUE;
}

fn term_up_char(s: *ReadlineState) void {
    if (s.term_hist_entry == -1) {
        s.term_hist_entry = s.term_history_size;
        // XXX: should save current contents to history
    }
    if (s.term_hist_entry == 0) {
        return;
    }
    
    // move to previous entry
    var idx = s.term_hist_entry - 1;
    while (idx > 0 and s.term_history[@as(usize, @intCast(idx - 1))] != 0) {
        idx -= 1;
    }
    s.term_hist_entry = idx;
    update_cmdline_from_history(s);
}

fn term_down_char(s: *ReadlineState) void {
    if (s.term_hist_entry == -1) return;
    
    const hist_entry_size = @as(c_int, @intCast(strlen(s.term_history + @as(usize, @intCast(s.term_hist_entry))))) + 1;
    if (s.term_hist_entry + hist_entry_size < s.term_history_size) {
        s.term_hist_entry += hist_entry_size;
        update_cmdline_from_history(s);
    } else {
        s.term_hist_entry = -1;
        s.term_cmd_buf_index = s.term_cmd_buf_len;
    }
}

fn term_hist_add(s: *ReadlineState, cmdline: [*c]const u8) void {
    if (cmdline[0] == 0) return;
    
    const cmdline_size = @as(c_int, @intCast(strlen(cmdline))) + 1;
    const cmdline_size_usize = @as(usize, @intCast(cmdline_size));
    
    var remove_idx: c_int = -1;
    var remove_size: c_int = 0;

    if (s.term_hist_entry != -1) {
        // We were editing an existing history entry: replace it
        const idx = s.term_hist_entry;
        const hist_entry = s.term_history + @as(usize, @intCast(idx));
        const hist_entry_size = @as(c_int, @intCast(strlen(hist_entry))) + 1;
        
        if (
            hist_entry_size == cmdline_size and 
            std.mem.eql(u8, hist_entry[0..cmdline_size_usize], cmdline[0..cmdline_size_usize])
        ) {
            // schedule removing identical entry
            remove_idx = idx;
            remove_size = hist_entry_size;
        }
    }

    if (remove_idx == -1) {
        // Search cmdline in the history
        var idx: c_int = 0;
        while (idx < s.term_history_size) {
            const hist_entry = s.term_history + @as(usize, @intCast(idx));
            const hist_entry_size = @as(c_int, @intCast(strlen(hist_entry))) + 1;
            
            if (
                hist_entry_size == cmdline_size and 
                std.mem.eql(u8, hist_entry[0..cmdline_size_usize], cmdline[0..cmdline_size_usize])
            ) {
                // schedule removing identical entry
                remove_idx = idx;
                remove_size = hist_entry_size;
                break;
            }
            idx += hist_entry_size;
        }
    }

    if (remove_idx != -1) {
        // remove the identical entry
        const cpyAmt = @as(usize, @intCast(s.term_history_size - (remove_idx + remove_size)));
        @memmove(
            s.term_history[(@intCast(remove_idx))..][0..cpyAmt], 
            s.term_history[(@intCast(remove_idx + remove_size))..][0..cpyAmt],
        );
        s.term_history_size -= remove_size;
    }

    if (cmdline_size <= s.term_history_buf_size) {
        // remove history entries if not enough space
        while (s.term_history_size + cmdline_size > s.term_history_buf_size) {
            const hist_entry_size = @as(c_int, @intCast(strlen(s.term_history))) + 1;
            const cpyAmt = @as(usize, @intCast(s.term_history_size - hist_entry_size));
            @memmove(
                s.term_history[0..cpyAmt], 
                s.term_history[(@intCast(hist_entry_size))..][0..cpyAmt],
            );
            s.term_history_size -= hist_entry_size;
        }

        // add the cmdline
        @memcpy(
            s.term_history[@as(usize, @intCast(s.term_history_size))..][0..cmdline_size_usize], 
            cmdline[0..cmdline_size_usize]
        );
        s.term_history_size += cmdline_size;
    }
    s.term_hist_entry = -1;
}

fn term_return(s: *ReadlineState) void {
    s.term_cmd_buf[@as(usize, @intCast(s.term_cmd_buf_len))] = 0;
    if (s.term_is_password == FALSE) {
        term_hist_add(s, @as([*c]const u8, @ptrCast(s.term_cmd_buf)));
    }
    s.term_cmd_buf_index = s.term_cmd_buf_len;
}

fn readline_handle_char(s: *ReadlineState, ch: c_int) c_int {
    var ret: c_int = READLINE_RET_HANDLED;
    
    switch (s.term_esc_state) {
        IS_NORM => {
            switch (ch) {
                1 => term_bol(s), // ^A
                4 => { // ^D
                    if (s.term_cmd_buf_len == 0) {
                        _ = term_printf("^D\n");
                        return READLINE_RET_EXIT;
                    }
                    term_delete_char(s);
                },
                5 => term_eol(s), // ^E
                9 => {}, // TAB completion skipped
                10, 13 => {
                    term_return(s);
                    ret = READLINE_RET_ACCEPTED;
                },
                11 => term_kill_region(s, s.term_cmd_buf_len, 1), // ^K
                21 => term_kill_region(s, 0, 1), // ^U
                23 => term_kill_word_backward(s), // ^W
                25 => term_yank(s), // ^Y
                27 => s.term_esc_state = IS_ESC,
                127, 8 => term_backspace(s), // DEL, ^H
                155 => s.term_esc_state = IS_CSI, // 0x9B
                else => {
                    if (ch >= 32) {
                        term_insert_char(s, ch);
                    } else {
                        return 0;
                    }
                },
            }
        },
        IS_ESC => {
            s.term_esc_state = IS_NORM;
            switch (ch) {
                '[', 'O' => {
                    s.term_esc_state = IS_CSI;
                    s.term_esc_param2 = 0;
                    s.term_esc_param1 = 0;
                    s.term_esc_param = 0;
                },
                13 => term_return(s), // ESC+RET or M-RET: validate in multi-line
                8, 127 => term_kill_word_backward(s),
                'b' => term_skip_word_backward(s),
                'd' => term_kill_word(s),
                'f' => term_skip_word_forward(s),
                else => return 0,
            }
        },
        IS_CSI => {
            s.term_esc_state = IS_NORM;
            switch (ch) {
                'A' => term_up_char(s),
                'B', 'E' => term_down_char(s),
                'D' => term_backward_char(s),
                'C' => term_forward_char(s),
                'F' => term_eol(s),
                'H' => term_bol(s),
                ';' => {
                    s.term_esc_param2 = s.term_esc_param1;
                    s.term_esc_param1 = s.term_esc_param;
                    s.term_esc_param = 0;
                    s.term_esc_state = IS_CSI;
                },
                '0'...'9' => {
                    s.term_esc_param = s.term_esc_param * 10 + (ch - '0');
                    s.term_esc_state = IS_CSI;
                },
                '~' => {
                    switch (s.term_esc_param) {
                        1 => term_bol(s),
                        3 => term_delete_char(s),
                        4 => term_eol(s),
                        else => return READLINE_RET_NOT_HANDLED,
                    }
                },
                else => return READLINE_RET_NOT_HANDLED,
            }
        },
        else => unreachable,
    }
    term_update(s);
    if (ret == READLINE_RET_ACCEPTED) {
        _ = term_printf("\n");
    }
    return ret;
}
