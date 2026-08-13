//
// Engine layouts and helpers for mquickjs_gc Zig port
//

pub const lt = @import("mquickjs_lexer_types.zig");
pub const rt = @import("mquickjs_runtime_types.zig");
pub const vt = rt.vt;
pub const mc = rt.mc;
pub const c = rt.c;

pub const JSParseState = lt.JSParseState;

pub const JS_BYTECODE_MAGIC: u16 = 0xacfb;
pub const JS_BYTECODE_VERSION_32: u16 = 0x0001;
pub const JS_BYTECODE_VERSION: u16 = JS_BYTECODE_VERSION_32 | @as(u16, @intCast((c.JSW & 8) << 12));
pub const N_ROM_ATOM_TABLES_MAX: u8 = 2;
pub const JS_STRING_LEN_MAX_32: u32 = (@as(u32, 1) << (32 - vt.JS_MTAG_BITS - 3)) - 1;

pub const GCMarkState = extern struct {
    ctx: *c.JSContext,
    gsp: [*]c.JSValue,
    gs_bottom: [*]c.JSValue,
    gs_top: [*]c.JSValue,
    overflow: c.JS_BOOL,
};

pub const BCRelocState = extern struct {
    ctx: *c.JSContext,
    offset: usize,
    update_atoms: c.JS_BOOL,
};

pub const JSBytecodeHeader = extern struct {
    magic: u16,
    version: u16,
    base_addr: usize,
    unique_strings: c.JSValue,
    main_func: c.JSValue,
};

pub const JSBytecodeHeader32 = extern struct {
    magic: u16,
    version: u16,
    base_addr: u32,
    unique_strings: u32,
    main_func: u32,
};

pub const JSMemBlockHeader_32 = extern struct {
    header: u32,
};

pub const JSValueArray_32 = extern struct {
    header: u32,
    arr: [0]u32,
};

pub const JSByteArray_32 = extern struct {
    header: u32,
    buf: [0]u8,
};

pub const JSString_32 = extern struct {
    header: u32,
    buf: [0]u8,
};

pub const JSFloat64_32 = packed struct {
    header: u32,
    dval: f64,
};

pub const JSFunctionBytecode_32 = extern struct {
    header: u32,
    func_name: u32,
    byte_code: u32,
    cpool: u32,
    vars: u32,
    ext_vars: u32,
    stack_size: u16,
    ext_vars_len: u16,
    filename: u32,
    pc2line: u32,
    source_pos: u32,
};

pub fn mbGcMark(ptr: *const anyopaque) bool {
    const w: *const c.JSWord = @ptrCast(@alignCast(ptr));
    return (w.* & 1) != 0;
}

pub fn mbSetGcMark(ptr: *anyopaque, mark: bool) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    if (mark) {
        w.* |= 1;
    } else {
        w.* &= ~@as(c.JSWord, 1);
    }
}

pub fn isRomPtr(ctx: *c.JSContext, ptr: *const anyopaque) bool {
    return vt.jsIsRomPtr(ctx, ptr);
}

pub fn objectExtraSize(p: *const mc.JSObjectExt) c.JSWord {
    return p.header >> 12;
}

pub fn freeBlockSizeWords(ptr: *const anyopaque) c.JSWord {
    const w: *const c.JSWord = @ptrCast(@alignCast(ptr));
    return w.* >> 4;
}

pub fn bytecodeHasArguments(b: *const rt.JSFunctionBytecodeExt) bool {
    return (b.header >> 4) & 1 != 0;
}

pub fn bytecodeHasLocalFuncName(b: *const rt.JSFunctionBytecodeExt) bool {
    return (b.header >> 5) & 1 != 0;
}

pub fn mb32GetMtag(ptr: *const anyopaque) c_int {
    const w: *const u32 = @ptrCast(@alignCast(ptr));
    return @intCast((w.* >> 1) & 0x7);
}

pub fn string32Len(p: *const JSString_32) u32 {
    return p.header >> 7;
}

pub fn valueArray32Size(p: *const JSValueArray_32) u32 {
    return p.header >> 4;
}

pub fn byteArray32Size(p: *const JSByteArray_32) u32 {
    return p.header >> 4;
}

pub fn valueToU32(val: c.JSValue) u32 {
    return @truncate(val);
}
