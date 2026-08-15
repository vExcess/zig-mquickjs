//
// Micro QuickJS engine runtime — JS_Call VM interpreter (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const utils = @import("mquickjs_utils_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const rt = @import("mquickjs_runtime_types.zig");
const vt = rt.vt;
const mc = vt.mc;
pub const c = rt.c;

const coerce = @import("mquickjs_runtime_coerce_lib.zig");

const OP = rt.OP;

fn jsGetShortFloat(v: c.JSValue) f64 {
    return @call(.never_inline, value.js_get_short_float, .{v});
}

fn max_int(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn throwTypeError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn throwInternalError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, msg);
}

fn get_i16(pc: [*]const u8) i32 {
    return @as(*align(1) const i16, @ptrCast(pc)).*;
}

fn get_i8(pc: [*]const u8) i32 {
    return @as(*const i8, @ptrCast(pc)).*;
}

fn c_abort() noreturn {
    std.posix.abort();
}

const Resume = enum {
    function_call,
    generic_function_call,
    dispatch,
    exception,
    generic_return,
    return_call,
    call_exception,
    binary_arith_slow,
    unary_arith_slow,
    binary_logic_slow,
    add_slow,
    float_result,
    done,
    get_field,
    get_length,
    get_array_el,
};

fn memmoveValues(dest: [*]c.JSValue, src: [*]c.JSValue, n: usize) void {
    if (n == 0 or @intFromPtr(dest) == @intFromPtr(src)) return;
    if (@intFromPtr(dest) < @intFromPtr(src)) {
        var i: usize = 0;
        while (i < n) : (i += 1) dest[i] = src[i];
    } else {
        var i = n;
        while (i > 0) {
            i -= 1;
            dest[i] = src[i];
        }
    }
}

fn ptrAddI32(p: [*]u8, diff: i32) [*]u8 {
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, @bitCast(@intFromPtr(p))) + @as(isize, diff))));
}

fn saveFrame(ctx: *c.JSContext, fp: [*]c.JSValue, sp: [*]c.JSValue, pc: [*]u8, b: *rt.JSFunctionBytecodeExt) void {
    const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.byte_code)));
    const off: i32 = @intCast(@intFromPtr(pc) - @intFromPtr(vt.byteArrayBuf(byte_code)));
    rt.slot(fp, rt.FRAME_OFFSET_CUR_PC).* = vt.newShortInt(off);
    mc.ctxExt(ctx).sp = @ptrCast(sp);
    mc.ctxExt(ctx).fp = @ptrCast(fp);
}

fn restorePc(fp: [*]c.JSValue) struct { b: *rt.JSFunctionBytecodeExt, pc: [*]u8 } {
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*)));
    const b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.closure.func_bytecode)));
    const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.byte_code)));
    const off = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CUR_PC).*);
    return .{ .b = b, .pc = vt.byteArrayBuf(byte_code) + @as(usize, @intCast(off)) };
}
pub fn JS_Call(ctx: *c.JSContext, call_flags_in: c_int) c.JSValue {
    var call_flags = call_flags_in;
    var fp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).fp);
    var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    var val: c.JSValue = c.JS_UNDEFINED;
    const initial_fp: [*]c.JSValue = fp;
    var pc: [*]u8 = undefined;
    var has_pc = false;
    var opcode: c_int = OP.invalid;
    var i: c_int = 0;
    var b: ?*rt.JSFunctionBytecodeExt = null;
    var dr: f64 = 0;
    var short_func_idx: c_int = 0;
    var p: ?*mc.JSObjectExt = null;
    var n: c_int = 0;
    var argc: c_int = 0;
    var pushed_argc: c_int = 0;
    var func_obj: c.JSValue = c.JS_UNDEFINED;
    var state: Resume = .function_call;

    if (mc.ctxExt(ctx).js_call_rec_count >= rt.JS_MAX_CALL_RECURSE)
        return throwInternalError(ctx, "C stack overflow");
    mc.ctxExt(ctx).js_call_rec_count += 1;

    outer: while (true) {
        switch (state) {
            .done => break :outer,
            .get_field, .get_length, .get_array_el => unreachable,
            .float_result => {
                if (@abs(dr) >= 0x1p-127 and @abs(dr) <= 0x1p+128) {
                    val = value.js_to_short_float(dr);
                } else if (dr == 0.0) {
                    const bits: u64 = @bitCast(dr);
                    if (bits != 0) {
                        val = mc.ctxExt(ctx).minus_zero;
                    } else {
                        val = vt.newShortInt(0);
                    }
                } else {
                    saveFrame(ctx, fp, sp, pc, b.?);
                    val = value.js_alloc_float64(ctx, dr);
                    const restored = restorePc(fp);
                    b = restored.b;
                    pc = restored.pc;
                    if (vt.isExactException(val)) {
                        state = .exception;
                        continue :outer;
                    }
                }
                sp[0] = val;
                state = .dispatch;
                continue :outer;
            },
            .add_slow => {
                saveFrame(ctx, fp, sp, pc, b.?);
                val = coerce.js_add_slow(ctx);
                const restored = restorePc(fp);
                b = restored.b;
                pc = restored.pc;
                if (vt.isExactException(val)) {
                    state = .exception;
                    continue :outer;
                }
                sp[1] = val;
                sp += 1;
                state = .dispatch;
                continue :outer;
            },
            .binary_arith_slow => {
                saveFrame(ctx, fp, sp, pc, b.?);
                val = coerce.js_binary_arith_slow(ctx, opcode);
                const restored = restorePc(fp);
                b = restored.b;
                pc = restored.pc;
                if (vt.isExactException(val)) {
                    state = .exception;
                    continue :outer;
                }
                sp[1] = val;
                sp += 1;
                state = .dispatch;
                continue :outer;
            },
            .unary_arith_slow => {
                saveFrame(ctx, fp, sp, pc, b.?);
                val = coerce.js_unary_arith_slow(ctx, opcode);
                const restored = restorePc(fp);
                b = restored.b;
                pc = restored.pc;
                if (vt.isExactException(val)) {
                    state = .exception;
                    continue :outer;
                }
                sp[0] = val;
                state = .dispatch;
                continue :outer;
            },
            .binary_logic_slow => {
                saveFrame(ctx, fp, sp, pc, b.?);
                val = coerce.js_binary_logic_slow(ctx, opcode);
                const restored = restorePc(fp);
                b = restored.b;
                pc = restored.pc;
                if (vt.isExactException(val)) {
                    state = .exception;
                    continue :outer;
                }
                sp[1] = val;
                sp += 1;
                state = .dispatch;
                continue :outer;
            },
            .generic_function_call => {
                mc.ctxExt(ctx).interrupt_counter -= 1;
                if (mc.ctxExt(ctx).interrupt_counter <= 0) {
                    saveFrame(ctx, fp, sp, pc, b.?);
                    val = coerce.__js_poll_interrupt(ctx);
                    const restored = restorePc(fp);
                    b = restored.b;
                    pc = restored.pc;
                    if (vt.isExactException(val)) {
                        state = .exception;
                        continue :outer;
                    }
                }
                const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                const off: i32 = @intCast(@intFromPtr(pc) - @intFromPtr(vt.byteArrayBuf(byte_code)));
                rt.slot(fp, rt.FRAME_OFFSET_CUR_PC).* = vt.newShortInt(off);
                state = .function_call;
                continue :outer;
            },
            .function_call => {
                sp -= 1;
                sp[0] = vt.newShortInt(call_flags);
                sp -= 1;
                sp[0] = rt.spToValue(ctx, fp);

                func_obj = rt.slot(sp, rt.FRAME_OFFSET_FUNC_OBJ).*;
                if (!mc.isPtr(func_obj)) {
                    if (rt.valueGetSpecialTag(func_obj) != c.JS_TAG_SHORT_FUNC) {
                        sp += 2;
                        mc.ctxExt(ctx).sp = @ptrCast(sp);
                        mc.ctxExt(ctx).fp = @ptrCast(fp);
                        val = throwTypeError(ctx, "not a function");
                        state = .call_exception;
                        continue :outer;
                    }
                    short_func_idx = rt.valueGetSpecialValue(func_obj);
                    p = null;
                } else {
                    p = @ptrCast(@alignCast(mc.valueToPtr(func_obj)));
                    if (mc.mbGetMtag(p.?) != mc.JS_MTAG_OBJECT) {
                        sp += 2;
                        mc.ctxExt(ctx).sp = @ptrCast(sp);
                        mc.ctxExt(ctx).fp = @ptrCast(fp);
                        val = throwTypeError(ctx, "not a function");
                        state = .call_exception;
                        continue :outer;
                    }
                    if (mc.objectClassId(p.?) != c.JS_CLASS_C_FUNCTION and mc.objectClassId(p.?) != c.JS_CLASS_CLOSURE) {
                        sp += 2;
                        mc.ctxExt(ctx).sp = @ptrCast(sp);
                        mc.ctxExt(ctx).fp = @ptrCast(fp);
                        val = throwTypeError(ctx, "not a function");
                        state = .call_exception;
                        continue :outer;
                    }
                    if (mc.objectClassId(p.?) == c.JS_CLASS_C_FUNCTION)
                        short_func_idx = @intCast(p.?.u.cfunc.idx);
                }

                if (p == null or mc.objectClassId(p.?) == c.JS_CLASS_C_FUNCTION) {
                    const fd = &vt.cFunctionTable(mc.ctxExt(ctx))[@intCast(short_func_idx)];
                    call_flags = vt.valueGetInt(rt.slot(sp, rt.FRAME_OFFSET_CALL_FLAGS).*);
                    if ((call_flags & rt.FRAME_CF_CTOR) != 0 and
                        fd.def_type != c.JS_CFUNC_constructor and
                        fd.def_type != c.JS_CFUNC_constructor_magic)
                    {
                        sp += 2;
                        mc.ctxExt(ctx).sp = @ptrCast(sp);
                        mc.ctxExt(ctx).fp = @ptrCast(fp);
                        val = throwTypeError(ctx, "not a constructor");
                        state = .call_exception;
                        continue :outer;
                    }
                    argc = call_flags & rt.FRAME_CF_ARGC_MASK;
                    mc.ctxExt(ctx).sp = @ptrCast(sp);
                    mc.ctxExt(ctx).fp = @ptrCast(fp);
                    n = utils.JS_StackCheck(ctx, @intCast(max_int(fd.arg_count - argc, 0)));
                    if (n != 0) {
                        sp += 2;
                        val = c.JS_EXCEPTION;
                        state = .call_exception;
                        continue :outer;
                    }
                    pushed_argc = argc;
                    if (fd.arg_count > argc) {
                        n = fd.arg_count - argc;
                        sp -= @as(usize, @intCast(n));
                        i = 0;
                        while (i < rt.FRAME_OFFSET_ARG0 + argc) : (i += 1) {
                            sp[@intCast(i)] = sp[@intCast(i + n)];
                        }
                        i = 0;
                        while (i < n) : (i += 1) {
                            rt.slot(sp, rt.FRAME_OFFSET_ARG0 + argc + i).* = c.JS_UNDEFINED;
                        }
                        pushed_argc = fd.arg_count;
                    }
                    fp = sp;
                    mc.ctxExt(ctx).sp = @ptrCast(sp);
                    mc.ctxExt(ctx).fp = @ptrCast(fp);
                    const argv: [*]c.JSValue = @ptrCast(rt.slot(fp, rt.FRAME_OFFSET_ARG0));
                    const this_ptr = rt.slot(fp, rt.FRAME_OFFSET_THIS_OBJ);
                    const argc_flags = call_flags & (rt.FRAME_CF_CTOR | rt.FRAME_CF_ARGC_MASK);
                    switch (fd.def_type) {
                        c.JS_CFUNC_generic, c.JS_CFUNC_constructor => {
                            const fn_ptr: rt.JSCFunctionGeneric = @ptrCast(fd.func.?);
                            val = fn_ptr(ctx, this_ptr, argc_flags, argv);
                        },
                        c.JS_CFUNC_generic_magic, c.JS_CFUNC_constructor_magic => {
                            const fn_ptr: rt.JSCFunctionGenericMagic = @ptrCast(fd.func.?);
                            val = fn_ptr(ctx, this_ptr, argc_flags, argv, fd.magic);
                        },
                        c.JS_CFUNC_generic_params => {
                            const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*)));
                            const fn_ptr: rt.JSCFunctionGenericParams = @ptrCast(fd.func.?);
                            val = fn_ptr(ctx, this_ptr, argc_flags, argv, po.u.cfunc.params);
                        },
                        c.JS_CFUNC_f_f => {
                            var d: f64 = undefined;
                            if (coerce.JS_ToNumber(ctx, &d, rt.slot(fp, rt.FRAME_OFFSET_ARG0).*) != 0) {
                                val = c.JS_EXCEPTION;
                            } else {
                                const fn_ptr: rt.JSCFunctionFF = @ptrCast(fd.func.?);
                                d = fn_ptr(d);
                                val = value.JS_NewFloat64(ctx, d);
                            }
                        },
                        else => c_abort(),
                    }
                    if (rt.isExceptionOrTailCall(val) and rt.valueGetSpecialValue(val) >= c.JS_EX_CALL) {
                        call_flags = rt.valueGetSpecialValue(val) - c.JS_EX_CALL;
                        sp = @ptrCast(mc.ctxExt(ctx).sp);
                        const fp1 = rt.valueToSp(ctx, rt.slot(fp, rt.FRAME_OFFSET_SAVED_FP).*);
                        argc = (call_flags & rt.FRAME_CF_ARGC_MASK) + 2;
                        const sp1: [*]c.JSValue = @ptrCast(rt.slot(fp, rt.FRAME_OFFSET_ARG0 + pushed_argc - argc));
                        memmoveValues(sp1, sp, @intCast(argc));
                        sp = sp1;
                        fp = fp1;
                        state = .function_call;
                        continue :outer;
                    } else {
                        sp = @ptrCast(rt.slot(fp, rt.FRAME_OFFSET_ARG0 + pushed_argc));
                        state = .return_call;
                        continue :outer;
                    }
                } else {
                    call_flags = vt.valueGetInt(rt.slot(sp, rt.FRAME_OFFSET_CALL_FLAGS).*);
                    if ((call_flags & rt.FRAME_CF_CTOR) != 0) {
                        mc.ctxExt(ctx).sp = @ptrCast(sp);
                        mc.ctxExt(ctx).fp = @ptrCast(fp);
                        val = coerce.js_call_constructor_start(ctx, func_obj);
                        if (vt.isExactException(val)) {
                            state = .call_exception;
                            continue :outer;
                        }
                        rt.slot(sp, rt.FRAME_OFFSET_THIS_OBJ).* = val;
                        func_obj = rt.slot(sp, rt.FRAME_OFFSET_FUNC_OBJ).*;
                        p = @ptrCast(@alignCast(mc.valueToPtr(func_obj)));
                    }
                    b = @ptrCast(@alignCast(mc.valueToPtr(p.?.u.closure.func_bytecode)));
                    var n_vars: c_int = 0;
                    if (b.?.vars != c.JS_NULL) {
                        const vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.vars)));
                        n_vars = vt.valueArraySize(vars) - rt.bytecodeArgCount(b.?);
                    }
                    argc = call_flags & rt.FRAME_CF_ARGC_MASK;
                    mc.ctxExt(ctx).sp = @ptrCast(sp);
                    mc.ctxExt(ctx).fp = @ptrCast(fp);
                    n = utils.JS_StackCheck(ctx, @intCast(max_int(rt.bytecodeArgCount(b.?) - argc, 0) + 2 + n_vars + @as(c_int, b.?.stack_size)));
                    if (n != 0) {
                        val = c.JS_EXCEPTION;
                        state = .call_exception;
                        continue :outer;
                    }
                    func_obj = rt.slot(sp, rt.FRAME_OFFSET_FUNC_OBJ).*;
                    p = @ptrCast(@alignCast(mc.valueToPtr(func_obj)));
                    b = @ptrCast(@alignCast(mc.valueToPtr(p.?.u.closure.func_bytecode)));
                    if (rt.bytecodeArgCount(b.?) > argc) {
                        n = rt.bytecodeArgCount(b.?) - argc;
                        sp -= @as(usize, @intCast(n));
                        i = 0;
                        while (i < rt.FRAME_OFFSET_ARG0 + argc) : (i += 1) {
                            sp[@intCast(i)] = sp[@intCast(i + n)];
                        }
                        i = 0;
                        while (i < n) : (i += 1) {
                            rt.slot(sp, rt.FRAME_OFFSET_ARG0 + argc + i).* = c.JS_UNDEFINED;
                        }
                    }
                    fp = sp;
                    sp -= 1;
                    sp[0] = vt.newShortInt(0);
                    sp -= 1;
                    sp[0] = c.JS_NULL;
                    sp -= @as(usize, @intCast(n_vars));
                    i = 0;
                    while (i < n_vars) : (i += 1) {
                        sp[@intCast(i)] = c.JS_UNDEFINED;
                    }
                    const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                    pc = vt.byteArrayBuf(byte_code);
                    has_pc = true;
                    state = .dispatch;
                    continue :outer;
                }
            },
            .call_exception => {
                if (!has_pc) {
                    state = .done;
                    continue :outer;
                } else {
                    const restored = restorePc(fp);
                    b = restored.b;
                    pc = restored.pc;
                    state = .exception;
                    continue :outer;
                }
            },
            .exception => {
                if (!has_pc) {
                    state = .done;
                    continue :outer;
                }
                const v = rt.valueGetSpecialValue(val);
                if (v >= c.JS_EX_CALL) {
                    call_flags = rt.valueGetSpecialValue(val) - c.JS_EX_CALL;
                    if (opcode == OP.get_length or opcode == OP.get_length2 or
                        opcode == OP.get_array_el or opcode == OP.get_array_el2 or
                        opcode == OP.put_array_el)
                    {
                        call_flags |= rt.FRAME_CF_PC_ADD1;
                    }
                    state = .generic_function_call;
                    continue :outer;
                }
                var stack_top: [*]c.JSValue = @ptrCast(rt.slot(fp, rt.FRAME_OFFSET_VAR0 + 1));
                if (b.?.vars != c.JS_NULL) {
                    const vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.vars)));
                    stack_top = @ptrFromInt(@intFromPtr(stack_top) - @as(usize, @intCast(vt.valueArraySize(vars) - rt.bytecodeArgCount(b.?))) * @sizeOf(c.JSValue));
                }
                if (mc.ctxExt(ctx).current_exception_is_uncatchable != 0) {
                    sp = stack_top;
                } else {
                    while (@intFromPtr(sp) < @intFromPtr(stack_top)) {
                        const val2 = sp[0];
                        sp += 1;
                        if (rt.valueGetSpecialTag(val2) == c.JS_TAG_CATCH_OFFSET) {
                            sp -= 1;
                            sp[0] = mc.ctxExt(ctx).current_exception;
                            mc.ctxExt(ctx).current_exception = c.JS_UNINITIALIZED;
                            const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                            pc = vt.byteArrayBuf(byte_code) + @as(usize, @intCast(rt.valueGetSpecialValue(val2)));
                            state = .dispatch;
                            continue :outer;
                        }
                    }
                }
                state = .generic_return;
                continue :outer;
            },
            .generic_return => {
                var val2 = rt.slot(fp, rt.FRAME_OFFSET_FIRST_VARREF).*;
                while (val2 != c.JS_NULL) {
                    const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(val2)));
                    val2 = pv.u.live.next;
                    std.debug.assert(!rt.varRefIsDetached(pv));
                    pv.u.value = pv.u.live.pvalue.*;
                    vt.varRefSetDetached(pv, true);
                    utils.set_free_block(
                        @ptrFromInt(@intFromPtr(pv) + @sizeOf(vt.JSVarRefExt) - @sizeOf(c.JSValue)),
                        @intCast(@sizeOf(c.JSValue)),
                    );
                }
                call_flags = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CALL_FLAGS).*);
                if ((call_flags & rt.FRAME_CF_CTOR) != 0) {
                    if (!vt.isExactException(val) and value.JS_IsObject(ctx, val) == 0) {
                        val = rt.slot(fp, rt.FRAME_OFFSET_THIS_OBJ).*;
                    }
                }
                argc = call_flags & rt.FRAME_CF_ARGC_MASK;
                argc = max_int(argc, rt.bytecodeArgCount(b.?));
                sp = @ptrCast(rt.slot(fp, rt.FRAME_OFFSET_ARG0 + argc));
                state = .return_call;
                continue :outer;
            },
            .return_call => {
                call_flags = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CALL_FLAGS).*);
                fp = rt.valueToSp(ctx, rt.slot(fp, rt.FRAME_OFFSET_SAVED_FP).*);
                if (@intFromPtr(fp) == @intFromPtr(initial_fp)) {
                    state = .done;
                    continue :outer;
                }
                const pc_offset = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CUR_PC).*);
                const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*)));
                b = @ptrCast(@alignCast(mc.valueToPtr(po.u.closure.func_bytecode)));
                const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                pc = vt.byteArrayBuf(byte_code) + @as(usize, @intCast(pc_offset));
                has_pc = true;
                if (vt.isExactException(val)) {
                    state = .exception;
                    continue :outer;
                }
                if ((call_flags & rt.FRAME_CF_POP_RET) == 0) {
                    sp -= 1;
                    sp[0] = val;
                }
                if ((call_flags & rt.FRAME_CF_PC_ADD1) == 0)
                    pc += 2;
                state = .dispatch;
                continue :outer;
            },
            .dispatch => {
                opcode = pc[0];
                pc += 1;
                switch (opcode) {
                    OP.push_minus1, OP.push_0, OP.push_1, OP.push_2, OP.push_3, OP.push_4, OP.push_5, OP.push_6, OP.push_7 => {
                        sp -= 1;
                        sp[0] = vt.newShortInt(opcode - OP.push_0);
                    },
                    OP.push_i8 => {
                        sp -= 1;
                        sp[0] = vt.newShortInt(get_i8(pc));
                        pc += 1;
                    },
                    OP.push_i16 => {
                        sp -= 1;
                        sp[0] = vt.newShortInt(get_i16(pc));
                        pc += 2;
                    },
                    OP.push_value => {
                        sp -= 1;
                        sp[0] = mc.get_u32(pc);
                        pc += 4;
                    },
                    OP.push_const => {
                        const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                        sp -= 1;
                        sp[0] = vt.valueArrayItems(cpool)[mc.get_u16(pc)];
                        pc += 2;
                    },
                    OP.undefined => {
                        sp -= 1;
                        sp[0] = c.JS_UNDEFINED;
                    },
                    OP.null => {
                        sp -= 1;
                        sp[0] = c.JS_NULL;
                    },
                    OP.push_this => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_THIS_OBJ).*;
                    },
                    OP.push_false => {
                        sp -= 1;
                        sp[0] = c.JS_FALSE;
                    },
                    OP.push_true => {
                        sp -= 1;
                        sp[0] = c.JS_TRUE;
                    },
                    OP.object => {
                        const nn: c_int = @intCast(mc.get_u16(pc));
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_NewObjectPrealloc(ctx, nn);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp -= 1;
                        sp[0] = val;
                        pc += 2;
                    },
                    OP.regexp => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_NewObjectClass(ctx, c.JS_CLASS_REGEXP, @sizeOf(rt.JSRegExpExt));
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
                        const re = rt.objectRegexp(po);
                        re.source = sp[1];
                        re.byte_code = sp[0];
                        re.last_index = 0;
                        sp[1] = val;
                        sp += 1;
                    },
                    OP.array_from => {
                        argc = @intCast(mc.get_u16(pc));
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_NewArray(ctx, argc);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        pc += 2;
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
                        const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(po.u.array.tab)));
                        const items = vt.valueArrayItems(arr);
                        i = 0;
                        while (i < argc) : (i += 1) {
                            items[@intCast(i)] = sp[@intCast(argc - 1 - i)];
                        }
                        sp += @as(usize, @intCast(argc));
                        sp -= 1;
                        sp[0] = val;
                    },
                    OP.this_func => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*;
                    },
                    OP.arguments => {
                        argc = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CALL_FLAGS).*) & rt.FRAME_CF_ARGC_MASK;
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_NewArray(ctx, argc);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
                        const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(po.u.array.tab)));
                        const items = vt.valueArrayItems(arr);
                        i = 0;
                        while (i < argc) : (i += 1) {
                            items[@intCast(i)] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + i).*;
                        }
                        sp -= 1;
                        sp[0] = val;
                    },
                    OP.new_target => {
                        call_flags = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CALL_FLAGS).*);
                        sp -= 1;
                        sp[0] = if ((call_flags & rt.FRAME_CF_CTOR) != 0)
                            rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*
                        else
                            c.JS_UNDEFINED;
                    },
                    OP.drop => {
                        sp += 1;
                    },
                    OP.nip => {
                        sp[1] = sp[0];
                        sp += 1;
                    },
                    OP.dup => {
                        sp -= 1;
                        sp[0] = sp[1];
                    },
                    OP.dup2 => {
                        sp -= 2;
                        sp[0] = sp[2];
                        sp[1] = sp[3];
                    },
                    OP.insert2 => {
                        rt.slot(sp, -1).* = sp[0];
                        sp[0] = sp[1];
                        sp[1] = rt.slot(sp, -1).*;
                        sp -= 1;
                    },
                    OP.insert3 => {
                        rt.slot(sp, -1).* = sp[0];
                        sp[0] = sp[1];
                        sp[1] = sp[2];
                        sp[2] = rt.slot(sp, -1).*;
                        sp -= 1;
                    },
                    OP.perm3 => {
                        const tmp = sp[1];
                        sp[1] = sp[2];
                        sp[2] = tmp;
                    },
                    OP.rot3l => {
                        const tmp = sp[2];
                        sp[2] = sp[1];
                        sp[1] = sp[0];
                        sp[0] = tmp;
                    },
                    OP.perm4 => {
                        const tmp = sp[1];
                        sp[1] = sp[2];
                        sp[2] = sp[3];
                        sp[3] = tmp;
                    },
                    OP.swap => {
                        const tmp = sp[1];
                        sp[1] = sp[0];
                        sp[0] = tmp;
                    },
                    OP.fclosure => {
                        const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                        const idx = mc.get_u16(pc);
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_closure(ctx, vt.valueArrayItems(cpool)[idx], fp);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        pc += 2;
                        sp -= 1;
                        sp[0] = val;
                    },
                    OP.call_constructor => {
                        call_flags = @intCast(mc.get_u16(pc) | @as(u32, @intCast(rt.FRAME_CF_CTOR)));
                        coerce.js_reverse_val(sp, (call_flags & rt.FRAME_CF_ARGC_MASK) + 1);
                        sp -= 1;
                        sp[0] = c.JS_UNDEFINED;
                        state = .generic_function_call;
                        continue :outer;
                    },
                    OP.call => {
                        call_flags = @intCast(mc.get_u16(pc));
                        coerce.js_reverse_val(sp, (call_flags & rt.FRAME_CF_ARGC_MASK) + 1);
                        sp -= 1;
                        sp[0] = c.JS_UNDEFINED;
                        state = .generic_function_call;
                        continue :outer;
                    },
                    OP.call_method => {
                        call_flags = @intCast(mc.get_u16(pc));
                        n = (call_flags & rt.FRAME_CF_ARGC_MASK) + 2;
                        coerce.js_reverse_val(sp, n);
                        state = .generic_function_call;
                        continue :outer;
                    },
                    OP.@"catch" => {
                        const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                        const diff: i32 = @bitCast(mc.get_u32(pc));
                        const dest: i32 = @intCast(@as(isize, @bitCast(@intFromPtr(pc))) + @as(isize, diff) - @as(isize, @bitCast(@intFromPtr(vt.byteArrayBuf(byte_code)))));
                        sp -= 1;
                        sp[0] = rt.makeSpecial(c.JS_TAG_CATCH_OFFSET, dest);
                        pc += 4;
                    },
                    OP.throw => {
                        val = sp[0];
                        sp += 1;
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = utils.JS_Throw(ctx, val);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        state = .exception;
                        continue :outer;
                    },
                    OP.gosub => {
                        const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                        const diff: i32 = @bitCast(mc.get_u32(pc));
                        const pos: i32 = @intCast(@as(isize, @bitCast(@intFromPtr(pc))) + 4 - @as(isize, @bitCast(@intFromPtr(vt.byteArrayBuf(byte_code)))));
                        sp -= 1;
                        sp[0] = vt.newShortInt(pos);
                        pc = ptrAddI32(pc, diff);
                    },
                    OP.ret => {
                        const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                        if (!mc.isInt(sp[0])) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = throwInternalError(ctx, "invalid ret value");
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            state = .exception;
                            continue :outer;
                        }
                        const pos = vt.valueGetInt(sp[0]);
                        if (pos < 0 or pos >= vt.byteArraySize(byte_code)) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = throwInternalError(ctx, "invalid ret value");
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            state = .exception;
                            continue :outer;
                        }
                        sp += 1;
                        pc = vt.byteArrayBuf(byte_code) + @as(usize, @intCast(pos));
                    },
                    OP.get_loc => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        pc += 2;
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - idx).*;
                    },
                    OP.put_loc => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        pc += 2;
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - idx).* = sp[0];
                        sp += 1;
                    },
                    OP.get_arg => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        pc += 2;
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + idx).*;
                    },
                    OP.put_arg => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        pc += 2;
                        rt.slot(fp, rt.FRAME_OFFSET_ARG0 + idx).* = sp[0];
                        sp += 1;
                    },
                    OP.get_loc0 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 0).*;
                    },
                    OP.get_loc1 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 1).*;
                    },
                    OP.get_loc2 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 2).*;
                    },
                    OP.get_loc3 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 3).*;
                    },
                    OP.get_loc8 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_VAR0 - @as(c_int, pc[0])).*;
                        pc += 1;
                    },
                    OP.put_loc0 => {
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 0).* = sp[0];
                        sp += 1;
                    },
                    OP.put_loc1 => {
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 1).* = sp[0];
                        sp += 1;
                    },
                    OP.put_loc2 => {
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 2).* = sp[0];
                        sp += 1;
                    },
                    OP.put_loc3 => {
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - 3).* = sp[0];
                        sp += 1;
                    },
                    OP.put_loc8 => {
                        rt.slot(fp, rt.FRAME_OFFSET_VAR0 - @as(c_int, pc[0])).* = sp[0];
                        pc += 1;
                        sp += 1;
                    },
                    OP.get_arg0 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 0).*;
                    },
                    OP.get_arg1 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 1).*;
                    },
                    OP.get_arg2 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 2).*;
                    },
                    OP.get_arg3 => {
                        sp -= 1;
                        sp[0] = rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 3).*;
                    },
                    OP.put_arg0 => {
                        rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 0).* = sp[0];
                        sp += 1;
                    },
                    OP.put_arg1 => {
                        rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 1).* = sp[0];
                        sp += 1;
                    },
                    OP.put_arg2 => {
                        rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 2).* = sp[0];
                        sp += 1;
                    },
                    OP.put_arg3 => {
                        rt.slot(fp, rt.FRAME_OFFSET_ARG0 + 3).* = sp[0];
                        sp += 1;
                    },
                    OP.get_var_ref, OP.get_var_ref_nocheck => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*)));
                        const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(rt.closureVarRefs(po)[@intCast(idx)])));
                        if (rt.varRefIsDetached(pv))
                            val = pv.u.value
                        else
                            val = pv.u.live.pvalue.*;
                        if (val == c.JS_UNINITIALIZED and opcode == OP.get_var_ref) {
                            const ext_vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.ext_vars)));
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = utils.JS_ThrowError(ctx, c.JS_CLASS_REFERENCE_ERROR, "variable '%lo' is not defined", vt.valueArrayItems(ext_vars)[@intCast(2 * idx)]);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            state = .exception;
                            continue :outer;
                        }
                        pc += 2;
                        sp -= 1;
                        sp[0] = val;
                    },
                    OP.put_var_ref, OP.put_var_ref_nocheck => {
                        const idx: c_int = @intCast(mc.get_u16(pc));
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*)));
                        const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(rt.closureVarRefs(po)[@intCast(idx)])));
                        const pval: *c.JSValue = if (rt.varRefIsDetached(pv)) &pv.u.value else pv.u.live.pvalue;
                        if (pval.* == c.JS_UNINITIALIZED and opcode == OP.put_var_ref) {
                            const ext_vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.ext_vars)));
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = utils.JS_ThrowError(ctx, c.JS_CLASS_REFERENCE_ERROR, "variable '%lo' is not defined", vt.valueArrayItems(ext_vars)[@intCast(2 * idx)]);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            state = .exception;
                            continue :outer;
                        }
                        pval.* = sp[0];
                        sp += 1;
                        pc += 2;
                    },
                    OP.goto => {
                        const diff: i32 = @bitCast(mc.get_u32(pc));
                        pc = ptrAddI32(pc, diff);
                        mc.ctxExt(ctx).interrupt_counter -= 1;
                        if (mc.ctxExt(ctx).interrupt_counter <= 0) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = coerce.__js_poll_interrupt(ctx);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                        }
                    },
                    OP.if_false, OP.if_true => {
                        pc += 4;
                        const res = value.JS_ToBool(ctx, sp[0]);
                        sp += 1;
                        if ((res ^ (OP.if_true - opcode)) != 0) {
                            const diff: i32 = @bitCast(mc.get_u32(pc - 4));
                            pc = ptrAddI32(pc, diff - 4);
                        }
                        mc.ctxExt(ctx).interrupt_counter -= 1;
                        if (mc.ctxExt(ctx).interrupt_counter <= 0) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = coerce.__js_poll_interrupt(ctx);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                        }
                    },
                    OP.lnot => {
                        const res = value.JS_ToBool(ctx, sp[0]);
                        sp[0] = rt.newBool(res == 0);
                    },
                    OP.get_field2 => {
                        sp -= 1;
                        sp[0] = sp[1];
                        state = .get_field;
                        // handled below by duplicating get_field
                    },
                    OP.get_field => {
                        const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                        const idx = mc.get_u16(pc);
                        const prop = vt.valueArrayItems(cpool)[idx];
                        var obj = sp[0];
                        var slow = true;
                        if (mc.isPtr(obj)) {
                            var po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT) {
                                slow = false;
                                while (true) {
                                    if (vt.findOwnPropertyInlined(po, prop)) |pr| {
                                        if (vt.propType(pr) != vt.JS_PROP_NORMAL) {
                                            slow = true;
                                            break;
                                        } else {
                                            val = pr.value;
                                            break;
                                        }
                                    }
                                    obj = po.proto;
                                    if (obj == c.JS_NULL) {
                                        val = c.JS_UNDEFINED;
                                        break;
                                    }
                                    po = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                                }
                            }
                        }
                        if (slow) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_GetPropertyInternal(ctx, obj, prop, 1);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (rt.isExceptionOrTailCall(val)) {
                                sp = @ptrCast(mc.ctxExt(ctx).sp);
                                state = .exception;
                                continue :outer;
                            }
                        }
                        pc += 2;
                        sp[0] = val;
                    },
                    OP.get_length2 => {
                        sp -= 1;
                        sp[0] = sp[1];
                        state = .get_length;
                    },
                    OP.get_length => {
                        const obj = sp[0];
                        var slow = true;
                        if (mc.isPtr(obj)) {
                            const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT) {
                                if (mc.objectClassId(po) == c.JS_CLASS_ARRAY) {
                                    if (po.proto == vt.classProto(mc.ctxExt(ctx), c.JS_CLASS_ARRAY).* and
                                        po.props == mc.ctxExt(ctx).empty_props)
                                    {
                                        val = vt.newShortInt(@intCast(po.u.array.len));
                                        slow = false;
                                    }
                                }
                            } else if (mc.mbGetMtag(po) == mc.JS_MTAG_STRING) {
                                const ps: *vt.JSStringExt = @ptrCast(po);
                                if (vt.stringIsAscii(ps))
                                    val = vt.newShortInt(@intCast(vt.stringLen(ps)))
                                else
                                    val = vt.newShortInt(@intCast(value.js_string_utf8_to_utf16_pos(ctx, obj, @intCast(vt.stringLen(ps) * 2))));
                                slow = false;
                            }
                        } else if (rt.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
                            val = vt.newShortInt(if (rt.valueGetSpecialValue(val) >= 0x10000) 2 else 1);
                            slow = false;
                        }
                        if (slow) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_GetPropertyInternal(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_length), 1);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (rt.isExceptionOrTailCall(val)) {
                                sp = @ptrCast(mc.ctxExt(ctx).sp);
                                state = .exception;
                                continue :outer;
                            }
                        }
                        sp[0] = val;
                    },
                    OP.put_field => {
                        const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                        const idx = mc.get_u16(pc);
                        const prop = vt.valueArrayItems(cpool)[idx];
                        const obj = sp[1];
                        var slow = true;
                        if (mc.isPtr(obj)) {
                            const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT) {
                                if (vt.findOwnPropertyInlined(po, prop)) |pr| {
                                    if (vt.propType(pr) == vt.JS_PROP_NORMAL and !vt.jsIsRomPtr(ctx, pr)) {
                                        pr.value = sp[0];
                                        sp += 2;
                                        slow = false;
                                    }
                                }
                            }
                        }
                        if (slow) {
                            val = sp[0];
                            sp += 1;
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_SetPropertyInternal(ctx, sp[0], prop, val, 1);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (rt.isExceptionOrTailCall(val)) {
                                sp = @ptrCast(mc.ctxExt(ctx).sp);
                                state = .exception;
                                continue :outer;
                            }
                            sp += 1;
                        }
                        pc += 2;
                    },
                    OP.get_array_el2 => {
                        val = sp[0];
                        sp[0] = sp[1];
                        state = .get_array_el;
                    },
                    OP.get_array_el => {
                        if (opcode == OP.get_array_el) {
                            val = sp[0];
                            sp += 1;
                        }
                        var prop = val;
                        const obj = sp[0];
                        var slow = true;
                        if (mc.isPtr(obj) and mc.isInt(prop)) {
                            const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT and mc.objectClassId(po) == c.JS_CLASS_ARRAY) {
                                const idx: u32 = @bitCast(vt.valueGetInt(prop));
                                if (idx < po.u.array.len) {
                                    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(po.u.array.tab)));
                                    val = vt.valueArrayItems(arr)[idx];
                                    slow = false;
                                }
                            }
                        }
                        if (slow) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            prop = coerce.JS_ToPropertyKey(ctx, prop);
                            var restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(prop)) {
                                val = prop;
                                state = .exception;
                                continue :outer;
                            }
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_GetPropertyInternal(ctx, sp[0], prop, 1);
                            restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (rt.isExceptionOrTailCall(val)) {
                                sp = @ptrCast(mc.ctxExt(ctx).sp);
                                state = .exception;
                                continue :outer;
                            }
                        }
                        sp[0] = val;
                    },
                    OP.put_array_el => {
                        const obj = sp[2];
                        var prop = sp[1];
                        var slow = true;
                        if (mc.isPtr(obj) and mc.isInt(prop)) {
                            const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT and mc.objectClassId(po) == c.JS_CLASS_ARRAY) {
                                const idx: u32 = @bitCast(vt.valueGetInt(prop));
                                const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(po.u.array.tab)));
                                if (idx >= po.u.array.len) {
                                    if (idx == po.u.array.len and po.u.array.tab != c.JS_NULL and
                                        idx < @as(u32, @intCast(vt.valueArraySize(arr))))
                                    {
                                        vt.valueArrayItems(arr)[idx] = sp[0];
                                        po.u.array.len = idx + 1;
                                        sp += 3;
                                        slow = false;
                                    }
                                } else {
                                    vt.valueArrayItems(arr)[idx] = sp[0];
                                    sp += 3;
                                    slow = false;
                                }
                            }
                        }
                        if (slow) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            sp[1] = coerce.JS_ToPropertyKey(ctx, sp[1]);
                            var restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(sp[1])) {
                                val = sp[1];
                                state = .exception;
                                continue :outer;
                            }
                            val = sp[0];
                            sp += 1;
                            prop = sp[0];
                            sp += 1;
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_SetPropertyInternal(ctx, sp[0], prop, val, 1);
                            restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (rt.isExceptionOrTailCall(val)) {
                                sp = @ptrCast(mc.ctxExt(ctx).sp);
                                state = .exception;
                                continue :outer;
                            }
                            sp += 1;
                        }
                    },
                    OP.define_field, OP.define_getter, OP.define_setter => {
                        const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                        const idx = mc.get_u16(pc);
                        const prop = vt.valueArrayItems(cpool)[idx];
                        saveFrame(ctx, fp, sp, pc, b.?);
                        if (opcode == OP.define_field) {
                            val = value.JS_DefinePropertyValue(ctx, sp[1], prop, sp[0]);
                        } else if (opcode == OP.define_getter) {
                            val = value.JS_DefinePropertyGetSet(ctx, sp[1], prop, sp[0], c.JS_UNDEFINED, vt.JS_DEF_PROP_HAS_GET);
                        } else {
                            val = value.JS_DefinePropertyGetSet(ctx, sp[1], prop, c.JS_UNDEFINED, sp[0], vt.JS_DEF_PROP_HAS_SET);
                        }
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        pc += 2;
                        sp += 1;
                    },
                    OP.set_proto => {
                        if (value.JS_IsObject(ctx, sp[0]) != 0 or sp[0] == c.JS_NULL) {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = builtins.js_set_prototype_internal(ctx, sp[1], sp[0]);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                        }
                        sp += 1;
                    },
                    OP.add => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const ov = @addWithOverflow(rt.asI32(op1), rt.asI32(op2));
                            if (ov[1] != 0) {
                                state = .add_slow;
                                continue :outer;
                            }
                            sp[1] = rt.storeU32(@bitCast(ov[0]));
                        } else if (rt.isBothShortFloat(op1, op2)) {
                            dr = jsGetShortFloat(op1) + jsGetShortFloat(op2);
                            sp += 1;
                            state = .float_result;
                            continue :outer;
                        } else {
                            state = .add_slow;
                            continue :outer;
                        }
                        sp += 1;
                    },
                    OP.sub => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const ov = @subWithOverflow(rt.asI32(op1), rt.asI32(op2));
                            if (ov[1] != 0) {
                                state = .binary_arith_slow;
                                continue :outer;
                            }
                            sp[1] = rt.storeU32(@bitCast(ov[0]));
                        } else if (rt.isBothShortFloat(op1, op2)) {
                            dr = jsGetShortFloat(op1) - jsGetShortFloat(op2);
                            sp += 1;
                            state = .float_result;
                            continue :outer;
                        } else {
                            state = .binary_arith_slow;
                            continue :outer;
                        }
                        sp += 1;
                    },
                    OP.mul => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const v1 = rt.asI32(op1);
                            const v2 = rt.asI32(op2) >> 1;
                            const r: i64 = @as(i64, v1) * @as(i64, v2);
                            if (r != @as(i32, @truncate(r))) {
                                dr = @floatFromInt(r >> 1);
                                sp += 1;
                                state = .float_result;
                                continue :outer;
                            }
                            if (r == 0 and (v1 | v2) < 0) {
                                sp[1] = mc.ctxExt(ctx).minus_zero;
                            } else {
                                sp[1] = rt.storeU32(@bitCast(@as(i32, @truncate(r))));
                            }
                        } else if (rt.isBothShortFloat(op1, op2)) {
                            dr = jsGetShortFloat(op1) * jsGetShortFloat(op2);
                            sp += 1;
                            state = .float_result;
                            continue :outer;
                        } else {
                            state = .binary_arith_slow;
                            continue :outer;
                        }
                        sp += 1;
                    },
                    OP.div => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const v1 = vt.valueGetInt(op1);
                            const v2 = vt.valueGetInt(op2);
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = value.JS_NewFloat64(ctx, @as(f64, @floatFromInt(v1)) / @as(f64, @floatFromInt(v2)));
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                            sp[1] = val;
                            sp += 1;
                        } else {
                            state = .binary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.mod => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const v1 = vt.valueGetInt(op1);
                            const v2 = vt.valueGetInt(op2);
                            if (v1 < 0 or v2 <= 0) {
                                state = .binary_arith_slow;
                                continue :outer;
                            }
                            sp[1] = vt.newShortInt(@mod(v1, v2));
                            sp += 1;
                        } else {
                            state = .binary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.pow => {
                        state = .binary_arith_slow;
                        continue :outer;
                    },
                    OP.plus => {
                        const op1 = sp[0];
                        if (!(vt.isIntOrShortFloat(op1) or (mc.isPtr(op1) and utils.js_get_mtag(mc.valueToPtr(op1)) == mc.JS_MTAG_FLOAT64))) {
                            state = .unary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.neg => {
                        const op1 = sp[0];
                        if (mc.isInt(op1)) {
                            const v1 = rt.asI32(op1);
                            if (v1 == 0) {
                                sp[0] = mc.ctxExt(ctx).minus_zero;
                            } else if (v1 == std.math.minInt(i32)) {
                                dr = -@as(f64, @floatFromInt(vt.JS_SHORTINT_MIN));
                                state = .float_result;
                                continue :outer;
                            } else {
                                sp[0] = rt.storeI32(-v1);
                            }
                        } else if (mc.isShortFloat(op1)) {
                            dr = -jsGetShortFloat(op1);
                            state = .float_result;
                            continue :outer;
                        } else {
                            state = .unary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.inc => {
                        const op1 = sp[0];
                        if (mc.isInt(op1)) {
                            const v1 = vt.valueGetInt(op1);
                            if (v1 == vt.JS_SHORTINT_MAX) {
                                state = .unary_arith_slow;
                                continue :outer;
                            }
                            sp[0] = vt.newShortInt(v1 + 1);
                        } else {
                            state = .unary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.dec => {
                        const op1 = sp[0];
                        if (mc.isInt(op1)) {
                            const v1 = vt.valueGetInt(op1);
                            if (v1 == vt.JS_SHORTINT_MIN) {
                                state = .unary_arith_slow;
                                continue :outer;
                            }
                            sp[0] = vt.newShortInt(v1 - 1);
                        } else {
                            state = .unary_arith_slow;
                            continue :outer;
                        }
                    },
                    OP.post_inc, OP.post_dec => {
                        const op1 = sp[0];
                        if (mc.isInt(op1)) {
                            const v1 = vt.valueGetInt(op1) + 2 * (opcode - OP.post_dec) - 1;
                            if (v1 < vt.JS_SHORTINT_MIN or v1 > vt.JS_SHORTINT_MAX) {
                                saveFrame(ctx, fp, sp, pc, b.?);
                                val = coerce.js_post_inc_slow(ctx, opcode);
                                const restored = restorePc(fp);
                                b = restored.b;
                                pc = restored.pc;
                                if (vt.isExactException(val)) {
                                    state = .exception;
                                    continue :outer;
                                }
                            } else {
                                val = vt.newShortInt(v1);
                            }
                        } else {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = coerce.js_post_inc_slow(ctx, opcode);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                        }
                        sp -= 1;
                        sp[0] = val;
                    },
                    OP.not => {
                        const op1 = sp[0];
                        if (mc.isInt(op1)) {
                            sp[0] = (~op1) & (~@as(c.JSValue, 1));
                        } else {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = coerce.js_not_slow(ctx);
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                            sp[0] = val;
                        }
                    },
                    OP.shl => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const r = vt.valueGetInt(op1) << @as(u5, @intCast(vt.valueGetInt(op2) & 0x1f));
                            if (r < vt.JS_SHORTINT_MIN or r > vt.JS_SHORTINT_MAX) {
                                dr = @floatFromInt(r);
                                sp += 1;
                                state = .float_result;
                                continue :outer;
                            }
                            sp[1] = vt.newShortInt(r);
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.shr => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const r: u32 = @as(u32, @bitCast(vt.valueGetInt(op1))) >> @as(u5, @intCast(@as(u32, @bitCast(vt.valueGetInt(op2))) & 0x1f));
                            if (r > @as(u32, @intCast(vt.JS_SHORTINT_MAX))) {
                                dr = @floatFromInt(r);
                                sp += 1;
                                state = .float_result;
                                continue :outer;
                            }
                            sp[1] = vt.newShortInt(@intCast(r));
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.sar => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            sp[1] = rt.storeI32(rt.asI32(op1) >> @as(u5, @intCast(vt.valueGetInt(op2) & 0x1f))) & ~@as(c.JSValue, 1);
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.@"and" => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            sp[1] = op1 & op2;
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.@"or" => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            sp[1] = op1 | op2;
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.xor => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            sp[1] = op1 ^ op2;
                            sp += 1;
                        } else {
                            state = .binary_logic_slow;
                            continue :outer;
                        }
                    },
                    OP.lt, OP.lte, OP.gt, OP.gte, OP.eq, OP.neq, OP.strict_eq, OP.strict_neq => {
                        const op1 = sp[1];
                        const op2 = sp[0];
                        if (rt.isBothInt(op1, op2)) {
                            const a = vt.valueGetInt(op1);
                            const bbv = vt.valueGetInt(op2);
                            const cmp: bool = switch (opcode) {
                                OP.lt => a < bbv,
                                OP.lte => a <= bbv,
                                OP.gt => a > bbv,
                                OP.gte => a >= bbv,
                                OP.eq, OP.strict_eq => a == bbv,
                                else => a != bbv,
                            };
                            sp[1] = rt.newBool(cmp);
                            sp += 1;
                        } else {
                            saveFrame(ctx, fp, sp, pc, b.?);
                            val = switch (opcode) {
                                OP.lt, OP.lte, OP.gt, OP.gte => coerce.js_relational_slow(ctx, opcode),
                                OP.eq => coerce.js_eq_slow(ctx, 0),
                                OP.neq => coerce.js_eq_slow(ctx, 1),
                                OP.strict_eq => coerce.js_strict_eq_slow(ctx, 0),
                                else => coerce.js_strict_eq_slow(ctx, 1),
                            };
                            const restored = restorePc(fp);
                            b = restored.b;
                            pc = restored.pc;
                            if (vt.isExactException(val)) {
                                state = .exception;
                                continue :outer;
                            }
                            sp[1] = val;
                            sp += 1;
                        }
                    },
                    OP.in => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_operator_in(ctx);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp[1] = val;
                        sp += 1;
                    },
                    OP.instanceof => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_operator_instanceof(ctx);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp[1] = val;
                        sp += 1;
                    },
                    OP.typeof => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_operator_typeof(ctx, sp[0]);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp[0] = val;
                    },
                    OP.delete => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_DeleteProperty(ctx, sp[1], sp[0]);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp[1] = val;
                        sp += 1;
                    },
                    OP.for_in_start, OP.for_of_start => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_for_of_start(ctx, @intFromBool(opcode == OP.for_in_start));
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp[0] = val;
                    },
                    OP.for_of_next => {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = coerce.js_for_of_next(ctx);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(val)) {
                            state = .exception;
                            continue :outer;
                        }
                        sp -= 2;
                    },
                    OP.@"return" => {
                        val = sp[0];
                        state = .generic_return;
                        continue :outer;
                    },
                    OP.return_undef => {
                        val = c.JS_UNDEFINED;
                        state = .generic_return;
                        continue :outer;
                    },
                    else => {
                        const byte_code: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.byte_code)));
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = utils.JS_ThrowError(
                            ctx,
                            c.JS_CLASS_INTERNAL_ERROR,
                            "invalid opcode: pc=%u opcode=0x%02x",
                            @as(c_int, @intCast(@intFromPtr(pc) - @intFromPtr(vt.byteArrayBuf(byte_code)) - 1)),
                            opcode,
                        );
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        state = .exception;
                        continue :outer;
                    },
                }
                // get_field2 / get_length2 / get_array_el2 fallthroughs
                if (state == .get_field) {
                    state = .dispatch;
                    const cpool: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.?.cpool)));
                    const idx = mc.get_u16(pc);
                    const prop = vt.valueArrayItems(cpool)[idx];
                    var obj = sp[0];
                    var slow = true;
                    if (mc.isPtr(obj)) {
                        var po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                        if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT) {
                            slow = false;
                            while (true) {
                                if (vt.findOwnPropertyInlined(po, prop)) |pr| {
                                    if (vt.propType(pr) != vt.JS_PROP_NORMAL) {
                                        slow = true;
                                        break;
                                    } else {
                                        val = pr.value;
                                        break;
                                    }
                                }
                                obj = po.proto;
                                if (obj == c.JS_NULL) {
                                    val = c.JS_UNDEFINED;
                                    break;
                                }
                                po = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                            }
                        }
                    }
                    if (slow) {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_GetPropertyInternal(ctx, obj, prop, 1);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (rt.isExceptionOrTailCall(val)) {
                            sp = @ptrCast(mc.ctxExt(ctx).sp);
                            state = .exception;
                            continue :outer;
                        }
                    }
                    pc += 2;
                    sp[0] = val;
                } else if (state == .get_length) {
                    state = .dispatch;
                    const obj = sp[0];
                    var slow = true;
                    if (mc.isPtr(obj)) {
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                        if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT) {
                            if (mc.objectClassId(po) == c.JS_CLASS_ARRAY) {
                                if (po.proto == vt.classProto(mc.ctxExt(ctx), c.JS_CLASS_ARRAY).* and
                                    po.props == mc.ctxExt(ctx).empty_props)
                                {
                                    val = vt.newShortInt(@intCast(po.u.array.len));
                                    slow = false;
                                }
                            }
                        } else if (mc.mbGetMtag(po) == mc.JS_MTAG_STRING) {
                            const ps: *vt.JSStringExt = @ptrCast(po);
                            if (vt.stringIsAscii(ps))
                                val = vt.newShortInt(@intCast(vt.stringLen(ps)))
                            else
                                val = vt.newShortInt(@intCast(value.js_string_utf8_to_utf16_pos(ctx, obj, @intCast(vt.stringLen(ps) * 2))));
                            slow = false;
                        }
                    } else if (rt.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
                        val = vt.newShortInt(if (rt.valueGetSpecialValue(val) >= 0x10000) 2 else 1);
                        slow = false;
                    }
                    if (slow) {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_GetPropertyInternal(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_length), 1);
                        const restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (rt.isExceptionOrTailCall(val)) {
                            sp = @ptrCast(mc.ctxExt(ctx).sp);
                            state = .exception;
                            continue :outer;
                        }
                    }
                    sp[0] = val;
                } else if (state == .get_array_el) {
                    state = .dispatch;
                    var prop = val;
                    const obj = sp[0];
                    var slow = true;
                    if (mc.isPtr(obj) and mc.isInt(prop)) {
                        const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
                        if (mc.mbGetMtag(po) == mc.JS_MTAG_OBJECT and mc.objectClassId(po) == c.JS_CLASS_ARRAY) {
                            const idx: u32 = @bitCast(vt.valueGetInt(prop));
                            if (idx < po.u.array.len) {
                                const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(po.u.array.tab)));
                                val = vt.valueArrayItems(arr)[idx];
                                slow = false;
                            }
                        }
                    }
                    if (slow) {
                        saveFrame(ctx, fp, sp, pc, b.?);
                        prop = coerce.JS_ToPropertyKey(ctx, prop);
                        var restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (vt.isExactException(prop)) {
                            val = prop;
                            state = .exception;
                            continue :outer;
                        }
                        saveFrame(ctx, fp, sp, pc, b.?);
                        val = value.JS_GetPropertyInternal(ctx, sp[0], prop, 1);
                        restored = restorePc(fp);
                        b = restored.b;
                        pc = restored.pc;
                        if (rt.isExceptionOrTailCall(val)) {
                            sp = @ptrCast(mc.ctxExt(ctx).sp);
                            state = .exception;
                            continue :outer;
                        }
                    }
                    sp[0] = val;
                }
            },
        }
    }

    mc.ctxExt(ctx).sp = @ptrCast(sp);
    mc.ctxExt(ctx).fp = @ptrCast(fp);
    mc.ctxExt(ctx).js_call_rec_count -= 1;
    return val;
}
