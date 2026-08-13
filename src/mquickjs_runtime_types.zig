//
// Engine layouts and helpers for mquickjs_runtime Zig port
//

pub const vt = @import("mquickjs_value_types.zig");
pub const mc = vt.mc;
pub const c = vt.c;

pub const JS_MAX_CALL_RECURSE: c_int = 8;
pub const JS_INTERRUPT_COUNTER_INIT: i16 = 10000;
pub const FRAME_CF_ARGC_MASK: c_int = 0xffff;
pub const FRAME_CF_CTOR: c_int = 1 << 16;
pub const FRAME_CF_POP_RET: c_int = 1 << 17;
pub const FRAME_CF_PC_ADD1: c_int = 1 << 18;

pub const FRAME_OFFSET_ARG0: i32 = 4;
pub const FRAME_OFFSET_FUNC_OBJ: i32 = 3;
pub const FRAME_OFFSET_THIS_OBJ: i32 = 2;
pub const FRAME_OFFSET_CALL_FLAGS: i32 = 1;
pub const FRAME_OFFSET_SAVED_FP: i32 = 0;
pub const FRAME_OFFSET_CUR_PC: i32 = -1;
pub const FRAME_OFFSET_FIRST_VARREF: i32 = -2;
pub const FRAME_OFFSET_VAR0: i32 = -3;

pub const HINT_STRING: c_int = 0;
pub const HINT_NUMBER: c_int = 1;
pub const HINT_NONE: c_int = HINT_NUMBER;

pub const JS_ATOD_TOSTRING: c_int = 1 << 8;

pub const JS_VARREF_KIND_ARG: c_int = 0;
pub const JS_VARREF_KIND_VAR: c_int = 1;
pub const JS_VARREF_KIND_VAR_REF: c_int = 2;
pub const JS_VARREF_KIND_GLOBAL: c_int = 3;

pub const JS_ETAG_NUMBER: c_int = @as(c_int, @intCast(c.JS_TAG_SPECIAL)) | (8 << 2);
pub const JS_ETAG_STRING: c_int = @as(c_int, @intCast(c.JS_TAG_SPECIAL)) | (9 << 2);
pub const JS_ETAG_OBJECT: c_int = @as(c_int, @intCast(c.JS_TAG_SPECIAL)) | (10 << 2);

pub const JSOpCodeExt = extern struct {
    size: u8,
    n_pop: u8,
    n_push: u8,
    fmt: u8,
};

pub const JSFunctionBytecodeExt = extern struct {
    header: c.JSWord,
    func_name: c.JSValue,
    byte_code: c.JSValue,
    cpool: c.JSValue,
    vars: c.JSValue,
    ext_vars: c.JSValue,
    stack_size: u16,
    ext_vars_len: u16,
    filename: c.JSValue,
    pc2line: c.JSValue,
    source_pos: c_uint,
};

pub const JSRegExpExt = extern struct {
    source: c.JSValue,
    byte_code: c.JSValue,
    last_index: c_int,
};

pub const JSInterruptHandler = *const fn (ctx: *c.JSContext, opaque_val: ?*anyopaque) callconv(.c) c_int;
pub const JSCFinalizer = *const fn (ctx: *c.JSContext, opaque_val: ?*anyopaque) callconv(.c) void;

pub const JSCFunctionGeneric = *const fn (ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) callconv(.c) c.JSValue;
pub const JSCFunctionGenericMagic = *const fn (ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) callconv(.c) c.JSValue;
pub const JSCFunctionGenericParams = *const fn (ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, params: c.JSValue) callconv(.c) c.JSValue;
pub const JSCFunctionFF = *const fn (f: f64) callconv(.c) f64;

pub fn bytecodeHasColumn(b: *const JSFunctionBytecodeExt) bool {
    return (b.header >> 6) & 1 != 0;
}

pub fn bytecodeArgCount(b: *const JSFunctionBytecodeExt) c_int {
    return @intCast((b.header >> 7) & 0xffff);
}

pub fn varRefIsDetached(p: *const vt.JSVarRefExt) bool {
    return (p.header >> 4) & 1 != 0;
}

pub fn makeSpecial(tag: c.JSWord, v: c_int) c.JSValue {
    return @as(c.JSValue, @intCast(tag)) | (@as(c.JSValue, @bitCast(@as(i64, v))) << @as(u6, @intCast(c.JS_TAG_SPECIAL_BITS)));
}

pub fn newBool(val: bool) c.JSValue {
    return makeSpecial(c.JS_TAG_BOOL, @intFromBool(val));
}

pub fn valueGetSpecialValue(v: c.JSValue) c_int {
    const as_int: i32 = @bitCast(@as(u32, @truncate(v)));
    return as_int >> @as(u5, @intCast(c.JS_TAG_SPECIAL_BITS));
}

pub fn valueGetSpecialTag(v: c.JSValue) c.JSWord {
    return v & ((@as(c.JSWord, 1) << @as(u6, @intCast(c.JS_TAG_SPECIAL_BITS))) - 1);
}

pub fn asI32(v: c.JSValue) i32 {
    return @bitCast(@as(u32, @truncate(v)));
}

pub fn storeI32(v: i32) c.JSValue {
    return @as(c.JSValue, @bitCast(@as(i64, v)));
}

pub fn storeU32(v: u32) c.JSValue {
    return v;
}

pub fn isBothInt(a: c.JSValue, b: c.JSValue) bool {
    return ((a | b) & 1) == 0;
}

pub fn isBothShortFloat(a: c.JSValue, b: c.JSValue) bool {
    const tag: c.JSValue = @intCast(c.JS_TAG_SHORT_FLOAT);
    return (((a -% tag) | (b -% tag)) & 7) == 0;
}

pub fn isExceptionOrTailCall(v: c.JSValue) bool {
    return valueGetSpecialTag(v) == c.JS_TAG_EXCEPTION;
}

pub fn slot(p: [*]c.JSValue, off: i32) *c.JSValue {
    const addr = @as(isize, @bitCast(@intFromPtr(p))) + @as(isize, off) * @as(isize, @sizeOf(c.JSValue));
    return @ptrFromInt(@as(usize, @bitCast(addr)));
}

pub fn spToValue(ctx: *c.JSContext, fp: [*]c.JSValue) c.JSValue {
    const diff: i32 = @intCast(@as(isize, @bitCast(@intFromPtr(fp))) - @as(isize, @bitCast(@intFromPtr(ctx))));
    return vt.newShortInt(diff);
}

pub fn valueToSp(ctx: *c.JSContext, val: c.JSValue) [*]c.JSValue {
    const off = vt.valueGetInt(val);
    const addr = @as(isize, @bitCast(@intFromPtr(ctx))) + @as(isize, off);
    return @ptrFromInt(@as(usize, @bitCast(addr)));
}

pub fn closureVarRefs(p: *mc.JSObjectExt) [*]c.JSValue {
    const base: [*]c.JSValue = @ptrCast(@alignCast(&p.u.closure.func_bytecode));
    return base + 1;
}

pub fn objectRegexp(p: *mc.JSObjectExt) *JSRegExpExt {
    return @ptrCast(@alignCast(&p.u));
}

pub fn objectError(p: *mc.JSObjectExt) *mc.JSErrorDataExt {
    return @ptrCast(@alignCast(&p.u));
}

pub const OP_FMT_none: u8 = 0;
pub const OP_FMT_none_int: u8 = 1;
pub const OP_FMT_none_loc: u8 = 2;
pub const OP_FMT_none_arg: u8 = 3;
pub const OP_FMT_none_var_ref: u8 = 4;
pub const OP_FMT_u8: u8 = 5;
pub const OP_FMT_i8: u8 = 6;
pub const OP_FMT_loc8: u8 = 7;
pub const OP_FMT_const8: u8 = 8;
pub const OP_FMT_label8: u8 = 9;
pub const OP_FMT_u16: u8 = 10;
pub const OP_FMT_i16: u8 = 11;
pub const OP_FMT_label16: u8 = 12;
pub const OP_FMT_npop: u8 = 13;
pub const OP_FMT_npopx: u8 = 14;
pub const OP_FMT_loc: u8 = 15;
pub const OP_FMT_arg: u8 = 16;
pub const OP_FMT_var_ref: u8 = 17;
pub const OP_FMT_u32: u8 = 18;
pub const OP_FMT_i32: u8 = 19;
pub const OP_FMT_const16: u8 = 20;
pub const OP_FMT_label: u8 = 21;
pub const OP_FMT_value: u8 = 22;

pub const OP = struct {
    pub const invalid: c_int = 0;
    pub const push_value: c_int = 1;
    pub const push_const: c_int = 2;
    pub const fclosure: c_int = 3;
    pub const @"undefined": c_int = 4;
    pub const @"null": c_int = 5;
    pub const push_this: c_int = 6;
    pub const push_false: c_int = 7;
    pub const push_true: c_int = 8;
    pub const object: c_int = 9;
    pub const this_func: c_int = 10;
    pub const arguments: c_int = 11;
    pub const new_target: c_int = 12;
    pub const drop: c_int = 13;
    pub const nip: c_int = 14;
    pub const dup: c_int = 15;
    pub const dup1: c_int = 16;
    pub const dup2: c_int = 17;
    pub const insert2: c_int = 18;
    pub const insert3: c_int = 19;
    pub const perm3: c_int = 20;
    pub const perm4: c_int = 21;
    pub const swap: c_int = 22;
    pub const rot3l: c_int = 23;
    pub const call_constructor: c_int = 24;
    pub const call: c_int = 25;
    pub const call_method: c_int = 26;
    pub const array_from: c_int = 27;
    pub const @"return": c_int = 28;
    pub const return_undef: c_int = 29;
    pub const throw: c_int = 30;
    pub const regexp: c_int = 31;
    pub const get_field: c_int = 32;
    pub const get_field2: c_int = 33;
    pub const put_field: c_int = 34;
    pub const get_array_el: c_int = 35;
    pub const get_array_el2: c_int = 36;
    pub const put_array_el: c_int = 37;
    pub const get_length: c_int = 38;
    pub const get_length2: c_int = 39;
    pub const define_field: c_int = 40;
    pub const define_getter: c_int = 41;
    pub const define_setter: c_int = 42;
    pub const set_proto: c_int = 43;
    pub const get_loc: c_int = 44;
    pub const put_loc: c_int = 45;
    pub const get_arg: c_int = 46;
    pub const put_arg: c_int = 47;
    pub const get_var_ref: c_int = 48;
    pub const put_var_ref: c_int = 49;
    pub const get_var_ref_nocheck: c_int = 50;
    pub const put_var_ref_nocheck: c_int = 51;
    pub const if_false: c_int = 52;
    pub const if_true: c_int = 53;
    pub const goto: c_int = 54;
    pub const @"catch": c_int = 55;
    pub const gosub: c_int = 56;
    pub const ret: c_int = 57;
    pub const for_in_start: c_int = 58;
    pub const for_of_start: c_int = 59;
    pub const for_of_next: c_int = 60;
    pub const neg: c_int = 61;
    pub const plus: c_int = 62;
    pub const dec: c_int = 63;
    pub const inc: c_int = 64;
    pub const post_dec: c_int = 65;
    pub const post_inc: c_int = 66;
    pub const not: c_int = 67;
    pub const lnot: c_int = 68;
    pub const typeof: c_int = 69;
    pub const delete: c_int = 70;
    pub const mul: c_int = 71;
    pub const div: c_int = 72;
    pub const mod: c_int = 73;
    pub const add: c_int = 74;
    pub const sub: c_int = 75;
    pub const pow: c_int = 76;
    pub const shl: c_int = 77;
    pub const sar: c_int = 78;
    pub const shr: c_int = 79;
    pub const lt: c_int = 80;
    pub const lte: c_int = 81;
    pub const gt: c_int = 82;
    pub const gte: c_int = 83;
    pub const instanceof: c_int = 84;
    pub const in: c_int = 85;
    pub const eq: c_int = 86;
    pub const neq: c_int = 87;
    pub const strict_eq: c_int = 88;
    pub const strict_neq: c_int = 89;
    pub const @"and": c_int = 90;
    pub const xor: c_int = 91;
    pub const @"or": c_int = 92;
    pub const nop: c_int = 93;
    pub const push_minus1: c_int = 94;
    pub const push_0: c_int = 95;
    pub const push_1: c_int = 96;
    pub const push_2: c_int = 97;
    pub const push_3: c_int = 98;
    pub const push_4: c_int = 99;
    pub const push_5: c_int = 100;
    pub const push_6: c_int = 101;
    pub const push_7: c_int = 102;
    pub const push_i8: c_int = 103;
    pub const push_i16: c_int = 104;
    pub const push_const8: c_int = 105;
    pub const fclosure8: c_int = 106;
    pub const push_empty_string: c_int = 107;
    pub const get_loc8: c_int = 108;
    pub const put_loc8: c_int = 109;
    pub const get_loc0: c_int = 110;
    pub const get_loc1: c_int = 111;
    pub const get_loc2: c_int = 112;
    pub const get_loc3: c_int = 113;
    pub const put_loc0: c_int = 114;
    pub const put_loc1: c_int = 115;
    pub const put_loc2: c_int = 116;
    pub const put_loc3: c_int = 117;
    pub const get_arg0: c_int = 118;
    pub const get_arg1: c_int = 119;
    pub const get_arg2: c_int = 120;
    pub const get_arg3: c_int = 121;
    pub const put_arg0: c_int = 122;
    pub const put_arg1: c_int = 123;
    pub const put_arg2: c_int = 124;
    pub const put_arg3: c_int = 125;
    pub const COUNT: usize = 126;
};

pub const opcode_info_data = [_]JSOpCodeExt{
    .{ .size = 1, .n_pop = 0, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 5, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_value },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_u16 },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 3, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 4, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 3, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 3, .n_push = 4, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 3, .n_push = 3, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 4, .n_push = 4, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 3, .n_push = 3, .fmt = OP_FMT_none },
    .{ .size = 3, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_npop },
    .{ .size = 3, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_npop },
    .{ .size = 3, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_npop },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_npop },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 3, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 3, .n_pop = 1, .n_push = 2, .fmt = OP_FMT_const16 },
    .{ .size = 3, .n_pop = 2, .n_push = 0, .fmt = OP_FMT_const16 },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 3, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 3, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 3, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 3, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_const16 },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_loc },
    .{ .size = 3, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_loc },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_arg },
    .{ .size = 3, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_arg },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_var_ref },
    .{ .size = 3, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_var_ref },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_var_ref },
    .{ .size = 3, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_var_ref },
    .{ .size = 5, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_label },
    .{ .size = 5, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_label },
    .{ .size = 5, .n_pop = 0, .n_push = 0, .fmt = OP_FMT_label },
    .{ .size = 5, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_label },
    .{ .size = 5, .n_pop = 0, .n_push = 0, .fmt = OP_FMT_label },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 3, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 2, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 1, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 2, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 0, .fmt = OP_FMT_none },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_int },
    .{ .size = 2, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_i8 },
    .{ .size = 3, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_i16 },
    .{ .size = 2, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_const8 },
    .{ .size = 2, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_const8 },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none },
    .{ .size = 2, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_loc8 },
    .{ .size = 2, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_loc8 },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_loc },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 0, .n_push = 1, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_arg },
    .{ .size = 1, .n_pop = 1, .n_push = 0, .fmt = OP_FMT_none_arg },
};
