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

const char *js_mtag_name[JS_MTAG_COUNT] = {
    "free", "object", "float64", "string",
    "func_bytecode", "value_array", "byte_array", "varref",
};
JSValue *JS_PushGCRef(JSContext *ctx, JSGCRef *ref)
{
    ref->prev = ctx->top_gc_ref;
    ctx->top_gc_ref = ref;
    ref->val = JS_UNDEFINED;
    return &ref->val;
}

JSValue JS_PopGCRef(JSContext *ctx, JSGCRef *ref)
{
    ctx->top_gc_ref = ref->prev;
    return ref->val;
}

JSValue *JS_AddGCRef(JSContext *ctx, JSGCRef *ref)
{
    ref->prev = ctx->last_gc_ref;
    ctx->last_gc_ref = ref;
    ref->val = JS_UNDEFINED;
    return &ref->val;
}

void JS_DeleteGCRef(JSContext *ctx, JSGCRef *ref)
{
    JSGCRef **pref, *ref1;
    pref = &ctx->last_gc_ref;
    for(;;) {
        ref1 = *pref;
        if (ref1 == NULL)
            abort();
        if (ref1 == ref) {
            *pref = ref1->prev;
            break;
        }
        pref = &ref1->prev;
    }
}

#undef JS_PUSH_VALUE
#undef JS_POP_VALUE

#define JS_PUSH_VALUE(ctx, v) do {               \
        v ## _ref.prev = ctx->top_gc_ref;       \
        ctx->top_gc_ref = &v ## _ref;            \
        v ## _ref.val = v;                     \
    } while (0)
          
#define JS_POP_VALUE(ctx, v) do {                     \
          v = v ## _ref.val;                        \
          ctx->top_gc_ref = v ## _ref.prev;         \
      } while (0)

JSValue js_get_atom(JSContext *ctx, int a)
{
    return JS_VALUE_FROM_PTR(&ctx->atom_table[a]);
}


inline JS_BOOL JS_IsExceptionOrTailCall(JSValue v)
{
    return JS_VALUE_GET_SPECIAL_TAG(v) == JS_TAG_EXCEPTION;
}

int js_get_mtag(void *ptr)
{
    return ((JSMemBlockHeader *)ptr)->mtag;
}

int check_free_mem(JSContext *ctx, JSValue *stack_bottom, uint32_t size)
{
#ifdef DEBUG_GC
    assert(ctx->sp >= stack_bottom);
    /* don't start the GC before dummy_block is allocated */
    if (JS_IsPtr(ctx->dummy_block)) {
        JS_GC(ctx);
    }
#endif
    if (((uint8_t *)stack_bottom - ctx->heap_free) < size + ctx->min_free_size) {
        JS_GC(ctx);
        if (((uint8_t *)stack_bottom - ctx->heap_free) < size + ctx->min_free_size) {
            JS_ThrowOutOfMemory(ctx);
            return -1;
        }
    }
    return 0;
}

/* check that 'len' values can be pushed on the stack. Return 0 if OK,
   -1 if not enough space. May trigger a GC(). */
int JS_StackCheck(JSContext *ctx, uint32_t len)
{
    JSValue *new_stack_bottom;

    len += JS_STACK_SLACK;
    new_stack_bottom = ctx->sp - len;
    if (check_free_mem(ctx, new_stack_bottom, len * sizeof(JSValue)))
        return -1;
    ctx->stack_bottom = new_stack_bottom;
    return 0;
}

void *js_malloc(JSContext *ctx, uint32_t size, int mtag)
{
    JSMemBlockHeader *p;

    if (size == 0)
        return NULL;
    size = (size + JSW - 1) & ~(JSW - 1);

    if (check_free_mem(ctx, ctx->stack_bottom, size))
        return NULL;
    
    p = (JSMemBlockHeader *)ctx->heap_free;
    ctx->heap_free += size;

    p->mtag = mtag;
    p->gc_mark = 0;
    p->dummy = 0;
    return p;
}

void *js_mallocz(JSContext *ctx, uint32_t size, int mtag)
{
    uint8_t *ptr;
    ptr = js_malloc(ctx, size, mtag);
    if (!ptr)
        return NULL;
    if (size > sizeof(uint32_t)) {
        memset(ptr + sizeof(uint32_t), 0, size - sizeof(uint32_t));
    }
    return ptr;
}

/* currently only free the last element */
void js_free(JSContext *ctx, void *ptr)
{
    uint8_t *ptr1;
    if (!ptr)
        return;
    ptr1 = ptr;
    ptr1 += get_mblock_size(ptr1);
    if (ptr1 == ctx->heap_free)
        ctx->heap_free = ptr;
}

/* 'size' is in bytes and must be multiple of JSW and > 0 */
void set_free_block(void *ptr, uint32_t size)
{
    JSFreeBlock *p;
    p = (JSFreeBlock *)ptr;
    p->mtag = JS_MTAG_FREE;
    p->gc_mark = 0;
    p->size = (size - sizeof(JSFreeBlock)) / sizeof(JSWord);
}

/* 'ptr' must be != NULL. new_size must be less or equal to the
   current block size. */
void *js_shrink(JSContext *ctx, void *ptr, uint32_t new_size)
{
    uint32_t old_size;
    uint32_t diff;
    
    new_size = (new_size + (JSW - 1)) & ~(JSW - 1);

    if (new_size == 0) {
        js_free(ctx, ptr);
        return NULL;
    }
    old_size = get_mblock_size(ptr);
    assert(new_size <= old_size);
    diff = old_size - new_size;
    if (diff == 0)
        return ptr;
    set_free_block((uint8_t *)ptr + new_size, diff);
    /* add a new free block after 'ptr' */
    return ptr;
}

JSValue JS_Throw(JSContext *ctx, JSValue obj)
{
    ctx->current_exception = obj;
    ctx->current_exception_is_uncatchable = FALSE;
    return JS_EXCEPTION;
}

/* return the byte length. 'buf' must contain UTF8_CHAR_LEN_MAX + 1 bytes */
int get_short_string(uint8_t *buf, JSValue val)
{
    int len;
    len = unicode_to_utf8(buf, JS_VALUE_GET_SPECIAL_VALUE(val));
    buf[len] = '\0';
    return len;
}

/* printf utility */

#define PF_ZERO_PAD (1 << 0) /* 0 */
#define PF_ALT_FORM (1 << 1) /* # */
#define PF_MARK_POS (1 << 2) /* + */
#define PF_LEFT_ADJ (1 << 3) /* - */
#define PF_PAD_POS  (1 << 4) /* ' ' */
#define PF_INT64    (1 << 5) /* l/ll */

BOOL is_digit(int c)
{
    return (c >= '0' && c <= '9');
}

/* pad with chars 'c' */
void pad(JSWriteFunc *write_func, void *opaque, char c, int width, int len)
{
    char buf[16];
    int l;
    if (len >= width)
        return;
    width -= len;
    memset(buf, c, min_int(sizeof(buf), width));
    while (width != 0) {
        l = min_int(width, sizeof(buf));
        write_func(opaque, buf, l);
        width -= l;
    }
}

/* The 'o' format can be used to print a JSValue. Only short int,
   bool, null, undefined and string types are supported. */
void js_vprintf(JSWriteFunc *write_func, void *opaque, const char *fmt, va_list ap)
{
    const char *p;
    int width, prec, flags, c;
    char tmp_buf[32], *buf;
    size_t len;
    
    while (*fmt != '\0') {
        p = fmt;
        while (*fmt != '%' && *fmt != '\0')
            fmt++;
        if (fmt > p)
            write_func(opaque, p, fmt - p);
        if (*fmt == '\0')
            break;
        fmt++;
        /* get the flags */
        flags = 0;
        for(;;) {
            c = *fmt;
            if (c == '0') {
                flags |= PF_ZERO_PAD;
            } else if (c == '#') {
                flags |= PF_ALT_FORM;
            } else if (c == '+') {
                flags |= PF_MARK_POS;
            } else if (c == '-') {
                flags |= PF_LEFT_ADJ;
            } else if (c == ' ') {
                flags |= PF_MARK_POS;
            } else {
                break;
            }
            fmt++;
        }
        width = 0;
        if (*fmt == '*') {
            width = va_arg(ap, int);
        } else {
            while (is_digit(*fmt)) {
                width = width * 10 + *fmt - '0';
                fmt++;
            }
        }
        prec = 0;
        if (*fmt == '.') {
            fmt++;
            if (*fmt == '*') {
                prec = va_arg(ap, int);
            } else {
                while (is_digit(*fmt)) {
                    prec = prec * 10 + *fmt - '0';
                    fmt++;
                }
            }
        }
        /* modifiers */
        for(;;) {
            c = *fmt;
            if (c == 'l') {
                if (sizeof(long) == sizeof(int64_t) || fmt[-1] == 'l')
                    flags |= PF_INT64;
            } else
            if (c == 'z' || c == 't') {
                if (sizeof(size_t) == sizeof(uint64_t))
                    flags |= PF_INT64;
            } else {
                break;
            }
            fmt++;
        }

        c = *fmt++;
        /* XXX: not complete, just enough for our needs */
        buf = tmp_buf;
        len = 0;
        switch(c) {
        case '%':
            write_func(opaque, fmt - 1, 1);
            break;
        case 'c':
            buf[0] = va_arg(ap, int);
            len = 1;
            flags &= ~PF_ZERO_PAD;
            break;
        case 's':
            buf = va_arg(ap, char *);
            if (!buf)
                buf = "null";
            len = strlen(buf);
            flags &= ~PF_ZERO_PAD;
            break;
        case 'd':
            if (flags & PF_INT64)
                len = i64toa(buf, va_arg(ap, int64_t));
            else
                len = i32toa(buf, va_arg(ap, int32_t));
            break;
        case 'u':
            if (flags & PF_INT64)
                len = u64toa(buf, va_arg(ap, uint64_t));
            else
                len = u32toa(buf, va_arg(ap, uint32_t));
            break;
        case 'x':
            if (flags & PF_INT64)
                len = u64toa_radix(buf, va_arg(ap, uint64_t), 16);
            else
                len = u64toa_radix(buf, va_arg(ap, uint32_t), 16);
            break;
        case 'p':
            buf[0] = '0';
            buf[1] = 'x';
            len = u64toa_radix(buf + 2, (uintptr_t)va_arg(ap, void *), 16);
            len += 2;
            break;
        case 'o':
            {
                JSValue val = (flags & PF_INT64) ? va_arg(ap, uint64_t) : va_arg(ap, uint32_t);
                if (JS_IsInt(val)) {
                    len = i32toa(buf, JS_VALUE_GET_INT(val));
                } else
#ifdef JS_USE_SHORT_FLOAT
                if (JS_IsShortFloat(val)) {
                    /* XXX: print it */
                    buf = "[short_float]";
                    goto do_strlen;
                } else
#endif
                if (!JS_IsPtr(val)) {
                    switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
                    case JS_TAG_NULL:
                        buf = "null";
                        goto do_strlen;
                    case JS_TAG_UNDEFINED:
                        buf = "undefined";
                        goto do_strlen;
                    case JS_TAG_UNINITIALIZED:
                        buf = "uninitialized";
                        goto do_strlen;
                    case JS_TAG_BOOL:
                        buf = JS_VALUE_GET_SPECIAL_VALUE(val) ? "true" : "false";
                        goto do_strlen;
                    case JS_TAG_STRING_CHAR:
                        len = get_short_string((uint8_t *)buf, val);
                        break;
                    default:
                        buf = "[tag]";
                        goto do_strlen;
                    }
                } else {
                    void *ptr = JS_VALUE_TO_PTR(val);
                    int mtag = ((JSMemBlockHeader *)ptr)->mtag;
                    switch(mtag) {
                    case JS_MTAG_STRING:
                        {
                            JSString *p = ptr;
                            buf = (char *)p->buf;
                            len = p->len;
                        }
                        break;
                    default:
                        buf = "[mtag]";
                    do_strlen:
                        len = strlen(buf);
                        break;
                    }
                }
                /* remove the trailing '\n' if any (used in error output) */
                if ((flags & PF_ALT_FORM) && len > 0 && buf[len - 1] == '\n')
                    len--;
                flags &= ~PF_ZERO_PAD;
            }
            break;
        default:
            goto error;
        }
        if (flags & PF_ZERO_PAD) {
            /* XXX: incorrect with prefix */
            pad(write_func, opaque, '0', width, len);
        } else {
            if (!(flags & PF_LEFT_ADJ))
                pad(write_func, opaque, ' ', width, len);
        }
        write_func(opaque, buf, len);
        if (flags & PF_LEFT_ADJ)
            pad(write_func, opaque, ' ', width, len);
    }
    return;
 error:
    return;
}

/* used for the debug output */
void __js_printf_like(2, 3) js_printf(JSContext *ctx, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    js_vprintf(ctx->write_func, ctx->opaque, fmt, ap);
    va_end(ap);
}

__maybe_unused void js_putchar(JSContext *ctx, uint8_t c)
{
    ctx->write_func(ctx->opaque, &c, 1);
}

typedef struct {
    char *ptr;
    char *buf_end;
    int len;
} SNPrintfState;

void snprintf_write_func(void *opaque, const void *buf, size_t buf_len)
{
    SNPrintfState *s = opaque;
    size_t l;
    s->len += buf_len;
    l = min_size_t(buf_len, s->buf_end - s->ptr);
    if (l != 0) {
        memcpy(s->ptr, buf, l);
        s->ptr += l;
    }
}

int js_vsnprintf(char *buf, size_t buf_size, const char *fmt, va_list ap)
{
    SNPrintfState ss, *s = &ss;
    s->ptr = buf;
    s->buf_end = buf + max_size_t(buf_size, 1) - 1;
    s->len = 0;
    js_vprintf(snprintf_write_func, s, fmt, ap);
    if (buf_size > 0)
        *s->ptr = '\0';
    return s->len;
}

int __maybe_unused __js_printf_like(3, 4) js_snprintf(char *buf, size_t buf_size, const char *fmt, ...)
{
    va_list ap;
    int ret;
    va_start(ap, fmt);
    ret = js_vsnprintf(buf, buf_size, fmt, ap);
    va_end(ap);
    return ret;
}

JSValue __js_printf_like(3, 4) JS_ThrowError(JSContext *ctx, JSObjectClassEnum error_num,
                                           const char *fmt, ...)
{
    JSObject *p;
    va_list ap;
    char buf[128];
    JSValue msg, error_obj;
    JSGCRef msg_ref, error_obj_ref;
    
    va_start(ap, fmt);
    js_vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    msg = JS_NewString(ctx, buf);

    JS_PUSH_VALUE(ctx, msg);
    error_obj = JS_NewObjectProtoClass(ctx, ctx->class_proto[error_num], JS_CLASS_ERROR,
                                       sizeof(JSErrorData));
    JS_POP_VALUE(ctx, msg);
    if (JS_IsException(error_obj))
        return error_obj;

    p = JS_VALUE_TO_PTR(error_obj);
    p->u.error.message = msg;
    p->u.error.stack = JS_NULL;

    /* in case of syntax error, the backtrace is added later */
    if (error_num != JS_CLASS_SYNTAX_ERROR) {
        JS_PUSH_VALUE(ctx, error_obj);
        build_backtrace(ctx, error_obj, NULL, 0, 0, 0);
        JS_POP_VALUE(ctx, error_obj);
    }

    return JS_Throw(ctx, error_obj);
}

JSValue JS_ThrowOutOfMemory(JSContext *ctx)
{
    JSValue val;
    if (ctx->in_out_of_memory)
        return JS_Throw(ctx, JS_NULL);
    ctx->in_out_of_memory = TRUE;
    ctx->min_free_size = JS_MIN_CRITICAL_FREE_SIZE;
    val = JS_ThrowInternalError(ctx, "out of memory");
    ctx->in_out_of_memory = FALSE;
    ctx->min_free_size = JS_MIN_FREE_SIZE;
    return val;
}

#define JS_SHORTINT_MIN (-(1 << 30))
#define JS_SHORTINT_MAX ((1 << 30) - 1)

inline int is_ident_first(int c)
{
    return (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        c == '_' || c == '$';
}

inline int is_ident_next(int c)
{
    return is_ident_first(c) || is_num(c);
}

/**********************************************************************/
/* dump utilities */

#ifdef JS_DUMP

void js_dump_array(JSContext *ctx, JSValueArray *arr, int len)
{
    int i;
    
    js_printf(ctx, "[ ");
    for(i = 0; i < len; i++) {
        if (i != 0)
            js_printf(ctx, ", ");
        JS_PrintValue(ctx, arr->arr[i]);
    }
    js_printf(ctx, " ]");
}

/* put constructors into a separate table */
/* XXX: improve by using a table */
JSValue js_find_class_name(JSContext *ctx, int class_id)
{
    const JSCFunctionDef *fd;
    fd = ctx->c_function_table;
    while ((fd->def_type != JS_CFUNC_constructor_magic &&
            fd->def_type != JS_CFUNC_constructor) ||
           fd->magic != class_id) {
        fd++;
    }
    return reloc_c_func_name(ctx, fd->name);
}

void js_dump_float64(JSContext *ctx, double d)
{
    char buf[32];
    JSDTOATempMem tmp_mem; /* XXX: potentially large stack size */
    js_dtoa(buf, d, 10, 0, JS_DTOA_FORMAT_FREE | JS_DTOA_MINUS_ZERO, &tmp_mem);
    js_printf(ctx, "%s", buf);
}

void dump_regexp(JSContext *ctx, JSObject *p);

void js_dump_error(JSContext *ctx, JSObject *p)
{
    JSObject *p1;
    JSProperty *pr;
    JSValue name;
    
    /* find the error name without side effect */
    p1 = p;
    if (p->proto != JS_NULL) 
        p1 = JS_VALUE_TO_PTR(p->proto);
    pr = find_own_property(ctx, p1, js_get_atom(ctx, JS_ATOM_name));
    if (!pr || !JS_IsString(ctx, pr->value))
        name = js_get_atom(ctx, JS_ATOM_Error);
    else
        name = pr->value;
    js_printf(ctx, "%" JSValue_PRI, name);
    if (p->u.error.message != JS_NULL) {
        js_printf(ctx, ": %" JSValue_PRI, p->u.error.message);
    }
    if (p->u.error.stack != JS_NULL) {
        /* remove the trailing '\n' if any */
        js_printf(ctx, "\n%#" JSValue_PRI, p->u.error.stack);
    }
}

void js_dump_object(JSContext *ctx, JSObject *p, int flags)
{
    if (flags & JS_DUMP_LONG) {
        switch(p->class_id) {
        case JS_CLASS_CLOSURE:
            {
                JSFunctionBytecode *b = JS_VALUE_TO_PTR(p->u.closure.func_bytecode);
                js_printf(ctx, "function ");
                JS_PrintValueF(ctx, b->func_name, JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            }
            break;
        case JS_CLASS_C_FUNCTION:
            js_printf(ctx, "function ");
            JS_PrintValueF(ctx, reloc_c_func_name(ctx, ctx->c_function_table[p->u.cfunc.idx].name), JS_DUMP_NOQUOTE);
            js_printf(ctx, "()");
            break;
        case JS_CLASS_ERROR:
            js_dump_error(ctx, p);
            break;
        case JS_CLASS_REGEXP:
            dump_regexp(ctx, p);
            break;
        default:
        case JS_CLASS_ARRAY:
        case JS_CLASS_OBJECT:
            if (p->class_id >= JS_CLASS_UINT8C_ARRAY &&
                p->class_id <= JS_CLASS_FLOAT64_ARRAY) {            
                int i, idx;
                uint32_t v;
                double d;
                JSObject *pbuffer;
                JSByteArray *arr;
                JS_PrintValueF(ctx, js_find_class_name(ctx, p->class_id),
                               JS_DUMP_NOQUOTE);
                js_printf(ctx, "([ ");
                pbuffer = JS_VALUE_TO_PTR(p->u.typed_array.buffer);
                arr = JS_VALUE_TO_PTR(pbuffer->u.array_buffer.byte_buffer);
                for(i = 0; i < p->u.typed_array.len; i++) {
                    if (i != 0)
                        js_printf(ctx, ", ");
                    idx = i + p->u.typed_array.offset;
                    switch(p->class_id) {
                    default:
                    case JS_CLASS_UINT8C_ARRAY:
                    case JS_CLASS_UINT8_ARRAY:
                        v = *((uint8_t *)arr->buf + idx);
                        goto ta_i32;
                    case JS_CLASS_INT8_ARRAY:
                        v = *((int8_t *)arr->buf + idx);
                        goto ta_i32;
                    case JS_CLASS_INT16_ARRAY:
                        v = *((int16_t *)arr->buf + idx);
                        goto ta_i32;
                    case JS_CLASS_UINT16_ARRAY:
                        v = *((uint16_t *)arr->buf + idx);
                        goto ta_i32;
                    case JS_CLASS_INT32_ARRAY:
                        v = *((int32_t *)arr->buf + idx);
                    ta_i32:
                        js_printf(ctx, "%d", v);
                        break;
                    case JS_CLASS_UINT32_ARRAY:
                        v = *((uint32_t *)arr->buf + idx);
                        js_printf(ctx, "%u", v);
                        break;
                    case JS_CLASS_FLOAT32_ARRAY:
                        d = *((float *)arr->buf + idx);
                        goto ta_d;
                    case JS_CLASS_FLOAT64_ARRAY:
                        d = *((double *)arr->buf + idx);
                    ta_d:
                        js_dump_float64(ctx, d);
                        break;
                    }
                }
                js_printf(ctx, " ])");
            } else {
                int i, j, prop_count, hash_mask;
                JSProperty *pr;
                JSValueArray *arr;
                BOOL is_first = TRUE;

                arr = JS_VALUE_TO_PTR(p->props);
                prop_count = JS_VALUE_GET_INT(arr->arr[0]);
                hash_mask = JS_VALUE_GET_INT(arr->arr[1]);
                if (p->class_id == JS_CLASS_ARRAY) {
                    JSValueArray *tab = JS_VALUE_TO_PTR(p->u.array.tab);
                    js_printf(ctx, "[ ");
                    for(i = 0; i < p->u.array.len; i++) {
                        if (!is_first)
                            js_printf(ctx, ", ");
                        JS_PrintValue(ctx, tab->arr[i]);
                        is_first = FALSE;
                    }
                } else {
                    if (p->class_id != JS_CLASS_OBJECT) {
                        JSValue class_name = js_find_class_name(ctx, p->class_id);
                        if (!JS_IsNull(class_name))
                            JS_PrintValueF(ctx, class_name, JS_DUMP_NOQUOTE);
                        js_putchar(ctx, ' ');
                    }
                    js_printf(ctx, "{ ");
                }
                for(i = 0, j = 0; j < prop_count; i++) {
                    pr = (JSProperty *)&arr->arr[2 + (hash_mask + 1) + 3 * i];
                    if (pr->key != JS_UNINITIALIZED) {
                        if (!is_first)
                            js_printf(ctx, ", ");
                        JS_PrintValueF(ctx, pr->key, JS_DUMP_NOQUOTE);
                        js_printf(ctx, ": ");
                        if (!(flags & JS_DUMP_RAW) && pr->prop_type == JS_PROP_SPECIAL) {
                            JS_PrintValue(ctx, get_special_prop(ctx, pr->value));
                        } else {
                            JS_PrintValue(ctx, pr->value);
                        }
                        is_first = FALSE;
                        j++;
                    }
                }
                js_printf(ctx, " %c",
                          p->class_id == JS_CLASS_ARRAY ? ']' : '}');
            }
            break;
        }
    } else {
        const char *str;
        if (p->class_id == JS_CLASS_ARRAY)
            str = "Array";
        else if (p->class_id == JS_CLASS_ERROR)
            str = "Error";
        else if (p->class_id == JS_CLASS_CLOSURE ||
                 p->class_id == JS_CLASS_C_FUNCTION) {
            str = "Function";
        } else {
            str = "Object";
        }
        js_printf(ctx, "[object %s]", str);
    }
}

void dump_string(JSContext *ctx, int sep, const uint8_t *buf, size_t len, int flags)
{
    BOOL use_quote;
    const uint8_t *p, *p_end;
    size_t i, clen;
    int c;

    use_quote = TRUE;
    if (flags & JS_DUMP_NOQUOTE) {
        if (len >= 1 && is_ident_first(buf[0])) {
            for(i = 1; i < len; i++) {
                if (!is_ident_next(buf[i]))
                    goto need_quote;
            }
            use_quote = FALSE;
        }
    need_quote: ;
    }
    
    if (!(flags & JS_DUMP_RAW))
        sep = '"';
    if (use_quote)
        js_putchar(ctx, sep);
    p = buf;
    p_end = buf + len;
    while (p < p_end) {
        c = utf8_get(p, &clen);
        switch(c) {
        case '\t':
            c = 't';
            goto quote;
        case '\r':
            c = 'r';
            goto quote;
        case '\n':
            c = 'n';
            goto quote;
        case '\b':
            c = 'b';
            goto quote;
        case '\f':
            c = 'f';
            goto quote;
        case '\"':
        case '\\':
        quote:
            js_putchar(ctx, '\\');
            js_putchar(ctx, c);
            break;
        default:
            if (c < 32 || (c >= 0xd800 && c < 0xe000)) {
                js_printf(ctx, "\\u%04x", c);
            } else {
                ctx->write_func(ctx->opaque, p, clen);
            }
            break;
        }
        p += clen;
    }
    if (use_quote)
        js_putchar(ctx, sep);
}

void JS_PrintValueF(JSContext *ctx, JSValue val, int flags)
{
    if (JS_IsInt(val)) {
        js_printf(ctx, "%d", JS_VALUE_GET_INT(val));
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        js_dump_float64(ctx, js_get_short_float(val));
    } else
#endif
    if (!JS_IsPtr(val)) {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_NULL:
        case JS_TAG_UNDEFINED:
        case JS_TAG_UNINITIALIZED:
        case JS_TAG_BOOL:
            js_printf(ctx, "%"JSValue_PRI"", val);
            break;
        case JS_TAG_EXCEPTION:
            js_printf(ctx, "[exception %d]", JS_VALUE_GET_SPECIAL_VALUE(val));
            break;
        case JS_TAG_CATCH_OFFSET:
            js_printf(ctx, "[catch_offset %d]", JS_VALUE_GET_SPECIAL_VALUE(val));
            break;
        case JS_TAG_SHORT_FUNC:
            {
                int idx = JS_VALUE_GET_SPECIAL_VALUE(val);
                js_printf(ctx, "function ");
                JS_PrintValueF(ctx, reloc_c_func_name(ctx, ctx->c_function_table[idx].name), JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            }
            break;
        case JS_TAG_STRING_CHAR:
            {
                uint8_t buf[UTF8_CHAR_LEN_MAX + 1];
                int len;
                len = get_short_string(buf, val);
                dump_string(ctx, '`', buf, len, flags);
            }
            break;
        default:
            js_printf(ctx, "[tag %d]", (int)JS_VALUE_GET_SPECIAL_TAG(val));
            break;
        }
    } else {
        void *ptr = JS_VALUE_TO_PTR(val);
        int mtag = ((JSMemBlockHeader *)ptr)->mtag;
        switch(mtag) {
        case JS_MTAG_FLOAT64:
            {
                JSFloat64 *p = ptr;
                js_dump_float64(ctx, p->u.dval);
            }
            break;
        case JS_MTAG_OBJECT:
            js_dump_object(ctx, ptr, flags);
            break;
        case JS_MTAG_STRING:
            {
                JSString *p = ptr;
                int sep;
                sep = p->is_unique ? '\'' : '\"';
                dump_string(ctx, sep, p->buf, p->len, flags);
            }
            break;
        case JS_MTAG_VALUE_ARRAY:
            {
                JSValueArray *arr = ptr;
                js_dump_array(ctx, arr, arr->size);
            }
            break;
        case JS_MTAG_BYTE_ARRAY:
            {
                JSByteArray *arr = ptr;
                js_printf(ctx, "byte_array(%" PRIu64 ")", (uint64_t)arr->size);
            }
            break;
        case JS_MTAG_FUNCTION_BYTECODE:
            {
                JSFunctionBytecode *b = ptr;
                js_printf(ctx, "bytecode_function ");
                JS_PrintValueF(ctx, b->func_name, JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            }
            break;
        case JS_MTAG_VARREF:
            {
                JSVarRef *pv = ptr;
                js_printf(ctx, "var_ref(");
                if (pv->is_detached)
                    JS_PrintValue(ctx, pv->u.value);
                else
                    JS_PrintValue(ctx, *pv->u.pvalue);
                js_printf(ctx, ")");
            }
            break;
        default:
            js_printf(ctx, "[mtag %d]", mtag);
            break;
        }
    }
}

void JS_PrintValue(JSContext *ctx, JSValue val)
{
    return JS_PrintValueF(ctx, val, 0);
}

const char *get_mtag_name(unsigned int mtag)
{
    if (mtag >= countof(js_mtag_name))
        return "?";
    else
        return js_mtag_name[mtag];
}

uint32_t val_to_offset(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val))
        return 0;
    else
        return (uint8_t *)JS_VALUE_TO_PTR(val) - ctx->heap_base;
}

void JS_DumpMemory(JSContext *ctx, BOOL is_long)
{
    uint8_t *ptr;
    uint32_t mtag_mem_size[JS_MTAG_COUNT];
    uint32_t mtag_count[JS_MTAG_COUNT];
    uint32_t tot_size, i;
    if (is_long) {
        js_printf(ctx, "%10s %s %8s %15s %10s %10s %s\n", "OFFSET", "M", "SIZE", "TAG", "PROTO", "PROPS", "EXTRA");
    }
    for(i = 0; i < JS_MTAG_COUNT; i++) {
        mtag_mem_size[i] = 0;
        mtag_count[i] = 0;
    }
    tot_size = 0;
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        int mtag, size, gc_mark;
        mtag = ((JSMemBlockHeader *)ptr)->mtag;
        gc_mark = ((JSMemBlockHeader *)ptr)->gc_mark;
        size = get_mblock_size(ptr);
        mtag_mem_size[mtag] += size;
        mtag_count[mtag]++;
        tot_size += size;
        if (is_long) {
            js_printf(ctx, "0x%08x %c %8u %15s",
                      (unsigned int)((uint8_t *)ptr - ctx->heap_base),
                      gc_mark ? '*' : ' ',
                      size,
                      get_mtag_name(mtag));
            if (mtag != JS_MTAG_FREE) {
                if (mtag == JS_MTAG_OBJECT) {
                    JSObject *p = (JSObject *)ptr;
                    js_printf(ctx, " 0x%08x 0x%08x",
                              val_to_offset(ctx, p->proto), val_to_offset(ctx, p->props));
                } else {
                    js_printf(ctx, " %10s %10s", "", "");
                }
                js_printf(ctx, " ");
                JS_PrintValueF(ctx, JS_VALUE_FROM_PTR(ptr), JS_DUMP_RAW);
            }
            js_printf(ctx, "\n");
        }
        ptr += size;
    }
    
    js_printf(ctx, "%15s %8s %8s %8s %8s\n", "TAG", "COUNT", "AVG_SIZE", "SIZE", "RATIO");
    for(i = 0; i < JS_MTAG_COUNT; i++) {
        if (mtag_count[i] != 0) {
            js_printf(ctx, "%15s %8u %8d %8u %7d%%\n",
                      get_mtag_name(i),
                      (unsigned int)mtag_count[i],
                      (int)js_lrint((double)mtag_mem_size[i] / (double)mtag_count[i]),
                      (unsigned int)mtag_mem_size[i],
                      (int)js_lrint((double)mtag_mem_size[i] / (double)tot_size * 100.0));
        }
    }
    js_printf(ctx, "heap size=%u/%u stack_size=%u\n",
           (unsigned int)(ctx->heap_free - ctx->heap_base),
           (unsigned int)(ctx->stack_top - ctx->heap_base),
           (unsigned int)(ctx->stack_top - (uint8_t *)ctx->sp));
}

__maybe_unused void JS_DumpUniqueStrings(JSContext *ctx)
{
    int i;
    JSValueArray *arr;
    
    arr = JS_VALUE_TO_PTR( ctx->unique_strings);
    js_printf(ctx, "%5s %s\n", "N", "UNIQUE_STRING");
    for(i = 0; i < ctx->unique_strings_len; i++) {
        js_printf(ctx, "%5d ", i);
        JS_PrintValue(ctx, arr->arr[i]);
        js_printf(ctx, "\n");
    }
}
#else
void JS_PrintValueF(JSContext *ctx, JSValue val, int flags)
{
}
void JS_PrintValue(JSContext *ctx, JSValue val)
{
    return JS_PrintValueF(ctx, val, 0);
}
void JS_DumpMemory(JSContext *ctx, BOOL is_long)
{
}
__maybe_unused void JS_DumpUniqueStrings(JSContext *ctx)
{
}
#endif

void JS_DumpValueF(JSContext *ctx, const char *str,
                   JSValue val, int flags)
{
    js_printf(ctx, "%s=", str);
    JS_PrintValueF(ctx, val, flags);
    js_printf(ctx, "\n");
}

void JS_DumpValue(JSContext *ctx, const char *str,
                   JSValue val)
{
    JS_DumpValueF(ctx, str, val, 0);
}
