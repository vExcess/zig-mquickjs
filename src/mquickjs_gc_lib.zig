//
// Micro QuickJS engine garbage collector (shared implementation)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const utils = @import("mquickjs_utils_lib.zig");
const gt = @import("mquickjs_gc_types.zig");
const rt = gt.rt;
const vt = gt.vt;
const mc = gt.mc;
pub const c = gt.c;

const JSParseState = gt.JSParseState;

extern fn js_rehash_props(ctx: *c.JSContext, p: *anyopaque, gc_rehash: c.JS_BOOL) void;
extern fn find_atom(ctx: *c.JSContext, pidx: *c_int, arr: *const anyopaque, len: c_int, val: c.JSValue) c.JSValue;
extern fn js_get_short_float(v: c.JSValue) f64;

inline fn cx(ctx: *c.JSContext) *mc.JSContextExt {
    return mc.ctxExt(ctx);
}

fn classProtoBase(x: *mc.JSContextExt) [*]c.JSValue {
    return @ptrCast(@alignCast(&x.class_proto));
}

fn classObjBase(x: *mc.JSContextExt) [*]c.JSValue {
    return @ptrCast(x.class_obj.?);
}

fn ptrDiffValues(a: [*]c.JSValue, b: [*]c.JSValue) isize {
    return @divExact(@as(isize, @bitCast(@intFromPtr(a))) - @as(isize, @bitCast(@intFromPtr(b))), @sizeOf(c.JSValue));
}

pub fn get_mblock_size(ptr: *const anyopaque) c_int {
    const mtag = mc.mbGetMtag(@constCast(ptr));
    var size: c_int = 0;
    switch (mtag) {
        mc.JS_MTAG_OBJECT => {
            const p: *const mc.JSObjectExt = @ptrCast(@alignCast(ptr));
            size = @intCast(vt.objectOffsetOfU() + @as(c_uint, @intCast(gt.objectExtraSize(p))) * c.JSW);
        },
        mc.JS_MTAG_FLOAT64 => {
            size = @intCast(@sizeOf(vt.JSFloat64Ext));
        },
        mc.JS_MTAG_STRING => {
            const p: *const vt.JSStringExt = @ptrCast(@alignCast(ptr));
            const len = vt.stringLen(p);
            const mask: usize = ~@as(usize, c.JSW - 1);
            size = @intCast(@sizeOf(vt.JSStringExt) + ((len + c.JSW) & mask));
        },
        mc.JS_MTAG_BYTE_ARRAY => {
            const p: *const vt.JSByteArrayExt = @ptrCast(@alignCast(ptr));
            const arr_size: usize = @intCast(vt.byteArraySize(p));
            const mask: usize = ~@as(usize, c.JSW - 1);
            size = @intCast(@sizeOf(vt.JSByteArrayExt) + ((arr_size + c.JSW - 1) & mask));
        },
        mc.JS_MTAG_VALUE_ARRAY => {
            const p: *const vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
            const n: usize = @intCast(vt.valueArraySize(p));
            size = @intCast(@sizeOf(vt.JSValueArrayExt) + n * @sizeOf(c.JSValue));
        },
        mc.JS_MTAG_FREE => {
            const words = gt.freeBlockSizeWords(ptr);
            size = @intCast(@sizeOf(c.JSWord) + words * @sizeOf(c.JSWord));
        },
        mc.JS_MTAG_VARREF => {
            const p: *const vt.JSVarRefExt = @ptrCast(@alignCast(ptr));
            size = @intCast(@sizeOf(vt.JSVarRefExt));
            if (rt.varRefIsDetached(p))
                size -= @intCast(@sizeOf(c.JSValue));
        },
        mc.JS_MTAG_FUNCTION_BYTECODE => {
            size = @intCast(@sizeOf(rt.JSFunctionBytecodeExt));
        },
        else => {
            size = 0;
            std.debug.assert(false);
        },
    }
    return size;
}

pub fn mtag_has_references(mtag: c_int) bool {
    return (mtag == mc.JS_MTAG_OBJECT or
        mtag == mc.JS_MTAG_VALUE_ARRAY or
        mtag == mc.JS_MTAG_VARREF or
        mtag == mc.JS_MTAG_FUNCTION_BYTECODE);
}

pub fn gc_mark(s: *gt.GCMarkState, val: c.JSValue) void {
    const ctx = s.ctx;

    if (!mc.isPtr(val))
        return;
    const ptr = mc.valueToPtr(val);
    if (gt.isRomPtr(ctx, ptr))
        return;
    if (gt.mbGcMark(ptr))
        return;
    gt.mbSetGcMark(ptr, true);
    if (mtag_has_references(mc.mbGetMtag(ptr))) {
        if (mc.mbGetMtag(ptr) == mc.JS_MTAG_VALUE_ARRAY) {
            if (ptrDiffValues(s.gsp, s.gs_bottom) < 2) {
                s.overflow = c.TRUE;
            } else {
                s.gsp -= 1;
                s.gsp[0] = 0;
                s.gsp -= 1;
                s.gsp[0] = val;
            }
        } else {
            if (ptrDiffValues(s.gsp, s.gs_bottom) < 1) {
                s.overflow = c.TRUE;
            } else {
                s.gsp -= 1;
                s.gsp[0] = val;
            }
        }
    }
}

pub fn gc_mark_flush(s: *gt.GCMarkState) void {
    while (@intFromPtr(s.gsp) < @intFromPtr(s.gs_top)) {
        const val = s.gsp[0];
        s.gsp += 1;
        const ptr = mc.valueToPtr(val);

        switch (mc.mbGetMtag(ptr)) {
            mc.JS_MTAG_OBJECT => {
                const p: *const mc.JSObjectExt = @ptrCast(@alignCast(ptr));
                gc_mark(s, p.proto);
                gc_mark(s, p.props);
                switch (mc.objectClassId(p)) {
                    c.JS_CLASS_CLOSURE => {
                        gc_mark(s, p.u.closure.func_bytecode);
                        const extra = gt.objectExtraSize(p);
                        var i: c.JSWord = 0;
                        while (i < extra - 1) : (i += 1) {
                            gc_mark(s, rt.closureVarRefs(@constCast(p))[@intCast(i)]);
                        }
                    },
                    c.JS_CLASS_C_FUNCTION => {
                        if (gt.objectExtraSize(p) > 1)
                            gc_mark(s, p.u.cfunc.params);
                    },
                    c.JS_CLASS_ARRAY => {
                        gc_mark(s, p.u.array.tab);
                    },
                    c.JS_CLASS_ERROR => {
                        gc_mark(s, p.u.err.message);
                        gc_mark(s, p.u.err.stack);
                    },
                    c.JS_CLASS_ARRAY_BUFFER => {
                        gc_mark(s, p.u.array_buffer.byte_buffer);
                    },
                    c.JS_CLASS_UINT8C_ARRAY,
                    c.JS_CLASS_INT8_ARRAY,
                    c.JS_CLASS_UINT8_ARRAY,
                    c.JS_CLASS_INT16_ARRAY,
                    c.JS_CLASS_UINT16_ARRAY,
                    c.JS_CLASS_INT32_ARRAY,
                    c.JS_CLASS_UINT32_ARRAY,
                    c.JS_CLASS_FLOAT32_ARRAY,
                    c.JS_CLASS_FLOAT64_ARRAY,
                    => {
                        gc_mark(s, p.u.typed_array.buffer);
                    },
                    c.JS_CLASS_REGEXP => {
                        const re = rt.objectRegexp(@constCast(p));
                        gc_mark(s, re.source);
                        gc_mark(s, re.byte_code);
                    },
                    else => {},
                }
            },
            mc.JS_MTAG_VALUE_ARRAY => {
                const p: *const vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
                var pos: c_int = @intCast(s.gsp[0]);
                s.gsp += 1;

                const arr = vt.valueArrayItems(p);
                const arr_size = vt.valueArraySize(p);
                while (pos < arr_size and !mc.isPtr(arr[@intCast(pos)]))
                    pos += 1;

                if (pos < arr_size) {
                    if ((pos + 1) < arr_size) {
                        s.gsp -= 1;
                        s.gsp[0] = @intCast(pos + 1);
                        s.gsp -= 1;
                        s.gsp[0] = val;
                    }
                    gc_mark(s, arr[@intCast(pos)]);
                }
            },
            mc.JS_MTAG_VARREF => {
                const p: *const vt.JSVarRefExt = @ptrCast(@alignCast(ptr));
                gc_mark(s, p.u.value);
            },
            mc.JS_MTAG_FUNCTION_BYTECODE => {
                const b: *const rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(ptr));
                gc_mark(s, b.func_name);
                gc_mark(s, b.byte_code);
                gc_mark(s, b.cpool);
                gc_mark(s, b.vars);
                gc_mark(s, b.ext_vars);
                gc_mark(s, b.filename);
                gc_mark(s, b.pc2line);
            },
            else => {},
        }
    }
}

pub fn gc_mark_root(s: *gt.GCMarkState, val: c.JSValue) void {
    gc_mark(s, val);
    gc_mark_flush(s);
}

pub fn gc_mb_is_marked(val: c.JSValue) c.JS_BOOL {
    if (!mc.isPtr(val))
        return c.FALSE;
    return @intFromBool(gt.mbGcMark(mc.valueToPtr(val)));
}

pub fn gc_mark_all(ctx: *c.JSContext, keep_atoms: c.JS_BOOL) void {
    var s_s: gt.GCMarkState = undefined;
    const s = &s_s;
    const x = cx(ctx);

    s.ctx = ctx;
    s.overflow = c.FALSE;
    s.gs_top = @ptrCast(x.sp);
    s.gsp = s.gs_top;
    s.gs_bottom = @ptrCast(@alignCast(x.heap_free));

    if (@intFromPtr(x.atom_table) == @intFromPtr(x.heap_base) and keep_atoms != 0) {
        var ptr: [*]u8 = @ptrCast(@constCast(x.atom_table));
        const end = @intFromPtr(x.atom_table) + @as(usize, @intCast(c.JS_ATOM_END)) * @sizeOf(c.JSWord);
        while (@intFromPtr(ptr) < end) {
            gc_mark_root(s, mc.valueFromPtr(ptr));
            ptr += @intCast(get_mblock_size(ptr));
        }
    }

    const proto = classProtoBase(x);
    const sp_end = proto + @as(usize, @intCast(2 * x.class_count));
    var sp: [*]c.JSValue = @ptrCast(&x.current_exception);
    while (@intFromPtr(sp) < @intFromPtr(sp_end)) : (sp += 1) {
        gc_mark_root(s, sp[0]);
    }

    sp = @ptrCast(x.sp);
    const stack_top: [*]c.JSValue = @ptrCast(@alignCast(x.stack_top));
    while (@intFromPtr(sp) < @intFromPtr(stack_top)) : (sp += 1) {
        gc_mark_root(s, sp[0]);
    }

    {
        var ref = x.top_gc_ref;
        while (ref) |r| {
            gc_mark_root(s, r.val);
            ref = r.prev;
        }
        ref = x.last_gc_ref;
        while (ref) |r| {
            gc_mark_root(s, r.val);
            ref = r.prev;
        }
    }

    if (x.parse_state) |ps_ptr| {
        const ps: *JSParseState = @ptrCast(@alignCast(ps_ptr));
        gc_mark_root(s, ps.source_str);
        gc_mark_root(s, ps.filename_str);
        gc_mark_root(s, ps.token.value);
        gc_mark_root(s, ps.cur_func);
        gc_mark_root(s, ps.byte_code);
    }

    while (s.overflow != 0) {
        s.overflow = c.FALSE;

        var ptr: [*]u8 = x.heap_base;
        while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
            const size = get_mblock_size(ptr);
            if (gt.mbGcMark(ptr) and mtag_has_references(mc.mbGetMtag(ptr))) {
                if (mc.mbGetMtag(ptr) == mc.JS_MTAG_VALUE_ARRAY) {
                    s.gsp -= 1;
                    s.gsp[0] = 0;
                }
                s.gsp -= 1;
                s.gsp[0] = mc.valueFromPtr(ptr);
                gc_mark_flush(s);
            }
            ptr += @intCast(size);
        }
    }

    if (!mc.isNull(x.unique_strings)) {
        const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(x.unique_strings)));
        const items = vt.valueArrayItems(arr);
        var j: c_int = 0;
        var i: c_int = 0;
        while (i < vt.valueArraySize(arr)) : (i += 1) {
            if (gc_mb_is_marked(items[@intCast(i)]) != 0) {
                items[@intCast(j)] = items[@intCast(i)];
                j += 1;
            }
        }
        x.unique_strings_len = j;
        if (j > 0) {
            gt.mbSetGcMark(arr, true);
            if (j < vt.valueArraySize(arr)) {
                utils.set_free_block(@ptrCast(&items[@intCast(j)]), @intCast(@as(usize, @intCast(vt.valueArraySize(arr) - j)) * @sizeOf(c.JSValue)));
                vt.valueArraySetSize(arr, j);
            }
        } else {
            gt.mbSetGcMark(arr, false);
            x.unique_strings = c.JS_NULL;
        }
    }

    {
        var i: usize = 0;
        while (i < vt.JS_STRING_POS_CACHE_SIZE) : (i += 1) {
            const ce = &x.string_pos_cache[i];
            if (gc_mb_is_marked(ce.str) == 0)
                ce.str = c.JS_NULL;
        }
    }

    {
        var ptr: [*]u8 = x.heap_base;
        while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
            var size = get_mblock_size(ptr);
            if (gt.mbGcMark(ptr)) {
                gt.mbSetGcMark(ptr, false);
            } else {
                const p: *mc.JSObjectExt = @ptrCast(@alignCast(ptr));
                if (mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT and mc.objectClassId(p) >= c.JS_CLASS_USER) {
                    const table: [*]const ?rt.JSCFinalizer = @ptrCast(@alignCast(x.c_finalizer_table));
                    const idx: usize = @intCast(mc.objectClassId(p) - c.JS_CLASS_USER);
                    if (table[idx]) |fin| {
                        fin(ctx, vt.objectUserOpaque(p).*);
                    }
                }
                var ptr1 = ptr + @as(usize, @intCast(size));
                while (@intFromPtr(ptr1) < @intFromPtr(x.heap_free) and !gt.mbGcMark(ptr1)) {
                    ptr1 += @intCast(get_mblock_size(ptr1));
                }
                size = @intCast(@intFromPtr(ptr1) - @intFromPtr(ptr));
                utils.set_free_block(ptr, @intCast(size));
            }
            ptr += @intCast(size);
        }
    }
}

pub fn js_value_from_pval(ctx: *c.JSContext, pval: *c.JSValue) c.JSValue {
    _ = ctx;
    return mc.valueFromPtr(pval);
}

pub fn js_value_to_pval(ctx: *c.JSContext, val: c.JSValue) *c.JSValue {
    _ = ctx;
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

pub fn gc_thread_pointer(ctx: *c.JSContext, pval: *c.JSValue) void {
    const val = pval.*;
    if (!mc.isPtr(val))
        return;
    const ptr: *c.JSValue = @ptrCast(@alignCast(mc.valueToPtr(val)));
    if (gt.isRomPtr(ctx, ptr))
        return;
    pval.* = ptr.*;
    ptr.* = js_value_from_pval(ctx, pval);
}

pub fn gc_update_threaded_pointers(ctx: *c.JSContext, ptr: *anyopaque, new_ptr: *anyopaque) void {
    var val = @as(*c.JSValue, @ptrCast(@alignCast(ptr))).*;
    if (mc.isPtr(val)) {
        while (true) {
            const pv = js_value_to_pval(ctx, val);
            val = pv.*;
            pv.* = mc.valueFromPtr(new_ptr);
            if (!mc.isPtr(val))
                break;
        }
        @as(*c.JSValue, @ptrCast(@alignCast(ptr))).* = val;
    }
}

pub fn gc_thread_block(ctx: *c.JSContext, ptr: *anyopaque) void {
    const mtag = mc.mbGetMtag(ptr);
    switch (mtag) {
        mc.JS_MTAG_OBJECT => {
            const p: *mc.JSObjectExt = @ptrCast(@alignCast(ptr));
            gc_thread_pointer(ctx, &p.proto);
            gc_thread_pointer(ctx, &p.props);
            switch (mc.objectClassId(p)) {
                c.JS_CLASS_CLOSURE => {
                    gc_thread_pointer(ctx, &p.u.closure.func_bytecode);
                    const extra = gt.objectExtraSize(p);
                    var i: c.JSWord = 0;
                    while (i < extra - 1) : (i += 1) {
                        gc_thread_pointer(ctx, &rt.closureVarRefs(p)[@intCast(i)]);
                    }
                },
                c.JS_CLASS_C_FUNCTION => {
                    if (gt.objectExtraSize(p) > 1)
                        gc_thread_pointer(ctx, &p.u.cfunc.params);
                },
                c.JS_CLASS_ARRAY => {
                    gc_thread_pointer(ctx, &p.u.array.tab);
                },
                c.JS_CLASS_ERROR => {
                    gc_thread_pointer(ctx, &p.u.err.message);
                    gc_thread_pointer(ctx, &p.u.err.stack);
                },
                c.JS_CLASS_ARRAY_BUFFER => {
                    gc_thread_pointer(ctx, &p.u.array_buffer.byte_buffer);
                },
                c.JS_CLASS_UINT8C_ARRAY,
                c.JS_CLASS_INT8_ARRAY,
                c.JS_CLASS_UINT8_ARRAY,
                c.JS_CLASS_INT16_ARRAY,
                c.JS_CLASS_UINT16_ARRAY,
                c.JS_CLASS_INT32_ARRAY,
                c.JS_CLASS_UINT32_ARRAY,
                c.JS_CLASS_FLOAT32_ARRAY,
                c.JS_CLASS_FLOAT64_ARRAY,
                => {
                    gc_thread_pointer(ctx, &p.u.typed_array.buffer);
                },
                c.JS_CLASS_REGEXP => {
                    const re = rt.objectRegexp(p);
                    gc_thread_pointer(ctx, &re.source);
                    gc_thread_pointer(ctx, &re.byte_code);
                },
                else => {},
            }
        },
        mc.JS_MTAG_VALUE_ARRAY => {
            const p: *vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
            const items = vt.valueArrayItems(p);
            var i: c_int = 0;
            while (i < vt.valueArraySize(p)) : (i += 1) {
                gc_thread_pointer(ctx, &items[@intCast(i)]);
            }
        },
        mc.JS_MTAG_VARREF => {
            const p: *vt.JSVarRefExt = @ptrCast(@alignCast(ptr));
            gc_thread_pointer(ctx, &p.u.value);
        },
        mc.JS_MTAG_FUNCTION_BYTECODE => {
            const b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(ptr));
            gc_thread_pointer(ctx, &b.func_name);
            gc_thread_pointer(ctx, &b.byte_code);
            gc_thread_pointer(ctx, &b.cpool);
            gc_thread_pointer(ctx, &b.vars);
            gc_thread_pointer(ctx, &b.ext_vars);
            gc_thread_pointer(ctx, &b.filename);
            gc_thread_pointer(ctx, &b.pc2line);
        },
        else => {},
    }
}

pub fn gc_compact_heap(ctx: *c.JSContext) void {
    const x = cx(ctx);

    const proto = classProtoBase(x);
    const sp_end = proto + @as(usize, @intCast(2 * x.class_count));
    var sp: [*]c.JSValue = @ptrCast(&x.unique_strings);
    while (@intFromPtr(sp) < @intFromPtr(sp_end)) : (sp += 1) {
        gc_thread_pointer(ctx, &sp[0]);
    }

    {
        var i: usize = 0;
        while (i < vt.JS_STRING_POS_CACHE_SIZE) : (i += 1) {
            gc_thread_pointer(ctx, &x.string_pos_cache[i].str);
        }
    }

    sp = @ptrCast(x.sp);
    const stack_top: [*]c.JSValue = @ptrCast(@alignCast(x.stack_top));
    while (@intFromPtr(sp) < @intFromPtr(stack_top)) : (sp += 1) {
        gc_thread_pointer(ctx, &sp[0]);
    }

    {
        var ref = x.top_gc_ref;
        while (ref) |r| {
            gc_thread_pointer(ctx, &r.val);
            ref = r.prev;
        }
        ref = x.last_gc_ref;
        while (ref) |r| {
            gc_thread_pointer(ctx, &r.val);
            ref = r.prev;
        }
    }

    if (x.parse_state) |ps_ptr| {
        const ps: *JSParseState = @ptrCast(@alignCast(ps_ptr));
        gc_thread_pointer(ctx, &ps.source_str);
        gc_thread_pointer(ctx, &ps.filename_str);
        gc_thread_pointer(ctx, &ps.token.value);
        gc_thread_pointer(ctx, &ps.cur_func);
        gc_thread_pointer(ctx, &ps.byte_code);
    }

    var new_ptr: [*]u8 = x.heap_base;
    var ptr: [*]u8 = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        gc_update_threaded_pointers(ctx, ptr, new_ptr);
        const size = get_mblock_size(ptr);
        if (utils.js_get_mtag(ptr) != mc.JS_MTAG_FREE) {
            gc_thread_block(ctx, ptr);
            new_ptr += @intCast(size);
        }
        ptr += @intCast(size);
    }

    new_ptr = x.heap_base;
    ptr = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        gc_update_threaded_pointers(ctx, ptr, new_ptr);
        const size = get_mblock_size(ptr);
        if (utils.js_get_mtag(ptr) != mc.JS_MTAG_FREE) {
            if (@intFromPtr(new_ptr) != @intFromPtr(ptr)) {
                @memmove(new_ptr[0..@intCast(size)], ptr[0..@intCast(size)]);
            }
            new_ptr += @intCast(size);
        }
        ptr += @intCast(size);
    }
    x.heap_free = new_ptr;

    if (x.parse_state) |ps_ptr| {
        const ps: *JSParseState = @ptrCast(@alignCast(ps_ptr));
        if (mc.isPtr(ps.source_str)) {
            const p: *const vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(ps.source_str)));
            ps.source_buf = vt.stringBuf(p);
        }
    }

    ptr = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        const size = get_mblock_size(ptr);
        if (utils.js_get_mtag(ptr) == mc.JS_MTAG_OBJECT) {
            js_rehash_props(ctx, ptr, c.TRUE);
        }
        ptr += @intCast(size);
    }
}

pub fn JS_GC2(ctx: *c.JSContext, keep_atoms: c.JS_BOOL) void {
    gc_mark_all(ctx, keep_atoms);
    gc_compact_heap(ctx);
}

pub fn JS_GC(ctx: *c.JSContext) void {
    JS_GC2(ctx, c.TRUE);
}

pub fn JS_PrepareBytecode(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code_in: c.JSValue,
) void {
    const x = cx(ctx);
    var eval_code = eval_code_in;
    var eval_code_ref: c.JSGCRef = undefined;

    x.empty_props = c.JS_NULL;
    var i: u16 = 0;
    while (i < x.class_count) : (i += 1) {
        classProtoBase(x)[i] = c.JS_NULL;
        classObjBase(x)[i] = c.JS_NULL;
    }
    x.global_obj = c.JS_NULL;

    _ = utils.JS_PushGCRef(ctx, &eval_code_ref);
    eval_code_ref.val = eval_code;
    JS_GC2(ctx, c.FALSE);
    eval_code = utils.JS_PopGCRef(ctx, &eval_code_ref);

    hdr.magic = gt.JS_BYTECODE_MAGIC;
    hdr.version = gt.JS_BYTECODE_VERSION;
    hdr.base_addr = @intFromPtr(x.heap_base);
    hdr.unique_strings = x.unique_strings;
    hdr.main_func = eval_code;

    pdata_buf.* = x.heap_base;
    pdata_len.* = @intCast(@intFromPtr(x.heap_free) - @intFromPtr(x.heap_base));
}

fn convert_mblock_64to32(ptr1: *anyopaque, ptr: *const anyopaque) c_int {
    const mtag = mc.mbGetMtag(@constCast(ptr));
    switch (mtag) {
        mc.JS_MTAG_FUNCTION_BYTECODE => {
            const b: *const rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(ptr));
            const b1: *gt.JSFunctionBytecode_32 = @ptrCast(@alignCast(ptr1));
            const mark_bit: u32 = if (gt.mbGcMark(ptr)) 1 else 0;
            b1.header = mark_bit |
                (@as(u32, @intCast(mtag)) << 1) |
                (@as(u32, @intFromBool(gt.bytecodeHasArguments(b))) << 4) |
                (@as(u32, @intFromBool(gt.bytecodeHasLocalFuncName(b))) << 5) |
                (@as(u32, @intFromBool(rt.bytecodeHasColumn(b))) << 6) |
                (@as(u32, @intCast(rt.bytecodeArgCount(b))) << 7);
            b1.func_name = gt.valueToU32(b.func_name);
            b1.byte_code = gt.valueToU32(b.byte_code);
            b1.cpool = gt.valueToU32(b.cpool);
            b1.vars = gt.valueToU32(b.vars);
            b1.ext_vars = gt.valueToU32(b.ext_vars);
            b1.stack_size = b.stack_size;
            b1.ext_vars_len = b.ext_vars_len;
            b1.filename = gt.valueToU32(b.filename);
            b1.pc2line = gt.valueToU32(b.pc2line);
            b1.source_pos = b.source_pos;
        },
        mc.JS_MTAG_FLOAT64 => {
            const b: *const vt.JSFloat64Ext = @ptrCast(@alignCast(ptr));
            const dest: [*]u8 = @ptrCast(ptr1);
            const mark_bit: u32 = if (gt.mbGcMark(ptr)) 1 else 0;
            const header: u32 = mark_bit | (@as(u32, @intCast(mtag)) << 1);
            @memcpy(dest[0..4], std.mem.asBytes(&header));
            @memcpy(dest[4..12], std.mem.asBytes(&b.dval));
        },
        mc.JS_MTAG_VALUE_ARRAY => {
            const b: *const vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
            const b1: *gt.JSValueArray_32 = @ptrCast(@alignCast(ptr1));
            const mark_bit: u32 = if (gt.mbGcMark(ptr)) 1 else 0;
            const arr_size = vt.valueArraySize(b);
            b1.header = mark_bit | (@as(u32, @intCast(mtag)) << 1) | (@as(u32, @intCast(arr_size)) << 4);
            const src = vt.valueArrayItems(b);
            const dst: [*]u32 = @ptrCast(@alignCast(&b1.arr));
            var i: c_int = 0;
            while (i < arr_size) : (i += 1) {
                dst[@intCast(i)] = gt.valueToU32(src[@intCast(i)]);
            }
        },
        mc.JS_MTAG_BYTE_ARRAY => {
            const b: *const vt.JSByteArrayExt = @ptrCast(@alignCast(ptr));
            const b1: *gt.JSByteArray_32 = @ptrCast(@alignCast(ptr1));
            const mark_bit: u32 = if (gt.mbGcMark(ptr)) 1 else 0;
            const arr_size = vt.byteArraySize(b);
            b1.header = mark_bit | (@as(u32, @intCast(mtag)) << 1) | (@as(u32, @intCast(arr_size)) << 4);
            const n: usize = @intCast(arr_size);
            @memmove((@as([*]u8, @ptrCast(&b1.buf)))[0..n], vt.byteArrayBuf(b)[0..n]);
        },
        mc.JS_MTAG_STRING => {
            const b: *const vt.JSStringExt = @ptrCast(@alignCast(ptr));
            const b1: *gt.JSString_32 = @ptrCast(@alignCast(ptr1));
            const len = vt.stringLen(b);
            if (len > gt.JS_STRING_LEN_MAX_32)
                return -1;
            const mark_bit: u32 = if (gt.mbGcMark(ptr)) 1 else 0;
            b1.header = mark_bit |
                (@as(u32, @intCast(mtag)) << 1) |
                (@as(u32, @intFromBool(vt.stringIsUnique(b))) << 4) |
                (@as(u32, @intFromBool(vt.stringIsAscii(b))) << 5) |
                (@as(u32, @intFromBool(vt.stringIsNumeric(b))) << 6) |
                (@as(u32, @intCast(len)) << 7);
            @memmove((@as([*]u8, @ptrCast(&b1.buf)))[0 .. len + 1], vt.stringBuf(b)[0 .. len + 1]);
        },
        else => {
            std.process.abort();
        },
    }
    return 0;
}

fn get_mblock_size_32(ptr: *const anyopaque) c_int {
    const mtag = gt.mb32GetMtag(ptr);
    var size: c_int = 0;
    switch (mtag) {
        mc.JS_MTAG_FLOAT64 => {
            size = @intCast(@sizeOf(gt.JSFloat64_32));
        },
        mc.JS_MTAG_STRING => {
            const p: *const gt.JSString_32 = @ptrCast(@alignCast(ptr));
            const len = gt.string32Len(p);
            const mask: u32 = ~@as(u32, 4 - 1);
            size = @intCast(@sizeOf(gt.JSString_32) + ((len + 4) & mask));
        },
        mc.JS_MTAG_BYTE_ARRAY => {
            const p: *const gt.JSByteArray_32 = @ptrCast(@alignCast(ptr));
            const arr_size = gt.byteArray32Size(p);
            const mask: u32 = ~@as(u32, 4 - 1);
            size = @intCast(@sizeOf(gt.JSByteArray_32) + ((arr_size + 4 - 1) & mask));
        },
        mc.JS_MTAG_VALUE_ARRAY => {
            const p: *const gt.JSValueArray_32 = @ptrCast(@alignCast(ptr));
            const n = gt.valueArray32Size(p);
            size = @intCast(@sizeOf(gt.JSValueArray_32) + n * @sizeOf(u32));
        },
        mc.JS_MTAG_FUNCTION_BYTECODE => {
            size = @intCast(@sizeOf(gt.JSFunctionBytecode_32));
        },
        else => {
            size = 0;
            std.debug.assert(false);
        },
    }
    return size;
}

fn gc_compact_heap_64to32(ctx: *c.JSContext) c_int {
    const x = cx(ctx);

    gc_thread_pointer(ctx, &x.unique_strings);

    {
        var ref = x.top_gc_ref;
        while (ref) |r| {
            gc_thread_pointer(ctx, &r.val);
            ref = r.prev;
        }
    }

    var new_offset: usize = 0;
    var ptr: [*]u8 = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        gc_update_threaded_pointers(ctx, ptr, @ptrFromInt(new_offset));
        const size = get_mblock_size(ptr);
        if (utils.js_get_mtag(ptr) != mc.JS_MTAG_FREE) {
            gc_thread_block(ctx, ptr);
            const size_32 = get_mblock_size_32(ptr);
            new_offset += @intCast(size_32);
        }
        ptr += @intCast(size);
    }

    new_offset = 0;
    ptr = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        gc_update_threaded_pointers(ctx, ptr, @ptrFromInt(new_offset));
        const size = get_mblock_size(ptr);
        if (utils.js_get_mtag(ptr) != mc.JS_MTAG_FREE) {
            const size_32 = get_mblock_size_32(ptr);
            if (convert_mblock_64to32(x.heap_base + new_offset, ptr) != 0)
                return -1;
            new_offset += @intCast(size_32);
        }
        ptr += @intCast(size);
    }
    x.heap_free = x.heap_base + new_offset;
    return 0;
}

fn expand_short_float(ctx: *c.JSContext, pval: *c.JSValue) c_int {
    if (mc.isShortFloat(pval.*)) {
        const f = utils.js_malloc(ctx, @intCast(@sizeOf(vt.JSFloat64Ext)), mc.JS_MTAG_FLOAT64) orelse
            return -1;
        const fp: *vt.JSFloat64Ext = @ptrCast(@alignCast(f));
        fp.dval = js_get_short_float(pval.*);
        pval.* = mc.valueFromPtr(f);
    }
    return 0;
}

fn expand_short_floats(ctx: *c.JSContext) c_int {
    const x = cx(ctx);
    var ptr: [*]u8 = x.heap_base;
    const p_end = x.heap_free;
    while (@intFromPtr(ptr) < @intFromPtr(p_end)) {
        const size = get_mblock_size(ptr);
        const mtag = mc.mbGetMtag(ptr);
        switch (mtag) {
            mc.JS_MTAG_FUNCTION_BYTECODE => {},
            mc.JS_MTAG_VALUE_ARRAY => {
                const p: *vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
                const items = vt.valueArrayItems(p);
                var i: c_int = 0;
                while (i < vt.valueArraySize(p)) : (i += 1) {
                    if (expand_short_float(ctx, &items[@intCast(i)]) != 0)
                        return -1;
                }
            },
            mc.JS_MTAG_STRING, mc.JS_MTAG_FLOAT64, mc.JS_MTAG_BYTE_ARRAY => {},
            else => {
                std.process.abort();
            },
        }
        ptr += @intCast(size);
    }
    return 0;
}

pub fn JS_PrepareBytecode64to32(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader32,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code_in: c.JSValue,
) c_int {
    const x = cx(ctx);
    var eval_code = eval_code_in;
    var eval_code_ref: c.JSGCRef = undefined;

    x.empty_props = c.JS_NULL;
    var i: u16 = 0;
    while (i < x.class_count) : (i += 1) {
        classProtoBase(x)[i] = c.JS_NULL;
        classObjBase(x)[i] = c.JS_NULL;
    }
    x.global_obj = c.JS_NULL;

    _ = utils.JS_PushGCRef(ctx, &eval_code_ref);
    eval_code_ref.val = eval_code;
    JS_GC2(ctx, c.FALSE);
    if (expand_short_floats(ctx) != 0)
        return -1;
    if (gc_compact_heap_64to32(ctx) != 0)
        return -1;
    eval_code = utils.JS_PopGCRef(ctx, &eval_code_ref);

    hdr.magic = gt.JS_BYTECODE_MAGIC;
    hdr.version = gt.JS_BYTECODE_VERSION_32;
    hdr.base_addr = 0;
    hdr.unique_strings = gt.valueToU32(x.unique_strings);
    hdr.main_func = gt.valueToU32(eval_code);

    pdata_buf.* = x.heap_base;
    pdata_len.* = @intCast(@intFromPtr(x.heap_free) - @intFromPtr(x.heap_base));
    x.heap_free = x.heap_base;
    return 0;
}

pub fn JS_IsBytecode(buf: [*]const u8, buf_len: usize) c.JS_BOOL {
    if (buf_len < @sizeOf(gt.JSBytecodeHeader))
        return c.FALSE;
    const hdr: *const gt.JSBytecodeHeader = @ptrCast(@alignCast(buf));
    return @intFromBool(hdr.magic == gt.JS_BYTECODE_MAGIC);
}

pub fn bc_reloc_value(s: *gt.BCRelocState, pval: *c.JSValue) void {
    const ctx = s.ctx;
    var val = pval.*;

    if (mc.isPtr(val)) {
        val +%= @as(c.JSValue, @intCast(s.offset));

        if (s.update_atoms != 0) {
            const p: *const vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
            if (mc.mbGetMtag(@ptrCast(@constCast(p))) == mc.JS_MTAG_STRING and vt.stringIsUnique(p)) {
                const x = cx(ctx);
                var i: u8 = 0;
                while (i < x.n_rom_atom_tables) : (i += 1) {
                    const arr1: *const vt.JSValueArrayExt = @ptrCast(@alignCast(x.rom_atom_tables[i]));
                    var a: c_int = undefined;
                    const str = find_atom(ctx, &a, arr1, vt.valueArraySize(arr1), val);
                    if (!mc.isNull(str)) {
                        val = str;
                        break;
                    }
                }
            }
        }
        pval.* = val;
    }
}

pub fn JS_RelocateBytecode2(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    buf: [*]u8,
    buf_len: u32,
    new_base_addr: usize,
    update_atoms: c.JS_BOOL,
) c_int {
    if (hdr.magic != gt.JS_BYTECODE_MAGIC)
        return -1;
    if (hdr.version != gt.JS_BYTECODE_VERSION)
        return -1;

    var ss: gt.BCRelocState = undefined;
    const s = &ss;
    s.ctx = ctx;
    s.offset = new_base_addr -% hdr.base_addr;
    s.update_atoms = update_atoms;

    bc_reloc_value(s, &hdr.unique_strings);
    bc_reloc_value(s, &hdr.main_func);

    var ptr = buf;
    const p_end = buf + buf_len;
    while (@intFromPtr(ptr) < @intFromPtr(p_end)) {
        const size = get_mblock_size(ptr);
        const mtag = mc.mbGetMtag(ptr);
        switch (mtag) {
            mc.JS_MTAG_FUNCTION_BYTECODE => {
                const b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(ptr));
                bc_reloc_value(s, &b.func_name);
                bc_reloc_value(s, &b.byte_code);
                bc_reloc_value(s, &b.cpool);
                bc_reloc_value(s, &b.vars);
                bc_reloc_value(s, &b.ext_vars);
                bc_reloc_value(s, &b.filename);
                bc_reloc_value(s, &b.pc2line);
            },
            mc.JS_MTAG_VALUE_ARRAY => {
                const p: *vt.JSValueArrayExt = @ptrCast(@alignCast(ptr));
                const items = vt.valueArrayItems(p);
                var i: c_int = 0;
                while (i < vt.valueArraySize(p)) : (i += 1) {
                    bc_reloc_value(s, &items[@intCast(i)]);
                }
            },
            mc.JS_MTAG_STRING, mc.JS_MTAG_FLOAT64, mc.JS_MTAG_BYTE_ARRAY => {},
            else => {
                std.process.abort();
            },
        }
        ptr += @intCast(size);
    }
    hdr.base_addr = new_base_addr;
    return 0;
}

pub fn JS_RelocateBytecode(ctx: *c.JSContext, buf: [*]u8, buf_len: u32) c_int {
    if (buf_len < @sizeOf(gt.JSBytecodeHeader))
        return -1;
    const data_ptr = buf + @sizeOf(gt.JSBytecodeHeader);
    const hdr: *gt.JSBytecodeHeader = @ptrCast(@alignCast(buf));
    return JS_RelocateBytecode2(
        ctx,
        hdr,
        data_ptr,
        buf_len - @sizeOf(gt.JSBytecodeHeader),
        @intFromPtr(data_ptr),
        c.TRUE,
    );
}

pub fn JS_LoadBytecode(ctx: *c.JSContext, buf: [*]const u8) c.JSValue {
    const hdr: *const gt.JSBytecodeHeader = @ptrCast(@alignCast(buf));
    const x = cx(ctx);

    if (x.unique_strings_len != 0)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "no atom must be defined in RAM");
    if (x.n_rom_atom_tables >= gt.N_ROM_ATOM_TABLES_MAX)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "too many rom atom tables");
    if (hdr.magic != gt.JS_BYTECODE_MAGIC)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "invalid bytecode magic");
    if ((hdr.version & 0x8000) != (gt.JS_BYTECODE_VERSION & 0x8000))
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "bytecode not saved for %d-bit", c.JSW * 8);
    if (hdr.version != gt.JS_BYTECODE_VERSION)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "invalid bytecode version");
    if (hdr.base_addr != @intFromPtr(hdr) + @sizeOf(gt.JSBytecodeHeader))
        return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "bytecode not relocated");
    x.rom_atom_tables[x.n_rom_atom_tables] = @ptrCast(@alignCast(mc.valueToPtr(hdr.unique_strings)));
    x.n_rom_atom_tables += 1;
    return hdr.main_func;
}
