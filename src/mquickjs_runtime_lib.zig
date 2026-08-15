//
// Micro QuickJS engine runtime (shared implementation)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const dtoa = @import("dtoa_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const gc = @import("mquickjs_gc_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const rt = @import("mquickjs_runtime_types.zig");
const vt = rt.vt;
const mc = vt.mc;
pub const c = rt.c;

const coerce = @import("mquickjs_runtime_coerce_lib.zig");

pub const JS_ToPrimitive = coerce.JS_ToPrimitive;
pub const js_dtoa2 = coerce.js_dtoa2;
pub const JS_ToString = coerce.JS_ToString;
pub const JS_ToPropertyKey = coerce.JS_ToPropertyKey;
pub const skip_spaces = coerce.skip_spaces;
pub const js_atod1 = coerce.js_atod1;
pub const JS_ToNumber = coerce.JS_ToNumber;
pub const JS_ToInt32Internal = coerce.JS_ToInt32Internal;
pub const JS_ToInt32 = coerce.JS_ToInt32;
pub const JS_ToUint32 = coerce.JS_ToUint32;
pub const JS_ToInt32Sat = coerce.JS_ToInt32Sat;
pub const JS_ToInt32Clamp = coerce.JS_ToInt32Clamp;
pub const JS_ToUint8Clamp = coerce.JS_ToUint8Clamp;
pub const js_get_length32 = coerce.js_get_length32;
pub const js_add_slow = coerce.js_add_slow;
pub const js_binary_arith_slow = coerce.js_binary_arith_slow;
pub const js_unary_arith_slow = coerce.js_unary_arith_slow;
pub const js_post_inc_slow = coerce.js_post_inc_slow;
pub const js_binary_logic_slow = coerce.js_binary_logic_slow;
pub const js_not_slow = coerce.js_not_slow;
pub const js_relational_slow = coerce.js_relational_slow;
pub const js_strict_eq = coerce.js_strict_eq;
pub const js_strict_eq_slow = coerce.js_strict_eq_slow;
pub const js_eq_get_type = coerce.js_eq_get_type;
pub const js_eq_slow = coerce.js_eq_slow;
pub const js_operator_in = coerce.js_operator_in;
pub const js_operator_instanceof = coerce.js_operator_instanceof;
pub const js_operator_typeof = coerce.js_operator_typeof;
pub const js_reverse_val = coerce.js_reverse_val;
pub const js_closure = coerce.js_closure;
pub const js_for_of_start = coerce.js_for_of_start;
pub const js_for_of_next = coerce.js_for_of_next;
pub const js_new_c_function_proto = coerce.js_new_c_function_proto;
pub const JS_NewCFunctionParams = coerce.JS_NewCFunctionParams;
pub const js_call_constructor_start = coerce.js_call_constructor_start;
pub const __js_poll_interrupt = coerce.__js_poll_interrupt;

const call = @import("mquickjs_runtime_call_lib.zig");
pub const JS_Call = call.JS_Call;

extern fn js_lrint(x: f64) c_long;
extern fn js_fmod(x: f64, y: f64) f64;
extern fn js_pow(x: f64, y: f64) f64;

fn jsNewInt32(ctx: *c.JSContext, v: i32) c.JSValue {
    return @call(.never_inline, value.JS_NewInt32, .{ctx, v});
}

fn jsNewUint32(ctx: *c.JSContext, v: u32) c.JSValue {
    return @call(.never_inline, value.JS_NewUint32, .{ctx, v});
}

fn get_be32(d: [*]const u8) u32 {
    return @byteSwap(mc.get_u32(d));
}

pub fn dummy_write_func(opaque_val: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) callconv(.c) void {
    _ = opaque_val;
    _ = buf;
    _ = buf_len;
}

pub fn JS_NewContext2(mem_start: *anyopaque, mem_size_in: usize, stdlib_def: *const c.JSSTDLibraryDef, prepare_compilation: c.JS_BOOL) *c.JSContext {
    const mem_align: usize = if (@sizeOf(c.JSWord) == 8) 8 else 4;
    const mem_size = mem_size_in & ~(mem_align - 1);
    std.debug.assert(mem_size >= 1024);
    std.debug.assert(@intFromPtr(mem_start) & (mem_align - 1) == 0);

    const ctx: *c.JSContext = @ptrCast(@alignCast(mem_start));
    const ctx_bytes: [*]u8 = @ptrCast(ctx);
    @memset(ctx_bytes[0..@sizeOf(mc.JSContextExt)], 0);
    const x = mc.ctxExt(ctx);
    x.class_count = @intCast(stdlib_def.class_count);
    const proto: [*]c.JSValue = @ptrCast(@alignCast(&x.class_proto));
    x.class_obj = @ptrCast(proto + @as(usize, @intCast(x.class_count)));
    x.heap_base = @ptrCast(proto + @as(usize, @intCast(2 * @as(c_int, x.class_count))));
    x.heap_free = x.heap_base;
    x.stack_top = @as([*]u8, @ptrCast(mem_start)) + mem_size;
    x.sp = @ptrCast(@alignCast(x.stack_top));
    x.stack_bottom = x.sp;
    x.fp = x.sp;
    x.min_free_size = mc.JS_MIN_FREE_SIZE;
    x.random_state = 1;
    x.write_func = dummy_write_func;
    for (0..vt.JS_STRING_POS_CACHE_SIZE) |i| {
        x.string_pos_cache[i].str = c.JS_NULL;
    }

    if (prepare_compilation != 0) {
        const atom_table_len: usize = @intCast(stdlib_def.sorted_atoms_offset);
        x.atom_table = @ptrCast(@alignCast(x.heap_free));
        const src: [*]const u8 = @ptrCast(stdlib_def.stdlib_table);
        const nbytes = atom_table_len * @sizeOf(c.JSWord);
        @memcpy(x.heap_free[0..nbytes], src[0..nbytes]);
        x.heap_free += nbytes;

        const arr1: *vt.JSValueArrayExt = @ptrCast(@alignCast(@constCast(
            @as([*]const c.JSWord, @ptrCast(stdlib_def.stdlib_table)) + atom_table_len,
        )));
        const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(
            value.js_alloc_value_array(ctx, 0, vt.valueArraySize(arr1)).?,
        ));
        x.unique_strings = mc.valueFromPtr(arr);
        const items = vt.valueArrayItems(arr);
        const items1 = vt.valueArrayItems(arr1);
        const stdlib_base = @intFromPtr(stdlib_def.stdlib_table);
        const atom_base = @intFromPtr(x.atom_table);
        const n: usize = @intCast(vt.valueArraySize(arr1));
        for (0..n) |i| {
            const ptr = @intFromPtr(mc.valueToPtr(items1[i]));
            const relocated = ptr - stdlib_base + atom_base;
            items[i] = mc.valueFromPtr(@ptrFromInt(relocated));
        }
        x.unique_strings_len = vt.valueArraySize(arr1);
    } else {
        x.atom_table = stdlib_def.stdlib_table;
        x.rom_atom_tables[0] = @ptrCast(@constCast(
            @as([*]const c.JSWord, @ptrCast(stdlib_def.stdlib_table)) + @as(usize, @intCast(stdlib_def.sorted_atoms_offset)),
        ));
        x.n_rom_atom_tables = 1;
        x.c_function_table = @ptrCast(stdlib_def.c_function_table);
        x.c_finalizer_table = @ptrCast(@constCast(stdlib_def.c_finalizer_table));
        x.unique_strings = c.JS_NULL;
        x.unique_strings_len = 0;
    }

    x.current_exception = c.JS_UNINITIALIZED;

    const empty: *vt.JSValueArrayExt = @ptrCast(@alignCast(value.js_alloc_value_array(ctx, 0, 3).?));
    const empty_items = vt.valueArrayItems(empty);
    empty_items[0] = vt.newShortInt(0);
    empty_items[1] = vt.newShortInt(0);
    empty_items[2] = vt.newShortInt(0);
    x.empty_props = mc.valueFromPtr(empty);
    var i: c_int = 0;
    while (i < x.class_count) : (i += 1) {
        vt.classProto(x, i).* = c.JS_NULL;
    }
    i = 0;
    while (i < x.class_count) : (i += 1) {
        vt.classObj(x, i).* = c.JS_NULL;
    }
    vt.classProto(x, c.JS_CLASS_OBJECT).* = value.JS_NewObject(ctx);
    vt.classProto(x, c.JS_CLASS_CLOSURE).* = value.JS_NewObject(ctx);
    x.global_obj = value.JS_NewObject(ctx);
    x.minus_zero = value.js_alloc_float64(ctx, -0.0);

    if (prepare_compilation == 0) {
        value.stdlib_init(ctx, @ptrCast(@as([*]const c.JSWord, @ptrCast(stdlib_def.stdlib_table)) +
            @as(usize, @intCast(stdlib_def.global_object_offset))));
    }
    return ctx;
}

pub fn JS_NewContext(mem_start: *anyopaque, mem_size: usize, stdlib_def: *const c.JSSTDLibraryDef) *c.JSContext {
    return JS_NewContext2(mem_start, mem_size, stdlib_def, 0);
}

pub fn JS_FreeContext(ctx: *c.JSContext) void {
    const x = mc.ctxExt(ctx);
    var ptr: [*]u8 = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        const size = gc.get_mblock_size(ptr);
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(ptr));
        const class_id = mc.objectClassId(p);
        if (mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT and class_id >= c.JS_CLASS_USER) {
            const table: [*]const ?rt.JSCFinalizer = @ptrCast(@alignCast(x.c_finalizer_table));
            const fin = table[@intCast(class_id - c.JS_CLASS_USER)];
            if (fin != null) {
                fin.?(ctx, vt.objectUserOpaque(p).*);
            }
        }
        ptr += @as(usize, @intCast(size));
    }
}

pub fn JS_SetContextOpaque(ctx: *c.JSContext, opaque_val: ?*anyopaque) void {
    mc.ctxExt(ctx).opaque_val = opaque_val;
}

pub fn JS_GetContextOpaque(ctx: *c.JSContext) ?*anyopaque {
    return mc.ctxExt(ctx).opaque_val;
}

pub fn JS_SetInterruptHandler(ctx: *c.JSContext, interrupt_handler: ?*anyopaque) void {
    mc.ctxExt(ctx).interrupt_handler = interrupt_handler;
}

pub fn JS_SetLogFunc(ctx: *c.JSContext, write_func: ?mc.JSWriteFn) void {
    mc.ctxExt(ctx).write_func = write_func;
}

pub fn JS_SetRandomSeed(ctx: *c.JSContext, seed: u64) void {
    mc.ctxExt(ctx).random_state = seed;
}

pub fn JS_GetGlobalObject(ctx: *c.JSContext) c.JSValue {
    return mc.ctxExt(ctx).global_obj;
}

pub fn get_var_ref(ctx: *c.JSContext, pfirst_var_ref: *c.JSValue, pval: *c.JSValue) c.JSValue {
    var val = pfirst_var_ref.*;
    while (true) {
        if (val == c.JS_NULL)
            break;
        const p: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        std.debug.assert(!rt.varRefIsDetached(p));
        if (p.u.live.pvalue == pval)
            return val;
        val = p.u.live.next;
    }

    const p: *vt.JSVarRefExt = @ptrCast(@alignCast(
        utils.js_malloc(ctx, @intCast(@sizeOf(vt.JSVarRefExt)), mc.JS_MTAG_VARREF) orelse return c.JS_EXCEPTION,
    ));
    vt.varRefSetDetached(p, false);
    p.u.live.pvalue = pval;
    p.u.live.next = pfirst_var_ref.*;
    val = mc.valueFromPtr(p);
    pfirst_var_ref.* = val;
    return val;
}

pub fn reloc_c_func_name(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    _ = ctx;
    return val;
}

pub fn js_function_get_length_name1(ctx: *c.JSContext, this_val: *c.JSValue, is_name: c_int, pb: *?*rt.JSFunctionBytecodeExt) c.JSValue {
    var short_func_idx: c_int = undefined;
    if (!mc.isPtr(this_val.*)) {
        if (rt.valueGetSpecialTag(this_val.*) != c.JS_TAG_SHORT_FUNC)
            return fail(pb);
        short_func_idx = rt.valueGetSpecialValue(this_val.*);
        return short_func(ctx, short_func_idx, is_name, pb);
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(this_val.*)));
        if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT)
            return fail(pb);
        if (mc.objectClassId(p) == c.JS_CLASS_CLOSURE) {
            const b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.closure.func_bytecode)));
            const ret: c.JSValue = if (is_name != 0) blk: {
                if (b.func_name == c.JS_NULL)
                    break :blk utils.js_get_atom(ctx, c.JS_ATOM_empty)
                else
                    break :blk b.func_name;
            } else vt.newShortInt(rt.bytecodeArgCount(b));
            pb.* = b;
            return ret;
        } else if (mc.objectClassId(p) == c.JS_CLASS_C_FUNCTION) {
            short_func_idx = @intCast(p.u.cfunc.idx);
            return short_func(ctx, short_func_idx, is_name, pb);
        } else {
            return fail(pb);
        }
    }
}

fn fail(pb: *?*rt.JSFunctionBytecodeExt) c.JSValue {
    pb.* = null;
    return c.JS_NULL;
}

fn short_func(ctx: *c.JSContext, short_func_idx: c_int, is_name: c_int, pb: *?*rt.JSFunctionBytecodeExt) c.JSValue {
    const fd = &vt.cFunctionTable(mc.ctxExt(ctx))[@intCast(short_func_idx)];
    const ret: c.JSValue = if (is_name != 0)
        reloc_c_func_name(ctx, fd.name)
    else
        vt.newShortInt(fd.arg_count);
    pb.* = null;
    return ret;
}

pub fn get_bit(buf: [*]const u8, index: u32) u32 {
    return (buf[index >> 3] >> @as(u3, @intCast(7 - (index & 7)))) & 1;
}

pub fn get_bits_slow(buf: [*]const u8, index: u32, n: c_int) u32 {
    var val: u32 = 0;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        val |= get_bit(buf, index + @as(u32, @intCast(i))) << @as(u5, @intCast(n - 1 - i));
    }
    return val;
}

pub fn get_bits(buf: [*]const u8, buf_len: u32, index: u32, n: c_int) u32 {
    const pos = index >> 3;
    if (n > 25 or (pos + 3) >= buf_len) {
        return get_bits_slow(buf, index, n);
    } else {
        const val = get_be32(buf + pos);
        return (val >> @as(u5, @intCast(32 - @as(c_int, @intCast(index & 7)) - n))) & ((@as(u32, 1) << @as(u5, @intCast(n))) - 1);
    }
}

pub fn get_ugolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) u32 {
    var index = pindex.*;
    var i: c_int = 0;
    while (true) {
        if (get_bit(buf, index) != 0) {
            index += 1;
            break;
        }
        index += 1;
        i += 1;
        if (i == 32) {
            pindex.* = index;
            return 0xffffffff;
        }
    }
    var v: u32 = undefined;
    if (i == 0) {
        v = 0;
    } else {
        v = ((@as(u32, 1) << @as(u5, @intCast(i))) | get_bits(buf, buf_len, index, i)) - 1;
        index += @as(u32, @intCast(i));
    }
    pindex.* = index;
    return v;
}

pub fn get_sgolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) i32 {
    const val = get_ugolomb(buf, buf_len, pindex);
    return @as(i32, @bitCast(val >> 1)) ^ -@as(i32, @intCast(val & 1));
}

pub fn get_pc2line_hoisted_code_len(buf: [*]const u8, buf_len: usize) c_int {
    var i = buf_len;
    var v: c_int = 0;
    while (i > 0) {
        i -= 1;
        v = (v << 7) | @as(c_int, buf[i] & 0x7f);
        if ((buf[i] & 0x80) == 0)
            break;
    }
    return v;
}

pub fn get_pc2line(pline_num: *c_int, pcol_num: *c_int, buf: [*]const u8, buf_len: u32, pindex: *u32, has_column: c.JS_BOOL) void {
    var line_num = pline_num.*;
    var col_num = pcol_num.*;
    const line_delta = get_sgolomb(buf, buf_len, pindex);
    line_num += line_delta;
    if (has_column != 0) {
        if (line_delta == 0) {
            const col_delta = get_sgolomb(buf, buf_len, pindex);
            col_num += col_delta;
        } else {
            col_num = @as(c_int, @intCast(get_ugolomb(buf, buf_len, pindex))) + 1;
        }
    } else {
        col_num = 0;
    }
    pline_num.* = line_num;
    pcol_num.* = col_num;
}

pub fn find_line_col(pcol_num: *c_int, b: *rt.JSFunctionBytecodeExt, pc_in: u32) c_int {
    if (b.pc2line == c.JS_NULL) {
        pcol_num.* = 0;
        return 0;
    }
    const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.byte_code)));
    const pc2line: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.pc2line)));
    const pc2line_buf = vt.byteArrayBuf(pc2line);
    var pos: c_int = get_pc2line_hoisted_code_len(pc2line_buf, @intCast(vt.byteArraySize(pc2line)));
    var pc = pc_in;
    if (pc < @as(u32, @intCast(pos)))
        pc = @intCast(pos);
    var pc2line_pos: u32 = 0;
    var line_num: c_int = 1;
    var col_num: c_int = 1;
    const arr_buf = vt.byteArrayBuf(arr);
    const arr_size = vt.byteArraySize(arr);
    while (pos < arr_size) {
        get_pc2line(&line_num, &col_num, pc2line_buf, @intCast(vt.byteArraySize(pc2line)), &pc2line_pos, @intFromBool(rt.bytecodeHasColumn(b)));
        if (@as(u32, @intCast(pos)) == pc) {
            pcol_num.* = col_num;
            return line_num;
        }
        const op = arr_buf[@intCast(pos)];
        pos += rt.opcode_info_data[op].size;
    }
    pcol_num.* = 0;
    return 0;
}

pub fn get_func_name(ctx: *c.JSContext, func_obj: c.JSValue, str_buf: *c.JSCStringBuf, pb: *?*rt.JSFunctionBytecodeExt) ?[*:0]const u8 {
    var func = func_obj;
    const val = js_function_get_length_name1(ctx, &func, 1, pb);
    if (val == c.JS_NULL)
        return null;
    return value.JS_ToCString(ctx, val, str_buf);
}

fn cprintf(pp: *[*]u8, buf_end: [*]u8, fmt: [*:0]const u8, args: anytype) void {
    var p = pp.*;
    if (@intFromPtr(p) + 1 >= @intFromPtr(buf_end))
        return;
    const rem = @intFromPtr(buf_end) - @intFromPtr(p);
    _ = @call(.auto, utils.js_snprintf, .{ @as([*c]u8, @ptrCast(p)), rem, fmt } ++ args);
    p += std.mem.len(@as([*:0]const u8, @ptrCast(p)));
    pp.* = p;
}

pub fn build_backtrace(ctx: *c.JSContext, error_obj: c.JSValue, filename: ?[*:0]const u8, line_num: c_int, col_num: c_int, skip_level_in: c_int) void {
    if (value.JS_IsError(ctx, error_obj) == 0)
        return;
    var buf: [128]u8 = undefined;
    var p: [*]u8 = &buf;
    const buf_end: [*]u8 = @as([*]u8, &buf) + buf.len;
    p[0] = 0;
    if (filename) |fn_name| {
        cprintf(&p, buf_end, "    at %s:%d:%d\n", .{ fn_name, line_num, col_num });
    }
    var fp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).fp);
    var level: c_int = 0;
    var skip_level = skip_level_in;
    while (@intFromPtr(fp) != @intFromPtr(mc.ctxExt(ctx).stack_top) and level < 10) {
        if (skip_level != 0) {
            skip_level -= 1;
        } else {
            const line_start = p;
            var str_buf: c.JSCStringBuf = undefined;
            var b: ?*rt.JSFunctionBytecodeExt = null;
            var str = get_func_name(ctx, rt.slot(fp, rt.FRAME_OFFSET_FUNC_OBJ).*, &str_buf, &b);
            if (str == null)
                str = "<anonymous>";
            cprintf(&p, buf_end, "    at %s", .{str.?});
            if (b) |bb| {
                const filename2 = value.JS_ToCString(ctx, bb.filename, &str_buf).?;
                const pc_off = vt.valueGetInt(rt.slot(fp, rt.FRAME_OFFSET_CUR_PC).*) - 1;
                var col2: c_int = 0;
                const line2 = find_line_col(&col2, bb, @intCast(pc_off));
                cprintf(&p, buf_end, " (%s", .{filename2});
                if (line2 != 0) {
                    cprintf(&p, buf_end, ":%d", .{line2});
                    if (col2 != 0)
                        cprintf(&p, buf_end, ":%d", .{col2});
                }
                cprintf(&p, buf_end, ")", .{});
            } else {
                cprintf(&p, buf_end, " (native)", .{});
            }
            cprintf(&p, buf_end, "\n", .{});
            if (@intFromPtr(p) + 1 >= @intFromPtr(buf_end)) {
                line_start[0] = 0;
                break;
            }
            level += 1;
        }
        fp = rt.valueToSp(ctx, rt.slot(fp, rt.FRAME_OFFSET_SAVED_FP).*);
    }

    var error_obj_ref: c.JSGCRef = undefined;
    var error_obj_mut = error_obj;
    utils.pushValue(ctx, &error_obj_ref, error_obj_mut);
    const stack_str = value.JS_NewString(ctx, @ptrCast(&buf));
    error_obj_mut = utils.popValue(ctx, &error_obj_ref);
    const p1: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(error_obj_mut)));
    p1.u.err.stack = stack_str;
}


pub fn JS_PushArg(ctx: *c.JSContext, val: c.JSValue) void {
    const x = mc.ctxExt(ctx);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    x.sp = @ptrCast(sp - 1);
    x.sp.* = val;
}
