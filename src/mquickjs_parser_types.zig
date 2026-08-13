//
// Engine layouts and helpers for mquickjs_parser Zig port
//

pub const lt = @import("mquickjs_lexer_types.zig");
pub const rt = @import("mquickjs_runtime_types.zig");
pub const vt = lt.vt;
pub const mc = lt.mc;
pub const c = lt.c;

pub const JSParseState = lt.JSParseState;
pub const BlockEnv = lt.BlockEnv;
pub const JSToken = lt.JSToken;
pub const JSParsePos = lt.JSParsePos;
pub const JSSourcePos = u32;

pub const JS_STACK_SLACK: c_int = 16;
pub const JS_MAX_LOCAL_VARS: c_int = 65535;
pub const JS_MAX_FUNC_STACK_SIZE: c_int = 65535;
pub const JS_MAX_ARGC: c_int = 65535;

pub const JS_PARSE_FUNC_STATEMENT: c_int = 0;
pub const JS_PARSE_FUNC_EXPR: c_int = 1;
pub const JS_PARSE_FUNC_METHOD: c_int = 2;

pub const PUT_LVALUE_KEEP_TOP: c_int = 0;
pub const PUT_LVALUE_NOKEEP_TOP: c_int = 1;
pub const PUT_LVALUE_KEEP_SECOND: c_int = 2;
pub const PUT_LVALUE_NOKEEP_BOTTOM: c_int = 3;

pub const PARSE_FUNC_js_parse_expr_comma: c_int = 0;
pub const PARSE_FUNC_js_parse_assign_expr: c_int = 1;
pub const PARSE_FUNC_js_parse_cond_expr: c_int = 2;
pub const PARSE_FUNC_js_parse_logical_and_or: c_int = 3;
pub const PARSE_FUNC_js_parse_expr_binary: c_int = 4;
pub const PARSE_FUNC_js_parse_unary: c_int = 5;
pub const PARSE_FUNC_js_parse_postfix_expr: c_int = 6;
pub const PARSE_FUNC_js_parse_statement: c_int = 7;
pub const PARSE_FUNC_js_parse_block: c_int = 8;
pub const PARSE_FUNC_js_parse_json_value: c_int = 9;
pub const PARSE_FUNC_re_parse_alternative: c_int = 10;
pub const PARSE_FUNC_re_parse_disjunction: c_int = 11;

pub const PARSE_STATE_INIT: c_int = 0xfe;
pub const PARSE_STATE_RET: c_int = 0xff;

pub const PF_NO_IN: c_int = 1 << 0;
pub const PF_DROP: c_int = 1 << 1;
pub const PF_ACCEPT_LPAREN: c_int = 1 << 2;
pub const PF_LEVEL_SHIFT: c_int = 4;
pub const PF_LEVEL_MASK: c_int = 0xf << PF_LEVEL_SHIFT;

pub const PARSE_PROP_FIELD: c_int = 0;
pub const PARSE_PROP_GET: c_int = 1;
pub const PARSE_PROP_SET: c_int = 2;
pub const PARSE_PROP_METHOD: c_int = 3;

pub const LABEL_RESOLVED_FLAG: c_int = 1 << 29;
pub const LABEL_OFFSET_MASK: c_int = (1 << 29) - 1;

pub const ConvertVarEntry = extern struct {
    new_var_idx: u16,
    is_local: u8,
};

pub const JSParseFunc = *const fn (s: *JSParseState, state: c_int, param: c_int) callconv(.c) c_int;

pub fn labelNone() c.JSValue {
    return vt.newShortInt(-1);
}

pub fn bytecodeHasArguments(b: *const rt.JSFunctionBytecodeExt) bool {
    return (b.header >> 4) & 1 != 0;
}

pub fn bytecodeHasLocalFuncName(b: *const rt.JSFunctionBytecodeExt) bool {
    return (b.header >> 5) & 1 != 0;
}

pub fn bytecodeSetHasArguments(b: *rt.JSFunctionBytecodeExt, v: bool) void {
    if (v) {
        b.header |= @as(c.JSWord, 1) << 4;
    } else {
        b.header &= ~(@as(c.JSWord, 1) << 4);
    }
}

pub fn bytecodeSetHasLocalFuncName(b: *rt.JSFunctionBytecodeExt, v: bool) void {
    if (v) {
        b.header |= @as(c.JSWord, 1) << 5;
    } else {
        b.header &= ~(@as(c.JSWord, 1) << 5);
    }
}

pub fn bytecodeSetHasColumn(b: *rt.JSFunctionBytecodeExt, v: bool) void {
    if (v) {
        b.header |= @as(c.JSWord, 1) << 6;
    } else {
        b.header &= ~(@as(c.JSWord, 1) << 6);
    }
}

pub fn bytecodeSetArgCount(b: *rt.JSFunctionBytecodeExt, count: c_int) void {
    b.header = (b.header & ~(@as(c.JSWord, 0xffff) << 7)) |
        (@as(c.JSWord, @intCast(count)) << 7);
}
