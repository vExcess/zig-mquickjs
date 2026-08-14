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
const BlockEnv = pt.BlockEnv;
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

inline fn cx(ctx: *c.JSContext) *mc.JSContextExt {
    return mc.ctxExt(ctx);
}

fn pushValue(ctx: *c.JSContext, ref: *c.JSGCRef, val: c.JSValue) void {
    _ = utils.JS_PushGCRef(ctx, ref);
    ref.val = val;
}

fn popValue(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    return utils.JS_PopGCRef(ctx, ref);
}

fn get_u8(p: [*]const u8) u8 {
    return p[0];
}

fn get_u16(p: [*]const u8) u32 {
    return @as(*align(1) const u16, @ptrCast(p)).*;
}

fn get_u32(p: [*]const u8) u32 {
    return @as(*align(1) const u32, @ptrCast(p)).*;
}

fn put_u16(p: [*]u8, val: u16) void {
    @as(*align(1) u16, @ptrCast(p)).* = val;
}

fn put_u32(p: [*]u8, val: u32) void {
    @as(*align(1) u32, @ptrCast(p)).* = val;
}

fn get_be32(d: [*]const u8) u32 {
    return @byteSwap(get_u32(d));
}

fn put_be32(d: [*]u8, v: u32) void {
    put_u32(d, @byteSwap(v));
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

fn blockEnv(ctx: *c.JSContext, val: c.JSValue) *BlockEnv {
    return @ptrCast(@alignCast(rt.valueToSp(ctx, val)));
}

pub fn is_label(s: *JSParseState) c.JS_BOOL {
    return @intFromBool(s.token.val == lt.TOK_IDENT and s.source_buf[s.buf_pos] == ':');
}

fn is_var_decl_token(tok: c_int) bool {
    return tok == lt.TOK_VAR or tok == lt.TOK_LET or tok == lt.TOK_CONST;
}

fn get_byte_code(s: *JSParseState) [*]u8 {
    return vt.byteArrayBuf(byteArr(s.byte_code));
}

pub fn emit_claim_size(s: *JSParseState, n: c_int) void {
    const val = value.js_resize_byte_array(s.ctx, s.byte_code, @intCast(s.byte_code_len + @as(u32, @intCast(n))));
    if (vt.isExactException(val))
        lexer.js_parse_error_mem(s);
    s.byte_code = val;
}

pub fn emit_u8(s: *JSParseState, val: u8) void {
    emit_claim_size(s, 1);
    const arr = byteArr(s.byte_code);
    vt.byteArrayBuf(arr)[s.byte_code_len] = val;
    s.byte_code_len += 1;
}

pub fn emit_u16(s: *JSParseState, val: u16) void {
    emit_claim_size(s, 2);
    const arr = byteArr(s.byte_code);
    put_u16(vt.byteArrayBuf(arr) + s.byte_code_len, val);
    s.byte_code_len += 2;
}

pub fn emit_u32(s: *JSParseState, val: u32) void {
    emit_claim_size(s, 4);
    const arr = byteArr(s.byte_code);
    put_u32(vt.byteArrayBuf(arr) + s.byte_code_len, val);
    s.byte_code_len += 4;
}

pub fn pc2line_put_bits_short(s: *JSParseState, n: c_int, bits: u32) void {
    const index = s.pc2line_bit_len;
    const pos = index >> 3;

    var b = funcBc(s.cur_func);
    const val1 = value.js_resize_byte_array(s.ctx, b.pc2line, @intCast(pos + 4));
    if (vt.isExactException(val1))
        lexer.js_parse_error_mem(s);
    b = funcBc(s.cur_func);
    b.pc2line = val1;

    const arr = byteArr(val1);
    const p = vt.byteArrayBuf(arr) + pos;
    var val = get_be32(p);
    const shift: u5 = @intCast(32 - @as(c_int, @intCast(index & 7)) - n);
    val &= ~(((@as(u32, 1) << @intCast(n)) - 1) << shift);
    val |= bits << shift;
    put_be32(p, val);
    s.pc2line_bit_len = index + @as(u32, @intCast(n));
}

pub fn pc2line_put_bits(s: *JSParseState, n_in: c_int, bits_in: u32) void {
    var n = n_in;
    var bits = bits_in;
    const n_max: c_int = 25;
    if (n > n_max) {
        pc2line_put_bits_short(s, n - n_max, bits >> @intCast(n_max));
        bits &= (@as(u32, 1) << @intCast(n_max)) - 1;
        n = n_max;
    }
    pc2line_put_bits_short(s, n, bits);
}

pub fn put_ugolomb(s: *JSParseState, v_in: u32) void {
    const v = v_in + 1;
    const n = 32 - clz32(v);
    if (n > 1)
        pc2line_put_bits(s, n - 1, 0);
    pc2line_put_bits(s, n, v);
}

pub fn put_sgolomb(s: *JSParseState, v1: i32) void {
    const v: u32 = @bitCast(v1);
    put_ugolomb(s, (2 *% v) ^ (0 -% (v >> 31)));
}

pub fn get_line_col_delta(pcol_num: *c_int, buf: [*]const u8, pos1: c_int, pos2: c_int) c_int {
    var line_num: c_int = 0;
    var col_num: c_int = 0;
    if (pos2 >= pos1) {
        line_num = lexer.get_line_col(&col_num, buf + @as(usize, @intCast(pos1)), @intCast(pos2 - pos1));
    } else {
        line_num = lexer.get_line_col(&col_num, buf + @as(usize, @intCast(pos2)), @intCast(pos1 - pos2));
        line_num = -line_num;
        col_num = -col_num;
        if (line_num != 0) {
            col_num = 0;
            var i = pos2 - 1;
            while (i >= 0) : (i -= 1) {
                const ch = buf[@intCast(i)];
                if (ch == '\n') {
                    break;
                } else if (ch < 0x80 or ch >= 0xc0) {
                    col_num += 1;
                }
            }
        }
    }
    pcol_num.* = col_num;
    return line_num;
}

pub fn emit_pc2line(s: *JSParseState, pos: u32) void {
    var col_delta: c_int = 0;
    const line_delta = get_line_col_delta(&col_delta, s.source_buf, @intCast(s.pc2line_source_pos), @intCast(pos));
    put_sgolomb(s, line_delta);
    if (asBool(s.has_column)) {
        if (line_delta == 0) {
            put_sgolomb(s, col_delta);
        } else {
            put_ugolomb(s, @bitCast(col_delta));
        }
    }
    s.pc2line_source_pos = pos;
}

pub fn emit_op_pos(s: *JSParseState, op: u8, source_pos: u32) void {
    s.last_opcode_pos = @intCast(s.byte_code_len);
    s.last_pc2line_pos = @intCast(s.pc2line_bit_len);
    s.last_pc2line_source_pos = s.pc2line_source_pos;
    emit_pc2line(s, source_pos);
    emit_u8(s, op);
}

pub fn emit_op(s: *JSParseState, op: u8) void {
    emit_op_pos(s, op, s.pc2line_source_pos);
}

pub fn emit_op_param(s: *JSParseState, op: u8, param: u32, source_pos: u32) void {
    emit_op_pos(s, op, source_pos);
    const oi = rt.opcode_info_data[op];
    switch (oi.fmt) {
        rt.OP_FMT_none => {},
        rt.OP_FMT_npop => emit_u16(s, @intCast(param)),
        else => std.debug.assert(false),
    }
}

pub fn emit_insert(s: *JSParseState, pos: c_int, n: c_int) void {
    emit_claim_size(s, n);
    const arr = byteArr(s.byte_code);
    const buf = vt.byteArrayBuf(arr);
    const src = buf + @as(usize, @intCast(pos));
    const dest = buf + @as(usize, @intCast(pos + n));
    const len = s.byte_code_len - @as(u32, @intCast(pos));
    std.mem.copyBackwards(u8, dest[0..len], src[0..len]);
    s.byte_code_len += @as(u32, @intCast(n));
}

fn get_prev_opcode(s: *JSParseState) c_int {
    if (s.last_opcode_pos < 0) {
        return OP.invalid;
    } else {
        return get_byte_code(s)[@intCast(s.last_opcode_pos)];
    }
}

fn js_is_live_code(s: *JSParseState) bool {
    return switch (get_prev_opcode(s)) {
        OP.@"return", OP.return_undef, OP.throw, OP.goto, OP.ret => false,
        else => true,
    };
}

pub fn remove_last_op(s: *JSParseState) void {
    s.byte_code_len = @intCast(s.last_opcode_pos);
    s.pc2line_bit_len = @intCast(s.last_pc2line_pos);
    s.pc2line_source_pos = s.last_pc2line_source_pos;
    s.last_opcode_pos = -1;
}

pub fn emit_push_short_int(s: *JSParseState, val: c_int) void {
    if (val >= -1 and val <= 7) {
        emit_op(s, @intCast(OP.push_0 + val));
    } else if (val == @as(i8, @truncate(val))) {
        emit_op(s, @intCast(OP.push_i8));
        emit_u8(s, @bitCast(@as(i8, @truncate(val))));
    } else if (val == @as(i16, @truncate(val))) {
        emit_op(s, @intCast(OP.push_i16));
        emit_u16(s, @bitCast(@as(i16, @truncate(val))));
    } else {
        emit_op(s, @intCast(OP.push_value));
        emit_u32(s, @truncate(vt.newShortInt(val)));
    }
}

pub fn emit_var(s: *JSParseState, opcode: c_int, var_idx: c_int, source_pos: u32) void {
    switch (opcode) {
        OP.get_loc => {
            if (var_idx < 4) {
                emit_op_pos(s, @intCast(OP.get_loc0 + var_idx), source_pos);
                return;
            } else if (var_idx < 256) {
                emit_op_pos(s, @intCast(OP.get_loc8), source_pos);
                emit_u8(s, @intCast(var_idx));
                return;
            }
        },
        OP.put_loc => {
            if (var_idx < 4) {
                emit_op_pos(s, @intCast(OP.put_loc0 + var_idx), source_pos);
                return;
            } else if (var_idx < 256) {
                emit_op_pos(s, @intCast(OP.put_loc8), source_pos);
                emit_u8(s, @intCast(var_idx));
                return;
            }
        },
        OP.get_arg => {
            if (var_idx < 4) {
                emit_op_pos(s, @intCast(OP.get_arg0 + var_idx), source_pos);
                return;
            }
        },
        OP.put_arg => {
            if (var_idx < 4) {
                emit_op_pos(s, @intCast(OP.put_arg0 + var_idx), source_pos);
                return;
            }
        },
        else => {},
    }
    emit_op_pos(s, @intCast(opcode), source_pos);
    emit_u16(s, @intCast(var_idx));
}

fn label_is_none(label: c.JSValue) bool {
    return vt.valueGetInt(label) < 0;
}

fn new_label(s: *JSParseState) c.JSValue {
    _ = s;
    return vt.newShortInt(pt.LABEL_OFFSET_MASK);
}

fn emit_label_pos(s: *JSParseState, plabel: *c.JSValue, pos: c_int) void {
    var label = vt.valueGetInt(plabel.*);
    std.debug.assert(label & pt.LABEL_RESOLVED_FLAG == 0);
    const arr = byteArr(s.byte_code);
    const buf = vt.byteArrayBuf(arr);
    while (label != pt.LABEL_OFFSET_MASK) {
        const next = @as(c_int, @bitCast(get_u32(buf + @as(usize, @intCast(label)))));
        put_u32(buf + @as(usize, @intCast(label)), @bitCast(pos - label));
        label = next;
    }
    plabel.* = vt.newShortInt(pos | pt.LABEL_RESOLVED_FLAG);
}

fn emit_label(s: *JSParseState, plabel: *c.JSValue) void {
    emit_label_pos(s, plabel, @intCast(s.byte_code_len));
    s.last_opcode_pos = -1;
}

fn emit_goto(s: *JSParseState, opcode: c_int, plabel: *c.JSValue) void {
    emit_op(s, @intCast(opcode));
    const label = vt.valueGetInt(plabel.*);
    if (label & pt.LABEL_RESOLVED_FLAG != 0) {
        emit_u32(s, @bitCast((label & pt.LABEL_OFFSET_MASK) - @as(c_int, @intCast(s.byte_code_len))));
    } else {
        emit_u32(s, @bitCast(label));
        plabel.* = vt.newShortInt(@as(c_int, @intCast(s.byte_code_len)) - 4);
    }
}

pub fn cpool_add(s: *JSParseState, val: c.JSValue) c_int {
    var b = funcBc(s.cur_func);
    var arr = valueArr(b.cpool);
    var i: c_int = 0;
    while (i < s.cpool_len) : (i += 1) {
        if (vt.valueArrayItems(arr)[@intCast(i)] == val)
            return i;
    }
    if (s.cpool_len > 65535)
        lexer.js_parse_error(s, "too many constants");
    var val_ref: c.JSGCRef = undefined;
    pushValue(s.ctx, &val_ref, val);
    const new_cpool = value.js_resize_value_array(s.ctx, b.cpool, max_int(s.cpool_len + 1, 4));
    _ = popValue(s.ctx, &val_ref);
    if (vt.isExactException(new_cpool))
        lexer.js_parse_error_mem(s);
    b = funcBc(s.cur_func);
    b.cpool = new_cpool;
    arr = valueArr(b.cpool);
    vt.valueArrayItems(arr)[s.cpool_len] = val;
    s.cpool_len += 1;
    return s.cpool_len - 1;
}

pub fn js_emit_push_const(s: *JSParseState, val: c.JSValue) void {
    if (mc.isPtr(val) or mc.isShortFloat(val)) {
        const idx = cpool_add(s, val);
        emit_op(s, @intCast(OP.push_const));
        emit_u16(s, @intCast(idx));
    } else {
        emit_op(s, @intCast(OP.push_value));
        emit_u32(s, @truncate(val));
    }
}

pub fn find_func_var(ctx: *c.JSContext, func: c.JSValue, name: c.JSValue) c_int {
    _ = ctx;
    const b = funcBc(func);
    if (b.vars == c.JS_NULL)
        return -1;
    const arr = valueArr(b.vars);
    const items = vt.valueArrayItems(arr);
    const n = vt.valueArraySize(arr);
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        if (items[@intCast(i)] == name)
            return i;
    }
    return -1;
}

pub fn find_var(s: *JSParseState, name: c.JSValue) c_int {
    const b = funcBc(s.cur_func);
    const arr = valueArr(b.vars);
    const items = vt.valueArrayItems(arr);
    var i: c_int = 0;
    while (i < s.local_vars_len) : (i += 1) {
        if (items[@intCast(i)] == name)
            return i;
    }
    return -1;
}

pub fn get_ext_var_name(s: *JSParseState, var_idx: c_int) c.JSValue {
    const b = funcBc(s.cur_func);
    const arr = valueArr(b.ext_vars);
    return vt.valueArrayItems(arr)[@intCast(2 * var_idx)];
}

pub fn find_func_ext_var(s: *JSParseState, func: c.JSValue, name: c.JSValue) c_int {
    _ = s;
    const b = funcBc(func);
    const arr = valueArr(b.ext_vars);
    const items = vt.valueArrayItems(arr);
    var i: c_int = 0;
    while (i < b.ext_vars_len) : (i += 1) {
        if (items[@intCast(2 * i)] == name)
            return i;
    }
    return -1;
}

pub fn find_ext_var(s: *JSParseState, name: c.JSValue) c_int {
    return find_func_ext_var(s, s.cur_func, name);
}

pub fn add_func_ext_var(s: *JSParseState, func: c.JSValue, name: c.JSValue, decl: c_int) c_int {
    var b = funcBc(func);
    if (b.ext_vars_len >= pt.JS_MAX_LOCAL_VARS)
        lexer.js_parse_error(s, "too many variable references");
    var func_ref: c.JSGCRef = undefined;
    var name_ref: c.JSGCRef = undefined;
    pushValue(s.ctx, &func_ref, func);
    pushValue(s.ctx, &name_ref, name);
    const new_ext_vars = value.js_resize_value_array(s.ctx, b.ext_vars, max_int(b.ext_vars_len + 1, 2) * 2);
    _ = popValue(s.ctx, &name_ref);
    _ = popValue(s.ctx, &func_ref);
    if (vt.isExactException(new_ext_vars))
        lexer.js_parse_error_mem(s);
    b = funcBc(func);
    b.ext_vars = new_ext_vars;
    const arr = valueArr(b.ext_vars);
    const items = vt.valueArrayItems(arr);
    items[@intCast(2 * b.ext_vars_len)] = name;
    items[@intCast(2 * b.ext_vars_len + 1)] = vt.newShortInt(decl);
    b.ext_vars_len += 1;
    return b.ext_vars_len - 1;
}

pub fn add_ext_var(s: *JSParseState, name: c.JSValue, decl: c_int) c_int {
    return add_func_ext_var(s, s.cur_func, name, decl);
}

pub fn add_var(s: *JSParseState, name: c.JSValue) c_int {
    var b = funcBc(s.cur_func);
    if (s.local_vars_len >= pt.JS_MAX_LOCAL_VARS)
        lexer.js_parse_error(s, "too many local variables");
    var name_ref: c.JSGCRef = undefined;
    pushValue(s.ctx, &name_ref, name);
    const new_vars = value.js_resize_value_array(s.ctx, b.vars, max_int(s.local_vars_len + 1, 4));
    _ = popValue(s.ctx, &name_ref);
    if (vt.isExactException(new_vars))
        lexer.js_parse_error_mem(s);
    b = funcBc(s.cur_func);
    b.vars = new_vars;
    const arr = valueArr(b.vars);
    vt.valueArrayItems(arr)[s.local_vars_len] = name;
    s.local_vars_len += 1;
    return s.local_vars_len - 1;
}

pub fn get_lvalue(s: *JSParseState, popcode: *c_int, pvar_idx: *c_int, psource_pos: *u32, keep: bool) void {
    var opcode = get_prev_opcode(s);
    var var_idx: c_int = 0;
    switch (opcode) {
        OP.get_loc0, OP.get_loc1, OP.get_loc2, OP.get_loc3 => {
            var_idx = opcode - OP.get_loc0;
            opcode = OP.get_loc;
        },
        OP.get_arg0, OP.get_arg1, OP.get_arg2, OP.get_arg3 => {
            var_idx = opcode - OP.get_arg0;
            opcode = OP.get_arg;
        },
        OP.get_loc8 => {
            var_idx = get_u8(get_byte_code(s) + @as(usize, @intCast(s.last_opcode_pos + 1)));
            opcode = OP.get_loc;
        },
        OP.get_loc, OP.get_arg, OP.get_var_ref, OP.get_field => {
            var_idx = @intCast(get_u16(get_byte_code(s) + @as(usize, @intCast(s.last_opcode_pos + 1))));
        },
        OP.get_array_el, OP.get_length => {
            var_idx = -1;
        },
        else => lexer.js_parse_error(s, "invalid lvalue"),
    }
    const source_pos = s.pc2line_source_pos;
    remove_last_op(s);

    if (keep) {
        switch (opcode) {
            OP.get_loc, OP.get_arg, OP.get_var_ref => emit_var(s, opcode, var_idx, source_pos),
            OP.get_field => {
                emit_op_pos(s, @intCast(OP.get_field2), source_pos);
                emit_u16(s, @intCast(var_idx));
            },
            OP.get_length => emit_op_pos(s, @intCast(OP.get_length2), source_pos),
            OP.get_array_el => {
                emit_op(s, @intCast(OP.dup2));
                emit_op_pos(s, @intCast(OP.get_array_el), source_pos);
            },
            else => c_abort(),
        }
    }
    popcode.* = opcode;
    pvar_idx.* = var_idx;
    psource_pos.* = source_pos;
}

pub fn put_lvalue(s: *JSParseState, opcode_in: c_int, var_idx: c_int, source_pos: u32, special: c_int) void {
    var opcode = opcode_in;
    switch (opcode) {
        OP.get_loc, OP.get_arg, OP.get_var_ref => {
            if (special == pt.PUT_LVALUE_KEEP_TOP)
                emit_op(s, @intCast(OP.dup));
            if (opcode == OP.get_var_ref and asBool(s.is_repl))
                opcode = OP.put_var_ref_nocheck
            else
                opcode += 1;
            emit_var(s, opcode, var_idx, source_pos);
        },
        OP.get_field, OP.get_length => {
            switch (special) {
                pt.PUT_LVALUE_KEEP_TOP => emit_op(s, @intCast(OP.insert2)),
                pt.PUT_LVALUE_NOKEEP_TOP => {},
                pt.PUT_LVALUE_NOKEEP_BOTTOM => emit_op(s, @intCast(OP.swap)),
                else => emit_op(s, @intCast(OP.perm3)),
            }
            emit_op_pos(s, @intCast(OP.put_field), source_pos);
            if (opcode == OP.get_length) {
                emit_u16(s, @intCast(cpool_add(s, utils.js_get_atom(s.ctx, c.JS_ATOM_length))));
            } else {
                emit_u16(s, @intCast(var_idx));
            }
        },
        OP.get_array_el => {
            switch (special) {
                pt.PUT_LVALUE_KEEP_TOP => emit_op(s, @intCast(OP.insert3)),
                pt.PUT_LVALUE_NOKEEP_TOP => {},
                pt.PUT_LVALUE_NOKEEP_BOTTOM => emit_op(s, @intCast(OP.rot3l)),
                else => emit_op(s, @intCast(OP.perm4)),
            }
            emit_op_pos(s, @intCast(OP.put_array_el), source_pos);
        },
        else => c_abort(),
    }
}

pub fn js_parse_property_name(s: *JSParseState, pname: *c.JSValue) c_int {
    const ctx = s.ctx;
    var name: c.JSValue = c.JS_UNDEFINED;
    var name_ref: c.JSGCRef = undefined;
    var prop_type: c_int = pt.PARSE_PROP_FIELD;

    if (s.token.val == lt.TOK_IDENT) {
        var is_set: c_int = undefined;
        if (s.token.value == utils.js_get_atom(ctx, c.JS_ATOM_get))
            is_set = 0
        else if (s.token.value == utils.js_get_atom(ctx, c.JS_ATOM_set))
            is_set = 1
        else
            is_set = -1;
        if (is_set >= 0) {
            lexer.next_token(s);
            if (s.token.val == ':' or s.token.val == ',' or
                s.token.val == '}' or s.token.val == '(')
            {
                name = utils.js_get_atom(ctx, if (is_set != 0) c.JS_ATOM_set else c.JS_ATOM_get);
            } else {
                prop_type = pt.PARSE_PROP_GET + is_set;
            }
        }
    }

    if (name == c.JS_UNDEFINED) {
        if (s.token.val == lt.TOK_IDENT or s.token.val >= lt.TOK_FIRST_KEYWORD) {
            name = s.token.value;
        } else if (s.token.val == lt.TOK_STRING) {
            name = s.token.value;
        } else if (s.token.val == lt.TOK_NUMBER) {
            name = value.JS_NewFloat64(s.ctx, s.token.u.d);
            if (vt.isExactException(name))
                lexer.js_parse_error_mem(s);
        } else {
            lexer.js_parse_error(s, "invalid property name");
        }
        name = runtime.JS_ToPropertyKey(s.ctx, name);
        if (vt.isExactException(name))
            lexer.js_parse_error_mem(s);
        pushValue(ctx, &name_ref, name);
        lexer.next_token(s);
        name = popValue(ctx, &name_ref);
    }
    if (prop_type == pt.PARSE_PROP_FIELD and s.token.val == '(')
        prop_type = pt.PARSE_PROP_METHOD;
    pname.* = name;
    return prop_type;
}

pub fn parse_stack_alloc(s: *JSParseState, val_in: c.JSValue) c.JSValue {
    var val_ref: c.JSGCRef = undefined;
    pushValue(s.ctx, &val_ref, val_in);
    if (utils.JS_StackCheck(s.ctx, 1) != 0)
        lexer.js_parse_error_stack_overflow(s);
    return popValue(s.ctx, &val_ref);
}

pub fn js_parse_push_val(s: *JSParseState, val_in: c.JSValue) void {
    const ctx = s.ctx;
    var val = val_in;
    if (@intFromPtr(cx(ctx).sp) <= @intFromPtr(cx(ctx).stack_bottom)) {
        val = parse_stack_alloc(s, val);
    }
    const x = cx(ctx);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp - 1);
    x.sp.* = val;
}

pub fn js_parse_pop_val(s: *JSParseState) c.JSValue {
    const x = cx(s.ctx);
    const val = x.sp.*;
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp + 1);
    const slack = @as([*]c.JSValue, @ptrCast(x.sp)) - pt.JS_STACK_SLACK;
    if (@intFromPtr(slack) > @intFromPtr(x.stack_bottom))
        x.stack_bottom = @ptrCast(slack);
    return val;
}

pub fn js_parse_call(s: *JSParseState, func_idx_in: c_int, param_in: c_int) void {
    const x = cx(s.ctx);
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

pub fn may_drop_result(s: *JSParseState, parse_flags: c_int) bool {
    return (parse_flags & pt.PF_DROP) != 0 and
        (s.token.val == ';' or s.token.val == ')' or s.token.val == ',');
}

pub fn js_emit_push_number(s: *JSParseState, d: f64) void {
    const val = value.JS_NewFloat64(s.ctx, d);
    if (vt.isExactException(val))
        lexer.js_parse_error_mem(s);
    if (mc.isInt(val)) {
        emit_push_short_int(s, vt.valueGetInt(val));
    } else {
        js_emit_push_const(s, val);
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
pub fn js_parse_postfix_expr(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var is_new = false;
    var prop_idx: c_int = 0;
    var count_pos: c_int = 0;
    var has_proto = false;
    var idx: u32 = 0;
    var opcode: c_int = 0;
    var arg_count: c_int = 0;
    var op_source_pos: u32 = 0;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            switch (s.token.val) {
                lt.TOK_NUMBER => {
                    js_emit_push_number(s, s.token.u.d);
                    lexer.next_token(s);
                },
                lt.TOK_STRING => {
                    js_emit_push_const(s, s.token.value);
                    lexer.next_token(s);
                },
                lt.TOK_REGEXP => {
                    js_emit_push_const(s, s.token.value);
                    const saved_buf_pos = s.buf_pos;
                    const saved_buf_len = s.buf_len;
                    var b = funcBc(s.cur_func);
                    b.byte_code = s.byte_code;
                    const saved_byte_code_len = s.byte_code_len;
                    s.buf_pos = s.token.source_pos + 1;
                    s.buf_len = s.token.u.regexp.re_end_pos;
                    const byte_code = builtins.js_parse_regexp(s, @intCast(s.token.u.regexp.re_flags));
                    s.buf_pos = saved_buf_pos;
                    s.buf_len = saved_buf_len;
                    b = funcBc(s.cur_func);
                    s.byte_code = b.byte_code;
                    s.byte_code_len = saved_byte_code_len;
                    js_emit_push_const(s, byte_code);
                    emit_op(s, @intCast(OP.regexp));
                    lexer.next_token(s);
                },
                '(' => {
                    lexer.next_token(s);
                    parsePushInt(s, parse_flags);
                    return parseCall(0, pt.PARSE_FUNC_js_parse_expr_comma, 0);
                },
                lt.TOK_FUNCTION => js_parse_function_decl(s, pt.JS_PARSE_FUNC_EXPR, c.JS_NULL),
                lt.TOK_NULL => {
                    emit_op(s, @intCast(OP.null));
                    lexer.next_token(s);
                },
                lt.TOK_THIS => {
                    emit_op(s, @intCast(OP.push_this));
                    lexer.next_token(s);
                },
                lt.TOK_FALSE, lt.TOK_TRUE => {
                    emit_op(s, @intCast(OP.push_false + @intFromBool(s.token.val == lt.TOK_TRUE)));
                    lexer.next_token(s);
                },
                lt.TOK_IDENT => {
                    const b = funcBc(s.cur_func);
                    const arg_count1 = rt.bytecodeArgCount(b);
                    const name = s.token.value;
                    var var_idx = find_var(s, name);
                    var op: c_int = undefined;
                    if (var_idx >= 0) {
                        if (var_idx < arg_count1) {
                            op = OP.get_arg;
                        } else {
                            op = OP.get_loc;
                            var_idx -= arg_count1;
                        }
                    } else {
                        var_idx = find_ext_var(s, name);
                        if (var_idx < 0)
                            var_idx = add_ext_var(s, name, (rt.JS_VARREF_KIND_GLOBAL << 16) | 0);
                        op = OP.get_var_ref;
                    }
                    emit_var(s, op, var_idx, s.token.source_pos);
                    lexer.next_token(s);
                },
                '{' => {
                    lexer.next_token(s);
                    emit_op(s, @intCast(OP.object));
                    count_pos = @intCast(s.byte_code_len);
                    emit_u16(s, 0);
                    has_proto = false;
                    continue :sw 101;
                },
                '[' => {
                    lexer.next_token(s);
                    idx = 0;
                    continue :sw 102;
                },
                lt.TOK_NEW => {
                    lexer.next_token(s);
                    if (s.token.val == '.') {
                        lexer.next_token(s);
                        if (s.token.val != lt.TOK_IDENT or
                            s.token.value != utils.js_get_atom(s.ctx, c.JS_ATOM_target))
                        {
                            lexer.js_parse_error(s, "expecting target");
                        }
                        lexer.next_token(s);
                        emit_op(s, @intCast(OP.new_target));
                    } else {
                        parsePushInt(s, parse_flags);
                        return parseCall(4, pt.PARSE_FUNC_js_parse_postfix_expr, 0);
                    }
                },
                else => lexer.js_parse_error(s, "unexpected character in expression"),
            }
            continue :sw 100;
        },
        0 => {
            parse_flags = parsePopInt(s);
            lexer.js_parse_expect(s, ')');
            continue :sw 100;
        },
        1 => {
            count_pos = parsePopInt(s);
            has_proto = parsePopInt(s) != 0;
            parse_flags = parsePopInt(s);
            prop_idx = parsePopInt(s);
            if (prop_idx >= 0) {
                emit_op(s, @intCast(OP.define_field));
                emit_u16(s, @intCast(prop_idx));
            } else {
                emit_op(s, @intCast(OP.set_proto));
            }
            continue :sw 104;
        },
        2 => {
            parse_flags = parsePopInt(s);
            idx = @bitCast(parsePopInt(s));
            idx += 1;
            if (s.token.val == ',') {
                lexer.next_token(s);
            } else if (s.token.val != ']') {
                continue :sw 103;
            }
            continue :sw 102;
        },
        3 => {
            parse_flags = parsePopInt(s);
            idx = @bitCast(parsePopInt(s));
            emit_op(s, @intCast(OP.put_array_el));
            idx += 1;
            if (s.token.val == ',')
                lexer.next_token(s);
            continue :sw 105;
        },
        4 => {
            parse_flags = parsePopInt(s);
            if (s.token.val != '(') {
                emit_op_param(s, @intCast(OP.call_constructor), 0, s.token.source_pos);
                continue :sw 100;
            } else {
                is_new = true;
                continue :sw 100;
            }
        },
        5 => {
            op_source_pos = @bitCast(parsePopInt(s));
            is_new = parsePopInt(s) != 0;
            opcode = parsePopInt(s);
            arg_count = parsePopInt(s);
            parse_flags = parsePopInt(s);
            if (s.token.val == ')') {
                continue :sw 106;
            }
            lexer.js_parse_expect(s, ',');
            continue :sw 107;
        },
        6 => {
            op_source_pos = @bitCast(parsePopInt(s));
            is_new = parsePopInt(s) != 0;
            parse_flags = parsePopInt(s);
            lexer.js_parse_expect(s, ']');
            emit_op_pos(s, @intCast(OP.get_array_el), op_source_pos);
            continue :sw 100;
        },
        101 => {
            if (s.token.val == '}') {
                lexer.js_parse_expect(s, '}');
                continue :sw 100;
            }
            var name: c.JSValue = undefined;
            const prop_type = js_parse_property_name(s, &name);
            if (prop_type == pt.PARSE_PROP_FIELD and
                name == utils.js_get_atom(s.ctx, c.JS_ATOM___proto__))
            {
                if (has_proto)
                    lexer.js_parse_error(s, "duplicate __proto__ property name");
                has_proto = true;
                prop_idx = -1;
            } else {
                prop_idx = cpool_add(s, name);
                const byte_code = get_byte_code(s);
                const count = get_u16(byte_code + @as(usize, @intCast(count_pos)));
                put_u16(byte_code + @as(usize, @intCast(count_pos)), @intCast(min_int(@intCast(count + 1), 0xffff)));
            }
            if (prop_type == pt.PARSE_PROP_FIELD) {
                lexer.js_parse_expect(s, ':');
                parsePushInt(s, prop_idx);
                parsePushInt(s, parse_flags);
                parsePushInt(s, @intFromBool(has_proto));
                parsePushInt(s, count_pos);
                return parseCall(1, pt.PARSE_FUNC_js_parse_assign_expr, 0);
            } else {
                js_parse_function_decl(s, pt.JS_PARSE_FUNC_METHOD, name);
                if (prop_type == pt.PARSE_PROP_METHOD)
                    emit_op(s, @intCast(OP.define_field))
                else if (prop_type == pt.PARSE_PROP_GET)
                    emit_op(s, @intCast(OP.define_getter))
                else
                    emit_op(s, @intCast(OP.define_setter));
                emit_u16(s, @intCast(prop_idx));
                continue :sw 104;
            }
        },
        104 => {
            if (s.token.val != ',') {
                lexer.js_parse_expect(s, '}');
                continue :sw 100;
            }
            lexer.next_token(s);
            continue :sw 101;
        },
        102 => {
            if (s.token.val != ']' and idx < 32) {
                parsePushInt(s, @bitCast(idx));
                parsePushInt(s, parse_flags);
                return parseCall(2, pt.PARSE_FUNC_js_parse_assign_expr, 0);
            }
            continue :sw 103;
        },
        103 => {
            emit_op_param(s, @intCast(OP.array_from), idx, s.pc2line_source_pos);
            continue :sw 105;
        },
        105 => {
            if (s.token.val != ']') {
                if (idx >= vt.JS_SHORTINT_MAX)
                    lexer.js_parse_error(s, "too many elements");
                emit_op(s, @intCast(OP.dup));
                emit_push_short_int(s, @bitCast(idx));
                parsePushInt(s, @bitCast(idx));
                parsePushInt(s, parse_flags);
                return parseCall(3, pt.PARSE_FUNC_js_parse_assign_expr, 0);
            }
            lexer.js_parse_expect(s, ']');
            continue :sw 100;
        },
        100 => {
            if (s.token.val == '(' and (parse_flags & pt.PF_ACCEPT_LPAREN) != 0) {
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                if (!is_new) {
                    opcode = get_prev_opcode(s);
                    const byte_code = get_byte_code(s);
                    switch (opcode) {
                        OP.get_field => byte_code[@intCast(s.last_opcode_pos)] = @intCast(OP.get_field2),
                        OP.get_length => byte_code[@intCast(s.last_opcode_pos)] = @intCast(OP.get_length2),
                        OP.get_array_el => byte_code[@intCast(s.last_opcode_pos)] = @intCast(OP.get_array_el2),
                        OP.get_var_ref => {
                            opcode = OP.invalid;
                        },
                        else => opcode = OP.invalid,
                    }
                } else {
                    opcode = OP.invalid;
                }
                arg_count = 0;
                if (s.token.val != ')') {
                    continue :sw 107;
                }
                continue :sw 106;
            } else if (s.token.val == '.') {
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                if (!(s.token.val == lt.TOK_IDENT or s.token.val >= lt.TOK_FIRST_KEYWORD))
                    lexer.js_parse_error(s, "expecting field name");
                if (s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_NaN) or
                    s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_Infinity))
                {
                    js_emit_push_const(s, s.token.value);
                    emit_op_pos(s, @intCast(OP.get_array_el), op_source_pos);
                } else if (s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_length)) {
                    emit_op_pos(s, @intCast(OP.get_length), op_source_pos);
                } else {
                    const pidx = cpool_add(s, s.token.value);
                    emit_op_pos(s, @intCast(OP.get_field), op_source_pos);
                    emit_u16(s, @intCast(pidx));
                }
                lexer.next_token(s);
                continue :sw 100;
            } else if (s.token.val == '[') {
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                parsePushInt(s, parse_flags);
                parsePushInt(s, @intFromBool(is_new));
                parsePushInt(s, @bitCast(op_source_pos));
                return parseCall(6, pt.PARSE_FUNC_js_parse_expr_comma, 0);
            } else if (!asBool(s.got_lf) and (s.token.val == lt.TOK_DEC or s.token.val == lt.TOK_INC)) {
                const op = s.token.val;
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                var lv_opcode: c_int = undefined;
                var var_idx: c_int = undefined;
                var source_pos: u32 = undefined;
                get_lvalue(s, &lv_opcode, &var_idx, &source_pos, true);
                if (may_drop_result(s, parse_flags)) {
                    s.dropped_result = 1;
                    emit_op_pos(s, @intCast(OP.dec + op - lt.TOK_DEC), op_source_pos);
                    put_lvalue(s, lv_opcode, var_idx, source_pos, pt.PUT_LVALUE_NOKEEP_TOP);
                } else {
                    emit_op_pos(s, @intCast(OP.post_dec + op - lt.TOK_DEC), op_source_pos);
                    put_lvalue(s, lv_opcode, var_idx, source_pos, pt.PUT_LVALUE_KEEP_SECOND);
                }
                continue :sw 100;
            } else {
                return pt.PARSE_STATE_RET;
            }
        },
        107 => {
            if (arg_count >= pt.JS_MAX_ARGC)
                lexer.js_parse_error(s, "too many call arguments");
            arg_count += 1;
            parsePushInt(s, parse_flags);
            parsePushInt(s, arg_count);
            parsePushInt(s, opcode);
            parsePushInt(s, @intFromBool(is_new));
            parsePushInt(s, @bitCast(op_source_pos));
            return parseCall(5, pt.PARSE_FUNC_js_parse_assign_expr, 0);
        },
        106 => {
            lexer.next_token(s);
            if (opcode == OP.get_field or opcode == OP.get_length or opcode == OP.get_array_el) {
                emit_op_param(s, @intCast(OP.call_method), @intCast(arg_count), op_source_pos);
            } else if (is_new) {
                emit_op_param(s, @intCast(OP.call_constructor), @intCast(arg_count), op_source_pos);
            } else {
                emit_op_param(s, @intCast(OP.call), @intCast(arg_count), op_source_pos);
            }
            is_new = false;
            continue :sw 100;
        },
        else => c_abort(),
    }
}

fn js_emit_delete(s: *JSParseState) void {
    const opcode = get_prev_opcode(s);
    switch (opcode) {
        OP.get_field => {
            const arr = byteArr(s.byte_code);
            const prop_idx = get_u16(vt.byteArrayBuf(arr) + @as(usize, @intCast(s.last_opcode_pos + 1)));
            remove_last_op(s);
            emit_op(s, @intCast(OP.push_const));
            emit_u16(s, @intCast(prop_idx));
        },
        OP.get_length => {
            remove_last_op(s);
            js_emit_push_const(s, utils.js_get_atom(s.ctx, c.JS_ATOM_length));
        },
        OP.get_array_el => remove_last_op(s),
        else => lexer.js_parse_error(s, "invalid lvalue for delete"),
    }
    emit_op(s, @intCast(OP.delete));
}

pub fn js_parse_unary(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var op: c_int = 0;
    var op_source_pos: u32 = 0;

    switch (state) {
        pt.PARSE_STATE_INIT => {
            switch (s.token.val) {
                '+', '-', '!', '~' => {
                    op = s.token.val;
                    op_source_pos = s.token.source_pos;
                    lexer.next_token(s);
                    if (s.token.val == lt.TOK_NUMBER and (op == '-' or op == '+')) {
                        var d = s.token.u.d;
                        if (op == '-')
                            d = -d;
                        js_emit_push_number(s, d);
                        lexer.next_token(s);
                        return pt.PARSE_STATE_RET;
                    }
                    parsePushInt(s, op);
                    parsePushInt(s, @bitCast(op_source_pos));
                    return parseCall(0, pt.PARSE_FUNC_js_parse_unary, 0);
                },
                lt.TOK_VOID => {
                    lexer.next_token(s);
                    return parseCall(1, pt.PARSE_FUNC_js_parse_unary, 0);
                },
                lt.TOK_DEC, lt.TOK_INC => {
                    op = s.token.val;
                    op_source_pos = s.token.source_pos;
                    lexer.next_token(s);
                    parsePushInt(s, op);
                    parsePushInt(s, parse_flags);
                    parsePushInt(s, @bitCast(op_source_pos));
                    return parseCall(2, pt.PARSE_FUNC_js_parse_unary, 0);
                },
                lt.TOK_TYPEOF => {
                    lexer.next_token(s);
                    return parseCall(3, pt.PARSE_FUNC_js_parse_unary, 0);
                },
                lt.TOK_DELETE => {
                    lexer.next_token(s);
                    return parseCall(4, pt.PARSE_FUNC_js_parse_unary, 0);
                },
                else => return parseCall(5, pt.PARSE_FUNC_js_parse_postfix_expr, parse_flags | pt.PF_ACCEPT_LPAREN),
            }
        },
        0 => {
            op_source_pos = @bitCast(parsePopInt(s));
            op = parsePopInt(s);
            switch (op) {
                '-' => emit_op_pos(s, @intCast(OP.neg), op_source_pos),
                '+' => emit_op_pos(s, @intCast(OP.plus), op_source_pos),
                '!' => emit_op_pos(s, @intCast(OP.lnot), op_source_pos),
                '~' => emit_op_pos(s, @intCast(OP.not), op_source_pos),
                else => c_abort(),
            }
            return pt.PARSE_STATE_RET;
        },
        1 => {
            emit_op(s, @intCast(OP.drop));
            emit_op(s, @intCast(OP.undefined));
            return pt.PARSE_STATE_RET;
        },
        2 => {
            op_source_pos = @bitCast(parsePopInt(s));
            parse_flags = parsePopInt(s);
            op = parsePopInt(s);
            var opcode: c_int = undefined;
            var var_idx: c_int = undefined;
            var source_pos: u32 = undefined;
            get_lvalue(s, &opcode, &var_idx, &source_pos, true);
            emit_op_pos(s, @intCast(OP.dec + op - lt.TOK_DEC), op_source_pos);
            const special: c_int = if (may_drop_result(s, parse_flags)) blk: {
                s.dropped_result = 1;
                break :blk pt.PUT_LVALUE_NOKEEP_TOP;
            } else pt.PUT_LVALUE_KEEP_TOP;
            put_lvalue(s, opcode, var_idx, source_pos, special);
            return pt.PARSE_STATE_RET;
        },
        3 => {
            if (get_prev_opcode(s) == OP.get_var_ref) {
                const byte_code = get_byte_code(s);
                byte_code[@intCast(s.last_opcode_pos)] = @intCast(OP.get_var_ref_nocheck);
            }
            emit_op(s, @intCast(OP.typeof));
            return pt.PARSE_STATE_RET;
        },
        4 => {
            js_emit_delete(s);
            return pt.PARSE_STATE_RET;
        },
        5 => {
            if (s.token.val == lt.TOK_POW) {
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                parsePushInt(s, @bitCast(op_source_pos));
                return parseCall(6, pt.PARSE_FUNC_js_parse_unary, 0);
            }
            return pt.PARSE_STATE_RET;
        },
        6 => {
            op_source_pos = @bitCast(parsePopInt(s));
            emit_op_pos(s, @intCast(OP.pow), op_source_pos);
            return pt.PARSE_STATE_RET;
        },
        else => c_abort(),
    }
}

pub fn js_parse_expr_binary(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var opcode: c_int = 0;
    var op_source_pos: u32 = 0;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            const level = (parse_flags & pt.PF_LEVEL_MASK) >> pt.PF_LEVEL_SHIFT;
            if (level == 0)
                return parseCall(0, pt.PARSE_FUNC_js_parse_unary, parse_flags);
            parsePushInt(s, parse_flags);
            return parseCall(1, pt.PARSE_FUNC_js_parse_expr_binary, parse_flags - (1 << pt.PF_LEVEL_SHIFT));
        },
        0 => return pt.PARSE_STATE_RET,
        1 => {
            parse_flags = parsePopInt(s);
            parse_flags &= ~pt.PF_DROP;
            continue :sw 10;
        },
        2 => {
            op_source_pos = @bitCast(parsePopInt(s));
            opcode = parsePopInt(s);
            parse_flags = parsePopInt(s);
            emit_op_pos(s, @intCast(opcode), op_source_pos);
            continue :sw 10;
        },
        10 => {
            const op = s.token.val;
            op_source_pos = s.token.source_pos;
            const level = (parse_flags & pt.PF_LEVEL_MASK) >> pt.PF_LEVEL_SHIFT;
            opcode = switch (level) {
                1 => switch (op) {
                    '*' => OP.mul,
                    '/' => OP.div,
                    '%' => OP.mod,
                    else => return pt.PARSE_STATE_RET,
                },
                2 => switch (op) {
                    '+' => OP.add,
                    '-' => OP.sub,
                    else => return pt.PARSE_STATE_RET,
                },
                3 => switch (op) {
                    lt.TOK_SHL => OP.shl,
                    lt.TOK_SAR => OP.sar,
                    lt.TOK_SHR => OP.shr,
                    else => return pt.PARSE_STATE_RET,
                },
                4 => switch (op) {
                    '<' => OP.lt,
                    '>' => OP.gt,
                    lt.TOK_LTE => OP.lte,
                    lt.TOK_GTE => OP.gte,
                    lt.TOK_INSTANCEOF => OP.instanceof,
                    lt.TOK_IN => if ((parse_flags & pt.PF_NO_IN) == 0) OP.in else return pt.PARSE_STATE_RET,
                    else => return pt.PARSE_STATE_RET,
                },
                5 => switch (op) {
                    lt.TOK_EQ => OP.eq,
                    lt.TOK_NEQ => OP.neq,
                    lt.TOK_STRICT_EQ => OP.strict_eq,
                    lt.TOK_STRICT_NEQ => OP.strict_neq,
                    else => return pt.PARSE_STATE_RET,
                },
                6 => if (op == '&') OP.@"and" else return pt.PARSE_STATE_RET,
                7 => if (op == '^') OP.xor else return pt.PARSE_STATE_RET,
                8 => if (op == '|') OP.@"or" else return pt.PARSE_STATE_RET,
                else => {
                    c_abort();
                },
            };
            lexer.next_token(s);
            parsePushInt(s, parse_flags);
            parsePushInt(s, opcode);
            parsePushInt(s, @bitCast(op_source_pos));
            return parseCall(2, pt.PARSE_FUNC_js_parse_expr_binary, parse_flags - (1 << pt.PF_LEVEL_SHIFT));
        },
        else => c_abort(),
    }
}

pub fn js_parse_logical_and_or(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var label1: c.JSValue = c.JS_UNDEFINED;
    var op: c_int = 0;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            const level = (parse_flags & pt.PF_LEVEL_MASK) >> pt.PF_LEVEL_SHIFT;
            if (level == 0)
                return parseCall(0, pt.PARSE_FUNC_js_parse_expr_binary, (parse_flags & ~pt.PF_LEVEL_MASK) | (8 << pt.PF_LEVEL_SHIFT));
            parsePushInt(s, parse_flags);
            return parseCall(1, pt.PARSE_FUNC_js_parse_logical_and_or, parse_flags - (1 << pt.PF_LEVEL_SHIFT));
        },
        0 => return pt.PARSE_STATE_RET,
        1 => {
            parse_flags = parsePopInt(s);
            const level = (parse_flags & pt.PF_LEVEL_MASK) >> pt.PF_LEVEL_SHIFT;
            op = if (level == 1) lt.TOK_LAND else lt.TOK_LOR;
            parse_flags &= ~pt.PF_DROP;
            if (s.token.val != op)
                return pt.PARSE_STATE_RET;
            label1 = new_label(s);
            continue :sw 10;
        },
        2 => {
            parse_flags = parsePopInt(s);
            label1 = js_parse_pop_val(s);
            const level = (parse_flags & pt.PF_LEVEL_MASK) >> pt.PF_LEVEL_SHIFT;
            op = if (level == 1) lt.TOK_LAND else lt.TOK_LOR;
            if (s.token.val != op) {
                emit_label(s, &label1);
                return pt.PARSE_STATE_RET;
            }
            continue :sw 10;
        },
        10 => {
            lexer.next_token(s);
            emit_op(s, @intCast(OP.dup));
            emit_goto(s, if (op == lt.TOK_LAND) OP.if_false else OP.if_true, &label1);
            emit_op(s, @intCast(OP.drop));
            js_parse_push_val(s, label1);
            parsePushInt(s, parse_flags);
            return parseCall(2, pt.PARSE_FUNC_js_parse_logical_and_or, parse_flags - (1 << pt.PF_LEVEL_SHIFT));
        },
        else => c_abort(),
    }
}

pub fn js_parse_cond_expr(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var label1: c.JSValue = c.JS_UNDEFINED;
    var label2: c.JSValue = c.JS_UNDEFINED;

    switch (state) {
        pt.PARSE_STATE_INIT => {
            parsePushInt(s, parse_flags);
            return parseCall(2, pt.PARSE_FUNC_js_parse_logical_and_or, parse_flags | (2 << pt.PF_LEVEL_SHIFT));
        },
        2 => {
            parse_flags = parsePopInt(s);
            parse_flags &= ~pt.PF_DROP;
            if (s.token.val != '?')
                return pt.PARSE_STATE_RET;
            lexer.next_token(s);
            label1 = new_label(s);
            emit_goto(s, OP.if_false, &label1);
            js_parse_push_val(s, label1);
            parsePushInt(s, parse_flags);
            return parseCall(0, pt.PARSE_FUNC_js_parse_assign_expr, parse_flags);
        },
        0 => {
            parse_flags = parsePopInt(s);
            label1 = js_parse_pop_val(s);
            label2 = new_label(s);
            emit_goto(s, OP.goto, &label2);
            lexer.js_parse_expect(s, ':');
            emit_label(s, &label1);
            js_parse_push_val(s, label2);
            parsePushInt(s, parse_flags);
            return parseCall(1, pt.PARSE_FUNC_js_parse_assign_expr, parse_flags);
        },
        1 => {
            parse_flags = parsePopInt(s);
            label2 = js_parse_pop_val(s);
            emit_label(s, &label2);
            return pt.PARSE_STATE_RET;
        },
        else => c_abort(),
    }
}

pub fn js_parse_assign_expr(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var opcode: c_int = 0;
    var op: c_int = 0;
    var var_idx: c_int = 0;
    var op_source_pos: u32 = 0;
    var source_pos: u32 = 0;

    switch (state) {
        pt.PARSE_STATE_INIT => {
            parsePushInt(s, parse_flags);
            return parseCall(1, pt.PARSE_FUNC_js_parse_cond_expr, parse_flags);
        },
        1 => {
            parse_flags = parsePopInt(s);
            op = s.token.val;
            if (op == '=' or (op >= lt.TOK_MUL_ASSIGN and op <= lt.TOK_OR_ASSIGN)) {
                op_source_pos = s.token.source_pos;
                lexer.next_token(s);
                get_lvalue(s, &opcode, &var_idx, &source_pos, op != '=');
                parsePushInt(s, op);
                parsePushInt(s, opcode);
                parsePushInt(s, var_idx);
                parsePushInt(s, parse_flags);
                parsePushInt(s, @bitCast(op_source_pos));
                parsePushInt(s, @bitCast(source_pos));
                return parseCall(0, pt.PARSE_FUNC_js_parse_assign_expr, parse_flags & ~pt.PF_DROP);
            }
            return pt.PARSE_STATE_RET;
        },
        0 => {
            source_pos = @bitCast(parsePopInt(s));
            op_source_pos = @bitCast(parsePopInt(s));
            parse_flags = parsePopInt(s);
            var_idx = parsePopInt(s);
            opcode = parsePopInt(s);
            op = parsePopInt(s);
            if (op != '=') {
                const assign_opcodes = [_]u8{
                    @intCast(OP.mul),   @intCast(OP.div), @intCast(OP.mod), @intCast(OP.add),    @intCast(OP.sub),
                    @intCast(OP.shl),   @intCast(OP.sar), @intCast(OP.shr), @intCast(OP.@"and"), @intCast(OP.xor),
                    @intCast(OP.@"or"), @intCast(OP.pow),
                };
                emit_op_pos(s, assign_opcodes[@intCast(op - lt.TOK_MUL_ASSIGN)], op_source_pos);
            }
            const special: c_int = if (may_drop_result(s, parse_flags)) blk: {
                s.dropped_result = 1;
                break :blk pt.PUT_LVALUE_NOKEEP_TOP;
            } else pt.PUT_LVALUE_KEEP_TOP;
            put_lvalue(s, opcode, var_idx, source_pos, special);
            return pt.PARSE_STATE_RET;
        },
        else => c_abort(),
    }
}

pub fn js_parse_expr_comma(s: *JSParseState, state: c_int, parse_flags_in: c_int) callconv(.c) c_int {
    var parse_flags = parse_flags_in;
    var comma = false;

    sw: switch (state) {
        pt.PARSE_STATE_INIT => continue :sw 10,
        0 => {
            parse_flags = parsePopInt(s);
            comma = parsePopInt(s) != 0;
            if (comma)
                s.last_opcode_pos = -1;
            if (s.token.val != ',') {
                if ((parse_flags & pt.PF_DROP) != 0 and !asBool(s.dropped_result))
                    emit_op(s, @intCast(OP.drop));
                return pt.PARSE_STATE_RET;
            }
            comma = true;
            if (!asBool(s.dropped_result))
                emit_op(s, @intCast(OP.drop));
            lexer.next_token(s);
            continue :sw 10;
        },
        10 => {
            s.dropped_result = 0;
            parsePushInt(s, @intFromBool(comma));
            parsePushInt(s, parse_flags);
            return parseCall(0, pt.PARSE_FUNC_js_parse_assign_expr, parse_flags);
        },
        else => c_abort(),
    }
}

pub fn js_parse_assign_expr2(s: *JSParseState, parse_flags: c_int) void {
    js_parse_call(s, pt.PARSE_FUNC_js_parse_assign_expr, parse_flags);
}

pub fn js_parse_expr2(s: *JSParseState, parse_flags: c_int) void {
    js_parse_call(s, pt.PARSE_FUNC_js_parse_expr_comma, parse_flags);
}

pub fn js_parse_expr(s: *JSParseState) void {
    js_parse_expr2(s, 0);
}

pub fn js_parse_expr_paren(s: *JSParseState) void {
    lexer.js_parse_expect(s, '(');
    js_parse_expr(s);
    lexer.js_parse_expect(s, ')');
}
fn push_break_entry(s: *JSParseState, label_name: c.JSValue, label_break: c.JSValue, label_cont: c.JSValue, drop_count: c_int) *BlockEnv {
    const ctx = s.ctx;
    const block_env_len = @as(c_int, @intCast(@sizeOf(BlockEnv) / @sizeOf(c.JSValue)));
    var label_name_ref: c.JSGCRef = undefined;
    pushValue(ctx, &label_name_ref, label_name);
    const ret = utils.JS_StackCheck(ctx, @intCast(block_env_len));
    _ = popValue(ctx, &label_name_ref);
    if (ret != 0)
        lexer.js_parse_error_stack_overflow(s);
    const x = cx(ctx);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp - @as(usize, @intCast(block_env_len)));
    const be: *BlockEnv = @ptrCast(@alignCast(x.sp));
    be.prev = s.top_break;
    s.top_break = rt.spToValue(ctx, @ptrCast(be));
    be.label_name = label_name;
    be.label_break = label_break;
    be.label_cont = label_cont;
    be.label_finally = pt.labelNone();
    be.drop_count = vt.newShortInt(drop_count);
    return be;
}

fn pop_break_entry(s: *JSParseState) void {
    const ctx = s.ctx;
    const be = blockEnv(ctx, s.top_break);
    s.top_break = be.prev;
    const x = cx(ctx);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp + @sizeOf(BlockEnv) / @sizeOf(c.JSValue));
    x.stack_bottom = x.sp;
}

fn emit_return(s: *JSParseState, hasval_in: bool, source_pos: u32) void {
    var hasval = hasval_in;
    var drop_count: c_int = 0;
    var top_val = s.top_break;
    while (!mc.isNull(top_val)) {
        const top = blockEnv(s.ctx, top_val);
        drop_count += vt.valueGetInt(top.drop_count);
        if (!label_is_none(top.label_finally)) {
            if (!hasval) {
                emit_op(s, @intCast(OP.undefined));
                hasval = true;
            }
            var i: c_int = 0;
            while (i < drop_count) : (i += 1)
                emit_op(s, @intCast(OP.nip));
            drop_count = 0;
            emit_goto(s, OP.gosub, &top.label_finally);
        }
        top_val = top.prev;
    }
    emit_op_pos(s, @intCast(if (hasval) OP.@"return" else OP.return_undef), source_pos);
}

fn emit_break(s: *JSParseState, label_name: c.JSValue, is_cont: c_int) void {
    var top_val = s.top_break;
    var label_name_ref: c.JSGCRef = undefined;
    while (!mc.isNull(top_val)) {
        const top = blockEnv(s.ctx, top_val);
        const is_labelled_stmt = (top.label_cont == pt.labelNone() and
            vt.valueGetInt(top.drop_count) == 0);
        if ((label_name == c.JS_NULL and !is_labelled_stmt) or
            top.label_name == label_name)
        {
            const plabel = if (is_cont != 0) &top.label_cont else &top.label_break;
            if (!label_is_none(plabel.*)) {
                emit_goto(s, OP.goto, plabel);
                return;
            }
        }
        pushValue(s.ctx, &label_name_ref, label_name);
        var i: c_int = 0;
        while (i < vt.valueGetInt(top.drop_count)) : (i += 1)
            emit_op(s, @intCast(OP.drop));
        if (!label_is_none(top.label_finally)) {
            emit_op(s, @intCast(OP.undefined));
            emit_goto(s, OP.gosub, &top.label_finally);
            emit_op(s, @intCast(OP.drop));
        }
        _ = popValue(s.ctx, &label_name_ref);
        top_val = top.prev;
    }
    if (label_name == c.JS_NULL) {
        if (is_cont != 0)
            lexer.js_parse_error(s, "continue must be inside loop")
        else
            lexer.js_parse_error(s, "break must be inside loop or switch");
    } else {
        lexer.js_parse_error(s, "break/continue label not found");
    }
}

fn define_var(s: *JSParseState, pvar_kind: *c_int, name: c.JSValue) c_int {
    var var_kind: c_int = undefined;
    var var_idx: c_int = undefined;
    if (asBool(s.is_eval)) {
        var_idx = find_ext_var(s, name);
        if (var_idx < 0) {
            var_idx = add_ext_var(s, name, (rt.JS_VARREF_KIND_GLOBAL << 16) | 1);
        } else {
            const b = funcBc(s.cur_func);
            const arr = valueArr(b.ext_vars);
            vt.valueArrayItems(arr)[@intCast(2 * var_idx + 1)] = vt.newShortInt((rt.JS_VARREF_KIND_GLOBAL << 16) | 1);
        }
        var_kind = rt.JS_VARREF_KIND_VAR_REF;
    } else {
        const b = funcBc(s.cur_func);
        const arg_count = rt.bytecodeArgCount(b);
        var_idx = find_var(s, name);
        if (var_idx >= 0) {
            if (var_idx < arg_count) {
                var_kind = rt.JS_VARREF_KIND_ARG;
            } else {
                var_kind = rt.JS_VARREF_KIND_VAR;
                var_idx -= arg_count;
            }
        } else {
            var_idx = add_var(s, name);
            var_kind = rt.JS_VARREF_KIND_VAR;
            var_idx -= arg_count;
        }
    }
    pvar_kind.* = var_kind;
    return var_idx;
}

fn put_var(s: *JSParseState, var_kind: c_int, var_idx: c_int, source_pos: u32) void {
    const opcode: c_int = if (var_kind == rt.JS_VARREF_KIND_ARG)
        OP.put_arg
    else if (var_kind == rt.JS_VARREF_KIND_VAR)
        OP.put_loc
    else
        OP.put_var_ref_nocheck;
    emit_var(s, opcode, var_idx, source_pos);
}

fn js_parse_var(s: *JSParseState, in_accepted: bool) void {
    while (true) {
        const ident_source_pos = s.token.source_pos;
        if (s.token.val != lt.TOK_IDENT)
            lexer.js_parse_error(s, "variable name expected");
        if (s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_arguments))
            lexer.js_parse_error(s, "invalid variable name");
        var var_kind: c_int = undefined;
        const var_idx = define_var(s, &var_kind, s.token.value);
        lexer.next_token(s);
        if (s.token.val == '=') {
            lexer.next_token(s);
            js_parse_assign_expr2(s, if (in_accepted) 0 else pt.PF_NO_IN);
            put_var(s, var_kind, var_idx, ident_source_pos);
        }
        if (s.token.val != ',')
            break;
        lexer.next_token(s);
    }
}

fn set_eval_ret_undefined(s: *JSParseState) void {
    if (s.eval_ret_idx >= 0) {
        emit_op(s, @intCast(OP.undefined));
        emit_var(s, OP.put_loc, s.eval_ret_idx, s.pc2line_source_pos);
    }
}

pub fn js_parse_block(s: *JSParseState, state: c_int, dummy_param: c_int) callconv(.c) c_int {
    _ = dummy_param;
    switch (state) {
        pt.PARSE_STATE_INIT => {
            lexer.js_parse_expect(s, '{');
            if (s.token.val == '}') {
                lexer.next_token(s);
                return pt.PARSE_STATE_RET;
            }
            return parseCall(0, pt.PARSE_FUNC_js_parse_statement, 0);
        },
        0 => {
            if (s.token.val == '}') {
                lexer.next_token(s);
                return pt.PARSE_STATE_RET;
            }
            return parseCall(0, pt.PARSE_FUNC_js_parse_statement, 0);
        },
        else => c_abort(),
    }
}

pub fn js_parse_statement(s: *JSParseState, state: c_int, dummy_param: c_int) callconv(.c) c_int {
    _ = dummy_param;
    var label_name: c.JSValue = c.JS_NULL;
    var label1: c.JSValue = c.JS_UNDEFINED;
    var label2: c.JSValue = c.JS_UNDEFINED;
    var label_next: c.JSValue = c.JS_UNDEFINED;
    var label_test: c.JSValue = c.JS_UNDEFINED;
    var label_case: c.JSValue = c.JS_UNDEFINED;
    var label_catch: c.JSValue = c.JS_UNDEFINED;
    var label_finally: c.JSValue = c.JS_UNDEFINED;
    var label_end: c.JSValue = c.JS_UNDEFINED;
    var label_catch2: c.JSValue = c.JS_UNDEFINED;
    var default_label_pos: c_int = -1;
    var expr3_pos: JSParsePos = .{ .got_lf = 0, .regexp_allowed = 0, .source_pos = 0 };

    sw: switch (state) {
        pt.PARSE_STATE_INIT => {
            if (is_label(s) != 0) {
                label_name = s.token.value;
                var label_name_ref: c.JSGCRef = undefined;
                pushValue(s.ctx, &label_name_ref, label_name);
                lexer.next_token(s);
                lexer.js_parse_expect(s, ':');
                label_name = popValue(s.ctx, &label_name_ref);

                var top_val = s.top_break;
                while (!mc.isNull(top_val)) {
                    const top = blockEnv(s.ctx, top_val);
                    if (top.label_name == label_name)
                        lexer.js_parse_error(s, "duplicate label name");
                    top_val = top.prev;
                }

                if (s.token.val != lt.TOK_FOR and
                    s.token.val != lt.TOK_DO and
                    s.token.val != lt.TOK_WHILE)
                {
                    _ = push_break_entry(s, label_name, new_label(s), pt.labelNone(), 0);
                    return parseCall(11, pt.PARSE_FUNC_js_parse_statement, 0);
                }
            } else {
                label_name = c.JS_NULL;
            }
            continue :sw 200;
        },
        11 => {
            const be = blockEnv(s.ctx, s.top_break);
            emit_label(s, &be.label_break);
            pop_break_entry(s);
            return pt.PARSE_STATE_RET;
        },
        200 => {
            switch (s.token.val) {
                '{' => return parseCall(0, pt.PARSE_FUNC_js_parse_block, 0),
                lt.TOK_RETURN => {
                    if (asBool(s.is_eval))
                        lexer.js_parse_error(s, "return not in a function");
                    const op_source_pos = s.token.source_pos;
                    lexer.next_token(s);
                    var has_val = false;
                    if (s.token.val != ';' and s.token.val != '}' and !asBool(s.got_lf)) {
                        js_parse_expr(s);
                        has_val = true;
                    }
                    emit_return(s, has_val, op_source_pos);
                    lexer.js_parse_expect_semi(s);
                },
                lt.TOK_THROW => {
                    const op_source_pos = s.token.source_pos;
                    lexer.next_token(s);
                    if (asBool(s.got_lf))
                        lexer.js_parse_error(s, "line terminator not allowed after throw");
                    js_parse_expr(s);
                    emit_op_pos(s, @intCast(OP.throw), op_source_pos);
                    lexer.js_parse_expect_semi(s);
                },
                lt.TOK_VAR, lt.TOK_LET, lt.TOK_CONST => {
                    lexer.next_token(s);
                    js_parse_var(s, true);
                    lexer.js_parse_expect_semi(s);
                },
                lt.TOK_IF => {
                    lexer.next_token(s);
                    set_eval_ret_undefined(s);
                    js_parse_expr_paren(s);
                    label1 = new_label(s);
                    emit_goto(s, OP.if_false, &label1);
                    js_parse_push_val(s, label1);
                    return parseCall(1, pt.PARSE_FUNC_js_parse_statement, 0);
                },
                lt.TOK_WHILE => {
                    _ = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
                    lexer.next_token(s);
                    set_eval_ret_undefined(s);
                    const be = blockEnv(s.ctx, s.top_break);
                    emit_label(s, &be.label_cont);
                    js_parse_expr_paren(s);
                    emit_goto(s, OP.if_false, &be.label_break);
                    return parseCall(3, pt.PARSE_FUNC_js_parse_statement, 0);
                },
                lt.TOK_DO => {
                    _ = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
                    label1 = new_label(s);
                    lexer.next_token(s);
                    set_eval_ret_undefined(s);
                    emit_label(s, &label1);
                    js_parse_push_val(s, label1);
                    return parseCall(4, pt.PARSE_FUNC_js_parse_statement, 0);
                },
                lt.TOK_FOR => {
                    const be = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
                    lexer.next_token(s);
                    set_eval_ret_undefined(s);
                    lexer.js_parse_expect1(s, '(');
                    const bits = lexer.js_parse_skip_parens_token(s);
                    lexer.next_token(s);
                    if ((bits & lt.SKIP_HAS_SEMI) == 0) {
                        be.drop_count = vt.newShortInt(1);
                        var label_expr = new_label(s);
                        var label_body = new_label(s);
                        label_next = new_label(s);
                        emit_goto(s, OP.goto, &label_expr);
                        emit_label(s, &label_next);
                        if (is_var_decl_token(s.token.val)) {
                            lexer.next_token(s);
                            var var_kind: c_int = undefined;
                            const var_idx = define_var(s, &var_kind, s.token.value);
                            put_var(s, var_kind, var_idx, s.pc2line_source_pos);
                            lexer.next_token(s);
                        } else {
                            var opcode: c_int = undefined;
                            var var_idx: c_int = undefined;
                            var source_pos: u32 = undefined;
                            js_parse_assign_expr2(s, pt.PF_NO_IN);
                            get_lvalue(s, &opcode, &var_idx, &source_pos, false);
                            put_lvalue(s, opcode, var_idx, source_pos, pt.PUT_LVALUE_NOKEEP_BOTTOM);
                        }
                        emit_goto(s, OP.goto, &label_body);
                        const for_op: c_int = if (s.token.val == lt.TOK_IN)
                            OP.for_in_start
                        else if (s.token.val == lt.TOK_IDENT and
                            s.token.value == utils.js_get_atom(s.ctx, c.JS_ATOM_of))
                            OP.for_of_start
                        else
                            lexer.js_parse_error(s, "expected 'of' or 'in' in for control expression");
                        lexer.next_token(s);
                        emit_label(s, &label_expr);
                        js_parse_expr(s);
                        emit_op(s, @intCast(for_op));
                        emit_goto(s, OP.goto, &be.label_cont);
                        lexer.js_parse_expect(s, ')');
                        emit_label(s, &label_body);
                        js_parse_push_val(s, label_next);
                        return parseCall(5, pt.PARSE_FUNC_js_parse_statement, 0);
                    } else {
                        if (s.token.val != ';') {
                            if (is_var_decl_token(s.token.val)) {
                                lexer.next_token(s);
                                js_parse_var(s, false);
                            } else {
                                js_parse_expr2(s, pt.PF_NO_IN | pt.PF_DROP);
                            }
                        }
                        lexer.js_parse_expect(s, ';');
                        label_test = new_label(s);
                        emit_label(s, &label_test);
                        if (s.token.val != ';') {
                            js_parse_expr(s);
                            emit_goto(s, OP.if_false, &be.label_break);
                        }
                        lexer.js_parse_expect(s, ';');
                        if (s.token.val != ')') {
                            lexer.js_parse_get_pos(s, &expr3_pos);
                            lexer.js_skip_expr(s);
                        } else {
                            expr3_pos.source_pos = @bitCast(@as(i32, -1));
                            expr3_pos.got_lf = 0;
                            expr3_pos.regexp_allowed = 0;
                        }
                        lexer.js_parse_expect(s, ')');
                        js_parse_push_val(s, label_test);
                        parsePushInt(s, expr3_pos.got_lf | (@as(c_int, expr3_pos.regexp_allowed) << 1));
                        parsePushInt(s, @bitCast(expr3_pos.source_pos));
                        return parseCall(6, pt.PARSE_FUNC_js_parse_statement, 0);
                    }
                },
                lt.TOK_BREAK, lt.TOK_CONTINUE => {
                    const is_cont: c_int = @intFromBool(s.token.val == lt.TOK_CONTINUE);
                    lexer.next_token(s);
                    const brk_name: c.JSValue = if (!asBool(s.got_lf) and s.token.val == lt.TOK_IDENT)
                        s.token.value
                    else
                        c.JS_NULL;
                    emit_break(s, brk_name, is_cont);
                    if (brk_name != c.JS_NULL)
                        lexer.next_token(s);
                    lexer.js_parse_expect_semi(s);
                },
                lt.TOK_SWITCH => {
                    _ = push_break_entry(s, label_name, new_label(s), pt.labelNone(), 1);
                    lexer.next_token(s);
                    set_eval_ret_undefined(s);
                    js_parse_expr_paren(s);
                    lexer.js_parse_expect(s, '{');
                    default_label_pos = -1;
                    label_case = pt.labelNone();
                    continue :sw 210;
                },
                lt.TOK_TRY => {
                    set_eval_ret_undefined(s);
                    lexer.next_token(s);
                    label_catch = new_label(s);
                    label_finally = new_label(s);
                    emit_goto(s, OP.@"catch", &label_catch);
                    const be = push_break_entry(s, c.JS_NULL, pt.labelNone(), pt.labelNone(), 1);
                    be.label_finally = label_finally;
                    js_parse_push_val(s, label_catch);
                    return parseCall(8, pt.PARSE_FUNC_js_parse_block, 0);
                },
                ';' => lexer.next_token(s),
                else => {
                    if (s.eval_ret_idx >= 0) {
                        js_parse_expr(s);
                        emit_var(s, OP.put_loc, s.eval_ret_idx, s.pc2line_source_pos);
                    } else {
                        js_parse_expr2(s, pt.PF_DROP);
                    }
                    lexer.js_parse_expect_semi(s);
                },
            }
            return pt.PARSE_STATE_RET;
        },
        0 => return pt.PARSE_STATE_RET,
        1 => {
            label1 = js_parse_pop_val(s);
            if (s.token.val == lt.TOK_ELSE) {
                lexer.next_token(s);
                label2 = new_label(s);
                emit_goto(s, OP.goto, &label2);
                emit_label(s, &label1);
                js_parse_push_val(s, label2);
                return parseCall(2, pt.PARSE_FUNC_js_parse_statement, 0);
            }
            emit_label(s, &label1);
            return pt.PARSE_STATE_RET;
        },
        2 => {
            label2 = js_parse_pop_val(s);
            emit_label(s, &label2);
            return pt.PARSE_STATE_RET;
        },
        3 => {
            const be = blockEnv(s.ctx, s.top_break);
            emit_goto(s, OP.goto, &be.label_cont);
            emit_label(s, &be.label_break);
            pop_break_entry(s);
            return pt.PARSE_STATE_RET;
        },
        4 => {
            label1 = js_parse_pop_val(s);
            const be = blockEnv(s.ctx, s.top_break);
            emit_label(s, &be.label_cont);
            lexer.js_parse_expect(s, lt.TOK_WHILE);
            js_parse_expr_paren(s);
            if (s.token.val == ';')
                lexer.next_token(s);
            emit_goto(s, OP.if_true, &label1);
            emit_label(s, &be.label_break);
            pop_break_entry(s);
            return pt.PARSE_STATE_RET;
        },
        5 => {
            label_next = js_parse_pop_val(s);
            const be = blockEnv(s.ctx, s.top_break);
            emit_label(s, &be.label_cont);
            emit_op(s, @intCast(OP.for_of_next));
            emit_goto(s, OP.if_false, &label_next);
            emit_op(s, @intCast(OP.drop));
            emit_label(s, &be.label_break);
            emit_op(s, @intCast(OP.drop));
            pop_break_entry(s);
            return pt.PARSE_STATE_RET;
        },
        6 => {
            expr3_pos.source_pos = @bitCast(parsePopInt(s));
            const tmp_val = parsePopInt(s);
            expr3_pos.got_lf = @intCast(tmp_val & 1);
            expr3_pos.regexp_allowed = @intCast(tmp_val >> 1);
            label_test = js_parse_pop_val(s);
            var be = blockEnv(s.ctx, s.top_break);
            emit_label(s, &be.label_cont);
            if (expr3_pos.source_pos != @as(u32, @bitCast(@as(i32, -1)))) {
                var end_pos: JSParsePos = undefined;
                lexer.js_parse_get_pos(s, &end_pos);
                lexer.js_parse_seek_token(s, &expr3_pos);
                js_parse_expr2(s, pt.PF_DROP);
                lexer.js_parse_seek_token(s, &end_pos);
            }
            emit_goto(s, OP.goto, &label_test);
            be = blockEnv(s.ctx, s.top_break);
            emit_label(s, &be.label_break);
            pop_break_entry(s);
            return pt.PARSE_STATE_RET;
        },
        7 => {
            default_label_pos = parsePopInt(s);
            label_case = js_parse_pop_val(s);
            continue :sw 210;
        },
        210 => {
            if (s.token.val == '}') {
                lexer.js_parse_expect(s, '}');
                if (default_label_pos >= 0) {
                    emit_label_pos(s, &label_case, default_label_pos);
                } else if (!label_is_none(label_case)) {
                    emit_label(s, &label_case);
                }
                const be = blockEnv(s.ctx, s.top_break);
                emit_label(s, &be.label_break);
                emit_op(s, @intCast(OP.drop));
                pop_break_entry(s);
                return pt.PARSE_STATE_RET;
            }
            if (s.token.val == lt.TOK_CASE) {
                var label1b = pt.labelNone();
                if (!label_is_none(label_case)) {
                    label1b = new_label(s);
                    emit_goto(s, OP.goto, &label1b);
                    emit_label(s, &label_case);
                    label_case = pt.labelNone();
                }
                while (true) {
                    lexer.next_token(s);
                    emit_op(s, @intCast(OP.dup));
                    js_parse_expr(s);
                    lexer.js_parse_expect(s, ':');
                    emit_op(s, @intCast(OP.strict_eq));
                    if (s.token.val == lt.TOK_CASE) {
                        if (label_is_none(label1b))
                            label1b = new_label(s);
                        emit_goto(s, OP.if_true, &label1b);
                    } else {
                        label_case = new_label(s);
                        emit_goto(s, OP.if_false, &label_case);
                        if (!label_is_none(label1b))
                            emit_label(s, &label1b);
                        break;
                    }
                }
                continue :sw 210;
            } else if (s.token.val == lt.TOK_DEFAULT) {
                lexer.next_token(s);
                lexer.js_parse_expect(s, ':');
                if (default_label_pos >= 0)
                    lexer.js_parse_error(s, "duplicate default");
                if (label_is_none(label_case)) {
                    label_case = new_label(s);
                    emit_goto(s, OP.goto, &label_case);
                }
                default_label_pos = @intCast(s.byte_code_len);
                continue :sw 210;
            } else {
                if (label_is_none(label_case))
                    lexer.js_parse_error(s, "invalid switch statement");
                js_parse_push_val(s, label_case);
                parsePushInt(s, default_label_pos);
                return parseCall(7, pt.PARSE_FUNC_js_parse_statement, 0);
            }
        },
        8 => {
            label_catch = js_parse_pop_val(s);
            var be = blockEnv(s.ctx, s.top_break);
            label_finally = be.label_finally;
            pop_break_entry(s);
            emit_op(s, @intCast(OP.drop));
            emit_op(s, @intCast(OP.undefined));
            emit_goto(s, OP.gosub, &label_finally);
            emit_op(s, @intCast(OP.drop));
            label_end = new_label(s);
            emit_goto(s, OP.goto, &label_end);
            if (s.token.val == lt.TOK_CATCH) {
                label_catch2 = new_label(s);
                lexer.next_token(s);
                lexer.js_parse_expect(s, '(');
                if (s.token.val != lt.TOK_IDENT)
                    lexer.js_parse_error(s, "identifier expected");
                const name = s.token.value;
                if (find_var(s, name) >= 0 or find_ext_var(s, name) >= 0)
                    lexer.js_parse_error(s, "catch variable already exists");
                const var_idx = add_var(s, name);
                lexer.next_token(s);
                lexer.js_parse_expect(s, ')');
                emit_label(s, &label_catch);
                {
                    const b = funcBc(s.cur_func);
                    emit_var(s, OP.put_loc, var_idx - rt.bytecodeArgCount(b), s.pc2line_source_pos);
                }
                emit_goto(s, OP.@"catch", &label_catch2);
                be = push_break_entry(s, c.JS_NULL, pt.labelNone(), pt.labelNone(), 1);
                be.label_finally = label_finally;
                js_parse_push_val(s, label_end);
                js_parse_push_val(s, label_catch2);
                return parseCall(9, pt.PARSE_FUNC_js_parse_block, 0);
            } else if (s.token.val == lt.TOK_FINALLY) {
                emit_label(s, &label_catch);
                emit_goto(s, OP.gosub, &label_finally);
                emit_op(s, @intCast(OP.throw));
                continue :sw 220;
            } else {
                lexer.js_parse_error(s, "expecting catch or finally");
            }
        },
        9 => {
            label_catch2 = js_parse_pop_val(s);
            label_end = js_parse_pop_val(s);
            const be = blockEnv(s.ctx, s.top_break);
            label_finally = be.label_finally;
            pop_break_entry(s);
            emit_op(s, @intCast(OP.drop));
            emit_op(s, @intCast(OP.undefined));
            emit_goto(s, OP.gosub, &label_finally);
            emit_op(s, @intCast(OP.drop));
            emit_goto(s, OP.goto, &label_end);
            emit_label(s, &label_catch2);
            emit_goto(s, OP.gosub, &label_finally);
            emit_op(s, @intCast(OP.throw));
            continue :sw 220;
        },
        220 => {
            emit_label(s, &label_finally);
            if (s.token.val == lt.TOK_FINALLY) {
                lexer.next_token(s);
                _ = push_break_entry(s, c.JS_NULL, pt.labelNone(), pt.labelNone(), 2);
                js_parse_push_val(s, label_end);
                return parseCall(10, pt.PARSE_FUNC_js_parse_block, 0);
            }
            emit_op(s, @intCast(OP.ret));
            emit_label(s, &label_end);
            return pt.PARSE_STATE_RET;
        },
        10 => {
            label_end = js_parse_pop_val(s);
            pop_break_entry(s);
            emit_op(s, @intCast(OP.ret));
            emit_label(s, &label_end);
            return pt.PARSE_STATE_RET;
        },
        else => c_abort(),
    }
}
fn js_parse_source_element(s: *JSParseState) void {
    if (s.token.val == lt.TOK_FUNCTION) {
        js_parse_function_decl(s, pt.JS_PARSE_FUNC_STATEMENT, c.JS_NULL);
    } else {
        js_parse_call(s, pt.PARSE_FUNC_js_parse_statement, 0);
    }
}

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

fn js_parse_function_decl(s: *JSParseState, func_type: c_int, func_name_in: c.JSValue) void {
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
            pushValue(ctx, &func_name_ref, func_name);
            lexer.next_token(s);
            func_name = popValue(ctx, &func_name_ref);
        }
    }

    pushValue(ctx, &func_name_ref, func_name);
    const b0 = js_alloc_function_bytecode(s.ctx) orelse lexer.js_parse_error_mem(s);
    const bfunc = mc.valueFromPtr(b0);
    pushValue(ctx, &bfunc_ref, bfunc);

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
        idx = define_var(s, &var_kind, func_name_ref.val);
        s.hoisted_code_len += 3 + 3;
        if (var_kind == rt.JS_VARREF_KIND_VAR) {
            const cur = funcBc(s.cur_func);
            idx += rt.bytecodeArgCount(cur);
        }
        b = funcBc(bfunc_ref.val);
        pt.bytecodeSetArgCount(b, idx + 1);
    }
    _ = popValue(ctx, &bfunc_ref);
    _ = popValue(ctx, &func_name_ref);
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
    put_var(s, rt.JS_VARREF_KIND_ARG, arg_idx, source_pos);
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
        put_var(s, rt.JS_VARREF_KIND_VAR, var_idx - @as(c_int, @intCast(arg_count)), s.pc2line_source_pos);
    }
    b = funcBc(s.cur_func);
    if (pt.bytecodeHasLocalFuncName(b)) {
        const var_idx = add_var(s, b.func_name);
        emit_op(s, @intCast(OP.this_func));
        put_var(s, rt.JS_VARREF_KIND_VAR, var_idx - @as(c_int, @intCast(arg_count)), s.pc2line_source_pos);
    }
    while (s.token.val != '}') {
        js_parse_source_element(s);
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
        js_parse_source_element(s);
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
                const var_idx: c_int = @intCast(get_u16(byte_code + @as(usize, @intCast(pos + 1))));
                if (var_idx >= var_start and var_idx < var_end) {
                    const j = var_idx - var_start;
                    put_u16(byte_code + @as(usize, @intCast(pos + 1)), cvt_tab[@intCast(j)].new_var_idx);
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
    pushValue(ctx, &explore_arr_val_ref, explore_arr_val);
    const stack_top: [*]c.JSValue = @ptrCast(cx(ctx).sp);
    compute_stack_size_push(s, arr, explore_tab, 0, 0);
    while (@intFromPtr(cx(ctx).sp) < @intFromPtr(stack_top)) {
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
            n_pop += @intCast(get_u16(vt.byteArrayBuf(arr) + pos));
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
            @as(u8, @intCast(OP.goto)) => pos +%= get_u32(vt.byteArrayBuf(arr) + pos),
            @as(u8, @intCast(OP.if_true)), @as(u8, @intCast(OP.if_false)) => {
                const pos1 = pos +% get_u32(vt.byteArrayBuf(arr) + pos);
                compute_stack_size_push(s, arr, explore_tab, pos1, stack_len);
                pos += @as(u32, @intCast(op_len - 1));
            },
            @as(u8, @intCast(OP.gosub)) => {
                const pos1 = pos +% get_u32(vt.byteArrayBuf(arr) + pos);
                compute_stack_size_push(s, arr, explore_tab, pos1, stack_len + 1);
                pos += @as(u32, @intCast(op_len - 1));
            },
            else => pos += @as(u32, @intCast(op_len - 1)),
        }
        if (!skip_push)
            compute_stack_size_push(s, arr, explore_tab, pos, stack_len);
    }
    explore_arr_val = popValue(ctx, &explore_arr_val_ref);
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
    const x = cx(ctx);
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
            const b = funcBc(pf.*);
            convert_ext_vars_to_local_vars(s);
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
                const func = vt.valueArrayItems(cpool2)[@intCast(cpool_pos)];
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
                pushValue(ctx, &func_ref, func);
                js_parse_function(s);
                const err = utils.JS_StackCheck(ctx, 3);
                _ = popValue(ctx, &func_ref);
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
            val2 = value.JS_SetPropertyUint32(ctx, cx(ctx).sp.*, idx, val2);
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
            val2 = value.JS_DefinePropertyValue(ctx, cx(ctx).sp.*, prop, val2);
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
    cx(ctx).parse_state = s;
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
    const saved_top_gc_ref = cx(ctx).top_gc_ref;
    const saved_sp = cx(ctx).sp;

    if (setjmp(@ptrCast(&s.jmp_env)) != 0) {
        cx(ctx).parse_state = null;
        cx(ctx).top_gc_ref = saved_top_gc_ref;
        cx(ctx).sp = saved_sp;
        cx(ctx).stack_bottom = cx(ctx).sp;
        var col_num: c_int = 0;
        const line_num = lexer.get_line_col(&col_num, s.source_buf, if ((eval_flags & (c.JS_EVAL_JSON | c.JS_EVAL_REGEXP)) != 0)
            s.buf_pos
        else
            s.token.source_pos);
        const val = utils.JS_ThrowError(ctx, c.JS_CLASS_SYNTAX_ERROR, "%s", @as([*:0]const u8, @ptrCast(&s.error_msg)));
        runtime.build_backtrace(ctx, cx(ctx).current_exception, filename, line_num + 1, col_num + 1, 0);
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
        pushValue(ctx, &top_func_ref, top_func);
        js_parse_program(s);
        js_parse_local_functions(s, &top_func_ref.val);
        top_func = popValue(ctx, &top_func_ref);
    }
    cx(ctx).parse_state = null;
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
    pushValue(ctx, &val_ref, val);
    const err = utils.JS_StackCheck(ctx, 2);
    val = popValue(ctx, &val_ref);
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
