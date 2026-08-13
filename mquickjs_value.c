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

#ifdef JS_USE_SHORT_FLOAT

#define JS_FLOAT64_VALUE_EXP_MIN (1023 - 127)
#define JS_FLOAT64_VALUE_ADDEND ((uint64_t)(JS_FLOAT64_VALUE_EXP_MIN - (JS_TAG_SHORT_FLOAT << 8)) << 52)

/* 1 <= n <= 63 */
inline uint64_t rotl64(uint64_t a, int n)
{
    return (a << n) | (a >> (64 - n));
}

double js_get_short_float(JSValue v)
{
    return uint64_as_float64(rotl64(v, 60) + JS_FLOAT64_VALUE_ADDEND);
}

JSValue js_to_short_float(double d)
{
    return rotl64(float64_as_uint64(d) - JS_FLOAT64_VALUE_ADDEND, 4);
}

#endif /* JS_USE_SHORT_FLOAT */

JSValue js_alloc_float64(JSContext *ctx, double d)
{
    JSFloat64 *f;
    f = js_malloc(ctx, sizeof(JSFloat64), JS_MTAG_FLOAT64);
    if (!f)
        return JS_EXCEPTION;
    f->u.dval = d;
    return JS_VALUE_FROM_PTR(f);
}

/* create a new float64 value which is known not to be a short integer */
JSValue __JS_NewFloat64(JSContext *ctx, double d)
{
    if (float64_as_uint64(d) == 0x8000000000000000) {
        /* minus zero often happens, so it is worth having a constant
           value */
        return ctx->minus_zero;
    } else
#ifdef JS_USE_SHORT_FLOAT
    /* Note: this test is false for NaN */
    if (fabs(d) >= 0x1p-127 && fabs(d) <= 0x1p+128) {
        return js_to_short_float(d);
    } else
#endif
    {
        return js_alloc_float64(ctx, d);
    }
}

inline JSValue JS_NewShortInt(int32_t val)
{
    return JS_TAG_INT + (val << 1);
}

#if defined(USE_SOFTFLOAT)
JSValue JS_NewFloat64(JSContext *ctx, double d)
{
    uint64_t a, m;
    int e, b, shift;
    JSValue v;

    a = float64_as_uint64(d);
    if (a == 0) {
        v = JS_NewShortInt(0);
    } else {
        e = (a >> 52) & 0x7ff;
        if (e >= 1023 && e <= 1023 + 30 - 1) {
            m = (a & (((uint64_t)1 << 52) - 1)) | ((uint64_t)1 << 52);
            shift = 52 - (e - 1023);
            /* test if exact integer */
            if ((m & (((uint64_t)1 << shift) - 1)) != 0)
                goto not_int;
            b = m >> shift;
            if (a >> 63)
                b = -b;
            v = JS_NewShortInt(b);
        } else if (a == 0xc1d0000000000000) {
            v = JS_NewShortInt(-(1 << 30));
        } else {
        not_int:
            v = __JS_NewFloat64(ctx, d);
        }
    }
    return v;
}
#else
JSValue JS_NewFloat64(JSContext *ctx, double d)
{
    int32_t val;
    if (d >= JS_SHORTINT_MIN && d <= JS_SHORTINT_MAX) {
        val = (int32_t)d;
        /* -0 cannot be represented as integer, so we compare the bit
           representation */
        if (float64_as_uint64(d) == float64_as_uint64((double)val))
            return JS_NewShortInt(val);
    }
    return __JS_NewFloat64(ctx, d);
}
#endif

inline BOOL int64_is_short_int(int64_t val)
{
    return val >= JS_SHORTINT_MIN && val <= JS_SHORTINT_MAX;
}

JSValue JS_NewInt64(JSContext *ctx, int64_t val)
{
    JSValue v;
    if (likely(int64_is_short_int(val))) {
        v = JS_NewShortInt(val);
    } else {
        v = __JS_NewFloat64(ctx, val);
    }
    return v;
}

JSValue JS_NewInt32(JSContext *ctx, int32_t val)
{
    return JS_NewInt64(ctx, val);
}

JSValue JS_NewUint32(JSContext *ctx, uint32_t val)
{
    return JS_NewInt64(ctx, val);
}

BOOL JS_IsPrimitive(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return JS_VALUE_GET_SPECIAL_TAG(val) != JS_TAG_SHORT_FUNC;
    } else {
        return (js_get_mtag(JS_VALUE_TO_PTR(val)) != JS_MTAG_OBJECT);
    }
}

/* Note: short functions are not considered as objects by this function */
BOOL JS_IsObject(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return FALSE;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        return (p->mtag == JS_MTAG_OBJECT);
    }
}

/* return -1 if not an object */
int JS_GetClassID(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return -1;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        if (p->mtag != JS_MTAG_OBJECT)
            return -1;
        else
            return p->class_id;
    }
}

void JS_SetOpaque(JSContext *ctx, JSValue val, void *opaque)
{
    JSObject *p;
    assert(JS_IsPtr(val));
    p = JS_VALUE_TO_PTR(val);
    assert(p->mtag == JS_MTAG_OBJECT);
    assert(p->class_id >= JS_CLASS_USER);
    p->u.user.opaque = opaque;
}

void *JS_GetOpaque(JSContext *ctx, JSValue val)
{
    JSObject *p;
    assert(JS_IsPtr(val));
    p = JS_VALUE_TO_PTR(val);
    assert(p->mtag == JS_MTAG_OBJECT);
    assert(p->class_id >= JS_CLASS_USER);
    return p->u.user.opaque;
}

JSObject *js_get_object_class(JSContext *ctx, JSValue val, int class_id)
{
    if (!JS_IsPtr(val)) {
        return NULL;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        if (p->mtag != JS_MTAG_OBJECT || p->class_id != class_id)
            return NULL;
        else
            return p;
    }
}

BOOL JS_IsFunction(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_SHORT_FUNC;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        return (p->mtag == JS_MTAG_OBJECT &&
                (p->class_id == JS_CLASS_CLOSURE ||
                 p->class_id == JS_CLASS_C_FUNCTION));
    }
}

BOOL JS_IsFunctionObject(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return FALSE;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        return (p->mtag == JS_MTAG_OBJECT &&
                (p->class_id == JS_CLASS_CLOSURE ||
                 p->class_id == JS_CLASS_C_FUNCTION));
    }
}

BOOL JS_IsError(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return FALSE;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(val);
        return (p->mtag == JS_MTAG_OBJECT && p->class_id == JS_CLASS_ERROR);
    }
}


BOOL JS_IsNumber(JSContext *ctx, JSValue val)
{
    if (JS_IsIntOrShortFloat(val)) {
        return TRUE;
    } else if (JS_IsPtr(val)) {
        void *ptr = JS_VALUE_TO_PTR(val);
        return (js_get_mtag(ptr) == JS_MTAG_FLOAT64);
    } else {
        return FALSE;
    }
}

BOOL JS_IsString(JSContext *ctx, JSValue val)
{
    if (!JS_IsPtr(val)) {
        return JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR;
    } else {
        void *ptr = JS_VALUE_TO_PTR(val);
        return (js_get_mtag(ptr) == JS_MTAG_STRING);
    }
}

JSString *js_alloc_string(JSContext *ctx, uint32_t buf_len)
{
    JSString *p;

    if (buf_len > JS_STRING_LEN_MAX) {
        JS_ThrowInternalError(ctx, "string too long");
        return NULL;
    }
    p = js_malloc(ctx, sizeof(JSString) + buf_len + 1, JS_MTAG_STRING);
    if (!p)
        return NULL;
    p->is_unique = FALSE;
    p->is_ascii = FALSE;
    p->is_numeric = FALSE;
    p->len = buf_len;
    p->buf[buf_len] = '\0';
    return p;
}

/* 0 <= c <= 0x10ffff */
inline JSValue JS_NewStringChar(uint32_t c)
{
    return JS_VALUE_MAKE_SPECIAL(JS_TAG_STRING_CHAR, c);
}


BOOL is_ascii_string(const char *buf, size_t len)
{
    size_t i;
    for(i = 0; i < len; i++) {
        if ((uint8_t)buf[i] > 0x7f)
            return FALSE;
    }
    return TRUE;
}

JSString *get_string_ptr(JSContext *ctx, JSStringCharBuf *buf, JSValue val)
{
    if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
        JSString *p = (JSString *)buf;
        p->is_unique = FALSE;
        p->is_ascii = JS_VALUE_GET_SPECIAL_VALUE(val) <= 0x7f;
        p->len = get_short_string(p->buf, val);
        return p;
    } else {
        return JS_VALUE_TO_PTR(val);
    }
}

JSValue js_sub_string_utf8(JSContext *ctx, JSValue val, uint32_t start0, uint32_t end0)
{
    JSString *p, *p1;
    int len, start, end, c;
    BOOL start_surrogate, end_surrogate;
    JSStringCharBuf buf;
    JSGCRef val_ref;
    const uint8_t *ptr;
    size_t clen;
    
    if (end0 - start0 == 0) {
        return js_get_atom(ctx, JS_ATOM_empty);
    }
    start_surrogate = start0 & 1;
    end_surrogate = end0 & 1;
    start = start0 >> 1;
    end = end0 >> 1;
    len = end - start;
    p1 = get_string_ptr(ctx, &buf, val);
    ptr = p1->buf;
    if (!start_surrogate && !end_surrogate && utf8_char_len(ptr[start]) == len) {
        c = utf8_get(ptr + start, &clen);
        return JS_NewStringChar(c);
    }

    JS_PUSH_VALUE(ctx, val);
    p = js_alloc_string(ctx, len - start_surrogate + (end_surrogate ? 3 : 0));
    JS_POP_VALUE(ctx, val);
    if (!p)
        return JS_EXCEPTION;
    p1 = get_string_ptr(ctx, &buf, val);
    ptr = p1->buf;
    if (unlikely(start_surrogate || end_surrogate)) {
        uint8_t *q = p->buf;
        p->is_ascii = FALSE;
        if (start_surrogate) {
            c = utf8_get(ptr + start, &clen);
            c = 0xdc00 + ((c - 0x10000) & 0x3ff); /* right surrogate */
            q += unicode_to_utf8(q, c);
            start += 4;
        }
        memcpy(q, ptr + start, end - start);
        q += end - start;
        if (end_surrogate) {
            c = utf8_get(ptr + end, &clen);
            c = 0xd800 + ((c - 0x10000) >> 10); /* left surrogate */
            q += unicode_to_utf8(q, c);
        }
        assert((q - p->buf) == p->len);
    } else {
        p->is_ascii = p1->is_ascii ? TRUE : is_ascii_string((const char *)(ptr + start), len);
        memcpy(p->buf, ptr + start, len);
    }
    return JS_VALUE_FROM_PTR(p);
}

/* Warning: the string must be a valid WTF-8 string (= UTF-8 +
   unpaired surrogates). */
JSValue JS_NewStringLen(JSContext *ctx, const char *buf, size_t len)
{
    JSString *p;
    
    if (len == 0) {
        return js_get_atom(ctx, JS_ATOM_empty);
    } else {
        if (utf8_char_len(buf[0]) == len) {
            size_t clen;
            int c;
            c = utf8_get((const uint8_t *)buf, &clen);
            return JS_NewStringChar(c);
        }
    }
    p = js_alloc_string(ctx, len);
    if (!p)
        return JS_EXCEPTION;
    p->is_ascii = is_ascii_string((const char *)buf, len);
    memcpy(p->buf, buf, len);
    return JS_VALUE_FROM_PTR(p);
}

/* Warning: the string must be a valid UTF-8 string. */
JSValue JS_NewString(JSContext *ctx, const char *buf)
{
    return JS_NewStringLen(ctx, buf, strlen(buf));
}

/* the byte array must be zero terminated. */
JSValue js_byte_array_to_string(JSContext *ctx, JSValue val, int len, BOOL is_ascii)
{
    JSByteArray *arr = JS_VALUE_TO_PTR(val);
    JSString *p;

    assert(len + 1 <= arr->size);
    if (len == 0) {
        return js_get_atom(ctx, JS_ATOM_empty);
    } else if (utf8_char_len(arr->buf[0]) == len) {
        size_t clen;
        return JS_NewStringChar(utf8_get(arr->buf, &clen));
    } else {
        js_shrink_byte_array(ctx, &val, len + 1);
        p = (JSString *)arr;
        p->mtag = JS_MTAG_STRING;
        p->is_ascii = is_ascii;
        p->is_unique = FALSE;
        p->is_numeric = FALSE;
        p->len = len;
        return val;
    }
}

/* in bytes */
__maybe_unused int js_string_byte_len(JSContext *ctx, JSValue val)
{
    if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
        int c = JS_VALUE_GET_SPECIAL_VALUE(val);
        if (c < 0x80)
            return 1;
        else if (c < 0x800)
            return 2;
        else if (c < 0x10000)
            return 3;
        else
            return 4;
    } else {
        JSString *p = JS_VALUE_TO_PTR(val);
        return p->len;
    }
}
    
/* assuming that utf8_next() returns 4, validate the corresponding UTF-8 sequence */
BOOL is_valid_len4_utf8(const uint8_t *buf)
{
    return (((buf[0] & 0xf) << 6) | (buf[1] & 0x3f)) >= 0x10;
}

__maybe_unused void dump_string_pos_cache(JSContext *ctx)
{
    int i;
    JSStringPosCacheEntry *ce;
    for(i = 0; i < JS_STRING_POS_CACHE_SIZE; i++) {
        ce = &ctx->string_pos_cache[i];
        printf("%d: ", i);
        if (ce->str == JS_NULL) {
            printf("<empty>\n");
        } else {
            JSString *p = JS_VALUE_TO_PTR(ce->str);
            printf(" utf8_pos=%u/%u utf16_pos=%u\n",
                   ce->str_pos[POS_TYPE_UTF8], (int)p->len, ce->str_pos[POS_TYPE_UTF16]);
        }
    }
}

/* an UTF-8 position is the byte position multiplied by 2. One is
   added when the corresponding UTF-16 character represents the right
   surrogate if the code is >= 0x10000.
*/
uint32_t js_string_convert_pos(JSContext *ctx, JSValue val, uint32_t pos, StringPosTypeEnum pos_type)
{
    JSStringCharBuf buf;
    JSString *p;
    size_t i, clen, len, start;
    uint32_t d_min, d, j;
    JSStringPosCacheEntry *ce, *ce1;
    uint32_t surrogate_flag, has_surrogate, limit;
    int ce_idx;

    p = get_string_ptr(ctx, &buf, val);
    len = p->len;
    if (p->is_ascii) {
        if (pos_type == POS_TYPE_UTF8)
            return min_int(len, pos / 2);
        else
            return min_int(len, pos) * 2;
    }

    if (pos_type == POS_TYPE_UTF8) {
        has_surrogate = pos & 1;
        pos >>= 1;
    } else {
        has_surrogate = 0;
    }
    
    ce = NULL;
    if (len < JS_STRING_POS_CACHE_MIN_LEN) {
        j = 0;
        i = 0;
        goto uncached;
    }

    d_min = pos;
    for(ce_idx = 0; ce_idx < JS_STRING_POS_CACHE_SIZE; ce_idx++) {
        ce1 = &ctx->string_pos_cache[ce_idx];
        if (ce1->str == val) {
            d = ce1->str_pos[pos_type];
            d = d >= pos ? d - pos : pos - d;
            if (d < d_min) {
                d_min = d;
                ce = ce1;
            }
        }
    }
    if (!ce) {
        /* "random" replacement */
        ce = &ctx->string_pos_cache[ctx->string_pos_cache_counter];
        if (++ctx->string_pos_cache_counter == JS_STRING_POS_CACHE_SIZE)
            ctx->string_pos_cache_counter = 0;
        ce->str = val;
        ce->str_pos[POS_TYPE_UTF8] = 0;
        ce->str_pos[POS_TYPE_UTF16] = 0;
    }
    
    i = ce->str_pos[POS_TYPE_UTF8];
    j = ce->str_pos[POS_TYPE_UTF16];
    if (ce->str_pos[pos_type] <= pos) {
    uncached:
        surrogate_flag = 0;
        if (pos_type == POS_TYPE_UTF8) {
            limit = INT32_MAX;
            len = pos;
        } else {
            limit = pos;
        }
        for(; i < len; i += clen) {
            if (j == limit)
                break;
            clen = utf8_char_len(p->buf[i]);
            if (clen == 4 && is_valid_len4_utf8(p->buf + i)) {
                if ((j + 1) == limit) {
                    surrogate_flag = 1;
                    break;
                }
                j += 2;
            } else {
                j++;
            }
        }
    } else {
        surrogate_flag = 0;
        if (pos_type == POS_TYPE_UTF8) {
            start = pos;
            limit = INT32_MAX;
        } else {
            limit = pos;
            start = 0;
        }
        while (i > start) {
            size_t i0 = i;
            i--;
            while ((p->buf[i] & 0xc0) == 0x80)
                i--;
            clen = i0 - i;
            if (clen == 4 && is_valid_len4_utf8(p->buf + i)) {
                j -= 2;
                if ((j + 1) == limit) {
                    surrogate_flag = 1;
                    break;
                }
            } else {
                j--;
            }
            if (j == limit)
                break;
        }
    }
    if (ce) {
        ce->str_pos[POS_TYPE_UTF8] = i;
        ce->str_pos[POS_TYPE_UTF16] = j;
    }
    if (pos_type == POS_TYPE_UTF8)
        return j + has_surrogate;
    else
        return i * 2 + surrogate_flag;
}

uint32_t js_string_utf16_to_utf8_pos(JSContext *ctx, JSValue val, uint32_t utf16_pos)
{
    return js_string_convert_pos(ctx, val, utf16_pos, POS_TYPE_UTF16);
}

uint32_t js_string_utf8_to_utf16_pos(JSContext *ctx, JSValue val, uint32_t utf8_pos)
{
    return js_string_convert_pos(ctx, val, utf8_pos, POS_TYPE_UTF8);
}

/* Testing the third byte is not needed as the UTF-8 encoding must be
   correct */
BOOL is_utf8_left_surrogate(const uint8_t *p)
{
    return p[0] == 0xed && (p[1] >= 0xa0 && p[1] <= 0xaf);
}

BOOL is_utf8_right_surrogate(const uint8_t *p)
{
    return p[0] == 0xed && (p[1] >= 0xb0 && p[1] <= 0xbf);
}

/* return 0 if OK, -1 in case of exception (exception possible if len > 0) */
int string_buffer_push(JSContext *ctx, StringBuffer *s, int len)
{
    s->len = 0;
    s->is_ascii = TRUE;
    if (len > 0) {
        JSByteArray *arr;
        arr = js_alloc_byte_array(ctx, len);
        if (!arr)
            return -1;
        s->buffer_ref.val = JS_VALUE_FROM_PTR(arr);
    } else {
        s->buffer_ref.val = js_get_atom(ctx, JS_ATOM_empty);
    }
    s->buffer_ref.prev = ctx->top_gc_ref;
    ctx->top_gc_ref = &s->buffer_ref;
    return 0;
}

/* val2 must be a string. Return 0 if OK, -1 in case of exception */
int string_buffer_concat_str(JSContext *ctx, StringBuffer *s, JSValue val2)
{
    JSStringCharBuf buf1, buf2;
    JSByteArray *arr;
    JSString *p1, *p2;
    int len, len1, len2;
    JSValue val1;
    uint8_t *q;
    
    if (JS_IsException(s->buffer_ref.val))
        return -1;
    p2 = get_string_ptr(ctx, &buf2, val2);
    len2 = p2->len;
    if (len2 == 0)
        return 0;
    if (JS_IsString(ctx, s->buffer_ref.val)) {
        p1 = get_string_ptr(ctx, &buf1, s->buffer_ref.val);
        len1 = p1->len;
        if (len1 == 0) {
            /* empty string in buffer: just keep 'val2' */
            s->buffer_ref.val = val2;
            return 0;
        }
        arr = NULL;
        val1 = s->buffer_ref.val;
        s->buffer_ref.val = JS_NULL;
    } else {
        arr = JS_VALUE_TO_PTR(s->buffer_ref.val);
        len1 = s->len;
        val1 = JS_NULL;
    }

    len = len1 + len2;
    if (len > JS_STRING_LEN_MAX) {
        s->buffer_ref.val = JS_ThrowInternalError(ctx, "string too long");
        return -1;
    }

    if (!arr || (len + 1) > arr->size) {
        JSGCRef val1_ref, val2_ref;

        JS_PUSH_VALUE(ctx, val1);
        JS_PUSH_VALUE(ctx, val2);
        s->buffer_ref.val = js_resize_byte_array(ctx, s->buffer_ref.val, len + 1);
        JS_POP_VALUE(ctx, val2);
        JS_POP_VALUE(ctx, val1);
        if (JS_IsException(s->buffer_ref.val))
            return -1;
        arr = JS_VALUE_TO_PTR(s->buffer_ref.val);
        if (val1 != JS_NULL) {
            p1 = get_string_ptr(ctx, &buf1, val1);
            s->is_ascii = p1->is_ascii;
            memcpy(arr->buf, p1->buf, len1);
        }
        p2 = get_string_ptr(ctx, &buf2, val2);
    }
    
    q = arr->buf + len1;
    if (len2 >= 3 && unlikely(is_utf8_right_surrogate(p2->buf)) &&
        len1 >= 3 && is_utf8_left_surrogate(q - 3)) {
        size_t clen;
        int c;
        /* contract the two surrogates to 4 bytes */
        c = (utf8_get(q - 3, &clen) & 0x3ff) << 10;
        c |= (utf8_get(p2->buf, &clen) & 0x3ff);
        c += 0x10000;
        len -= 2;
        len2 -= 3;
        q -= 3;
        q += unicode_to_utf8(q, c);
        s->is_ascii = FALSE;
    }
    memcpy(q, p2->buf + p2->len - len2, len2);
    s->len = len;
    s->is_ascii &= p2->is_ascii;
    return 0;
}

/* 'str' must be a string */
int string_buffer_concat_utf8(JSContext *ctx, StringBuffer *s, JSValue str, uint32_t start, uint32_t end)
{
    JSValue val2;
    
    if (end <= start)
        return 0;
    /* XXX: avoid explicitly constructing the substring */
    val2 = js_sub_string_utf8(ctx, str, start, end);
    if (JS_IsException(val2)) {
        s->buffer_ref.val = JS_EXCEPTION;
        return -1;
    }
    return string_buffer_concat_str(ctx, s, val2);
}

int string_buffer_concat_utf16(JSContext *ctx, StringBuffer *s, JSValue str, uint32_t start, uint32_t end)
{
    uint32_t start_utf8, end_utf8;
    if (end <= start)
        return 0;
    start_utf8 = js_string_utf16_to_utf8_pos(ctx, str, start);
    end_utf8 = js_string_utf16_to_utf8_pos(ctx, str, end);
    return string_buffer_concat_utf8(ctx, s, str, start_utf8, end_utf8);
}

int string_buffer_concat(JSContext *ctx, StringBuffer *s, JSValue val2)
{
    val2 = JS_ToString(ctx, val2);
    if (JS_IsException(val2)) {
        s->buffer_ref.val = JS_EXCEPTION;
        return -1;
    }
    return string_buffer_concat_str(ctx, s, val2);
}

/* XXX: could optimize */
int string_buffer_putc(JSContext *ctx, StringBuffer *s, int c)
{
    return string_buffer_concat_str(ctx, s, JS_NewStringChar(c));
}

int string_buffer_puts(JSContext *ctx, StringBuffer *s, const char *str)
{
    JSValue val;

    /* XXX: avoid this allocation */
    val = JS_NewString(ctx, str);
    if (JS_IsException(val))
        return -1;
    return string_buffer_concat_str(ctx, s, val);
}

JSValue string_buffer_pop(JSContext *ctx, StringBuffer *s)
{
    JSValue res;
    if (JS_IsException(s->buffer_ref.val) ||
        JS_IsString(ctx, s->buffer_ref.val)) {
        res = s->buffer_ref.val;
    } else {
        if (s->len != 0) {
            /* add the trailing '\0' */
            JSByteArray *arr = JS_VALUE_TO_PTR(s->buffer_ref.val);
            arr->buf[s->len] = '\0';
        }
        res = js_byte_array_to_string(ctx, s->buffer_ref.val, s->len, s->is_ascii);
    }
    ctx->top_gc_ref = s->buffer_ref.prev;
    return res;
}

/* val1 and val2 must be strings or exception */
JSValue JS_ConcatString(JSContext *ctx, JSValue val1, JSValue val2)
{
    StringBuffer b_s, *b = &b_s;

    if (JS_IsException(val1) ||
        JS_IsException(val2))
        return JS_EXCEPTION;

    string_buffer_push(ctx, b, 0);
    string_buffer_concat_str(ctx, b, val1); /* no memory allocation */
    string_buffer_concat_str(ctx, b, val2);
    return string_buffer_pop(ctx, b);
}

BOOL js_string_eq(JSContext *ctx, JSValue val1, JSValue val2)
{
    JSStringCharBuf buf1, buf2;
    JSString *p1, *p2;

    p1 = get_string_ptr(ctx, &buf1, val1);
    p2 = get_string_ptr(ctx, &buf2, val2);
    if (p1->len != p2->len)
        return FALSE;
    return !memcmp(p1->buf, p2->buf, p1->len);
}

/* Return the unicode character containing the byte at position
   'i'. Return -1 in case of error. */
int string_get_cp(const uint8_t *p)
{
    size_t clen;
    while ((*p & 0xc0) == 0x80)
        p--;
    return utf8_get(p, &clen);
}

int js_string_compare(JSContext *ctx, JSValue val1, JSValue val2)
{
    JSStringCharBuf buf1, buf2;
    int len, i, res;
    JSString *p1, *p2;
    
    p1 = get_string_ptr(ctx, &buf1, val1);
    p2 = get_string_ptr(ctx, &buf2, val2);
    len = min_int(p1->len, p2->len);
    for(i = 0; i < len; i++) {
        if (p1->buf[i] != p2->buf[i])
            break;
    }
    if (i != len) {
        int c1, c2;
        /* if valid UTF-8, the strings cannot be equal at this point */
        /* Note: UTF-16 does not preserve unicode order like UTF-8 */
        c1 = string_get_cp(p1->buf + i);
        c2 = string_get_cp(p2->buf + i);
        if ((c1 < 0x10000 && c2 < 0x10000) ||
            (c1 >= 0x10000 && c2 >= 0x10000)) {
            if (c1 < c2)
                res = -1;
            else
                res = 1;
        } else if (c1 < 0x10000) {
            /* p1 < p2 if same first UTF-16 char */
            c2 = 0xd800 + ((c2 - 0x10000) >> 10);
            if (c1 <= c2)
                res = -1;
            else
                res = 1;
        } else {
            /* p1 > p2 if same first UTF-16 char */
            c1 = 0xd800 + ((c1 - 0x10000) >> 10);
            if (c1 < c2)
                res = -1;
            else
                res = 1;
        }
    } else {
        if (p1->len == p2->len)
            res = 0;
        else if (p1->len < p2->len)
            res = -1;
        else
            res = 1;
    }
    return res;
}

/* return the string length in UTF16 characters. 'val' must be a
   string char or a string */
int js_string_len(JSContext *ctx, JSValue val)
{
    if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
        return JS_VALUE_GET_SPECIAL_VALUE(val) >= 0x10000 ? 2 : 1;
    } else {
        JSString *p;
        p = JS_VALUE_TO_PTR(val);
        if (p->is_ascii)
            return p->len;
        else
            return js_string_utf8_to_utf16_pos(ctx, val, p->len * 2);
    }
}

/* return the UTF-16 code or the unicode character at a given UTF-8
   position or -1 if outside the string */
int string_getcp(JSContext *ctx, JSValue str, uint32_t utf16_pos, BOOL is_codepoint)
{
    JSString *p;
    JSStringCharBuf buf;
    uint32_t surrogate_flag, c, utf8_pos;
    size_t clen;

    utf8_pos = js_string_utf16_to_utf8_pos(ctx, str, utf16_pos);
    surrogate_flag = utf8_pos & 1;
    utf8_pos >>= 1;
    p = get_string_ptr(ctx, &buf, str);
    if (utf8_pos >= p->len)
        return -1;
    c = utf8_get(p->buf + utf8_pos, &clen);
    if (c < 0x10000 || (!surrogate_flag && is_codepoint)) {
        return c;
    } else {
        c -= 0x10000;
        if (!surrogate_flag)
            return 0xd800 + (c >> 10); /* left surrogate */
        else
            return 0xdc00 + (c & 0x3ff); /* right surrogate */
    }
}

int string_getc(JSContext *ctx, JSValue str, uint32_t utf16_pos)
{
    return string_getcp(ctx, str, utf16_pos, FALSE);
}

/* precondition: 0 <= start <= end <= string length */
JSValue js_sub_string(JSContext *ctx, JSValue val, int start, int end)
{
    uint32_t start_utf8, end_utf8;
    
    if (end <= start)
        return js_get_atom(ctx, JS_ATOM_empty);
    start_utf8 = js_string_utf16_to_utf8_pos(ctx, val, start);
    end_utf8 = js_string_utf16_to_utf8_pos(ctx, val, end);
    return js_sub_string_utf8(ctx, val, start_utf8, end_utf8);
}

inline int is_num(int c)
{
    return c >= '0' && c <= '9';
}

/* return TRUE if the property 'val' represents a numeric property. -1
   is returned in case of exception. 'val' must be a string.  It is
   assumed that NaN and infinities have already been handled. */
int js_is_numeric_string(JSContext *ctx, JSValue val)
{
    int c, len;
    double d;
    const char *r, *q;
    JSString *p;
    JSByteArray *tmp_arr;
    JSGCRef val_ref;
    char buf[32]; /* enough for js_dtoa() */
    
    p = JS_VALUE_TO_PTR(val);
    /* the fast case is when the string is not a number */
    if (p->len == 0 || !p->is_ascii)
        return FALSE;
    q = (const char *)p->buf;
    c = *q;
    if (c == '-') {
        if (p->len == 1)
            return FALSE;
        q++;
        c = *q;
    }
    if (!is_num(c))
        return FALSE;

    JS_PUSH_VALUE(ctx, val);
    tmp_arr = js_alloc_byte_array(ctx, max_int(sizeof(JSATODTempMem),
                                               sizeof(JSDTOATempMem)));
    JS_POP_VALUE(ctx, val);
    if (!tmp_arr)
        return -1;
    p = JS_VALUE_TO_PTR(val);
    d = js_atod((char *)p->buf, &r, 10, 0, (JSATODTempMem *)tmp_arr->buf);
    if ((r - (char *)p->buf) != p->len) {
        js_free(ctx, tmp_arr);
        return FALSE;
    }
    len = js_dtoa(buf, d, 10, 0, JS_DTOA_FORMAT_FREE, (JSDTOATempMem *)tmp_arr->buf);
    js_free(ctx, tmp_arr);
    return (p->len == len && !memcmp(buf, p->buf, len));
}

/* return JS_NULL if not found */
JSValue find_atom(JSContext *ctx, int *pidx, const JSValueArray *arr, int len, JSValue val)
{
    int a, b, m, r;
    JSValue val1;

    a = 0;
    b = len - 1;
    while (a <= b) {
        m = (a + b) >> 1;
        val1 = arr->arr[m];
        r = js_string_compare(ctx, val, val1);
        if (r == 0) {
            /* found */
            *pidx = m;
            return val1;
        } else if (r < 0) {
            b = m - 1;
        } else {
            a = m + 1;
        }
    }
    *pidx = a;
    return JS_NULL;
}

/* if 'val' is not a string, it is returned */
/* XXX: use hash table */
JSValue JS_MakeUniqueString(JSContext *ctx, JSValue val)
{
    JSString *p;
    int a, is_numeric, i;
    JSValueArray *arr;
    const JSValueArray *arr1;
    JSValue val1, new_tab;
    JSGCRef val_ref;
    
    if (!JS_IsPtr(val))
        return val;
    p = JS_VALUE_TO_PTR(val);
    if (p->mtag != JS_MTAG_STRING || p->is_unique)
        return val;

    /* not unique: find it in the ROM or RAM sorted unique string table */
    for(i = 0; i < ctx->n_rom_atom_tables; i++) {
        arr1 = ctx->rom_atom_tables[i];
        if (arr1) {
            val1 = find_atom(ctx, &a, arr1, arr1->size, val); 
            if (!JS_IsNull(val1))
                return val1;
        }
    }
    
    arr = JS_VALUE_TO_PTR( ctx->unique_strings);
    val1 = find_atom(ctx, &a, arr, ctx->unique_strings_len, val); 
    if (!JS_IsNull(val1))
        return val1;
    
    JS_PUSH_VALUE(ctx, val);
    is_numeric = js_is_numeric_string(ctx, val);
    JS_POP_VALUE(ctx, val);
    if (is_numeric < 0)
        return JS_EXCEPTION;
    
    /* not found: add it in the table */
    JS_PUSH_VALUE(ctx, val);
    new_tab = js_resize_value_array(ctx, ctx->unique_strings,
                                 ctx->unique_strings_len + 1);
    JS_POP_VALUE(ctx, val);
    if (JS_IsException(new_tab))
        return JS_EXCEPTION;
    ctx->unique_strings = new_tab;
    arr = JS_VALUE_TO_PTR( ctx->unique_strings);
    memmove(&arr->arr[a + 1], &arr->arr[a],
            sizeof(arr->arr[0]) * (ctx->unique_strings_len - a));
    arr->arr[a] = val;
    p = JS_VALUE_TO_PTR(val);
    p->is_unique = TRUE;
    p->is_numeric = is_numeric;
    ctx->unique_strings_len++;
    return val;
}

int JS_ToBool(JSContext *ctx, JSValue val)
{
    if (JS_IsInt(val)) {
        return JS_VALUE_GET_INT(val) != 0;
    } else
#ifdef JS_USE_SHORT_FLOAT
    if (JS_IsShortFloat(val)) {
        double d;
        d = js_get_short_float(val);
        return !isnan(d) && d != 0;
    } else
#endif
    if (!JS_IsPtr(val)) {
        switch(JS_VALUE_GET_SPECIAL_TAG(val)) {
        case JS_TAG_BOOL:
        case JS_TAG_NULL:
        case JS_TAG_UNDEFINED:
            return JS_VALUE_GET_SPECIAL_VALUE(val);
        case JS_TAG_SHORT_FUNC:
        case JS_TAG_STRING_CHAR:
            return TRUE;
        default:
            return FALSE;
        }
    } else {
        JSMemBlockHeader *h = JS_VALUE_TO_PTR(val);
        switch(h->mtag) {
        case JS_MTAG_STRING:
            {
                JSString *p = (JSString *)h;
                return p->len != 0;
            }
        case JS_MTAG_FLOAT64:
            {
                JSFloat64 *p = (JSFloat64 *)h;
                return !isnan(p->u.dval) && p->u.dval != 0;
            }
        default:
        case JS_MTAG_OBJECT:
            return TRUE;
        }
    }
}

/* plen can be NULL. No memory allocation is done if 'val' already is
   a string. */
const char *JS_ToCStringLen(JSContext *ctx, size_t *plen, JSValue val,
                            JSCStringBuf *buf)
{
    const char *p;
    int len;

    val = JS_ToString(ctx, val);
    if (JS_IsException(val))
        return NULL;
    if (JS_VALUE_GET_SPECIAL_TAG(val) == JS_TAG_STRING_CHAR) {
        len = get_short_string(buf->buf, val);
        p = (const char *)buf->buf;
    } else {
        JSString *r;
        r = JS_VALUE_TO_PTR(val);
        p = (const char *)r->buf;
        len = r->len;
    }
    if (plen)
        *plen = len;
    return p;
}

const char *JS_ToCString(JSContext *ctx, JSValue val, JSCStringBuf *buf)
{
    return JS_ToCStringLen(ctx, NULL, val, buf);
}

BOOL JS_HasException(JSContext *ctx)
{
    return !JS_IsUninitialized(ctx->current_exception);
}

JSValue JS_GetException(JSContext *ctx)
{
    JSValue obj;
    obj = ctx->current_exception;
    ctx->current_exception = JS_UNINITIALIZED;
    return obj;
}

JSValue JS_ToStringCheckObject(JSContext *ctx, JSValue val)
{
    if (val == JS_NULL || val == JS_UNDEFINED)
        return JS_ThrowTypeError(ctx, "null or undefined are forbidden");
    return JS_ToString(ctx, val);
}

JSValue JS_ThrowTypeErrorNotAnObject(JSContext *ctx)
{
    return JS_ThrowTypeError(ctx, "not an object");
}

/* 'val' must be a string. return TRUE if the string represents a
   short integer */
inline BOOL is_num_string(JSContext *ctx, int32_t *pval, JSValue val)
{
    JSStringCharBuf buf;
    uint32_t n;
    uint64_t n64;
    JSString *p1;
    int c, is_neg;
    const uint8_t *p, *p_end;
    
    p1 = get_string_ptr(ctx, &buf, val);
    if (p1->len == 0 || p1->len > 11 || !p1->is_ascii)
        return FALSE;
    p = p1->buf;
    p_end = p + p1->len;
    c = *p++;
    is_neg = 0;
    if (c == '-') {
        if (p >= p_end)
            return FALSE;
        is_neg = 1;
        c = *p++;
    }
    if (!is_num(c))
        return FALSE;
    if (c == '0') {
        if (p != p_end || is_neg)
            return FALSE;
        n = 0;
    } else {
        n = c - '0';
        while (p < p_end) {
            c = *p++;
            if (!is_num(c))
                return FALSE;
            /* XXX: simplify ? */
            n64 = (uint64_t)n * 10 + (c - '0');
            if (n64 > (JS_SHORTINT_MAX + is_neg))
                return FALSE;
            n = n64;
        }
        if (is_neg)
            n = -n;
    }
    *pval = n;
    return TRUE;
}

/* return TRUE if the property 'val' represent a numeric property. It
   is assumed that the shortint case has been tested before */
BOOL JS_IsNumericProperty(JSContext *ctx, JSValue val)
{
    JSString *p;
    if (!JS_IsPtr(val))
        return FALSE; /* JS_TAG_STRING_CHAR */
    p = JS_VALUE_TO_PTR(val);
    return p->is_numeric;
}

JSValueArray *js_alloc_value_array(JSContext *ctx, int init_base, int new_size)
{
    JSValueArray *arr;
    int i;
    
    if (new_size > JS_VALUE_ARRAY_SIZE_MAX) {
        JS_ThrowOutOfMemory(ctx);
        return NULL;
    }
    arr = js_malloc(ctx, sizeof(JSValueArray) + new_size * sizeof(JSValue), JS_MTAG_VALUE_ARRAY);
    if (!arr)
        return NULL;
    arr->size = new_size;
    for(i = init_base; i < new_size; i++)
        arr->arr[i] = JS_UNDEFINED;
    return arr;
}

/* val can be JS_NULL (zero size). 'prop_base' is non zero only when
 * resizing the property arrays so that the property array has a size
 * which is a multiple of 3 */
JSValue js_resize_value_array2(JSContext *ctx, JSValue val, int new_size, int prop_base)
{
    JSValueArray *slots, *new_slots;
    int old_size, new_size1;
    JSGCRef val_ref;
    
    if (val == JS_NULL) {
        slots = NULL;
        old_size = 0;
    } else {
        slots = JS_VALUE_TO_PTR(val);
        old_size = slots->size;
    }
    if (unlikely(new_size > old_size)) {
        new_size1 = old_size + old_size / 2;
        if (new_size1 > new_size) {
            new_size = new_size1;
            /* ensure that the property array has a size which is a
             * multiple of 3 */
            if (prop_base != 0) {
                int align = (new_size - prop_base) % 3;
                if (align != 0)
                    new_size += 3 - align;
            }
        }
        new_size = max_int(new_size, old_size + old_size / 2);
        JS_PUSH_VALUE(ctx, val);
        new_slots = js_alloc_value_array(ctx, old_size, new_size);
        JS_POP_VALUE(ctx, val);
        if (!new_slots)
            return JS_EXCEPTION;
        if (old_size > 0) {
            slots = JS_VALUE_TO_PTR(val);
            memcpy(new_slots->arr, slots->arr, old_size * sizeof(JSValue));
        }
        val = JS_VALUE_FROM_PTR(new_slots);
    }
    return val;
}

JSValue js_resize_value_array(JSContext *ctx, JSValue val, int new_size)
{
    return js_resize_value_array2(ctx, val, new_size, 0);
}

/* no allocation is done */
void js_shrink_value_array(JSContext *ctx, JSValue *pval, int new_size)
{
    JSValueArray *arr;
    if (*pval == JS_NULL)
        return;
    arr = JS_VALUE_TO_PTR(*pval);
    assert(new_size <= arr->size);
    if (new_size == 0) {
        js_free(ctx, arr);
        *pval = JS_NULL;
    } else {
        arr = js_shrink(ctx, arr, sizeof(JSValueArray) + new_size * sizeof(JSValue));
        arr->size = new_size;
    }
}

JSByteArray *js_alloc_byte_array(JSContext *ctx, int size)
{
    JSByteArray *arr;
    
    if (size > JS_BYTE_ARRAY_SIZE_MAX) {
        JS_ThrowOutOfMemory(ctx);
        return NULL;
    }
    arr = js_malloc(ctx, sizeof(JSByteArray) + size, JS_MTAG_BYTE_ARRAY);
    if (!arr)
        return NULL;
    arr->size = size;
    return arr;
}

JSValue js_resize_byte_array(JSContext *ctx, JSValue val, int new_size)
{
    JSByteArray *arr, *new_arr;
    int old_size;
    JSGCRef val_ref;
    
    if (val == JS_NULL) {
        arr = NULL;
        old_size = 0;
    } else {
        arr = JS_VALUE_TO_PTR(val);
        old_size = arr->size;
    }
    if (unlikely(new_size > old_size)) {
        new_size = max_int(new_size, old_size + old_size / 2);
        JS_PUSH_VALUE(ctx, val);
        new_arr = js_alloc_byte_array(ctx, new_size);
        JS_POP_VALUE(ctx, val);
        if (!new_arr)
            return JS_EXCEPTION;
        if (old_size > 0) {
            arr = JS_VALUE_TO_PTR(val);
            memcpy(new_arr->buf, arr->buf, old_size);
        }
        val = JS_VALUE_FROM_PTR(new_arr);
    }
    return val;
}

void js_shrink_byte_array(JSContext *ctx, JSValue *pval, int new_size)
{
    JSByteArray *arr;
    if (*pval == JS_NULL)
        return;
    arr = JS_VALUE_TO_PTR(*pval);
    assert(new_size <= arr->size);
    if (new_size == 0) {
        js_free(ctx, arr);
        *pval = JS_NULL;
    } else {
        arr = js_shrink(ctx, arr, sizeof(JSByteArray) + new_size);
        arr->size = new_size;
    }
}

/* extra_size is in bytes */
JSObject *JS_NewObjectProtoClass1(JSContext *ctx, JSValue proto, int class_id, int extra_size)
{
    JSObject *p;
    JSGCRef proto_ref;
    extra_size = (unsigned)(extra_size + JSW - 1) / JSW;
    JS_PUSH_VALUE(ctx, proto);
    p = js_malloc(ctx, offsetof(JSObject, u) + extra_size * JSW,  JS_MTAG_OBJECT);
    JS_POP_VALUE(ctx, proto);
    if (!p)
        return NULL;
    p->class_id = class_id;
    p->extra_size = extra_size;
    p->proto = proto;
    p->props = ctx->empty_props;
    return p;
}

JSValue JS_NewObjectProtoClass(JSContext *ctx, JSValue proto, int class_id, int extra_size)
{
    JSObject *p;
    p = JS_NewObjectProtoClass1(ctx, proto, class_id, extra_size);
    if (!p)
        return JS_EXCEPTION;
    else
        return JS_VALUE_FROM_PTR(p);
}

JSValue JS_NewObjectClass(JSContext *ctx, int class_id, int extra_size)
{
    return JS_NewObjectProtoClass(ctx, ctx->class_proto[class_id], class_id, extra_size);
}

JSValue JS_NewObjectClassUser(JSContext *ctx, int class_id)
{
    JSObject *p;
    assert(class_id >= JS_CLASS_USER);
    p = JS_NewObjectProtoClass1(ctx, ctx->class_proto[class_id], class_id,
                                sizeof(JSObjectUserData));
    if (!p)
        return JS_EXCEPTION;
    p->u.user.opaque = NULL;
    return JS_VALUE_FROM_PTR(p);
}

JSValue JS_NewObject(JSContext *ctx)
{
    return JS_NewObjectClass(ctx, JS_CLASS_OBJECT, 0);
}

/* same as JS_NewObject() but preallocate for 'n' properties */
JSValue JS_NewObjectPrealloc(JSContext *ctx, int n)
{
    JSValue obj;
    JSValueArray *arr;
    JSObject *p;
    JSGCRef obj_ref;
    
    obj = JS_NewObjectClass(ctx, JS_CLASS_OBJECT, 0);
    if (JS_IsException(obj) || n <= 0)
        return obj;
    JS_PUSH_VALUE(ctx, obj);
    arr = js_alloc_props(ctx, n);
    JS_POP_VALUE(ctx, obj);
    if (!arr)
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(obj);
    p->props = JS_VALUE_FROM_PTR(arr);
    return obj;
}

JSValue JS_NewArray(JSContext *ctx, int initial_len)
{
    JSObject *p;
    JSValue val;
    JSGCRef val_ref;
    
    val = JS_NewObjectClass(ctx, JS_CLASS_ARRAY, sizeof(JSArrayData));
    if (JS_IsException(val))
        return val;
    p = JS_VALUE_TO_PTR(val);
    p->u.array.tab = JS_NULL;
    p->u.array.len = 0;
    if (initial_len > 0) {
        JSValueArray *arr;
        JS_PUSH_VALUE(ctx, val);
        arr = js_alloc_value_array(ctx, 0, initial_len);
        JS_POP_VALUE(ctx, val);
        if (!arr)
            return JS_EXCEPTION;
        p = JS_VALUE_TO_PTR(val);
        p->u.array.tab = JS_VALUE_FROM_PTR(arr);
        p->u.array.len = initial_len;
    }
    return val;
}


inline JSProperty *find_own_property(JSContext *ctx, JSObject *p, JSValue prop)
{
    return find_own_property_inlined(ctx, p, prop);
}

JSValue get_special_prop(JSContext *ctx, JSValue val)
{
    int idx;
    /* 'prototype' or 'constructor' property in ROM */
    idx = JS_VALUE_GET_INT(val);
    if (idx >= 0)
        return ctx->class_proto[idx];
    else
        return ctx->class_obj[-idx - 1];
}

/* return the value or:
   - exception 
   - tail call : returned in case of getter and handle_getset =
   true. The function is put on the stack
*/
JSValue JS_GetPropertyInternal(JSContext *ctx, JSValue obj, JSValue prop, BOOL allow_tail_call)
{
    JSObject *p;
    JSValue proto;
    JSProperty *pr;

    if (unlikely(!JS_IsPtr(obj))) {
        if (JS_IsIntOrShortFloat(obj)) {
            p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_NUMBER]);
        } else {
            switch(JS_VALUE_GET_SPECIAL_TAG(obj)) {
            case JS_TAG_BOOL:
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_BOOLEAN]);
                break;
            case JS_TAG_SHORT_FUNC:
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_CLOSURE]);
                break;
            case JS_TAG_STRING_CHAR:
                goto string_proto;
            case JS_TAG_NULL:
                return JS_ThrowTypeError(ctx, "cannot read property '%"JSValue_PRI"' of null", prop);
            case JS_TAG_UNDEFINED:
                return JS_ThrowTypeError(ctx, "cannot read property '%"JSValue_PRI"' of undefined", prop);
            default:
                goto no_prop;
            }
        }
    } else {
        p = JS_VALUE_TO_PTR(obj);
    }
    if (unlikely(p->mtag != JS_MTAG_OBJECT)) {
        switch(p->mtag) {
        case JS_MTAG_FLOAT64:
            p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_NUMBER]);
            break;
        case JS_MTAG_STRING:
        string_proto:
            {
                if (JS_IsInt(prop)) {
                    JSValue ret;
                    ret = js_string_charAt(ctx, &obj, 1, &prop, magic_internalAt);
                    if (!JS_IsUndefined(ret))
                        return ret;
                }
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_STRING]);
            }
            break;
        default:
        no_prop:
            return JS_ThrowTypeError(ctx, "cannot read property '%"JSValue_PRI"' of value", prop);
        }
    }

    for(;;) {
        if (p->class_id == JS_CLASS_ARRAY) {
            if (JS_IsInt(prop)) {
                uint32_t idx = JS_VALUE_GET_INT(prop);
                if (idx < p->u.array.len) {
                    JSValueArray *arr = JS_VALUE_TO_PTR(p->u.array.tab);
                    return arr->arr[idx];
                }
            } else if (JS_IsNumericProperty(ctx, prop)) {
                return JS_UNDEFINED;
            }
        } else if (p->class_id >= JS_CLASS_UINT8C_ARRAY &&
                   p->class_id <= JS_CLASS_FLOAT64_ARRAY) {
            if (JS_IsInt(prop)) {
                uint32_t idx = JS_VALUE_GET_INT(prop);
                JSObject *pbuffer;
                JSByteArray *arr;
                if (idx < p->u.typed_array.len) {
                    idx += p->u.typed_array.offset;
                    pbuffer = JS_VALUE_TO_PTR(p->u.typed_array.buffer);
                    arr = JS_VALUE_TO_PTR(pbuffer->u.array_buffer.byte_buffer);
                    switch(p->class_id) {
                    default:
                    case JS_CLASS_UINT8C_ARRAY:
                    case JS_CLASS_UINT8_ARRAY:
                        return JS_NewShortInt(*((uint8_t *)arr->buf + idx));
                    case JS_CLASS_INT8_ARRAY:
                        return JS_NewShortInt(*((int8_t *)arr->buf + idx));
                    case JS_CLASS_INT16_ARRAY:
                        return JS_NewShortInt(*((int16_t *)arr->buf + idx));
                    case JS_CLASS_UINT16_ARRAY:
                        return JS_NewShortInt(*((uint16_t *)arr->buf + idx));
                    case JS_CLASS_INT32_ARRAY:
                        return JS_NewInt32(ctx, *((int32_t *)arr->buf + idx));
                    case JS_CLASS_UINT32_ARRAY:
                        return JS_NewUint32(ctx, *((uint32_t *)arr->buf + idx));
                    case JS_CLASS_FLOAT32_ARRAY:
                        return JS_NewFloat64(ctx, *((float *)arr->buf + idx));
                    case JS_CLASS_FLOAT64_ARRAY:
                        return JS_NewFloat64(ctx, *((double *)arr->buf + idx));
                    }
                }
            } else if (JS_IsNumericProperty(ctx, prop)) {
                return JS_UNDEFINED;
            }
        }

        pr = find_own_property(ctx, p, prop);
        if (pr) {
            if (likely(pr->prop_type == JS_PROP_NORMAL)) {
                return pr->value;
            } else if (pr->prop_type == JS_PROP_VARREF) {
                JSVarRef *pv = JS_VALUE_TO_PTR(pr->value);
                /* always detached */
                return pv->u.value;
            } else if (pr->prop_type == JS_PROP_SPECIAL) {
                return get_special_prop(ctx, pr->value);
            } else {
                JSValueArray *arr = JS_VALUE_TO_PTR(pr->value);
                JSValue getter = arr->arr[0];
                if (getter == JS_UNDEFINED)
                    return JS_UNDEFINED;
                if (allow_tail_call) {
                    /* It is assumed 'this_obj' is on the stack and
                       that the stack has some slack to add one element. */
                    ctx->sp[-1] = ctx->sp[0];
                    ctx->sp[0] = getter;
                    ctx->sp--;
                    return JS_NewTailCall(0);
                } else {
                    JSGCRef getter_ref, obj_ref;
                    int err;
                    JS_PUSH_VALUE(ctx, getter);
                    JS_PUSH_VALUE(ctx, obj);
                    err = JS_StackCheck(ctx, 2);
                    JS_POP_VALUE(ctx, obj);
                    JS_POP_VALUE(ctx, getter);
                    if (err)
                        return JS_EXCEPTION;
                    JS_PushArg(ctx, getter);
                    JS_PushArg(ctx, obj);
                    return JS_Call(ctx, 0);
                }
            }
        }
        /* look in the prototype */
        proto = p->proto;
        if (proto == JS_NULL)
            break;
        p = JS_VALUE_TO_PTR(proto);
    }
    return JS_UNDEFINED;
}

JSValue JS_GetProperty(JSContext *ctx, JSValue obj, JSValue prop)
{
    return JS_GetPropertyInternal(ctx, obj, prop, FALSE);
}

JSValue JS_GetPropertyStr(JSContext *ctx, JSValue this_obj, const char *str)
{
    JSValue prop;
    JSGCRef this_obj_ref;
    
    JS_PUSH_VALUE(ctx, this_obj);
    prop = JS_NewString(ctx, str);
    if (!JS_IsException(prop)) {
        prop = JS_ToPropertyKey(ctx, prop);
    }
    JS_POP_VALUE(ctx, this_obj);
    if (JS_IsException(prop))
        return prop;
    return JS_GetProperty(ctx, this_obj, prop);
}

JSValue JS_GetPropertyUint32(JSContext *ctx, JSValue obj, uint32_t idx)
{
    if (idx > JS_SHORTINT_MAX)
        return JS_ThrowRangeError(ctx, "invalid array index");
    return JS_GetProperty(ctx, obj, JS_NewInt32(ctx, idx));
}

BOOL JS_HasProperty(JSContext *ctx, JSValue obj, JSValue prop)
{
    JSObject *p;
    JSProperty *pr;
    
    if (!JS_IsPtr(obj))
        return FALSE;
    p = JS_VALUE_TO_PTR(obj);
    if (p->mtag != JS_MTAG_OBJECT)
        return FALSE;
    for(;;) {
        pr = find_own_property(ctx, p, prop);
        if (pr)
            return TRUE;
        obj = p->proto;
        if (obj == JS_NULL)
            break;
        p = JS_VALUE_TO_PTR(obj);
    }
    return FALSE;
}

int get_prop_hash_size_log2(int prop_count)
{
    /* XXX: adjust ? */
    if (prop_count <= 1)
        return 0;
    else
        return (32 - clz32(prop_count - 1)) - 1;
}

/* allocate 'n' properties, assuming n >= 1 */
JSValueArray *js_alloc_props(JSContext *ctx, int n)
{
    int hash_size_log2, hash_mask, size, i, first_free;
    JSValueArray *arr;
    JSProperty *pr;
    
    hash_size_log2 = get_prop_hash_size_log2(n);
    hash_mask = (1 << hash_size_log2) - 1;
    first_free = 2 + hash_mask + 1;
    size = first_free + 3 * n;
    arr = js_alloc_value_array(ctx, 0, size);
    if (!arr)
        return NULL;
    arr->arr[0] = JS_NewShortInt(0); /* no property is allocated yet */
    arr->arr[1] = JS_NewShortInt(hash_mask);
    for(i = 0; i <= hash_mask; i++)
        arr->arr[2 + i] = 0;
    pr = NULL; /* avoid warning */
    for(i = 0; i < n; i++) {
        pr = (JSProperty *)&arr->arr[2 + hash_mask + 1 + 3 * i];
        pr->key = JS_UNINITIALIZED;
    }
    /* last property */
    pr->hash_next = first_free << 1;
    return arr;
}
                          
void js_rehash_props(JSContext *ctx, JSObject *p, BOOL gc_rehash)
{
    JSValueArray *arr;
    int prop_count, hash_mask, h, idx, i, j;
    JSProperty *pr;

    arr = JS_VALUE_TO_PTR(p->props);
    if (JS_IS_ROM_PTR(ctx, arr))
        return;
    hash_mask = JS_VALUE_GET_INT(arr->arr[1]);
    if (hash_mask == 0 && gc_rehash)
        return; /* no need to rehash if single hash entry */
    prop_count = JS_VALUE_GET_INT(arr->arr[0]);
    for(i = 0; i <= hash_mask; i++) {
        arr->arr[2 + i] = JS_NewShortInt(0);
    }
    for(i = 0, j = 0; j < prop_count; i++) {
        idx = 2 + (hash_mask + 1) + 3 * i;
        pr = (JSProperty *)&arr->arr[idx];
        if (pr->key != JS_UNINITIALIZED) {
            h = hash_prop(pr->key) & hash_mask;
            pr->hash_next = arr->arr[2 + h];
            arr->arr[2 + h] = JS_NewShortInt(idx);
            j++;
        }
    }
}

/* Compact the properties. No memory allocation is done */
void js_compact_props(JSContext *ctx, JSObject *p)
{
   JSValueArray *arr;
   int prop_count, hash_mask, i, j, hash_size_log2;
   int new_size, new_hash_mask;
   JSProperty *pr, *pr1;
   
   arr = JS_VALUE_TO_PTR(p->props);
   prop_count = JS_VALUE_GET_INT(arr->arr[0]);

   /* no property */
   if (prop_count == 0) {
       if (p->props != ctx->empty_props) {
           //js_free(ctx, p->props);
           p->props = ctx->empty_props;
       }
       return;
   }

   hash_mask = JS_VALUE_GET_INT(arr->arr[1]);
   hash_size_log2 = get_prop_hash_size_log2(prop_count);
   new_hash_mask = min_int(hash_mask, (1 << hash_size_log2) - 1);
   new_size = 2 + new_hash_mask + 1 + 3 * prop_count;
   if (new_size >= arr->size)
       return; /* nothing to do */
   //   printf("compact_props: new_size=%d size=%d hash=%d\n", new_size, arr->size, new_hash_mask);
   
   arr->arr[1] = JS_NewShortInt(new_hash_mask);

   /* move the properties, skipping the deleted ones */
   for(i = 0, j = 0; j < prop_count; i++) {
        pr = (JSProperty *)&arr->arr[2 + (hash_mask + 1) + 3 * i];
        if (pr->key != JS_UNINITIALIZED) {
            pr1 = (JSProperty *)&arr->arr[2 + (new_hash_mask + 1) + 3 * j];
            *pr1 = *pr;
            j++;
        }
   }
   
   js_shrink_value_array(ctx, &p->props, new_size);

   js_rehash_props(ctx, p, FALSE);
}

/* if the existing properties are in ROM, copy them to RAM. Return non zero if error */
int js_update_props(JSContext *ctx, JSValue obj)
{
    JSObject *p;
    JSValueArray *arr, *arr1;
    JSGCRef obj_ref;
    int i, idx, prop_count, hash_mask;
    JSProperty *pr;
    
    p = JS_VALUE_TO_PTR(obj);
    arr = JS_VALUE_TO_PTR(p->props);
    if (!JS_IS_ROM_PTR(ctx, arr))
        return 0;
    JS_PUSH_VALUE(ctx, obj);
    arr1 = js_alloc_value_array(ctx, 0, arr->size);
    JS_POP_VALUE(ctx, obj);
    if (!arr1)
        return -1;
    /* no rehashing is needed because all the atoms are in ROM */
    memcpy(arr1->arr, arr->arr, arr->size * sizeof(JSValue));
    prop_count = JS_VALUE_GET_INT(arr1->arr[0]);
    hash_mask = JS_VALUE_GET_INT(arr1->arr[1]);
    /* no deleted properties in ROM */
    assert(arr1->size == 2 + (hash_mask + 1) + 3 * prop_count);
    /* convert JS_PROP_SPECIAL properties ("prototype" and "constructor") */
    for(i = 0; i < prop_count; i++) {
        idx = 2 + (hash_mask + 1) + 3 * i;
        pr = (JSProperty *)&arr1->arr[idx];
        if (pr->prop_type == JS_PROP_SPECIAL) {
            pr->value = get_special_prop(ctx, pr->value);
            pr->prop_type = JS_PROP_NORMAL;
        }
    }
    
    p = JS_VALUE_TO_PTR(obj);
    p->props = JS_VALUE_FROM_PTR(arr1);
    return 0;
}

/* compute 'first_free' in a property list */
int get_first_free(JSValueArray *arr)
{
    JSProperty *pr1;
    int first_free;
    
    pr1 = (JSProperty *)&arr->arr[arr->size - 3];
    if (pr1->key == JS_UNINITIALIZED)
        first_free = pr1->hash_next >> 1;
    else
        first_free = arr->size;
    return first_free;
}

/* It is assumed that the property does not already exists. */
JSProperty *js_create_property(JSContext *ctx, JSValue obj, JSValue prop)
{
    JSObject *p;
    JSValueArray *arr;
    int prop_count, hash_mask, new_size, h, first_free, new_hash_mask;
    JSProperty *pr, *pr1;
    JSValue new_props;
    JSGCRef obj_ref, prop_ref;

    p = JS_VALUE_TO_PTR(obj);
    arr = JS_VALUE_TO_PTR(p->props);

    //    JS_DumpValue(ctx, "create", prop);
    prop_count = JS_VALUE_GET_INT(arr->arr[0]);
    hash_mask = JS_VALUE_GET_INT(arr->arr[1]);
    /* extend the array if no space left (this single test is valid
       even if the property list is empty) */
    pr1 = (JSProperty *)&arr->arr[arr->size - 3];
    if (pr1->key != JS_UNINITIALIZED) {
        if (p->props == ctx->empty_props) {
            /* XXX: remove and move empty_props to ROM */
            JS_PUSH_VALUE(ctx, obj);
            JS_PUSH_VALUE(ctx, prop);
            arr = js_alloc_props(ctx, 1);
            JS_POP_VALUE(ctx, prop);
            JS_POP_VALUE(ctx, obj);
            if (!arr)
                return NULL;
            p = JS_VALUE_TO_PTR(obj);
            p->props = JS_VALUE_FROM_PTR(arr);
            first_free = 3;
        } else {
            first_free = arr->size;
            new_size = first_free + 3;
            new_hash_mask = hash_mask;
            if ((prop_count + 1) > 2 * (hash_mask + 1)) {
                /* resize the hash table if too many properties */
                new_hash_mask = 2 * (hash_mask + 1) - 1;
                new_size += new_hash_mask - hash_mask;
            }
            JS_PUSH_VALUE(ctx, obj);
            JS_PUSH_VALUE(ctx, prop);
            //            printf("resize_props: new_size=%d hash=%d %d\n", new_size, new_hash_mask, hash_mask);
            new_props = js_resize_value_array2(ctx, p->props, new_size, 2 + new_hash_mask + 1);
            JS_POP_VALUE(ctx, prop);
            JS_POP_VALUE(ctx, obj);
            if (JS_IsException(new_props))
                return NULL;
            p = JS_VALUE_TO_PTR(obj);
            p->props = new_props;
            arr = JS_VALUE_TO_PTR(p->props);
            if (new_hash_mask != hash_mask) {
                /* rebuild the hash table */
                memmove(&arr->arr[2 + (new_hash_mask + 1)],
                        &arr->arr[2 + (hash_mask + 1)],
                        (first_free - (2 + hash_mask + 1)) * sizeof(JSValue));
                first_free += new_hash_mask - hash_mask;
                hash_mask = new_hash_mask;
                arr->arr[1] = JS_NewShortInt(hash_mask);
                js_rehash_props(ctx, p, FALSE);
            }
        }
        /* ensure the last element is marked as uninitialized to store 'first_free' */
        pr1 = (JSProperty *)&arr->arr[arr->size - 3];
        pr1->key = JS_UNINITIALIZED;
    } else {
        first_free = pr1->hash_next >> 1;
    }

    pr = (JSProperty *)&arr->arr[first_free];
    pr->key = prop;
    pr->value = JS_UNDEFINED;
    pr->prop_type = JS_PROP_NORMAL;
    h = hash_prop(prop) & hash_mask;
    pr->hash_next = arr->arr[2 + h];
    arr->arr[2 + h] = JS_NewShortInt(first_free);
    arr->arr[0] = JS_NewShortInt(prop_count + 1);
    /* update first_free */
    first_free += 3;
    if (first_free < arr->size) {
        pr1 = (JSProperty *)&arr->arr[arr->size - 3];
        pr1->hash_next = first_free << 1;
    }

    return pr;
}

/* don't do property lookup if not present */
#define JS_DEF_PROP_LOOKUP  (1 << 0)
/* return the raw property value */
#define JS_DEF_PROP_RET_VAL (1 << 1)
#define JS_DEF_PROP_HAS_VALUE (1 << 2)
#define JS_DEF_PROP_HAS_GET   (1 << 3)
#define JS_DEF_PROP_HAS_SET   (1 << 4)

/* XXX: handle arrays and typed arrays */
JSValue JS_DefinePropertyInternal(JSContext *ctx, JSValue obj, JSValue prop, JSValue val, JSValue setter, int flags)
{
    JSProperty *pr;
    JSValueArray *arr;
    JSGCRef obj_ref, prop_ref, val_ref, setter_ref;
    int ret, prop_type;
    
    /* move to RAM if needed */
    JS_PUSH_VALUE(ctx, obj);
    JS_PUSH_VALUE(ctx, prop);
    JS_PUSH_VALUE(ctx, val);
    JS_PUSH_VALUE(ctx, setter);
    ret = js_update_props(ctx, obj);
    JS_POP_VALUE(ctx, setter);
    JS_POP_VALUE(ctx, val);
    JS_POP_VALUE(ctx, prop);
    JS_POP_VALUE(ctx, obj);
    if (ret)
        return JS_EXCEPTION;
    
    if (flags & JS_DEF_PROP_LOOKUP) {
        pr = find_own_property(ctx, JS_VALUE_TO_PTR(obj), prop);
        if (pr) {
            if (flags & JS_DEF_PROP_HAS_VALUE) {
                if (pr->prop_type == JS_PROP_NORMAL) {
                    pr->value = val;
                } else if (pr->prop_type == JS_PROP_VARREF) {
                    JSVarRef *pv = JS_VALUE_TO_PTR(pr->value);
                    pv->u.value = val;
                } else {
                    goto error_modify;
                }
            } else if (flags & (JS_DEF_PROP_HAS_GET | JS_DEF_PROP_HAS_SET)) {
                if (pr->prop_type != JS_PROP_GETSET) {
                error_modify:
                    return JS_ThrowTypeError(ctx, "cannot modify getter/setter/value kind");
                }
                arr = JS_VALUE_TO_PTR(pr->value);
                if (unlikely(JS_IS_ROM_PTR(ctx, arr))) {
                    /* move to RAM */
                    JSValueArray *arr2;
                    JS_PUSH_VALUE(ctx, obj);
                    JS_PUSH_VALUE(ctx, prop);
                    JS_PUSH_VALUE(ctx, val);
                    JS_PUSH_VALUE(ctx, setter);
                    arr2 = js_alloc_value_array(ctx, 0, 2);
                    JS_POP_VALUE(ctx, setter);
                    JS_POP_VALUE(ctx, val);
                    JS_POP_VALUE(ctx, prop);
                    JS_POP_VALUE(ctx, obj);
                    if (!arr2)
                        return JS_EXCEPTION;
                    pr = find_own_property(ctx, JS_VALUE_TO_PTR(obj), prop);
                    arr = JS_VALUE_TO_PTR(pr->value);
                    arr2->arr[0] = arr->arr[0];
                    arr2->arr[1] = arr->arr[1];
                    pr->value = JS_VALUE_FROM_PTR(arr2);
                    arr = arr2;
                }
                if (flags & JS_DEF_PROP_HAS_GET)
                    arr->arr[0] = val;
                if (flags & JS_DEF_PROP_HAS_SET)
                    arr->arr[1] = setter;
            }
            goto done;
        }
    }

    if (flags & (JS_DEF_PROP_HAS_GET | JS_DEF_PROP_HAS_SET)) {
        prop_type = JS_PROP_GETSET;
        JS_PUSH_VALUE(ctx, obj);
        JS_PUSH_VALUE(ctx, prop);
        JS_PUSH_VALUE(ctx, val);
        JS_PUSH_VALUE(ctx, setter);
        arr = js_alloc_value_array(ctx, 0, 2);
        JS_POP_VALUE(ctx, setter);
        JS_POP_VALUE(ctx, val);
        JS_POP_VALUE(ctx, prop);
        JS_POP_VALUE(ctx, obj);
        if (!arr)
            return JS_EXCEPTION;
        arr->arr[0] = val;
        arr->arr[1] = setter;
        val = JS_VALUE_FROM_PTR(arr);
    } else if (obj == ctx->global_obj) {
        JSVarRef *pv;
        
        prop_type = JS_PROP_VARREF;
        JS_PUSH_VALUE(ctx, obj);
        JS_PUSH_VALUE(ctx, prop);
        JS_PUSH_VALUE(ctx, val);
        pv = js_malloc(ctx, sizeof(JSVarRef) - sizeof(JSValue), JS_MTAG_VARREF);
        JS_POP_VALUE(ctx, val);
        JS_POP_VALUE(ctx, prop);
        JS_POP_VALUE(ctx, obj);
        if (!pv)
            return JS_EXCEPTION;
        pv->is_detached = TRUE;
        pv->u.value = val;
        val = JS_VALUE_FROM_PTR(pv);
    } else {
        prop_type = JS_PROP_NORMAL;
    }
    JS_PUSH_VALUE(ctx, val);
    pr = js_create_property(ctx, obj, prop);
    JS_POP_VALUE(ctx, val);
    if (!pr)
        return JS_EXCEPTION;
    pr->prop_type = prop_type;
    pr->value = val;
 done:
    if (flags & JS_DEF_PROP_RET_VAL) {
        return pr->value;
    } else {
        return JS_UNDEFINED;
    }
}

JSValue JS_DefinePropertyValue(JSContext *ctx, JSValue obj, JSValue prop, JSValue val)
{
    return JS_DefinePropertyInternal(ctx, obj, prop, val, JS_NULL,
                                     JS_DEF_PROP_LOOKUP | JS_DEF_PROP_HAS_VALUE);
}

JSValue JS_DefinePropertyGetSet(JSContext *ctx, JSValue obj, JSValue prop, JSValue getter, JSValue setter, int flags)
{
    return JS_DefinePropertyInternal(ctx, obj, prop, getter, setter,
                                     JS_DEF_PROP_LOOKUP | flags);
}

/* return a JSVarRef or an exception. */
JSValue add_global_var(JSContext *ctx, JSValue prop, BOOL define_flag)
{
    JSObject *p;
    JSProperty *pr;
    
    p = JS_VALUE_TO_PTR(ctx->global_obj);
    pr = find_own_property(ctx, p, prop);
    if (pr) {
        if (pr->prop_type != JS_PROP_VARREF)
            return JS_ThrowReferenceError(ctx, "global variable '%"JSValue_PRI"' must be a reference", prop);
        if (define_flag) {
            JSVarRef *pv = JS_VALUE_TO_PTR(pr->value);
            /* define the variable if needed */
            if (pv->u.value == JS_UNINITIALIZED)
                pv->u.value = JS_UNDEFINED;
        }
        return pr->value;
    }
    return JS_DefinePropertyInternal(ctx, ctx->global_obj, prop,
                                     define_flag ? JS_UNDEFINED : JS_UNINITIALIZED, JS_NULL,
                                     JS_DEF_PROP_RET_VAL | JS_DEF_PROP_HAS_VALUE);
}

/* return JS_UNDEFINED in the normal case. Otherwise:
   - exception 
   - tail call : returned in case of getter and handle_getset =
   true. The function is put on the stack
*/
JSValue JS_SetPropertyInternal(JSContext *ctx, JSValue this_obj, JSValue prop, JSValue val, BOOL allow_tail_call)
{
    JSValue proto;
    JSObject *p;
    JSProperty *pr;
    BOOL is_obj;
    
    if (unlikely(!JS_IsPtr(this_obj))) {
        is_obj = FALSE;
        if (JS_IsIntOrShortFloat(this_obj)) {
            p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_NUMBER]);
            goto prototype_lookup;
        } else {
            switch(JS_VALUE_GET_SPECIAL_TAG(this_obj)) {
            case JS_TAG_BOOL:
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_BOOLEAN]);
                goto prototype_lookup;
            case JS_TAG_SHORT_FUNC:
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_CLOSURE]);
                goto prototype_lookup;
            case JS_TAG_STRING_CHAR:
                p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_STRING]);
                goto prototype_lookup;
            case JS_TAG_NULL:
                return JS_ThrowTypeError(ctx, "cannot set property '%"JSValue_PRI"' of null", prop);
            case JS_TAG_UNDEFINED:
                return JS_ThrowTypeError(ctx, "cannot set property '%"JSValue_PRI"' of undefined", prop);
            default:
                goto no_prop;
            }
        }
    } else {
        is_obj = TRUE;
        p = JS_VALUE_TO_PTR(this_obj);
    }
    if (unlikely(p->mtag != JS_MTAG_OBJECT)) {
        is_obj = FALSE;
        switch(p->mtag) {
        case JS_MTAG_FLOAT64:
            p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_NUMBER]);
            goto prototype_lookup;
        case JS_MTAG_STRING:
            p = JS_VALUE_TO_PTR(ctx->class_proto[JS_CLASS_STRING]);
            goto prototype_lookup;
        default:
        no_prop:
            return JS_ThrowTypeError(ctx, "cannot set property '%"JSValue_PRI"' of value", prop);
        }
    }

    /* search if the property is already present */
    if (p->class_id == JS_CLASS_ARRAY) {
        if (JS_IsInt(prop)) {
            JSValueArray *arr;
            uint32_t idx = JS_VALUE_GET_INT(prop);
            /* not standard: we refuse to add properties to object
               except at the last position */
            if (idx < p->u.array.len) {
                arr = JS_VALUE_TO_PTR(p->u.array.tab);
                arr->arr[idx] = val;
                return JS_UNDEFINED;
            } else if (idx == p->u.array.len) {
                JSValue new_tab;
                JSGCRef this_obj_ref, val_ref;

                JS_PUSH_VALUE(ctx, this_obj);
                JS_PUSH_VALUE(ctx, val);
                new_tab = js_resize_value_array(ctx, p->u.array.tab, idx + 1);
                JS_POP_VALUE(ctx, val);
                JS_POP_VALUE(ctx, this_obj);
                if (JS_IsException(new_tab))
                    return JS_EXCEPTION;
                p = JS_VALUE_TO_PTR(this_obj);
                p->u.array.tab = new_tab;
                arr = JS_VALUE_TO_PTR(p->u.array.tab);
                arr->arr[idx] = val;
                p->u.array.len++;
                return JS_UNDEFINED;
            } else {
                goto invalid_array_subscript;
            }
        } else if (JS_IsNumericProperty(ctx, prop)) {
            goto invalid_array_subscript;
        }
    } else if (p->class_id >= JS_CLASS_UINT8C_ARRAY &&
               p->class_id <= JS_CLASS_FLOAT64_ARRAY) {
        if (JS_IsInt(prop)) {
            uint32_t idx = JS_VALUE_GET_INT(prop);
            int v, conv_ret;
            double d;
            JSObject *pbuffer;
            JSByteArray *arr;
            JSGCRef val_ref, this_obj_ref;

            JS_PUSH_VALUE(ctx, this_obj);
            JS_PUSH_VALUE(ctx, val);
            switch(p->class_id) {
            case JS_CLASS_UINT8C_ARRAY:
                conv_ret = JS_ToUint8Clamp(ctx, &v, val);
                break;
            case JS_CLASS_FLOAT32_ARRAY:
            case JS_CLASS_FLOAT64_ARRAY:
                conv_ret = JS_ToNumber(ctx, &d, val);
                break;
            default:
                conv_ret = JS_ToInt32(ctx, &v, val);
                break;
            }
            JS_POP_VALUE(ctx, val);
            JS_POP_VALUE(ctx, this_obj);
            if (conv_ret)
                return JS_EXCEPTION;
            
            p = JS_VALUE_TO_PTR(this_obj);
            if (idx >= p->u.typed_array.len)
                goto invalid_array_subscript;
            idx += p->u.typed_array.offset;
            pbuffer = JS_VALUE_TO_PTR(p->u.typed_array.buffer);
            arr = JS_VALUE_TO_PTR(pbuffer->u.array_buffer.byte_buffer);
            switch(p->class_id) {
            default:
            case JS_CLASS_UINT8C_ARRAY:
            case JS_CLASS_INT8_ARRAY:
            case JS_CLASS_UINT8_ARRAY:
                *((uint8_t *)arr->buf + idx) = v;
                break;
            case JS_CLASS_INT16_ARRAY:
            case JS_CLASS_UINT16_ARRAY:
                *((uint16_t *)arr->buf + idx) = v;
                break;
            case JS_CLASS_INT32_ARRAY:
            case JS_CLASS_UINT32_ARRAY:
                *((uint32_t *)arr->buf + idx) = v;
                break;
            case JS_CLASS_FLOAT32_ARRAY:
                *((float *)arr->buf + idx) = d;
                break;
            case JS_CLASS_FLOAT64_ARRAY:
                *((double *)arr->buf + idx) = d;
                break;
            }
            return JS_UNDEFINED;
        } else if (JS_IsNumericProperty(ctx, prop)) {
        invalid_array_subscript:
            return JS_ThrowTypeError(ctx, "invalid array subscript");
        }
    }

 redo:
    pr = find_own_property(ctx, p, prop);
    if (pr) {
        if (likely(pr->prop_type == JS_PROP_NORMAL)) {
            if (unlikely(JS_IS_ROM_PTR(ctx, pr)))
                goto convert_to_ram;
            pr->value = val;
            return JS_UNDEFINED;
        } else if (pr->prop_type == JS_PROP_VARREF) {
            JSVarRef *pv = JS_VALUE_TO_PTR(pr->value);
            /* always detached */
            pv->u.value = val;
            return JS_UNDEFINED;
        } else if (pr->prop_type == JS_PROP_SPECIAL) {
            JSGCRef val_ref, prop_ref, this_obj_ref;
            int err;
        convert_to_ram:
            JS_PUSH_VALUE(ctx, this_obj);
            JS_PUSH_VALUE(ctx, prop);
            JS_PUSH_VALUE(ctx, val);
            err = js_update_props(ctx, this_obj);
            JS_POP_VALUE(ctx, val);
            JS_POP_VALUE(ctx, prop);
            JS_POP_VALUE(ctx, this_obj);
            if (err)
                return JS_EXCEPTION;
            p = JS_VALUE_TO_PTR(this_obj);
            goto redo;
        } else {
            goto getset;
        }
    }

    /* search in the prototype chain (getter/setters) */
    for(;;) {
        proto = p->proto;
        if (proto == JS_NULL)
            break;
        p = JS_VALUE_TO_PTR(proto);
    prototype_lookup:
        pr = find_own_property(ctx, p, prop);
        if (pr) {
            if (unlikely(pr->prop_type == JS_PROP_GETSET)) {
                JSValueArray *arr;
                JSValue setter;
            getset:
                arr = JS_VALUE_TO_PTR(pr->value);
                setter = arr->arr[1];
                if (allow_tail_call) {
                    /* It is assumed "this_obj" already is on the stack
                       and that the stack has some slack to add one
                       element. */
                    ctx->sp[-2] = ctx->sp[0];
                    ctx->sp[-1] = setter;
                    ctx->sp[0] = val;
                    ctx->sp -= 2;
                    return JS_NewTailCall(1 | FRAME_CF_POP_RET);
                } else {
                    JSGCRef val_ref, setter_ref, this_obj_ref;
                    int err;
                    JS_PUSH_VALUE(ctx, val);
                    JS_PUSH_VALUE(ctx, setter);
                    JS_PUSH_VALUE(ctx, this_obj);
                    err = JS_StackCheck(ctx, 3);
                    JS_POP_VALUE(ctx, this_obj);
                    JS_POP_VALUE(ctx, setter);
                    JS_POP_VALUE(ctx, val);
                    if (err)
                        return JS_EXCEPTION;
                    JS_PushArg(ctx, val);
                    JS_PushArg(ctx, setter);
                    JS_PushArg(ctx, this_obj);
                    return JS_Call(ctx, 1);
                }
            } else {
                /* stop prototype chain lookup */
                break;
            }
        }
    }
    
    /* add the property in the object */
    if (!is_obj)
        return JS_ThrowTypeErrorNotAnObject(ctx);
    return JS_DefinePropertyInternal(ctx, this_obj, prop, val, JS_UNDEFINED,
                                     JS_DEF_PROP_HAS_VALUE);
}

JSValue JS_SetPropertyStr(JSContext *ctx, JSValue this_obj,
                          const char *str, JSValue val)
{
    JSValue prop;
    JSGCRef this_obj_ref, val_ref;
    
    JS_PUSH_VALUE(ctx, this_obj);
    JS_PUSH_VALUE(ctx, val);
    prop = JS_NewString(ctx, str);
    if (!JS_IsException(prop)) {
        prop = JS_ToPropertyKey(ctx, prop);
    }
    JS_POP_VALUE(ctx, val);
    JS_POP_VALUE(ctx, this_obj);
    if (JS_IsException(prop))
        return prop;
    return JS_SetPropertyInternal(ctx, this_obj, prop, val, FALSE);
}

JSValue JS_SetPropertyUint32(JSContext *ctx, JSValue this_obj,
                             uint32_t idx, JSValue val)
{
    if (idx > JS_SHORTINT_MAX)
        return JS_ThrowRangeError(ctx, "invalid array index");
    return JS_SetPropertyInternal(ctx, this_obj, JS_NewShortInt(idx), val, FALSE);
}

/* return JS_FALSE, JS_TRUE or JS_EXCEPTION. Return false only if the
   property is not configurable which is never the case here. */
JSValue JS_DeleteProperty(JSContext *ctx, JSValue this_obj, JSValue prop)
{
    JSObject *p;
    JSProperty *pr, *pr1;
    JSValueArray *arr;
    int h, idx, hash_mask, last_idx, prop_count, first_free;
    JSGCRef this_obj_ref;
    
    JS_PUSH_VALUE(ctx, this_obj);
    prop = JS_ToPropertyKey(ctx, prop);
    JS_POP_VALUE(ctx, this_obj);
    if (JS_IsException(prop))
        return prop;
    
    /* XXX: check return value */
    if (!JS_IsPtr(this_obj))
        return JS_TRUE;
    p = JS_VALUE_TO_PTR(this_obj);
    if (p->mtag != JS_MTAG_OBJECT)
        return JS_TRUE;

    arr = JS_VALUE_TO_PTR(p->props);
    hash_mask = JS_VALUE_GET_INT(arr->arr[1]);
    h = hash_prop(prop) & hash_mask;
    idx = JS_VALUE_GET_INT(arr->arr[2 + h]);
    last_idx = -1;
    while (idx != 0) {
        pr = (JSProperty *)(arr->arr + idx);
        if (pr->key == prop) {
            if (JS_IS_ROM_PTR(ctx, arr)) {
                JSGCRef this_obj_ref;
                int ret;
                JS_PUSH_VALUE(ctx, this_obj);
                ret = js_update_props(ctx, this_obj);
                JS_POP_VALUE(ctx, this_obj);
                if (ret)
                    return JS_EXCEPTION;
                p = JS_VALUE_TO_PTR(this_obj);
                arr = JS_VALUE_TO_PTR(p->props);
                pr = (JSProperty *)(arr->arr + idx);
            }
            /* found: remove it */
            if (last_idx >= 0) {
                JSProperty *lpr = (JSProperty *)(arr->arr + last_idx);
                lpr->hash_next = pr->hash_next;
            } else {
                arr->arr[2 + h] = pr->hash_next;
            }
            first_free = get_first_free(arr);

            prop_count = JS_VALUE_GET_INT(arr->arr[0]);
            arr->arr[0] = JS_NewShortInt(prop_count - 1);
            pr->prop_type = JS_PROP_NORMAL;
            pr->key = JS_UNINITIALIZED;
            pr->value = JS_UNDEFINED;

            /* update first_free if needed */
            while (first_free > 2 + hash_mask + 1) {
                pr1 = (JSProperty *)&arr->arr[first_free - 3];
                if (pr1->key != JS_UNINITIALIZED)
                    break;
                first_free -= 3;
            }

            /* update first_free */
            if (first_free < arr->size) {
                pr1 = (JSProperty *)&arr->arr[arr->size - 3];
                pr1->hash_next = first_free << 1;
            }

            /* compact the properties if needed */
            if ((2 + hash_mask + 1 + 3 * prop_count) < arr->size / 2)
                js_compact_props(ctx, p);
            return JS_TRUE;
        }
        last_idx = idx;
        idx = pr->hash_next >> 1;
    }
    /* not found */
    return JS_TRUE;
}

JSValue stdlib_init_class(JSContext *ctx, const JSROMClass *class_def)
{
    JSValue obj, proto, parent_class, parent_proto;
    JSGCRef parent_class_ref;
    JSObject *p;
    int ctor_idx = class_def->ctor_idx;

    if (ctor_idx >= 0) {
        int class_id = ctx->c_function_table[ctor_idx].magic;
        obj = ctx->class_obj[class_id];
        if (!JS_IsNull(obj))
            return obj; /* already defined */

       /* initialize the parent class if necessary */
        if (!JS_IsNull(class_def->parent_class)) {
            JSROMClass *parent_class_def = JS_VALUE_TO_PTR(class_def->parent_class);
            int parent_class_id;
            parent_class = stdlib_init_class(ctx, parent_class_def);
            parent_class_id = ctx->c_function_table[parent_class_def->ctor_idx].magic;
            parent_proto = ctx->class_proto[parent_class_id];
        } else {
            parent_class = JS_NULL;
            parent_proto = ctx->class_proto[JS_CLASS_OBJECT];
        }
        /* initialize the prototype before. It is already defined only
           for Object and Function */
        proto = ctx->class_proto[class_id];
        if (JS_IsNull(proto)) {
            JS_PUSH_VALUE(ctx, parent_class);
            proto = JS_NewObjectProtoClass(ctx, parent_proto, JS_CLASS_OBJECT, 0);
            JS_POP_VALUE(ctx, parent_class);
            ctx->class_proto[class_id] = proto;
        }
        p = JS_VALUE_TO_PTR(proto);
        if (!JS_IsNull(class_def->proto_props))
            p->props = class_def->proto_props;

        if (JS_IsNull(parent_class))
            parent_class = ctx->class_proto[JS_CLASS_CLOSURE];
        obj = js_new_c_function_proto(ctx, ctor_idx, parent_class, FALSE, JS_NULL);
        ctx->class_obj[class_id] = obj;
    } else {
        /* normal object */
        obj = JS_NewObject(ctx);
    }
    p = JS_VALUE_TO_PTR(obj);
    if (!JS_IsNull(class_def->props)) {
        /* set the properties from the ROM. They are copied to RAM
           when modified */
        p->props = class_def->props;
    } 
    return obj;
}

void stdlib_init(JSContext *ctx, const JSValueArray *arr)
{
    JSValue name, val;
    int i;

    for(i = 0; i < arr->size; i += 2) {
        name = arr->arr[i];
        val = arr->arr[i + 1];
        if (JS_IsObject(ctx, val)) {
            val = stdlib_init_class(ctx, JS_VALUE_TO_PTR(val));
        } else if (val == JS_NULL) {
            val = ctx->global_obj;
        }
        JS_DefinePropertyInternal(ctx, ctx->global_obj, name,
                                  val, JS_NULL,
                                  JS_DEF_PROP_HAS_VALUE);
    }
}

