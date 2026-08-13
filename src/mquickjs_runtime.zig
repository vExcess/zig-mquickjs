//
// Micro QuickJS engine runtime (C ABI exports)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const lib = @import("mquickjs_runtime_lib.zig");
const rt = @import("mquickjs_runtime_types.zig");
const c = lib.c;

export const opcode_info: [rt.OP.COUNT]rt.JSOpCodeExt = rt.opcode_info_data;

export fn dummy_write_func(opaque_val: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) void {
    lib.dummy_write_func(opaque_val, buf, buf_len);
}

export fn JS_NewContext2(mem_start: *anyopaque, mem_size: usize, stdlib_def: *const c.JSSTDLibraryDef, prepare_compilation: c.JS_BOOL) *c.JSContext {
    return lib.JS_NewContext2(mem_start, mem_size, stdlib_def, prepare_compilation);
}

export fn JS_NewContext(mem_start: *anyopaque, mem_size: usize, stdlib_def: *const c.JSSTDLibraryDef) *c.JSContext {
    return lib.JS_NewContext(mem_start, mem_size, stdlib_def);
}

export fn JS_FreeContext(ctx: *c.JSContext) void {
    lib.JS_FreeContext(ctx);
}

export fn JS_SetContextOpaque(ctx: *c.JSContext, opaque_val: ?*anyopaque) void {
    lib.JS_SetContextOpaque(ctx, opaque_val);
}

export fn JS_GetContextOpaque(ctx: *c.JSContext) ?*anyopaque {
    return lib.JS_GetContextOpaque(ctx);
}

export fn JS_SetInterruptHandler(ctx: *c.JSContext, interrupt_handler: ?*anyopaque) void {
    lib.JS_SetInterruptHandler(ctx, interrupt_handler);
}

export fn JS_SetLogFunc(ctx: *c.JSContext, write_func: ?rt.mc.JSWriteFn) void {
    lib.JS_SetLogFunc(ctx, write_func);
}

export fn JS_SetRandomSeed(ctx: *c.JSContext, seed: u64) void {
    lib.JS_SetRandomSeed(ctx, seed);
}

export fn JS_GetGlobalObject(ctx: *c.JSContext) c.JSValue {
    return lib.JS_GetGlobalObject(ctx);
}

export fn get_var_ref(ctx: *c.JSContext, pfirst_var_ref: *c.JSValue, pval: *c.JSValue) c.JSValue {
    return lib.get_var_ref(ctx, pfirst_var_ref, pval);
}

export fn reloc_c_func_name(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.reloc_c_func_name(ctx, val);
}

export fn js_function_get_length_name1(ctx: *c.JSContext, this_val: *c.JSValue, is_name: c_int, pb: *?*anyopaque) c.JSValue {
    return lib.js_function_get_length_name1(ctx, this_val, is_name, @ptrCast(@alignCast(pb)));
}

export fn get_bit(buf: [*]const u8, index: u32) u32 {
    return lib.get_bit(buf, index);
}

export fn get_bits_slow(buf: [*]const u8, index: u32, n: c_int) u32 {
    return lib.get_bits_slow(buf, index, n);
}

export fn get_bits(buf: [*]const u8, buf_len: u32, index: u32, n: c_int) u32 {
    return lib.get_bits(buf, buf_len, index, n);
}

export fn get_ugolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) u32 {
    return lib.get_ugolomb(buf, buf_len, pindex);
}

export fn get_sgolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) i32 {
    return lib.get_sgolomb(buf, buf_len, pindex);
}

export fn get_pc2line_hoisted_code_len(buf: [*]const u8, buf_len: usize) c_int {
    return lib.get_pc2line_hoisted_code_len(buf, buf_len);
}

export fn get_pc2line(pline_num: *c_int, pcol_num: *c_int, buf: [*]const u8, buf_len: u32, pindex: *u32, has_column: c.JS_BOOL) void {
    lib.get_pc2line(pline_num, pcol_num, buf, buf_len, pindex, has_column);
}

export fn find_line_col(pcol_num: *c_int, b: *anyopaque, pc_in: u32) c_int {
    return lib.find_line_col(pcol_num, @ptrCast(@alignCast(b)), pc_in);
}

export fn get_func_name(ctx: *c.JSContext, func_obj: c.JSValue, str_buf: *c.JSCStringBuf, pb: *?*anyopaque) ?[*:0]const u8 {
    return lib.get_func_name(ctx, func_obj, str_buf, @ptrCast(@alignCast(pb)));
}

export fn build_backtrace(ctx: *c.JSContext, error_obj: c.JSValue, filename: ?[*:0]const u8, line_num: c_int, col_num: c_int, skip_level: c_int) void {
    lib.build_backtrace(ctx, error_obj, filename, line_num, col_num, skip_level);
}

export fn JS_ToPrimitive(ctx: *c.JSContext, val: c.JSValue, hint: c_int) c.JSValue {
    return lib.JS_ToPrimitive(ctx, val, hint);
}

export fn js_dtoa2(ctx: *c.JSContext, d: f64, radix: c_int, n_digits: c_int, flags: c_int) c.JSValue {
    return lib.js_dtoa2(ctx, d, radix, n_digits, flags);
}

export fn JS_ToString(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.JS_ToString(ctx, val);
}

export fn JS_ToPropertyKey(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.JS_ToPropertyKey(ctx, val);
}

export fn skip_spaces(p1: [*:0]const u8) c_int {
    return lib.skip_spaces(p1);
}

export fn js_atod1(ctx: *c.JSContext, pres: *f64, val: c.JSValue, radix: c_int, flags: c_int) c_int {
    return lib.js_atod1(ctx, pres, val, radix, flags);
}

export fn JS_ToNumber(ctx: *c.JSContext, pres: *f64, val: c.JSValue) c_int {
    return lib.JS_ToNumber(ctx, pres, val);
}

export fn JS_ToInt32Internal(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, sat_flag: c.JS_BOOL) c_int {
    return lib.JS_ToInt32Internal(ctx, pres, val, sat_flag);
}

export fn JS_ToInt32(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return lib.JS_ToInt32(ctx, pres, val);
}

export fn JS_ToUint32(ctx: *c.JSContext, pres: *u32, val: c.JSValue) c_int {
    return lib.JS_ToUint32(ctx, pres, val);
}

export fn JS_ToInt32Sat(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return lib.JS_ToInt32Sat(ctx, pres, val);
}

export fn JS_ToInt32Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, min_v: c_int, max_v: c_int, min_offset: c_int) c_int {
    return lib.JS_ToInt32Clamp(ctx, pres, val, min_v, max_v, min_offset);
}

export fn JS_ToUint8Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return lib.JS_ToUint8Clamp(ctx, pres, val);
}

export fn js_get_length32(ctx: *c.JSContext, pres: *u32, obj: c.JSValue) c_int {
    return lib.js_get_length32(ctx, pres, obj);
}

export fn js_add_slow(ctx: *c.JSContext) c.JSValue {
    return lib.js_add_slow(ctx);
}

export fn js_binary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return lib.js_binary_arith_slow(ctx, op);
}

export fn js_unary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return lib.js_unary_arith_slow(ctx, op);
}

export fn js_post_inc_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return lib.js_post_inc_slow(ctx, op);
}

export fn js_binary_logic_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return lib.js_binary_logic_slow(ctx, op);
}

export fn js_not_slow(ctx: *c.JSContext) c.JSValue {
    return lib.js_not_slow(ctx);
}

export fn js_relational_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return lib.js_relational_slow(ctx, op);
}

export fn js_strict_eq(ctx: *c.JSContext, op1: c.JSValue, op2: c.JSValue) c.JS_BOOL {
    return lib.js_strict_eq(ctx, op1, op2);
}

export fn js_strict_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    return lib.js_strict_eq_slow(ctx, is_neq);
}

export fn js_eq_get_type(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.js_eq_get_type(ctx, val);
}

export fn js_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    return lib.js_eq_slow(ctx, is_neq);
}

export fn js_operator_in(ctx: *c.JSContext) c.JSValue {
    return lib.js_operator_in(ctx);
}

export fn js_operator_instanceof(ctx: *c.JSContext) c.JSValue {
    return lib.js_operator_instanceof(ctx);
}

export fn js_operator_typeof(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.js_operator_typeof(ctx, val);
}

export fn js_reverse_val(tab: [*]c.JSValue, n: c_int) void {
    lib.js_reverse_val(tab, n);
}

export fn js_closure(ctx: *c.JSContext, bfunc: c.JSValue, fp: [*c]c.JSValue) c.JSValue {
    const fp_opt: ?[*]c.JSValue = if (fp) |p| @ptrCast(p) else null;
    return lib.js_closure(ctx, bfunc, fp_opt);
}

export fn js_for_of_start(ctx: *c.JSContext, is_for_in: c.JS_BOOL) c.JSValue {
    return lib.js_for_of_start(ctx, is_for_in);
}

export fn js_for_of_next(ctx: *c.JSContext) c.JSValue {
    return lib.js_for_of_next(ctx);
}

export fn js_new_c_function_proto(ctx: *c.JSContext, func_idx: c_int, proto: c.JSValue, has_params: c.JS_BOOL, params: c.JSValue) c.JSValue {
    return lib.js_new_c_function_proto(ctx, func_idx, proto, has_params, params);
}

export fn JS_NewCFunctionParams(ctx: *c.JSContext, func_idx: c_int, params: c.JSValue) c.JSValue {
    return lib.JS_NewCFunctionParams(ctx, func_idx, params);
}

export fn js_call_constructor_start(ctx: *c.JSContext, func: c.JSValue) c.JSValue {
    return lib.js_call_constructor_start(ctx, func);
}

export fn __js_poll_interrupt(ctx: *c.JSContext) c.JSValue {
    return lib.__js_poll_interrupt(ctx);
}

export fn JS_PushArg(ctx: *c.JSContext, val: c.JSValue) void {
    lib.JS_PushArg(ctx, val);
}

export fn JS_Call(ctx: *c.JSContext, call_flags: c_int) c.JSValue {
    return lib.JS_Call(ctx, call_flags);
}
