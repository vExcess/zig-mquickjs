//
// Micro QuickJS engine parser (shared implementation)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const cutils = @import("cutils_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const pt = @import("mquickjs_parser_types.zig");
const lt = pt.lt;
const rt = pt.rt;
const vt = pt.vt;
const mc = pt.mc;
pub const c = pt.c;

const JSParseState = pt.JSParseState;
const JSParsePos = pt.JSParsePos;
const OP = rt.OP;

const lexer = @import("mquickjs_lexer_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const dtoa = @import("dtoa_lib.zig");

extern fn setjmp(env: *anyopaque) c_int;

const min_int = cutils.min_int;

fn max_int(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn get_be32(d: [*]const u8) u32 {
    return @byteSwap(mc.get_u32(d));
}

fn put_be32(d: [*]u8, v: u32) void {
    mc.put_u32(d, @byteSwap(v));
}

fn clz32(a: u32) c_int {
    return @intCast(@clz(a));
}

fn parseCall(cur_state: c_int, func: c_int, param: c_int) c_int {
    return cur_state | (func << 8) | (param << 16);
}

fn parsePushInt(s: *JSParseState, v: c_int) void {
    js_parse_push_val(s, vt.newShortInt(v));
}

fn parsePopInt(s: *JSParseState) c_int {
    return vt.valueGetInt(js_parse_pop_val(s));
}

fn c_abort() noreturn {
    std.posix.abort();
}

fn asBool(v: u8) bool {
    return v != 0;
}

fn funcBc(val: c.JSValue) *rt.JSFunctionBytecodeExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn byteArr(val: c.JSValue) *vt.JSByteArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn valueArr(val: c.JSValue) *vt.JSValueArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

const emit = @import("mquickjs_parser_emit_lib.zig");

pub const is_label = emit.is_label;
pub const emit_claim_size = emit.emit_claim_size;
pub const emit_u8 = emit.emit_u8;
pub const emit_u16 = emit.emit_u16;
pub const emit_u32 = emit.emit_u32;
pub const pc2line_put_bits_short = emit.pc2line_put_bits_short;
pub const pc2line_put_bits = emit.pc2line_put_bits;
pub const put_ugolomb = emit.put_ugolomb;
pub const put_sgolomb = emit.put_sgolomb;
pub const get_line_col_delta = emit.get_line_col_delta;
pub const emit_pc2line = emit.emit_pc2line;
pub const emit_op_pos = emit.emit_op_pos;
pub const emit_op = emit.emit_op;
pub const emit_op_param = emit.emit_op_param;
pub const emit_insert = emit.emit_insert;
pub const remove_last_op = emit.remove_last_op;
pub const emit_push_short_int = emit.emit_push_short_int;
pub const emit_var = emit.emit_var;
pub const cpool_add = emit.cpool_add;
pub const js_emit_push_const = emit.js_emit_push_const;
pub const find_func_var = emit.find_func_var;
pub const find_var = emit.find_var;
pub const get_ext_var_name = emit.get_ext_var_name;
pub const find_func_ext_var = emit.find_func_ext_var;
pub const find_ext_var = emit.find_ext_var;
pub const add_func_ext_var = emit.add_func_ext_var;
pub const add_ext_var = emit.add_ext_var;
pub const add_var = emit.add_var;
pub const get_lvalue = emit.get_lvalue;
pub const put_lvalue = emit.put_lvalue;
pub const js_parse_property_name = emit.js_parse_property_name;
pub const parse_stack_alloc = emit.parse_stack_alloc;
pub const js_parse_push_val = emit.js_parse_push_val;
pub const js_parse_pop_val = emit.js_parse_pop_val;
pub const may_drop_result = emit.may_drop_result;
pub const js_emit_push_number = emit.js_emit_push_number;

const new_label = emit.new_label;
const emit_label = emit.emit_label;
const emit_label_pos = emit.emit_label_pos;
const emit_goto = emit.emit_goto;
const label_is_none = emit.label_is_none;
const get_byte_code = emit.get_byte_code;
const get_prev_opcode = emit.get_prev_opcode;
const js_is_live_code = emit.js_is_live_code;

const expr = @import("mquickjs_parser_expr_lib.zig");

pub const js_parse_postfix_expr = expr.js_parse_postfix_expr;
pub const js_parse_unary = expr.js_parse_unary;
pub const js_parse_expr_binary = expr.js_parse_expr_binary;
pub const js_parse_logical_and_or = expr.js_parse_logical_and_or;
pub const js_parse_cond_expr = expr.js_parse_cond_expr;
pub const js_parse_assign_expr = expr.js_parse_assign_expr;
pub const js_parse_expr_comma = expr.js_parse_expr_comma;
pub const js_parse_assign_expr2 = expr.js_parse_assign_expr2;
pub const js_parse_expr2 = expr.js_parse_expr2;
pub const js_parse_expr = expr.js_parse_expr;
pub const js_parse_expr_paren = expr.js_parse_expr_paren;

const stmt = @import("mquickjs_parser_stmt_lib.zig");

pub const js_parse_block = stmt.js_parse_block;
pub const js_parse_statement = stmt.js_parse_statement;

pub fn js_parse_call(s: *JSParseState, func_idx_in: c_int, param_in: c_int) void {
    const x = mc.ctxExt(s.ctx);
    const stack_top: [*]c.JSValue = @ptrCast(x.sp);
    var state: c_int = pt.PARSE_STATE_INIT;
    var func_idx = func_idx_in;
    var param = param_in;
    while (true) {
        const ret = parse_func_table[@intCast(func_idx)](s, state, param);
        state = ret & 0xff;
        if (state == pt.PARSE_STATE_RET) {
            if (@intFromPtr(x.sp) == @intFromPtr(stack_top))
                break;
            const popped = parsePopInt(s);
            state = popped & 0xff;
            func_idx = (popped >> 8) & 0xff;
            param = -1;
        } else {
            parsePushInt(s, state | (func_idx << 8));
            state = pt.PARSE_STATE_INIT;
            func_idx = (ret >> 8) & 0xff;
            param = ret >> 16;
        }
    }
}

const parse_func_table = [_]pt.JSParseFunc{
    &js_parse_expr_comma,
    &js_parse_assign_expr,
    &js_parse_cond_expr,
    &js_parse_logical_and_or,
    &js_parse_expr_binary,
    &js_parse_unary,
    &js_parse_postfix_expr,
    &js_parse_statement,
    &js_parse_block,
    &js_parse_json_value,
    builtins.re_parse_alternative,
    builtins.re_parse_disjunction,
};

pub fn js_alloc_function_bytecode(ctx: *c.JSContext) ?*rt.JSFunctionBytecodeExt {
    const b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(
        utils.js_mallocz(ctx, @intCast(@sizeOf(rt.JSFunctionBytecodeExt)), mc.JS_MTAG_FUNCTION_BYTECODE) orelse return null,
    ));
    b.func_name = c.JS_NULL;
    b.byte_code = c.JS_NULL;
    b.cpool = c.JS_NULL;
    b.vars = c.JS_NULL;
    b.ext_vars = c.JS_NULL;
    b.filename = c.JS_NULL;
    b.pc2line = c.JS_NULL;
    return b;
}

pub fn js_parse_function_decl(s: *JSParseState, func_type: c_int, func_name_in: c.JSValue) void {
    const ctx = s.ctx;
    var func_name = func_name_in;
    const is_expr = func_type != pt.JS_PARSE_FUNC_STATEMENT;
    var func_name_ref: c.JSGCRef = undefined;
    var bfunc_ref: c.JSGCRef = undefined;

    if (func_type == pt.JS_PARSE_FUNC_STATEMENT or func_type == pt.JS_PARSE_FUNC_EXPR) {
        lexer.next_token(s);
        if (s.token.val != lt.TOK_IDENT and !is_expr)
            lexer.js_parse_error(s, "function name expected");
        if (s.token.val == lt.TOK_IDENT) {
            func_name = s.token.value;
            utils.pushValue(ctx, &func_name_ref, func_name);
            lexer.next_token(s);
            func_name = utils.popValue(ctx, &func_name_ref);
        }
    }

    utils.pushValue(ctx, &func_name_ref, func_name);
    const b0 = js_alloc_function_bytecode(s.ctx) orelse lexer.js_parse_error_mem(s);
    const bfunc = mc.valueFromPtr(b0);
    utils.pushValue(ctx, &bfunc_ref, bfunc);

    var b = funcBc(bfunc_ref.val);
    b.filename = s.filename_str;
    b.func_name = func_name_ref.val;
    b.source_pos = s.token.source_pos;
    pt.bytecodeSetHasColumn(b, asBool(s.has_column));

    lexer.js_parse_expect1(s, '(');
    _ = lexer.js_skip_parens(s, null);
    lexer.js_parse_expect1(s, '{');
    const skip_bits = lexer.js_skip_parens(s, if (is_expr) &func_name_ref.val else null);

    b = funcBc(bfunc_ref.val);
    pt.bytecodeSetHasArguments(b, (skip_bits & lt.SKIP_HAS_ARGUMENTS) != 0);
    pt.bytecodeSetHasLocalFuncName(b, (skip_bits & lt.SKIP_HAS_FUNC_NAME) != 0);

    var idx = cpool_add(s, bfunc_ref.val);
    if (is_expr) {
        emit_op(s, @intCast(OP.fclosure));
        emit_u16(s, @intCast(idx));
    } else {
        var var_kind: c_int = undefined;
        idx = stmt.define_var(s, &var_kind, func_name_ref.val);
        s.hoisted_code_len += 3 + 3;
        if (var_kind == rt.JS_VARREF_KIND_VAR) {
            const cur = funcBc(s.cur_func);
            idx += rt.bytecodeArgCount(cur);
        }
        b = funcBc(bfunc_ref.val);
        pt.bytecodeSetArgCount(b, idx + 1);
    }
    _ = utils.popValue(ctx, &bfunc_ref);
    _ = utils.popValue(ctx, &func_name_ref);
}

fn define_hoisted_functions(s: *JSParseState, is_eval: bool) void {
    var b = funcBc(s.cur_func);
    if (b.pc2line != c.JS_NULL) {
        var n: c_int = @intCast((0 -% s.pc2line_bit_len) & 7);
        if (n != 0)
            pc2line_put_bits(s, n, 0);
        n = @intCast(s.hoisted_code_len);
        var h: c_int = 0;
        while (true) {
            pc2line_put_bits(s, 8, @intCast((n & 0x7f) | h));
            n >>= 7;
            if (n == 0)
                break;
            h |= 0x80;
        }
    }
    if (s.hoisted_code_len == 0)
        return;
    emit_insert(s, 0, @intCast(s.hoisted_code_len));

    b = funcBc(s.cur_func);
    const arg_count = rt.bytecodeArgCount(b);
    const saved_byte_code_len = s.byte_code_len;
    s.byte_code_len = 0;
    const cpool = valueArr(b.cpool);
    const items = vt.valueArrayItems(cpool);
    var i: c_int = 0;
    while (i < s.cpool_len) : (i += 1) {
        const val = items[@intCast(i)];
        if (mc.isPtr(val)) {
            b = funcBc(val);
            if (mc.mbGetMtag(b) == mc.JS_MTAG_FUNCTION_BYTECODE and
                rt.bytecodeArgCount(b) != 0)
            {
                var idx = rt.bytecodeArgCount(b) - 1;
                const op: c_int = if (is_eval)
                    OP.put_var_ref_nocheck
                else if (idx < arg_count)
                    OP.put_arg
                else blk: {
                    idx -= arg_count;
                    break :blk OP.put_loc;
                };
                emit_u8(s, @intCast(OP.fclosure));
                emit_u16(s, @intCast(i));
                emit_u8(s, @intCast(op));
                emit_u16(s, @intCast(idx));
            }
        }
    }
    s.byte_code_len = saved_byte_code_len;
}

const MAX_DEFAULT_PARAMS: c_int = 64;

fn emit_arg_default(s: *JSParseState, arg_idx: c_int, default_pos: *const JSParsePos) void {
    lexer.js_parse_seek_token(s, default_pos);
    const source_pos = s.pc2line_source_pos;
    emit_var(s, OP.get_arg, arg_idx, source_pos);
    emit_op(s, @intCast(OP.undefined));
    emit_op(s, @intCast(OP.strict_eq));
    var label = new_label(s);
    emit_goto(s, OP.if_false, &label);
    js_parse_assign_expr2(s, 0);
    stmt.put_var(s, rt.JS_VARREF_KIND_ARG, arg_idx, source_pos);
    emit_label(s, &label);
}

fn js_parse_function(s: *JSParseState) void {
    lexer.next_token(s);
    lexer.js_parse_expect(s, '(');
    var default_arg_idx: [MAX_DEFAULT_PARAMS]c_int = undefined;
    var default_pos: [MAX_DEFAULT_PARAMS]JSParsePos = undefined;
    var default_count: c_int = 0;
    while (s.token.val != ')') {
        if (s.token.val != lt.TOK_IDENT)
            lexer.js_parse_error(s, "missing formal parameter");
        const name = s.token.value;
        if (name == utils.js_get_atom(s.ctx, c.JS_ATOM_eval) or
            name == utils.js_get_atom(s.ctx, c.JS_ATOM_arguments))
        {
            lexer.js_parse_error(s, "invalid argument name");
        }
        if (find_var(s, name) >= 0)
            lexer.js_parse_error(s, "duplicate argument name");
        _ = add_var(s, name);
        const arg_idx = s.local_vars_len - 1;
        lexer.next_token(s);
        if (s.token.val == '=') {
            if (default_count >= MAX_DEFAULT_PARAMS)
                lexer.js_parse_error(s, "too many default parameters");
            lexer.next_token(s);
            lexer.js_parse_get_pos(s, &default_pos[@intCast(default_count)]);
            lexer.js_skip_expr(s);
            default_arg_idx[@intCast(default_count)] = arg_idx;
            default_count += 1;
        }
        if (s.token.val == ')')
            break;
        lexer.js_parse_expect(s, ',');
    }
    var b = funcBc(s.cur_func);
    const arg_count = s.local_vars_len;
    pt.bytecodeSetArgCount(b, @intCast(arg_count));
    lexer.next_token(s);
    lexer.js_parse_expect(s, '{');

    var body_pos: JSParsePos = undefined;
    lexer.js_parse_get_pos(s, &body_pos);
    var i: c_int = 0;
    while (i < default_count) : (i += 1) {
        emit_arg_default(s, default_arg_idx[@intCast(i)], &default_pos[@intCast(i)]);
    }
    lexer.js_parse_seek_token(s, &body_pos);

    b = funcBc(s.cur_func);
    if (pt.bytecodeHasArguments(b)) {
        const var_idx = add_var(s, utils.js_get_atom(s.ctx, c.JS_ATOM_arguments));
        emit_op(s, @intCast(OP.arguments));
        stmt.put_var(s, rt.JS_VARREF_KIND_VAR, var_idx - @as(c_int, @intCast(arg_count)), s.pc2line_source_pos);
    }
    b = funcBc(s.cur_func);
    if (pt.bytecodeHasLocalFuncName(b)) {
        const var_idx = add_var(s, b.func_name);
        emit_op(s, @intCast(OP.this_func));
        stmt.put_var(s, rt.JS_VARREF_KIND_VAR, var_idx - @as(c_int, @intCast(arg_count)), s.pc2line_source_pos);
    }
    while (s.token.val != '}') {
        stmt.js_parse_source_element(s);
    }
    if (js_is_live_code(s))
        emit_op(s, @intCast(OP.return_undef));
    lexer.next_token(s);
    define_hoisted_functions(s, false);
    b = funcBc(s.cur_func);
    b.byte_code = s.byte_code;
}

fn js_parse_program(s: *JSParseState) void {
    lexer.next_token(s);
    if (asBool(s.has_retval)) {
        s.eval_ret_idx = add_var(s, utils.js_get_atom(s.ctx, c.JS_ATOM__ret_));
    }
    while (s.token.val != lt.TOK_EOF) {
        stmt.js_parse_source_element(s);
    }
    if (s.eval_ret_idx >= 0) {
        emit_var(s, OP.get_loc, s.eval_ret_idx, s.pc2line_source_pos);
        emit_op(s, @intCast(OP.@"return"));
    } else {
        emit_op(s, @intCast(OP.return_undef));
    }
    define_hoisted_functions(s, true);
    const b = funcBc(s.cur_func);
    b.byte_code = s.byte_code;
}

const CVT_VAR_SIZE_MAX: c_int = 16;

fn convert_ext_vars_to_local_vars_bytecode(s: *JSParseState, byte_code: [*]u8, byte_code_len: c_int, var_start: c_int, cvt_tab: [*]const pt.ConvertVarEntry, tab_len: c_int) void {
    _ = s;
    const var_end = var_start + tab_len;
    var pos: c_int = 0;
    while (pos < byte_code_len) {
        const op = byte_code[@intCast(pos)];
        const oi = rt.opcode_info_data[op];
        switch (op) {
            @as(u8, @intCast(OP.get_var_ref)),
            @as(u8, @intCast(OP.put_var_ref)),
            @as(u8, @intCast(OP.get_var_ref_nocheck)),
            @as(u8, @intCast(OP.put_var_ref_nocheck)),
            => {
                const var_idx: c_int = @intCast(mc.get_u16(byte_code + @as(usize, @intCast(pos + 1))));
                if (var_idx >= var_start and var_idx < var_end) {
                    const j = var_idx - var_start;
                    mc.put_u16(byte_code + @as(usize, @intCast(pos + 1)), cvt_tab[@intCast(j)].new_var_idx);
                    if (cvt_tab[@intCast(j)].is_local != 0) {
                        if (op == @as(u8, @intCast(OP.get_var_ref)) or op == @as(u8, @intCast(OP.get_var_ref_nocheck))) {
                            byte_code[@intCast(pos)] = @intCast(OP.get_loc);
                        } else {
                            byte_code[@intCast(pos)] = @intCast(OP.put_loc);
                        }
                    }
                }
            },
            else => {},
        }
        pos += oi.size;
    }
}

fn convert_ext_vars_to_local_vars(s: *JSParseState) void {
    var b = funcBc(s.cur_func);
    if (s.local_vars_len == 0 or b.ext_vars_len == 0)
        return;
    const bc_arr = byteArr(b.byte_code);
    const ext_vars = valueArr(b.ext_vars);
    const items = vt.valueArrayItems(ext_vars);
    var cvt_tab: [CVT_VAR_SIZE_MAX]pt.ConvertVarEntry = undefined;
    var j: c_int = 0;
    var ext0: c_int = 0;
    while (ext0 < b.ext_vars_len) : (ext0 += CVT_VAR_SIZE_MAX) {
        const l = min_int(b.ext_vars_len - ext0, CVT_VAR_SIZE_MAX);
        var i: c_int = 0;
        while (i < l) : (i += 1) {
            const var_name = items[@intCast(2 * (ext0 + i))];
            const decl = items[@intCast(2 * (ext0 + i) + 1)];
            const var_idx = find_var(s, var_name);
            if (var_idx >= rt.bytecodeArgCount(b)) {
                cvt_tab[@intCast(i)].new_var_idx = @intCast(var_idx - rt.bytecodeArgCount(b));
                cvt_tab[@intCast(i)].is_local = 1;
            } else {
                cvt_tab[@intCast(i)].new_var_idx = @intCast(j);
                cvt_tab[@intCast(i)].is_local = 0;
                items[@intCast(2 * j)] = var_name;
                items[@intCast(2 * j + 1)] = decl;
                j += 1;
            }
        }
        if (j != (ext0 + l)) {
            convert_ext_vars_to_local_vars_bytecode(s, vt.byteArrayBuf(bc_arr), @intCast(s.byte_code_len), ext0, &cvt_tab, l);
        }
    }
    b.ext_vars_len = @intCast(j);
}

fn compute_stack_size_push(s: *JSParseState, arr: *vt.JSByteArrayExt, explore_tab: [*]u8, pos: u32, stack_len: c_int) void {
    if (pos >= @as(u32, @intCast(vt.byteArraySize(arr))))
        lexer.js_parse_error(s, "bytecode buffer overflow (pc=%d)", pos);
    const short_stack_len: u8 = @intCast(1 + @as(u32, @bitCast(stack_len)) % 255);
    if (explore_tab[pos] != 0) {
        if (explore_tab[pos] != short_stack_len) {
            lexer.js_parse_error(s, "inconsistent stack size: %d %d (pc=%d)", explore_tab[pos] - 1, short_stack_len - 1, @as(c_int, @intCast(pos)));
        }
    } else {
        explore_tab[pos] = short_stack_len;
        parsePushInt(s, @bitCast(pos));
        parsePushInt(s, stack_len);
    }
}

fn compute_stack_size(s: *JSParseState, pfunc: *c.JSValue) void {
    const ctx = s.ctx;
    var b = funcBc(pfunc.*);
    var arr = byteArr(b.byte_code);
    const explore_arr_ptr = value.js_alloc_byte_array(s.ctx, vt.byteArraySize(arr)) orelse lexer.js_parse_error_mem(s);
    b = funcBc(pfunc.*);
    arr = byteArr(b.byte_code);
    var explore_arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(explore_arr_ptr));
    var explore_arr_val = mc.valueFromPtr(explore_arr);
    var explore_tab = vt.byteArrayBuf(explore_arr);
    @memset(explore_tab[0..@intCast(vt.byteArraySize(arr))], 0);
    var explore_arr_val_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &explore_arr_val_ref, explore_arr_val);
    const stack_top: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    compute_stack_size_push(s, arr, explore_tab, 0, 0);
    while (@intFromPtr(mc.ctxExt(ctx).sp) < @intFromPtr(stack_top)) {
        var stack_len = parsePopInt(s);
        var pos: u32 = @bitCast(parsePopInt(s));
        b = funcBc(pfunc.*);
        arr = byteArr(b.byte_code);
        explore_arr = @ptrCast(@alignCast(mc.valueToPtr(explore_arr_val_ref.val)));
        explore_tab = vt.byteArrayBuf(explore_arr);
        const op = arr_buf: {
            const buf = vt.byteArrayBuf(arr);
            const o = buf[pos];
            pos += 1;
            break :arr_buf o;
        };
        if (op == @as(u8, @intCast(OP.invalid)) or op >= OP.COUNT)
            lexer.js_parse_error(s, "invalid opcode (pc=%d)", @as(c_int, @intCast(pos - 1)));
        const oi = rt.opcode_info_data[op];
        const op_len: c_int = oi.size;
        if ((pos + @as(u32, @intCast(op_len - 1))) > @as(u32, @intCast(vt.byteArraySize(arr))))
            lexer.js_parse_error(s, "bytecode buffer overflow (pc=%d)", @as(c_int, @intCast(pos - 1)));
        var n_pop: c_int = oi.n_pop;
        if (oi.fmt == rt.OP_FMT_npop)
            n_pop += @intCast(mc.get_u16(vt.byteArrayBuf(arr) + pos));
        if (stack_len < n_pop)
            lexer.js_parse_error(s, "stack underflow (pc=%d)", @as(c_int, @intCast(pos - 1)));
        stack_len += @as(c_int, oi.n_push) - n_pop;
        if (stack_len > b.stack_size) {
            if (stack_len > pt.JS_MAX_FUNC_STACK_SIZE)
                lexer.js_parse_error(s, "stack overflow (pc=%d)", @as(c_int, @intCast(pos - 1)));
            b.stack_size = @intCast(stack_len);
        }
        var skip_push = false;
        switch (op) {
            @as(u8, @intCast(OP.@"return")),
            @as(u8, @intCast(OP.return_undef)),
            @as(u8, @intCast(OP.throw)),
            @as(u8, @intCast(OP.ret)),
            => skip_push = true,
            @as(u8, @intCast(OP.goto)) => pos +%= mc.get_u32(vt.byteArrayBuf(arr) + pos),
            @as(u8, @intCast(OP.if_true)), @as(u8, @intCast(OP.if_false)) => {
                const pos1 = pos +% mc.get_u32(vt.byteArrayBuf(arr) + pos);
                compute_stack_size_push(s, arr, explore_tab, pos1, stack_len);
                pos += @as(u32, @intCast(op_len - 1));
            },
            @as(u8, @intCast(OP.gosub)) => {
                const pos1 = pos +% mc.get_u32(vt.byteArrayBuf(arr) + pos);
                compute_stack_size_push(s, arr, explore_tab, pos1, stack_len + 1);
                pos += @as(u32, @intCast(op_len - 1));
            },
            else => pos += @as(u32, @intCast(op_len - 1)),
        }
        if (!skip_push)
            compute_stack_size_push(s, arr, explore_tab, pos, stack_len);
    }
    explore_arr_val = utils.popValue(ctx, &explore_arr_val_ref);
    explore_arr = @ptrCast(@alignCast(mc.valueToPtr(explore_arr_val)));
    utils.js_free(s.ctx, explore_arr);
}

fn resolve_var_refs(s: *JSParseState, pfunc: *c.JSValue, pparent_func: *c.JSValue) void {
    var b = funcBc(pfunc.*);
    if (b.ext_vars_len == 0)
        return;
    const b1 = funcBc(pparent_func.*);
    const arg_count = rt.bytecodeArgCount(b1);
    const ext_vars_len = b.ext_vars_len;
    var i: c_int = 0;
    while (i < ext_vars_len) : (i += 1) {
        b = funcBc(pfunc.*);
        const ext_vars = valueArr(b.ext_vars);
        const var_name = vt.valueArrayItems(ext_vars)[@intCast(2 * i)];
        var var_idx = find_func_var(s.ctx, pparent_func.*, var_name);
        const decl: c_int = if (var_idx >= 0) blk: {
            if (var_idx < arg_count) {
                break :blk (rt.JS_VARREF_KIND_ARG << 16) | var_idx;
            } else {
                break :blk (rt.JS_VARREF_KIND_VAR << 16) | (var_idx - arg_count);
            }
        } else blk: {
            var_idx = find_func_ext_var(s, pparent_func.*, var_name);
            if (var_idx < 0) {
                var_idx = add_func_ext_var(s, pparent_func.*, var_name, (rt.JS_VARREF_KIND_GLOBAL << 16));
            }
            break :blk (rt.JS_VARREF_KIND_VAR_REF << 16) | var_idx;
        };
        b = funcBc(pfunc.*);
        const ext_vars2 = valueArr(b.ext_vars);
        vt.valueArrayItems(ext_vars2)[@intCast(2 * i + 1)] = vt.newShortInt(decl);
    }
}

fn reset_parse_state(s: *JSParseState, input_pos: u32, cur_func: c.JSValue) void {
    s.buf_pos = input_pos;
    s.token.val = ' ';
    s.cur_func = cur_func;
    s.byte_code = c.JS_NULL;
    s.byte_code_len = 0;
    s.last_opcode_pos = -1;
    s.pc2line_bit_len = 0;
    s.pc2line_source_pos = 0;
    s.cpool_len = 0;
    s.hoisted_code_len = 0;
    s.local_vars_len = 0;
    s.eval_ret_idx = -1;
}

fn js_parse_local_functions(s: *JSParseState, pfunc: *c.JSValue) void {
    const ctx = s.ctx;
    if (utils.JS_StackCheck(ctx, 3) != 0)
        lexer.js_parse_error_stack_overflow(s);
    const x = mc.ctxExt(ctx);
    const stack_top: [*]c.JSValue = @ptrCast(x.sp);
    var sp: [*]c.JSValue = @ptrCast(x.sp);
    sp -= 1;
    sp[0] = c.JS_NULL;
    sp -= 1;
    sp[0] = pfunc.*;
    sp -= 1;
    sp[0] = vt.newShortInt(0);
    x.sp = @ptrCast(sp);

    while (@intFromPtr(x.sp) < @intFromPtr(stack_top)) {
        const pparent_func = &@as([*]c.JSValue, @ptrCast(x.sp))[2];
        const pf = &@as([*]c.JSValue, @ptrCast(x.sp))[1];
        var cpool_pos = vt.valueGetInt(@as([*]c.JSValue, @ptrCast(x.sp))[0]);
        if (cpool_pos == 0) {
            s.cur_func = pf.*;
            var b = funcBc(pf.*);
            b.byte_code = s.byte_code;
            convert_ext_vars_to_local_vars(s);
            b = funcBc(pf.*);
            value.js_shrink_byte_array(ctx, &b.byte_code, @intCast(s.byte_code_len));
            value.js_shrink_value_array(ctx, &b.cpool, s.cpool_len);
            value.js_shrink_value_array(ctx, &b.vars, s.local_vars_len);
            value.js_shrink_byte_array(ctx, &b.pc2line, @intCast((s.pc2line_bit_len + 7) / 8));
            compute_stack_size(s, pf);
        }
        const b = funcBc(pf.*);
        if (b.cpool != c.JS_NULL) {
            const cpool = valueArr(b.cpool);
            const cpool_size = vt.valueArraySize(cpool);
            while (cpool_pos < cpool_size) : (cpool_pos += 1) {
                const b2 = funcBc(pf.*);
                const cpool2 = valueArr(b2.cpool);
                var func = vt.valueArrayItems(cpool2)[@intCast(cpool_pos)];
                if (!mc.isPtr(func))
                    continue;
                const b1 = funcBc(func);
                if (mc.mbGetMtag(b1) != mc.JS_MTAG_FUNCTION_BYTECODE)
                    continue;
                reset_parse_state(s, b1.source_pos, func);
                s.is_eval = 0;
                s.is_repl = 0;
                s.has_retval = 0;
                var func_ref: c.JSGCRef = undefined;
                utils.pushValue(ctx, &func_ref, func);
                js_parse_function(s);
                const err = utils.JS_StackCheck(ctx, 3);
                func = utils.popValue(ctx, &func_ref);
                if (err != 0)
                    lexer.js_parse_error_stack_overflow(s);
                @as([*]c.JSValue, @ptrCast(x.sp))[0] = vt.newShortInt(cpool_pos + 1);
                sp = @ptrCast(x.sp);
                sp -= 1;
                sp[0] = pf.*;
                sp -= 1;
                sp[0] = func;
                sp -= 1;
                sp[0] = vt.newShortInt(0);
                x.sp = @ptrCast(sp);
                break;
            } else {
                if (pparent_func.* != c.JS_NULL)
                    resolve_var_refs(s, pf, pparent_func);
                const b3 = funcBc(pf.*);
                value.js_shrink_value_array(ctx, &b3.ext_vars, 2 * b3.ext_vars_len);
                x.sp = @ptrCast(@as([*]c.JSValue, @ptrCast(x.sp)) + 3);
                x.stack_bottom = x.sp;
            }
            continue;
        }
        if (pparent_func.* != c.JS_NULL)
            resolve_var_refs(s, pf, pparent_func);
        const b3 = funcBc(pf.*);
        value.js_shrink_value_array(ctx, &b3.ext_vars, 2 * b3.ext_vars_len);
        x.sp = @ptrCast(@as([*]c.JSValue, @ptrCast(x.sp)) + 3);
        x.stack_bottom = x.sp;
    }
}

pub fn js_parse_json_value(s: *JSParseState, state: c_int, dummy_param: c_int) callconv(.c) c_int {
    _ = dummy_param;
    const ctx = s.ctx;
    var p: [*]const u8 = undefined;
    var val: c.JSValue = undefined;
    var idx: u32 = 0;
    var prop: c.JSValue = undefined;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            p = s.source_buf + s.buf_pos;
            p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            if ((p[0] >= '0' and p[0] <= '9') or p[0] == '-') {
                const tmp_arr = value.js_alloc_byte_array(s.ctx, @intCast(@sizeOf(c.JSATODTempMem))) orelse lexer.js_parse_error_mem(s);
                p = s.source_buf + s.buf_pos;
                var next: [*c]const u8 = p;
                const d = dtoa.js_atod(p, @ptrCast(&next), 10, 0, @ptrCast(@alignCast(tmp_arr)));
                utils.js_free(s.ctx, tmp_arr);
                if (std.math.isNan(d))
                    lexer.js_parse_error(s, "invalid number literal");
                val = value.JS_NewFloat64(s.ctx, d);
                p = next;
            } else if (p[0] == 't' and p[1] == 'r' and p[2] == 'u' and p[3] == 'e') {
                p += 4;
                val = c.JS_TRUE;
            } else if (p[0] == 'f' and p[1] == 'a' and p[2] == 'l' and p[3] == 's' and p[4] == 'e') {
                p += 5;
                val = c.JS_FALSE;
            } else if (p[0] == 'n' and p[1] == 'u' and p[2] == 'l' and p[3] == 'l') {
                p += 4;
                val = c.JS_NULL;
            } else if (p[0] == '"') {
                var pos: u32 = @intCast(@intFromPtr(p + 1) - @intFromPtr(s.source_buf));
                val = lexer.js_parse_string(s, &pos, '"');
                p = s.source_buf + pos;
            } else if (p[0] == '[') {
                val = value.JS_NewArray(ctx, 0);
                if (vt.isExactException(val))
                    lexer.js_parse_error_mem(s);
                js_parse_push_val(s, val);
                p = s.source_buf + s.buf_pos + 1;
                p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
                if (p[0] != ']') {
                    idx = 0;
                    s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                    parsePushInt(s, @bitCast(idx));
                    return parseCall(0, pt.PARSE_FUNC_js_parse_json_value, 0);
                }
                if (p[0] != ']')
                    lexer.js_parse_error(s, "expecting ']'");
                p += 1;
                val = js_parse_pop_val(s);
            } else if (p[0] == '{') {
                val = value.JS_NewObject(ctx);
                if (vt.isExactException(val))
                    lexer.js_parse_error_mem(s);
                js_parse_push_val(s, val);
                p = s.source_buf + s.buf_pos + 1;
                p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
                if (p[0] != '}') {
                    s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                    continue :sw 10;
                }
                if (p[0] != '}')
                    lexer.js_parse_error(s, "expecting '}'");
                p += 1;
                val = js_parse_pop_val(s);
            } else {
                lexer.js_parse_error(s, "unexpected character");
            }
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            s.token.value = val;
            return pt.PARSE_STATE_RET;
        },
        0 => {
            idx = @bitCast(parsePopInt(s));
            var val2 = s.token.value;
            val2 = value.JS_SetPropertyUint32(ctx, mc.ctxExt(ctx).sp.*, idx, val2);
            if (vt.isExactException(val2))
                lexer.js_parse_error_mem(s);
            idx += 1;
            p = s.source_buf + s.buf_pos;
            p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
            if (p[0] == ',') {
                p += 1;
                s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                parsePushInt(s, @bitCast(idx));
                return parseCall(0, pt.PARSE_FUNC_js_parse_json_value, 0);
            }
            if (p[0] != ']')
                lexer.js_parse_error(s, "expecting ']'");
            p += 1;
            val = js_parse_pop_val(s);
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            s.token.value = val;
            return pt.PARSE_STATE_RET;
        },
        1 => {
            var val2 = s.token.value;
            prop = js_parse_pop_val(s);
            val2 = value.JS_DefinePropertyValue(ctx, mc.ctxExt(ctx).sp.*, prop, val2);
            if (vt.isExactException(val2))
                lexer.js_parse_error_mem(s);
            p = s.source_buf + s.buf_pos;
            p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
            if (p[0] == ',') {
                p += 1;
                s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
                continue :sw 10;
            }
            if (p[0] != '}')
                lexer.js_parse_error(s, "expecting '}'");
            p += 1;
            val = js_parse_pop_val(s);
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            s.token.value = val;
            return pt.PARSE_STATE_RET;
        },
        10 => {
            p = s.source_buf + s.buf_pos;
            p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            if (p[0] != '"')
                lexer.js_parse_error(s, "expecting '\"'");
            var pos: u32 = @intCast(@intFromPtr(p + 1) - @intFromPtr(s.source_buf));
            prop = lexer.js_parse_string(s, &pos, '"');
            prop = runtime.JS_ToPropertyKey(ctx, prop);
            if (vt.isExactException(prop))
                lexer.js_parse_error_mem(s);
            p = s.source_buf + pos;
            p += @as(usize, @intCast(runtime.skip_spaces(@ptrCast(p))));
            if (p[0] != ':')
                lexer.js_parse_error(s, "expecting ':'");
            p += 1;
            s.buf_pos = @intCast(@intFromPtr(p) - @intFromPtr(s.source_buf));
            js_parse_push_val(s, prop);
            return parseCall(1, pt.PARSE_FUNC_js_parse_json_value, 0);
        },
        else => c_abort(),
    }
}

fn js_parse_json(s: *JSParseState) c.JSValue {
    s.buf_pos = 0;
    js_parse_call(s, pt.PARSE_FUNC_js_parse_json_value, 0);
    s.buf_pos += @as(u32, @intCast(runtime.skip_spaces(@ptrCast(s.source_buf + s.buf_pos))));
    if (s.buf_pos != s.buf_len)
        lexer.js_parse_error(s, "unexpected character");
    return s.token.value;
}

pub fn JS_Parse2(ctx: *c.JSContext, source_str: c.JSValue, input: ?[*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    var parse_state: JSParseState = undefined;
    @memset(std.mem.asBytes(&parse_state), 0);
    const s = &parse_state;
    s.ctx = ctx;
    mc.ctxExt(ctx).parse_state = s;
    s.source_str = c.JS_NULL;
    s.filename_str = c.JS_NULL;
    s.has_column = @intFromBool((eval_flags & c.JS_EVAL_STRIP_COL) == 0);

    var str_buf: [5]u8 = undefined;
    if (mc.isPtr(source_str)) {
        const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(source_str)));
        s.source_str = source_str;
        s.buf_len = @intCast(vt.stringLen(p));
        s.source_buf = vt.stringBuf(p);
    } else if (rt.valueGetSpecialTag(source_str) == c.JS_TAG_STRING_CHAR) {
        s.buf_len = @intCast(utils.get_short_string(&str_buf, source_str));
        s.source_buf = &str_buf;
    } else {
        s.buf_len = @intCast(input_len);
        s.source_buf = @ptrCast(input.?);
    }
    s.top_break = c.JS_NULL;
    const saved_top_gc_ref = mc.ctxExt(ctx).top_gc_ref;
    const saved_sp = mc.ctxExt(ctx).sp;

    if (setjmp(@ptrCast(&s.jmp_env)) != 0) {
        mc.ctxExt(ctx).parse_state = null;
        mc.ctxExt(ctx).top_gc_ref = saved_top_gc_ref;
        mc.ctxExt(ctx).sp = saved_sp;
        mc.ctxExt(ctx).stack_bottom = mc.ctxExt(ctx).sp;
        var col_num: c_int = 0;
        const line_num = lexer.get_line_col(&col_num, s.source_buf, if ((eval_flags & (c.JS_EVAL_JSON | c.JS_EVAL_REGEXP)) != 0)
            s.buf_pos
        else
            s.token.source_pos);
        const val = utils.JS_ThrowError(ctx, c.JS_CLASS_SYNTAX_ERROR, "%s", @as([*:0]const u8, @ptrCast(&s.error_msg)));
        runtime.build_backtrace(ctx, mc.ctxExt(ctx).current_exception, filename, line_num + 1, col_num + 1, 0);
        return val;
    }

    var top_func: c.JSValue = undefined;
    if ((eval_flags & c.JS_EVAL_JSON) != 0) {
        top_func = js_parse_json(s);
    } else if ((eval_flags & c.JS_EVAL_REGEXP) != 0) {
        top_func = builtins.js_parse_regexp(s, eval_flags >> c.JS_EVAL_REGEXP_FLAGS_SHIFT);
    } else {
        s.filename_str = value.JS_NewString(ctx, filename);
        if (vt.isExactException(s.filename_str))
            lexer.js_parse_error_mem(s);
        const b = js_alloc_function_bytecode(ctx) orelse lexer.js_parse_error_mem(s);
        b.filename = s.filename_str;
        b.func_name = utils.js_get_atom(ctx, c.JS_ATOM__eval_);
        pt.bytecodeSetHasColumn(b, asBool(s.has_column));
        top_func = mc.valueFromPtr(b);
        reset_parse_state(s, 0, top_func);
        s.is_eval = 1;
        s.has_retval = @intFromBool((eval_flags & c.JS_EVAL_RETVAL) != 0);
        s.is_repl = @intFromBool((eval_flags & c.JS_EVAL_REPL) != 0);
        var top_func_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &top_func_ref, top_func);
        js_parse_program(s);
        js_parse_local_functions(s, &top_func_ref.val);
        top_func = utils.popValue(ctx, &top_func_ref);
    }
    mc.ctxExt(ctx).parse_state = null;
    return top_func;
}

pub fn JS_Parse(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return JS_Parse2(ctx, c.JS_NULL, input, input_len, filename, eval_flags);
}

pub fn JS_Run(ctx: *c.JSContext, val_in: c.JSValue) c.JSValue {
    var val = val_in;
    if (!mc.isPtr(val))
        return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "bytecode function expected");
    const b = funcBc(val);
    if (mc.mbGetMtag(b) != mc.JS_MTAG_FUNCTION_BYTECODE)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "bytecode function expected");
    val = runtime.js_closure(ctx, val, null);
    if (vt.isExactException(val))
        return val;
    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &val_ref, val);
    const err = utils.JS_StackCheck(ctx, 2);
    val = utils.popValue(ctx, &val_ref);
    if (err != 0)
        return c.JS_EXCEPTION;
    runtime.JS_PushArg(ctx, val);
    runtime.JS_PushArg(ctx, c.JS_NULL);
    return runtime.JS_Call(ctx, 0);
}

pub fn JS_Eval(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    const val = JS_Parse(ctx, input, input_len, filename, eval_flags);
    if (vt.isExactException(val))
        return val;
    return JS_Run(ctx, val);
}
