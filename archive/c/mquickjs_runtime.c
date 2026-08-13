/*
 * Micro QuickJS Javascript Engine
 *
 * Copyright (c) 2017-2025 Fabrice Bellard
 * Copyright (c) 2017-2025 Charlie Gordon
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <inttypes.h>
#include <string.h>
#include <assert.h>
#include <math.h>
#include <setjmp.h>

#include "cutils.h"
#include "dtoa.h"
#include "mquickjs_internal.h"

const JSOpCode opcode_info[OP_COUNT] = {
#define FMT(f)
#ifdef DUMP_BYTECODE
#define DEF(id, size, n_pop, n_push, f) { #id, size, n_pop, n_push, OP_FMT_ ## f },
#else
#define DEF(id, size, n_pop, n_push, f) { size, n_pop, n_push, OP_FMT_ ## f },
#endif
#include "mquickjs_opcode.h"
#undef DEF
#undef FMT
};
void dummy_write_func(void *opaque, const void *buf, size_t buf_len)
{
    //    fwrite(buf, 1, buf_len, stdout);
}

/* if prepare_compilation is true, the context will be used to compile
   to a binary file. It is not expected to be used in the embedded
   version */
JSContext *JS_NewContext2(void *mem_start, size_t mem_size, const JSSTDLibraryDef *stdlib_def, BOOL prepare_compilation)
{
    JSContext *ctx;
    JSValueArray *arr;
    int i, mem_align;

#ifdef JS_PTR64
    mem_align = 8;
#else
    mem_align = 4;
#endif
    mem_size = mem_size & ~(mem_align - 1);
    assert(mem_size >= 1024);
    assert(((uintptr_t)mem_start & (mem_align - 1)) == 0);

    ctx = mem_start;
    memset(ctx, 0, sizeof(*ctx));
    ctx->class_count = stdlib_def->class_count;
    ctx->class_obj = ctx->class_proto + ctx->class_count;
    ctx->heap_base = (void *)(ctx->class_proto + 2 * ctx->class_count);
    ctx->heap_free = ctx->heap_base;
    ctx->stack_top = mem_start + mem_size;
    ctx->sp = (JSValue *)ctx->stack_top;
    ctx->stack_bottom = ctx->sp;
    ctx->fp = ctx->sp;
    ctx->min_free_size = JS_MIN_FREE_SIZE;
#ifdef DEBUG_GC
    ctx->dummy_block = JS_NULL;
    ctx->unique_strings = JS_NULL;
#endif    
    ctx->random_state = 1;
    ctx->write_func = dummy_write_func;
    for(i = 0; i < JS_STRING_POS_CACHE_SIZE; i++)
        ctx->string_pos_cache[i].str = JS_NULL;

    if (prepare_compilation) {
        int atom_table_len;
        JSValueArray *arr, *arr1;
        uint8_t *ptr;
        
        /* for compilation, no stdlib is needed. Only the atoms
           corresponding to JS_ATOM_x are needed and they are stored
           in RAM. */
        /* copy the atoms to a fixed location at the beginning of the
           heap */
        ctx->atom_table = (JSWord *)ctx->heap_free;
        atom_table_len = stdlib_def->sorted_atoms_offset;
        memcpy(ctx->heap_free, stdlib_def->stdlib_table,
               atom_table_len * sizeof(JSWord));
        ctx->heap_free += atom_table_len * sizeof(JSWord);

        /* allocate the sorted atom table and populate it */
        arr1 = (JSValueArray *)(stdlib_def->stdlib_table + atom_table_len);
        arr = js_alloc_value_array(ctx, 0, arr1->size);
        ctx->unique_strings = JS_VALUE_FROM_PTR(arr);
        for(i = 0; i < arr1->size; i++) {
            ptr = JS_VALUE_TO_PTR(arr1->arr[i]);
            ptr = ptr - (uint8_t *)stdlib_def->stdlib_table +
                (uint8_t *)ctx->atom_table;
            arr->arr[i] = JS_VALUE_FROM_PTR(ptr);
        }
        ctx->unique_strings_len = arr1->size;
    } else {
        ctx->atom_table = stdlib_def->stdlib_table;
        ctx->rom_atom_tables[0] = (JSValueArray *)(stdlib_def->stdlib_table +
                                                   stdlib_def->sorted_atoms_offset);
        ctx->n_rom_atom_tables = 1;
        ctx->c_function_table = stdlib_def->c_function_table;
        ctx->c_finalizer_table = stdlib_def->c_finalizer_table;
        ctx->unique_strings = JS_NULL;
        ctx->unique_strings_len = 0;
    }
    
    
    ctx->current_exception = JS_UNINITIALIZED;
#ifdef DEBUG_GC
    /* set the dummy block at the start of the memory */
    {
        JSByteArray *barr;
        barr = js_alloc_byte_array(ctx, (min_int(mem_size / 2, 1 << 17)) & ~(JSW - 1));
        ctx->dummy_block = JS_VALUE_FROM_PTR(barr);
    }
#endif

    arr = js_alloc_value_array(ctx, 0, 3);
    arr->arr[0] = JS_NewShortInt(0); /* prop_count */
    arr->arr[1] = JS_NewShortInt(0); /* hash_mark */
    arr->arr[2] = JS_NewShortInt(0); /* hash_table[1] */
    ctx->empty_props = JS_VALUE_FROM_PTR(arr);
    for(i = 0; i < ctx->class_count; i++)
        ctx->class_proto[i] = JS_NULL;
    for(i = 0; i < ctx->class_count; i++)
        ctx->class_obj[i] = JS_NULL;
    /* must be done first so that the prototype of Object.prototype is
       JS_NULL */
    ctx->class_proto[JS_CLASS_OBJECT] = JS_NewObject(ctx); 
    /* must be done for proper function init */
    ctx->class_proto[JS_CLASS_CLOSURE] = JS_NewObject(ctx); 

    ctx->global_obj = JS_NewObject(ctx);
    ctx->minus_zero = js_alloc_float64(ctx, -0.0); /* XXX: use a ROM value instead */
        
    if (!prepare_compilation) {
        stdlib_init(ctx, (JSValueArray *)(stdlib_def->stdlib_table + stdlib_def->global_object_offset));
    }
    
    return ctx;
}

JSContext *JS_NewContext(void *mem_start, size_t mem_size, const JSSTDLibraryDef *stdlib_def)
{
    return JS_NewContext2(mem_start, mem_size, stdlib_def, FALSE);
}

void JS_FreeContext(JSContext *ctx)
{
    uint8_t *ptr;
    int size;
    JSObject *p;
    
    /* call the user C finalizers */
    /* XXX: could disable it when prepare_compilation = true */
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        size = get_mblock_size(ptr);
        p = (JSObject *)ptr;
        if (p->mtag == JS_MTAG_OBJECT && p->class_id >= JS_CLASS_USER &&
            ctx->c_finalizer_table[p->class_id - JS_CLASS_USER] != NULL) {
            ctx->c_finalizer_table[p->class_id - JS_CLASS_USER](ctx, p->u.user.opaque);
        }
        ptr += size;
    }
}

void JS_SetContextOpaque(JSContext *ctx, void *opaque)
{
    ctx->opaque = opaque;
}

void *JS_GetContextOpaque(JSContext *ctx)
{
    return ctx->opaque;
}

void JS_SetInterruptHandler(JSContext *ctx, JSInterruptHandler *interrupt_handler)
{
    ctx->interrupt_handler = interrupt_handler;
}

void JS_SetLogFunc(JSContext *ctx, JSWriteFunc *write_func)
{
    ctx->write_func = write_func;
}

void JS_SetRandomSeed(JSContext *ctx, uint64_t seed)
{
    ctx->random_state = seed;
}

JSValue JS_GetGlobalObject(JSContext *ctx)
{
    return ctx->global_obj;
}

JSValue get_var_ref(JSContext *ctx, JSValue *pfirst_var_ref, JSValue *pval)
{
    JSValue val;
    JSVarRef *p;
    
    val = *pfirst_var_ref;
    for(;;) {
        if (val == JS_NULL)
            break;
        p = JS_VALUE_TO_PTR(val);
        assert(!p->is_detached);
        if (p->u.pvalue == pval)
            return val;
        val = p->u.next;
    }

    p = js_malloc(ctx, sizeof(JSVarRef), JS_MTAG_VARREF);
    if (!p)
        return JS_EXCEPTION;
    p->is_detached = FALSE;
    p->u.pvalue = pval;
    p->u.next = *pfirst_var_ref;
    val = JS_VALUE_FROM_PTR(p);
    *pfirst_var_ref = val;
    return val;
}

#define FRAME_OFFSET_ARG0       4
#define FRAME_OFFSET_FUNC_OBJ   3
#define FRAME_OFFSET_THIS_OBJ   2
#define FRAME_OFFSET_CALL_FLAGS 1
#define FRAME_OFFSET_SAVED_FP   0
#define FRAME_OFFSET_CUR_PC     (-1) /* current pc_offset */
#define FRAME_OFFSET_FIRST_VARREF (-2)
#define FRAME_OFFSET_VAR0      (-3)

/* stack layout:
   
   padded_args (padded_argc - argc)
   args (argc)
   func_obj                   fp[3]
   this_obj                   fp[2]
   call_flags     (int)       fp[1]
   saved_fp (int)             fp[0]
   cur_pc   (int)             fp[-1]
   first_var_ref (val)        fp[-2]
   vars (var_count)
   temp stack          (pointed by sp)
*/

#define SP_TO_VALUE(ctx, fp) JS_NewShortInt((uint8_t *)(fp) - (uint8_t *)ctx)
#define VALUE_TO_SP(ctx, val) (void *)((uint8_t *)ctx + JS_VALUE_GET_INT(val))

/* buf_end points to the end of the buffer (after the final '\0') */
__js_printf_like(3, 4) void cprintf(char **pp, char *buf_end, const char *fmt, ...)
{
    char *p;
    va_list ap;
    
    p = *pp;
    if ((p + 1) >= buf_end)
        return;
    va_start(ap, fmt);
    js_vsnprintf(p, buf_end - p, fmt, ap);
    va_end(ap);
    p += strlen(p);
    *pp = p;
}

JSValue reloc_c_func_name(JSContext *ctx, JSValue val)
{
    return val;
}

/* no memory allocation is done */
/* XXX: handle bound functions */
JSValue js_function_get_length_name1(JSContext *ctx, JSValue *this_val, int is_name, JSFunctionBytecode **pb)
{
    int short_func_idx;
    const JSCFunctionDef *fd;
    JSValue ret;

    if (!JS_IsPtr(*this_val)) {
        if (JS_VALUE_GET_SPECIAL_TAG(*this_val) != JS_TAG_SHORT_FUNC)
            goto fail;
        short_func_idx = JS_VALUE_GET_SPECIAL_VALUE(*this_val);
        goto short_func;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(*this_val);
        JSFunctionBytecode *b;
        if (p->mtag != JS_MTAG_OBJECT)
            goto fail;
        if (p->class_id == JS_CLASS_CLOSURE) {
            b = JS_VALUE_TO_PTR(p->u.closure.func_bytecode);
            if (is_name) {
                /* XXX: directly set func_name to the empty string ? */
                if (b->func_name == JS_NULL)
                    ret = js_get_atom(ctx, JS_ATOM_empty);
                else
                    ret = b->func_name;
            } else {
                ret = JS_NewShortInt(b->arg_count);
            }
            *pb = b;
            return ret;
        } else if (p->class_id == JS_CLASS_C_FUNCTION) {
            short_func_idx = p->u.cfunc.idx;
        short_func:
            fd = &ctx->c_function_table[short_func_idx];
            if (is_name) {
                ret = reloc_c_func_name(ctx, fd->name);
            } else {
                ret = JS_NewShortInt(fd->arg_count);
            }
            *pb = NULL;
            return ret;
        } else {
        fail:
            *pb = NULL;
            return JS_NULL;
        }
    }
}

uint32_t get_bit(const uint8_t *buf, uint32_t index)
{
    return (buf[index >> 3] >> (7 - (index & 7))) & 1;
}

uint32_t get_bits_slow(const uint8_t *buf, uint32_t index, int n)
{
    int i;
    uint32_t val;
    val = 0;
    for(i = 0; i < n; i++)
        val |= get_bit(buf, index + i) << (n - 1 - i);
    return val;
}

uint32_t get_bits(const uint8_t *buf, uint32_t buf_len, uint32_t index, int n)
{
    uint32_t val, pos;

    pos = index >> 3;
    if (unlikely(n > 25 || (pos + 3) >= buf_len)) {
        /* slow case */
        return get_bits_slow(buf, index, n);
    } else {
        /* fast case */
        val = get_be32(buf + pos);
        return (val >> (32 - (index & 7) - n)) & ((1 << n) - 1);
    }
}

uint32_t get_ugolomb(const uint8_t *buf, uint32_t buf_len, uint32_t *pindex)
{
    uint32_t index = *pindex;
    int i;
    uint32_t v;
    
    i = 0;
    for(;;) {
        if (get_bit(buf, index++))
            break;
        i++;
        if (i == 32) {
            /* error */
            *pindex = index;
            return 0xffffffff;
        }
    }
    if (i == 0) {
        v = 0;
    } else {
        v = ((1 << i) | get_bits(buf, buf_len, index, i)) - 1;
        index += i;
    }
    *pindex = index;
    //    printf("get_ugolomb: v=%d\n", v);
    return v;
}

int32_t get_sgolomb(const uint8_t *buf, uint32_t buf_len, uint32_t *pindex)
{
    uint32_t val;
    val = get_ugolomb(buf, buf_len, pindex);
    return (val >> 1) ^ -(val & 1);
}

int get_pc2line_hoisted_code_len(const uint8_t *buf, size_t buf_len)
{
    size_t i = buf_len;
    int v = 0;
    while (i > 0) {
        i--;
        v = (v << 7) | (buf[i] & 0x7f);
        if ((buf[i] & 0x80) == 0)
            break;
    }
    return v;
}

/* line_num, col_num and index are updated */
void get_pc2line(int *pline_num, int *pcol_num, const uint8_t *buf, uint32_t buf_len, uint32_t *pindex, BOOL has_column)
{
    int line_delta, line_num, col_num, col_delta;

    line_num = *pline_num;
    col_num = *pcol_num;
    
    line_delta = get_sgolomb(buf, buf_len, pindex);
    line_num += line_delta;
    if (has_column) {
        if (line_delta == 0) {
            col_delta = get_sgolomb(buf, buf_len, pindex);
            col_num += col_delta;
        } else {
            col_num = get_ugolomb(buf, buf_len, pindex) + 1;
        }
    } else {
        col_num = 0;
    }
    *pline_num = line_num;
    *pcol_num = col_num;
}

/* return 0 if line/col number info */
int find_line_col(int *pcol_num, JSFunctionBytecode *b, uint32_t pc)
{
    JSByteArray *arr, *pc2line;
    int pos, op, line_num, col_num;
    uint32_t pc2line_pos;
    
    if (b->pc2line == JS_NULL)
        goto fail;
    arr = JS_VALUE_TO_PTR(b->byte_code);
    pc2line = JS_VALUE_TO_PTR(b->pc2line);

    /* skip the hoisted code */
    pos = get_pc2line_hoisted_code_len(pc2line->buf, pc2line->size);
    if (pc < pos)
        pc = pos;
    pc2line_pos = 0;
    line_num = 1;
    col_num = 1;
    while (pos < arr->size) {
        get_pc2line(&line_num, &col_num, pc2line->buf, pc2line->size,
                    &pc2line_pos, b->has_column);
        if (pos == pc) {
            *pcol_num = col_num;
            return line_num;
        }
        op = arr->buf[pos];
        pos += opcode_info[op].size;
    }
 fail:
    *pcol_num = 0;
    return 0;
}

const char *get_func_name(JSContext *ctx, JSValue func_obj, JSCStringBuf *str_buf, JSFunctionBytecode **pb)
{
    JSValue val;
    val = js_function_get_length_name1(ctx, &func_obj, 1, pb);
    if (JS_IsNull(val))
        return NULL;
    return JS_ToCString(ctx, val, str_buf);
}

void build_backtrace(JSContext *ctx, JSValue error_obj, const char *filename, int line_num, int col_num, int skip_level)
{
    JSObject *p1;
    char buf[128], *p, *buf_end, *line_start;
    const char *str;
    JSValue *fp, stack_str;
    JSCStringBuf str_buf;
    JSFunctionBytecode *b;
    int level;
    JSGCRef error_obj_ref;
    
    if (!JS_IsError(ctx, error_obj))
        return;
    p = buf;
    buf_end = buf + sizeof(buf);
    p[0] = '\0';
    if (filename) {
        cprintf(&p, buf_end, "    at %s:%d:%d\n", filename, line_num, col_num);
    }
    fp = ctx->fp;
    level = 0;
    while (fp != (JSValue *)ctx->stack_top && level < 10) {
        if (skip_level != 0) {
            skip_level--;
        } else {
            line_start = p;
            str = get_func_name(ctx, fp[FRAME_OFFSET_FUNC_OBJ], &str_buf, &b);
            if (!str)
                str = "<anonymous>";
            cprintf(&p, buf_end, "    at %s", str);
            if (b) {
                int pc, line_num, col_num;
                const char *filename;
                filename = JS_ToCString(ctx, b->filename, &str_buf);
                pc = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CUR_PC]) - 1;
                line_num = find_line_col(&col_num, b, pc);
                cprintf(&p, buf_end, " (%s", filename);
                if (line_num != 0) {
                    cprintf(&p, buf_end, ":%d", line_num);
                    if (col_num != 0)
                        cprintf(&p, buf_end, ":%d", col_num);
                }
                cprintf(&p, buf_end, ")");
            } else {
                cprintf(&p, buf_end, " (native)");
            }
            cprintf(&p, buf_end, "\n");
            /* if truncated line, remove it and stop */
            if ((p + 1) >= buf_end) {
                *line_start = '\0';
                break;
            }
            level++;
        }
        fp = VALUE_TO_SP(ctx, fp[FRAME_OFFSET_SAVED_FP]);
    }

    JS_PUSH_VALUE(ctx, error_obj);
    stack_str = JS_NewString(ctx, buf);
    JS_POP_VALUE(ctx, error_obj);
    p1 = JS_VALUE_TO_PTR(error_obj);
    p1->u.error.stack = stack_str;
}

#define HINT_STRING  0
#define HINT_NUMBER  1
#define HINT_NONE    HINT_NUMBER

JSValue JS_ToPrimitive(JSContext *ctx, JSValue val, int hint)
{
    int i, atom;
    JSValue method, ret;
    JSGCRef val_ref, method_ref;
    
    if (JS_IsPrimitive(ctx, val))
        return val;
    for(i = 0; i < 2; i++) {
        if ((i ^ hint) == 0) {
            atom = JS_ATOM_toString;
        } else {
            atom = JS_ATOM_valueOf;
        }
        JS_PUSH_VALUE(ctx, val);
        method = JS_GetProperty(ctx, val, js_get_atom(ctx, atom));
        JS_POP_VALUE(ctx, val);
        if (JS_IsException(method))
            return method;
        if (JS_IsFunction(ctx, method)) {
            int err;
            JS_PUSH_VALUE(ctx, method);
            JS_PUSH_VALUE(ctx, val);
            err = JS_StackCheck(ctx, 2);
            JS_POP_VALUE(ctx, val);
            JS_POP_VALUE(ctx, method);
            if (err)
                return JS_EXCEPTION;

            JS_PushArg(ctx, method);
            JS_PushArg(ctx, val);
            JS_PUSH_VALUE(ctx, val);
            ret = JS_Call(ctx, 0);
            JS_POP_VALUE(ctx, val);
            if (JS_IsException(ret))
                return ret;
            if (!JS_IsObject(ctx, ret))
                return ret;
        }
    }
    return JS_ThrowTypeError(ctx, "toPrimitive");
}

/* return a string or an exception */
JSValue js_dtoa2(JSContext *ctx, double d, int radix, int n_digits, int flags)
{
    int len_max, len;
    JSValue str;
    JSGCRef str_ref;
    JSByteArray *tmp_arr, *p;

    len_max = js_dtoa_max_len(d, radix, n_digits, flags);
    p = js_alloc_byte_array(ctx, len_max + 1);
    if (!p)
        return JS_EXCEPTION;
    /* allocate the temporary buffer */
    str = JS_VALUE_FROM_PTR(p);
    JS_PUSH_VALUE(ctx, str);
    tmp_arr = js_alloc_byte_array(ctx, sizeof(JSDTOATempMem));
    JS_POP_VALUE(ctx, str);
    if (!tmp_arr)
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(str);
    /* Note: tmp_arr->buf is always 32 bit aligned */
    len = js_dtoa((char *)p->buf, d, radix, n_digits, flags, (JSDTOATempMem *)tmp_arr->buf);
    js_free(ctx, tmp_arr);
    return js_byte_array_to_string(ctx, str, len, TRUE);
}
    
JSValue JS_ToString(JSContext *ctx, JSValue val)
{
    char buf[128];
    int atom;
    const char *str;
    
 redo:
    if (JS_IsInt(val)) {
        int len;
        len = i32toa(buf, JS_VALUE_GET_INT(val));
        buf[len] = '\0';
        goto ret_buf;
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        return js_dtoa2(ctx, js_get_short_float(val), 10, 0, JS_DTOA_FORMAT_FREE);
    } else
#endif
    if (JS_IsPtr(val)) {
        void *ptr = JS_VALUE_TO_PTR(val);
        int mtag = js_get_mtag(ptr);
        switch(mtag) {
        case JS_MTAG_OBJECT:
        to_primitive:
            val = JS_ToPrimitive(ctx, val, HINT_STRING);
            if (JS_IsException(val))
                return val;
            goto redo;
        case JS_MTAG_STRING:
            return val;
        case JS_MTAG_FLOAT64:
            {
                JSFloat64 *p = ptr;
                return js_dtoa2(ctx, p->u.dval, 10, 0, JS_DTOA_FORMAT_FREE);
            }
        default:
            js_snprintf(buf, sizeof(buf), "[mtag %d]", mtag);
            goto ret_buf;
        }
    } else {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_NULL:
            atom = JS_ATOM_null;
            goto ret_atom;
        case JS_TAG_UNDEFINED:
            atom = JS_ATOM_undefined;
            goto ret_atom;
        case JS_TAG_BOOL:
            if (JS_VALUE_GET_SPECIAL_VALUE(val))
                atom = JS_ATOM_true;
            else
                atom = JS_ATOM_false;
        ret_atom:
            return js_get_atom(ctx, atom);
        case JS_TAG_STRING_CHAR:
            return val;
        case JS_TAG_SHORT_FUNC:
            goto to_primitive;
        default:
            str = "?";
            goto ret_str;
        ret_buf:
            str = buf;
        ret_str:
            return JS_NewString(ctx, str);
        }
    }
}

/* return either a unique string or an integer. Strings representing
   a short integer are converted to short integer */
JSValue JS_ToPropertyKey(JSContext *ctx, JSValue val)
{
    int32_t n;
    if (JS_IsInt(val))
        return val;
    val = JS_ToString(ctx, val);
    if (JS_IsException(val))
        return val;
    if (is_num_string(ctx, &n, val))
        return JS_NewShortInt(n);
    else
        return JS_MakeUniqueString(ctx, val);
}

int skip_spaces(const char *p1)
{
    const char *p = p1;
    int c;
    for(;;) {
        c = *p;
        if (!((c >= 0x09 && c <= 0x0d) || (c == 0x20)))
            break;
        p++;
    }
    return p - p1;
}

/* JS_ToString() specific behaviors */
#define JS_ATOD_TOSTRING (1 << 8)

/* 'val' must be a string */
int js_atod1(JSContext *ctx, double *pres, JSValue val, int radix, int flags)
{
    JSString *p;
    JSByteArray *tmp_arr;
    double d;
    JSGCRef val_ref;
    const char *p1;

    if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
        int c = JS_VALUE_GET_SPECIAL_VALUE(val);
        if (c >= '0' && c <= '9') {
            *pres = c - '0';
        } else {
            *pres = NAN;
        }
        return 0;
    }
    
    JS_PUSH_VALUE(ctx, val);
    tmp_arr = js_alloc_byte_array(ctx, sizeof(JSATODTempMem));
    JS_POP_VALUE(ctx, val);
    if (!tmp_arr) {
        *pres = NAN;
        return -1;
    }
    p = JS_VALUE_TO_PTR(val);
    p1 = (char *)p->buf;
    p1 += skip_spaces(p1);
    if ((p1 - (char *)p->buf) == p->len) {
        if (flags & JS_ATOD_TOSTRING)
            d = 0;
        else
            d = NAN;
        goto done;
    }
    d = js_atod(p1, &p1, radix, flags, (JSATODTempMem *)tmp_arr->buf);
    js_free(ctx, tmp_arr);
    if (flags & JS_ATOD_TOSTRING) {
        p1 += skip_spaces(p1);
        if ((p1 - (char *)p->buf) < p->len)
            d = NAN;
    }
 done:
    *pres = d;
    return 0;
}

/* Note: can fail due to memory allocation even if primitive type */
int JS_ToNumber(JSContext *ctx, double *pres, JSValue val)
{
 redo:
    if (JS_IsInt(val)) {
        *pres = (double)JS_VALUE_GET_INT(val);
        return 0;
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        *pres = js_get_short_float(val);
        return 0;
    } else
#endif
    if (JS_IsPtr(val)) {
        void *ptr = JS_VALUE_TO_PTR(val);
        switch(js_get_mtag(ptr)) {
        case JS_MTAG_STRING:
            goto atod;
        case JS_MTAG_FLOAT64:
            {
                JSFloat64 *p = ptr;
                *pres = p->u.dval;
                return 0;
            }
        case JS_MTAG_OBJECT:
            val = JS_ToPrimitive(ctx, val, HINT_NUMBER);
            if (JS_IsException(val)) {
                *pres = NAN;
                return -1;
            }
            goto redo;
        default:
            *pres = NAN;
            return 0;
        }
    } else {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_NULL:
        case JS_TAG_BOOL:
            *pres = (double)JS_VALUE_GET_SPECIAL_VALUE(val);
            return 0;
        case JS_TAG_UNDEFINED:
            *pres = NAN;
            return 0;
        case JS_TAG_STRING_CHAR:
        atod:
            return js_atod1(ctx, pres, val, 0,
                            JS_ATOD_ACCEPT_BIN_OCT | JS_ATOD_TOSTRING);
        default:
            *pres = NAN;
            return 0;
        }
    }
}

int JS_ToInt32Internal(JSContext *ctx, int *pres, JSValue val, BOOL sat_flag)
{
    int32_t ret;
    double d;

    if (JS_IsInt(val)) {
        ret = JS_VALUE_GET_INT(val);
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        d = js_get_short_float(val);
        goto handle_float64;
    } else
#endif
    if (JS_IsPtr(val)) {
        uint64_t u;
        int e;

    handle_number:
        if (JS_ToNumber(ctx, &d, val)) {
            *pres = 0;
            return -1;
        }
#ifdef JS_USE_SHORT_FLOAT
    handle_float64:
#endif        
        u = float64_as_uint64(d);
        e = (u >> 52) & 0x7ff;
        if (likely(e <= (1023 + 30))) {
            /* fast case */
            ret = (int32_t)d;
        } else if (!sat_flag) {
            if (e <= (1023 + 30 + 53)) {
                uint64_t v;
                /* remainder modulo 2^32 */
                v = (u & (((uint64_t)1 << 52) - 1)) | ((uint64_t)1 << 52);
                v = v << ((e - 1023) - 52 + 32);
                ret = v >> 32;
                /* take the sign into account */
                if (u >> 63)
                    ret = -ret;
            } else {
                ret = 0; /* also handles NaN and +inf */
            }
        } else {
            if (e == 2047 && (u & (((uint64_t)1 << 52) - 1)) != 0) {
                /* nan */
                ret = 0;
            } else {
                /* take the sign into account */
                if (u >> 63)
                    ret = 0x80000000;
                else
                    ret = 0x7fffffff;
            }
        }
    } else {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_BOOL:
        case JS_TAG_NULL:
        case JS_TAG_UNDEFINED:
            ret = JS_VALUE_GET_SPECIAL_VALUE(val);
            break;
        default:
            goto handle_number;
        }
    }
    *pres = ret;
    return 0;
}

int JS_ToInt32(JSContext *ctx, int *pres, JSValue val)
{
    return JS_ToInt32Internal(ctx, pres, val, FALSE);
}

int JS_ToUint32(JSContext *ctx, uint32_t *pres, JSValue val)
{
    return JS_ToInt32Internal(ctx, (int *)pres, val, FALSE);
}

int JS_ToInt32Sat(JSContext *ctx, int *pres, JSValue val)
{
    return JS_ToInt32Internal(ctx, pres, val, TRUE);
}

int JS_ToInt32Clamp(JSContext *ctx, int *pres, JSValue val, int min, int max, int min_offset)
{
    int res = JS_ToInt32Sat(ctx, pres, val);
    if (res == 0) {
        if (*pres < min) {
            *pres += min_offset;
            if (*pres < min)
                *pres = min;
        } else {
            if (*pres > max)
                *pres = max;
        }
    }
    return res;
}

int JS_ToUint8Clamp(JSContext *ctx, int *pres, JSValue val)
{
    int32_t ret;
    double d;

    if (JS_IsInt(val)) {
        ret = JS_VALUE_GET_INT(val);
        if (ret < 0)
            ret = 0;
        else if (ret > 255)
            ret = 255;
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        d = js_get_short_float(val);
        goto handle_float64;
    } else
#endif
    if (JS_IsPtr(val)) {
    handle_number:
        if (JS_ToNumber(ctx, &d, val)) {
            *pres = 0;
            return -1;
        }
#ifdef JS_USE_SHORT_FLOAT
    handle_float64:
#endif        
        if (d < 0 || isnan(d))
            ret = 0;
        else if (d > 255)
            ret = 255;
        else
            ret = js_lrint(d);
    } else {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_BOOL:
        case JS_TAG_NULL:
        case JS_TAG_UNDEFINED:
            ret = JS_VALUE_GET_SPECIAL_VALUE(val);
            break;
        default:
            goto handle_number;
        }
    }
    *pres = ret;
    return 0;
}

int js_get_length32(JSContext *ctx, uint32_t *pres, JSValue obj)
{
    JSValue len_val;
    len_val = JS_GetProperty(ctx, obj, js_get_atom(ctx, JS_ATOM_length));
    if (JS_IsException(len_val)) {
        *pres = 0;
        return -1;
    }
    return JS_ToUint32(ctx, pres, len_val);
}

no_inline JSValue js_add_slow(JSContext *ctx)
{
    JSValue *op1, *op2;
    
    op1 = &ctx->sp[1];
    op2 = &ctx->sp[0];
    *op1 = JS_ToPrimitive(ctx, *op1, HINT_NONE);
    if (JS_IsException(*op1))
        return JS_EXCEPTION;
    *op2 = JS_ToPrimitive(ctx, *op2, HINT_NONE);
    if (JS_IsException(*op2))
        return JS_EXCEPTION;
    if (JS_IsString(ctx, *op1) || JS_IsString(ctx, *op2)) {
        *op1 = JS_ToString(ctx, *op1);
        if (JS_IsException(*op1))
            return JS_EXCEPTION;
        *op2 = JS_ToString(ctx, *op2);
        if (JS_IsException(*op2))
            return JS_EXCEPTION;
        return JS_ConcatString(ctx, *op1, *op2);
    } else {
        double d1, d2, r;
        /* cannot fail */
        if (JS_ToNumber(ctx, &d1, *op1))
            return JS_EXCEPTION;
        if (JS_ToNumber(ctx, &d2, *op2))
            return JS_EXCEPTION;
        r = d1 + d2;
        return JS_NewFloat64(ctx, r);
    }
}

no_inline JSValue js_binary_arith_slow(JSContext *ctx, OPCodeEnum op)
{
    double d1, d2, r;

    if (JS_ToNumber(ctx, &d1, ctx->sp[1]))
        return JS_EXCEPTION;

    if (JS_ToNumber(ctx, &d2, ctx->sp[0]))
        return JS_EXCEPTION;
        
    switch(op) {
    case OP_sub:
        r = d1 - d2;
        break;
    case OP_mul:
        r = d1 * d2;
        break;
    case OP_div:
        r = d1 / d2;
        break;
    case OP_mod:
        r = js_fmod(d1, d2);
        break;
    case OP_pow:
        r = js_pow(d1, d2);
        break;
    default:
        abort();
    }
    return JS_NewFloat64(ctx, r);
}

no_inline JSValue js_unary_arith_slow(JSContext *ctx, OPCodeEnum op)
{
    double d;
    
    if (JS_ToNumber(ctx, &d, ctx->sp[0]))
        return JS_EXCEPTION;

    switch(op) {
    case OP_inc:
        d++;
        break;
    case OP_dec:
        d--;
        break;
    case OP_plus:
        break;
    case OP_neg:
        d = -d;
        break;
    default:
        abort();
    }
    return JS_NewFloat64(ctx, d);
}

/* specific case necessary for correct return value semantics */
no_inline JSValue js_post_inc_slow(JSContext *ctx, OPCodeEnum op)
{
    JSValue val;
    double d, r;
    
    if (JS_ToNumber(ctx, &d, ctx->sp[0]))
        return JS_EXCEPTION;
    r = d + 2 * (op - OP_post_dec) - 1;
    val = JS_NewFloat64(ctx, d);
    if (JS_IsException(val))
        return val;
    ctx->sp[0] = val;
    return JS_NewFloat64(ctx, r);
}

no_inline JSValue js_binary_logic_slow(JSContext *ctx, OPCodeEnum op)
{
    uint32_t v1, v2, r;

    if (JS_ToUint32(ctx, &v1, ctx->sp[1]))
        return JS_EXCEPTION;
    if (JS_ToUint32(ctx, &v2, ctx->sp[0]))
        return JS_EXCEPTION;
    switch(op) {
    case OP_shl:
        r = v1 << (v2 & 0x1f);
        break;
    case OP_sar:
        r = (int)v1 >> (v2 & 0x1f);
        break;
    case OP_shr:
        r = v1 >> (v2 & 0x1f);
        return JS_NewUint32(ctx, r);
    case OP_and:
        r = v1 & v2;
        break;
    case OP_or:
        r = v1 | v2;
        break;
    case OP_xor:
        r = v1 ^ v2;
        break;
    default:
        abort();
    }
    return JS_NewInt32(ctx, r);
}

no_inline JSValue js_not_slow(JSContext *ctx)
{
    uint32_t r;
    
    if (JS_ToUint32(ctx, &r, ctx->sp[0]))
        return JS_EXCEPTION;
    return JS_NewInt32(ctx, ~r);
}

no_inline JSValue js_relational_slow(JSContext *ctx, OPCodeEnum op)
{
    JSValue *op1, *op2;
    int res;
    double d1, d2;
    
    op1 = &ctx->sp[1];
    op2 = &ctx->sp[0];
    *op1 = JS_ToPrimitive(ctx, *op1, HINT_NUMBER);
    if (JS_IsException(*op1))
        return JS_EXCEPTION;
    *op2 = JS_ToPrimitive(ctx, *op2, HINT_NUMBER);
    if (JS_IsException(*op2))
        return JS_EXCEPTION;
    if (JS_IsString(ctx, *op1) && JS_IsString(ctx, *op2)) {
        res = js_string_compare(ctx, *op1, *op2);
        switch(op) {
        case OP_lt:
            res = (res < 0);
            break;
        case OP_lte:
            res = (res <= 0);
            break;
        case OP_gt:
            res = (res > 0);
            break;
        default:
        case OP_gte:
            res = (res >= 0);
            break;
        }
    } else {
        if (JS_ToNumber(ctx, &d1, *op1))
            return JS_EXCEPTION;
        if (JS_ToNumber(ctx, &d2, *op2))
            return JS_EXCEPTION;
        switch(op) {
        case OP_lt:
            res = (d1 < d2); /* if NaN return false */
            break;
        case OP_lte:
            res = (d1 <= d2); /* if NaN return false */
            break;
        case OP_gt:
            res = (d1 > d2); /* if NaN return false */
            break;
        default:
        case OP_gte:
            res = (d1 >= d2); /* if NaN return false */
            break;
        }
    }
    return JS_NewBool(res);
}

BOOL js_strict_eq(JSContext *ctx, JSValue op1, JSValue op2)
{
    BOOL res;
    
    if (JS_IsNumber(ctx, op1)) {
        if (!JS_IsNumber(ctx, op2)) {
            res = FALSE;
        } else {
            double d1, d2;
            /* cannot fail */
            JS_ToNumber(ctx, &d1, op1);
            JS_ToNumber(ctx, &d2, op2);
            res = (d1 == d2); /* if NaN return false */
        }
    } else if (JS_IsString(ctx, op1)) {
        if (!JS_IsString(ctx, op2)) {
            res = FALSE;
        } else {
            res = js_string_eq(ctx, op1, op2);
        }
    } else {
        /* special value or object */
        res = (op1 == op2);
    }
    return res;
}

JSValue js_strict_eq_slow(JSContext *ctx, BOOL is_neq)
{
    BOOL res;
    res = js_strict_eq(ctx, ctx->sp[1], ctx->sp[0]);
    return JS_NewBool(res ^ is_neq);
}

enum {
    /* special tags to simplify the comparison */
    JS_ETAG_NUMBER = JS_TAG_SPECIAL | (8 << 2),
    JS_ETAG_STRING = JS_TAG_SPECIAL | (9 << 2),
    JS_ETAG_OBJECT = JS_TAG_SPECIAL | (10 << 2),
};

int js_eq_get_type(JSContext *ctx, JSValue val)
{
    if (JS_IsIntOrShortFloat(val)) {
        return JS_ETAG_NUMBER;
    } else if (JS_IsPtr(val)) {
        void *ptr = JS_VALUE_TO_PTR(val);
        switch(js_get_mtag(ptr)) {
        case JS_MTAG_FLOAT64:
            return JS_ETAG_NUMBER;
        case JS_MTAG_STRING:
            return JS_ETAG_STRING;
        default:
        case JS_MTAG_OBJECT:
            return JS_ETAG_OBJECT;
        }
    } else {
        int tag = JS_VALUE_GET_SPECIAL_TAG(val);
        switch(tag) {
        case JS_TAG_STRING_CHAR:
            return JS_ETAG_STRING;
        case JS_TAG_SHORT_FUNC:
            return JS_ETAG_OBJECT;
        default:
            return tag;
        }
    }
}

no_inline JSValue js_eq_slow(JSContext *ctx, BOOL is_neq)
{
    JSValue op1, op2;
    int tag1, tag2;
    BOOL res;
    
 redo:
    op1 = ctx->sp[1];
    op2 = ctx->sp[0];
    tag1 = js_eq_get_type(ctx, op1);
    tag2 = js_eq_get_type(ctx, op2);
    if (tag1 == tag2) {
        res = js_strict_eq(ctx, op1, op2);
    } else if ((tag1 == JS_TAG_NULL && tag2 == JS_TAG_UNDEFINED) ||
               (tag2 == JS_TAG_NULL && tag1 == JS_TAG_UNDEFINED)) {
        res = TRUE;
    } else if ((tag1 == JS_ETAG_STRING && tag2 == JS_ETAG_NUMBER) ||
               (tag2 == JS_ETAG_STRING && tag1 == JS_ETAG_NUMBER)) {
        double d1;
        double d2;
        if (JS_ToNumber(ctx, &d1, ctx->sp[1]))
            return JS_EXCEPTION;
        if (JS_ToNumber(ctx, &d2, ctx->sp[0]))
            return JS_EXCEPTION;
        res = (d1 == d2);
    } else if (tag1 == JS_TAG_BOOL) {
        ctx->sp[1] = JS_NewShortInt(JS_VALUE_GET_SPECIAL_VALUE(op1));
        goto redo;
    } else if (tag2 == JS_TAG_BOOL) {
        ctx->sp[0] = JS_NewShortInt(JS_VALUE_GET_SPECIAL_VALUE(op2));
        goto redo;
    } else if (tag1 == JS_ETAG_OBJECT &&
               (tag2 == JS_ETAG_NUMBER || tag2 == JS_ETAG_STRING)) {
        ctx->sp[1] = JS_ToPrimitive(ctx, op1, HINT_NONE);
        if (JS_IsException(ctx->sp[1]))
            return JS_EXCEPTION;
        goto redo;
    } else if (tag2 == JS_ETAG_OBJECT &&
               (tag1 == JS_ETAG_NUMBER || tag1 == JS_ETAG_STRING)) {
        ctx->sp[0] = JS_ToPrimitive(ctx, op2, HINT_NONE);
        if (JS_IsException(ctx->sp[0]))
            return JS_EXCEPTION;
        goto redo;
    } else {
        res = FALSE;
    }
    return JS_NewBool(res ^ is_neq);
}

JSValue js_operator_in(JSContext *ctx)
{
    JSValue prop;
    int res;

    if (js_eq_get_type(ctx, ctx->sp[0]) != JS_ETAG_OBJECT)
        return JS_ThrowTypeError(ctx, "invalid 'in' operand");
    prop = JS_ToPropertyKey(ctx, ctx->sp[1]);
    if (JS_IsException(prop))
        return prop;
    res = JS_HasProperty(ctx, ctx->sp[0], prop);
    return JS_NewBool(res);
}

JSValue js_operator_instanceof(JSContext *ctx)
{
    JSValue op1, op2, proto;
    JSObject *p;

    op1 = ctx->sp[1];
    op2 = ctx->sp[0];
    if (!JS_IsFunctionObject(ctx, op2))
        return JS_ThrowTypeError(ctx, "invalid 'instanceof' right operand");
    proto = JS_GetProperty(ctx, op2, js_get_atom(ctx, JS_ATOM_prototype));
    if (JS_IsException(proto))
        return proto;
    if (!JS_IsObject(ctx, op1))
        return JS_NewBool(FALSE);
    p = JS_VALUE_TO_PTR(op1);
    for(;;) {
        if (p->proto == JS_NULL)
            return JS_NewBool(FALSE);
        if (p->proto == proto)
            return JS_NewBool(TRUE);
        p = JS_VALUE_TO_PTR(p->proto);
    }
    return JS_NewBool(FALSE);
}

JSValue js_operator_typeof(JSContext *ctx, JSValue val)
{
    int tag, atom;
    tag = js_eq_get_type(ctx, val);
    switch(tag) {
    case JS_ETAG_NUMBER:
        atom = JS_ATOM_number;
        break;
    case JS_ETAG_STRING:
        atom = JS_ATOM_string;
        break;
    case JS_TAG_BOOL:
        atom = JS_ATOM_boolean;
        break;
    case JS_ETAG_OBJECT:
        if (JS_IsFunction(ctx, val))
            atom = JS_ATOM_function;
        else
            atom = JS_ATOM_object;
        break;
    case JS_TAG_NULL:
        atom = JS_ATOM_object;
        break;
    default:
    case JS_TAG_UNDEFINED:
        atom = JS_ATOM_undefined;
        break;
    }
    return js_get_atom(ctx, atom);
}

void js_reverse_val(JSValue *tab, int n)
{
    int i;
    JSValue tmp;
    
    for(i = 0; i < n / 2; i++) {
        tmp = tab[i];
        tab[i] = tab[n - 1 - i];
        tab[n - 1 - i] = tmp;
    }
}
 
JSValue js_closure(JSContext *ctx, JSValue bfunc, JSValue *fp)
{
    JSFunctionBytecode *b;
    JSObject *p;
    JSGCRef bfunc_ref, closure_ref;
    JSValueArray *ext_vars;
    JSValue closure;
    int ext_vars_len;
    
    b = JS_VALUE_TO_PTR(bfunc);
    if (b->ext_vars != JS_NULL) {
        ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
        ext_vars_len = ext_vars->size / 2;
    } else {
        ext_vars_len = 0;
    }
    
    JS_PUSH_VALUE(ctx, bfunc);
    closure = JS_NewObjectProtoClass(ctx, ctx->class_proto[JS_CLASS_CLOSURE], JS_CLASS_CLOSURE,
                                     sizeof(JSClosureData) + ext_vars_len * sizeof(JSValue));
    JS_POP_VALUE(ctx, bfunc);
    if (JS_IsException(closure))
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(closure);
    p->u.closure.func_bytecode = bfunc;
        
    if (ext_vars_len > 0) {
        JSValue *pfirst_var_ref, val;
        int i, var_idx, var_kind, decl;
        
        /* initialize the var_refs in case of exception */
        memset(p->u.closure.var_refs, 0, sizeof(JSValue) * ext_vars_len);
        if (fp) {
            pfirst_var_ref = &fp[FRAME_OFFSET_FIRST_VARREF];
        } else {
            pfirst_var_ref = NULL; /* not used */
        }
        for(i = 0; i < ext_vars_len; i++) {
            b = JS_VALUE_TO_PTR(bfunc);
            ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
            decl = JS_VALUE_GET_INT(ext_vars->arr[2 * i + 1]);
            var_kind = decl >> 16;
            var_idx = decl & 0xffff;
            JS_PUSH_VALUE(ctx, bfunc);
            JS_PUSH_VALUE(ctx, closure);
            switch(var_kind) {
            case JS_VARREF_KIND_ARG:
                val = get_var_ref(ctx, pfirst_var_ref, 
                                  &fp[FRAME_OFFSET_ARG0 + var_idx]);
                break;
            case JS_VARREF_KIND_VAR:
                val = get_var_ref(ctx, pfirst_var_ref,
                                  &fp[FRAME_OFFSET_VAR0 - var_idx]);
                break;
            case JS_VARREF_KIND_VAR_REF:
                {
                    JSObject *p;
                    p = JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]);
                    val = p->u.closure.var_refs[var_idx];
                }
                break;
            case JS_VARREF_KIND_GLOBAL:
                /* only for eval code */
                val = add_global_var(ctx, ext_vars->arr[2 * i], (var_idx != 0));
                break;
            default:
                abort();
            }
            JS_POP_VALUE(ctx, closure);
            JS_POP_VALUE(ctx, bfunc);
            if (JS_IsException(val))
                return val;
            p = JS_VALUE_TO_PTR(closure);
            p->u.closure.var_refs[i] = val;
        }
    }
    return closure;
}

JSValue js_for_of_start(JSContext *ctx, BOOL is_for_in)
{
    JSValueArray *arr;

    if (is_for_in) {
        /* XXX: not spec compliant and slow. We return only the own
           object keys. */
        ctx->sp[0] = js_object_keys(ctx, NULL, 1, &ctx->sp[0]);
        if (JS_IsException(ctx->sp[0]))
            return JS_EXCEPTION;
    }
    
    if (!js_get_object_class(ctx, ctx->sp[0], JS_CLASS_ARRAY))
        return JS_ThrowTypeError(ctx, "unsupported type in for...of");
    
    arr = js_alloc_value_array(ctx, 0, 2);
    if (!arr)
        return JS_EXCEPTION;
    arr->arr[0] = ctx->sp[0];
    arr->arr[1] = JS_NewShortInt(0);
    return JS_VALUE_FROM_PTR(arr);
}

JSValue js_for_of_next(JSContext *ctx)
{
    JSValueArray *arr, *arr1;
    JSObject *p;
    int pos;
    
    arr = JS_VALUE_TO_PTR(ctx->sp[0]);
    pos = JS_VALUE_GET_INT(arr->arr[1]);
    p = JS_VALUE_TO_PTR(arr->arr[0]);
    if (pos >= p->u.array.len) {
        ctx->sp[-2] = JS_TRUE;
        ctx->sp[-1] = JS_UNDEFINED;
    } else {
        ctx->sp[-2] = JS_FALSE;
        arr1 = JS_VALUE_TO_PTR(p->u.array.tab);
        ctx->sp[-1] = arr1->arr[pos];
        arr->arr[1] = JS_NewShortInt(pos + 1);
    }
    return JS_UNDEFINED;
}

JSValue js_new_c_function_proto(JSContext *ctx, int func_idx, JSValue proto, BOOL has_params, JSValue params)
{
    JSObject *p;
    JSGCRef params_ref;
    
    JS_PUSH_VALUE(ctx, params);
    p = JS_NewObjectProtoClass1(ctx, proto, JS_CLASS_C_FUNCTION,
                                sizeof(JSCFunctionData) - (!has_params ? sizeof(JSValue) : 0));
    JS_POP_VALUE(ctx, params);
    if (!p)
        return JS_EXCEPTION;
    p->u.cfunc.idx = func_idx;
    if (has_params)
        p->u.cfunc.params = params;
    return JS_VALUE_FROM_PTR(p);
}

JSValue JS_NewCFunctionParams(JSContext *ctx, int func_idx, JSValue params)
{
    return js_new_c_function_proto(ctx, func_idx, ctx->class_proto[JS_CLASS_CLOSURE], TRUE, params);
}

JSValue js_call_constructor_start(JSContext *ctx, JSValue func)
{
    JSValue proto;
    proto = JS_GetProperty(ctx, func, js_get_atom(ctx, JS_ATOM_prototype));
    if (JS_IsException(proto))
        return proto;
    if (!JS_IsObject(ctx, proto))
        proto = ctx->class_proto[JS_CLASS_OBJECT];
    return JS_NewObjectProtoClass(ctx, proto, JS_CLASS_OBJECT, 0);
}

#define SAVE() do { \
        fp[FRAME_OFFSET_CUR_PC] = JS_NewShortInt(pc - ((JSByteArray *)JS_VALUE_TO_PTR(b->byte_code))->buf); \
        ctx->sp = sp; \
        ctx->fp = fp; \
    } while (0)

/* only need to restore PC */
#define RESTORE() do { \
        b = JS_VALUE_TO_PTR(((JSObject *)JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]))->u.closure.func_bytecode); \
        pc = ((JSByteArray *)JS_VALUE_TO_PTR(b->byte_code))->buf + JS_VALUE_GET_INT(fp[FRAME_OFFSET_CUR_PC]); \
    } while (0)

JSValue __js_poll_interrupt(JSContext *ctx)
{
    ctx->interrupt_counter = JS_INTERRUPT_COUNTER_INIT;
    if (ctx->interrupt_handler && ctx->interrupt_handler(ctx, ctx->opaque)) {
        JS_ThrowInternalError(ctx, "interrupted");
        ctx->current_exception_is_uncatchable = TRUE;
        return JS_EXCEPTION;
    }
    return JS_UNDEFINED;
}

/* handle user interruption */
#define POLL_INTERRUPT() do {                           \
        if (unlikely(--ctx->interrupt_counter <= 0)) {  \
            SAVE();                                     \
            val = __js_poll_interrupt(ctx);             \
            RESTORE();                                  \
            if (JS_IsException(val))                    \
                goto exception;                         \
        }                                               \
    } while(0)

/* must use JS_StackCheck() before using it */
void JS_PushArg(JSContext *ctx, JSValue val)
{
#ifdef DEBUG_GC
    assert((ctx->sp - 1) >= ctx->stack_bottom);
#endif
    *--ctx->sp = val;
}

/* Usage:
   if (JS_StackCheck(ctx, n + 2)) ...
   JS_PushArg(ctx, arg[n - 1]);
   ...
   JS_PushArg(ctx, arg[0]);
   JS_PushArg(ctx, func);
   JS_PushArg(ctx, this_obj);
   res = JS_Call(ctx, n);
*/
JSValue JS_Call(JSContext *ctx, int call_flags)
{
    JSValue *fp, *sp, val = JS_UNDEFINED, *initial_fp;
    uint8_t *pc;
    /* temporary variables */
    int opcode = OP_invalid, i;
    JSFunctionBytecode *b;
#ifdef JS_USE_SHORT_FLOAT
    double dr;
#endif
    
    if (ctx->js_call_rec_count >= JS_MAX_CALL_RECURSE)
        return JS_ThrowInternalError(ctx, "C stack overflow");
    ctx->js_call_rec_count++;

    sp = ctx->sp;
    fp = ctx->fp;
    initial_fp = fp;
    b = NULL;
    pc = NULL;
    goto function_call;

#define CASE(op)        case op
#define DEFAULT         default
#define BREAK           break
    
    for(;;) {
        opcode = *pc++;
#ifdef DUMP_EXEC
        {
            JSByteArray *arr;
            arr = JS_VALUE_TO_PTR(b->byte_code);
            js_printf(ctx, "    sp=%d\n", (int)(sp - fp));
            js_printf(ctx, "%4d: %s\n", (int)(pc - arr->buf - 1),
                   opcode_info[opcode].name);
        }
#endif
        switch(opcode) {
        CASE(OP_push_minus1):
        CASE(OP_push_0):
        CASE(OP_push_1):
        CASE(OP_push_2):
        CASE(OP_push_3):
        CASE(OP_push_4):
        CASE(OP_push_5):
        CASE(OP_push_6):
        CASE(OP_push_7):
            *--sp = JS_NewShortInt(opcode - OP_push_0);
            BREAK;
        CASE(OP_push_i8):
            *--sp = JS_NewShortInt(get_i8(pc));
            pc += 1;
            BREAK;
        CASE(OP_push_i16):
            *--sp = JS_NewShortInt(get_i16(pc));
            pc += 2;
            BREAK;
        CASE(OP_push_value):
            *--sp = get_u32(pc);
            pc += 4;
            BREAK;
        CASE(OP_push_const):
            {
                JSValueArray *cpool = JS_VALUE_TO_PTR(b->cpool);
                *--sp = cpool->arr[get_u16(pc)];
                pc += 2;
            }
            BREAK;
        CASE(OP_undefined):
            *--sp = JS_UNDEFINED;
            BREAK;
        CASE(OP_null):
            *--sp = JS_NULL;
            BREAK;
        CASE(OP_push_this):
            *--sp = fp[FRAME_OFFSET_THIS_OBJ];
            BREAK;
        CASE(OP_push_false):
            *--sp = JS_FALSE;
            BREAK;
        CASE(OP_push_true):
            *--sp = JS_TRUE;
            BREAK;
        CASE(OP_object):
            {
                int n = get_u16(pc);
                SAVE();
                val = JS_NewObjectPrealloc(ctx, n);
                RESTORE();
                if (JS_IsException(val))
                    goto exception;
                *--sp = val;
                pc += 2;
            }
            BREAK;
        CASE(OP_regexp):
            {
                JSObject *p;
                SAVE();
                val = JS_NewObjectClass(ctx, JS_CLASS_REGEXP, sizeof(JSRegExp));
                RESTORE();
                if (JS_IsException(val))
                    goto exception;
                p = JS_VALUE_TO_PTR(val);
                p->u.regexp.source = sp[1];
                p->u.regexp.byte_code = sp[0];
                p->u.regexp.last_index = 0;
                sp[1] = val;
                sp++;
            }
            BREAK;
        CASE(OP_array_from):
            {
                JSObject *p;
                JSValueArray *arr;
                int i, argc;

                argc = get_u16(pc);
                SAVE();
                val = JS_NewArray(ctx, argc);
                RESTORE();
                if (JS_IsException(val))
                    goto exception;
                pc += 2;
                p = JS_VALUE_TO_PTR(val);
                arr = JS_VALUE_TO_PTR(p->u.array.tab);
                for(i = 0; i < argc; i++) {
                    arr->arr[i] = sp[argc - 1 - i];
                }
                sp += argc;
                *--sp = val;
            }
            BREAK;
        CASE(OP_this_func):
            *--sp = fp[FRAME_OFFSET_FUNC_OBJ];
            BREAK;
        CASE(OP_arguments):
            {
                JSObject *p;
                JSValueArray *arr;
                int i, argc;
                
                argc = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CALL_FLAGS]) & FRAME_CF_ARGC_MASK;
                SAVE();
                val = JS_NewArray(ctx, argc);
                RESTORE();
                if (JS_IsException(val))
                    goto exception;
                p = JS_VALUE_TO_PTR(val);
                arr = JS_VALUE_TO_PTR(p->u.array.tab);
                for(i = 0; i < argc; i++) {
                    arr->arr[i] = fp[FRAME_OFFSET_ARG0 + i];
                }
                *--sp = val;
            }
            BREAK;
        CASE(OP_new_target):
            call_flags = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CALL_FLAGS]);
            if (call_flags & FRAME_CF_CTOR) {
                *--sp = fp[FRAME_OFFSET_FUNC_OBJ];
            } else {
                *--sp = JS_UNDEFINED;
            }
            BREAK;
        CASE(OP_drop):
            sp++;
            BREAK;
        CASE(OP_nip):
            sp[1] = sp[0];
            sp++;
            BREAK;
        CASE(OP_dup):
            sp--;
            sp[0] = sp[1];
            BREAK;
        CASE(OP_dup2):
            sp -= 2;
            sp[0] = sp[2];
            sp[1] = sp[3];
            BREAK;
        CASE(OP_insert2):
            sp[-1] = sp[0];
            sp[0] = sp[1];
            sp[1] = sp[-1];
            sp--;
            BREAK;
        CASE(OP_insert3):
            sp[-1] = sp[0];
            sp[0] = sp[1];
            sp[1] = sp[2];
            sp[2] = sp[-1];
            sp--;
            BREAK;
        CASE(OP_perm3): /* obj a b -> a obj b (213) */
            {
                JSValue tmp;
                tmp = sp[1];
                sp[1] = sp[2];
                sp[2] = tmp;
            }
            BREAK;
        CASE(OP_rot3l): /* x a b -> a b x (231) */
            {
                JSValue tmp;
                tmp = sp[2];
                sp[2] = sp[1];
                sp[1] = sp[0];
                sp[0] = tmp;
            }
            BREAK;
        CASE(OP_perm4): /* obj prop a b -> a obj prop b */
            {
                JSValue tmp;
                tmp = sp[1];
                sp[1] = sp[2];
                sp[2] = sp[3];
                sp[3] = tmp;
            }
            BREAK;
        CASE(OP_swap): /* a b -> b a */
            {
                JSValue tmp;
                tmp = sp[1];
                sp[1] = sp[0];
                sp[0] = tmp;
            }
            BREAK;

        CASE(OP_fclosure):
            {
                int idx;
                JSValueArray *cpool = JS_VALUE_TO_PTR(b->cpool);
                idx = get_u16(pc);
                SAVE();
                val = js_closure(ctx, cpool->arr[idx], fp);
                RESTORE();
                if (unlikely(JS_IsException(val)))
                    goto exception;
                pc += 2;
                *--sp = val;
            }
            BREAK;

        CASE(OP_call_constructor):
            call_flags = get_u16(pc) | FRAME_CF_CTOR;
            goto global_function_call;
        CASE(OP_call):
            call_flags = get_u16(pc);
        global_function_call:
            js_reverse_val(sp, (call_flags & FRAME_CF_ARGC_MASK) + 1);
            *--sp = JS_UNDEFINED;
            goto generic_function_call;
        CASE(OP_call_method):
            {
                int n, argc, short_func_idx;
                JSValue func_obj;
                JSObject *p;
                JSByteArray *byte_code;
                
                call_flags = get_u16(pc);

                n = (call_flags & FRAME_CF_ARGC_MASK) + 2;
                js_reverse_val(sp, n);
                
            generic_function_call:
                POLL_INTERRUPT();
                byte_code = JS_VALUE_TO_PTR(b->byte_code);
                /* save pc + 1 of the current call */
                fp[FRAME_OFFSET_CUR_PC] = JS_NewShortInt(pc - byte_code->buf);
            function_call:
                *--sp = JS_NewShortInt(call_flags);
                *--sp = SP_TO_VALUE(ctx, fp);
                
                func_obj = sp[FRAME_OFFSET_FUNC_OBJ];
#if defined(DUMP_EXEC)
                JS_DumpValue(ctx, "calling", func_obj);
#endif
                if (!JS_IsPtr(func_obj)) {
                    if (JS_VALUE_GET_SPECIAL_TAG(func_obj) != JS_TAG_SHORT_FUNC)
                        goto not_a_function;
                    short_func_idx = JS_VALUE_GET_SPECIAL_VALUE(func_obj);
                    p = NULL;
                    goto c_function;
                } else {
                    p = JS_VALUE_TO_PTR(func_obj);
                    if (p->mtag != JS_MTAG_OBJECT)
                        goto not_a_function;
                    if (p->class_id == JS_CLASS_C_FUNCTION) {
                        const JSCFunctionDef *fd;
                        int pushed_argc;
                        short_func_idx = p->u.cfunc.idx;
                    c_function:
                        fd = &ctx->c_function_table[short_func_idx];
                        /* add undefined arguments if the caller did not
                           provide enough arguments */
                        call_flags = JS_VALUE_GET_INT(sp[FRAME_OFFSET_CALL_FLAGS]);
                        if ((call_flags & FRAME_CF_CTOR) &&
                            (fd->def_type != JS_CFUNC_constructor &&
                             fd->def_type != JS_CFUNC_constructor_magic)) {
                            sp += 2; /* go back to the caller frame */
                            ctx->sp = sp;
                            ctx->fp = fp;
                            val = JS_ThrowTypeError(ctx, "not a constructor");
                            goto call_exception;
                        }

                        argc = call_flags & FRAME_CF_ARGC_MASK;
                        /* JS_StackCheck may trigger a gc */
                        ctx->sp = sp;
                        ctx->fp = fp;
                        n = JS_StackCheck(ctx, max_int(fd->arg_count - argc, 0));
                        if (n) {
                            sp += 2; /* go back to the caller frame */
                            val = JS_EXCEPTION;
                            goto call_exception;
                        }
                        pushed_argc = argc;
                        if (fd->arg_count > argc) {
                            n = fd->arg_count - argc;
                            sp -= n;
                            for(i = 0; i < FRAME_OFFSET_ARG0 + argc; i++)
                                sp[i] = sp[i + n];
                            for(i = 0; i < n; i++)
                                sp[FRAME_OFFSET_ARG0 + argc + i] = JS_UNDEFINED;
                            pushed_argc = fd->arg_count;
                        }
                        fp = sp;
                        ctx->sp = sp;
                        ctx->fp = fp;
                        switch(fd->def_type) {
                        case JS_CFUNC_generic:
                        case JS_CFUNC_constructor:
                            val = fd->func.generic(ctx, &fp[FRAME_OFFSET_THIS_OBJ],
                                                   call_flags & (FRAME_CF_CTOR | FRAME_CF_ARGC_MASK),
                                                   fp + FRAME_OFFSET_ARG0);
                            break;
                        case JS_CFUNC_generic_magic:
                        case JS_CFUNC_constructor_magic:
                            val = fd->func.generic_magic(ctx, &fp[FRAME_OFFSET_THIS_OBJ],
                                                   call_flags & (FRAME_CF_CTOR | FRAME_CF_ARGC_MASK),
                                                   fp + FRAME_OFFSET_ARG0, fd->magic);
                            break;
                        case JS_CFUNC_generic_params:
                            p = JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]);
                            val = fd->func.generic_params(ctx, &fp[FRAME_OFFSET_THIS_OBJ],
                                                          call_flags & (FRAME_CF_CTOR | FRAME_CF_ARGC_MASK),
                                                          fp + FRAME_OFFSET_ARG0, p->u.cfunc.params);
                            break;
                        case JS_CFUNC_f_f:
                            {
                                double d;
                                if (JS_ToNumber(ctx, &d, fp[FRAME_OFFSET_ARG0])) {
                                    val = JS_EXCEPTION;
                                } else {
                                    d = fd->func.f_f(d);
                                }
                                val = JS_NewFloat64(ctx, d);
                            }
                            break;
                        default:
                            assert(0);
                        }
                        if (JS_IsExceptionOrTailCall(val) &&
                            JS_VALUE_GET_SPECIAL_VALUE(val) >= JS_EX_CALL) {
                            JSValue *fp1, *sp1;
                            /* tail call: equivalent to calling the
                               function after the C function */
                            /* XXX: handle the call flags of the caller ? */
                            call_flags = JS_VALUE_GET_SPECIAL_VALUE(val) - JS_EX_CALL;
                            sp = ctx->sp;
                            /* pop the frame */
                            fp1 = VALUE_TO_SP(ctx, fp[FRAME_OFFSET_SAVED_FP]);
                            /* move the new arguments at the correct stack position */
                            argc = (call_flags & FRAME_CF_ARGC_MASK) + 2;
                            sp1 = fp + FRAME_OFFSET_ARG0 + pushed_argc - argc;
                            memmove(sp1, sp, sizeof(*sp) * (argc));
                            sp = sp1;
                            fp = fp1;
                            goto function_call;
                        } else {
                            sp = fp + FRAME_OFFSET_ARG0 + pushed_argc;
                            goto return_call;
                        }
                    } else if (p->class_id == JS_CLASS_CLOSURE) {
                        int n_vars;
                        call_flags = JS_VALUE_GET_INT(sp[FRAME_OFFSET_CALL_FLAGS]);
                        if (call_flags & FRAME_CF_CTOR) {
                            ctx->sp = sp;
                            ctx->fp = fp;
                            /* Note: can recurse at this point */
                            val = js_call_constructor_start(ctx, func_obj);
                            if (JS_IsException(val))
                                goto call_exception;
                            sp[FRAME_OFFSET_THIS_OBJ] = val;
                            func_obj = sp[FRAME_OFFSET_FUNC_OBJ];
                            p = JS_VALUE_TO_PTR(func_obj);
                        }
                        b = JS_VALUE_TO_PTR(p->u.closure.func_bytecode);
                        if (b->vars != JS_NULL) {
                            JSValueArray *vars = JS_VALUE_TO_PTR(b->vars);
                            n_vars = vars->size - b->arg_count;
                        } else {
                            n_vars = 0;
                        }
                        argc = call_flags & FRAME_CF_ARGC_MASK;
                        /* JS_StackCheck may trigger a gc */
                        ctx->sp = sp;
                        ctx->fp = fp;
                        n = JS_StackCheck(ctx, max_int(b->arg_count - argc, 0) + 2 + n_vars +
                                           b->stack_size);
                        if (n) {
                            val = JS_EXCEPTION;
                            goto call_exception;
                        }
                        func_obj = sp[FRAME_OFFSET_FUNC_OBJ];
                        p = JS_VALUE_TO_PTR(func_obj);
                        b = JS_VALUE_TO_PTR(p->u.closure.func_bytecode);
                        /* add undefined arguments if the caller did not
                           provide enough arguments */
                        if (unlikely(b->arg_count > argc)) {
                            n = b->arg_count - argc;
                            sp -= n;
                            for(i = 0; i < FRAME_OFFSET_ARG0 + argc; i++)
                                sp[i] = sp[i + n];
                            for(i = 0; i < n; i++)
                                sp[FRAME_OFFSET_ARG0 + argc + i] = JS_UNDEFINED;
                        }
                        fp = sp;
                        *--sp = JS_NewShortInt(0); /* FRAME_OFFSET_CUR_PC */
                        *--sp = JS_NULL; /* FRAME_OFFSET_FIRST_VARREF */
                        sp -= n_vars;
                        for(i = 0; i < n_vars; i++)
                            sp[i] = JS_UNDEFINED;
                        byte_code = JS_VALUE_TO_PTR(b->byte_code);
                        pc = byte_code->buf;
                    } else {
                    not_a_function:
                        sp += 2; /* go back to the caller frame */
                        ctx->sp = sp;
                        ctx->fp = fp;
                        val = JS_ThrowTypeError(ctx, "not a function");
                    call_exception:
                        if (!pc) {
                            goto done;
                        } else {
                            RESTORE();
                            goto exception;
                        }
                    }
                }
            }
            BREAK;

        exception:
            /* 'val' must contain the exception */
            {
                JSValue *stack_top, val2;
                JSValueArray *vars;
                int v;
                /* exception before entering in the first function ?
                   (XXX: remove this test) */
                if (!pc) 
                    goto done;
                v = JS_VALUE_GET_SPECIAL_VALUE(val);
                if (v >= JS_EX_CALL) {
                    /* tail call */
                    call_flags = JS_VALUE_GET_SPECIAL_VALUE(val) - JS_EX_CALL;
                    /* the opcode has only one byte, hence the PC must
                       be updated accordingly after the function
                       returns */
                    if (opcode == OP_get_length ||
                        opcode == OP_get_length2 ||
                        opcode == OP_get_array_el ||
                        opcode == OP_get_array_el2 ||
                        opcode == OP_put_array_el) {
                        call_flags |= FRAME_CF_PC_ADD1;
                    }
                    //                    js_printf(ctx, "tail call: 0x%x\n", call_flags);
                    goto generic_function_call;
                }
                /* XXX: start gc in case of JS_EXCEPTION_MEM */
                stack_top = fp + FRAME_OFFSET_VAR0 + 1;
                if (b->vars != JS_NULL) {
                    vars = JS_VALUE_TO_PTR(b->vars);
                    stack_top -= (vars->size - b->arg_count);
                }
                if (ctx->current_exception_is_uncatchable) {
                    sp = stack_top;
                } else {
                    while (sp < stack_top) {
                        val2 = *sp++;
                        if (JS_VALUE_GET_SPECIAL_TAG(val2) == JS_TAG_CATCH_OFFSET) {
                            JSByteArray *byte_code;
                            /* exception caught by a 'catch' in the
                               current function */
                            *--sp = ctx->current_exception;
                            ctx->current_exception = JS_UNINITIALIZED;
                            byte_code = JS_VALUE_TO_PTR(b->byte_code);
                            pc = byte_code->buf + JS_VALUE_GET_SPECIAL_VALUE(val2);
                            goto restart;
                        }
                    }
                }
            }
            goto generic_return;

        CASE(OP_return_undef):
            val = JS_UNDEFINED;
            goto generic_return;
            
        CASE(OP_return):
            val = sp[0];
        generic_return:
            {
                JSObject *p;
                int argc, pc_offset;
                JSValue val2;
                JSVarRef *pv;
                JSByteArray *byte_code;
                
                /* detach the variable references */
                val2 = fp[FRAME_OFFSET_FIRST_VARREF];
                while (val2 != JS_NULL) {
                    pv = JS_VALUE_TO_PTR(val2);
                    val2 = pv->u.next;
                    assert(!pv->is_detached);
                    pv->u.value = *pv->u.pvalue;
                    pv->is_detached = TRUE;
                    /* shrink 'pv' */
                    set_free_block((uint8_t *)pv + sizeof(JSVarRef) - sizeof(JSValue), sizeof(JSValue));
                }

                call_flags = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CALL_FLAGS]);
                if (unlikely(call_flags & FRAME_CF_CTOR)) {
                    if (!JS_IsException(val) && !JS_IsObject(ctx, val)) {
                        val = fp[FRAME_OFFSET_THIS_OBJ];
                    }
                }
                argc = call_flags & FRAME_CF_ARGC_MASK;
                argc = max_int(argc, b->arg_count);
                sp = fp + FRAME_OFFSET_ARG0 + argc;
        return_call:
                call_flags = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CALL_FLAGS]);
                /* XXX: restore stack_bottom to reduce memory usage */
                fp = VALUE_TO_SP(ctx, fp[FRAME_OFFSET_SAVED_FP]);
                if (fp == initial_fp)
                    goto done;
                pc_offset = JS_VALUE_GET_INT(fp[FRAME_OFFSET_CUR_PC]);
                p = JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]);
                b = JS_VALUE_TO_PTR(p->u.closure.func_bytecode);
                byte_code = JS_VALUE_TO_PTR(b->byte_code);
                pc = byte_code->buf + pc_offset;
                /* now we are in the calling function */
                if (JS_IsException(val))
                    goto exception;
                if (!(call_flags & FRAME_CF_POP_RET))
                    *--sp = val;
                /* Note: if variable size call, can add a flag in call_flags */
                if (!(call_flags & FRAME_CF_PC_ADD1))
                    pc += 2; /* skip the call arg or get_field/put_field arg */
            }
            BREAK;
                
       CASE(OP_catch):
            {
                int32_t diff;
                JSByteArray *byte_code = JS_VALUE_TO_PTR(b->byte_code);
                diff = get_u32(pc);
                *--sp = JS_VALUE_MAKE_SPECIAL(JS_TAG_CATCH_OFFSET, pc + diff - byte_code->buf);
                pc += 4;
            }
            BREAK;
        CASE(OP_throw):
            val = *sp++;
            SAVE();
            val = JS_Throw(ctx, val);
            RESTORE();
            goto exception;
        CASE(OP_gosub):
            {
                int32_t diff;
                JSByteArray *byte_code = JS_VALUE_TO_PTR(b->byte_code);
                diff = get_u32(pc);
                *--sp = JS_NewShortInt(pc + 4 - byte_code->buf);
                pc += diff;
            }
            BREAK;
        CASE(OP_ret):
            {
                JSByteArray *byte_code = JS_VALUE_TO_PTR(b->byte_code);
                uint32_t pos;
                if (unlikely(!JS_IsInt(sp[0])))
                    goto ret_fail;
                pos = JS_VALUE_GET_INT(sp[0]);
                if (unlikely(pos >= byte_code->size)) {
                ret_fail:
                    SAVE();
                    val = JS_ThrowInternalError(ctx, "invalid ret value");
                    RESTORE();
                    goto exception;
                }
                sp++;
                pc = byte_code->buf + pos;
            }
            BREAK;

        CASE(OP_get_loc):
            {
                int idx;
                idx = get_u16(pc);
                pc += 2;
                *--sp = fp[FRAME_OFFSET_VAR0 - idx];
            }
            BREAK;
        CASE(OP_put_loc):
            {
                int idx;
                idx = get_u16(pc);
                pc += 2;
                fp[FRAME_OFFSET_VAR0 - idx] = sp[0];
                sp++;
            }
            BREAK;
        CASE(OP_get_arg):
            {
                int idx;
                idx = get_u16(pc);
                pc += 2;
                *--sp = fp[FRAME_OFFSET_ARG0 + idx];
            }
            BREAK;
        CASE(OP_put_arg):
            {
                int idx;
                idx = get_u16(pc);
                pc += 2;
                fp[FRAME_OFFSET_ARG0 + idx] = sp[0];
                sp++;
            }
            BREAK;
            
        CASE(OP_get_loc0): *--sp = fp[FRAME_OFFSET_VAR0 - 0]; BREAK;
        CASE(OP_get_loc1): *--sp = fp[FRAME_OFFSET_VAR0 - 1]; BREAK;
        CASE(OP_get_loc2): *--sp = fp[FRAME_OFFSET_VAR0 - 2]; BREAK;
        CASE(OP_get_loc3): *--sp = fp[FRAME_OFFSET_VAR0 - 3]; BREAK;
        CASE(OP_get_loc8): *--sp = fp[FRAME_OFFSET_VAR0 - *pc++]; BREAK;
            
        CASE(OP_put_loc0): fp[FRAME_OFFSET_VAR0 - 0] = *sp++; BREAK;
        CASE(OP_put_loc1): fp[FRAME_OFFSET_VAR0 - 1] = *sp++; BREAK;
        CASE(OP_put_loc2): fp[FRAME_OFFSET_VAR0 - 2] = *sp++; BREAK;
        CASE(OP_put_loc3): fp[FRAME_OFFSET_VAR0 - 3] = *sp++; BREAK;
        CASE(OP_put_loc8): fp[FRAME_OFFSET_VAR0 - *pc++] = *sp++; BREAK;

        CASE(OP_get_arg0): *--sp = fp[FRAME_OFFSET_ARG0 + 0]; BREAK;
        CASE(OP_get_arg1): *--sp = fp[FRAME_OFFSET_ARG0 + 1]; BREAK;
        CASE(OP_get_arg2): *--sp = fp[FRAME_OFFSET_ARG0 + 2]; BREAK;
        CASE(OP_get_arg3): *--sp = fp[FRAME_OFFSET_ARG0 + 3]; BREAK;

        CASE(OP_put_arg0): fp[FRAME_OFFSET_ARG0 + 0] = *sp++; BREAK;
        CASE(OP_put_arg1): fp[FRAME_OFFSET_ARG0 + 1] = *sp++; BREAK;
        CASE(OP_put_arg2): fp[FRAME_OFFSET_ARG0 + 2] = *sp++; BREAK;
        CASE(OP_put_arg3): fp[FRAME_OFFSET_ARG0 + 3] = *sp++; BREAK;
            
        CASE(OP_get_var_ref):
        CASE(OP_get_var_ref_nocheck):
            {
                int idx;
                JSObject *p;
                JSVarRef *pv;
                idx = get_u16(pc);
                p = JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]);
                pv = JS_VALUE_TO_PTR(p->u.closure.var_refs[idx]);
                if (pv->is_detached)
                    val = pv->u.value;
                else
                    val = *pv->u.pvalue;
                if (unlikely(val == JS_TAG_UNINITIALIZED) &&
                    opcode == OP_get_var_ref) {
                    JSValueArray *ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
                    SAVE();
                    val = JS_ThrowReferenceError(ctx, "variable '%"JSValue_PRI"' is not defined", ext_vars->arr[2 * idx]);
                    RESTORE();
                    goto exception;
                }
                pc += 2;
                *--sp = val;
            }
            BREAK;
        CASE(OP_put_var_ref):
        CASE(OP_put_var_ref_nocheck):
            {
                int idx;
                JSObject *p;
                JSVarRef *pv;
                JSValue *pval;
                idx = get_u16(pc);
                p = JS_VALUE_TO_PTR(fp[FRAME_OFFSET_FUNC_OBJ]);
                pv = JS_VALUE_TO_PTR(p->u.closure.var_refs[idx]);
                if (pv->is_detached)
                    pval = &pv->u.value;
                else
                    pval = pv->u.pvalue;
                if (unlikely(*pval == JS_TAG_UNINITIALIZED) &&
                    opcode == OP_put_var_ref) {
                    JSValueArray *ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
                    SAVE();
                    val = JS_ThrowReferenceError(ctx, "variable '%"JSValue_PRI"' is not defined", ext_vars->arr[2 * idx]);
                    RESTORE();
                    goto exception;
                }
                *pval = *sp++;
                pc += 2;
            }
            BREAK;

        CASE(OP_goto):
            pc += (int32_t)get_u32(pc);
            POLL_INTERRUPT();
            BREAK;
        CASE(OP_if_false):
        CASE(OP_if_true):
            {
                int res;

                pc += 4;

                res = JS_ToBool(ctx, *sp++);
                if (res ^ (OP_if_true - opcode)) {
                    pc += (int32_t)get_u32(pc - 4) - 4;
                }
                POLL_INTERRUPT();
            }
            BREAK;

        CASE(OP_lnot):
            {
                int res;
                res = JS_ToBool(ctx, sp[0]);
                sp[0] = JS_NewBool(!res);
            }
            BREAK;
            
        CASE(OP_get_field2):
            sp--;
            sp[0] = sp[1];
            goto get_field_common;
        CASE(OP_get_field):
        get_field_common:
            {
                int idx;
                JSValue prop, obj;
                JSValueArray *cpool = JS_VALUE_TO_PTR(b->cpool);
                idx = get_u16(pc);
                prop = cpool->arr[idx];
                obj = sp[0];
                if (likely(JS_IsPtr(obj))) {
                    /* fast case */
                    JSObject *p = JS_VALUE_TO_PTR(obj);
                    JSProperty *pr;
                    if (unlikely(p->mtag != JS_MTAG_OBJECT))
                        goto get_field_slow;
                    for(;;) {
                        /* no array check is necessary because 'prop' is
                           guaranteed not to be a numeric property */
                        /* XXX: slow due to short ints */
                        pr = find_own_property_inlined(ctx, p, prop);
                        if (pr) {
                            if (unlikely(pr->prop_type != JS_PROP_NORMAL)) {
                                /* sp[0] is this_obj, obj is the current
                                   object */
                                goto get_field_slow;
                            } else {
                                val = pr->value;
                                break;
                            }
                        }
                        obj = p->proto;
                        if (obj == JS_NULL) {
                            val = JS_UNDEFINED;
                            break;
                        }
                        p = JS_VALUE_TO_PTR(obj);
                    }
                } else {
                get_field_slow:
                    SAVE();
                    val = JS_GetPropertyInternal(ctx, obj, prop, TRUE);
                    RESTORE();
                    if (unlikely(JS_IsExceptionOrTailCall(val))) {
                        sp = ctx->sp;
                        goto exception;
                    }
                }
                pc += 2;
                sp[0] = val;
            }
            BREAK;

        CASE(OP_get_length2):
            sp--;
            sp[0] = sp[1];
            goto get_length_common;
            
        CASE(OP_get_length):
        get_length_common:
            {
                JSValue obj;
                obj = sp[0];
                if (likely(JS_IsPtr(obj))) {
                    /* fast case */
                    JSObject *p = JS_VALUE_TO_PTR(obj);
                    if (p->mtag == JS_MTAG_OBJECT) {
                        if (p->class_id == JS_CLASS_ARRAY) {
                            if (unlikely(p->proto != ctx->class_proto[JS_CLASS_ARRAY] ||
                                         p->props != ctx->empty_props))
                                goto get_length_slow;
                            val = JS_NewShortInt(p->u.array.len);
                        } else {
                            goto get_length_slow;
                        }
                    } else if (p->mtag == JS_MTAG_STRING) {
                        JSString *ps = (JSString *)p;
                        if (likely(ps->is_ascii))
                            val = JS_NewShortInt(ps->len);
                        else
                            val = JS_NewShortInt(js_string_utf8_to_utf16_pos(ctx, obj, ps->len * 2));
                    } else {
                        goto get_length_slow;
                    }
                } else if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
                    val = JS_NewShortInt(JS_VALUE_GET_SPECIAL_VALUE(val) >= 0x10000 ? 2 : 1); 
                } else {
                get_length_slow:
                    SAVE();
                    val = JS_GetPropertyInternal(ctx, obj, js_get_atom(ctx, JS_ATOM_length), TRUE);
                    RESTORE();
                    if (unlikely(JS_IsExceptionOrTailCall(val))) {
                        sp = ctx->sp;
                        goto exception;
                    }
                }
                sp[0] = val;
            }
            BREAK;

        CASE(OP_put_field):
            {
                int idx;
                JSValue prop, obj;
                JSValueArray *cpool = JS_VALUE_TO_PTR(b->cpool);

                idx = get_u16(pc);
                prop = cpool->arr[idx];
                obj = sp[1];
                if (likely(JS_IsPtr(obj))) {
                    /* fast case */
                    JSObject *p = JS_VALUE_TO_PTR(obj);
                    JSProperty *pr;
                    if (unlikely(p->mtag != JS_MTAG_OBJECT))
                        goto put_field_slow;
                    /* no array check is necessary because 'prop' is
                       guaranteed not to be a numeric property */
                    /* XXX: slow due to short ints */
                    pr = find_own_property_inlined(ctx, p, prop);
                    if (unlikely(!pr))
                        goto put_field_slow;
                    if (unlikely(pr->prop_type != JS_PROP_NORMAL))
                        goto put_field_slow;
                    /* XXX: slow */
                    if (unlikely(JS_IS_ROM_PTR(ctx, pr)))
                        goto put_field_slow;
                    pr->value = sp[0];
                    sp += 2;
                } else {
                put_field_slow:
                    val = *sp++;
                    SAVE();
                    val = JS_SetPropertyInternal(ctx, sp[0], prop, val, TRUE);
                    RESTORE();
                    if (unlikely(JS_IsExceptionOrTailCall(val))) {
                        sp = ctx->sp;
                        goto exception;
                    }
                    sp++;
                }
                pc += 2;
            }
            BREAK;

        CASE(OP_get_array_el2):
            val = sp[0];
            sp[0] = sp[1];
            goto get_array_el_common;
        CASE(OP_get_array_el):
            val = sp[0];
            sp++;
        get_array_el_common:
            {
                JSValue prop = val, obj;
                obj = sp[0];
                if (JS_IsPtr(obj) && JS_IsInt(prop)) {
                    /* fast case with array */
                    /* XXX: optimize typed arrays too ? */
                    JSObject *p = JS_VALUE_TO_PTR(obj);
                    uint32_t idx;
                    JSValueArray *arr;
                    if (unlikely(p->mtag != JS_MTAG_OBJECT))
                        goto get_array_el_slow;
                    if (unlikely(p->class_id != JS_CLASS_ARRAY))
                        goto get_array_el_slow;
                    idx = JS_VALUE_GET_INT(prop);
                    if (unlikely(idx >= p->u.array.len))
                        goto get_array_el_slow;
                        
                    arr = JS_VALUE_TO_PTR(p->u.array.tab);
                    val = arr->arr[idx];
                } else {
                get_array_el_slow:
                    SAVE();
                    prop = JS_ToPropertyKey(ctx, prop);
                    RESTORE();
                    if (JS_IsException(prop)) {
                        val = prop;
                        goto exception;
                    }
                    SAVE();
                    val = JS_GetPropertyInternal(ctx, sp[0], prop, TRUE);
                    RESTORE();
                    if (unlikely(JS_IsExceptionOrTailCall(val))) {
                        sp = ctx->sp;
                        goto exception;
                    }
                }
                sp[0] = val;
            }
            BREAK;
            
        CASE(OP_put_array_el):
            {
                JSValue prop, obj;
                obj = sp[2];
                prop = sp[1];
                if (JS_IsPtr(obj) && JS_IsInt(prop)) {
                    /* fast case with array */
                    /* XXX: optimize typed arrays too ? */
                    JSObject *p = JS_VALUE_TO_PTR(obj);
                    uint32_t idx;
                    JSValueArray *arr;
                    if (unlikely(p->mtag != JS_MTAG_OBJECT))
                        goto put_array_el_slow;
                    if (unlikely(p->class_id != JS_CLASS_ARRAY))
                        goto put_array_el_slow;
                    idx = JS_VALUE_GET_INT(prop);
                    arr = JS_VALUE_TO_PTR(p->u.array.tab);
                    if (unlikely(idx >= p->u.array.len)) {
                        if (idx == p->u.array.len &&
                            p->u.array.tab != JS_NULL &&
                            idx < arr->size) {
                            arr->arr[idx] = sp[0];
                            p->u.array.len = idx + 1;
                        } else {
                            goto put_array_el_slow;
                        }
                    } else {
                        arr->arr[idx] = sp[0];
                    }
                    sp += 3;
                } else {
                put_array_el_slow:
                    SAVE();
                    sp[1] = JS_ToPropertyKey(ctx, sp[1]);
                    RESTORE();
                    if (JS_IsException(sp[1])) {
                        val = sp[1];
                        goto exception;
                    }
                    val = *sp++;
                    prop = *sp++;
                    SAVE();
                    val = JS_SetPropertyInternal(ctx, sp[0], prop, val, TRUE);
                    RESTORE();
                    if (unlikely(JS_IsExceptionOrTailCall(val))) {
                        sp = ctx->sp;
                        goto exception;
                    }
                    sp++;
                }
            }
            BREAK;
            
        CASE(OP_define_field):
        CASE(OP_define_getter):
        CASE(OP_define_setter):
            {
                int idx;
                JSValue prop;
                JSValueArray *cpool = JS_VALUE_TO_PTR(b->cpool);
                
                idx = get_u16(pc);
                prop = cpool->arr[idx];
                
                SAVE();
                if (opcode == OP_define_field) {
                    val = JS_DefinePropertyValue(ctx, sp[1], prop, sp[0]);
                } else if (opcode == OP_define_getter)
                    val = JS_DefinePropertyGetSet(ctx, sp[1], prop, sp[0], JS_UNDEFINED, JS_DEF_PROP_HAS_GET);
                else
                    val = JS_DefinePropertyGetSet(ctx, sp[1], prop, JS_UNDEFINED, sp[0], JS_DEF_PROP_HAS_SET);
                RESTORE();
                if (unlikely(JS_IsException(val)))
                    goto exception;
                pc += 2;
                sp++;
            }
            BREAK;

        CASE(OP_set_proto):
            {
                if (JS_IsObject(ctx, sp[0]) || JS_IsNull(sp[0])) {
                    SAVE();
                    val = js_set_prototype_internal(ctx, sp[1], sp[0]);
                    RESTORE();
                    if (unlikely(JS_IsException(val)))
                        goto exception;
                }
                sp++;
            }
            BREAK;
            
        CASE(OP_add):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int r;
                    if (unlikely(__builtin_add_overflow((int)op1, (int)op2, &r)))
                        goto add_slow;
                    sp[1] = (uint32_t)r;
                } else 
#ifdef JS_USE_SHORT_FLOAT
                if (JS_VALUE_IS_BOTH_SHORT_FLOAT(op1, op2)) {
                    double d1, d2;
                    d1 = js_get_short_float(op1);
                    d2 = js_get_short_float(op2);
                    dr = d1 + d2;
                    sp++;
                    goto float_result;
                } else
#endif
                {
                add_slow:
                    SAVE();
                    val = js_add_slow(ctx);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                    sp[1] = val;
                }
                sp++;
            }
            BREAK;
        CASE(OP_sub):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int r;
                    if (unlikely(__builtin_sub_overflow((int)op1, (int)op2, &r)))
                        goto binary_arith_slow;
                    sp[1] = (uint32_t)r;
                } else
#ifdef JS_USE_SHORT_FLOAT
                if (JS_VALUE_IS_BOTH_SHORT_FLOAT(op1, op2)) {
                    double d1, d2;
                    d1 = js_get_short_float(op1);
                    d2 = js_get_short_float(op2);
                    dr = d1 - d2;
                    sp++;
                    goto float_result;
                } else
#endif
                {
                    goto binary_arith_slow;
                }
                sp++;
            }
            BREAK;
        CASE(OP_mul):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int v1, v2;
                    int64_t r;
                    v1 = (int)op1;
                    v2 = (int)op2 >> 1;
                    r = (int64_t)v1 * (int64_t)v2;
                    if (unlikely(r != (int)r)) {
#if defined(JS_USE_SHORT_FLOAT)
                        dr = (double)(r >> 1);
                        sp++;
                        goto float_result;
#else
                        goto binary_arith_slow;
#endif
                    }
                    /* -0 case */
                    if (unlikely(r == 0 && (v1 | v2) < 0)) {
                        sp[1] = ctx->minus_zero;
                    } else {
                        sp[1] = (uint32_t)r;
                    }
                } else
#ifdef JS_USE_SHORT_FLOAT
                if (JS_VALUE_IS_BOTH_SHORT_FLOAT(op1, op2)) {
                    double d1, d2;
                    d1 = js_get_short_float(op1);
                    d2 = js_get_short_float(op2);
                    dr = d1 * d2;
                    sp++;
                    goto float_result;
                } else
#endif
                {
                    goto binary_arith_slow;
                }
                sp++;
            }
            BREAK;
        CASE(OP_div):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int v1, v2;
                    v1 = JS_VALUE_GET_INT(op1);
                    v2 = JS_VALUE_GET_INT(op2);
                    SAVE();
                    val = JS_NewFloat64(ctx, (double)v1 / (double)v2);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                    sp[1] = val;
                    sp++;
                } else {
                    goto binary_arith_slow;
                }
            }
            BREAK;
        CASE(OP_mod):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int v1, v2, r;
                    v1 = JS_VALUE_GET_INT(op1);
                    v2 = JS_VALUE_GET_INT(op2);
                    if (unlikely(v1 < 0 || v2 <= 0))
                        goto binary_arith_slow;
                    r = v1 % v2;
                    sp[1] = JS_NewShortInt(r);
                    sp++;
                } else {
                    goto binary_arith_slow;
                }
            }
            BREAK;
        CASE(OP_pow):
        binary_arith_slow:
            SAVE();
            val = js_binary_arith_slow(ctx, opcode);
            RESTORE();
            if (JS_IsException(val))
                goto exception;
            sp[1] = val;
            sp++;
            BREAK;
        CASE(OP_plus):
            {
                JSValue op1;
                op1 = sp[0];
                if (JS_IsIntOrShortFloat(op1) ||
                    (JS_IsPtr(op1) && js_get_mtag(JS_VALUE_TO_PTR(op1)) == JS_MTAG_FLOAT64)) {
                } else {
                    goto unary_arith_slow;
                }
            }
            BREAK;
        CASE(OP_neg):
            {
                JSValue op1;
                int v1;
                op1 = sp[0];
                if (JS_IsInt(op1)) {
                    v1 = op1;
                    if (v1 == 0) {
                        sp[0] = ctx->minus_zero;
                    } else if (v1 == INT32_MIN) {
#if defined(JS_USE_SHORT_FLOAT)
                        dr = -(double)JS_SHORTINT_MIN;
                        goto float_result;
#else
                        goto unary_arith_slow;
#endif                        
                    } else {
                        sp[0] = -v1;
                    }
                } else
#if defined(JS_USE_SHORT_FLOAT)
                if (JS_IsShortFloat(op1)) {
                    dr = -js_get_short_float(op1);
                float_result:
                    /* for efficiency, we don't try to store it as a short integer */
                    if (likely(fabs(dr) >= 0x1p-127 && fabs(dr) <= 0x1p+128)) {
                        val = js_to_short_float(dr);
                    } else if (dr == 0.0) {
                        if (float64_as_uint64(dr) != 0) {
                            /* minus zero often happens, so it is worth having a constant
                               value */
                            val = ctx->minus_zero;
                        } else {
                            /* XXX: could have a short float
                               representation for zero and minus zero
                               so that the float fast case is still
                               used when they happen */
                            val = JS_NewShortInt(0);
                        }
                    } else {
                        /* slow case: need to allocate it */
                        SAVE();
                        val = js_alloc_float64(ctx, dr);
                        RESTORE();
                        if (JS_IsException(val))
                            goto exception;
                    }
                    sp[0] = val;
                } else
#endif
                {
                    goto unary_arith_slow;
                }
            }
            BREAK;
        CASE(OP_inc):
            {
                JSValue op1;
                int v1;
                op1 = sp[0];
                if (JS_IsInt(op1)) {
                    v1 = JS_VALUE_GET_INT(op1);
                    if (unlikely(v1 == JS_SHORTINT_MAX))
                        goto unary_arith_slow;
                    sp[0] = JS_NewShortInt(v1 + 1);
                } else {
                    goto unary_arith_slow;
                }
            }
            BREAK;
        CASE(OP_dec):
            {
                JSValue op1;
                int v1;
                op1 = sp[0];
                if (JS_IsInt(op1)) {
                    v1 = JS_VALUE_GET_INT(op1);
                    if (unlikely(v1 == JS_SHORTINT_MIN))
                        goto unary_arith_slow;
                    sp[0] = JS_NewShortInt(v1 - 1);
                } else {
                unary_arith_slow:
                    SAVE();
                    val = js_unary_arith_slow(ctx, opcode);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                    sp[0] = val;
                }
            }
            BREAK;
        CASE(OP_post_inc):
        CASE(OP_post_dec):
            {
                JSValue op1;
                int v1;
                op1 = sp[0];
                if (JS_IsInt(op1)) {
                    v1 = JS_VALUE_GET_INT(op1) + 2 * (opcode - OP_post_dec) - 1;
                    if (v1 < JS_SHORTINT_MIN || v1 > JS_SHORTINT_MAX)
                        goto slow_post_inc_dec;
                    val = JS_NewShortInt(v1);
                } else {
                slow_post_inc_dec:
                    SAVE();
                    val = js_post_inc_slow(ctx, opcode);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                }
                *--sp = val;
            }
            BREAK;

        CASE(OP_not):
            {
                JSValue op1;
                op1 = sp[0];
                if (JS_IsInt(op1)) {
                    sp[0] = (~op1) & (~1);
                } else {
                    SAVE();
                    val = js_not_slow(ctx);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                    sp[0] = val;
                }
            }
            BREAK;

        CASE(OP_shl):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    int32_t r;
                    r = JS_VALUE_GET_INT(op1) << (JS_VALUE_GET_INT(op2) & 0x1f);
                    if (unlikely(r < JS_SHORTINT_MIN || r > JS_SHORTINT_MAX)) {
#if defined(JS_USE_SHORT_FLOAT)
                        dr = (double)r;
                        sp++;
                        goto float_result;
#else
                        goto binary_logic_slow;
#endif
                    }
                    sp[1] = JS_NewShortInt(r);
                    sp++;
                } else {
                    goto binary_logic_slow;
                }
            }
            BREAK;
        CASE(OP_shr):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    uint32_t r;
                    r = (uint32_t)JS_VALUE_GET_INT(op1) >>
                        ((uint32_t)JS_VALUE_GET_INT(op2) & 0x1f);
                    if (unlikely(r > JS_SHORTINT_MAX)) {
#if defined(JS_USE_SHORT_FLOAT)
                        dr = (double)r;
                        sp++;
                        goto float_result;
#else
                        goto binary_logic_slow;
#endif
                    }
                    sp[1] = JS_NewShortInt(r);
                    sp++;
                } else {
                    goto binary_logic_slow;
                }
            }
            BREAK;
        CASE(OP_sar):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    sp[1] = ((int)op1 >> ((uint32_t)JS_VALUE_GET_INT(op2) & 0x1f)) & ~1;
                    sp++;
                } else {
                    goto binary_logic_slow;
                }
            }
            BREAK;
        CASE(OP_and):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    sp[1] = op1 & op2;
                    sp++;
                } else {
                    goto binary_logic_slow;
                }
            }
            BREAK;
        CASE(OP_or):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    sp[1] = op1 | op2;
                    sp++;
                } else {
                    goto binary_logic_slow;
                }
            }
            BREAK;
        CASE(OP_xor):
            {
                JSValue op1, op2;
                op1 = sp[1];
                op2 = sp[0];
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {
                    sp[1] = op1 ^ op2;
                    sp++;
                } else {
                binary_logic_slow:
                    SAVE();
                    val = js_binary_logic_slow(ctx, opcode);
                    RESTORE();
                    if (JS_IsException(val))
                        goto exception;
                    sp[1] = val;
                    sp++;
                }
            }
            BREAK;
            

#define OP_CMP(opcode, binary_op, slow_call)              \
            CASE(opcode):                                  \
                {                                         \
                JSValue op1, op2;                         \
                op1 = sp[1];                                   \
                op2 = sp[0];                                   \
                if (likely(JS_VALUE_IS_BOTH_INT(op1, op2))) {           \
                    sp[1] = JS_NewBool(JS_VALUE_GET_INT(op1) binary_op JS_VALUE_GET_INT(op2)); \
                    sp++;                                               \
                } else {                                                \
                    SAVE();                                             \
                    val = slow_call;                                    \
                    RESTORE();                                          \
                    if (JS_IsException(val))                            \
                        goto exception;                                 \
                    sp[1] = val;                                        \
                    sp++;                                               \
                }                                                       \
                }                                                       \
                BREAK;
            
            OP_CMP(OP_lt, <, js_relational_slow(ctx, opcode));
            OP_CMP(OP_lte, <=, js_relational_slow(ctx, opcode));
            OP_CMP(OP_gt, >, js_relational_slow(ctx, opcode));
            OP_CMP(OP_gte, >=, js_relational_slow(ctx, opcode));
            OP_CMP(OP_eq, ==, js_eq_slow(ctx, 0));
            OP_CMP(OP_neq, !=, js_eq_slow(ctx, 1));
            OP_CMP(OP_strict_eq, ==, js_strict_eq_slow(ctx, 0));
            OP_CMP(OP_strict_neq, !=, js_strict_eq_slow(ctx, 1));
        CASE(OP_in):
            SAVE();
            val = js_operator_in(ctx);
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp[1] = val;
            sp++;
            BREAK;
        CASE(OP_instanceof):
            SAVE();
            val = js_operator_instanceof(ctx);
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp[1] = val;
            sp++;
            BREAK;
        CASE(OP_typeof):
            SAVE();
            val = js_operator_typeof(ctx, sp[0]);
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp[0] = val;
            BREAK;
        CASE(OP_delete):
            SAVE();
            val = JS_DeleteProperty(ctx, sp[1], sp[0]);
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp[1] = val;
            sp++;
            BREAK;
        CASE(OP_for_in_start):
        CASE(OP_for_of_start):
            SAVE();
            val = js_for_of_start(ctx, (opcode == OP_for_in_start));
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp[0] = val;
            BREAK;
        CASE(OP_for_of_next):
            SAVE();
            val = js_for_of_next(ctx);
            RESTORE();
            if (unlikely(JS_IsException(val)))
                goto exception;
            sp -= 2;
            BREAK;
        default:
            {
                JSByteArray *byte_code = JS_VALUE_TO_PTR(b->byte_code);
                SAVE();
                val = JS_ThrowInternalError(ctx, "invalid opcode: pc=%u opcode=0x%02x",
                                            (int)(pc - byte_code->buf - 1), opcode);
                RESTORE();
            }
            goto exception;
        }
      restart: ;
    } /* switch */
 done:
    ctx->sp = sp;
    ctx->fp = fp;
    ctx->js_call_rec_count--;
    return val;
}
