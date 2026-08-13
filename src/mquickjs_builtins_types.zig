//
// Engine layouts and helpers for mquickjs_builtins Zig port
//

pub const lt = @import("mquickjs_lexer_types.zig");
pub const pt = @import("mquickjs_parser_types.zig");
pub const rt = pt.rt;
pub const vt = pt.vt;
pub const mc = pt.mc;
pub const c = pt.c;

pub const JSParseState = lt.JSParseState;

pub const LRE_FLAG_GLOBAL: c_int = 1 << 0;
pub const LRE_FLAG_IGNORECASE: c_int = 1 << 1;
pub const LRE_FLAG_MULTILINE: c_int = 1 << 2;
pub const LRE_FLAG_DOTALL: c_int = 1 << 3;
pub const LRE_FLAG_UNICODE: c_int = 1 << 4;
pub const LRE_FLAG_STICKY: c_int = 1 << 5;

pub const RE_HEADER_FLAGS: usize = 0;
pub const RE_HEADER_CAPTURE_COUNT: usize = 2;
pub const RE_HEADER_REGISTER_COUNT: usize = 3;
pub const RE_HEADER_LEN: usize = 4;

pub const CAPTURE_COUNT_MAX: c_int = 255;
pub const REGISTER_COUNT_MAX: c_int = 255;
pub const CLASS_RANGE_BASE: c_int = 0x40000000;

pub const CHAR_RANGE_d: c_int = 0;
pub const CHAR_RANGE_D: c_int = 1;
pub const CHAR_RANGE_s: c_int = 2;
pub const CHAR_RANGE_S: c_int = 3;
pub const CHAR_RANGE_w: c_int = 4;
pub const CHAR_RANGE_W: c_int = 5;

pub const magic_internalAt: c_int = 0;
pub const magic_charAt: c_int = 1;
pub const magic_charCodeAt: c_int = 2;
pub const magic_codePointAt: c_int = 3;

pub const js_special_every: c_int = 0;
pub const js_special_some: c_int = 1;
pub const js_special_forEach: c_int = 2;
pub const js_special_map: c_int = 3;
pub const js_special_filter: c_int = 4;

pub const js_special_reduce: c_int = 0;
pub const js_special_reduceRight: c_int = 1;

pub const JSON_REC_SIZE: c_int = 3;
pub const CP_LS: u32 = 0x2028;
pub const CP_PS: u32 = 0x2029;

pub const JSArraySortContext = extern struct {
    ctx: *c.JSContext,
    exception: c.JS_BOOL,
    parr: *c.JSValue,
    pfunc: ?*c.JSValue,
};

pub const JSDateExt = extern struct {
    dval: f64,
};

pub fn objectDate(p: *mc.JSObjectExt) *JSDateExt {
    return @ptrCast(@alignCast(&p.u));
}

pub const REOpCodeExt = extern struct {
    size: u8,
};

pub const REOP = struct {
    pub const invalid: c_int = 0;
    pub const char1: c_int = 1;
    pub const char2: c_int = 2;
    pub const char3: c_int = 3;
    pub const char4: c_int = 4;
    pub const dot: c_int = 5;
    pub const any: c_int = 6;
    pub const space: c_int = 7;
    pub const not_space: c_int = 8;
    pub const line_start: c_int = 9;
    pub const line_start_m: c_int = 10;
    pub const line_end: c_int = 11;
    pub const line_end_m: c_int = 12;
    pub const goto: c_int = 13;
    pub const split_goto_first: c_int = 14;
    pub const split_next_first: c_int = 15;
    pub const match: c_int = 16;
    pub const lookahead_match: c_int = 17;
    pub const negative_lookahead_match: c_int = 18;
    pub const save_start: c_int = 19;
    pub const save_end: c_int = 20;
    pub const save_reset: c_int = 21;
    pub const loop: c_int = 22;
    pub const loop_split_goto_first: c_int = 23;
    pub const loop_split_next_first: c_int = 24;
    pub const loop_check_adv_split_goto_first: c_int = 25;
    pub const loop_check_adv_split_next_first: c_int = 26;
    pub const set_i32: c_int = 27;
    pub const word_boundary: c_int = 28;
    pub const not_word_boundary: c_int = 29;
    pub const back_reference: c_int = 30;
    pub const back_reference_i: c_int = 31;
    pub const range8: c_int = 32;
    pub const range: c_int = 33;
    pub const lookahead: c_int = 34;
    pub const negative_lookahead: c_int = 35;
    pub const set_char_pos: c_int = 36;
    pub const check_advance: c_int = 37;
    pub const COUNT: usize = 38;
};

pub const reopcode_info_data = [_]REOpCodeExt{
    .{ .size = 1 },
    .{ .size = 2 },
    .{ .size = 3 },
    .{ .size = 4 },
    .{ .size = 5 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 5 },
    .{ .size = 5 },
    .{ .size = 5 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 2 },
    .{ .size = 2 },
    .{ .size = 3 },
    .{ .size = 6 },
    .{ .size = 10 },
    .{ .size = 10 },
    .{ .size = 10 },
    .{ .size = 10 },
    .{ .size = 6 },
    .{ .size = 1 },
    .{ .size = 1 },
    .{ .size = 2 },
    .{ .size = 2 },
    .{ .size = 2 },
    .{ .size = 3 },
    .{ .size = 5 },
    .{ .size = 5 },
    .{ .size = 2 },
    .{ .size = 2 },
};

pub const typed_array_size_log2 = [_]u8{ 0, 0, 0, 1, 1, 2, 2, 2, 3 };

pub const char_range_s = [_]u16{
    0x0009, 0x000D + 1,
    0x0020, 0x0020 + 1,
    0x00A0, 0x00A0 + 1,
    0x1680, 0x1680 + 1,
    0x2000, 0x200A + 1,
    0x2028, 0x2029 + 1,
    0x202F, 0x202F + 1,
    0x205F, 0x205F + 1,
    0x3000, 0x3000 + 1,
    0xFEFF, 0xFEFF + 1,
};

pub const char_range_w = [_]u16{
    0x0030, 0x0039 + 1,
    0x0041, 0x005A + 1,
    0x005F, 0x005F + 1,
    0x0061, 0x007A + 1,
};

pub fn typedArrayCount() c_int {
    return c.JS_CLASS_FLOAT64_ARRAY - c.JS_CLASS_UINT8C_ARRAY + 1;
}

pub fn reInJs(s: *const JSParseState) bool {
    return (s.re_bits & 1) != 0;
}

pub fn reMultiLine(s: *const JSParseState) bool {
    return (s.re_bits & 2) != 0;
}

pub fn reDotall(s: *const JSParseState) bool {
    return (s.re_bits & 4) != 0;
}

pub fn reIgnoreCase(s: *const JSParseState) bool {
    return (s.re_bits & 8) != 0;
}

pub fn reIsUnicode(s: *const JSParseState) bool {
    return (s.re_bits & 16) != 0;
}

pub fn setReBit(s: *JSParseState, mask: u8, v: bool) void {
    if (v) {
        s.re_bits |= mask;
    } else {
        s.re_bits &= ~mask;
    }
}

pub fn setReMultiLine(s: *JSParseState, v: bool) void {
    setReBit(s, 2, v);
}

pub fn setReDotall(s: *JSParseState, v: bool) void {
    setReBit(s, 4, v);
}

pub fn setReIgnoreCase(s: *JSParseState, v: bool) void {
    setReBit(s, 8, v);
}

pub fn setReIsUnicode(s: *JSParseState, v: bool) void {
    setReBit(s, 16, v);
}
