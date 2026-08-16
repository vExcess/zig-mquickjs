//
// Micro QuickJS engine builtins — regexp (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const platform_abort = @import("platform_abort.zig");
const cutils = @import("cutils_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const bt = @import("mquickjs_builtins_types.zig");
const lt = bt.lt;
const pt = bt.pt;
const rt = bt.rt;
const vt = bt.vt;
const mc = bt.mc;
const c = bt.c;

const JSParseState = bt.JSParseState;
const REOP = bt.REOP;
const reopcode_info = bt.reopcode_info_data;

const parser = @import("mquickjs_parser_lib.zig");
const lexer = @import("mquickjs_lexer_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");

fn throwTypeError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn objPtr(val: c.JSValue) *mc.JSObjectExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn valueArr(val: c.JSValue) *vt.JSValueArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn byteArr(val: c.JSValue) *vt.JSByteArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn parseCall(cur_state: c_int, func: c_int, param: c_int) c_int {
    return cur_state | (func << 8) | (param << 16);
}

fn parsePushInt(s: *JSParseState, v: c_int) void {
    parser.js_parse_push_val(s, vt.newShortInt(v));
}

fn parsePopInt(s: *JSParseState) c_int {
    return vt.valueGetInt(parser.js_parse_pop_val(s));
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn minInt(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn maxInt(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn unicode_is_space_ascii(ch: u32) bool {
    return (ch >= 0x0009 and ch <= 0x000D) or (ch == 0x0020);
}

fn unicode_is_space_non_ascii(ch: u32) bool {
    return ch == 0x00A0 or
        ch == 0x1680 or
        (ch >= 0x2000 and ch <= 0x200A) or
        (ch >= 0x2028 and ch <= 0x2029) or
        ch == 0x202F or
        ch == 0x205F or
        ch == 0x3000 or
        ch == 0xFEFF;
}

pub fn rqsort_idx(
    nmemb: usize,
    cmp: *const fn (usize, usize, *anyopaque) c_int,
    swap: *const fn (usize, usize, *anyopaque) void,
    opaque_ptr: *anyopaque,
) void {
    const size: usize = 1;
    if (nmemb > 1) {
        var i = (nmemb / 2) * size;
        const n = nmemb * size;

        while (i > 0) {
            i -= size;
            var r = i;
            while (true) {
                var child = r * 2 + size;
                if (child >= n) break;
                if (child < n - size and cmp(child, child + size, opaque_ptr) <= 0)
                    child += size;
                if (cmp(r, child, opaque_ptr) > 0)
                    break;
                swap(r, child, opaque_ptr);
                r = child;
            }
        }
        i = n - size;
        while (i > 0) : (i -= size) {
            swap(0, i, opaque_ptr);

            var r: usize = 0;
            while (true) {
                var child = r * 2 + size;
                if (child >= i) break;
                if (child < i - size and cmp(child, child + size, opaque_ptr) <= 0)
                    child += size;
                if (cmp(r, child, opaque_ptr) > 0)
                    break;
                swap(r, child, opaque_ptr);
                r = child;
            }
        }
    }
}

fn get_u64(p: [*]const u8) u64 {
    return @as(*align(1) const u64, @ptrCast(p)).*;
}

fn put_u64(p: [*]u8, val: u64) void {
    @as(*align(1) u64, @ptrCast(p)).* = val;
}

fn maxUint32(a: u32, b: u32) u32 {
    return if (a > b) a else b;
}

fn minUint32(a: u32, b: u32) u32 {
    return if (a < b) a else b;
}

fn ptrOff(p: [*]const u8, base: [*]const u8) c_int {
    return @intCast(@intFromPtr(p) - @intFromPtr(base));
}

fn ptrAddI(p: [*]const u8, off: i32) [*]const u8 {
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, @bitCast(@intFromPtr(p))) + off)));
}

fn unicodeFromUtf8(buf: [*]const u8, max_len: usize, plen: *usize) c_int {
    if (buf[0] < 0x80) {
        plen.* = 1;
        return buf[0];
    }
    return cutils.unicode_from_utf8(buf, max_len, plen);
}

pub fn lre_get_capture_count(bc_buf: [*]const u8) c_int {
    return bc_buf[bt.RE_HEADER_CAPTURE_COUNT];
}

pub fn lre_get_alloc_count(bc_buf: [*]const u8) c_int {
    return bc_buf[bt.RE_HEADER_CAPTURE_COUNT] * 2 + bc_buf[bt.RE_HEADER_REGISTER_COUNT];
}

pub fn lre_get_flags(bc_buf: [*]const u8) c_int {
    return @intCast(mc.get_u16(bc_buf + bt.RE_HEADER_FLAGS));
}

fn re_emit_op(s: *JSParseState, op: c_int) void {
    parser.emit_u8(s, @intCast(op));
}

fn re_emit_op_u8(s: *JSParseState, op: c_int, val: u32) void {
    parser.emit_u8(s, @intCast(op));
    parser.emit_u8(s, @intCast(val));
}

fn re_emit_op_u16(s: *JSParseState, op: c_int, val: u32) void {
    parser.emit_u8(s, @intCast(op));
    parser.emit_u16(s, @intCast(val));
}

fn re_emit_op_u32(s: *JSParseState, op: c_int, val: u32) c_int {
    parser.emit_u8(s, @intCast(op));
    const pos: c_int = @intCast(s.byte_code_len);
    parser.emit_u32(s, val);
    return pos;
}

fn re_emit_goto(s: *JSParseState, op: c_int, val: c_int) c_int {
    parser.emit_u8(s, @intCast(op));
    const pos: c_int = @intCast(s.byte_code_len);
    parser.emit_u32(s, @bitCast(val - (pos + 4)));
    return pos;
}

fn re_emit_goto_u8(s: *JSParseState, op: c_int, arg: u32, val: c_int) c_int {
    parser.emit_u8(s, @intCast(op));
    parser.emit_u8(s, @intCast(arg));
    const pos: c_int = @intCast(s.byte_code_len);
    parser.emit_u32(s, @bitCast(val - (pos + 4)));
    return pos;
}

fn re_emit_goto_u8_u32(s: *JSParseState, op: c_int, arg0: u32, arg1: u32, val: c_int) c_int {
    parser.emit_u8(s, @intCast(op));
    parser.emit_u8(s, @intCast(arg0));
    parser.emit_u32(s, arg1);
    const pos: c_int = @intCast(s.byte_code_len);
    parser.emit_u32(s, @bitCast(val - (pos + 4)));
    return pos;
}

fn re_emit_char(s: *JSParseState, ch: c_int) void {
    var buf: [4]u8 = undefined;
    const n = cutils.unicode_to_utf8(&buf, @intCast(ch));
    re_emit_op(s, REOP.char1 + @as(c_int, @intCast(n)) - 1);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        parser.emit_u8(s, buf[i]);
    }
}

fn re_parse_expect(s: *JSParseState, ch: c_int) void {
    if (s.source_buf[s.buf_pos] != @as(u8, @intCast(ch)))
        lexer.js_parse_error(s, "expecting '%c'", ch);
    s.buf_pos += 1;
}

fn parse_digits(pp: *[*]const u8) c_int {
    var p = pp.*;
    var v: u64 = 0;
    while (true) {
        const ch = p[0];
        if (ch < '0' or ch > '9')
            break;
        v = v * 10 + ch - '0';
        if (v >= @as(u64, @intCast(vt.JS_SHORTINT_MAX)))
            v = @intCast(vt.JS_SHORTINT_MAX);
        p += 1;
    }
    pp.* = p;
    return @intCast(v);
}

fn re_need_check_adv_and_capture_init(pneed_capture_init: *bool, bc_buf: [*]const u8, bc_buf_len: c_int) bool {
    var need_check_adv = true;
    var need_capture_init = false;
    var pos: c_int = 0;
    while (pos < bc_buf_len) {
        const opcode: c_int = bc_buf[@intCast(pos)];
        var len: c_int = reopcode_info[@intCast(opcode)].size;
        switch (opcode) {
            REOP.range8 => {
                const val: u32 = bc_buf[@intCast(pos + 1)];
                len += @intCast(val * 2);
                need_check_adv = false;
            },
            REOP.range => {
                const val = mc.get_u16(bc_buf + @as(usize, @intCast(pos + 1)));
                len += @intCast(val * 8);
                need_check_adv = false;
            },
            REOP.char1, REOP.char2, REOP.char3, REOP.char4, REOP.dot, REOP.any, REOP.space, REOP.not_space => {
                need_check_adv = false;
            },
            REOP.line_start, REOP.line_start_m, REOP.line_end, REOP.line_end_m, REOP.set_i32, REOP.set_char_pos, REOP.word_boundary, REOP.not_word_boundary => {},
            REOP.save_start, REOP.save_end, REOP.save_reset => {},
            else => {
                need_capture_init = true;
                pneed_capture_init.* = need_capture_init;
                return need_check_adv;
            },
        }
        pos += len;
    }
    pneed_capture_init.* = need_capture_init;
    return need_check_adv;
}

fn get_class_atom(s: *JSParseState, inclass: bool) c_int {
    var p: [*]const u8 = @ptrCast(s.source_buf + s.buf_pos);
    var ch: u32 = p[0];
    switch (ch) {
        '\\' => {
            p += 1;
            ch = p[0];
            p += 1;
            switch (ch) {
                'd' => {
                    ch = @intCast(bt.CHAR_RANGE_d);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                'D' => {
                    ch = @intCast(bt.CHAR_RANGE_D);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                's' => {
                    ch = @intCast(bt.CHAR_RANGE_s);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                'S' => {
                    ch = @intCast(bt.CHAR_RANGE_S);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                'w' => {
                    ch = @intCast(bt.CHAR_RANGE_w);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                'W' => {
                    ch = @intCast(bt.CHAR_RANGE_W);
                    ch += @intCast(bt.CLASS_RANGE_BASE);
                },
                'c' => {
                    ch = p[0];
                    if ((ch >= 'a' and ch <= 'z') or
                        (ch >= 'A' and ch <= 'Z') or
                        (((ch >= '0' and ch <= '9') or ch == '_') and
                            inclass and !bt.reIsUnicode(s)))
                    {
                        ch &= 0x1f;
                        p += 1;
                    } else if (bt.reIsUnicode(s)) {
                        s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                        lexer.js_parse_error(s, "invalid escape sequence in regular expression");
                    } else {
                        p -= 1;
                        ch = '\\';
                    }
                },
                '-' => {
                    if (!inclass and bt.reIsUnicode(s)) {
                        s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                        lexer.js_parse_error(s, "invalid escape sequence in regular expression");
                    }
                },
                '^', '$', '\\', '.', '*', '+', '?', '(', ')', '[', ']', '{', '}', '|', '/' => {},
                else => {
                    p -= 1;
                    var len: usize = undefined;
                    const ret = lexer.js_parse_escape(p, &len);
                    if (ret < 0) {
                        if (bt.reIsUnicode(s)) {
                            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                            lexer.js_parse_error(s, "invalid escape sequence in regular expression");
                        } else {
                            var nlen: usize = undefined;
                            const nret = unicodeFromUtf8(p, cutils.UTF8_CHAR_LEN_MAX, &nlen);
                            if (nret < 0)
                                lexer.js_parse_error(s, "malformed unicode char");
                            p += nlen;
                            ch = @intCast(nret);
                            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                            return @intCast(ch);
                        }
                    }
                    p += len;
                    ch = @intCast(ret);
                },
            }
        },
        0, '/' => {
            if (@intFromPtr(p) - @intFromPtr(s.source_buf) >= s.buf_len)
                lexer.js_parse_error(s, "unexpected end");
            var len: usize = undefined;
            const ret = unicodeFromUtf8(p, cutils.UTF8_CHAR_LEN_MAX, &len);
            if (ret < 0)
                lexer.js_parse_error(s, "malformed unicode char");
            p += len;
            ch = @intCast(ret);
        },
        else => {
            var len: usize = undefined;
            const ret = unicodeFromUtf8(p, cutils.UTF8_CHAR_LEN_MAX, &len);
            if (ret < 0)
                lexer.js_parse_error(s, "malformed unicode char");
            p += len;
            ch = @intCast(ret);
        },
    }
    s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
    return @intCast(ch);
}

fn re_emit_range_base1(s: *JSParseState, tab: []const u16) void {
    for (tab) |v| {
        parser.emit_u32(s, v);
    }
}

fn re_emit_range_base(s: *JSParseState, ch: c_int) void {
    const invert = (ch & 1) != 0;
    if (invert)
        parser.emit_u32(s, 0);
    switch (ch & ~@as(c_int, 1)) {
        bt.CHAR_RANGE_d => {
            parser.emit_u32(s, 0x30);
            parser.emit_u32(s, 0x39 + 1);
        },
        bt.CHAR_RANGE_s => re_emit_range_base1(s, &bt.char_range_s),
        bt.CHAR_RANGE_w => re_emit_range_base1(s, &bt.char_range_w),
        else => platform_abort.abort(),
    }
    if (invert)
        parser.emit_u32(s, 0x110000);
}

fn range_sort_cmp(idx1: usize, idx2: usize, opaque_ptr: ?*anyopaque) c_int {
    const tab: [*]u8 = @ptrCast(opaque_ptr.?);
    return @bitCast(mc.get_u32(tab + 8 * idx1) -% mc.get_u32(tab + 8 * idx2));
}

fn range_sort_swap(idx1: usize, idx2: usize, opaque_ptr: ?*anyopaque) void {
    const tab: [*]u8 = @ptrCast(opaque_ptr.?);
    const tmp = get_u64(tab + 8 * idx1);
    put_u64(tab + 8 * idx1, get_u64(tab + 8 * idx2));
    put_u64(tab + 8 * idx2, tmp);
}

fn range_compress(tab: [*]u8, len: c_int) c_int {
    var i: c_int = 0;
    var j: c_int = 0;
    while (i < len) {
        const start = mc.get_u32(tab + @as(usize, @intCast(8 * i)));
        const end = mc.get_u32(tab + @as(usize, @intCast(8 * i + 4)));
        if (start == end) {
            // empty interval : remove
        } else if ((i + 1) < len) {
            const start2 = mc.get_u32(tab + @as(usize, @intCast(8 * i + 8)));
            const end2 = mc.get_u32(tab + @as(usize, @intCast(8 * i + 12)));
            if (end < start2) {
                mc.put_u32(tab + @as(usize, @intCast(8 * j)), start);
                mc.put_u32(tab + @as(usize, @intCast(8 * j + 4)), end);
                j += 1;
            } else {
                mc.put_u32(tab + @as(usize, @intCast(8 * i + 8)), start);
                mc.put_u32(tab + @as(usize, @intCast(8 * i + 12)), maxUint32(end, end2));
            }
        } else {
            mc.put_u32(tab + @as(usize, @intCast(8 * j)), start);
            mc.put_u32(tab + @as(usize, @intCast(8 * j + 4)), end);
            j += 1;
        }
        i += 1;
    }
    return j;
}

fn re_range_optimize(s: *JSParseState, range_start: c_int, invert: bool) void {
    var n: c_int = @intCast((s.byte_code_len - @as(u32, @intCast(range_start))) / 8);
    var arr = byteArr(s.byte_code);
    rqsort_idx(@intCast(n), range_sort_cmp, range_sort_swap, @ptrCast(vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start))));

    var n1 = range_compress(vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start)), n);
    s.byte_code_len -= @intCast((n - n1) * 8);

    if (invert) {
        parser.emit_insert(s, range_start, 4);
        arr = byteArr(s.byte_code);
        mc.put_u32(vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start)), 0);
        parser.emit_u32(s, 0x110000);
        arr = byteArr(s.byte_code);
        n = n1 + 1;
        n1 = range_compress(vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start)), n);
        s.byte_code_len -= @intCast((n - n1) * 8);
    }
    n = n1;

    if (n > 65534)
        lexer.js_parse_error(s, "range too big");

    if (n > 0 and n < 16) {
        const tab = vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start));
        var ch: u32 = mc.get_u32(tab + @as(usize, @intCast(8 * (n - 1) + 4)));
        if (ch < 254 or (ch == 0x110000 and
            mc.get_u32(tab + @as(usize, @intCast(8 * (n - 1)))) < 254))
        {
            s.byte_code_len = @intCast(range_start - 3);
            re_emit_op_u8(s, REOP.range8, @intCast(n));
            var i: c_int = 0;
            while (i < 2 * n) : (i += 1) {
                ch = mc.get_u32(tab + @as(usize, @intCast(4 * i)));
                if (ch == 0x110000)
                    ch = 0xff;
                parser.emit_u8(s, @intCast(ch));
            }
            return;
        }
    }

    mc.put_u16(vt.byteArrayBuf(arr) + @as(usize, @intCast(range_start - 2)), @intCast(n));
}

fn add_interval_intersect(s: *JSParseState, start_in: u32, end_in: u32, start1: u32, end1: u32, offset: i32) void {
    const start = maxUint32(start_in, start1);
    const end = minUint32(end_in, end1);
    if (start < end) {
        parser.emit_u32(s, start);
        parser.emit_u32(s, end);
        if (offset != 0) {
            parser.emit_u32(s, @intCast(@as(i32, @intCast(start)) + offset));
            parser.emit_u32(s, @intCast(@as(i32, @intCast(end)) + offset));
        }
    }
}

fn re_parse_char_class(s: *JSParseState) void {
    s.buf_pos += 1;

    var invert = false;
    if (s.source_buf[s.buf_pos] == '^') {
        s.buf_pos += 1;
        invert = true;
    }

    _ = re_emit_op_u16(s, REOP.range, 0);
    const range_start: c_int = @intCast(s.byte_code_len);

    while (true) {
        if (s.source_buf[s.buf_pos] == ']')
            break;

        const c1: u32 = @intCast(get_class_atom(s, true));
        if (s.source_buf[s.buf_pos] == '-' and s.source_buf[s.buf_pos + 1] != ']') {
            s.buf_pos += 1;
            if (c1 >= @as(u32, @intCast(bt.CLASS_RANGE_BASE)))
                lexer.js_parse_error(s, "invalid class range");
            const c2: u32 = @intCast(get_class_atom(s, true));
            if (c2 >= @as(u32, @intCast(bt.CLASS_RANGE_BASE)))
                lexer.js_parse_error(s, "invalid class range");
            if (c2 < c1)
                lexer.js_parse_error(s, "invalid class range");
            var c2b = c2;
            c2b += 1;
            if (bt.reIgnoreCase(s)) {
                add_interval_intersect(s, c1, c2b, 0, 'A', 0);
                add_interval_intersect(s, c1, c2b, 'Z' + 1, 'a', 0);
                add_interval_intersect(s, c1, c2b, 'z' + 1, @intCast(std.math.maxInt(i32)), 0);
                add_interval_intersect(s, c1, c2b, 'A', 'Z' + 1, 32);
                add_interval_intersect(s, c1, c2b, 'a', 'z' + 1, -32);
            } else {
                parser.emit_u32(s, c1);
                parser.emit_u32(s, c2b);
            }
        } else {
            if (c1 >= @as(u32, @intCast(bt.CLASS_RANGE_BASE))) {
                re_emit_range_base(s, @intCast(c1 - @as(u32, @intCast(bt.CLASS_RANGE_BASE))));
            } else {
                var c2 = c1;
                c2 += 1;
                if (bt.reIgnoreCase(s)) {
                    add_interval_intersect(s, c1, c2, 0, 'A', 0);
                    add_interval_intersect(s, c1, c2, 'Z' + 1, 'a', 0);
                    add_interval_intersect(s, c1, c2, 'z' + 1, @intCast(std.math.maxInt(i32)), 0);
                    add_interval_intersect(s, c1, c2, 'A', 'Z' + 1, 32);
                    add_interval_intersect(s, c1, c2, 'a', 'z' + 1, -32);
                } else {
                    parser.emit_u32(s, c1);
                    parser.emit_u32(s, c2);
                }
            }
        }
    }
    s.buf_pos += 1;
    re_range_optimize(s, range_start, invert);
}

fn re_parse_quantifier(s: *JSParseState, last_atom_start_in: c_int, last_capture_count: c_int) void {
    var last_atom_start = last_atom_start_in;
    var p: [*]const u8 = @ptrCast(s.source_buf + s.buf_pos);
    const ch: c_int = p[0];
    var quant_min: c_int = undefined;
    var quant_max: c_int = undefined;
    switch (ch) {
        '*' => {
            p += 1;
            quant_min = 0;
            quant_max = vt.JS_SHORTINT_MAX;
        },
        '+' => {
            p += 1;
            quant_min = 1;
            quant_max = vt.JS_SHORTINT_MAX;
        },
        '?' => {
            p += 1;
            quant_min = 0;
            quant_max = 1;
        },
        '{' => {
            if (!isDigit(p[1]))
                lexer.js_parse_error(s, "invalid repetition count");
            p += 1;
            quant_min = parse_digits(&p);
            quant_max = quant_min;
            if (p[0] == ',') {
                p += 1;
                if (isDigit(p[0])) {
                    quant_max = parse_digits(&p);
                    if (quant_max < quant_min)
                        lexer.js_parse_error(s, "invalid repetition count");
                } else {
                    quant_max = vt.JS_SHORTINT_MAX;
                }
            }
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            re_parse_expect(s, '}');
            p = @ptrCast(s.source_buf + s.buf_pos);
        },
        else => return,
    }

    var greedy = true;
    if (p[0] == '?') {
        p += 1;
        greedy = false;
    }
    s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));

    if (last_atom_start < 0)
        lexer.js_parse_error(s, "nothing to repeat");

    var need_capture_init = false;
    var arr = byteArr(s.byte_code);
    var add_zero_advance_check = re_need_check_adv_and_capture_init(
        &need_capture_init,
        vt.byteArrayBuf(arr) + @as(usize, @intCast(last_atom_start)),
        @intCast(s.byte_code_len - @as(u32, @intCast(last_atom_start))),
    );

    if (need_capture_init and last_capture_count != s.capture_count) {
        parser.emit_insert(s, last_atom_start, 3);
        var pos = last_atom_start;
        arr = byteArr(s.byte_code);
        const buf = vt.byteArrayBuf(arr);
        buf[@intCast(pos)] = @intCast(REOP.save_reset);
        pos += 1;
        buf[@intCast(pos)] = @intCast(last_capture_count);
        pos += 1;
        buf[@intCast(pos)] = s.capture_count - 1;
    }

    const len: c_int = @intCast(s.byte_code_len - @as(u32, @intCast(last_atom_start)));
    if (quant_min == 0) {
        if (!need_capture_init and last_capture_count != s.capture_count) {
            parser.emit_insert(s, last_atom_start, 3);
            arr = byteArr(s.byte_code);
            const buf = vt.byteArrayBuf(arr);
            buf[@intCast(last_atom_start)] = @intCast(REOP.save_reset);
            last_atom_start += 1;
            buf[@intCast(last_atom_start)] = @intCast(last_capture_count);
            last_atom_start += 1;
            buf[@intCast(last_atom_start)] = s.capture_count - 1;
            last_atom_start += 1;
        }
        if (quant_max == 0) {
            s.byte_code_len = @intCast(last_atom_start);
        } else if (quant_max == 1 or quant_max == vt.JS_SHORTINT_MAX) {
            const has_goto = quant_max == vt.JS_SHORTINT_MAX;
            parser.emit_insert(s, last_atom_start, 5 + @as(c_int, @intFromBool(add_zero_advance_check)) * 2);
            arr = byteArr(s.byte_code);
            const buf = vt.byteArrayBuf(arr);
            buf[@intCast(last_atom_start)] = @intCast(REOP.split_goto_first + @as(c_int, @intFromBool(greedy)));
            mc.put_u32(buf + @as(usize, @intCast(last_atom_start + 1)), @intCast(len + 5 * @as(c_int, @intFromBool(has_goto)) + @as(c_int, @intFromBool(add_zero_advance_check)) * 4));
            if (add_zero_advance_check) {
                buf[@intCast(last_atom_start + 1 + 4)] = @intCast(REOP.set_char_pos);
                buf[@intCast(last_atom_start + 1 + 4 + 1)] = 0;
                re_emit_op_u8(s, REOP.check_advance, 0);
            }
            if (has_goto)
                _ = re_emit_goto(s, REOP.goto, last_atom_start);
        } else {
            parser.emit_insert(s, last_atom_start, 11 + @as(c_int, @intFromBool(add_zero_advance_check)) * 2);
            var pos = last_atom_start;
            arr = byteArr(s.byte_code);
            const buf = vt.byteArrayBuf(arr);
            buf[@intCast(pos)] = @intCast(REOP.split_goto_first + @as(c_int, @intFromBool(greedy)));
            pos += 1;
            mc.put_u32(buf + @as(usize, @intCast(pos)), @intCast(6 + @as(c_int, @intFromBool(add_zero_advance_check)) * 2 + len + 10));
            pos += 4;
            buf[@intCast(pos)] = @intCast(REOP.set_i32);
            pos += 1;
            buf[@intCast(pos)] = 0;
            pos += 1;
            mc.put_u32(buf + @as(usize, @intCast(pos)), @bitCast(quant_max));
            pos += 4;
            last_atom_start = pos;
            if (add_zero_advance_check) {
                buf[@intCast(pos)] = @intCast(REOP.set_char_pos);
                pos += 1;
                buf[@intCast(pos)] = 0;
            }
            _ = re_emit_goto_u8_u32(s, (if (add_zero_advance_check) REOP.loop_check_adv_split_next_first else REOP.loop_split_next_first) - @as(c_int, @intFromBool(greedy)), 0, @bitCast(quant_max), last_atom_start);
        }
    } else if (quant_min == 1 and quant_max == vt.JS_SHORTINT_MAX and !add_zero_advance_check) {
        _ = re_emit_goto(s, REOP.split_next_first - @as(c_int, @intFromBool(greedy)), last_atom_start);
    } else {
        if (quant_min == quant_max)
            add_zero_advance_check = false;
        parser.emit_insert(s, last_atom_start, 6 + @as(c_int, @intFromBool(add_zero_advance_check)) * 2);
        var pos = last_atom_start;
        arr = byteArr(s.byte_code);
        const buf = vt.byteArrayBuf(arr);
        buf[@intCast(pos)] = @intCast(REOP.set_i32);
        pos += 1;
        buf[@intCast(pos)] = 0;
        pos += 1;
        mc.put_u32(buf + @as(usize, @intCast(pos)), @bitCast(quant_max));
        pos += 4;
        last_atom_start = pos;
        if (add_zero_advance_check) {
            buf[@intCast(pos)] = @intCast(REOP.set_char_pos);
            pos += 1;
            buf[@intCast(pos)] = 0;
        }
        if (quant_min == quant_max) {
            _ = re_emit_goto_u8(s, REOP.loop, 0, last_atom_start);
        } else {
            _ = re_emit_goto_u8_u32(s, (if (add_zero_advance_check) REOP.loop_check_adv_split_next_first else REOP.loop_split_next_first) - @as(c_int, @intFromBool(greedy)), 0, @bitCast(quant_max - quant_min), last_atom_start);
        }
    }
}

fn re_is_char(buf: [*]const u8, start: c_int, end: c_int) c_int {
    if (!(buf[@intCast(start)] >= REOP.char1 and buf[@intCast(start)] <= REOP.char4))
        return 0;
    const n: c_int = buf[@intCast(start)] - REOP.char1 + 1;
    if ((end - start) != (n + 1))
        return 0;
    return n;
}

pub fn re_parse_alternative(s: *JSParseState, state: c_int, dummy_param: c_int) callconv(.c) c_int {
    _ = dummy_param;
    var term_start: c_int = undefined;
    var last_term_start: c_int = undefined;
    var last_atom_start: c_int = undefined;
    var last_capture_count: c_int = undefined;
    var ch: c_int = undefined;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            last_term_start = -1;
            continue :sw 100;
        },
        100 => {
            if (s.buf_pos >= s.buf_len)
                return pt.PARSE_STATE_RET;
            term_start = @intCast(s.byte_code_len);
            last_atom_start = -1;
            last_capture_count = 0;
            ch = s.source_buf[s.buf_pos];
            switch (ch) {
                '|', ')' => return pt.PARSE_STATE_RET,
                '^' => {
                    s.buf_pos += 1;
                    re_emit_op(s, if (bt.reMultiLine(s)) REOP.line_start_m else REOP.line_start);
                },
                '$' => {
                    s.buf_pos += 1;
                    re_emit_op(s, if (bt.reMultiLine(s)) REOP.line_end_m else REOP.line_end);
                },
                '.' => {
                    s.buf_pos += 1;
                    last_atom_start = @intCast(s.byte_code_len);
                    last_capture_count = s.capture_count;
                    re_emit_op(s, if (bt.reDotall(s)) REOP.any else REOP.dot);
                },
                '{' => {
                    if (!bt.reIsUnicode(s) and !isDigit(s.source_buf[s.buf_pos + 1])) {
                        continue :sw 102;
                    }
                    lexer.js_parse_error(s, "nothing to repeat");
                },
                '*', '+', '?' => lexer.js_parse_error(s, "nothing to repeat"),
                '(' => {
                    if (s.source_buf[s.buf_pos + 1] == '?') {
                        const gch: c_int = s.source_buf[s.buf_pos + 2];
                        if (gch == ':') {
                            s.buf_pos += 3;
                            last_atom_start = @intCast(s.byte_code_len);
                            last_capture_count = s.capture_count;
                            parsePushInt(s, last_term_start);
                            parsePushInt(s, term_start);
                            parsePushInt(s, last_atom_start);
                            parsePushInt(s, last_capture_count);
                            return parseCall(0, pt.PARSE_FUNC_re_parse_disjunction, 0);
                        } else if (gch == '=' or gch == '!') {
                            const is_neg: c_int = @intFromBool(gch == '!');
                            s.buf_pos += 3;
                            const pos = re_emit_op_u32(s, REOP.lookahead + is_neg, 0);
                            parsePushInt(s, last_term_start);
                            parsePushInt(s, term_start);
                            parsePushInt(s, last_atom_start);
                            parsePushInt(s, last_capture_count);
                            parsePushInt(s, is_neg);
                            parsePushInt(s, pos);
                            return parseCall(1, pt.PARSE_FUNC_re_parse_disjunction, 0);
                        } else {
                            lexer.js_parse_error(s, "invalid group");
                        }
                    } else {
                        s.buf_pos += 1;
                        if (s.capture_count >= bt.CAPTURE_COUNT_MAX)
                            lexer.js_parse_error(s, "too many captures");
                        last_atom_start = @intCast(s.byte_code_len);
                        last_capture_count = s.capture_count;
                        const capture_index: c_int = s.capture_count;
                        s.capture_count += 1;
                        re_emit_op_u8(s, REOP.save_start, @intCast(capture_index));
                        parsePushInt(s, last_term_start);
                        parsePushInt(s, term_start);
                        parsePushInt(s, last_atom_start);
                        parsePushInt(s, last_capture_count);
                        parsePushInt(s, capture_index);
                        return parseCall(2, pt.PARSE_FUNC_re_parse_disjunction, 0);
                    }
                },
                '\\' => {
                    switch (s.source_buf[s.buf_pos + 1]) {
                        'b', 'B' => {
                            if (s.source_buf[s.buf_pos + 1] != 'b') {
                                re_emit_op(s, REOP.not_word_boundary);
                            } else {
                                re_emit_op(s, REOP.word_boundary);
                            }
                            s.buf_pos += 2;
                        },
                        '0' => {
                            s.buf_pos += 2;
                            ch = 0;
                            if (isDigit(s.source_buf[s.buf_pos]))
                                lexer.js_parse_error(s, "invalid decimal escape in regular expression");
                            continue :sw 103;
                        },
                        '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                            var p: [*]const u8 = @ptrCast(s.source_buf + s.buf_pos + 1);
                            ch = parse_digits(&p);
                            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                            if (ch > bt.CAPTURE_COUNT_MAX)
                                lexer.js_parse_error(s, "back reference is out of range");
                            last_atom_start = @intCast(s.byte_code_len);
                            last_capture_count = s.capture_count;
                            re_emit_op_u8(s, REOP.back_reference + @as(c_int, @intFromBool(bt.reIgnoreCase(s))), @intCast(ch));
                        },
                        else => continue :sw 102,
                    }
                },
                '[' => {
                    last_atom_start = @intCast(s.byte_code_len);
                    last_capture_count = s.capture_count;
                    re_parse_char_class(s);
                },
                ']', '}' => {
                    if (bt.reIsUnicode(s))
                        lexer.js_parse_error(s, "syntax error");
                    continue :sw 102;
                },
                else => continue :sw 102,
            }
            continue :sw 101;
        },
        0 => {
            last_capture_count = parsePopInt(s);
            last_atom_start = parsePopInt(s);
            term_start = parsePopInt(s);
            last_term_start = parsePopInt(s);
            re_parse_expect(s, ')');
            continue :sw 101;
        },
        1 => {
            const pos = parsePopInt(s);
            const is_neg = parsePopInt(s);
            last_capture_count = parsePopInt(s);
            last_atom_start = parsePopInt(s);
            term_start = parsePopInt(s);
            last_term_start = parsePopInt(s);
            re_parse_expect(s, ')');
            re_emit_op(s, REOP.lookahead_match + is_neg);
            const arr = byteArr(s.byte_code);
            mc.put_u32(vt.byteArrayBuf(arr) + @as(usize, @intCast(pos)), @intCast(s.byte_code_len - @as(u32, @intCast(pos + 4))));
            continue :sw 101;
        },
        2 => {
            const capture_index = parsePopInt(s);
            last_capture_count = parsePopInt(s);
            last_atom_start = parsePopInt(s);
            term_start = parsePopInt(s);
            last_term_start = parsePopInt(s);
            re_emit_op_u8(s, REOP.save_end, @intCast(capture_index));
            re_parse_expect(s, ')');
            continue :sw 101;
        },
        102 => {
            ch = get_class_atom(s, false);
            continue :sw 103;
        },
        103 => {
            last_atom_start = @intCast(s.byte_code_len);
            last_capture_count = s.capture_count;
            if (ch >= bt.CLASS_RANGE_BASE) {
                ch -= bt.CLASS_RANGE_BASE;
                if (ch == bt.CHAR_RANGE_s or ch == bt.CHAR_RANGE_S) {
                    re_emit_op(s, REOP.space + ch - bt.CHAR_RANGE_s);
                } else {
                    _ = re_emit_op_u16(s, REOP.range, 0);
                    const range_start: c_int = @intCast(s.byte_code_len);
                    re_emit_range_base(s, ch);
                    re_range_optimize(s, range_start, false);
                }
            } else {
                if (bt.reIgnoreCase(s) and
                    ((ch >= 'A' and ch <= 'Z') or
                        (ch >= 'a' and ch <= 'z')))
                {
                    if (ch >= 'a')
                        ch -= 32;
                    re_emit_op_u8(s, REOP.range8, 2);
                    parser.emit_u8(s, @intCast(ch));
                    parser.emit_u8(s, @intCast(ch + 1));
                    parser.emit_u8(s, @intCast(ch + 32));
                    parser.emit_u8(s, @intCast(ch + 32 + 1));
                } else {
                    re_emit_char(s, ch);
                }
            }
            continue :sw 101;
        },
        101 => {
            if (last_atom_start >= 0) {
                re_parse_quantifier(s, last_atom_start, last_capture_count);
            }
            const arr = byteArr(s.byte_code);
            const buf = vt.byteArrayBuf(arr);
            const n1 = if (last_term_start >= 0) re_is_char(buf, last_term_start, term_start) else 0;
            const n2 = re_is_char(buf, term_start, @intCast(s.byte_code_len));
            if (last_term_start >= 0 and n1 > 0 and n2 > 0 and (n1 + n2) <= 4) {
                const nsum = n1 + n2;
                buf[@intCast(last_term_start)] = @intCast(REOP.char1 + nsum - 1);
                var i: c_int = 0;
                while (i < n2) : (i += 1) {
                    buf[@intCast(last_term_start + nsum + i)] = buf[@intCast(last_term_start + nsum + i + 1)];
                }
                s.byte_code_len -= 1;
            } else {
                last_term_start = term_start;
            }
            continue :sw 100;
        },
        else => unreachable,
    }
}

pub fn re_parse_disjunction(s: *JSParseState, state: c_int, dummy_param: c_int) callconv(.c) c_int {
    _ = dummy_param;
    var start: c_int = undefined;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            start = @intCast(s.byte_code_len);
            parsePushInt(s, start);
            return parseCall(0, pt.PARSE_FUNC_re_parse_alternative, 0);
        },
        0 => {
            start = parsePopInt(s);
            continue :sw 100;
        },
        100 => {
            if (s.source_buf[s.buf_pos] != '|')
                return pt.PARSE_STATE_RET;
            s.buf_pos += 1;
            const len: c_int = @intCast(s.byte_code_len - @as(u32, @intCast(start)));
            parser.emit_insert(s, start, 5);
            const arr = byteArr(s.byte_code);
            vt.byteArrayBuf(arr)[@intCast(start)] = @intCast(REOP.split_next_first);
            mc.put_u32(vt.byteArrayBuf(arr) + @as(usize, @intCast(start + 1)), @intCast(len + 5));
            const pos = re_emit_op_u32(s, REOP.goto, 0);
            parsePushInt(s, start);
            parsePushInt(s, pos);
            return parseCall(1, pt.PARSE_FUNC_re_parse_alternative, 0);
        },
        1 => {
            const pos = parsePopInt(s);
            start = parsePopInt(s);
            const len: c_int = @intCast(s.byte_code_len - @as(u32, @intCast(pos + 4)));
            const arr = byteArr(s.byte_code);
            mc.put_u32(vt.byteArrayBuf(arr) + @as(usize, @intCast(pos)), @bitCast(len));
            continue :sw 100;
        },
        else => unreachable,
    }
}

fn re_compute_register_count(s: *JSParseState, bc_buf: [*]u8, bc_buf_len: c_int) c_int {
    var stack_size: c_int = 0;
    var stack_size_max: c_int = 0;
    var pos: c_int = 0;
    while (pos < bc_buf_len) {
        const opcode: c_int = bc_buf[@intCast(pos)];
        var len: c_int = reopcode_info[@intCast(opcode)].size;
        std.debug.assert(opcode < @as(c_int, @intCast(REOP.COUNT)));
        std.debug.assert((pos + len) <= bc_buf_len);
        switch (opcode) {
            REOP.set_i32, REOP.set_char_pos => {
                bc_buf[@intCast(pos + 1)] = @intCast(stack_size);
                stack_size += 1;
                if (stack_size > stack_size_max) {
                    if (stack_size > bt.REGISTER_COUNT_MAX)
                        lexer.js_parse_error(s, "too many regexp registers");
                    stack_size_max = stack_size;
                }
            },
            REOP.check_advance, REOP.loop, REOP.loop_split_goto_first, REOP.loop_split_next_first => {
                std.debug.assert(stack_size > 0);
                stack_size -= 1;
                bc_buf[@intCast(pos + 1)] = @intCast(stack_size);
            },
            REOP.loop_check_adv_split_goto_first, REOP.loop_check_adv_split_next_first => {
                std.debug.assert(stack_size >= 2);
                stack_size -= 2;
                bc_buf[@intCast(pos + 1)] = @intCast(stack_size);
            },
            REOP.range8 => {
                const val: u32 = bc_buf[@intCast(pos + 1)];
                len += @intCast(val * 2);
            },
            REOP.range => {
                const val = mc.get_u16(bc_buf + @as(usize, @intCast(pos + 1)));
                len += @intCast(val * 8);
            },
            REOP.back_reference, REOP.back_reference_i => {
                if (bc_buf[@intCast(pos + 1)] >= s.capture_count)
                    lexer.js_parse_error(s, "back reference is out of range");
            },
            else => {},
        }
        pos += len;
    }
    return stack_size_max;
}

pub fn js_parse_regexp(s: *JSParseState, re_flags: c_int) c.JSValue {
    bt.setReMultiLine(s, (re_flags & bt.LRE_FLAG_MULTILINE) != 0);
    bt.setReDotall(s, (re_flags & bt.LRE_FLAG_DOTALL) != 0);
    bt.setReIgnoreCase(s, (re_flags & bt.LRE_FLAG_IGNORECASE) != 0);
    bt.setReIsUnicode(s, (re_flags & bt.LRE_FLAG_UNICODE) != 0);
    s.byte_code = c.JS_NULL;
    s.byte_code_len = 0;
    s.capture_count = 1;

    parser.emit_u16(s, @intCast(re_flags));
    parser.emit_u8(s, 0);
    parser.emit_u8(s, 0);

    if ((re_flags & bt.LRE_FLAG_STICKY) == 0) {
        _ = re_emit_op_u32(s, REOP.split_goto_first, 1 + 5);
        re_emit_op(s, REOP.any);
        _ = re_emit_op_u32(s, REOP.goto, @bitCast(@as(i32, -(5 + 1 + 5))));
    }
    re_emit_op_u8(s, REOP.save_start, 0);

    parser.js_parse_call(s, pt.PARSE_FUNC_re_parse_disjunction, 0);

    re_emit_op_u8(s, REOP.save_end, 0);
    re_emit_op(s, REOP.match);

    if (s.buf_pos != s.buf_len)
        lexer.js_parse_error(s, "extraneous characters at the end");

    const arr = byteArr(s.byte_code);
    vt.byteArrayBuf(arr)[bt.RE_HEADER_CAPTURE_COUNT] = s.capture_count;
    const register_count = re_compute_register_count(s, vt.byteArrayBuf(arr) + bt.RE_HEADER_LEN, @intCast(s.byte_code_len - bt.RE_HEADER_LEN));
    vt.byteArrayBuf(arr)[bt.RE_HEADER_REGISTER_COUNT] = @intCast(register_count);

    value.js_shrink_byte_array(s.ctx, &s.byte_code, @intCast(s.byte_code_len));
    return s.byte_code;
}

fn is_line_terminator(ch: u32) bool {
    return ch == '\n' or ch == '\r' or ch == bt.CP_LS or ch == bt.CP_PS;
}

fn is_word_char(ch: u32) bool {
    return (ch >= '0' and ch <= '9') or
        (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch == '_');
}

fn lre_canonicalize(ch_in: u32) u32 {
    var ch = ch_in;
    if (ch >= 'A' and ch <= 'Z') {
        ch = ch - 'A' + 'a';
    }
    return ch;
}

const RE_EXEC_STATE_SPLIT: u32 = 0;
const RE_EXEC_STATE_LOOKAHEAD: u32 = 1;
const RE_EXEC_STATE_NEGATIVE_LOOKAHEAD: u32 = 2;

const MAGIC_REGEXP_EXEC: c_int = 0;
const MAGIC_REGEXP_TEST: c_int = 1;
pub const MAGIC_REGEXP_SEARCH: c_int = 2;
pub const MAGIC_REGEXP_FORCE_GLOBAL: c_int = 3;
const RE_FLAG_COUNT: usize = 6;

fn reGetChar(cptr: *[*]const u8) u32 {
    var clen: usize = undefined;
    const ch = cutils.utf8_get(cptr.*, &clen);
    cptr.* += clen;
    return @intCast(ch);
}

fn rePeekChar(cptr: [*]const u8) u32 {
    var clen: usize = undefined;
    return @intCast(cutils.utf8_get(cptr, &clen));
}

fn rePeekPrevChar(cptr: [*]const u8) u32 {
    var cptr1 = cptr - 1;
    while ((cptr1[0] & 0xc0) == 0x80)
        cptr1 -= 1;
    var clen: usize = undefined;
    return @intCast(cutils.utf8_get(cptr1, &clen));
}

fn rePcTypeToValue(byte_code: c.JSValue, pc: [*]const u8, typ: u32) c.JSValue {
    const buf = vt.byteArrayBuf(byteArr(byte_code));
    const off: u32 = @intCast(@intFromPtr(pc) - @intFromPtr(buf));
    return (@as(c.JSValue, typ) << 1) | (@as(c.JSValue, off) << 3);
}

fn reValueToPc(byte_code: c.JSValue, val: c.JSValue) [*]const u8 {
    const buf = vt.byteArrayBuf(byteArr(byte_code));
    return buf + @as(usize, @intCast(val >> 3));
}

fn reValueToType(val: c.JSValue) u32 {
    return @intCast((val >> 1) & 3);
}

const LreState = struct {
    ctx: *c.JSContext,
    capture_buf: c.JSValue,
    byte_code: c.JSValue,
    str: c.JSValue,
    pc: [*]const u8,
    cptr: [*]const u8,
    cbuf: [*]const u8,
    cbuf_end: [*]const u8,
    capture: [*]u32,
    sp: [*]c.JSValue,
    bp: [*]c.JSValue,
    initial_sp: [*]c.JSValue,
    saved_stack_bottom: *c.JSValue,
    capture_count: c_int,
};

fn lreRelocate(st: *LreState, saved_pc: c_int, saved_cptr: c_int) void {
    const arr = byteArr(st.byte_code);
    st.pc = vt.byteArrayBuf(arr) + @as(usize, @intCast(saved_pc));
    const ps: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(st.str)));
    st.cbuf = vt.stringBuf(ps);
    st.cbuf_end = st.cbuf + vt.stringLen(ps);
    st.cptr = st.cbuf + @as(usize, @intCast(saved_cptr));
    st.capture = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(st.capture_buf))));
}

fn lrePollInterrupt(st: *LreState) c_int {
    const ctx = st.ctx;
    const x = mc.ctxExt(ctx);
    x.interrupt_counter -= 1;
    if (x.interrupt_counter <= 0) {
        @branchHint(.unlikely);
        const arr = byteArr(st.byte_code);
        const saved_pc: c_int = ptrOff(st.pc, vt.byteArrayBuf(arr));
        const saved_cptr: c_int = ptrOff(st.cptr, st.cbuf);
        var capture_buf_ref: c.JSGCRef = undefined;
        var byte_code_ref: c.JSGCRef = undefined;
        var str_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &capture_buf_ref, st.capture_buf);
        utils.pushValue(ctx, &byte_code_ref, st.byte_code);
        utils.pushValue(ctx, &str_ref, st.str);
        x.sp = @ptrCast(st.sp);
        const ret = runtime.__js_poll_interrupt(ctx);
        st.str = utils.popValue(ctx, &str_ref);
        st.byte_code = utils.popValue(ctx, &byte_code_ref);
        st.capture_buf = utils.popValue(ctx, &capture_buf_ref);
        if (vt.isExactException(ret)) {
            x.sp = @ptrCast(st.initial_sp);
            x.stack_bottom = st.saved_stack_bottom;
            return -1;
        }
        lreRelocate(st, saved_pc, saved_cptr);
    }
    return 0;
}

fn lreCheckStackSpace(st: *LreState, n: c_int) c_int {
    const ctx = st.ctx;
    const x = mc.ctxExt(ctx);
    const remaining = @divFloor(@as(isize, @bitCast(@intFromPtr(st.sp))) - @as(isize, @bitCast(@intFromPtr(x.stack_bottom))), @sizeOf(c.JSValue));
    if (remaining < n) {
        @branchHint(.unlikely);
        const arr = byteArr(st.byte_code);
        const saved_pc: c_int = ptrOff(st.pc, vt.byteArrayBuf(arr));
        const saved_cptr: c_int = ptrOff(st.cptr, st.cbuf);
        var capture_buf_ref: c.JSGCRef = undefined;
        var byte_code_ref: c.JSGCRef = undefined;
        var str_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &capture_buf_ref, st.capture_buf);
        utils.pushValue(ctx, &byte_code_ref, st.byte_code);
        utils.pushValue(ctx, &str_ref, st.str);
        x.sp = @ptrCast(st.sp);
        const ret = utils.JS_StackCheck(ctx, @intCast(n));
        st.str = utils.popValue(ctx, &str_ref);
        st.byte_code = utils.popValue(ctx, &byte_code_ref);
        st.capture_buf = utils.popValue(ctx, &capture_buf_ref);
        if (ret < 0) {
            x.sp = @ptrCast(st.initial_sp);
            x.stack_bottom = st.saved_stack_bottom;
            return -1;
        }
        lreRelocate(st, saved_pc, saved_cptr);
    }
    return 0;
}

fn lreSaveCapture(st: *LreState, idx: u32, capture_val: u32) c_int {
    if (lreCheckStackSpace(st, 2) < 0)
        return -1;
    st.sp -= 2;
    st.sp[0] = vt.newShortInt(@intCast(idx));
    st.sp[1] = vt.newShortInt(@bitCast(st.capture[idx]));
    st.capture[idx] = capture_val;
    return 0;
}

fn lreSaveCaptureCheck(st: *LreState, idx: u32, capture_val: u32) c_int {
    var sp1 = st.sp;
    while (true) {
        if (@intFromPtr(sp1) < @intFromPtr(st.bp)) {
            if (vt.valueGetInt(sp1[0]) == @as(c_int, @intCast(idx)))
                break;
            sp1 += 2;
        } else {
            if (lreCheckStackSpace(st, 2) < 0)
                return -1;
            st.sp -= 2;
            st.sp[0] = vt.newShortInt(@intCast(idx));
            st.sp[1] = vt.newShortInt(@bitCast(st.capture[idx]));
            break;
        }
    }
    st.capture[idx] = capture_val;
    return 0;
}

pub fn lre_exec(ctx: *c.JSContext, capture_buf: c.JSValue, byte_code: c.JSValue, str: c.JSValue, cindex: c_int) c_int {
    var st: LreState = undefined;
    st.ctx = ctx;
    st.capture_buf = capture_buf;
    st.byte_code = byte_code;
    st.str = str;

    var arr = byteArr(byte_code);
    st.pc = vt.byteArrayBuf(arr);
    arr = byteArr(capture_buf);
    st.capture = @ptrCast(@alignCast(vt.byteArrayBuf(arr)));
    st.capture_count = lre_get_capture_count(st.pc);
    st.pc += bt.RE_HEADER_LEN;
    const ps: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(str)));
    st.cbuf = vt.stringBuf(ps);
    st.cbuf_end = st.cbuf + vt.stringLen(ps);
    st.cptr = st.cbuf + @as(usize, @intCast(cindex));

    const x = mc.ctxExt(ctx);
    st.saved_stack_bottom = x.stack_bottom;
    st.initial_sp = @ptrCast(x.sp);
    st.sp = st.initial_sp;
    st.bp = st.initial_sp;

    var do_no_match = false;
    vm: while (true) {
        if (do_no_match) {
            do_no_match = false;
            while (true) {
                if (@intFromPtr(st.bp) == @intFromPtr(st.initial_sp)) {
                    x.sp = @ptrCast(st.initial_sp);
                    x.stack_bottom = st.saved_stack_bottom;
                    return 0;
                }
                while (@intFromPtr(st.sp) < @intFromPtr(st.bp)) {
                    const idx2 = vt.valueGetInt(st.sp[0]);
                    st.capture[@intCast(idx2)] = @bitCast(vt.valueGetInt(st.sp[1]));
                    st.sp += 2;
                }
                st.pc = reValueToPc(st.byte_code, st.sp[0]);
                const typ = reValueToType(st.sp[0]);
                st.cptr = st.cbuf + @as(usize, @intCast(vt.valueGetInt(st.sp[1])));
                st.bp = rt.valueToSp(ctx, st.sp[2]);
                st.sp += 3;
                if (typ != RE_EXEC_STATE_LOOKAHEAD)
                    break;
            }
            if (lrePollInterrupt(&st) < 0)
                return -1;
            continue :vm;
        }

        const opcode: c_int = st.pc[0];
        st.pc += 1;
        switch (opcode) {
            REOP.match => {
                x.sp = @ptrCast(st.initial_sp);
                x.stack_bottom = st.saved_stack_bottom;
                return 1;
            },
            REOP.lookahead_match => {
                const sp_start = st.sp;
                while (true) {
                    const sp1 = st.sp;
                    st.sp = st.bp;
                    st.pc = reValueToPc(st.byte_code, st.sp[0]);
                    const typ = reValueToType(st.sp[0]);
                    st.cptr = st.cbuf + @as(usize, @intCast(vt.valueGetInt(st.sp[1])));
                    st.bp = rt.valueToSp(ctx, st.sp[2]);
                    st.sp[2] = rt.spToValue(ctx, sp1);
                    st.sp += 3;
                    if (typ == RE_EXEC_STATE_LOOKAHEAD)
                        break;
                }
                if (@intFromPtr(st.sp) != @intFromPtr(st.initial_sp)) {
                    var sp1 = st.sp;
                    while (@intFromPtr(sp1) != @intFromPtr(sp_start)) {
                        sp1 -= 3;
                        const next_sp = rt.valueToSp(ctx, sp1[2]);
                        while (@intFromPtr(sp1) != @intFromPtr(next_sp)) {
                            st.sp -= 1;
                            sp1 -= 1;
                            st.sp[0] = sp1[0];
                        }
                    }
                }
            },
            REOP.negative_lookahead_match => {
                while (true) {
                    while (@intFromPtr(st.sp) < @intFromPtr(st.bp)) {
                        const idx2 = vt.valueGetInt(st.sp[0]);
                        st.capture[@intCast(idx2)] = @bitCast(vt.valueGetInt(st.sp[1]));
                        st.sp += 2;
                    }
                    st.pc = reValueToPc(st.byte_code, st.sp[0]);
                    const typ = reValueToType(st.sp[0]);
                    st.cptr = st.cbuf + @as(usize, @intCast(vt.valueGetInt(st.sp[1])));
                    st.bp = rt.valueToSp(ctx, st.sp[2]);
                    st.sp += 3;
                    if (typ == RE_EXEC_STATE_NEGATIVE_LOOKAHEAD)
                        break;
                }
                do_no_match = true;
                continue :vm;
            },
            REOP.char1 => {
                if (@intFromPtr(st.cbuf_end) - @intFromPtr(st.cptr) < 1) {
                    do_no_match = true;
                    continue :vm;
                }
                if (st.pc[0] != st.cptr[0]) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += 1;
                st.cptr += 1;
            },
            REOP.char2 => {
                if (@intFromPtr(st.cbuf_end) - @intFromPtr(st.cptr) < 2) {
                    do_no_match = true;
                    continue :vm;
                }
                if (mc.get_u16(st.pc) != mc.get_u16(st.cptr)) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += 2;
                st.cptr += 2;
            },
            REOP.char3 => {
                if (@intFromPtr(st.cbuf_end) - @intFromPtr(st.cptr) < 3) {
                    do_no_match = true;
                    continue :vm;
                }
                if (mc.get_u16(st.pc) != mc.get_u16(st.cptr) or st.pc[2] != st.cptr[2]) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += 3;
                st.cptr += 3;
            },
            REOP.char4 => {
                if (@intFromPtr(st.cbuf_end) - @intFromPtr(st.cptr) < 4) {
                    do_no_match = true;
                    continue :vm;
                }
                if (mc.get_u32(st.pc) != mc.get_u32(st.cptr)) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += 4;
                st.cptr += 4;
            },
            REOP.split_goto_first, REOP.split_next_first => {
                const val: i32 = @bitCast(mc.get_u32(st.pc));
                st.pc += 4;
                if (lreCheckStackSpace(&st, 3) < 0)
                    return -1;
                var pc1: [*]const u8 = undefined;
                if (opcode == REOP.split_next_first) {
                    pc1 = ptrAddI(st.pc, val);
                } else {
                    pc1 = st.pc;
                    st.pc = ptrAddI(st.pc, val);
                }
                st.sp -= 3;
                st.sp[0] = rePcTypeToValue(st.byte_code, pc1, RE_EXEC_STATE_SPLIT);
                st.sp[1] = vt.newShortInt(ptrOff(st.cptr, st.cbuf));
                st.sp[2] = rt.spToValue(ctx, st.bp);
                st.bp = st.sp;
            },
            REOP.lookahead, REOP.negative_lookahead => {
                const val: i32 = @bitCast(mc.get_u32(st.pc));
                st.pc += 4;
                if (lreCheckStackSpace(&st, 3) < 0)
                    return -1;
                st.sp -= 3;
                st.sp[0] = rePcTypeToValue(st.byte_code, ptrAddI(st.pc, val), RE_EXEC_STATE_LOOKAHEAD + @as(u32, @intCast(opcode - REOP.lookahead)));
                st.sp[1] = vt.newShortInt(ptrOff(st.cptr, st.cbuf));
                st.sp[2] = rt.spToValue(ctx, st.bp);
                st.bp = st.sp;
            },
            REOP.goto => {
                const val: i32 = @bitCast(mc.get_u32(st.pc));
                st.pc = ptrAddI(st.pc, 4 + val);
                if (lrePollInterrupt(&st) < 0)
                    return -1;
            },
            REOP.line_start, REOP.line_start_m => {
                if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf)) {
                    // match
                } else if (opcode == REOP.line_start) {
                    do_no_match = true;
                    continue :vm;
                } else {
                    const prev = rePeekPrevChar(st.cptr);
                    if (!is_line_terminator(prev)) {
                        do_no_match = true;
                        continue :vm;
                    }
                }
            },
            REOP.line_end, REOP.line_end_m => {
                if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf_end)) {
                    // match
                } else if (opcode == REOP.line_end) {
                    do_no_match = true;
                    continue :vm;
                } else {
                    const nextc = rePeekChar(st.cptr);
                    if (!is_line_terminator(nextc)) {
                        do_no_match = true;
                        continue :vm;
                    }
                }
            },
            REOP.dot => {
                if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf_end)) {
                    do_no_match = true;
                    continue :vm;
                }
                const nextc = reGetChar(&st.cptr);
                if (is_line_terminator(nextc)) {
                    do_no_match = true;
                    continue :vm;
                }
            },
            REOP.any => {
                if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf_end)) {
                    do_no_match = true;
                    continue :vm;
                }
                _ = reGetChar(&st.cptr);
            },
            REOP.space, REOP.not_space => {
                if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf_end)) {
                    do_no_match = true;
                    continue :vm;
                }
                var nextc: u32 = st.cptr[0];
                var v1: c_int = undefined;
                if (nextc < 128) {
                    st.cptr += 1;
                    v1 = @intFromBool(unicode_is_space_ascii(nextc));
                } else {
                    var clen: usize = undefined;
                    nextc = @intCast(cutils.utf8_get_impl(st.cptr, &clen));
                    st.cptr += clen;
                    v1 = @intFromBool(unicode_is_space_non_ascii(nextc));
                }
                v1 ^= opcode - REOP.space;
                if (v1 == 0) {
                    do_no_match = true;
                    continue :vm;
                }
            },
            REOP.save_start, REOP.save_end => {
                const val: u32 = st.pc[0];
                st.pc += 1;
                std.debug.assert(val < @as(u32, @intCast(st.capture_count)));
                const idx: u32 = 2 * val + @as(u32, @intCast(opcode - REOP.save_start));
                if (lreSaveCapture(&st, idx, @intCast(ptrOff(st.cptr, st.cbuf))) < 0)
                    return -1;
            },
            REOP.save_reset => {
                var val: u32 = st.pc[0];
                const val2: u32 = st.pc[1];
                st.pc += 2;
                std.debug.assert(val2 < @as(u32, @intCast(st.capture_count)));
                if (lreCheckStackSpace(&st, @intCast(2 * (val2 - val + 1))) < 0)
                    return -1;
                while (val <= val2) {
                    var idx: u32 = 2 * val;
                    if (lreSaveCapture(&st, idx, 0) < 0)
                        return -1;
                    idx = 2 * val + 1;
                    if (lreSaveCapture(&st, idx, 0) < 0)
                        return -1;
                    val += 1;
                }
            },
            REOP.set_i32 => {
                const idx: u32 = st.pc[0];
                const val = mc.get_u32(st.pc + 1);
                st.pc += 5;
                if (lreSaveCaptureCheck(&st, @as(u32, @intCast(2 * st.capture_count)) + idx, val) < 0)
                    return -1;
            },
            REOP.loop => {
                const idx: u32 = st.pc[0];
                const val: i32 = @bitCast(mc.get_u32(st.pc + 1));
                st.pc += 5;
                const val2: u32 = st.capture[@as(usize, @as(u32, @intCast(2 * st.capture_count)) + idx)] -% 1;
                if (lreSaveCaptureCheck(&st, @as(u32, @intCast(2 * st.capture_count)) + idx, val2) < 0)
                    return -1;
                if (val2 != 0) {
                    st.pc = ptrAddI(st.pc, val);
                    if (lrePollInterrupt(&st) < 0)
                        return -1;
                }
            },
            REOP.loop_split_goto_first, REOP.loop_split_next_first, REOP.loop_check_adv_split_goto_first, REOP.loop_check_adv_split_next_first => {
                const idx: u32 = st.pc[0];
                const limit = mc.get_u32(st.pc + 1);
                const val: i32 = @bitCast(mc.get_u32(st.pc + 5));
                st.pc += 9;
                const val2: u32 = st.capture[@as(usize, @as(u32, @intCast(2 * st.capture_count)) + idx)] -% 1;
                if (lreSaveCaptureCheck(&st, @as(u32, @intCast(2 * st.capture_count)) + idx, val2) < 0)
                    return -1;
                if (val2 > limit) {
                    st.pc = ptrAddI(st.pc, val);
                    if (lrePollInterrupt(&st) < 0)
                        return -1;
                } else {
                    if ((opcode == REOP.loop_check_adv_split_goto_first or
                        opcode == REOP.loop_check_adv_split_next_first) and
                        st.capture[@as(usize, @as(u32, @intCast(2 * st.capture_count)) + idx + 1)] == @as(u32, @intCast(ptrOff(st.cptr, st.cbuf))) and
                        val2 != limit)
                    {
                        do_no_match = true;
                        continue :vm;
                    }
                    if (val2 != 0) {
                        if (lreCheckStackSpace(&st, 3) < 0)
                            return -1;
                        var pc1: [*]const u8 = undefined;
                        if (opcode == REOP.loop_split_next_first or
                            opcode == REOP.loop_check_adv_split_next_first)
                        {
                            pc1 = ptrAddI(st.pc, val);
                        } else {
                            pc1 = st.pc;
                            st.pc = ptrAddI(st.pc, val);
                        }
                        st.sp -= 3;
                        st.sp[0] = rePcTypeToValue(st.byte_code, pc1, RE_EXEC_STATE_SPLIT);
                        st.sp[1] = vt.newShortInt(ptrOff(st.cptr, st.cbuf));
                        st.sp[2] = rt.spToValue(ctx, st.bp);
                        st.bp = st.sp;
                    }
                }
            },
            REOP.set_char_pos => {
                const idx: u32 = st.pc[0];
                st.pc += 1;
                if (lreSaveCaptureCheck(&st, @as(u32, @intCast(2 * st.capture_count)) + idx, @as(u32, @bitCast(@as(i32, ptrOff(st.cptr, st.cbuf))))) < 0)
                    return -1;
            },
            REOP.check_advance => {
                const idx: u32 = st.pc[0];
                st.pc += 1;
                if (st.capture[@as(usize, @as(u32, @intCast(2 * st.capture_count)) + idx)] == @as(u32, @intCast(ptrOff(st.cptr, st.cbuf)))) {
                    do_no_match = true;
                    continue :vm;
                }
            },
            REOP.word_boundary, REOP.not_word_boundary => {
                const is_boundary = opcode == REOP.word_boundary;
                const v1 = if (@intFromPtr(st.cptr) == @intFromPtr(st.cbuf))
                    false
                else
                    is_word_char(rePeekPrevChar(st.cptr));
                const v2 = if (@intFromPtr(st.cptr) >= @intFromPtr(st.cbuf_end))
                    false
                else
                    is_word_char(rePeekChar(st.cptr));
                if ((v1 != v2) != is_boundary) {
                    do_no_match = true;
                    continue :vm;
                }
            },
            REOP.range8 => {
                const n: c_int = st.pc[0];
                st.pc += 1;
                if (@intFromPtr(st.cptr) >= @intFromPtr(st.cbuf_end)) {
                    do_no_match = true;
                    continue :vm;
                }
                const nextc = reGetChar(&st.cptr);
                var i: c_int = 0;
                var matched = false;
                while (i < n - 1) : (i += 1) {
                    if (nextc >= st.pc[@intCast(2 * i)] and nextc < st.pc[@intCast(2 * i + 1)]) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    if (nextc >= st.pc[@intCast(2 * i)] and
                        (nextc < st.pc[@intCast(2 * i + 1)] or st.pc[@intCast(2 * i + 1)] == 0xff))
                    {
                        matched = true;
                    }
                }
                if (!matched) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += @as(usize, @intCast(2 * n));
            },
            REOP.range => {
                const n: u32 = mc.get_u16(st.pc);
                st.pc += 2;
                if (@intFromPtr(st.cptr) >= @intFromPtr(st.cbuf_end) or n == 0) {
                    do_no_match = true;
                    continue :vm;
                }
                const nextc = reGetChar(&st.cptr);
                var idx_min: u32 = 0;
                var low = mc.get_u32(st.pc + 0 * 8);
                if (nextc < low) {
                    do_no_match = true;
                    continue :vm;
                }
                var idx_max: u32 = n - 1;
                var high = mc.get_u32(st.pc + idx_max * 8 + 4);
                if (nextc >= high) {
                    do_no_match = true;
                    continue :vm;
                }
                var matched = false;
                while (idx_min <= idx_max) {
                    const idx = (idx_min + idx_max) / 2;
                    low = mc.get_u32(st.pc + idx * 8);
                    high = mc.get_u32(st.pc + idx * 8 + 4);
                    if (nextc < low) {
                        idx_max = idx -% 1;
                    } else if (nextc >= high) {
                        idx_min = idx + 1;
                    } else {
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    do_no_match = true;
                    continue :vm;
                }
                st.pc += 8 * n;
            },
            REOP.back_reference, REOP.back_reference_i => {
                const val: u32 = st.pc[0];
                st.pc += 1;
                const cap0 = st.capture[2 * val];
                const cap1 = st.capture[2 * val + 1];
                if (cap0 != @as(u32, @bitCast(@as(i32, -1))) and cap1 != @as(u32, @bitCast(@as(i32, -1)))) {
                    var cptr1 = st.cbuf + cap0;
                    const cptr1_end = st.cbuf + cap1;
                    while (@intFromPtr(cptr1) < @intFromPtr(cptr1_end)) {
                        if (@intFromPtr(st.cptr) >= @intFromPtr(st.cbuf_end)) {
                            do_no_match = true;
                            continue :vm;
                        }
                        var c1 = reGetChar(&cptr1);
                        var c2 = reGetChar(&st.cptr);
                        if (opcode == REOP.back_reference_i) {
                            c1 = lre_canonicalize(c1);
                            c2 = lre_canonicalize(c2);
                        }
                        if (c1 != c2) {
                            do_no_match = true;
                            continue :vm;
                        }
                    }
                }
            },
            else => platform_abort.abort(),
        }
    }
}

pub fn js_parse_regexp_flags(pre_flags: *c_int, buf: [*]const u8) usize {
    var p = buf;
    var re_flags: c_int = 0;
    while (p[0] != 0) {
        const mask: c_int = switch (p[0]) {
            'g' => bt.LRE_FLAG_GLOBAL,
            'i' => bt.LRE_FLAG_IGNORECASE,
            'm' => bt.LRE_FLAG_MULTILINE,
            's' => bt.LRE_FLAG_DOTALL,
            'u' => bt.LRE_FLAG_UNICODE,
            'y' => bt.LRE_FLAG_STICKY,
            else => break,
        };
        if ((re_flags & mask) != 0)
            break;
        re_flags |= mask;
        p += 1;
    }
    pre_flags.* = re_flags;
    return @intFromPtr(p) - @intFromPtr(buf);
}

pub fn js_compile_regexp(ctx: *c.JSContext, pattern: c.JSValue, flags: c.JSValue) c.JSValue {
    var re_flags: c_int = 0;
    if (!vt.isUndefined(flags)) {
        var buf: vt.JSStringCharBufExt = undefined;
        const ps: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&buf), flags)));
        const len = js_parse_regexp_flags(&re_flags, vt.stringBuf(ps));
        if (len != vt.stringLen(ps))
            return utils.JS_ThrowError(ctx, c.JS_CLASS_SYNTAX_ERROR, "invalid regular expression flags");
    }
    return parser.JS_Parse2(ctx, pattern, null, 0, "<regexp>", c.JS_EVAL_REGEXP | (re_flags << c.JS_EVAL_REGEXP_FLAGS_SHIFT));
}

pub fn js_get_regexp(ctx: *c.JSContext, obj: c.JSValue) ?*rt.JSRegExpExt {
    const p0 = value.js_get_object_class(ctx, obj, c.JS_CLASS_REGEXP) orelse {
        _ = throwTypeError(ctx, "not a regular expression");
        return null;
    };
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(p0));
    return rt.objectRegexp(p);
}

pub fn js_regexp_get_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const re = js_get_regexp(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    return value.JS_NewInt32(ctx, re.last_index);
}

pub fn js_regexp_get_source(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const re = js_get_regexp(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    return re.source;
}

pub fn js_regexp_set_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var last_index: c_int = undefined;
    if (runtime.JS_ToInt32(ctx, &last_index, argv[0]) != 0)
        return c.JS_EXCEPTION;
    const re = js_get_regexp(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    re.last_index = last_index;
    return c.JS_UNDEFINED;
}

fn js_regexp_flags_str(buf: [*]u8, re_flags: c_int) usize {
    const flag_char = [_]u8{ 'g', 'i', 'm', 's', 'u', 'y' };
    var p = buf;
    var i: usize = 0;
    while (i < RE_FLAG_COUNT) : (i += 1) {
        if ((@as(u32, @bitCast(re_flags)) >> @intCast(i)) & 1 != 0) {
            p[0] = flag_char[i];
            p += 1;
        }
    }
    p[0] = 0;
    return @intFromPtr(p) - @intFromPtr(buf);
}

pub fn dump_regexp(ctx: *c.JSContext, p0: *anyopaque) void {
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(p0));
    const re = rt.objectRegexp(p);
    var buf: vt.JSStringCharBufExt = undefined;
    var buf2: [RE_FLAG_COUNT + 1]u8 = undefined;
    utils.js_putchar(ctx, '/');
    const ps: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&buf), re.source)));
    if (vt.stringLen(ps) == 0) {
        utils.js_printf(ctx, "(?:)");
    } else {
        utils.js_printf(ctx, "%" ++ mc.JSValue_PRI, re.source);
    }
    const arr = byteArr(re.byte_code);
    _ = js_regexp_flags_str(&buf2, lre_get_flags(vt.byteArrayBuf(arr)));
    utils.js_printf(ctx, "/%s", @as([*:0]u8, @ptrCast(&buf2)));
}

pub fn js_regexp_get_flags(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const re = js_get_regexp(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var buf: [RE_FLAG_COUNT + 1]u8 = undefined;
    const arr = byteArr(re.byte_code);
    const len = js_regexp_flags_str(&buf, lre_get_flags(vt.byteArrayBuf(arr)));
    return value.JS_NewStringLen(ctx, &buf, len);
}

pub fn js_regexp_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc_in: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var argc = argc_in;
    argc &= ~c.FRAME_CF_CTOR;

    argv[0] = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(argv[0]))
        return c.JS_EXCEPTION;
    if (!vt.isUndefined(argv[1])) {
        argv[1] = runtime.JS_ToString(ctx, argv[1]);
        if (vt.isExactException(argv[1]))
            return c.JS_EXCEPTION;
    }
    var byte_code = js_compile_regexp(ctx, argv[0], argv[1]);
    if (vt.isExactException(byte_code))
        return c.JS_EXCEPTION;
    var byte_code_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &byte_code_ref, byte_code);
    const obj = value.JS_NewObjectClass(ctx, c.JS_CLASS_REGEXP, @sizeOf(rt.JSRegExpExt));
    byte_code = utils.popValue(ctx, &byte_code_ref);
    if (vt.isExactException(obj))
        return obj;
    const p = objPtr(obj);
    const re = rt.objectRegexp(p);
    re.source = argv[0];
    re.byte_code = byte_code;
    re.last_index = 0;
    return obj;
}

pub fn js_regexp_exec(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = argc;
    var re = js_get_regexp(ctx, this_val.*) orelse return c.JS_EXCEPTION;

    argv[0] = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(argv[0]))
        return c.JS_EXCEPTION;

    var p = objPtr(this_val.*);
    re = rt.objectRegexp(p);
    var last_index = maxInt(re.last_index, 0);

    const bc_arr = byteArr(re.byte_code);
    var re_flags = lre_get_flags(vt.byteArrayBuf(bc_arr));
    if (magic == MAGIC_REGEXP_FORCE_GLOBAL)
        re_flags |= MAGIC_REGEXP_FORCE_GLOBAL;
    if ((re_flags & (bt.LRE_FLAG_GLOBAL | bt.LRE_FLAG_STICKY)) == 0 or
        magic == MAGIC_REGEXP_SEARCH)
    {
        last_index = 0;
    }
    const capture_count = lre_get_capture_count(vt.byteArrayBuf(bc_arr));

    const carr0 = value.js_alloc_byte_array(ctx, @as(c_int, @intCast(@sizeOf(u32))) * lre_get_alloc_count(vt.byteArrayBuf(bc_arr)));
    const carr: *vt.JSByteArrayExt = @ptrCast(@alignCast(carr0 orelse {
        return c.JS_EXCEPTION;
    }));
    var capture_buf_ref: c.JSGCRef = undefined;
    const capture_buf = utils.JS_PushGCRef(ctx, &capture_buf_ref);
    capture_buf.* = mc.valueFromPtr(carr);
    var capture: [*]u32 = @ptrCast(@alignCast(vt.byteArrayBuf(carr)));
    var i: c_int = 0;
    while (i < 2 * capture_count) : (i += 1) {
        capture[@intCast(i)] = @bitCast(@as(i32, -1));
    }

    const last_index_utf8: u32 = if (last_index <= 0)
        0
    else
        value.js_string_utf16_to_utf8_pos(ctx, argv[0], @intCast(last_index)) / 2;

    var obj: c.JSValue = undefined;
    const rc: c_int = if (last_index_utf8 > @as(u32, @intCast(value.js_string_byte_len(ctx, argv[0]))))
        2
    else blk: {
        p = objPtr(this_val.*);
        re = rt.objectRegexp(p);
        var str_buf: vt.JSStringCharBufExt = undefined;
        const str: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&str_buf), argv[0])));
        break :blk lre_exec(ctx, capture_buf.*, re.byte_code, mc.valueFromPtr(str), @intCast(last_index_utf8));
    };

    if (rc != 1) {
        if (rc >= 0) {
            if (re_flags & (bt.LRE_FLAG_GLOBAL | bt.LRE_FLAG_STICKY) != 0) {
                p = objPtr(this_val.*);
                re = rt.objectRegexp(p);
                re.last_index = 0;
            }
            if (magic == MAGIC_REGEXP_SEARCH)
                obj = vt.newShortInt(-1)
            else if (magic == MAGIC_REGEXP_TEST)
                obj = c.JS_FALSE
            else
                obj = c.JS_NULL;
        } else {
            obj = c.JS_EXCEPTION;
        }
    } else {
        capture = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(capture_buf.*))));
        if (magic == MAGIC_REGEXP_SEARCH) {
            obj = vt.newShortInt(@intCast(value.js_string_utf8_to_utf16_pos(ctx, argv[0], capture[0] * 2)));
        } else {
            if (re_flags & (bt.LRE_FLAG_GLOBAL | bt.LRE_FLAG_STICKY) != 0) {
                p = objPtr(this_val.*);
                re = rt.objectRegexp(p);
                re.last_index = @intCast(value.js_string_utf8_to_utf16_pos(ctx, argv[0], capture[1] * 2));
            }
            if (magic == MAGIC_REGEXP_TEST) {
                obj = c.JS_TRUE;
            } else {
                obj = value.JS_NewArray(ctx, capture_count);
                if (vt.isExactException(obj)) {
                    _ = utils.popValue(ctx, &capture_buf_ref);
                    return c.JS_EXCEPTION;
                }

                var obj_ref: c.JSGCRef = undefined;
                utils.pushValue(ctx, &obj_ref, obj);
                capture = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(capture_buf.*))));
                var res = value.JS_DefinePropertyValue(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_index), vt.newShortInt(@intCast(value.js_string_utf8_to_utf16_pos(ctx, argv[0], capture[0] * 2))));
                obj = utils.popValue(ctx, &obj_ref);
                if (vt.isExactException(res)) {
                    _ = utils.popValue(ctx, &capture_buf_ref);
                    return c.JS_EXCEPTION;
                }

                utils.pushValue(ctx, &obj_ref, obj);
                res = value.JS_DefinePropertyValue(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_input), argv[0]);
                obj = utils.popValue(ctx, &obj_ref);
                if (vt.isExactException(res)) {
                    _ = utils.popValue(ctx, &capture_buf_ref);
                    return c.JS_EXCEPTION;
                }

                i = 0;
                while (i < capture_count) : (i += 1) {
                    capture = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(capture_buf.*))));
                    const start: i32 = @bitCast(capture[@intCast(2 * i)]);
                    const end: i32 = @bitCast(capture[@intCast(2 * i + 1)]);
                    if (start != -1 and end != -1) {
                        utils.pushValue(ctx, &obj_ref, obj);
                        const val = value.js_sub_string_utf8(ctx, argv[0], @intCast(2 * start), @intCast(2 * end));
                        obj = utils.popValue(ctx, &obj_ref);
                        if (vt.isExactException(val)) {
                            _ = utils.popValue(ctx, &capture_buf_ref);
                            return c.JS_EXCEPTION;
                        }
                        p = objPtr(obj);
                        const varr = valueArr(p.u.array.tab);
                        vt.valueArrayItems(varr)[@intCast(i)] = val;
                    }
                }
            }
        }
    }
    _ = utils.popValue(ctx, &capture_buf_ref);
    return obj;
}
