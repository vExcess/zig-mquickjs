//
// Micro QuickJS engine lexer (shared implementation)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by VExcess
//

const std = @import("std");
const cutils = @import("cutils_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const lt = @import("mquickjs_lexer_types.zig");
const vt = lt.vt;
const mc = lt.mc;
pub const c = lt.c;

extern fn string_buffer_push(ctx: *c.JSContext, s: *anyopaque, len: c_int) c_int;
extern fn string_buffer_putc(ctx: *c.JSContext, s: *anyopaque, ch: c_int) c_int;
extern fn string_buffer_pop(ctx: *c.JSContext, s: *anyopaque) c.JSValue;
extern fn js_alloc_string(ctx: *c.JSContext, buf_len: u32) ?*anyopaque;
extern fn js_alloc_byte_array(ctx: *c.JSContext, size: c_int) ?*anyopaque;
extern fn JS_MakeUniqueString(ctx: *c.JSContext, val: c.JSValue) c.JSValue;
extern fn is_ascii_string(buf: [*c]const u8, len: usize) c.JS_BOOL;
extern fn js_atod(str: [*c]const u8, pnext: [*c][*c]const u8, radix: c_int, flags: c_int, tmp_mem: *c.JSATODTempMem) f64;
extern fn js_parse_regexp_flags(pre_flags: *c_int, buf: [*]const u8) usize;
extern fn js_parse_error(s: *lt.JSParseState, fmt: [*:0]const u8, ...) noreturn;

fn pushValue(ctx: *c.JSContext, ref: *c.JSGCRef, val: c.JSValue) void {
    _ = utils.JS_PushGCRef(ctx, ref);
    ref.val = val;
}

fn popValue(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    return utils.JS_PopGCRef(ctx, ref);
}

fn unicodeFromUtf8(p: [*]const u8, max_len: usize, plen: *usize) c_int {
    if (p[0] < 0x80) {
        plen.* = 1;
        return p[0];
    }
    return cutils.unicode_from_utf8(p, max_len, plen);
}

fn srcOff(s: *const lt.JSParseState, p: [*]const u8) u32 {
    return @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
}

pub fn get_line_col(pcol_num: *c_int, buf: [*]const u8, len: usize) c_int {
    var line_num: c_int = 0;
    var col_num: c_int = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const ch = buf[i];
        if (ch == '\n') {
            line_num += 1;
            col_num = 0;
        } else if (ch < 0x80 or ch >= 0xc0) {
            col_num += 1;
        }
    }
    pcol_num.* = col_num;
    return line_num;
}

pub fn js_parse_error_mem(s: *lt.JSParseState) noreturn {
    js_parse_error(s, "not enough memory");
}

pub fn js_parse_error_stack_overflow(s: *lt.JSParseState) noreturn {
    js_parse_error(s, "stack overflow");
}

pub fn js_parse_expect1(s: *lt.JSParseState, ch: c_int) void {
    if (s.token.val != ch)
        js_parse_error(s, "expecting '%c'", ch);
}

pub fn js_parse_expect(s: *lt.JSParseState, ch: c_int) void {
    js_parse_expect1(s, ch);
    next_token(s);
}

pub fn js_parse_expect_semi(s: *lt.JSParseState) void {
    if (s.token.val != ';') {
        if (s.token.val == lt.TOK_EOF or s.token.val == '}' or s.got_lf != 0) {
            return;
        }
        js_parse_error(s, "expecting '%c'", @as(c_int, ';'));
    }
    next_token(s);
}

pub fn js_skip_parens(s: *lt.JSParseState, pfunc_name: ?*c.JSValue) c_int {
    var state: [128]u8 = undefined;
    var level: usize = 0;
    var bits: c_int = 0;

    state[level] = 0;
    level += 1;
    while (true) {
        switch (s.token.val) {
            '(' => {
                if (level >= state.len)
                    js_parse_error(s, "too many nested blocks");
                state[level] = ')';
                level += 1;
            },
            '[' => {
                if (level >= state.len)
                    js_parse_error(s, "too many nested blocks");
                state[level] = ']';
                level += 1;
            },
            '{' => {
                if (level >= state.len)
                    js_parse_error(s, "too many nested blocks");
                state[level] = '}';
                level += 1;
            },
            ')', ']', '}' => {
                level -= 1;
                const expected: c_int = state[level];
                if (s.token.val != expected)
                    js_parse_error(s, "expecting '%c'", expected);
            },
            lt.TOK_EOF => {
                js_parse_error(s, "expecting '%c'", @as(c_int, state[level - 1]));
            },
            lt.TOK_IDENT => {
                if (s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_arguments))
                    bits |= lt.SKIP_HAS_ARGUMENTS;
                if (pfunc_name) |pname| {
                    if (s.token.value == pname.*)
                        bits |= lt.SKIP_HAS_FUNC_NAME;
                }
            },
            ';' => {
                if (level == 2)
                    bits |= lt.SKIP_HAS_SEMI;
            },
            else => {},
        }
        next_token(s);
        if (level <= 1)
            break;
    }
    return bits;
}

pub fn js_skip_expr(s: *lt.JSParseState) void {
    while (true) {
        switch (s.token.val) {
            ')' => return,
            ';', lt.TOK_EOF => {
                js_parse_error(s, "expecting '%c'", @as(c_int, ')'));
            },
            '(', '[', '{' => {
                _ = js_skip_parens(s, null);
            },
            else => {
                next_token(s);
            },
        }
    }
}

pub fn is_regexp_allowed(tok: c_int) c.JS_BOOL {
    switch (tok) {
        lt.TOK_NUMBER,
        lt.TOK_STRING,
        lt.TOK_REGEXP,
        lt.TOK_DEC,
        lt.TOK_INC,
        lt.TOK_NULL,
        lt.TOK_FALSE,
        lt.TOK_TRUE,
        lt.TOK_THIS,
        lt.TOK_IF,
        lt.TOK_WHILE,
        lt.TOK_FOR,
        lt.TOK_DO,
        lt.TOK_CASE,
        lt.TOK_CATCH,
        ')',
        ']',
        lt.TOK_IDENT,
        => return c.FALSE,
        else => return c.TRUE,
    }
}

pub fn js_parse_get_pos(s: *lt.JSParseState, sp: *lt.JSParsePos) void {
    sp.source_pos = s.token.source_pos;
    sp.got_lf = s.got_lf;
    sp.regexp_allowed = @intCast(is_regexp_allowed(s.token.val));
}

pub fn js_parse_seek_token(s: *lt.JSParseState, sp: *const lt.JSParsePos) void {
    s.buf_pos = sp.source_pos;
    s.got_lf = sp.got_lf;
    s.token.val = if (sp.regexp_allowed != 0) ' ' else ')';
    next_token(s);
}

pub fn js_parse_skip_parens_token(s: *lt.JSParseState) c_int {
    var pos: lt.JSParsePos = undefined;
    js_parse_get_pos(s, &pos);
    const bits = js_skip_parens(s, null);
    js_parse_seek_token(s, &pos);
    return bits;
}

pub fn js_parse_escape(buf: [*]const u8, plen: *usize) c_int {
    var p = buf;
    var ch: c_int = p[0];
    p += 1;
    switch (ch) {
        'b' => ch = '\x08',
        'f' => ch = '\x0c',
        'n' => ch = '\n',
        'r' => ch = '\r',
        't' => ch = '\t',
        'v' => ch = '\x0b',
        '\'', '\"', '\\' => {},
        'x' => {
            const h0 = lt.fromHex(p[0]);
            p += 1;
            if (h0 < 0)
                return -1;
            const h1 = lt.fromHex(p[0]);
            p += 1;
            if (h1 < 0)
                return -1;
            ch = (h0 << 4) | h1;
        },
        'u' => {
            if (p[0] == '{') {
                p += 1;
                ch = 0;
                while (true) {
                    const h = lt.fromHex(p[0]);
                    p += 1;
                    if (h < 0)
                        return -1;
                    ch = (ch << 4) | h;
                    if (ch > 0x10FFFF)
                        return -1;
                    if (p[0] == '}')
                        break;
                }
                p += 1;
            } else {
                ch = 0;
                var i: c_int = 0;
                while (i < 4) : (i += 1) {
                    const h = lt.fromHex(p[0]);
                    p += 1;
                    if (h < 0)
                        return -1;
                    ch = (ch << 4) | h;
                }
            }
        },
        '0' => {
            ch -= '0';
            if (ch != 0 or vt.isNum(p[0]) != 0)
                return -1;
        },
        else => return -2,
    }
    plen.* = @intFromPtr(p) - @intFromPtr(buf);
    return ch;
}

pub fn js_parse_string(s: *lt.JSParseState, ppos: *u32, sep: c_int) c.JSValue {
    const ctx = s.ctx;
    var b: vt.StringBuffer = undefined;

    if (string_buffer_push(ctx, @ptrCast(&b), 16) != 0)
        js_parse_error_mem(s);
    var buf: [*]const u8 = s.source_buf;
    var pos = ppos.*;
    while (true) {
        var ch: u32 = buf[pos];
        if (ch == 0 or ch == '\n' or ch == '\r') {
            js_parse_error(s, "unexpected end of string");
        }
        pos += 1;
        if (ch == @as(u32, @intCast(sep)))
            break;
        if (ch == '\\') {
            if (buf[pos] == '\n') {
                pos += 1;
                continue;
            }
            var escape_len: usize = 0;
            const esc = js_parse_escape(buf + pos, &escape_len);
            if (esc == -1) {
                js_parse_error(s, "invalid escape sequence");
            } else if (esc == -2) {
                continue;
            }
            ch = @intCast(esc);
            pos += @intCast(escape_len);
        } else if (ch >= 0x80) {
            var clen: usize = 0;
            pos -= 1;
            const uc = unicodeFromUtf8(buf + pos, cutils.UTF8_CHAR_LEN_MAX, &clen);
            pos += @intCast(clen);
            if (uc == -1) {
                js_parse_error(s, "invalid UTF-8 sequence");
            }
            ch = @intCast(uc);
        }
        if (string_buffer_putc(ctx, @ptrCast(&b), @intCast(ch)) != 0)
            break;
        buf = s.source_buf;
    }
    ppos.* = pos;
    const res = string_buffer_pop(ctx, @ptrCast(&b));
    if (lt.isExactException(res))
        js_parse_error_mem(s);
    return res;
}

pub fn js_parse_ident(s: *lt.JSParseState, token: *lt.JSToken, ppos: *u32, first_c: c_int) void {
    const ctx = s.ctx;
    var b: vt.StringBuffer = undefined;

    if (string_buffer_push(ctx, @ptrCast(&b), 16) != 0)
        js_parse_error_mem(s);
    _ = string_buffer_putc(ctx, @ptrCast(&b), first_c);
    var buf: [*]const u8 = s.source_buf;
    var pos = ppos.*;
    while (pos < s.buf_len) {
        const ch: c_int = buf[pos];
        if (utils.is_ident_next(ch) == 0)
            break;
        pos += 1;
        if (string_buffer_putc(ctx, @ptrCast(&b), ch) != 0)
            break;
        buf = s.source_buf;
    }
    token.val = lt.TOK_IDENT;
    var val2 = string_buffer_pop(ctx, @ptrCast(&b));
    var val2_ref: c.JSGCRef = undefined;
    pushValue(ctx, &val2_ref, val2);
    const val = JS_MakeUniqueString(ctx, val2);
    val2 = popValue(ctx, &val2_ref);
    if (lt.isExactException(val))
        js_parse_error_mem(s);
    if (val != val2)
        utils.js_free(ctx, mc.valueToPtr(val2));
    token.value = val;
    if (lt.isPtr(val)) {
        const atom_start = mc.ctxExt(ctx).atom_table;
        const atom_last = atom_start + @as(usize, @intCast(c.JS_ATOM_yield));
        const ptr: [*]const c.JSWord = @ptrCast(@alignCast(mc.valueToPtr(val)));
        if (@intFromPtr(ptr) >= @intFromPtr(atom_start) and @intFromPtr(ptr) <= @intFromPtr(atom_last)) {
            const idx = (@intFromPtr(ptr) - @intFromPtr(atom_start)) / @sizeOf(c.JSWord);
            token.val = lt.TOK_NULL + @as(c_int, @intCast(idx));
        }
    }
    ppos.* = pos;
}

pub fn js_parse_regexp_token(s: *lt.JSParseState, ppos: *u32) void {
    const ctx = s.ctx;
    var in_class: bool = false;
    var pos = ppos.*;
    const start_pos: c_int = @intCast(pos);
    var clen: usize = 0;

    while (true) {
        var ch = unicodeFromUtf8(s.source_buf + pos, cutils.UTF8_CHAR_LEN_MAX, &clen);
        if (ch == -1)
            js_parse_error(s, "invalid UTF-8 sequence");
        pos += @intCast(clen);
        if (ch == 0 or ch == '\n' or ch == '\r') {
            js_parse_error(s, "unexpected line terminator in regexp");
        } else if (ch == '/') {
            if (!in_class)
                break;
        } else if (ch == '[') {
            in_class = true;
        } else if (ch == ']') {
            in_class = false;
        } else if (ch == '\\') {
            ch = unicodeFromUtf8(s.source_buf + pos, cutils.UTF8_CHAR_LEN_MAX, &clen);
            if (ch == -1)
                js_parse_error(s, "invalid UTF-8 sequence");
            if (ch == 0 or ch == '\n' or ch == '\r') {
                js_parse_error(s, "unexpected line terminator in regexp");
            }
            pos += @intCast(clen);
        }
    }
    const end_pos: c_int = @intCast(pos - 1);

    var re_flags: c_int = 0;
    clen = js_parse_regexp_flags(&re_flags, s.source_buf + pos);
    pos += @intCast(clen);
    if (utils.is_ident_next(s.source_buf[pos]) != 0)
        js_parse_error(s, "invalid regular expression flags");

    const str_len: u32 = @intCast(end_pos - start_pos);
    const p_raw = js_alloc_string(ctx, str_len) orelse js_parse_error_mem(s);
    const p: *vt.JSStringExt = @ptrCast(@alignCast(p_raw));
    vt.stringSetAscii(p, is_ascii_string(s.source_buf + @as(usize, @intCast(start_pos)), str_len) != 0);
    @memcpy(vt.stringBuf(p)[0..str_len], (s.source_buf + @as(usize, @intCast(start_pos)))[0..str_len]);

    ppos.* = pos;
    s.token.val = lt.TOK_REGEXP;
    s.token.value = mc.valueFromPtr(p);
    s.token.u.regexp.re_flags = @intCast(re_flags);
    s.token.u.regexp.re_end_pos = @intCast(end_pos);
}

pub fn next_token(s: *lt.JSParseState) void {
    var pos: u32 = s.buf_pos;
    s.got_lf = 0;
    s.token.value = c.JS_NULL;
    var p: [*]const u8 = s.source_buf + s.buf_pos;

    redo: while (true) {
        s.token.source_pos = srcOff(s, p);
        const ch = p[0];
        switch (ch) {
            0 => {
                s.token.val = lt.TOK_EOF;
                break :redo;
            },
            '"', '\'' => {
                p += 1;
                pos = srcOff(s, p);
                s.token.value = js_parse_string(s, &pos, ch);
                s.token.val = lt.TOK_STRING;
                p = s.source_buf + pos;
                break :redo;
            },
            '\n' => {
                s.got_lf = 1;
                p += 1;
                continue :redo;
            },
            ' ', '\t', '\x0c', '\x0b', '\r' => {
                p += 1;
                continue :redo;
            },
            '/' => {
                if (p[1] == '*') {
                    p += 2;
                    while (true) {
                        if (p[0] == 0)
                            js_parse_error(s, "unexpected end of comment");
                        if (p[0] == '*' and p[1] == '/') {
                            p += 2;
                            break;
                        }
                        p += 1;
                    }
                    continue :redo;
                } else if (p[1] == '/') {
                    p += 2;
                    while (true) {
                        if (p[0] == 0 or p[0] == '\n')
                            break;
                        p += 1;
                    }
                    continue :redo;
                } else if (is_regexp_allowed(s.token.val) != 0) {
                    p += 1;
                    pos = srcOff(s, p);
                    js_parse_regexp_token(s, &pos);
                    p = s.source_buf + pos;
                    break :redo;
                } else if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_DIV_ASSIGN;
                    break :redo;
                } else {
                    p += 1;
                    s.token.val = '/';
                    break :redo;
                }
            },
            'a'...'z', 'A'...'Z', '_', '$' => {
                p += 1;
                pos = srcOff(s, p);
                js_parse_ident(s, &s.token, &pos, ch);
                p = s.source_buf + pos;
                break :redo;
            },
            '.' => {
                if (utils.is_digit(p[1]) != 0) {
                    parseNumber(s, &p);
                } else {
                    s.token.val = '.';
                    p += 1;
                }
                break :redo;
            },
            '0' => {
                if (utils.is_digit(p[1]) != 0)
                    js_parse_error(s, "invalid number literal");
                parseNumber(s, &p);
                break :redo;
            },
            '1'...'9' => {
                parseNumber(s, &p);
                break :redo;
            },
            '*' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_MUL_ASSIGN;
                } else if (p[1] == '*') {
                    if (p[2] == '=') {
                        p += 3;
                        s.token.val = lt.TOK_POW_ASSIGN;
                    } else {
                        p += 2;
                        s.token.val = lt.TOK_POW;
                    }
                } else {
                    s.token.val = '*';
                    p += 1;
                }
                break :redo;
            },
            '%' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_MOD_ASSIGN;
                } else {
                    s.token.val = '%';
                    p += 1;
                }
                break :redo;
            },
            '+' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_PLUS_ASSIGN;
                } else if (p[1] == '+') {
                    p += 2;
                    s.token.val = lt.TOK_INC;
                } else {
                    s.token.val = '+';
                    p += 1;
                }
                break :redo;
            },
            '-' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_MINUS_ASSIGN;
                } else if (p[1] == '-') {
                    p += 2;
                    s.token.val = lt.TOK_DEC;
                } else {
                    s.token.val = '-';
                    p += 1;
                }
                break :redo;
            },
            '<' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_LTE;
                } else if (p[1] == '<') {
                    if (p[2] == '=') {
                        p += 3;
                        s.token.val = lt.TOK_SHL_ASSIGN;
                    } else {
                        p += 2;
                        s.token.val = lt.TOK_SHL;
                    }
                } else {
                    s.token.val = '<';
                    p += 1;
                }
                break :redo;
            },
            '>' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_GTE;
                } else if (p[1] == '>') {
                    if (p[2] == '>') {
                        if (p[3] == '=') {
                            p += 4;
                            s.token.val = lt.TOK_SHR_ASSIGN;
                        } else {
                            p += 3;
                            s.token.val = lt.TOK_SHR;
                        }
                    } else if (p[2] == '=') {
                        p += 3;
                        s.token.val = lt.TOK_SAR_ASSIGN;
                    } else {
                        p += 2;
                        s.token.val = lt.TOK_SAR;
                    }
                } else {
                    s.token.val = '>';
                    p += 1;
                }
                break :redo;
            },
            '=' => {
                if (p[1] == '=') {
                    if (p[2] == '=') {
                        p += 3;
                        s.token.val = lt.TOK_STRICT_EQ;
                    } else {
                        p += 2;
                        s.token.val = lt.TOK_EQ;
                    }
                } else {
                    s.token.val = '=';
                    p += 1;
                }
                break :redo;
            },
            '!' => {
                if (p[1] == '=') {
                    if (p[2] == '=') {
                        p += 3;
                        s.token.val = lt.TOK_STRICT_NEQ;
                    } else {
                        p += 2;
                        s.token.val = lt.TOK_NEQ;
                    }
                } else {
                    s.token.val = '!';
                    p += 1;
                }
                break :redo;
            },
            '&' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_AND_ASSIGN;
                } else if (p[1] == '&') {
                    p += 2;
                    s.token.val = lt.TOK_LAND;
                } else {
                    s.token.val = '&';
                    p += 1;
                }
                break :redo;
            },
            '^' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_XOR_ASSIGN;
                } else {
                    s.token.val = '^';
                    p += 1;
                }
                break :redo;
            },
            '|' => {
                if (p[1] == '=') {
                    p += 2;
                    s.token.val = lt.TOK_OR_ASSIGN;
                } else if (p[1] == '|') {
                    p += 2;
                    s.token.val = lt.TOK_LOR;
                } else {
                    s.token.val = '|';
                    p += 1;
                }
                break :redo;
            },
            else => {
                if (ch >= 128)
                    js_parse_error(s, "unexpected character");
                s.token.val = ch;
                p += 1;
                break :redo;
            },
        }
    }
    s.buf_pos = srcOff(s, p);
}

fn parseNumber(s: *lt.JSParseState, pp: *[*]const u8) void {
    var p = pp.*;
    const tmp_arr_ptr = js_alloc_byte_array(s.ctx, @intCast(@sizeOf(c.JSATODTempMem))) orelse
        js_parse_error_mem(s);
    const tmp_arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(tmp_arr_ptr));
    var p_char: [*c]const u8 = p;
    const d = js_atod(
        p_char,
        @ptrCast(&p_char),
        0,
        c.JS_ATOD_ACCEPT_BIN_OCT | c.JS_ATOD_ACCEPT_UNDERSCORES,
        @ptrCast(@alignCast(vt.byteArrayBuf(tmp_arr))),
    );
    utils.js_free(s.ctx, tmp_arr_ptr);
    p = p_char;
    if (std.math.isNan(d))
        js_parse_error(s, "invalid number literal");
    s.token.val = lt.TOK_NUMBER;
    s.token.u.d = d;
    pp.* = p;
}
