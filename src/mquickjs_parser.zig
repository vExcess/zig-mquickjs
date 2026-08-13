//
// Micro QuickJS engine parser (C ABI exports)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const lib = @import("mquickjs_parser_lib.zig");
const pt = @import("mquickjs_parser_types.zig");
const c = lib.c;

export fn get_line_col_delta(pcol_num: *c_int, buf: [*]const u8, pos1: c_int, pos2: c_int) c_int {
    return lib.get_line_col_delta(pcol_num, buf, pos1, pos2);
}

export fn emit_u8(s: *pt.JSParseState, val: u8) void {
    lib.emit_u8(s, val);
}

export fn emit_u16(s: *pt.JSParseState, val: u16) void {
    lib.emit_u16(s, val);
}

export fn emit_u32(s: *pt.JSParseState, val: u32) void {
    lib.emit_u32(s, val);
}

export fn emit_insert(s: *pt.JSParseState, pos: c_int, n: c_int) void {
    lib.emit_insert(s, pos, n);
}

export fn js_parse_push_val(s: *pt.JSParseState, val: c.JSValue) void {
    lib.js_parse_push_val(s, val);
}

export fn js_parse_pop_val(s: *pt.JSParseState) c.JSValue {
    return lib.js_parse_pop_val(s);
}

export fn js_parse_call(s: *pt.JSParseState, func_idx: c_int, param: c_int) void {
    lib.js_parse_call(s, func_idx, param);
}

export fn JS_Parse2(ctx: *c.JSContext, source_str: c.JSValue, input: ?[*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return lib.JS_Parse2(ctx, source_str, input, input_len, filename, eval_flags);
}

export fn JS_Parse(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return lib.JS_Parse(ctx, input, input_len, filename, eval_flags);
}

export fn JS_Run(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.JS_Run(ctx, val);
}

export fn JS_Eval(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return lib.JS_Eval(ctx, input, input_len, filename, eval_flags);
}
