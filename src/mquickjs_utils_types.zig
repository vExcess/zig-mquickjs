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

pub const JSStringExt = extern struct {
    header: c.JSWord,
    buf: [0]u8,
};

pub const JSValueArrayExt = extern struct {
    header: c.JSWord,
    arr: [0]c.JSValue,
};

pub const JSByteArrayExt = extern struct {
    header: c.JSWord,
    buf: [0]u8,
};

pub const JSVarRefExt = extern struct {
    header: c.JSWord,
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
    hash_and_type: u32,
    _pad: u32 = 0,
};

pub const JS_STACK_SLACK: c_uint = 16;
pub const JS_MIN_FREE_SIZE: c_uint = 512;
pub const JS_MIN_CRITICAL_FREE_SIZE: c_uint = JS_MIN_FREE_SIZE - 256;
pub const JS_PROP_SPECIAL: c_uint = 3;

const mi = @import("mquickjs_internal.zig");

pub const ctxExt = mi.ctxExt;
pub const mbInit = mi.mbInit;
pub const mbGetMtag = mi.mbGetMtag;
pub const mbSetFreeBlock = mi.mbSetFreeBlock;
pub const mbSetMtag = mi.mbSetMtag;
pub const objectClassId = mi.objectClassId;
pub const float64Value = mi.float64Value;
pub const valueFromPtr = mi.valueFromPtr;
pub const valueToPtr = mi.valueToPtr;
pub const valueGetInt = mi.valueGetInt;
pub const valueGetSpecialTag = mi.valueGetSpecialTag;
pub const valueGetSpecialValue = mi.valueGetSpecialValue;
pub const isInt = mi.isInt;
pub const isPtr = mi.isPtr;
pub const isShortFloat = mi.isShortFloat;
pub const isNull = mi.isNull;
pub const isException = mi.isException;
pub const alignUp = mi.alignUp;
pub const stringBuf = mi.stringBuf;
pub const stringLen = mi.stringLen;
pub const stringIsUnique = mi.stringIsUnique;
pub const stringIsAscii = mi.stringIsAscii;
pub const stringIsNumeric = mi.stringIsNumeric;
pub const stringSetMeta = mi.stringSetMeta;
pub const stringSetUnique = mi.stringSetUnique;
pub const stringSetAscii = mi.stringSetAscii;
pub const stringSetNumeric = mi.stringSetNumeric;
pub const valueArrayItems = mi.valueArrayItems;
pub const valueArraySize = mi.valueArraySize;
pub const valueArraySetSize = mi.valueArraySetSize;
pub const byteArrayBuf = mi.byteArrayBuf;
pub const byteArraySize = mi.byteArraySize;
pub const byteArraySetSize = mi.byteArraySetSize;
pub const varRefIsDetached = mi.varRefIsDetached;
pub const varRefSetDetached = mi.varRefSetDetached;
pub const propHashNext = mi.propHashNext;
pub const propSetHashNext = mi.propSetHashNext;
pub const propType = mi.propType;
pub const propSetType = mi.propSetType;
pub const get_u8 = mi.get_u8;
pub const get_u16 = mi.get_u16;
pub const get_u32 = mi.get_u32;
pub const put_u16 = mi.put_u16;
pub const put_u32 = mi.put_u32;
