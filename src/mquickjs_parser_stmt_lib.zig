//
// Micro QuickJS engine parser — statement parser (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
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
const emit = @import("mquickjs_parser_emit_lib.zig");
const parser = @import("mquickjs_parser_lib.zig");

const js_parse_call = parser.js_parse_call;
const js_parse_function_decl = parser.js_parse_function_decl;
const js_parse_expr = parser.js_parse_expr;
const js_parse_assign_expr2 = parser.js_parse_assign_expr2;
const js_parse_expr_paren = parser.js_parse_expr_paren;
const js_parse_expr2 = parser.js_parse_expr2;

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

fn valueArr(val: c.JSValue) *vt.JSValueArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn blockEnv(ctx: *c.JSContext, val: c.JSValue) *BlockEnv {
    return @ptrCast(@alignCast(rt.valueToSp(ctx, val)));
}

fn is_var_decl_token(tok: c_int) bool {
    return tok == lt.TOK_VAR or tok == lt.TOK_LET or tok == lt.TOK_CONST;
}

const is_label = emit.is_label;
const emit_op = emit.emit_op;
const emit_op_pos = emit.emit_op_pos;
const emit_var = emit.emit_var;
const emit_label = emit.emit_label;
const emit_label_pos = emit.emit_label_pos;
const emit_goto = emit.emit_goto;
const label_is_none = emit.label_is_none;
const new_label = emit.new_label;
const find_var = emit.find_var;
const find_ext_var = emit.find_ext_var;
const add_ext_var = emit.add_ext_var;
const add_var = emit.add_var;
const get_lvalue = emit.get_lvalue;
const put_lvalue = emit.put_lvalue;
const js_parse_push_val = emit.js_parse_push_val;
const js_parse_pop_val = emit.js_parse_pop_val;

fn push_break_entry(s: *JSParseState, label_name_in: c.JSValue, label_break: c.JSValue, label_cont: c.JSValue, drop_count: c_int) *BlockEnv {
    const ctx = s.ctx;
    var label_name = label_name_in;
    const block_env_len = @as(c_int, @intCast(@sizeOf(BlockEnv) / @sizeOf(c.JSValue)));
    var label_name_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &label_name_ref, label_name);
    const ret = utils.JS_StackCheck(ctx, @intCast(block_env_len));
    // C JS_POP_VALUE assigns back. StackCheck may GC; the interned label
    // is then stored on the JS stack (pointer equality for break/continue).
    label_name = utils.popValue(ctx, &label_name_ref);
    if (ret != 0)
        lexer.js_parse_error_stack_overflow(s);
    const x = mc.ctxExt(ctx);
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
    const x = mc.ctxExt(ctx);
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

fn emit_break(s: *JSParseState, label_name_in: c.JSValue, is_cont: c_int) void {
    var label_name = label_name_in;
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
        utils.pushValue(s.ctx, &label_name_ref, label_name);
        var i: c_int = 0;
        while (i < vt.valueGetInt(top.drop_count)) : (i += 1)
            emit_op(s, @intCast(OP.drop));
        if (!label_is_none(top.label_finally)) {
            emit_op(s, @intCast(OP.undefined));
            emit_goto(s, OP.gosub, &top.label_finally);
            emit_op(s, @intCast(OP.drop));
        }
        label_name = utils.popValue(s.ctx, &label_name_ref);
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

pub fn define_var(s: *JSParseState, pvar_kind: *c_int, name: c.JSValue) c_int {
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

pub fn put_var(s: *JSParseState, var_kind: c_int, var_idx: c_int, source_pos: u32) void {
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
                utils.pushValue(s.ctx, &label_name_ref, label_name);
                lexer.next_token(s);
                lexer.js_parse_expect(s, ':');
                label_name = utils.popValue(s.ctx, &label_name_ref);

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
pub fn js_parse_source_element(s: *JSParseState) void {
    if (s.token.val == lt.TOK_FUNCTION) {
        js_parse_function_decl(s, pt.JS_PARSE_FUNC_STATEMENT, c.JS_NULL);
    } else {
        js_parse_call(s, pt.PARSE_FUNC_js_parse_statement, 0);
    }
}
