//
// Micro QuickJS engine parser — expression parser (internal submodule)
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
const OP = rt.OP;

const lexer = @import("mquickjs_lexer_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const emit = @import("mquickjs_parser_emit_lib.zig");
const parser = @import("mquickjs_parser_lib.zig");

const min_int = cutils.min_int;

const js_parse_call = parser.js_parse_call;
const js_parse_function_decl = parser.js_parse_function_decl;

fn max_int(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn parseCall(cur_state: c_int, func: c_int, param: c_int) c_int {
    return cur_state | (func << 8) | (param << 16);
}

fn parsePushInt(s: *JSParseState, v: c_int) void {
    emit.js_parse_push_val(s, vt.newShortInt(v));
}

fn parsePopInt(s: *JSParseState) c_int {
    return vt.valueGetInt(emit.js_parse_pop_val(s));
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

const emit_op = emit.emit_op;
const emit_op_pos = emit.emit_op_pos;
const emit_op_param = emit.emit_op_param;
const emit_u8 = emit.emit_u8;
const emit_u16 = emit.emit_u16;
const emit_u32 = emit.emit_u32;
const emit_var = emit.emit_var;
const emit_push_short_int = emit.emit_push_short_int;
const remove_last_op = emit.remove_last_op;
const js_emit_push_const = emit.js_emit_push_const;
const js_emit_push_number = emit.js_emit_push_number;
const js_parse_push_val = emit.js_parse_push_val;
const js_parse_pop_val = emit.js_parse_pop_val;
const find_var = emit.find_var;
const find_ext_var = emit.find_ext_var;
const add_ext_var = emit.add_ext_var;
const cpool_add = emit.cpool_add;
const get_byte_code = emit.get_byte_code;
const get_prev_opcode = emit.get_prev_opcode;
const get_lvalue = emit.get_lvalue;
const put_lvalue = emit.put_lvalue;
const may_drop_result = emit.may_drop_result;
const js_parse_property_name = emit.js_parse_property_name;
const new_label = emit.new_label;
const emit_label = emit.emit_label;
const emit_goto = emit.emit_goto;

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
                const count = mc.get_u16(byte_code + @as(usize, @intCast(count_pos)));
                mc.put_u16(byte_code + @as(usize, @intCast(count_pos)), @intCast(min_int(@intCast(count + 1), 0xffff)));
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
            const prop_idx = mc.get_u16(vt.byteArrayBuf(arr) + @as(usize, @intCast(s.last_opcode_pos + 1)));
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
