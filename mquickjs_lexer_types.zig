//
// Engine layouts and helpers for mquickjs_lexer Zig port
//

pub const vt = @import("mquickjs_value_types.zig");
pub const mc = vt.mc;
pub const c = vt.c;

const setjmp = @cImport({
    @cInclude("setjmp.h");
});

pub const SKIP_HAS_ARGUMENTS: c_int = 1 << 0;
pub const SKIP_HAS_FUNC_NAME: c_int = 1 << 1;
pub const SKIP_HAS_SEMI: c_int = 1 << 2;

pub const TOK_NUMBER: c_int = 128;
pub const TOK_STRING: c_int = 129;
pub const TOK_IDENT: c_int = 130;
pub const TOK_REGEXP: c_int = 131;
pub const TOK_MUL_ASSIGN: c_int = 132;
pub const TOK_DIV_ASSIGN: c_int = 133;
pub const TOK_MOD_ASSIGN: c_int = 134;
pub const TOK_PLUS_ASSIGN: c_int = 135;
pub const TOK_MINUS_ASSIGN: c_int = 136;
pub const TOK_SHL_ASSIGN: c_int = 137;
pub const TOK_SAR_ASSIGN: c_int = 138;
pub const TOK_SHR_ASSIGN: c_int = 139;
pub const TOK_AND_ASSIGN: c_int = 140;
pub const TOK_XOR_ASSIGN: c_int = 141;
pub const TOK_OR_ASSIGN: c_int = 142;
pub const TOK_POW_ASSIGN: c_int = 143;
pub const TOK_DEC: c_int = 144;
pub const TOK_INC: c_int = 145;
pub const TOK_SHL: c_int = 146;
pub const TOK_SAR: c_int = 147;
pub const TOK_SHR: c_int = 148;
pub const TOK_LT: c_int = 149;
pub const TOK_LTE: c_int = 150;
pub const TOK_GT: c_int = 151;
pub const TOK_GTE: c_int = 152;
pub const TOK_EQ: c_int = 153;
pub const TOK_STRICT_EQ: c_int = 154;
pub const TOK_NEQ: c_int = 155;
pub const TOK_STRICT_NEQ: c_int = 156;
pub const TOK_LAND: c_int = 157;
pub const TOK_LOR: c_int = 158;
pub const TOK_POW: c_int = 159;
pub const TOK_EOF: c_int = 160;
pub const TOK_FIRST_KEYWORD: c_int = 161;

pub const TOK_NULL: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_null));
pub const TOK_FALSE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_false));
pub const TOK_TRUE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_true));
pub const TOK_IF: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_if));
pub const TOK_ELSE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_else));
pub const TOK_RETURN: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_return));
pub const TOK_VAR: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_var));
pub const TOK_THIS: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_this));
pub const TOK_DELETE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_delete));
pub const TOK_VOID: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_void));
pub const TOK_TYPEOF: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_typeof));
pub const TOK_NEW: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_new));
pub const TOK_IN: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_in));
pub const TOK_INSTANCEOF: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_instanceof));
pub const TOK_DO: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_do));
pub const TOK_WHILE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_while));
pub const TOK_FOR: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_for));
pub const TOK_BREAK: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_break));
pub const TOK_CONTINUE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_continue));
pub const TOK_SWITCH: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_switch));
pub const TOK_CASE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_case));
pub const TOK_DEFAULT: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_default));
pub const TOK_THROW: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_throw));
pub const TOK_TRY: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_try));
pub const TOK_CATCH: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_catch));
pub const TOK_FINALLY: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_finally));
pub const TOK_FUNCTION: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_function));
pub const TOK_DEBUGGER: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_debugger));
pub const TOK_WITH: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_with));
pub const TOK_CLASS: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_class));
pub const TOK_CONST: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_const));
pub const TOK_ENUM: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_enum));
pub const TOK_EXPORT: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_export));
pub const TOK_EXTENDS: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_extends));
pub const TOK_IMPORT: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_import));
pub const TOK_SUPER: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_super));
pub const TOK_IMPLEMENTS: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_implements));
pub const TOK_INTERFACE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_interface));
pub const TOK_LET: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_let));
pub const TOK_PACKAGE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_package));
pub const TOK_PRIVATE: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_private));
pub const TOK_PROTECTED: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_protected));
pub const TOK_PUBLIC: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_public));
pub const TOK_STATIC: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_static));
pub const TOK_YIELD: c_int = TOK_FIRST_KEYWORD + @as(c_int, @intCast(c.JS_ATOM_yield));

pub const BlockEnv = extern struct {
    prev: c.JSValue,
    label_name: c.JSValue,
    label_break: c.JSValue,
    label_cont: c.JSValue,
    label_finally: c.JSValue,
    drop_count: c.JSValue,
};

pub const JSToken = extern struct {
    val: c_int,
    source_pos: u32,
    u: extern union {
        d: f64,
        regexp: extern struct {
            re_flags: u32,
            re_end_pos: u32,
        },
    },
    value: c.JSValue,
};

pub const JSParseState = extern struct {
    ctx: *c.JSContext,
    token: JSToken,

    got_lf: u8,
    is_eval: u8,
    has_retval: u8,
    is_repl: u8,
    has_column: u8,
    dropped_result: u8,

    source_str: c.JSValue,
    filename_str: c.JSValue,
    source_buf: [*c]const u8,
    buf_pos: u32,
    buf_len: u32,

    cur_func: c.JSValue,
    byte_code: c.JSValue,
    byte_code_len: u32,
    last_opcode_pos: c_int,
    last_pc2line_pos: c_int,
    last_pc2line_source_pos: u32,

    pc2line_bit_len: u32,
    pc2line_source_pos: u32,

    cpool_len: u16,
    hoisted_code_len: u32,

    local_vars_len: u16,
    eval_ret_idx: c_int,
    top_break: c.JSValue,

    capture_count: u8,
    re_bits: u8,

    jmp_env: setjmp.jmp_buf,
    error_msg: [64]u8,
};

pub const JSParsePos = extern struct {
    got_lf: u8,
    regexp_allowed: u8,
    source_pos: u32,
};

pub fn fromHex(ch: u8) i32 {
    if (ch >= '0' and ch <= '9')
        return @as(i32, ch) - '0';
    if (ch >= 'A' and ch <= 'F')
        return @as(i32, ch) - 'A' + 10;
    if (ch >= 'a' and ch <= 'f')
        return @as(i32, ch) - 'a' + 10;
    return -1;
}

pub fn isPtr(v: c.JSValue) bool {
    return mc.isPtr(v);
}

pub fn isExactException(v: c.JSValue) bool {
    return vt.isExactException(v);
}
