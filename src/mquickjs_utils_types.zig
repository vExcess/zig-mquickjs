//
// Engine struct layouts for mquickjs_utils Zig port
//

pub const c = @cImport({
    @cInclude("stdarg.h");
    @cInclude("cutils.h");
    @cInclude("dtoa.h");
    @cInclude("mquickjs.h");
    @cInclude("mquickjs_atom.h");
});

pub const JS_MTAG_FREE: c_int = 0;
pub const JS_MTAG_OBJECT: c_int = 1;
pub const JS_MTAG_FLOAT64: c_int = 2;
pub const JS_MTAG_STRING: c_int = 3;
pub const JS_MTAG_FUNCTION_BYTECODE: c_int = 4;
pub const JS_MTAG_VALUE_ARRAY: c_int = 5;
pub const JS_MTAG_BYTE_ARRAY: c_int = 6;
pub const JS_MTAG_VARREF: c_int = 7;
pub const JS_MTAG_COUNT: usize = 8;

pub const JSValue_PRI: []const u8 = if (@sizeOf(c.JSWord) == 8) "lo" else "o";

pub const JSWriteFn = *const fn (?*anyopaque, ?*const anyopaque, usize) callconv(.c) void;

pub const JSGCRefExt = extern struct {
    val: c.JSValue,
    prev: ?*JSGCRefExt,
};

pub const JSContextExt = extern struct {
    heap_base: [*c]u8,
    heap_free: [*c]u8,
    stack_top: [*c]u8,
    stack_bottom: *c.JSValue,
    sp: *c.JSValue,
    fp: *c.JSValue,
    min_free_size: c_uint,
    in_out_of_memory: u8,
    n_rom_atom_tables: u8,
    string_pos_cache_counter: u8,
    class_count: u16,
    interrupt_counter: i16,
    current_exception_is_uncatchable: u8,
    parse_state: ?*anyopaque,
    unique_strings_len: c_int,
    js_call_rec_count: c_int,
    top_gc_ref: ?*JSGCRefExt,
    last_gc_ref: ?*JSGCRefExt,
    atom_table: [*c]const c.JSWord,
    rom_atom_tables: [2]?*anyopaque,
    c_function_table: [*c]const JSCFunctionDefExt,
    c_finalizer_table: ?*anyopaque,
    random_state: u64,
    interrupt_handler: ?*anyopaque,
    write_func: ?JSWriteFn,
    opaque_val: ?*anyopaque,
    class_obj: ?*c.JSValue,
    string_pos_cache: [2]JSStringPosCacheEntryExt,
    unique_strings: c.JSValue,
    current_exception: c.JSValue,
    empty_props: c.JSValue,
    global_obj: c.JSValue,
    minus_zero: c.JSValue,
    class_proto: [0]c.JSValue,
};

pub const JSStringPosCacheEntryExt = extern struct {
    str: c.JSValue,
    str_pos: [2]c_uint,
};

pub const JSCFunctionDefExt = extern struct {
    name: c.JSValue,
    def_type: u8,
    magic: c_int,
};

pub const JSClosureDataExt = extern struct {
    func_bytecode: c.JSValue,
};

pub const JSCFunctionDataExt = extern struct {
    idx: c_uint,
    params: c.JSValue,
};

pub const JSArrayDataExt = extern struct {
    tab: c.JSValue,
    len: c_uint,
};

pub const JSErrorDataExt = extern struct {
    message: c.JSValue,
    stack: c.JSValue,
};

pub const JSArrayBufferExt = extern struct {
    byte_buffer: c.JSValue,
};

pub const JSTypedArrayExt = extern struct {
    buffer: c.JSValue,
    len: c_uint,
    offset: c_uint,
};

pub const JSObjectExt = extern struct {
    header: c.JSWord,
    proto: c.JSValue,
    props: c.JSValue,
    u: extern union {
        closure: JSClosureDataExt,
        cfunc: JSCFunctionDataExt,
        array: JSArrayDataExt,
        err: JSErrorDataExt,
        array_buffer: JSArrayBufferExt,
        typed_array: JSTypedArrayExt,
    },
};

pub const JSFunctionBytecodeExt = extern struct {
    header: c.JSWord,
    flags: c.JSWord,
    func_name: c.JSValue,
    byte_code: c.JSValue,
    cpool: c.JSValue,
    vars: c.JSValue,
    ext_vars: c.JSValue,
    stack_size: u16,
    ext_vars_len: u16,
    filename: c.JSValue,
    pc2line: c.JSValue,
    source_pos: c_uint,
};

pub const JSStringExt = extern struct {
    header: c.JSWord,
    flags_len: c.JSWord,
    buf: [0]u8,
};

pub const JSValueArrayExt = extern struct {
    header: c.JSWord,
    size_field: c.JSWord,
    arr: [0]c.JSValue,
};

pub const JSByteArrayExt = extern struct {
    header: c.JSWord,
    size_field: c.JSWord,
    buf: [0]u8,
};

pub const JSVarRefExt = extern struct {
    header: c.JSWord,
    flags: c.JSWord,
    u: extern union {
        value: c.JSValue,
        live: extern struct {
            next: c.JSValue,
            pvalue: *c.JSValue,
        },
    },
};

pub const JSPropertyExt = extern struct {
    key: c.JSValue,
    value: c.JSValue,
    hash_next: c_uint,
    prop_type: c_uint,
};

pub const JS_STACK_SLACK: c_uint = 16;
pub const JS_MIN_FREE_SIZE: c_uint = 512;
pub const JS_MIN_CRITICAL_FREE_SIZE: c_uint = JS_MIN_FREE_SIZE - 256;
pub const JS_PROP_SPECIAL: c_uint = 3;

pub fn ctxExt(ctx: *c.JSContext) *JSContextExt {
    return @ptrCast(@alignCast(ctx));
}

pub fn mbInit(ptr: *anyopaque, mtag: c_int) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    w.* = @as(c.JSWord, @intCast(mtag)) << 1;
}

pub fn mbGetMtag(ptr: *anyopaque) c_int {
    const w: *const c.JSWord = @ptrCast(@alignCast(ptr));
    return @intCast((w.* >> 1) & 0x7);
}

pub fn mbSetFreeBlock(ptr: *anyopaque, size: c_uint) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    const payload_words = (size - @sizeOf(c.JSWord)) / @sizeOf(c.JSWord);
    w.* = (@as(c.JSWord, @intCast(JS_MTAG_FREE)) << 1) | (@as(c.JSWord, payload_words) << 4);
}

pub fn objectClassId(p: *const JSObjectExt) c_int {
    return @intCast((p.header >> 4) & 0xff);
}

pub fn stringIsUnique(p: *const JSStringExt) bool {
    return (p.flags_len & 1) != 0;
}

pub fn stringLen(p: *const JSStringExt) usize {
    return @intCast(p.flags_len >> 3);
}

pub fn valueArraySizeField(p: *const JSValueArrayExt) c_int {
    return @intCast(p.size_field >> 4);
}

pub fn byteArraySizeField(p: *const JSByteArrayExt) u64 {
    return p.size_field >> 4;
}

pub fn varRefIsDetached(p: *const JSVarRefExt) bool {
    return (p.flags & 1) != 0;
}

pub fn float64Value(ptr: *anyopaque) f64 {
    const bp: [*c]u8 = @ptrCast(ptr);
    const dptr: *f64 = @ptrCast(@alignCast(bp + @sizeOf(c.JSWord)));
    return dptr.*;
}

pub fn valueFromPtr(ptr: *anyopaque) c.JSValue {
    return @as(c.JSWord, @intCast(@intFromPtr(ptr))) + 1;
}

pub fn valueToPtr(val: c.JSValue) *anyopaque {
    return @ptrFromInt(@as(usize, @intCast(val - 1)));
}

pub fn valueGetInt(v: c.JSValue) c_int {
    return @as(c_int, @intCast(v >> 1));
}

pub fn valueGetSpecialTag(v: c.JSValue) c.JSWord {
    return v & ((@as(c.JSWord, 1) << c.JS_TAG_SPECIAL_BITS) - 1);
}

pub fn valueGetSpecialValue(v: c.JSValue) c_int {
    return @as(c_int, @intCast(v >> c.JS_TAG_SPECIAL_BITS));
}

pub fn isInt(v: c.JSValue) bool {
    return (v & 1) == c.JS_TAG_INT;
}

pub fn isPtr(v: c.JSValue) bool {
    return (v & (c.JSW - 1)) == c.JS_TAG_PTR;
}

pub fn isShortFloat(v: c.JSValue) bool {
    return (v & (c.JSW - 1)) == c.JS_TAG_SHORT_FLOAT;
}

pub fn isNull(v: c.JSValue) bool {
    return valueGetSpecialTag(v) == c.JS_TAG_NULL;
}

pub fn isException(v: c.JSValue) bool {
    return valueGetSpecialTag(v) == c.JS_TAG_EXCEPTION;
}

pub fn alignUp(size: c_uint, alignment: c_uint) c_uint {
    return (size + alignment - 1) & ~@as(c_uint, alignment - 1);
}

pub fn valueArrayItems(arr: *const JSValueArrayExt) [*]c.JSValue {
    return @constCast(@ptrCast(@alignCast(&arr.arr)));
}

pub fn byteArrayBuf(arr: *const JSByteArrayExt) [*]u8 {
    return @constCast(@ptrCast(@alignCast(&arr.buf)));
}

pub fn stringBuf(p: *const JSStringExt) [*]u8 {
    return @constCast(@ptrCast(@alignCast(&p.buf)));
}
