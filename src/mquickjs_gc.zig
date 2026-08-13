//
// Micro QuickJS engine garbage collector (C ABI exports)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by VExcess
//

const lib = @import("mquickjs_gc_lib.zig");
const gt = @import("mquickjs_gc_types.zig");
const c = lib.c;

export fn get_mblock_size(ptr: *const anyopaque) c_int {
    return lib.get_mblock_size(ptr);
}

export fn JS_GC(ctx: *c.JSContext) void {
    lib.JS_GC(ctx);
}

export fn JS_GC2(ctx: *c.JSContext, keep_atoms: c.JS_BOOL) void {
    lib.JS_GC2(ctx, keep_atoms);
}

export fn JS_LoadBytecode(ctx: *c.JSContext, buf: [*]const u8) c.JSValue {
    return lib.JS_LoadBytecode(ctx, buf);
}

export fn JS_IsBytecode(buf: [*]const u8, buf_len: usize) c.JS_BOOL {
    return lib.JS_IsBytecode(buf, buf_len);
}

export fn JS_RelocateBytecode(ctx: *c.JSContext, buf: [*]u8, buf_len: u32) c_int {
    return lib.JS_RelocateBytecode(ctx, buf, buf_len);
}

export fn JS_RelocateBytecode2(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    buf: [*]u8,
    buf_len: u32,
    new_base_addr: usize,
    update_atoms: c.JS_BOOL,
) c_int {
    return lib.JS_RelocateBytecode2(ctx, hdr, buf, buf_len, new_base_addr, update_atoms);
}

export fn JS_PrepareBytecode(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code: c.JSValue,
) void {
    lib.JS_PrepareBytecode(ctx, hdr, pdata_buf, pdata_len, eval_code);
}

export fn JS_PrepareBytecode64to32(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader32,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code: c.JSValue,
) c_int {
    return lib.JS_PrepareBytecode64to32(ctx, hdr, pdata_buf, pdata_len, eval_code);
}
