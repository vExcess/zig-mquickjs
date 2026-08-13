//
// Micro QuickJS engine lexer (C ABI exports)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by VExcess
//

const lib = @import("mquickjs_lexer_lib.zig");
const lt = @import("mquickjs_lexer_types.zig");
const utils = @import("mquickjs_utils_lib.zig");
const c = lib.c;

extern fn longjmp(env: *anyopaque, val: c_int) noreturn;

export fn get_line_col(pcol_num: *c_int, buf: [*]const u8, len: usize) c_int {
    return lib.get_line_col(pcol_num, buf, len);
}

export fn js_parse_error(s: *lt.JSParseState, fmt: [*:0]const u8, ...) callconv(.c) noreturn {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    _ = utils.js_vsnprintf(@ptrCast(&s.error_msg), s.error_msg.len, fmt, @ptrCast(&ap));
    longjmp(@ptrCast(&s.jmp_env), 1);
}

export fn js_parse_error_mem(s: *lt.JSParseState) void {
    lib.js_parse_error_mem(s);
}

export fn js_parse_error_stack_overflow(s: *lt.JSParseState) void {
    lib.js_parse_error_stack_overflow(s);
}

export fn js_parse_expect1(s: *lt.JSParseState, ch: c_int) void {
    lib.js_parse_expect1(s, ch);
}

export fn js_parse_expect(s: *lt.JSParseState, ch: c_int) void {
    lib.js_parse_expect(s, ch);
}

export fn js_parse_expect_semi(s: *lt.JSParseState) void {
    lib.js_parse_expect_semi(s);
}

export fn js_skip_parens(s: *lt.JSParseState, pfunc_name: ?*c.JSValue) c_int {
    return lib.js_skip_parens(s, pfunc_name);
}

export fn js_skip_expr(s: *lt.JSParseState) void {
    lib.js_skip_expr(s);
}

export fn is_regexp_allowed(tok: c_int) c.JS_BOOL {
    return lib.is_regexp_allowed(tok);
}

export fn js_parse_get_pos(s: *lt.JSParseState, sp: *lt.JSParsePos) void {
    lib.js_parse_get_pos(s, sp);
}

export fn js_parse_seek_token(s: *lt.JSParseState, sp: *const lt.JSParsePos) void {
    lib.js_parse_seek_token(s, sp);
}

export fn js_parse_skip_parens_token(s: *lt.JSParseState) c_int {
    return lib.js_parse_skip_parens_token(s);
}

export fn js_parse_escape(buf: [*]const u8, plen: *usize) c_int {
    return lib.js_parse_escape(buf, plen);
}

export fn js_parse_string(s: *lt.JSParseState, ppos: *u32, sep: c_int) c.JSValue {
    return lib.js_parse_string(s, ppos, sep);
}

export fn js_parse_ident(s: *lt.JSParseState, token: *lt.JSToken, ppos: *u32, first_c: c_int) void {
    lib.js_parse_ident(s, token, ppos, first_c);
}

export fn js_parse_regexp_token(s: *lt.JSParseState, ppos: *u32) void {
    lib.js_parse_regexp_token(s, ppos);
}

export fn next_token(s: *lt.JSParseState) void {
    lib.next_token(s);
}
