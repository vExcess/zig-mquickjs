//
// Micro QuickJS engine parser — bytecode emit helpers (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const platform_abort = @import("platform_abort.zig");
const utils = @import("mquickjs_utils_lib.zig");
const pt = @import("mquickjs_parser_types.zig");
const lt = pt.lt;
const rt = pt.rt;
const vt = pt.vt;
const mc = pt.mc;
pub const c = pt.c;

const JSParseState = pt.JSParseState;
const OP = rt.OP;

const lexer = @import("mquickjs_lexer_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");

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

fn c_abort() noreturn {
    platform_abort.abort();
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

pub fn is_label(s: *JSParseState) c.JS_BOOL {
    return @intFromBool(s.token.val == lt.TOK_IDENT and s.source_buf[s.buf_pos] == ':');
}
pub fn get_byte_code(s: *JSParseState) [*]u8 {
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
    mc.put_u16(vt.byteArrayBuf(arr) + s.byte_code_len, val);
    s.byte_code_len += 2;
}

pub fn emit_u32(s: *JSParseState, val: u32) void {
    emit_claim_size(s, 4);
    const arr = byteArr(s.byte_code);
    mc.put_u32(vt.byteArrayBuf(arr) + s.byte_code_len, val);
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

pub fn get_prev_opcode(s: *JSParseState) c_int {
    if (s.last_opcode_pos < 0) {
        return OP.invalid;
    } else {
        return get_byte_code(s)[@intCast(s.last_opcode_pos)];
    }
}

pub fn js_is_live_code(s: *JSParseState) bool {
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

pub fn label_is_none(label: c.JSValue) bool {
    return vt.valueGetInt(label) < 0;
}

pub fn new_label(s: *JSParseState) c.JSValue {
    _ = s;
    return vt.newShortInt(pt.LABEL_OFFSET_MASK);
}

pub fn emit_label_pos(s: *JSParseState, plabel: *c.JSValue, pos: c_int) void {
    var label = vt.valueGetInt(plabel.*);
    std.debug.assert(label & pt.LABEL_RESOLVED_FLAG == 0);
    const arr = byteArr(s.byte_code);
    const buf = vt.byteArrayBuf(arr);
    while (label != pt.LABEL_OFFSET_MASK) {
        const next = @as(c_int, @bitCast(mc.get_u32(buf + @as(usize, @intCast(label)))));
        mc.put_u32(buf + @as(usize, @intCast(label)), @bitCast(pos - label));
        label = next;
    }
    plabel.* = vt.newShortInt(pos | pt.LABEL_RESOLVED_FLAG);
}

pub fn emit_label(s: *JSParseState, plabel: *c.JSValue) void {
    emit_label_pos(s, plabel, @intCast(s.byte_code_len));
    s.last_opcode_pos = -1;
}

pub fn emit_goto(s: *JSParseState, opcode: c_int, plabel: *c.JSValue) void {
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
    var val_kept = val;
    var b = funcBc(s.cur_func);
    var arr = valueArr(b.cpool);
    var i: c_int = 0;
    while (i < s.cpool_len) : (i += 1) {
        if (vt.valueArrayItems(arr)[@intCast(i)] == val_kept)
            return i;
    }
    if (s.cpool_len > 65535)
        lexer.js_parse_error(s, "too many constants");
    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(s.ctx, &val_ref, val_kept);
    const new_cpool = value.js_resize_value_array(s.ctx, b.cpool, max_int(s.cpool_len + 1, 4));
    val_kept = utils.popValue(s.ctx, &val_ref);
    if (vt.isExactException(new_cpool))
        lexer.js_parse_error_mem(s);
    b = funcBc(s.cur_func);
    b.cpool = new_cpool;
    arr = valueArr(b.cpool);
    vt.valueArrayItems(arr)[s.cpool_len] = val_kept;
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
    var func_kept = func;
    var name_kept = name;
    var b = funcBc(func_kept);
    if (b.ext_vars_len >= pt.JS_MAX_LOCAL_VARS)
        lexer.js_parse_error(s, "too many variable references");
    var func_ref: c.JSGCRef = undefined;
    var name_ref: c.JSGCRef = undefined;
    utils.pushValue(s.ctx, &func_ref, func_kept);
    utils.pushValue(s.ctx, &name_ref, name_kept);
    const new_ext_vars = value.js_resize_value_array(s.ctx, b.ext_vars, max_int(b.ext_vars_len + 1, 2) * 2);
    name_kept = utils.popValue(s.ctx, &name_ref);
    func_kept = utils.popValue(s.ctx, &func_ref);
    if (vt.isExactException(new_ext_vars))
        lexer.js_parse_error_mem(s);
    b = funcBc(func_kept);
    b.ext_vars = new_ext_vars;
    const arr = valueArr(b.ext_vars);
    const items = vt.valueArrayItems(arr);
    items[@intCast(2 * b.ext_vars_len)] = name_kept;
    items[@intCast(2 * b.ext_vars_len + 1)] = vt.newShortInt(decl);
    b.ext_vars_len += 1;
    return b.ext_vars_len - 1;
}

pub fn add_ext_var(s: *JSParseState, name: c.JSValue, decl: c_int) c_int {
    return add_func_ext_var(s, s.cur_func, name, decl);
}

pub fn add_var(s: *JSParseState, name: c.JSValue) c_int {
    var name_kept = name;
    var b = funcBc(s.cur_func);
    if (s.local_vars_len >= pt.JS_MAX_LOCAL_VARS)
        lexer.js_parse_error(s, "too many local variables");
    var name_ref: c.JSGCRef = undefined;
    utils.pushValue(s.ctx, &name_ref, name_kept);
    const new_vars = value.js_resize_value_array(s.ctx, b.vars, max_int(s.local_vars_len + 1, 4));
    name_kept = utils.popValue(s.ctx, &name_ref);
    if (vt.isExactException(new_vars))
        lexer.js_parse_error_mem(s);
    b = funcBc(s.cur_func);
    b.vars = new_vars;
    const arr = valueArr(b.vars);
    vt.valueArrayItems(arr)[s.local_vars_len] = name_kept;
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
            var_idx = mc.get_u8(get_byte_code(s) + @as(usize, @intCast(s.last_opcode_pos + 1)));
            opcode = OP.get_loc;
        },
        OP.get_loc, OP.get_arg, OP.get_var_ref, OP.get_field => {
            var_idx = @intCast(mc.get_u16(get_byte_code(s) + @as(usize, @intCast(s.last_opcode_pos + 1))));
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
        utils.pushValue(ctx, &name_ref, name);
        lexer.next_token(s);
        name = utils.popValue(ctx, &name_ref);
    }
    if (prop_type == pt.PARSE_PROP_FIELD and s.token.val == '(')
        prop_type = pt.PARSE_PROP_METHOD;
    pname.* = name;
    return prop_type;
}

pub fn parse_stack_alloc(s: *JSParseState, val_in: c.JSValue) c.JSValue {
    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(s.ctx, &val_ref, val_in);
    if (utils.JS_StackCheck(s.ctx, 1) != 0)
        lexer.js_parse_error_stack_overflow(s);
    return utils.popValue(s.ctx, &val_ref);
}

pub fn js_parse_push_val(s: *JSParseState, val_in: c.JSValue) void {
    const ctx = s.ctx;
    var val = val_in;
    if (@intFromPtr(mc.ctxExt(ctx).sp) <= @intFromPtr(mc.ctxExt(ctx).stack_bottom)) {
        val = parse_stack_alloc(s, val);
    }
    const x = mc.ctxExt(ctx);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp - 1);
    x.sp.* = val;
}

pub fn js_parse_pop_val(s: *JSParseState) c.JSValue {
    const x = mc.ctxExt(s.ctx);
    const val = x.sp.*;
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp + 1);
    const slack = @as([*]c.JSValue, @ptrCast(x.sp)) - pt.JS_STACK_SLACK;
    if (@intFromPtr(slack) > @intFromPtr(x.stack_bottom))
        x.stack_bottom = @ptrCast(slack);
    return val;
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
