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
/**********************************************************************/
/* runtime */

JSValue js_function_constructor(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    StringBuffer b_s, *b = &b_s;
    JSValue val;
    int i, n;
    
    argc &= ~FRAME_CF_CTOR;
    string_buffer_push(ctx, b, 0);
    string_buffer_puts(ctx, b, "(function anonymous(");
    n = argc - 1;
    for(i = 0; i < n; i++) {
        if (i != 0) {
            string_buffer_putc(ctx, b, ',');
        }
        if (string_buffer_concat(ctx, b, argv[i]))
            goto done;
    }
    string_buffer_puts(ctx, b, "\n) {\n");
    if (n >= 0) {
        if (string_buffer_concat(ctx, b, argv[n]))
            goto done;
    }
    string_buffer_puts(ctx, b, "\n})");
 done:
    val = string_buffer_pop(ctx, b);
    if (JS_IsException(val))
        return val;
    val = JS_Parse2(ctx, val, NULL, 0, "<input>", JS_EVAL_RETVAL);
    if (JS_IsException(val))
        return val;
    return JS_Run(ctx, val);
}

JSValue js_function_get_prototype(JSContext *ctx, JSValue *this_val,
                                  int argc, JSValue *argv)
{
    JSValue obj;
    JSGCRef obj_ref;
    
    if (!JS_IsPtr(*this_val)) {
        if (JS_VALUE_GET_SPECIAL_TAG(*this_val) != JS_TAG_SHORT_FUNC)
            goto fail;
        return JS_UNDEFINED;
    } else {
        JSObject *p = JS_VALUE_TO_PTR(*this_val);
        if (p->mtag != JS_MTAG_OBJECT)
            goto fail;
        if (p->class_id == JS_CLASS_CLOSURE) {
            obj = JS_NewObject(ctx);
            if (JS_IsException(obj))
                return obj;
        } else if (p->class_id == JS_CLASS_C_FUNCTION) {
            /* for C constructors, the prototype property is already present */
            return JS_UNDEFINED;
        } else {
        fail:
            return JS_ThrowTypeError(ctx, "not a function");
        }
        JS_PUSH_VALUE(ctx, obj);
        JS_DefinePropertyValue(ctx, obj, js_get_atom(ctx, JS_ATOM_constructor),
                               *this_val);
        JS_POP_VALUE(ctx, obj);
        JS_PUSH_VALUE(ctx, obj);
        JS_DefinePropertyValue(ctx, *this_val, js_get_atom(ctx, JS_ATOM_prototype),
                               obj);
        JS_POP_VALUE(ctx, obj);
    }
    return obj;
}

JSValue js_function_set_prototype(JSContext *ctx, JSValue *this_val,
                                  int argc, JSValue *argv)
{
    if (!JS_IsFunctionObject(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not a function");

    JS_DefinePropertyValue(ctx, *this_val, js_get_atom(ctx, JS_ATOM_prototype),
                           argv[0]);
    return JS_UNDEFINED;
}

JSValue js_function_get_length_name(JSContext *ctx, JSValue *this_val,
                                    int argc, JSValue *argv, int is_name)
{
    JSFunctionBytecode *b;
    JSValue ret = js_function_get_length_name1(ctx, this_val, is_name, &b);
    if (JS_IsNull(ret))
        return JS_ThrowTypeError(ctx, "not a function");
    return ret;
}

JSValue js_function_toString(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv)
{
    JSValue str, val;
    JSGCRef str_ref;

    str = js_function_get_length_name(ctx, this_val, 0, NULL, 1);
    if (JS_IsException(str))
        return str;
    JS_PUSH_VALUE(ctx, str);
    val = JS_NewString(ctx, "function ");
    JS_POP_VALUE(ctx, str);
    str = JS_ConcatString(ctx, val, str);
    JS_PUSH_VALUE(ctx, str);
    val = JS_NewString(ctx, "() {\n    [native code]\n}");
    JS_POP_VALUE(ctx, str);
    return JS_ConcatString(ctx, str, val);
}

JSValue js_function_call(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    int i;
    argc = max_int(argc, 1);
    if (JS_StackCheck(ctx, argc + 1))
        return JS_EXCEPTION;
    for(i = 0; i < argc - 1; i++)
        JS_PushArg(ctx, argv[argc - 1 - i]);
    JS_PushArg(ctx, *this_val);
    JS_PushArg(ctx, argv[0]);
    /* we avoid recursing on the C stack */
    return JS_NewTailCall(argc - 1);
}

JSValue js_function_apply(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    JSValueArray *arr;
    JSObject *p;
    int len, i;
    p = js_get_object_class(ctx, argv[1], JS_CLASS_ARRAY);
    if (!p)
        return JS_ThrowTypeError(ctx, "not an array");
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    len = p->u.array.len;
    if (len > JS_MAX_ARGC)
        return JS_ThrowTypeError(ctx, "too many call arguments");
    if (JS_StackCheck(ctx, len + 2))
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(argv[1]);
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    for(i = 0; i < len; i++)
        JS_PushArg(ctx, arr->arr[len - 1 - i]);
    JS_PushArg(ctx, *this_val);
    JS_PushArg(ctx, argv[0]);
    /* we avoid recursing on the C stack */
    return JS_NewTailCall(len);
}

JSValue js_function_bind(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    int arg_count;
    JSValueArray *arr;
    int i;
    
    arg_count = max_int(argc - 1, 0);
    arr = js_alloc_value_array(ctx, 0, 2 + arg_count);
    if (!arr)
        return JS_EXCEPTION;
    /* arr[0] = func, arr[1] = this */
    arr->arr[0] = *this_val;
    for(i = 0; i < arg_count + 1; i++)
        arr->arr[1 + i] = argv[i];
    return JS_NewCFunctionParams(ctx, JS_CFUNCTION_bound, JS_VALUE_FROM_PTR(arr));
}

/* XXX: handle constructor case */
JSValue js_function_bound(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv, JSValue params)
{
    JSValueArray *arr;
    JSGCRef params_ref;
    int i, err, size, argc2;
    
    arr = JS_VALUE_TO_PTR(params);
    size = arr->size;
    JS_PUSH_VALUE(ctx, params);
    err = JS_StackCheck(ctx, size + argc);
    JS_POP_VALUE(ctx, params);
    if (err)
        return JS_EXCEPTION;
    argc2 = size - 2 + argc;
    if (argc2 > JS_MAX_ARGC)
        return JS_ThrowTypeError(ctx, "too many call arguments");
    arr = JS_VALUE_TO_PTR(params);
    for(i = argc - 1; i >= 0; i--)
        JS_PushArg(ctx, argv[i]);
    for(i = size - 1; i >= 2; i--) {
        JS_PushArg(ctx, arr->arr[i]);
    }
    JS_PushArg(ctx, arr->arr[0]); /* func */
    JS_PushArg(ctx, arr->arr[1]); /* this_val */
    /* we avoid recursing on the C stack */
    return JS_NewTailCall(argc2);
}

/**********************************************************************/

JSValue js_number_constructor(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv)
{
    double d;
    if (argc & FRAME_CF_CTOR)
        return JS_ThrowTypeError(ctx, "number constructor not supported");
    if (argc == 0) {
        return JS_NewShortInt(0);
    } else {
        if (JS_ToNumber(ctx, &d, argv[0]))
            return JS_EXCEPTION;
        return JS_NewFloat64(ctx, d);
    }
}

int js_thisNumberValue(JSContext *ctx, double *pres, JSValue val)
{
    if (!JS_IsNumber(ctx, val)) {
        JS_ThrowTypeError(ctx, "not a number");
        return -1;
    }
    return JS_ToNumber(ctx, pres, val);
}

JSValue js_number_toString(JSContext *ctx, JSValue *this_val,
                           int argc, JSValue *argv)
{
    int radix, flags;
    double d;
    
    if (js_thisNumberValue(ctx, &d, *this_val))
        return JS_EXCEPTION;
    if (JS_IsUndefined(argv[0])) {
        radix = 10;
    } else {
        if (JS_ToInt32Sat(ctx, &radix, argv[0]))
            return JS_EXCEPTION;
        if (radix < 2 || radix > 36)
            return JS_ThrowRangeError(ctx, "radix must be between 2 and 36");
    }
    /* cannot fail */
    flags = JS_DTOA_FORMAT_FREE;
    if (radix != 10)
        flags |=  JS_DTOA_EXP_DISABLED;
    return js_dtoa2(ctx, d, radix, 0, flags);
}

JSValue js_number_toFixed(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv)
{
    int f, flags;
    double d;

    if (js_thisNumberValue(ctx, &d, *this_val))
        return JS_EXCEPTION;
    if (JS_ToInt32Sat(ctx, &f, argv[0]))
        return JS_EXCEPTION;
    if (f < 0 || f > 100)
        return JS_ThrowRangeError(ctx, "invalid number of digits");
    if (fabs(d) >= 1e21) {
        flags = JS_DTOA_FORMAT_FREE;
    } else {
        flags = JS_DTOA_FORMAT_FRAC;
    }
    return js_dtoa2(ctx, d, 10, f, flags);
}

JSValue js_number_toExponential(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    int f, flags;
    double d;

    if (js_thisNumberValue(ctx, &d, *this_val))
        return JS_EXCEPTION;
    if (JS_ToInt32Sat(ctx, &f, argv[0]))
        return JS_EXCEPTION;
    if (JS_IsUndefined(argv[0]) || !isfinite(d)) {
        f = 0;
        flags = JS_DTOA_FORMAT_FREE;
    } else {
        if (f < 0 || f > 100)
            return JS_ThrowRangeError(ctx, "invalid number of digits");
        f++;
        flags = JS_DTOA_FORMAT_FIXED;
    }
    return js_dtoa2(ctx, d, 10, f, flags | JS_DTOA_EXP_ENABLED);
}

JSValue js_number_toPrecision(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv)
{
    int p, flags;
    double d;

    if (js_thisNumberValue(ctx, &d, *this_val))
        return JS_EXCEPTION;
    if (JS_IsUndefined(argv[0])) {
        flags = JS_DTOA_FORMAT_FREE;
        p = 0;
    } else {
        if (JS_ToInt32Sat(ctx, &p, argv[0]))
            return JS_EXCEPTION;
        if (!isfinite(d)) {
            flags = JS_DTOA_FORMAT_FREE;
        } else {
            if (p < 1 || p > 100)
                return JS_ThrowRangeError(ctx, "invalid number of digits");
            flags = JS_DTOA_FORMAT_FIXED;
        }
    }
    return js_dtoa2(ctx, d, 10, p, flags);
}

JSValue js_number_parseInt(JSContext *ctx, JSValue *this_val,
                           int argc, JSValue *argv)
{
    int radix;
    double d;
    
    argv[0] = JS_ToString(ctx, argv[0]);
    if (JS_IsException(argv[0]))
        return JS_EXCEPTION;
    if (JS_ToInt32(ctx, &radix, argv[1]))
        return JS_EXCEPTION;
    if (radix != 0 && (radix < 2 || radix > 36)) {
        d = NAN;
    } else {
        if (js_atod1(ctx, &d, argv[0], radix, JS_ATOD_INT_ONLY))
            return JS_EXCEPTION;
    }
    return JS_NewFloat64(ctx, d);
}

JSValue js_number_parseFloat(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv)
{
    double d;
    
    argv[0] = JS_ToString(ctx, argv[0]);
    if (JS_IsException(argv[0]))
        return JS_EXCEPTION;
    if (js_atod1(ctx, &d, argv[0], 10, 0))
        return JS_EXCEPTION;
    return JS_NewFloat64(ctx, d);
}

/**********************************************************************/

JSValue js_boolean_constructor(JSContext *ctx, JSValue *this_val,
                               int argc, JSValue *argv)
{
    if (argc & FRAME_CF_CTOR)
        return JS_ThrowTypeError(ctx, "Boolean constructor not supported");
    return JS_NewBool(JS_ToBool(ctx, argv[0]));
}

/**********************************************************************/

JSValue js_string_get_length(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv)
{
    int len;
    
    if (!JS_IsString(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not a string");
    len = js_string_len(ctx, *this_val);
    return JS_NewShortInt(len);
}

JSValue js_string_set_length(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv)
{
    return JS_UNDEFINED; /* ignored */
}

JSValue js_string_slice(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    int len, start, end;
    
    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    len = js_string_len(ctx, *this_val);
    if (JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len))
        return JS_EXCEPTION;
    end = len;
    if (!JS_IsUndefined(argv[1])) {
        if (JS_ToInt32Clamp(ctx, &end, argv[1], 0, len, len))
            return JS_EXCEPTION;
    }
    return js_sub_string(ctx, *this_val, start, max_int(end, start));
}

JSValue js_string_substring(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv)
{
    int a, b, start, end, len;

    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    len = js_string_len(ctx, *this_val);
    if (JS_ToInt32Clamp(ctx, &a, argv[0], 0, len, 0))
        return JS_EXCEPTION;
    b = len;
    if (!JS_IsUndefined(argv[1])) {
        if (JS_ToInt32Clamp(ctx, &b, argv[1], 0, len, 0))
            return JS_EXCEPTION;
    }
    if (a < b) {
        start = a;
        end = b;
    } else {
        start = b;
        end = a;
    }
    return js_sub_string(ctx, *this_val, start, end);
}

JSValue js_string_charAt(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv, int magic)
{
    JSValue ret;
    int idx, c;
    
    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    if (JS_ToInt32Sat(ctx, &idx, argv[0]))
        return JS_EXCEPTION;
    if (idx < 0)
        goto ret_undef;
    c = string_getcp(ctx, *this_val, idx, (magic == magic_codePointAt));
    if (c == -1) {
    ret_undef:
        if (magic == magic_charCodeAt)
            ret = JS_NewFloat64(ctx, NAN);
        else if (magic == magic_charAt)
            ret = js_get_atom(ctx, JS_ATOM_empty);
        else
            ret = JS_UNDEFINED;
    } else {
        if (magic == magic_charCodeAt || magic == magic_codePointAt)
            ret = JS_NewShortInt(c);
        else
            ret = JS_NewStringChar(c);
    }
    //    dump_string_pos_cache(ctx);    
    return ret;
}

JSValue js_string_constructor(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv)
{
    if (argc & FRAME_CF_CTOR)
        return JS_ThrowTypeError(ctx, "string constructor not supported");
    if (argc <= 0) {
        return js_get_atom(ctx, JS_ATOM_empty);
    } else {
        return JS_ToString(ctx, argv[0]);
    }
}

JSValue js_string_fromCharCode(JSContext *ctx, JSValue *this_val,
                               int argc, JSValue *argv, int is_fromCodePoint)
{
    int i;
    StringBuffer b_s, *b = &b_s;

    string_buffer_push(ctx, b, 0);
    for(i = 0; i < argc; i++) {
        int c;
        if (JS_ToInt32(ctx, &c, argv[i]))
            goto fail;
        if (is_fromCodePoint) {
            if (c < 0 || c > 0x10ffff) {
                JS_ThrowRangeError(ctx, "invalid code point");
                goto fail;
            }
        } else {
            c &= 0xffff;
        }
        if (string_buffer_putc(ctx, b, c))
            break;
    }
    return string_buffer_pop(ctx, b);
 fail:
    string_buffer_pop(ctx, b);
    return JS_EXCEPTION;
}

JSValue js_string_concat(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    int i;
    StringBuffer b_s, *b = &b_s;
    JSValue r;
    
    r = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(r))
        return JS_EXCEPTION;
    string_buffer_push(ctx, b, 0);
    if (string_buffer_concat(ctx, b, r))
        goto done;

    for (i = 0; i < argc; i++) {
        if (string_buffer_concat(ctx, b, argv[i]))
            goto done;
    }
 done:
    return string_buffer_pop(ctx, b);
}

JSValue js_string_indexOf(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv, int lastIndexOf)
{
    int i, len, v_len, pos, start, stop, ret, inc, j;

    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    argv[0] = JS_ToString(ctx, argv[0]);
    if (JS_IsException(argv[0]))
        return JS_EXCEPTION;
    len = js_string_len(ctx, *this_val);
    v_len = js_string_len(ctx, argv[0]);
    if (lastIndexOf) {
        pos = len - v_len;
        if (argc > 1) {
            double d;
            if (JS_ToNumber(ctx, &d, argv[1]))
                goto fail;
            if (!isnan(d)) {
                if (d <= 0)
                    pos = 0;
                else if (d < pos)
                    pos = d;
            }
        }
        start = pos;
        stop = 0;
        inc = -1;
    } else {
        pos = 0;
        if (argc > 1) {
            if (JS_ToInt32Clamp(ctx, &pos, argv[1], 0, len, 0))
                goto fail;
        }
        start = pos;
        stop = len - v_len;
        inc = 1;
    }
    ret = -1;
    if (len >= v_len && inc * (stop - start) >= 0) {
        for (i = start;; i += inc) {
            for(j = 0; j < v_len; j++) {
                if (string_getc(ctx, *this_val, i + j) != string_getc(ctx, argv[0], j)) {
                    goto next;
                }
            }
            ret = i;
            break;
        next:
            if (i == stop)
                break;
        }
    }
    return JS_NewShortInt(ret);

fail:
    return JS_EXCEPTION;
}

int js_string_indexof(JSContext *ctx, JSValue str, JSValue needle, int start, int str_len, int needle_len)
{
    int i, j;
    for(i = start; i <= str_len - needle_len; i++) {
        for(j = 0; j < needle_len; j++) {
            if (string_getc(ctx, str, i + j) !=
                string_getc(ctx, needle, j)) {
                goto next;
            }
            
        }
        return i;
    next: ;
    }
    return -1;
}

/* Note: ascii only */
JSValue js_string_toLowerCase(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv, int to_lower)
{
    StringBuffer b_s, *b = &b_s;
    int i, c, len;

    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return *this_val;
    len = js_string_len(ctx, *this_val);
    if (string_buffer_push(ctx, b, len))
        return JS_EXCEPTION;
    for(i = 0; i < len; i++) {
        c = string_getc(ctx, *this_val, i);
        if (to_lower) {
            if (c >= 'A' && c <= 'Z')
                c += 'a' - 'A';
        } else {
            if (c >= 'a' && c <= 'z')
                c += 'A' - 'a';
        }
        string_buffer_putc(ctx, b, c);
    }
    return string_buffer_pop(ctx, b);
}

/* c < 128 */

JSValue js_string_trim(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv, int magic)
{
    int a, b, len;

    *this_val = JS_ToStringCheckObject(ctx, *this_val);
    if (JS_IsException(*this_val))
        return *this_val;
    len = js_string_len(ctx, *this_val);
    a = 0;
    b = len;
    if (magic & 1) {
        while (a < len && unicode_is_space(string_getc(ctx, *this_val, a)))
            a++;
    }
    if (magic & 2) {
        while (b > a && unicode_is_space(string_getc(ctx, *this_val, b - 1)))
            b--;
    }
    return js_sub_string(ctx, *this_val, a, b);
}

JSValue js_string_toString(JSContext *ctx, JSValue *this_val,
                           int argc, JSValue *argv)
{
    if (!JS_IsString(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not a string");
    return *this_val;
}

JSValue js_string_repeat(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    StringBuffer b_s, *b = &b_s;
    JSStringCharBuf buf;
    JSString *p;
    int n;
    int64_t len;
    
    if (!JS_IsString(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not a string");
    if (JS_ToInt32Sat(ctx, &n, argv[0]))
        return -1;
    p = get_string_ptr(ctx, &buf, *this_val);
    if (n < 0 || (len = (int64_t)n * p->len) > JS_STRING_LEN_MAX)
        return JS_ThrowRangeError(ctx, "invalid repeat count");
    if (p->len == 0 || n == 1)
        return *this_val;
    if (string_buffer_push(ctx, b, len))
        return JS_EXCEPTION;
    while (n-- > 0) {
        string_buffer_concat_str(ctx, b, *this_val);
    }
    return string_buffer_pop(ctx, b);
}

/**********************************************************************/

JSValue js_object_constructor(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv)
{
    /* XXX: incomplete */
    argc &= ~FRAME_CF_CTOR;
    if (argc <= 0) {
        return JS_NewObject(ctx);
    } else {
        return argv[0];
    }
}

JSValue js_object_defineProperty(JSContext *ctx, JSValue *this_val,
                                 int argc, JSValue *argv)
{
    JSValue *pobj, *pprop, *pdesc;
    JSValue val, getter, setter;
    JSGCRef val_ref, getter_ref;
    int flags;
    
    pobj = &argv[0];
    pprop = &argv[1];
    pdesc = &argv[2];

    if (!JS_IsObject(ctx, *pobj))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    *pprop = JS_ToPropertyKey(ctx, *pprop);
    if (JS_IsException(*pprop))
        return JS_EXCEPTION;
    val = JS_UNDEFINED;
    getter = JS_UNDEFINED;
    setter = JS_UNDEFINED;
    flags = 0;
    if (JS_HasProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_value))) {
        flags |= JS_DEF_PROP_HAS_VALUE;
        val = JS_GetProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_value));
        if (JS_IsException(val))
            return JS_EXCEPTION;
    }
    if (JS_HasProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_get))) {
        flags |= JS_DEF_PROP_HAS_GET;
        JS_PUSH_VALUE(ctx, val);
        getter = JS_GetProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_get));
        JS_POP_VALUE(ctx, val);
        if (JS_IsException(getter))
            return JS_EXCEPTION;
        if (!JS_IsUndefined(getter) && !JS_IsFunction(ctx, getter))
            goto bad_getset;
    }
    if (JS_HasProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_set))) {
        flags |= JS_DEF_PROP_HAS_SET;
        JS_PUSH_VALUE(ctx, val);
        JS_PUSH_VALUE(ctx, getter);
        setter = JS_GetProperty(ctx, *pdesc, js_get_atom(ctx, JS_ATOM_set));
        JS_POP_VALUE(ctx, getter);
        JS_POP_VALUE(ctx, val);
        if (JS_IsException(setter))
            return JS_EXCEPTION;
        if (!JS_IsUndefined(setter) && !JS_IsFunction(ctx, setter)) {
        bad_getset:
            return JS_ThrowTypeError(ctx, "invalid getter or setter");
        }
    }
    if (flags & (JS_DEF_PROP_HAS_GET | JS_DEF_PROP_HAS_SET)) {
        if (flags & JS_DEF_PROP_HAS_VALUE)
            return JS_ThrowTypeError(ctx, "cannot have both value and get/set");
        val = getter;
    }
    val = JS_DefinePropertyInternal(ctx, *pobj, *pprop, val, setter,
                                    flags | JS_DEF_PROP_LOOKUP);
    if (JS_IsException(val))
        return val;
    return *pobj;
}

JSValue js_object_getPrototypeOf(JSContext *ctx, JSValue *this_val,
                                 int argc, JSValue *argv)
{
    JSObject *p;
    if (!JS_IsObject(ctx, argv[0]))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    p = JS_VALUE_TO_PTR(argv[0]);
    return p->proto;
}

/* 'obj' must be an object. 'proto' must be JS_NULL or an object */
JSValue js_set_prototype_internal(JSContext *ctx, JSValue obj, JSValue proto)
{
    JSObject *p, *p1;

    p = JS_VALUE_TO_PTR(obj);
    if (p->proto != proto) {
        if (proto != JS_NULL) {
            /* check if there is a cycle */
            p1 = JS_VALUE_TO_PTR(proto);
            for(;;) {
                if (p1 == p)
                    return JS_ThrowTypeError(ctx, "circular prototype chain");
                if (p1->proto == JS_NULL)
                    break;
                p1 = JS_VALUE_TO_PTR(p1->proto);
            }
        }
        
        p->proto = proto;
    }
    return JS_UNDEFINED;
}

JSValue js_object_setPrototypeOf(JSContext *ctx, JSValue *this_val,
                                 int argc, JSValue *argv)
{
    JSValue proto;
    
    if (!JS_IsObject(ctx, argv[0]))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    proto = argv[1];
    if (proto != JS_NULL && !JS_IsObject(ctx, proto))
        return JS_ThrowTypeError(ctx, "not a prototype");
    if (JS_IsException(js_set_prototype_internal(ctx, argv[0], proto)))
        return JS_EXCEPTION;
    return argv[0];
}

JSValue js_object_create(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    JSValue proto;
    proto = argv[0];
    if (proto != JS_NULL && !JS_IsObject(ctx, proto))
        return JS_ThrowTypeError(ctx, "not a prototype");
    if (argc >= 2)
        return JS_ThrowTypeError(ctx, "unsupported additional properties");
    return JS_NewObjectProtoClass(ctx, proto, JS_CLASS_OBJECT, 0);
}

JSValue js_object_keys(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv)
{
    JSObject *p, *pret;
    JSValue ret, str;
    JSValueArray *arr, *ret_arr;
    int array_len, prop_count, hash_mask, alloc_size, i, j, pos;
    JSGCRef ret_ref;

    if (!JS_IsObject(ctx, argv[0]))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    p = JS_VALUE_TO_PTR(argv[0]);

    if (p->class_id == JS_CLASS_ARRAY) {
        array_len = p->u.array.len;
    } else if (p->class_id >= JS_CLASS_UINT8C_ARRAY && p->class_id <= JS_CLASS_FLOAT64_ARRAY) {
        array_len = p->u.typed_array.len;
    } else {
        array_len = 0;
    }
            
    arr = JS_VALUE_TO_PTR(p->props);
    prop_count = JS_VALUE_GET_INT(arr->arr[0]);
    hash_mask = JS_VALUE_GET_INT(arr->arr[1]);

    alloc_size = array_len + prop_count;
    
    ret = JS_NewArray(ctx, alloc_size);
    if (JS_IsException(ret))
        return ret;

    pos = 0;
    for(i = 0; i < array_len; i++) {
        JS_PUSH_VALUE(ctx, ret);
        str = JS_ToString(ctx, JS_NewShortInt(i));
        JS_POP_VALUE(ctx, ret);
        if (JS_IsException(str))
            return str;
        pret = JS_VALUE_TO_PTR(ret);
        ret_arr = JS_VALUE_TO_PTR(pret->u.array.tab);
        ret_arr->arr[pos++] = str;
    }
    
    for(i = 0, j = 0; j < prop_count; i++) {
        JSProperty *pr;
        p = JS_VALUE_TO_PTR(argv[0]);
        arr = JS_VALUE_TO_PTR(p->props);
        pr = (JSProperty *)&arr->arr[2 + hash_mask + 1 + 3 * i];
        /* exclude deleted properties */
        if (pr->key != JS_UNINITIALIZED) {
            JS_PUSH_VALUE(ctx, ret);
            str = JS_ToString(ctx, pr->key);
            JS_POP_VALUE(ctx, ret);
            if (JS_IsException(str))
                return str;
            pret = JS_VALUE_TO_PTR(ret);
            ret_arr = JS_VALUE_TO_PTR(pret->u.array.tab);
            ret_arr->arr[pos++] = str;
            j++;
        }
    }
    pret = JS_VALUE_TO_PTR(ret);
    pret->u.array.len = pos;
    return ret;
}

JSValue js_object_hasOwnProperty(JSContext *ctx, JSValue *this_val,
                                 int argc, JSValue *argv)
{
    JSObject *p;
    JSValue prop;
    int array_len, idx;
    
    if (JS_IsNull(*this_val) || JS_IsUndefined(*this_val))
        return JS_ThrowTypeError(ctx, "cannot convert to object");
    if (!JS_IsObject(ctx, *this_val))
        return JS_FALSE; /* XXX: could improve for strings */
    prop = JS_ToPropertyKey(ctx, argv[0]);
    p = JS_VALUE_TO_PTR(*this_val);
    if (p->class_id == JS_CLASS_ARRAY) {
        array_len = p->u.array.len;
        goto check_array;
    } else if (p->class_id >= JS_CLASS_UINT8C_ARRAY && p->class_id <= JS_CLASS_FLOAT64_ARRAY) {
        array_len = p->u.typed_array.len;
    check_array:
        if (JS_IsInt(prop)) {
            idx = JS_VALUE_GET_INT(prop);
            return JS_NewBool((idx >= 0 && idx < array_len));
        }
    }
    return JS_NewBool((find_own_property(ctx, p, prop) != NULL));
}

JSValue js_object_toString(JSContext *ctx, JSValue *this_val,
                           int argc, JSValue *argv)
{
    const char *str;
    char buf[64];
    /* XXX: not fully compliant */
    if (JS_IsIntOrShortFloat(*this_val)) {
        goto number;
    } else if (!JS_IsPtr(*this_val)) {
        switch(JS_VALUE_GET_SPECIAL_TAG(*this_val)) {
        case JS_TAG_NULL:
            str = "Null";
            break;
        case JS_TAG_UNDEFINED:
            str = "Undefined";
            break;
        case JS_TAG_SHORT_FUNC:
            str = "Function";
            break;
        case JS_TAG_BOOL:
            str = "Boolean";
            break;
        case JS_TAG_STRING_CHAR:
            goto string;
        default:
            goto object;
        }
    } else {
        JSObject *p = JS_VALUE_TO_PTR(*this_val);
        switch(p->mtag) {
        case JS_MTAG_OBJECT:
            switch(p->class_id) {
            case JS_CLASS_ARRAY:
                str = "Array";
                break;
            case JS_CLASS_ERROR:
                str = "Error";
                break;
            case JS_CLASS_CLOSURE:
            case JS_CLASS_C_FUNCTION:
                str = "Function";
                break;
            default:
            object:
                str = "Object";
                break;
            }
            break;
        case JS_MTAG_STRING:
        string:
            str = "String";
            break;
        case JS_MTAG_FLOAT64:
        number:
            str = "Number";
            break;
        default:
            goto object;
        }
    }
    js_snprintf(buf, sizeof(buf), "[object %s]", str);
    return JS_NewString(ctx, buf);
}

/**********************************************************************/

JSValue js_error_constructor(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv, int magic)
{
    JSValue obj, msg;
    JSObject *p;
    JSGCRef obj_ref;
    
    argc &= ~FRAME_CF_CTOR;

    obj = JS_NewObjectProtoClass(ctx, ctx->class_proto[magic], JS_CLASS_ERROR,
                                 sizeof(JSErrorData));
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.error.message = JS_NULL;
    p->u.error.stack = JS_NULL;
    
    if (!JS_IsUndefined(argv[0])) {
        JS_PUSH_VALUE(ctx, obj);
        msg = JS_ToString(ctx, argv[0]);
        JS_POP_VALUE(ctx, obj);
        if (JS_IsException(msg))
            return msg;
        p = JS_VALUE_TO_PTR(obj);
        p->u.error.message = msg;
    } else {
        p = JS_VALUE_TO_PTR(obj);
        p->u.error.message = js_get_atom(ctx, JS_ATOM_empty);
    }
    JS_PUSH_VALUE(ctx, obj);
    build_backtrace(ctx, obj, NULL, 0, 0, 1);
    JS_POP_VALUE(ctx, obj);
    return obj;
}

JSValue js_error_toString(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv)
{
    JSObject *p;
    JSValue name;
    StringBuffer b_s, *b = &b_s;

    if (!JS_IsError(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not an Error object");
    name = JS_GetProperty(ctx, *this_val, js_get_atom(ctx, JS_ATOM_name));
    if (JS_IsException(name))
        return name;
    if (JS_IsUndefined(name))
        name = js_get_atom(ctx, JS_ATOM_Error);
    else
        name = JS_ToString(ctx, name);
    if (JS_IsException(name))
        return name;
    string_buffer_push(ctx, b, 0);
    string_buffer_concat(ctx, b, name);
    p = JS_VALUE_TO_PTR(*this_val);
    if (p->u.error.message != JS_NULL) {
        string_buffer_puts(ctx, b, ": ");
        p = JS_VALUE_TO_PTR(*this_val);
        string_buffer_concat(ctx, b, p->u.error.message);
    }
    return string_buffer_pop(ctx, b);
}

JSValue js_error_get_message(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv, int magic)
{
    JSObject *p;
    if (!JS_IsError(ctx, *this_val))
        return JS_ThrowTypeError(ctx, "not an Error object");
    p = JS_VALUE_TO_PTR(*this_val);
    if (magic == 0)
        return p->u.error.message;
    else
        return p->u.error.stack;
}

/**********************************************************************/

JSObject *js_get_array(JSContext *ctx, JSValue obj)
{
    JSObject *p;
    p = js_get_object_class(ctx, obj, JS_CLASS_ARRAY);
    if (!p) {
        JS_ThrowTypeError(ctx, "not an array");
        return NULL;
    }
    return p;
}

JSValue js_array_get_length(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv)
{
    JSObject *p;
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    return JS_NewShortInt(p->u.array.len);
}

int js_array_resize(JSContext *ctx, JSValue *this_val, int new_len)
{
    JSObject *p;
    int i;

    if (new_len < 0 || new_len > JS_SHORTINT_MAX) {
        JS_ThrowTypeError(ctx, "invalid array length");
        return -1;
    }
    p = JS_VALUE_TO_PTR(*this_val);
    if (new_len < p->u.array.len) {
        JSValueArray *arr = JS_VALUE_TO_PTR(p->u.array.tab);
        /* shrink the array if the new size is small enough */
        if (new_len < (arr->size / 2) && arr->size >= 4) {
            js_shrink_value_array(ctx, &p->u.array.tab, new_len);
            p = JS_VALUE_TO_PTR(*this_val);
        } else {
            for(i = new_len; i < p->u.array.len; i++)
                arr->arr[i] = JS_UNDEFINED;
        }
    } else if (new_len > p->u.array.len) {
        JSValueArray *arr;
        JSValue new_tab;
        new_tab = js_resize_value_array(ctx, p->u.array.tab, new_len);
        if (JS_IsException(new_tab))
            return -1;
        p = JS_VALUE_TO_PTR(*this_val);
        p->u.array.tab = new_tab;
        arr = JS_VALUE_TO_PTR(p->u.array.tab);
        for(i = p->u.array.len; i < new_len; i++)
            arr->arr[i] = JS_UNDEFINED;
    }
    p->u.array.len = new_len;
    return 0;
}

JSValue js_array_set_length(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv)
{
    int new_len;

    if (!js_get_array(ctx, *this_val))
        return JS_EXCEPTION;
    if (JS_ToInt32(ctx, &new_len, argv[0]))
        return JS_EXCEPTION;
    if (js_array_resize(ctx, this_val, new_len))
        return JS_EXCEPTION;
    return JS_UNDEFINED;
}

JSValue js_array_constructor(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv)
{
    JSValue obj;
    JSObject *p;
    int len, i;
    BOOL has_init;
    
    argc &= ~FRAME_CF_CTOR;

    if (argc == 1 && JS_IsNumber(ctx, argv[0])) {
        /* XXX: we create undefined properties instead of just setting the length */
        if (JS_ToInt32(ctx, &len, argv[0]))
            return JS_EXCEPTION;
        has_init = FALSE;
    } else {
        len = argc;
        has_init = TRUE;
    }
    
    if (len < 0 || len > JS_SHORTINT_MAX)
        return JS_ThrowRangeError(ctx, "invalid array length");
    obj = JS_NewArray(ctx, len);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.array.len = len;

    if (has_init) {
        JSValueArray *arr = JS_VALUE_TO_PTR(p->u.array.tab);
        for(i = 0; i < argc; i++) {
            arr->arr[i] = argv[i];
        }
    }
    return obj;
}

JSValue js_array_push(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv, int is_unshift)
{
    JSObject *p;
    int new_len, i, from;
    JSValueArray *arr;
    JSValue new_tab;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    from = p->u.array.len;
    new_len = from + argc;
    if (new_len > JS_SHORTINT_MAX)
        return JS_ThrowRangeError(ctx, "invalid array length");
    new_tab = js_resize_value_array(ctx, p->u.array.tab, new_len);
    if (JS_IsException(new_tab))
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(*this_val);
    p->u.array.tab = new_tab;
    p->u.array.len = new_len;
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    if (is_unshift && argc > 0) {
        memmove(arr->arr + argc, arr->arr, from * sizeof(JSValue));
        from = 0;
    }
    for(i = 0; i < argc; i++) {
        arr->arr[from + i] = argv[i];
    }
    return JS_NewShortInt(new_len);
}

JSValue js_array_pop(JSContext *ctx, JSValue *this_val,
                     int argc, JSValue *argv)
{
    JSObject *p;
    JSValue ret;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    if (p->u.array.len > 0) {
        JSValueArray *arr = JS_VALUE_TO_PTR(p->u.array.tab);
        ret = arr->arr[--p->u.array.len];
    } else {
        ret = JS_UNDEFINED;
    }
    return ret;
}

JSValue js_array_shift(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv)
{
    JSObject *p;
    JSValue ret;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    if (p->u.array.len > 0) {
        JSValueArray *arr = JS_VALUE_TO_PTR(p->u.array.tab);
        ret = arr->arr[0];
        p->u.array.len--;
        memmove(arr->arr, arr->arr + 1, p->u.array.len * sizeof(JSValue));
    } else {
        ret = JS_UNDEFINED;
    }
    return ret;
}

JSValue js_array_join(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    uint32_t i, len;
    BOOL is_array;
    JSValue sep, val;
    JSGCRef sep_ref;
    JSObject *p;
    JSValueArray *arr;
    StringBuffer b_s, *b = &b_s;
    
    if (!JS_IsObject(ctx, *this_val))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    p = JS_VALUE_TO_PTR(*this_val);
    is_array = (p->class_id == JS_CLASS_ARRAY);
    if (is_array) {
        len = p->u.array.len;
    } else {
        if (js_get_length32(ctx, &len, *this_val))
            return JS_EXCEPTION;
    }

    if (argc > 0 && !JS_IsUndefined(argv[0])) {
        sep = JS_ToString(ctx, argv[0]);
        if (JS_IsException(sep))
            return sep;
    } else {
        sep = JS_NewStringChar(',');
    }
    JS_PUSH_VALUE(ctx, sep);

    string_buffer_push(ctx, b, 0);
    for(i = 0; i < len; i++) {
        if (i > 0) {
            if (string_buffer_concat(ctx, b, sep_ref.val))
                goto exception;
        }
        if (is_array) {
            p = JS_VALUE_TO_PTR(*this_val);
            arr = JS_VALUE_TO_PTR(p->u.array.tab);
            if (i < p->u.array.len)
                val = arr->arr[i];
            else
                val = JS_UNDEFINED;
        } else {
            val = JS_GetPropertyUint32(ctx, *this_val, i);
            if (JS_IsException(val))
                goto exception;
        }
        if (!JS_IsUndefined(val) && !JS_IsNull(val)) {
            if (string_buffer_concat(ctx, b, val))
                goto exception;
        }
    }
    val = string_buffer_pop(ctx, b);
    JS_POP_VALUE(ctx, sep);
    return val;

 exception:
    string_buffer_pop(ctx, b);
    JS_POP_VALUE(ctx, sep);
    return JS_EXCEPTION;
}

JSValue js_array_toString(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv)
{
    return js_array_join(ctx, this_val, 0, NULL);
}

BOOL JS_IsArray(JSContext *ctx, JSValue obj)
{
    JSObject *p;
    p = js_get_object_class(ctx, obj, JS_CLASS_ARRAY);
    return (p != NULL);
}

JSValue js_array_isArray(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    return JS_NewBool(JS_IsArray(ctx, argv[0]));
}

JSValue js_array_reverse(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    int len;
    JSObject *p;
    JSValueArray *arr;

    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    js_reverse_val(arr->arr, len);
    return *this_val;
}

JSValue js_array_concat(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    JSObject *p;
    int len, i, j, pos;
    int64_t len64;
    JSValue obj, val;
    JSValueArray *arr, *arr1;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    /* do a first pass to estimate the length */
    len64 = p->u.array.len;
    for(i = 0; i < argc; i++) {
        p = js_get_object_class(ctx, argv[i], JS_CLASS_ARRAY);
        if (p) {
            len64 += p->u.array.len;
        } else {
            len64++;
        }
    }
    if (len64 > JS_SHORTINT_MAX)
        return JS_ThrowTypeError(ctx, "Array loo long");
    len = len64;

    obj = JS_NewArray(ctx, len);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    
    pos = 0;
    for(i = -1; i < argc; i++) {
        val = i == -1 ? *this_val : argv[i];
        p = js_get_object_class(ctx, val, JS_CLASS_ARRAY);
        if (p) {
            arr1 = JS_VALUE_TO_PTR(p->u.array.tab);
            for(j = 0; j < p->u.array.len; j++)
                arr->arr[pos + j] = arr1->arr[j];
            pos += p->u.array.len;
        } else {
            arr->arr[pos++] = val;
        }
    }
    return obj;
}

JSValue js_array_indexOf(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv, int is_lastIndexOf)
{
    JSObject *p;
    int len, n, res;
    JSValueArray *arr;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;
    if (is_lastIndexOf) {
        n = len - 1;
    } else {
        n = 0;
    }
    if (argc > 1) {
        if (JS_ToInt32Clamp(ctx, &n, argv[1],
                            -is_lastIndexOf, len - is_lastIndexOf, len))
            return JS_EXCEPTION;
    }
    /* the array may be modified */
    p = JS_VALUE_TO_PTR(*this_val);
    len = p->u.array.len; /* the length may be modified */
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    res = -1;
    if (is_lastIndexOf) {
        n = min_int(n, len - 1);
        for(;n >= 0; n--) {
            if (js_strict_eq(ctx, argv[0], arr->arr[n])) {
                res = n;
                break;
            }
        }
    } else {
        for(;n < len; n++) {
            if (js_strict_eq(ctx, argv[0], arr->arr[n])) {
                res = n;
                break;
            }
        }
    }
    return JS_NewShortInt(res);
}

JSValue js_array_slice(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv)
{
    JSObject *p, *p1;
    int len, start, final, k;
    JSValueArray *arr, *arr1;
    JSValue obj;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;

    if (JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len))
        return JS_EXCEPTION;
    final = len;
    if (!JS_IsUndefined(argv[1])) {
        if (JS_ToInt32Clamp(ctx, &final, argv[1], 0, len, len))
            return JS_EXCEPTION;
    }
    /* the array may have been modified */
    p = JS_VALUE_TO_PTR(*this_val);
    len = p->u.array.len; /* the length may be modified */
    final = min_int(final, len);

    obj = JS_NewArray(ctx, max_int(final - start, 0));
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(*this_val);
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    p1 = JS_VALUE_TO_PTR(obj);
    arr1 = JS_VALUE_TO_PTR(p1->u.array.tab);
    for(k = start; k < final; k++) {
        arr1->arr[k - start] = arr->arr[k];
    }
    return obj;
}

JSValue js_array_splice(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    JSObject *p, *p1;
    int start, len, item_count, del_count, new_len, i, ret;
    JSValueArray *arr, *arr1;
    JSValue obj;
    JSGCRef obj_ref;
    
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;

    if (JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len))
        return JS_EXCEPTION;

    if (argc == 0) {
        item_count = 0;
        del_count = 0;
    } else if (argc == 1) {
        item_count = 0;
        del_count = len - start;
    } else {
        item_count = argc - 2;
        if (JS_ToInt32Clamp(ctx, &del_count, argv[1], 0, len - start, 0))
            return JS_EXCEPTION;
    }
    new_len = len + item_count - del_count;
    
    obj = JS_NewArray(ctx, del_count);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(*this_val);
    /* handling this case has no practical use */
    if (p->u.array.len != len)
        return JS_ThrowTypeError(ctx, "array length was modified");
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    p1 = JS_VALUE_TO_PTR(obj);
    arr1 = JS_VALUE_TO_PTR(p1->u.array.tab);

    for(i = 0; i < del_count; i++) {
        arr1->arr[i] = arr->arr[start + i];
    }

    if (item_count != del_count) {
        /* resize */
        if (del_count > item_count) {
            memmove(arr->arr + start + item_count,
                    arr->arr + start + del_count,
                    (len - (start + del_count)) * sizeof(JSValue));
        }
        JS_PUSH_VALUE(ctx, obj);
        ret = js_array_resize(ctx, this_val, new_len);
        JS_POP_VALUE(ctx, obj);
        if (ret)
            return JS_EXCEPTION;
        p = JS_VALUE_TO_PTR(*this_val);
        arr = JS_VALUE_TO_PTR(p->u.array.tab);
        if (del_count < item_count) {
            memmove(arr->arr + start + item_count,
                    arr->arr + start + del_count,
                    (len - (start + del_count)) * sizeof(JSValue));
        }
    }

    for(i = 0; i < item_count; i++)
        arr->arr[start + i] = argv[2 + i];
    
    return obj;
}

JSValue js_array_every(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv, int special)
{
    JSObject *p;
    JSValueArray *arr;
    JSValue res, ret, val;
    JSValue *pfunc, *pthis_arg;
    JSGCRef val_ref, ret_ref;
    int len, k, n;

    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;

    pfunc = &argv[0];
    pthis_arg = NULL;
    if (argc > 1)
        pthis_arg = &argv[1];

    if (!JS_IsFunction(ctx, *pfunc))
        return JS_ThrowTypeError(ctx, "not a function");
    
    switch (special) {
    case js_special_every:
        ret = JS_TRUE;
        break;
    case js_special_some:
        ret = JS_FALSE;
        break;
    case js_special_map:
        ret = JS_NewArray(ctx, len);
        if (JS_IsException(ret))
            return JS_EXCEPTION;
        break;
    case js_special_filter:
        ret = JS_NewArray(ctx, 0);
        if (JS_IsException(ret))
            return JS_EXCEPTION;
        break;
    case js_special_forEach:
    default:
        ret = JS_UNDEFINED;
        break;
    }
    n = 0;

    JS_PUSH_VALUE(ctx, ret);
    for(k = 0; k < len; k++) {
        if (JS_StackCheck(ctx, 5))
            goto exception;

        p = JS_VALUE_TO_PTR(*this_val);
        arr = JS_VALUE_TO_PTR(p->u.array.tab);
        /* the array length may have been modified by the function call*/
        if (k >= p->u.array.len)
            break;
        val = arr->arr[k];
        
        JS_PushArg(ctx, *this_val);
        JS_PushArg(ctx, JS_NewShortInt(k));
        JS_PushArg(ctx, val); /* arg0 */
        JS_PushArg(ctx, *pfunc); /* func */
        JS_PushArg(ctx, pthis_arg ? *pthis_arg : JS_UNDEFINED); /* this */
        JS_PUSH_VALUE(ctx, val);
        res = JS_Call(ctx, 3);
        JS_POP_VALUE(ctx, val);
        if (JS_IsException(res))
            goto exception;
        
        switch (special) {
        case js_special_every:
            if (!JS_ToBool(ctx, res)) {
                ret_ref.val = JS_FALSE;
                goto done;
            }
            break;
        case js_special_some:
            if (JS_ToBool(ctx, res)) {
                ret_ref.val = JS_TRUE;
                goto done;
            }
            break;
        case js_special_map:
            /* Note: same as defineProperty for arrays */
            res = JS_SetPropertyUint32(ctx, ret_ref.val, k, res);
            if (JS_IsException(res))
                goto exception;
            break;
        case js_special_filter:
            if (JS_ToBool(ctx, res)) {
                res = JS_SetPropertyUint32(ctx, ret_ref.val, n++, val);
                if (JS_IsException(res))
                    goto exception;
            }
            break;
        case js_special_forEach:
        default:
            break;
        }
    }
done:
    JS_POP_VALUE(ctx, ret);
    return ret;
 exception:
    ret_ref.val = JS_EXCEPTION;
    goto done;
}

JSValue js_array_reduce(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv, int special)
{
    JSObject *p;
    JSValueArray *arr;
    JSValue acc, *pfunc;
    JSGCRef acc_ref;
    int len, k, k1, ret;

    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.array.len;
    pfunc = &argv[0];

    if (!JS_IsFunction(ctx, *pfunc))
        return JS_ThrowTypeError(ctx, "not a function");

    k = 0;
    if (argc > 1) {
        acc = argv[1];
    } else {
        if (len == 0)
            return JS_ThrowTypeError(ctx, "empty array");
        k1 = (special == js_special_reduceRight) ? len - k - 1 : k;
        arr = JS_VALUE_TO_PTR(p->u.array.tab);
        acc = arr->arr[k1];
        k++;
    }
    for (; k < len; k++) {
        JS_PUSH_VALUE(ctx, acc);
        ret = JS_StackCheck(ctx, 6);
        JS_POP_VALUE(ctx, acc);
        if (ret)
            return JS_EXCEPTION;

        k1 = (special == js_special_reduceRight) ? len - k - 1 : k;
        p = JS_VALUE_TO_PTR(*this_val);
        arr = JS_VALUE_TO_PTR(p->u.array.tab);
        /* Note: the array length may have been modified, hence the check */
        if (k1 >= p->u.array.len)
            break;
        
        JS_PushArg(ctx, *this_val);
        JS_PushArg(ctx, JS_NewShortInt(k1));
        JS_PushArg(ctx, arr->arr[k1]);
        JS_PushArg(ctx, acc); /* arg0 */
        JS_PushArg(ctx, *pfunc); /* func */
        JS_PushArg(ctx, JS_UNDEFINED); /* this */
        acc = JS_Call(ctx, 4);
        if (JS_IsException(acc))
            return JS_EXCEPTION;
    }
    return acc;
}

/* heapsort algorithm */
void rqsort_idx(size_t nmemb, int (*cmp)(size_t, size_t, void *), void (*swap)(size_t, size_t, void *), void *opaque)
{
    size_t i, n, c, r, size;

    size = 1;
    if (nmemb > 1) {
        i = (nmemb / 2) * size;
        n = nmemb * size;

        while (i > 0) {
            i -= size;
            for (r = i; (c = r * 2 + size) < n; r = c) {
                if (c < n - size && cmp(c, c + size, opaque) <= 0)
                    c += size;
                if (cmp(r, c, opaque) > 0)
                    break;
                swap(r, c, opaque);
            }
        }
        for (i = n - size; i > 0; i -= size) {
            swap(0, i, opaque);

            for (r = 0; (c = r * 2 + size) < i; r = c) {
                if (c < i - size && cmp(c, c + size, opaque) <= 0)
                    c += size;
                if (cmp(r, c, opaque) > 0)
                    break;
                swap(r, c, opaque);
            }
        }
    }
}

typedef struct {
    JSContext *ctx;
    BOOL exception;
    JSValue *parr;
    JSValue *pfunc;
} JSArraySortContext;

/* return -1, 0, 1  */
int js_array_sort_cmp(size_t i1, size_t i2, void *opaque)
{
    JSArraySortContext *s = opaque;
    JSContext *ctx = s->ctx;
    JSValueArray *arr;
    int cmp, j1, j2;
    
    if (s->exception)
        return 0;

    arr = JS_VALUE_TO_PTR(*s->parr);
    if (s->pfunc) {
        JSValue res;
        /* custom sort function is specified as returning 0 for identical
         * objects: avoid method call overhead.
         */
        if (arr->arr[2 * i1] == arr->arr[2 * i2])
            goto cmp_same;
        if (JS_StackCheck(ctx, 4))
            goto exception;
        arr = JS_VALUE_TO_PTR(*s->parr);

        JS_PushArg(ctx, arr->arr[2 * i2]);
        JS_PushArg(ctx, arr->arr[2 * i1]); /* arg0 */
        JS_PushArg(ctx, *s->pfunc); /* func */
        JS_PushArg(ctx, JS_UNDEFINED); /* this */
        res = JS_Call(ctx, 2);
        if (JS_IsException(res))
            return JS_EXCEPTION;
        if (JS_IsInt(res)) {
            int val = JS_VALUE_GET_INT(res);
            cmp = (val > 0) - (val < 0);
        } else {
            double val;
            if (JS_ToNumber(ctx, &val, res))
                goto exception;
            cmp = (val > 0) - (val < 0);
        }
    } else {
        JSValue str1, str2;
        JSGCRef str1_ref;

        str1 = arr->arr[2 * i1];
        if (!JS_IsString(ctx, str1)) {
            str1 = JS_ToString(ctx, str1);
            if (JS_IsException(str1))
                goto exception;
            arr = JS_VALUE_TO_PTR(*s->parr);
        }
        str2 = arr->arr[2 * i2];
        if (!JS_IsString(ctx, str2)) {
            JS_PUSH_VALUE(ctx, str1);
            str2 = JS_ToString(ctx, str2);
            JS_POP_VALUE(ctx, str1);
            if (JS_IsException(str2))
                goto exception;
        }
        cmp = js_string_compare(ctx, str1, str2);
    }
    if (cmp != 0)
        return cmp;
 cmp_same:
    /* make sort stable: compare array offsets */
    arr = JS_VALUE_TO_PTR(*s->parr);
    j1 = JS_VALUE_GET_INT(arr->arr[2 * i1 + 1]);
    j2 = JS_VALUE_GET_INT(arr->arr[2 * i2 + 1]);
    return (j1 > j2) - (j1 < j2);

exception:
    s->exception = TRUE;
    return 0;
}

void js_array_sort_swap(size_t i1, size_t i2, void *opaque)
{
    JSArraySortContext *s = opaque;
    JSValueArray *arr;
    JSValue tmp, *tab;
    
    arr = JS_VALUE_TO_PTR(*s->parr);
    tab = arr->arr;
    tmp = tab[2 * i1];
    tab[2 * i1] = tab[2 * i2];
    tab[2 * i2] = tmp;

    tmp = tab[2 * i1 + 1];
    tab[2 * i1 + 1] = tab[2 * i2 + 1];
    tab[2 * i2 + 1] = tmp;
}

JSValue js_array_sort(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    JSValue *pfunc = &argv[0];
    JSObject *p;
    JSValue tab_val;
    JSGCRef tab_val_ref;
    JSValueArray *tab, *arr;
    int i, len, n;
    JSArraySortContext ss, *s = &ss;
    
    if (!JS_IsUndefined(*pfunc)) {
        if (!JS_IsFunction(ctx, *pfunc))
            return JS_ThrowTypeError(ctx, "not a function");
    } else {
        pfunc = NULL;
    }
    p = js_get_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;

    /* create a temporary array for sorting */
    len = p->u.array.len;
    tab = js_alloc_value_array(ctx, 0, len * 2);
    if (!tab)
        return JS_EXCEPTION;

    p = JS_VALUE_TO_PTR(*this_val);
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    n = 0;
    for(i = 0; i < len; i++) {
        if (!JS_IsUndefined(arr->arr[i])) {
            tab->arr[2 * n] = arr->arr[i];
            tab->arr[2 * n + 1] = JS_NewShortInt(i);
            n++;
        }
    }
    /* the end of 'tab' is already filled with JS_UNDEFINED */
    tab_val = JS_VALUE_FROM_PTR(tab);
    
    JS_PUSH_VALUE(ctx, tab_val);
    s->ctx = ctx;
    s->exception = FALSE;
    s->parr = &tab_val_ref.val;
    s->pfunc = pfunc;
    rqsort_idx(n, js_array_sort_cmp, js_array_sort_swap, s);
    JS_POP_VALUE(ctx, tab_val);
    tab = JS_VALUE_TO_PTR(tab_val);
    if (s->exception) {
        js_free(ctx, tab);
        return JS_EXCEPTION;
    }
    
    p = JS_VALUE_TO_PTR(*this_val);
    arr = JS_VALUE_TO_PTR(p->u.array.tab);
    /* XXX: could resize the array in case it was shrank by the compare function */
    len = min_int(len, p->u.array.len);
    for(i = 0; i < len; i++) {
        arr->arr[i] = tab->arr[2 * i];
    }
    js_free(ctx, tab);
    return *this_val;
}

/**********************************************************************/

/* precondition: a and b are not NaN */
double js_fmin(double a, double b)
{
    if (a == 0 && b == 0) {
        return uint64_as_float64(float64_as_uint64(a) | float64_as_uint64(b));
    } else if (a <= b) {
        return a;
    } else {
        return b;
    }
}

/* precondition: a and b are not NaN */
double js_fmax(double a, double b)
{
    if (a == 0 && b == 0) {
        return uint64_as_float64(float64_as_uint64(a) & float64_as_uint64(b));
    } else if (a >= b) {
        return a;
    } else {
        return b;
    }
}

JSValue js_math_min_max(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv, int magic)
{
    BOOL is_max = magic;
    double r, a;
    int i;

    if (unlikely(argc == 0)) {
        return __JS_NewFloat64(ctx, is_max ? -1.0 / 0.0 : 1.0 / 0.0);
    }

    if (JS_IsInt(argv[0])) {
        int a1, r1 = JS_VALUE_GET_INT(argv[0]);
        for(i = 1; i < argc; i++) {
            if (!JS_IsInt(argv[i])) {
                r = r1;
                goto generic_case;
            }
            a1 = JS_VALUE_GET_INT(argv[i]);
            if (is_max)
                r1 = max_int(r1, a1);
            else
                r1 = min_int(r1, a1);
        }
        return JS_NewShortInt(r1);
    } else {
        if (JS_ToNumber(ctx, &r, argv[0]))
            return JS_EXCEPTION;
        i = 1;
    generic_case:
        while (i < argc) {
            if (JS_ToNumber(ctx, &a, argv[i]))
                return JS_EXCEPTION;
            if (!isnan(r)) {
                if (isnan(a)) {
                    r = a;
                } else {
                    if (is_max)
                        r = js_fmax(r, a);
                    else
                        r = js_fmin(r, a);
                }
            }
            i++;
        }
        return JS_NewFloat64(ctx, r);
    }
}

double js_math_sign(double a)
{
    if (isnan(a) || a == 0.0)
        return a;
    if (a < 0)
        return -1;
    else
        return 1;
}

double js_math_fround(double a)
{
    return (float)a;
}

JSValue js_math_imul(JSContext *ctx, JSValue *this_val,
                     int argc, JSValue *argv)
{
    int a, b;

    if (JS_ToInt32(ctx, &a, argv[0]))
        return JS_EXCEPTION;
    if (JS_ToInt32(ctx, &b, argv[1]))
        return JS_EXCEPTION;
    /* purposely ignoring overflow */
    return JS_NewInt32(ctx, (uint32_t)a * (uint32_t)b);
}

JSValue js_math_clz32(JSContext *ctx, JSValue *this_val,
                     int argc, JSValue *argv)
{
    uint32_t a, r;

    if (JS_ToUint32(ctx, &a, argv[0]))
        return JS_EXCEPTION;
    if (a == 0)
        r = 32;
    else
        r = clz32(a);
    return JS_NewInt32(ctx, r);
}

JSValue js_math_atan2(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    double y, x;
    
    if (JS_ToNumber(ctx, &y, argv[0]))
        return JS_EXCEPTION;
    if (JS_ToNumber(ctx, &x, argv[1]))
        return JS_EXCEPTION;
    return JS_NewFloat64(ctx, js_atan2(y, x));
}

JSValue js_math_pow(JSContext *ctx, JSValue *this_val,
                    int argc, JSValue *argv)
{
    double y, x;
    
    if (JS_ToNumber(ctx, &x, argv[0]))
        return JS_EXCEPTION;
    if (JS_ToNumber(ctx, &y, argv[1]))
        return JS_EXCEPTION;
    return JS_NewFloat64(ctx, js_pow(x, y));
}

/* xorshift* random number generator by Marsaglia */
uint64_t xorshift64star(uint64_t *pstate)
{
    uint64_t x;
    x = *pstate;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *pstate = x;
    return x * 0x2545F4914F6CDD1D;
}

JSValue js_math_random(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv)
{
    double d;
    uint64_t v;

    v = xorshift64star(&ctx->random_state);
    /* 1.0 <= u.d < 2 */
    d = uint64_as_float64(((uint64_t)0x3ff << 52) | (v >> 12));
    return __JS_NewFloat64(ctx, d - 1.0);
}

/* typed array */

#define JS_TYPED_ARRAY_COUNT (JS_CLASS_FLOAT64_ARRAY - JS_CLASS_UINT8C_ARRAY + 1)

static uint8_t typed_array_size_log2[JS_TYPED_ARRAY_COUNT] = {
    0, 0, 0, 1, 1, 2, 2, 2, 3
};

int JS_ToIndex(JSContext *ctx, uint64_t *plen, JSValue val)
{
    int v;
    /* XXX: should support 53 bit inteers */
    if (JS_ToInt32Sat(ctx, &v, val))
        return -1;
    if (v < 0 || v > JS_SHORTINT_MAX) {
        JS_ThrowRangeError(ctx, "invalid array index");
        return -1;
    }
    *plen = v;
    return 0;
}

JSValue js_array_buffer_alloc(JSContext *ctx, uint64_t len)
{
    JSByteArray *arr;
    JSValue buffer, obj;
    JSGCRef buffer_ref;
    JSObject *p;

    if (len > JS_SHORTINT_MAX)
        return JS_ThrowRangeError(ctx, "invalid array buffer length");
    arr = js_alloc_byte_array(ctx, len);
    if (!arr)
        return JS_EXCEPTION;
    memset(arr->buf, 0, len);
    buffer = JS_VALUE_FROM_PTR(arr);
    JS_PUSH_VALUE(ctx, buffer);
    obj = JS_NewObjectClass(ctx, JS_CLASS_ARRAY_BUFFER, sizeof(JSArrayBuffer));
    JS_POP_VALUE(ctx, buffer);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.array_buffer.byte_buffer = buffer;
    return obj;
}

JSValue js_array_buffer_constructor(JSContext *ctx, JSValue *this_val,
                                    int argc, JSValue *argv)
{
    uint64_t len;
    if (!(argc & FRAME_CF_CTOR))
        return JS_ThrowTypeError(ctx, "must be called with new");
    if (JS_ToIndex(ctx, &len, argv[0]))
        return JS_EXCEPTION;
    return js_array_buffer_alloc(ctx, len);
}

JSValue js_array_buffer_get_byteLength(JSContext *ctx, JSValue *this_val,
                                      int argc, JSValue *argv)
{
    JSObject *p = js_get_object_class(ctx, *this_val, JS_CLASS_ARRAY_BUFFER);
    JSByteArray *arr;
    if (!p)
        return JS_ThrowTypeError(ctx, "expected an ArrayBuffer");
    arr = JS_VALUE_TO_PTR(p->u.array_buffer.byte_buffer);
    return JS_NewShortInt(arr->size);
}

JSValue js_typed_array_base_constructor(JSContext *ctx, JSValue *this_val,
                                        int argc, JSValue *argv)
{
    return JS_ThrowTypeError(ctx, "cannot be called");
}

JSValue js_typed_array_constructor_obj(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv, int magic)
{
    int i, len;
    JSValue val, obj;
    JSGCRef obj_ref;
    JSObject *p;
    
    p = JS_VALUE_TO_PTR(argv[0]);
    if (p->class_id == JS_CLASS_ARRAY) {
        len = p->u.array.len;
    } else if (p->class_id >= JS_CLASS_UINT8C_ARRAY &&
               p->class_id <= JS_CLASS_FLOAT64_ARRAY) {
        len = p->u.typed_array.len;
    } else {
        return JS_ThrowTypeError(ctx, "unsupported object class");
    }
    val = JS_NewShortInt(len);
    obj = js_typed_array_constructor(ctx, NULL, 1 | FRAME_CF_CTOR, &val, magic);
    if (JS_IsException(obj))
        return obj;

    for(i = 0; i < len; i++) {
        JS_PUSH_VALUE(ctx, obj);
        val = JS_GetProperty(ctx, argv[0], JS_NewShortInt(i));
        JS_POP_VALUE(ctx, obj);
        if (JS_IsException(val))
            return val;
        JS_PUSH_VALUE(ctx, obj);
        val = JS_SetPropertyInternal(ctx, obj, JS_NewShortInt(i), val, FALSE);
        JS_POP_VALUE(ctx, obj);
        if (JS_IsException(val))
            return val;
    }
    return obj;
}

JSValue js_typed_array_constructor(JSContext *ctx, JSValue *this_val,
                                   int argc, JSValue *argv, int magic)
{
    int size_log2;
    uint64_t len, offset, byte_length;
    JSObject *p;
    JSByteArray *arr;
    JSValue buffer, obj;
    JSGCRef buffer_ref;
    
    if (!(argc & FRAME_CF_CTOR))
        return JS_ThrowTypeError(ctx, "must be called with new");
    size_log2 = typed_array_size_log2[magic - JS_CLASS_UINT8C_ARRAY];
    if (!JS_IsObject(ctx, argv[0])) {
        if (JS_ToIndex(ctx, &len, argv[0]))
            return JS_EXCEPTION;
        buffer = js_array_buffer_alloc(ctx, len << size_log2);
        if (JS_IsException(buffer))
            return JS_EXCEPTION;
        offset = 0;
    } else {
        p = JS_VALUE_TO_PTR(argv[0]);
        if (p->class_id == JS_CLASS_ARRAY_BUFFER) {
            arr = JS_VALUE_TO_PTR(p->u.array_buffer.byte_buffer);
            byte_length = arr->size;
            if (JS_ToIndex(ctx, &offset, argv[1]))
                return JS_EXCEPTION;
            if ((offset & ((1 << size_log2) - 1)) != 0 ||
                offset > byte_length)
                return JS_ThrowRangeError(ctx, "invalid offset");
            if (JS_IsUndefined(argv[2])) {
                if ((byte_length & ((1 << size_log2) - 1)) != 0)
                    goto invalid_length;
                len = (byte_length - offset) >> size_log2;
            } else {
                if (JS_ToIndex(ctx, &len, argv[2]))
                    return JS_EXCEPTION;
                if ((offset + (len << size_log2)) > byte_length) {
            invalid_length:
                    return JS_ThrowRangeError(ctx, "invalid length");
                }
            }
            buffer = argv[0];
            offset >>= size_log2;
        } else {
            return js_typed_array_constructor_obj(ctx, this_val,
                                                  argc, argv, magic);
        }
    }
    
    JS_PUSH_VALUE(ctx, buffer);
    obj = JS_NewObjectClass(ctx, magic, sizeof(JSTypedArray));
    JS_POP_VALUE(ctx, buffer);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.typed_array.buffer = buffer;
    p->u.typed_array.offset = offset;
    p->u.typed_array.len = len;
    return obj;
}

JSObject *get_typed_array(JSContext *ctx, JSValue val)
{
    JSObject *p;
    if (!JS_IsObject(ctx, val))
        goto fail;
    p = JS_VALUE_TO_PTR(val);
    if (!(p->class_id >= JS_CLASS_UINT8C_ARRAY && p->class_id <= JS_CLASS_FLOAT64_ARRAY)) {
    fail:
        JS_ThrowTypeError(ctx, "not a TypedArray");
        return NULL;
    }
    return p;
}

JSValue js_typed_array_get_length(JSContext *ctx, JSValue *this_val,
                                  int argc, JSValue *argv, int magic)
{
    JSObject *p;
    int size_log2;

    p = get_typed_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    size_log2 = typed_array_size_log2[p->class_id - JS_CLASS_UINT8C_ARRAY];
    switch(magic) {
    default:
    case 0:
        return JS_NewShortInt(p->u.typed_array.len);
    case 1:
        return JS_NewShortInt(p->u.typed_array.len << size_log2);
    case 2:
        return JS_NewShortInt(p->u.typed_array.offset << size_log2);
    case 3:
        return p->u.typed_array.buffer;
    }
}

JSValue js_typed_array_subarray(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    JSObject *p, *p1;
    JSByteArray *arr;
    int start, final, len;
    uint32_t offset, count;
    JSValue obj;
    
    p = get_typed_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    len = p->u.typed_array.len;
    if (JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len))
        return JS_EXCEPTION;
    if (JS_IsUndefined(argv[1])) {
        final = len;
    } else {
        if (JS_ToInt32Clamp(ctx, &final, argv[1], 0, len, len))
            return JS_EXCEPTION;
    }
    p = JS_VALUE_TO_PTR(*this_val);
    offset = p->u.typed_array.offset + start;
    count = max_int(final - start, 0);

    /* check offset and count */
    p1 = JS_VALUE_TO_PTR(p->u.typed_array.buffer);
    arr = JS_VALUE_TO_PTR(p1->u.array_buffer.byte_buffer);
    if (offset + count > arr->size)
        return JS_ThrowRangeError(ctx, "invalid length");
        
    obj = JS_NewObjectClass(ctx, p->class_id, sizeof(JSTypedArray));
    if (JS_IsException(obj))
        return JS_EXCEPTION;
    p = JS_VALUE_TO_PTR(*this_val);
    p1 = JS_VALUE_TO_PTR(obj);
    p1->u.typed_array.buffer = p->u.typed_array.buffer;
    p1->u.typed_array.offset = offset;
    p1->u.typed_array.len = count;
    return obj;
}

JSValue js_typed_array_set(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    JSObject *p, *p1;
    uint32_t dst_len, src_len, i;
    int offset;

    p = get_typed_array(ctx, *this_val);
    if (!p)
        return JS_EXCEPTION;
    if (argc > 1) {
        if (JS_ToInt32Sat(ctx, &offset, argv[1]))
            return JS_EXCEPTION;
    } else {
        offset = 0;
    }
    if (offset < 0)
        goto range_error;
    if (!JS_IsObject(ctx, argv[0]))
        return JS_ThrowTypeErrorNotAnObject(ctx);
    p = JS_VALUE_TO_PTR(*this_val);
    dst_len = p->u.typed_array.len;
    p1 = JS_VALUE_TO_PTR(argv[0]);
    if (p1->class_id >= JS_CLASS_UINT8C_ARRAY &&
        p1->class_id <= JS_CLASS_FLOAT64_ARRAY) {
        src_len = p1->u.typed_array.len;
        if (src_len > dst_len || offset > dst_len - src_len)
            goto range_error;
        if (p1->class_id == p->class_id) {
            JSObject *src_buffer, *dst_buffer;
            JSByteArray *src_arr, *dst_arr;
            int shift = typed_array_size_log2[p->class_id - JS_CLASS_UINT8C_ARRAY];
            dst_buffer = JS_VALUE_TO_PTR(p->u.typed_array.buffer);
            dst_arr = JS_VALUE_TO_PTR(dst_buffer->u.array_buffer.byte_buffer);
            src_buffer = JS_VALUE_TO_PTR(p1->u.typed_array.buffer);
            src_arr = JS_VALUE_TO_PTR(src_buffer->u.array_buffer.byte_buffer);
            /* same type: must copy to preserve float bits */
            memmove(dst_arr->buf + ((p->u.typed_array.offset + offset) << shift),
                    src_arr->buf + (p1->u.typed_array.offset << shift),
                    src_len << shift);
            goto done;
        }
    } else {
        if (js_get_length32(ctx, (uint32_t *)&src_len, argv[0]))
            return JS_EXCEPTION;
        if (src_len > dst_len || offset > dst_len - src_len) {
        range_error:
            return JS_ThrowRangeError(ctx, "invalid array length");
        }
    }
    for(i = 0; i < src_len; i++) {
        JSValue val;
        val = JS_GetPropertyUint32(ctx, argv[0], i);
        if (JS_IsException(val))
            return JS_EXCEPTION;
        val = JS_SetPropertyUint32(ctx, *this_val, offset + i, val);
        if (JS_IsException(val))
            return JS_EXCEPTION;
    }
 done:
    return JS_UNDEFINED;
}

/* Date */

JSValue JS_NewDate(JSContext *ctx, double epoch_ms)
{
    JSValue obj;
    JSObject *p;
    obj = JS_NewObjectClass(ctx, JS_CLASS_DATE, sizeof(JSDate));
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.date.dval = epoch_ms;
    return obj;
}

JSValue js_date_valueOf(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    JSObject *p;
    p = js_get_object_class(ctx, *this_val, JS_CLASS_DATE);
    if (!p) {
        JS_ThrowTypeError(ctx, "not a Date object");
        return JS_EXCEPTION;
    }
    return __JS_NewFloat64(ctx, p->u.date.dval);
}

/* global */

JSValue js_global_eval(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv)
{
    JSValue val;
    
    if (!JS_IsString(ctx, argv[0]))
        return argv[0];
    val = JS_Parse2(ctx, argv[0], NULL, 0, "<input>", JS_EVAL_RETVAL);
    if (JS_IsException(val))
        return val;
    return JS_Run(ctx, val);
}

JSValue js_global_isNaN(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    double d;
    if (unlikely(JS_ToNumber(ctx, &d, argv[0])))
        return JS_EXCEPTION;
    return JS_NewBool(isnan(d));
}

JSValue js_global_isFinite(JSContext *ctx, JSValue *this_val,
                                  int argc, JSValue *argv)
{
    double d;
    if (unlikely(JS_ToNumber(ctx, &d, argv[0])))
        return JS_EXCEPTION;
    return JS_NewBool(isfinite(d));
}

/* JSON */

JSValue js_json_parse(JSContext *ctx, JSValue *this_val,
                      int argc, JSValue *argv)
{
    JSValue val;
    
    val = JS_ToString(ctx, argv[0]);
    if (JS_IsException(val))
        return val;
    return JS_Parse2(ctx, val, NULL, 0, "<input>", JS_EVAL_JSON);
}

int js_to_quoted_string(JSContext *ctx, StringBuffer *b, JSValue str)
{
    int i, c;
    JSStringCharBuf buf;
    JSString *p;
    JSGCRef str_ref;
    size_t clen;

    JS_PUSH_VALUE(ctx, str);
    string_buffer_putc(ctx, b, '\"');

    i = 0;
    for(;;) {
        /* XXX: inefficient */
        p = get_string_ptr(ctx, &buf, str_ref.val);
        if (i >= p->len)
            break;
        c = utf8_get(p->buf + i, &clen);
        i += clen;

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
            string_buffer_putc(ctx, b, '\\');
            string_buffer_putc(ctx, b, c);
            break;
        default:
            if (c < 32 || (c >= 0xd800 && c < 0xe000)) {
                char buf[7];
                js_snprintf(buf, sizeof(buf), "\\u%04x", c);
                string_buffer_puts(ctx, b, buf);
            } else {
                string_buffer_putc(ctx, b, c);
            }
            break;
        }
    }
    string_buffer_putc(ctx, b, '\"');
    JS_POP_VALUE(ctx, str);
    return 0;
}

#define JSON_REC_SIZE 3

int check_circular_ref(JSContext *ctx, JSValue *stack_top, JSValue val)
{
    JSValue *sp;
    for(sp = ctx->sp; sp < stack_top; sp += JSON_REC_SIZE) {
        if (sp[0] == val) {
            JS_ThrowTypeError(ctx, "circular reference");
            return -1;
        }
    }
    return 0;
}

/* XXX: no space nor replacer */
JSValue js_json_stringify(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv)
{
    JSValue obj, *stack_top;
    StringBuffer b_s, *b = &b_s;
    int idx, ret;
    
#if 0
    if (JS_IsNumber(ctx, *pspace)) {
        int n;
        if (JS_ToInt32Clamp(ctx, &n, *pspace, 0, 10, 0))
            return JS_EXCEPTION;
        *pspace = JS_NewStringLen(ctx, "          ", n);
    } else if (JS_IsString(ctx, *pspace)) {
        *pspace = js_sub_string(ctx, *pspace, 0, 10);
    } else {
        *pspace = js_get_atom(ctx, JS_ATOM_empty);
    }
#endif
    string_buffer_push(ctx, b, 0);
    stack_top = ctx->sp;

    ret = JS_StackCheck(ctx, JSON_REC_SIZE);
    if (ret)
        goto fail;
    *--ctx->sp = JS_NULL; /* keys */
    *--ctx->sp = JS_NewShortInt(0); /* prop index */
    *--ctx->sp = argv[0]; /* object */
    
    while (ctx->sp < stack_top) {
        obj = ctx->sp[0];
        if (JS_IsFunction(ctx, obj)) {
            goto output_null;
        } else if (JS_IsObject(ctx, obj)) {
            JSObject *p = JS_VALUE_TO_PTR(obj);
            idx = JS_VALUE_GET_INT(ctx->sp[1]);
            if (p->class_id == JS_CLASS_ARRAY) {
                JSValueArray *arr;
                JSValue val;

                /* array */
                if (idx == 0)
                    string_buffer_putc(ctx, b, '[');
                p = JS_VALUE_TO_PTR(ctx->sp[0]);
                if (idx >= p->u.array.len) {
                    /* end of array */
                    string_buffer_putc(ctx, b, ']');
                    ctx->sp += JSON_REC_SIZE;
                } else {
                    if (idx != 0)
                        string_buffer_putc(ctx, b, ',');
                    ctx->sp[1] = JS_NewShortInt(idx + 1);
                    ret = JS_StackCheck(ctx, JSON_REC_SIZE);
                    if (ret)
                        goto fail;
                    p = JS_VALUE_TO_PTR(ctx->sp[0]);
                    arr = JS_VALUE_TO_PTR(p->u.array.tab);
                    val = arr->arr[idx];
                    if (check_circular_ref(ctx, stack_top, val))
                        goto fail;
                    *--ctx->sp = JS_NULL;
                    *--ctx->sp = JS_NewShortInt(0);
                    *--ctx->sp = val;
                }
            } else {
                JSValueArray *arr;
                JSValue val, prop;
                JSGCRef val_ref;
                int saved_idx;
                
                /* object */
                if (idx == 0) {
                    string_buffer_putc(ctx, b, '{');
                    ctx->sp[2] = js_object_keys(ctx, NULL, 1, &ctx->sp[0]);
                    if (JS_IsException(ctx->sp[2]))
                        goto fail;
                }
                saved_idx = idx;
                for(;;) {
                    p = JS_VALUE_TO_PTR(ctx->sp[2]); /* keys */
                    if (idx >= p->u.array.len) {
                        /* end of object */
                        string_buffer_putc(ctx, b, '}');
                        ctx->sp += JSON_REC_SIZE;
                        goto end_obj;
                    } else {
                        arr = JS_VALUE_TO_PTR(p->u.array.tab);
                        prop = JS_ToPropertyKey(ctx, arr->arr[idx]);
                        val = JS_GetProperty(ctx, ctx->sp[0], prop);
                        if (JS_IsException(val))
                            goto fail;
                        /* skip undefined properties */
                        if (!JS_IsUndefined(val))
                            break;
                        idx++;
                    }
                }
                JS_PUSH_VALUE(ctx, val);
                if (saved_idx != 0)
                    string_buffer_putc(ctx, b, ',');
                ctx->sp[1] = JS_NewShortInt(idx + 1);
                p = JS_VALUE_TO_PTR(ctx->sp[2]);
                arr = JS_VALUE_TO_PTR(p->u.array.tab);
                ret = js_to_quoted_string(ctx, b, arr->arr[idx]);
                string_buffer_putc(ctx, b, ':');
                ret |= JS_StackCheck(ctx, JSON_REC_SIZE);
                JS_POP_VALUE(ctx, val);
                if (ret)
                    goto fail;
                if (check_circular_ref(ctx, stack_top, val))
                    goto fail;
                *--ctx->sp = JS_NULL;
                *--ctx->sp = JS_NewShortInt(0);
                *--ctx->sp = val;
            end_obj: ;
            }
        } else if (JS_IsNumber(ctx, obj)) {
            double d;
            ret = JS_ToNumber(ctx, &d, obj);
            if (ret)
                goto fail;
            if (!isfinite(d))
                goto output_null;
            goto to_string;
        } else if (JS_IsBool(obj)) {
        to_string:
            if (string_buffer_concat(ctx, b, obj))
                goto fail;
            ctx->sp += JSON_REC_SIZE;
        } else if (JS_IsString(ctx, obj)) {
            if (js_to_quoted_string(ctx, b, obj))
                goto fail;
            ctx->sp += JSON_REC_SIZE;
        } else {
        output_null:
            string_buffer_concat(ctx, b, js_get_atom(ctx, JS_ATOM_null));
            ctx->sp += JSON_REC_SIZE;
        }
    }
    return string_buffer_pop(ctx, b);
    
 fail:
    ctx->sp = stack_top;
    string_buffer_pop(ctx, b);
    return JS_EXCEPTION;
}

/**********************************************************************/
/* regexp */


const REOpCode reopcode_info[REOP_COUNT] = {
#ifdef DUMP_REOP
#define REDEF(id, size) { #id, size },
#else
#define REDEF(id, size) { size },
#endif
#include "mquickjs_opcode.h"
#undef REDEF
};
int lre_get_capture_count(const uint8_t *bc_buf)
{
    return bc_buf[RE_HEADER_CAPTURE_COUNT];
}

int lre_get_alloc_count(const uint8_t *bc_buf)
{
    return bc_buf[RE_HEADER_CAPTURE_COUNT] * 2 + bc_buf[RE_HEADER_REGISTER_COUNT];
}

int lre_get_flags(const uint8_t *bc_buf)
{
    return get_u16(bc_buf + RE_HEADER_FLAGS);
}

#ifdef DUMP_REOP
__maybe_unused void lre_dump_bytecode(const uint8_t *buf, int buf_len)
{
    int pos, len, opcode, bc_len, re_flags;
    uint32_t val, val2;

    assert(buf_len >= RE_HEADER_LEN);
    re_flags = lre_get_flags(buf);
    bc_len = buf_len - RE_HEADER_LEN;

    printf("flags: 0x%x capture_count=%d reg_count=%d bytecode_len=%d\n",
           re_flags, buf[RE_HEADER_CAPTURE_COUNT], buf[RE_HEADER_REGISTER_COUNT],
           bc_len);

    buf += RE_HEADER_LEN;

    pos = 0;
    while (pos < bc_len) {
        printf("%5u: ", pos);
        opcode = buf[pos];
        len = reopcode_info[opcode].size;
        if (opcode >= REOP_COUNT) {
            printf(" invalid opcode=0x%02x\n", opcode);
            break;
        }
        if ((pos + len) > bc_len) {
            printf(" buffer overflow (opcode=0x%02x)\n", opcode);
            break;
        }
        printf("%s", reopcode_info[opcode].name);
        switch(opcode) {
        case REOP_char1:
        case REOP_char2:
        case REOP_char3:
        case REOP_char4:
            {
                int i, n;
                n = opcode - REOP_char1 + 1;
                for(i = 0; i < n; i++) {
                    val = buf[pos + 1 + i];
                    if (val >= ' ' && val <= 126)
                        printf(" '%c'", val);
                    else
                        printf(" 0x%2x", val);
                }
            }
            break;
        case REOP_goto:
        case REOP_split_goto_first:
        case REOP_split_next_first:
        case REOP_lookahead:
        case REOP_negative_lookahead:
            val = get_u32(buf + pos + 1);
            val += (pos + 5);
            printf(" %u", val);
            break;
        case REOP_loop:
            val2 = buf[pos + 1];
            val = get_u32(buf + pos + 2);
            val += (pos + 6);
            printf(" r%u, %u", val2, val);
            break;
        case REOP_loop_split_goto_first:
        case REOP_loop_split_next_first:
        case REOP_loop_check_adv_split_goto_first:
        case REOP_loop_check_adv_split_next_first:
            {
                uint32_t limit;
                val2 = buf[pos + 1];
                limit = get_u32(buf + pos + 2);
                val = get_u32(buf + pos + 6);
                val += (pos + 10);
                printf(" r%u, %u, %u", val2, limit, val);
            }
            break;
        case REOP_save_start:
        case REOP_save_end:
        case REOP_back_reference:
        case REOP_back_reference_i:
            printf(" %u", buf[pos + 1]);
            break;
        case REOP_save_reset:
            printf(" %u %u", buf[pos + 1], buf[pos + 2]);
            break;
        case REOP_set_i32:
            val = buf[pos + 1];
            val2 = get_u32(buf + pos + 2);
            printf(" r%u, %d", val, val2);
            break;
        case REOP_set_char_pos:
        case REOP_check_advance:
            val = buf[pos + 1];
            printf(" r%u", val);
            break;
        case REOP_range8:
            {
                int n, i;
                n = buf[pos + 1];
                len += n * 2;
                for(i = 0; i < n * 2; i++) {
                    val = buf[pos + 2 + i];
                    printf(" 0x%02x", val);
                }
            }
            break;
        case REOP_range:
            {
                int n, i;
                n = get_u16(buf + pos + 1);
                len += n * 8;
                for(i = 0; i < n * 2; i++) {
                    val = get_u32(buf + pos + 3 + i * 4);
                    printf(" 0x%05x", val);
                }
            }
            break;
        default:
            break;
        }
        printf("\n");
        pos += len;
    }
}
#endif

void re_emit_op(JSParseState *s, int op)
{
    emit_u8(s, op);
}

void re_emit_op_u8(JSParseState *s, int op, uint32_t val)
{
    emit_u8(s, op);
    emit_u8(s, val);
}

void re_emit_op_u16(JSParseState *s, int op, uint32_t val)
{
    emit_u8(s, op);
    emit_u16(s, val);
}

/* return the offset of the u32 value */
int re_emit_op_u32(JSParseState *s, int op, uint32_t val)
{
    int pos;
    emit_u8(s, op);
    pos = s->byte_code_len;
    emit_u32(s, val);
    return pos;
}

int re_emit_goto(JSParseState *s, int op, uint32_t val)
{
    int pos;
    emit_u8(s, op);
    pos = s->byte_code_len;
    emit_u32(s, val - (pos + 4));
    return pos;
}

int re_emit_goto_u8(JSParseState *s, int op, uint32_t arg, uint32_t val)
{
    int pos;
    emit_u8(s, op);
    emit_u8(s, arg);
    pos = s->byte_code_len;
    emit_u32(s, val - (pos + 4));
    return pos;
}

int re_emit_goto_u8_u32(JSParseState *s, int op, uint32_t arg0, uint32_t arg1, uint32_t val)
{
    int pos;
    emit_u8(s, op);
    emit_u8(s, arg0);
    emit_u32(s, arg1);
    pos = s->byte_code_len;
    emit_u32(s, val - (pos + 4));
    return pos;
}

void re_emit_char(JSParseState *s, int c)
{
    uint8_t buf[4];
    size_t n, i;
    n = unicode_to_utf8(buf, c);
    re_emit_op(s, REOP_char1 + n - 1);
    for(i = 0; i < n; i++)
        emit_u8(s, buf[i]);
}

void re_parse_expect(JSParseState *s, int c)
{
    if (s->source_buf[s->buf_pos] != c)
        return js_parse_error(s, "expecting '%c'", c);
    s->buf_pos++;
}

/* return JS_SHORTINT_MAX in case of overflow */
int parse_digits(const uint8_t **pp)
{
    const uint8_t *p;
    uint64_t v;
    int c;

    p = *pp;
    v = 0;
    for(;;) {
        c = *p;
        if (c < '0' || c > '9')
            break;
        v = v * 10 + c - '0';
        if (v >= JS_SHORTINT_MAX)
            v = JS_SHORTINT_MAX;
        p++;
    }
    *pp = p;
    return v;
}

/* need_check_adv: false if the opcodes always advance the char pointer
   need_capture_init: true if all the captures in the atom are not set
*/
BOOL re_need_check_adv_and_capture_init(BOOL *pneed_capture_init, const uint8_t *bc_buf, int bc_buf_len)
{
    int pos, opcode, len;
    uint32_t val;
    BOOL need_check_adv, need_capture_init;

    need_check_adv = TRUE;
    need_capture_init = FALSE;
    pos = 0;
    while (pos < bc_buf_len) {
        opcode = bc_buf[pos];
        len = reopcode_info[opcode].size;
        switch(opcode) {
        case REOP_range8:
            val = bc_buf[pos + 1];
            len += val * 2;
            need_check_adv = FALSE;
            break;
        case REOP_range:
            val = get_u16(bc_buf + pos + 1);
            len += val * 8;
            need_check_adv = FALSE;
            break;
        case REOP_char1:
        case REOP_char2:
        case REOP_char3:
        case REOP_char4:
        case REOP_dot:
        case REOP_any:
        case REOP_space:
        case REOP_not_space:
            need_check_adv = FALSE;
            break;
        case REOP_line_start:
        case REOP_line_start_m:
        case REOP_line_end:
        case REOP_line_end_m:
        case REOP_set_i32:
        case REOP_set_char_pos:
        case REOP_word_boundary:
        case REOP_not_word_boundary:
            /* no effect */
            break;
        case REOP_save_start:
        case REOP_save_end:
        case REOP_save_reset:
            break;
        default:
            /* safe behavior: we cannot predict the outcome */
            need_capture_init = TRUE;
            goto done;
        }
        pos += len;
    }
 done:
    *pneed_capture_init = need_capture_init;
    return need_check_adv;
}

/* return the character or a class range (>= CLASS_RANGE_BASE) if inclass
   = TRUE */
int get_class_atom(JSParseState *s, BOOL inclass)
{
    const uint8_t *p;
    uint32_t c;
    int ret;
    size_t len;
    
    p = s->source_buf + s->buf_pos;
    c = *p;
    switch(c) {
    case '\\':
        p++;
        c = *p++;
        switch(c) {
        case 'd':
            c = CHAR_RANGE_d;
            goto class_range;
        case 'D':
            c = CHAR_RANGE_D;
            goto class_range;
        case 's':
            c = CHAR_RANGE_s;
            goto class_range;
        case 'S':
            c = CHAR_RANGE_S;
            goto class_range;
        case 'w':
            c = CHAR_RANGE_w;
            goto class_range;
        case 'W':
            c = CHAR_RANGE_W;
        class_range:
            c += CLASS_RANGE_BASE;
            break;
        case 'c':
            c = *p;
            if ((c >= 'a' && c <= 'z') ||
                (c >= 'A' && c <= 'Z') ||
                (((c >= '0' && c <= '9') || c == '_') &&
                 inclass && !s->is_unicode)) {   /* Annex B.1.4 */
                c &= 0x1f;
                p++;
            } else if (s->is_unicode) {
                goto invalid_escape;
            } else {
                /* otherwise return '\' and 'c' */
                p--;
                c = '\\';
            }
            break;
        case '-':
            if (!inclass && s->is_unicode)
                goto invalid_escape;
            break;
        case '^':
        case '$':
        case '\\':
        case '.':
        case '*':
        case '+':
        case '?':
        case '(':
        case ')':
        case '[':
        case ']':
        case '{':
        case '}':
        case '|':
        case '/':
            /* always valid to escape these characters */
            break;
        default:
            p--;
            ret = js_parse_escape(p, &len);
            if (ret < 0) {
                if (s->is_unicode) {
                invalid_escape:
                    s->buf_pos = p - s->source_buf;
                    js_parse_error(s, "invalid escape sequence in regular expression");
                } else {
                    goto normal_char;
                }
            }
            p += len;
            c = ret;
            break;
        }
        break;
    case '\0':
    case '/': /* safety for end of regexp in JS parser */
        if ((p - s->source_buf) >= s->buf_len)
            js_parse_error(s, "unexpected end");
        goto normal_char;
    default:
    normal_char:
        /* normal char */
        ret = unicode_from_utf8(p, UTF8_CHAR_LEN_MAX, &len);
        /* Note: should not fail with normal JS strings */
        if (ret < 0)
            js_parse_error(s, "malformed unicode char"); 
        p += len;
        c = ret;
        break;
    }
    s->buf_pos = p - s->source_buf;
    return c;
}

/* code point ranges for Zs,Zl or Zp property */
static const uint16_t char_range_s[] = {
    0x0009, 0x000D + 1,
    0x0020, 0x0020 + 1,
    0x00A0, 0x00A0 + 1,
    0x1680, 0x1680 + 1,
    0x2000, 0x200A + 1,
    /* 2028;LINE SEPARATOR;Zl;0;WS;;;;;N;;;;; */
    /* 2029;PARAGRAPH SEPARATOR;Zp;0;B;;;;;N;;;;; */
    0x2028, 0x2029 + 1,
    0x202F, 0x202F + 1,
    0x205F, 0x205F + 1,
    0x3000, 0x3000 + 1,
    /* FEFF;ZERO WIDTH NO-BREAK SPACE;Cf;0;BN;;;;;N;BYTE ORDER MARK;;;; */
    0xFEFF, 0xFEFF + 1,
};

static const uint16_t char_range_w[] = {
    0x0030, 0x0039 + 1,
    0x0041, 0x005A + 1,
    0x005F, 0x005F + 1,
    0x0061, 0x007A + 1,
};

void re_emit_range_base1(JSParseState *s, const uint16_t *tab, int n)
{
    int i;
    for(i = 0; i < n; i++)
        emit_u32(s, tab[i]);
}

void re_emit_range_base(JSParseState *s, int c)
{
    BOOL invert;
    invert = c & 1;
    if (invert)
        emit_u32(s, 0);
    switch(c & ~1) {
    case CHAR_RANGE_d:
        emit_u32(s, 0x30);
        emit_u32(s, 0x39 + 1);
        break;
    case CHAR_RANGE_s:
        re_emit_range_base1(s, char_range_s, countof(char_range_s));
        break;
    case CHAR_RANGE_w:
        re_emit_range_base1(s, char_range_w, countof(char_range_w));
        break;
    default:
        abort();
    }
    if (invert)
        emit_u32(s, 0x110000);
}

int range_sort_cmp(size_t i1, size_t i2, void *opaque)
{
    uint8_t *tab = opaque;
    return get_u32(&tab[8 * i1]) - get_u32(&tab[8 * i2]);
}

void range_sort_swap(size_t i1, size_t i2, void *opaque)
{
    uint8_t *tab = opaque;
    uint64_t tmp;
    tmp = get_u64(&tab[8 * i1]);
    put_u64(&tab[8 * i1], get_u64(&tab[8 * i2]));
    put_u64(&tab[8 * i2], tmp);
}

/* merge consecutive intervals, remove empty intervals and handle overlapping intervals */ 
int range_compress(uint8_t *tab, int len)
{
    int i, j;
    uint32_t start, end, start2, end2;

    i = 0;
    j = 0;
    while (i < len) {
        start = get_u32(&tab[8 * i]);
        end = get_u32(&tab[8 * i + 4]);
        if (start == end) {
            /* empty interval : remove */
        } else if ((i + 1) < len) {
            start2 = get_u32(&tab[8 * i + 8]);
            end2 = get_u32(&tab[8 * i + 12]);
            if (end < start2) {
                goto copy;
            } else {
                /* union of the intervals */
                put_u32(&tab[8 * i + 8], start);
                put_u32(&tab[8 * i + 12], max_uint32(end, end2));
            }
        } else {
        copy:
            put_u32(&tab[8 * j], start);
            put_u32(&tab[8 * j + 4], end);
            j++;
        }
        i++;
    }
    return j;
}

void re_range_optimize(JSParseState *s, int range_start, BOOL invert)
{
    int n, n1;
    JSByteArray *arr;

    n = (unsigned)(s->byte_code_len - range_start) / 8;

    arr = JS_VALUE_TO_PTR(s->byte_code);
    rqsort_idx(n, range_sort_cmp, range_sort_swap, arr->buf + range_start);

    /* must compress before inverting */
    n1 = range_compress(arr->buf + range_start, n);
    s->byte_code_len -= (n - n1) * 8;

    if (invert) {
        emit_insert(s, range_start, 4);
        arr = JS_VALUE_TO_PTR(s->byte_code);
        put_u32(arr->buf + range_start, 0);
        emit_u32(s, 0x110000);
        arr = JS_VALUE_TO_PTR(s->byte_code);
        n = n1 + 1;
        n1 = range_compress(arr->buf + range_start, n);
        s->byte_code_len -= (n - n1) * 8;
    }
    n = n1;
    
    if (n > 65534)
        js_parse_error(s, "range too big");

    /* compress to 8 bit if possible */
    /* XXX: adjust threshold */
    if (n > 0 && n < 16) {
        uint8_t *tab = arr->buf + range_start;
        int c, i;
        c = get_u32(&tab[8 * (n - 1) + 4]);
        if (c < 254 || (c == 0x110000 &&
                        get_u32(&tab[8 * (n - 1)]) < 254)) {
            s->byte_code_len = range_start - 3;
            re_emit_op_u8(s, REOP_range8, n);
            for(i = 0; i < 2 * n; i++) {
                c = get_u32(&tab[4 * i]);
                if (c == 0x110000)
                    c = 0xff;
                emit_u8(s, c);
            }
            goto done;
        }
    }
    
    put_u16(arr->buf + range_start - 2, n);
 done: ;
}

/* add the intersection of the two intervals and if offset != 0 the
   translated interval */
void add_interval_intersect(JSParseState *s, uint32_t start, uint32_t end, uint32_t start1, uint32_t end1, int offset)
{
    start = max_uint32(start, start1);
    end = min_uint32(end, end1);
    if (start < end) {
        emit_u32(s, start);
        emit_u32(s, end);
        if (offset != 0) {
            emit_u32(s, start + offset);
            emit_u32(s, end + offset);
        }
    }
}

void re_parse_char_class(JSParseState *s)
{
    uint32_t c1, c2;
    BOOL invert;
    int range_start;
    
    s->buf_pos++; /* skip '[' */

    invert = FALSE;
    if (s->source_buf[s->buf_pos] == '^') {
        s->buf_pos++;
        invert = TRUE;
    }
    
    re_emit_op_u16(s, REOP_range, 0);
    range_start = s->byte_code_len;
 
    for(;;) {
        if (s->source_buf[s->buf_pos] == ']')
            break;

        c1 = get_class_atom(s, TRUE);
        if (s->source_buf[s->buf_pos] == '-' && s->source_buf[s->buf_pos + 1] != ']') {
            s->buf_pos++;
            if (c1 >= CLASS_RANGE_BASE) 
                goto invalid_class_range;
            c2 = get_class_atom(s, TRUE);
            if (c2 >= CLASS_RANGE_BASE) 
                goto invalid_class_range;
            if (c2 < c1) {
            invalid_class_range:
                js_parse_error(s, "invalid class range");
            }
            goto add_range;
        } else {
            if (c1 >= CLASS_RANGE_BASE) {
                re_emit_range_base(s, c1 - CLASS_RANGE_BASE);
            } else {
                c2 = c1;
            add_range:
                c2++;
                if (s->ignore_case) {
                    /* add the intervals exclude the cased characters */
                    add_interval_intersect(s, c1, c2, 0, 'A', 0);
                    add_interval_intersect(s, c1, c2, 'Z' + 1, 'a', 0);
                    add_interval_intersect(s, c1, c2, 'z' + 1, INT32_MAX, 0);
                    /* include all the possible cases */
                    add_interval_intersect(s, c1, c2, 'A', 'Z' + 1, 32);
                    add_interval_intersect(s, c1, c2, 'a', 'z' + 1, -32);
                } else {
                    emit_u32(s, c1);
                    emit_u32(s, c2);
                }
            }
        }
    }
    s->buf_pos++;    /* skip ']' */
    re_range_optimize(s, range_start, invert);
}

void re_parse_quantifier(JSParseState *s, int last_atom_start, int last_capture_count)
{
    int c, quant_min, quant_max;
    JSByteArray *arr;
    BOOL greedy;
    const uint8_t *p;
        
    p = s->source_buf + s->buf_pos;
    c = *p;
    switch(c) {
    case '*':
        p++;
        quant_min = 0;
        quant_max = JS_SHORTINT_MAX;
        goto quantifier;
    case '+':
        p++;
        quant_min = 1;
        quant_max = JS_SHORTINT_MAX;
        goto quantifier;
    case '?':
        p++;
        quant_min = 0;
        quant_max = 1;
        goto quantifier;
    case '{':
        {
            if (!is_digit(p[1]))
                goto invalid_quant_count;
            p++;
            quant_min = parse_digits(&p);
            quant_max = quant_min;
            if (*p == ',') {
                p++;
                if (is_digit(*p)) {
                    quant_max = parse_digits(&p);
                    if (quant_max < quant_min) {
                    invalid_quant_count:
                        js_parse_error(s, "invalid repetition count");
                    }
                } else {
                    quant_max = JS_SHORTINT_MAX; /* infinity */
                }
            }
            s->buf_pos = p - s->source_buf;
            re_parse_expect(s, '}');
            p = s->source_buf + s->buf_pos;
        }
    quantifier:
        greedy = TRUE;

        if (*p == '?') {
            p++;
            greedy = FALSE;
        }
        s->buf_pos = p - s->source_buf;

        if (last_atom_start < 0)
            js_parse_error(s, "nothing to repeat");
        {
            BOOL need_capture_init, add_zero_advance_check;
            int len, pos;
                
            /* the spec tells that if there is no advance when
               running the atom after the first quant_min times,
               then there is no match. We remove this test when we
               are sure the atom always advances the position. */
            arr = JS_VALUE_TO_PTR(s->byte_code);
            add_zero_advance_check =
                re_need_check_adv_and_capture_init(&need_capture_init,
                                                   arr->buf + last_atom_start,
                                                   s->byte_code_len - last_atom_start);
            
            /* general case: need to reset the capture at each
               iteration. We don't do it if there are no captures
               in the atom or if we are sure all captures are
               initialized in the atom. If quant_min = 0, we still
               need to reset once the captures in case the atom
               does not match. */
            if (need_capture_init && last_capture_count != s->capture_count) {
                emit_insert(s, last_atom_start, 3);
                int pos = last_atom_start;
                arr = JS_VALUE_TO_PTR(s->byte_code);
                arr->buf[pos++] = REOP_save_reset;
                arr->buf[pos++] = last_capture_count;
                arr->buf[pos++] = s->capture_count - 1;
            }

            len = s->byte_code_len - last_atom_start;
            if (quant_min == 0) {
                /* need to reset the capture in case the atom is
                   not executed */
                if (!need_capture_init && last_capture_count != s->capture_count) {
                    emit_insert(s, last_atom_start, 3);
                    arr = JS_VALUE_TO_PTR(s->byte_code);
                    arr->buf[last_atom_start++] = REOP_save_reset;
                    arr->buf[last_atom_start++] = last_capture_count;
                    arr->buf[last_atom_start++] = s->capture_count - 1;
                }
                if (quant_max == 0) {
                    s->byte_code_len = last_atom_start;
                } else if (quant_max == 1 || quant_max == JS_SHORTINT_MAX) {
                    BOOL has_goto = (quant_max == JS_SHORTINT_MAX);
                    emit_insert(s, last_atom_start, 5 + add_zero_advance_check * 2);
                    arr = JS_VALUE_TO_PTR(s->byte_code);
                    arr->buf[last_atom_start] = REOP_split_goto_first +
                        greedy;
                    put_u32(arr->buf + last_atom_start + 1,
                            len + 5 * has_goto + add_zero_advance_check * 2 * 2);
                    if (add_zero_advance_check) {
                        arr->buf[last_atom_start + 1 + 4] = REOP_set_char_pos;
                        arr->buf[last_atom_start + 1 + 4 + 1] = 0;
                        re_emit_op_u8(s, REOP_check_advance, 0);
                    }
                    if (has_goto)
                        re_emit_goto(s, REOP_goto, last_atom_start);
                } else {
                    emit_insert(s, last_atom_start, 11 + add_zero_advance_check * 2);
                    pos = last_atom_start;
                    arr = JS_VALUE_TO_PTR(s->byte_code);
                    arr->buf[pos++] = REOP_split_goto_first + greedy;
                    put_u32(arr->buf + pos, 6 + add_zero_advance_check * 2 + len + 10);
                    pos += 4;

                    arr->buf[pos++] = REOP_set_i32;
                    arr->buf[pos++] = 0;
                    put_u32(arr->buf + pos, quant_max);
                    pos += 4;
                    last_atom_start = pos;
                    if (add_zero_advance_check) {
                        arr->buf[pos++] = REOP_set_char_pos;
                        arr->buf[pos++] = 0;
                    }
                    re_emit_goto_u8_u32(s, (add_zero_advance_check ? REOP_loop_check_adv_split_next_first : REOP_loop_split_next_first) - greedy, 0, quant_max, last_atom_start);
                }
            } else if (quant_min == 1 && quant_max == JS_SHORTINT_MAX &&
                       !add_zero_advance_check) {
                re_emit_goto(s, REOP_split_next_first - greedy,
                             last_atom_start);
            } else {
                if (quant_min == quant_max)
                    add_zero_advance_check = FALSE;
                emit_insert(s, last_atom_start, 6 + add_zero_advance_check * 2);
                /* Note: we assume the string length is < JS_SHORTINT_MAX */
                pos = last_atom_start;
                arr = JS_VALUE_TO_PTR(s->byte_code);
                arr->buf[pos++] = REOP_set_i32;
                arr->buf[pos++] = 0;
                put_u32(arr->buf + pos, quant_max);
                pos += 4;
                last_atom_start = pos;
                if (add_zero_advance_check) {
                    arr->buf[pos++] = REOP_set_char_pos;
                    arr->buf[pos++] = 0;
                }
                if (quant_min == quant_max) {
                    /* a simple loop is enough */
                    re_emit_goto_u8(s, REOP_loop, 0, last_atom_start);
                } else {
                    re_emit_goto_u8_u32(s, (add_zero_advance_check ? REOP_loop_check_adv_split_next_first : REOP_loop_split_next_first) - greedy, 0, quant_max - quant_min, last_atom_start);
                }
            }
            last_atom_start = -1;
        }
        break;
    default:
        break;
    }
}

/* return the number of bytes if char otherwise 0 */
int re_is_char(const uint8_t *buf, int start, int end)
{
    int n;
    if (!(buf[start] >= REOP_char1 && buf[start] <= REOP_char4))
        return 0;
    n = buf[start] - REOP_char1 + 1;
    if ((end - start) != (n + 1))
        return 0;
    return n;
}

int re_parse_alternative(JSParseState *s, int state, int dummy_param)
{
    int term_start, last_term_start, last_atom_start, last_capture_count, c, n1, n2, i;
    JSByteArray *arr;
    
    PARSE_START3();

    last_term_start = -1;
    for(;;) {
        if (s->buf_pos >= s->buf_len)
            break;
        term_start = s->byte_code_len;

        last_atom_start = -1;
        last_capture_count = 0;
        c = s->source_buf[s->buf_pos];
        switch(c) {
        case '|':
        case ')':
            goto done;
        case '^':
            s->buf_pos++;
            re_emit_op(s, s->multi_line ? REOP_line_start_m : REOP_line_start);
            break;
        case '$':
            s->buf_pos++;
            re_emit_op(s, s->multi_line ? REOP_line_end_m : REOP_line_end);
            break;
        case '.':
            s->buf_pos++;
            last_atom_start = s->byte_code_len;
            last_capture_count = s->capture_count;
            re_emit_op(s, s->dotall ? REOP_any : REOP_dot);
            break;
        case '{': 
            /* As an extension (see ES6 annex B), we accept '{' not
               followed by digits as a normal atom */
            if (!s->is_unicode && !is_digit(s->source_buf[s->buf_pos + 1]))
                goto parse_class_atom;
            /* fall thru */
        case '*':
        case '+':
        case '?':
            js_parse_error(s, "nothing to repeat");
        case '(':
            if (s->source_buf[s->buf_pos + 1] == '?') {
                c = s->source_buf[s->buf_pos + 2];
                if (c == ':') {
                    s->buf_pos += 3;
                    last_atom_start = s->byte_code_len;
                    last_capture_count = s->capture_count;
                    PARSE_CALL_SAVE4(s, 0, re_parse_disjunction, 0,
                                     last_term_start, term_start, last_atom_start, last_capture_count);
                    re_parse_expect(s, ')');
                } else if ((c == '=' || c == '!')) {
                    int is_neg, pos;
                    is_neg = (c == '!');
                    s->buf_pos += 3;
                    /* lookahead */
                    pos = re_emit_op_u32(s, REOP_lookahead + is_neg, 0);
                    PARSE_CALL_SAVE6(s, 1, re_parse_disjunction, 0,
                                     last_term_start, term_start, last_atom_start, last_capture_count,
                                     is_neg, pos);
                    re_parse_expect(s, ')');
                    re_emit_op(s, REOP_lookahead_match + is_neg);
                    /* jump after the 'match' after the lookahead is successful */
                    arr = JS_VALUE_TO_PTR(s->byte_code);
                    put_u32(arr->buf + pos, s->byte_code_len - (pos + 4));
                } else {
                    js_parse_error(s, "invalid group");
                }
            } else {
                int capture_index;
                s->buf_pos++;
                /* capture without group name */
                if (s->capture_count >= CAPTURE_COUNT_MAX)
                    js_parse_error(s, "too many captures");
                last_atom_start = s->byte_code_len;
                last_capture_count = s->capture_count;
                capture_index = s->capture_count++;
                re_emit_op_u8(s, REOP_save_start, capture_index);

                PARSE_CALL_SAVE5(s, 2, re_parse_disjunction, 0,
                                 last_term_start, term_start, last_atom_start, last_capture_count,
                                 capture_index);

                re_emit_op_u8(s, REOP_save_end, capture_index);

                re_parse_expect(s, ')');
            }
            break;
        case '\\':
            switch(s->source_buf[s->buf_pos + 1]) {
            case 'b':
            case 'B':
                if (s->source_buf[s->buf_pos + 1] != 'b') {
                    re_emit_op(s, REOP_not_word_boundary);
                } else {
                    re_emit_op(s, REOP_word_boundary);
                }
                s->buf_pos += 2;
                break;
            case '0':
                s->buf_pos += 2;
                c = 0;
                if (is_digit(s->source_buf[s->buf_pos]))
                    js_parse_error(s, "invalid decimal escape in regular expression");
                goto normal_char;
            case '1': case '2': case '3': case '4':
            case '5': case '6': case '7': case '8':
            case '9':
                {
                    const uint8_t *p;
                    p = s->source_buf + s->buf_pos + 1;
                    c = parse_digits(&p);
                    s->buf_pos = p - s->source_buf;
                    if (c > CAPTURE_COUNT_MAX)
                        js_parse_error(s, "back reference is out of range");
                    /* the range is checked afterwards as we don't know the number of captures */
                    last_atom_start = s->byte_code_len;
                    last_capture_count = s->capture_count;
                    re_emit_op_u8(s, REOP_back_reference + s->ignore_case, c);
                }
                break;
            default:
                goto parse_class_atom;
            }
            break;
        case '[':
            last_atom_start = s->byte_code_len;
            last_capture_count = s->capture_count;
            re_parse_char_class(s);
            break;
        case ']':
        case '}':
            if (s->is_unicode)
                js_parse_error(s, "syntax error");
            goto parse_class_atom;
        default:
        parse_class_atom:
            c = get_class_atom(s, FALSE);
        normal_char:
            last_atom_start = s->byte_code_len;
            last_capture_count = s->capture_count;
            if (c >= CLASS_RANGE_BASE) {
                int range_start;
                c -= CLASS_RANGE_BASE;
                if (c == CHAR_RANGE_s || c == CHAR_RANGE_S) {
                    re_emit_op(s, REOP_space + c - CHAR_RANGE_s);
                } else {
                    re_emit_op_u16(s, REOP_range, 0);
                    range_start = s->byte_code_len;
                
                    re_emit_range_base(s, c);
                    re_range_optimize(s, range_start, FALSE);
                }
            } else {
                if (s->ignore_case &&
                    ((c >= 'A' && c <= 'Z') ||
                     (c >= 'a' && c <= 'z'))) {
                    /* XXX: could add specific operation */
                    if (c >= 'a')
                        c -= 32;
                    re_emit_op_u8(s, REOP_range8, 2);
                    emit_u8(s, c);
                    emit_u8(s, c + 1);
                    emit_u8(s, c + 32);
                    emit_u8(s, c + 32 + 1);
                } else {
                    re_emit_char(s, c);
                }
            }
            break;
        }

        /* quantifier */
        if (last_atom_start >= 0) {
            re_parse_quantifier(s, last_atom_start, last_capture_count);
        }

        /* combine several characters when possible */
        arr = JS_VALUE_TO_PTR(s->byte_code);
        if (last_term_start >= 0 &&
            (n1 = re_is_char(arr->buf, last_term_start, term_start)) > 0 &&
            (n2 = re_is_char(arr->buf, term_start, s->byte_code_len)) > 0 &&
            (n1 + n2) <= 4) {
            n1 += n2;
            arr->buf[last_term_start] = REOP_char1 + n1 - 1;
            for(i = 0; i < n2; i++)
                arr->buf[last_term_start + n1 + i] = arr->buf[last_term_start + n1 + i + 1];
            s->byte_code_len--;
        } else {
            last_term_start = term_start;
        }
    }
 done:
    return PARSE_STATE_RET;
}

int re_parse_disjunction(JSParseState *s, int state, int dummy_param)
{
    int start, len, pos;
    JSByteArray *arr;

    PARSE_START2();
    
    start = s->byte_code_len;

    PARSE_CALL_SAVE1(s, 0, re_parse_alternative, 0, start);
    while (s->source_buf[s->buf_pos] == '|') {
        s->buf_pos++;

        len = s->byte_code_len - start;

        /* insert a split before the first alternative */
        emit_insert(s, start, 5);
        arr = JS_VALUE_TO_PTR(s->byte_code);
        arr->buf[start] = REOP_split_next_first;
        put_u32(arr->buf + start + 1, len + 5);

        pos = re_emit_op_u32(s, REOP_goto, 0);

        PARSE_CALL_SAVE2(s, 1, re_parse_alternative, 0, start, pos);

        /* patch the goto */
        len = s->byte_code_len - (pos + 4);
        arr = JS_VALUE_TO_PTR(s->byte_code);
        put_u32(arr->buf + pos, len);
    }
    return PARSE_STATE_RET;
}

/* Allocate the registers as a stack. The control flow is recursive so
   the analysis can be linear. */
int re_compute_register_count(JSParseState *s, uint8_t *bc_buf, int bc_buf_len)
{
    int stack_size, stack_size_max, pos, opcode, len;
    uint32_t val;

    stack_size = 0;
    stack_size_max = 0;
    pos = 0;
    while (pos < bc_buf_len) {
        opcode = bc_buf[pos];
        len = reopcode_info[opcode].size;
        assert(opcode < REOP_COUNT);
        assert((pos + len) <= bc_buf_len);
        switch(opcode) {
        case REOP_set_i32:
        case REOP_set_char_pos:
            bc_buf[pos + 1] = stack_size;
            stack_size++;
            if (stack_size > stack_size_max) {
                if (stack_size > REGISTER_COUNT_MAX)
                    js_parse_error(s, "too many regexp registers");
                stack_size_max = stack_size;
            }
            break;
        case REOP_check_advance:
        case REOP_loop:
        case REOP_loop_split_goto_first:
        case REOP_loop_split_next_first:
            assert(stack_size > 0);
            stack_size--;
            bc_buf[pos + 1] = stack_size;
            break;
        case REOP_loop_check_adv_split_goto_first:
        case REOP_loop_check_adv_split_next_first:
            assert(stack_size >= 2);
            stack_size -= 2;
            bc_buf[pos + 1] = stack_size;
            break;
        case REOP_range8:
            val = bc_buf[pos + 1];
            len += val * 2;
            break;
        case REOP_range:
            val = get_u16(bc_buf + pos + 1);
            len += val * 8;
            break;
        case REOP_back_reference:
        case REOP_back_reference_i:
            /* validate back references */
            if (bc_buf[pos + 1] >= s->capture_count)
                js_parse_error(s, "back reference is out of range");
            break;
        }
        pos += len;
    }
    return stack_size_max;
}

/* return a JSByteArray. 'source' must be a string */
JSValue js_parse_regexp(JSParseState *s, int re_flags)
{
    JSByteArray *arr;
    int register_count;
    
    s->multi_line = ((re_flags & LRE_FLAG_MULTILINE) != 0);
    s->dotall = ((re_flags & LRE_FLAG_DOTALL) != 0);
    s->ignore_case = ((re_flags & LRE_FLAG_IGNORECASE) != 0);
    s->is_unicode = ((re_flags & LRE_FLAG_UNICODE) != 0);
    s->byte_code = JS_NULL;
    s->byte_code_len = 0;
    s->capture_count = 1;
    
    emit_u16(s, re_flags);
    emit_u8(s, 0); /* number of captures */
    emit_u8(s, 0); /* number of registers */

    if (!(re_flags & LRE_FLAG_STICKY)) {
        re_emit_op_u32(s, REOP_split_goto_first, 1 + 5);
        re_emit_op(s, REOP_any);
        re_emit_op_u32(s, REOP_goto, -(5 + 1 + 5));
    }
    re_emit_op_u8(s, REOP_save_start, 0);

    js_parse_call(s, PARSE_FUNC_re_parse_disjunction, 0);

    re_emit_op_u8(s, REOP_save_end, 0);
    re_emit_op(s, REOP_match);

    if (s->buf_pos != s->buf_len)
        js_parse_error(s, "extraneous characters at the end");

    arr = JS_VALUE_TO_PTR(s->byte_code);
    arr->buf[RE_HEADER_CAPTURE_COUNT] = s->capture_count;
    register_count =
        re_compute_register_count(s, arr->buf + RE_HEADER_LEN,
                                  s->byte_code_len - RE_HEADER_LEN);
    arr->buf[RE_HEADER_REGISTER_COUNT] = register_count;
    
    js_shrink_byte_array(s->ctx, &s->byte_code, s->byte_code_len);

#ifdef DUMP_REOP
    arr = JS_VALUE_TO_PTR(s->byte_code);
    lre_dump_bytecode(arr->buf, arr->size);
#endif
    
    return s->byte_code;
}

/* regexp interpreter */

#define CP_LS   0x2028
#define CP_PS   0x2029

BOOL is_line_terminator(uint32_t c)
{
    return (c == '\n' || c == '\r' || c == CP_LS || c == CP_PS);
}

BOOL is_word_char(uint32_t c)
{
    return ((c >= '0' && c <= '9') ||
            (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c == '_'));
}

/* Note: we canonicalize as in the unicode case, but only handle ASCII characters */
int lre_canonicalize(uint32_t c)
{
    if (c >= 'A' && c <= 'Z') {
        c = c - 'A' + 'a';
    }
    return c;
}

#define GET_CHAR(c, cptr, cbuf_end)                          \
    do {                                                     \
        size_t clen;                                         \
        c = utf8_get(cptr, &clen);                           \
        cptr += clen;                                        \
    } while (0)

#define PEEK_CHAR(c, cptr, cbuf_end)                         \
    do {                                                                \
        size_t clen;                                         \
        c = utf8_get(cptr, &clen);                           \
    } while (0)

#define PEEK_PREV_CHAR(c, cptr, cbuf_start)                  \
    do {                                                     \
        const uint8_t *cptr1 = cptr - 1;                     \
        size_t clen;                                         \
        while ((*cptr1 & 0xc0) == 0x80)                                  \
            cptr1--;                                                     \
        c = utf8_get(cptr1, &clen);                                      \
    } while (0)

typedef enum {
    RE_EXEC_STATE_SPLIT,
    RE_EXEC_STATE_LOOKAHEAD,
    RE_EXEC_STATE_NEGATIVE_LOOKAHEAD,
} REExecStateEnum;

//#define DUMP_REEXEC

/* return 1 if match, 0 if not match or < 0 if error. str must be a
   JSString. capture_buf and byte_code are JSByteArray */
int lre_exec(JSContext *ctx, JSValue capture_buf, JSValue byte_code, JSValue str, int cindex)
{
    const uint8_t *pc, *cptr, *cbuf;
    uint32_t *capture;
    int opcode, capture_count;
    uint32_t val, c, idx;
    const uint8_t *cbuf_end;
    JSValue *sp, *bp, *initial_sp, *saved_stack_bottom;
    JSByteArray *arr; /* temporary use */
    JSString *ps; /* temporary use */
    JSGCRef capture_buf_ref, byte_code_ref, str_ref;

    arr = JS_VALUE_TO_PTR(byte_code);
    pc = arr->buf;
    arr = JS_VALUE_TO_PTR(capture_buf);
    capture = (uint32_t *)arr->buf;
    capture_count = lre_get_capture_count(pc);
    pc += RE_HEADER_LEN;
    ps = JS_VALUE_TO_PTR(str);
    cbuf = ps->buf;
    cbuf_end = cbuf + ps->len;
    cptr = cbuf + cindex;

    saved_stack_bottom = ctx->stack_bottom;
    initial_sp = ctx->sp;
    sp = initial_sp;
    bp = initial_sp;
    
#define LRE_POLL_INTERRUPT() do {                       \
        if (unlikely(--ctx->interrupt_counter <= 0)) {  \
            JSValue ret;                                \
            int saved_pc, saved_cptr;                   \
            arr = JS_VALUE_TO_PTR(byte_code);      \
            saved_pc = pc - arr->buf;                   \
            saved_cptr = cptr - cbuf;                   \
            JS_PUSH_VALUE(ctx, capture_buf);            \
            JS_PUSH_VALUE(ctx, byte_code);              \
            JS_PUSH_VALUE(ctx, str);                    \
            ctx->sp = sp;                               \
            ret = __js_poll_interrupt(ctx);             \
            JS_POP_VALUE(ctx, str);                     \
            JS_POP_VALUE(ctx, byte_code);               \
            JS_POP_VALUE(ctx, capture_buf);             \
            if (JS_IsException(ret)) {                  \
                ctx->sp = initial_sp;                   \
                ctx->stack_bottom = saved_stack_bottom; \
                return -1;                              \
            }                                           \
            arr = JS_VALUE_TO_PTR(byte_code);      \
            pc = arr->buf + saved_pc;                   \
            ps = JS_VALUE_TO_PTR(str);             \
            cbuf = ps->buf;                             \
            cbuf_end = cbuf + ps->len;                  \
            cptr = cbuf + saved_cptr;                   \
            arr = JS_VALUE_TO_PTR(capture_buf);    \
            capture = (uint32_t *)arr->buf;             \
        }                                               \
    } while(0)

#define CHECK_STACK_SPACE(n)                            \
    {                                                   \
        if (unlikely((sp - ctx->stack_bottom) < (n))) { \
            int ret, saved_pc, saved_cptr;              \
            arr = JS_VALUE_TO_PTR(byte_code);      \
            saved_pc = pc - arr->buf;                   \
            saved_cptr = cptr - cbuf;                   \
            JS_PUSH_VALUE(ctx, capture_buf);            \
            JS_PUSH_VALUE(ctx, byte_code);              \
            JS_PUSH_VALUE(ctx, str);                    \
            ctx->sp = sp;                               \
            ret = JS_StackCheck(ctx, n);                \
            JS_POP_VALUE(ctx, str);                     \
            JS_POP_VALUE(ctx, byte_code);               \
            JS_POP_VALUE(ctx, capture_buf);             \
            if (ret < 0) {                              \
                ctx->sp = initial_sp;                   \
                ctx->stack_bottom = saved_stack_bottom; \
                return -1;                              \
            }                                           \
            arr = JS_VALUE_TO_PTR(byte_code);      \
            pc = arr->buf + saved_pc;                   \
            ps = JS_VALUE_TO_PTR(str);             \
            cbuf = ps->buf;                             \
            cbuf_end = cbuf + ps->len;                  \
            cptr = cbuf + saved_cptr;                   \
            arr = JS_VALUE_TO_PTR(capture_buf);    \
            capture = (uint32_t *)arr->buf;             \
        }                                               \
    }

#define SAVE_CAPTURE(idx, value)                        \
    {                                                   \
        int __v = (value);                              \
        CHECK_STACK_SPACE(2);                           \
        sp[-2] = JS_NewShortInt(idx);                   \
        sp[-1] = JS_NewShortInt(capture[idx]);   \
        sp -= 2;                                                \
        capture[idx] = __v;                                     \
    }

    /* avoid saving the previous value if already saved */
#define SAVE_CAPTURE_CHECK(idx, value)                    \
    {                                                     \
        int __v = (value);                                \
        JSValue *sp1;                           \
        sp1 = sp;                               \
        for(;;) {                               \
            if (sp1 < bp) {                             \
                if (JS_VALUE_GET_INT(sp1[0]) == (idx))  \
                    break;                              \
                sp1 += 2;                               \
            } else {                                    \
                CHECK_STACK_SPACE(2);                   \
                sp[-2] = JS_NewShortInt(idx);           \
                sp[-1] = JS_NewShortInt(capture[idx]);  \
                sp -= 2;                                \
                break;                                  \
            }                                           \
        }                                               \
        capture[idx] = __v;                             \
    }

#define RE_PC_TYPE_TO_VALUE(pc, type) (((type) << 1) | (((pc) - ((JSByteArray *)JS_VALUE_TO_PTR(byte_code))->buf) << 3))
#define RE_VALUE_TO_PC(val) (((val) >> 3) + ((JSByteArray *)JS_VALUE_TO_PTR(byte_code))->buf)
#define RE_VALUE_TO_TYPE(val) (((val) >> 1) & 3)

#ifdef DUMP_REEXEC
    printf("%5s %5s %5s %5s %s\n", "PC", "CP", "BP", "SP", "OPCODE");
#endif    
    for(;;) {
        opcode = *pc++;
#ifdef DUMP_REEXEC
        printf("%5ld %5ld %5ld %5ld %s\n",
               pc - 1 - ((JSByteArray *)JS_VALUE_TO_PTR(byte_code))->buf - RE_HEADER_LEN,
               cptr - cbuf,
               bp - initial_sp,
               sp - initial_sp,
               reopcode_info[opcode].name);
#endif        
        switch(opcode) {
        case REOP_match:
            ctx->sp = initial_sp;
            ctx->stack_bottom = saved_stack_bottom;
            return 1;
        no_match:
            for(;;) {
                REExecStateEnum type;
                if (bp == initial_sp) {
                    ctx->sp = initial_sp;
                    ctx->stack_bottom = saved_stack_bottom;
                    return 0;
                }
                /* undo the modifications to capture[] and regs[] */
                while (sp < bp) {
                    int idx2 = JS_VALUE_GET_INT(sp[0]);
                    capture[idx2] = JS_VALUE_GET_INT(sp[1]);
                    sp += 2;
                }
                
                pc = RE_VALUE_TO_PC(sp[0]);
                type = RE_VALUE_TO_TYPE(sp[0]);
                cptr = JS_VALUE_GET_INT(sp[1]) + cbuf;
                bp = VALUE_TO_SP(ctx, sp[2]);
                sp += 3;
                if (type != RE_EXEC_STATE_LOOKAHEAD)
                    break;
            }
            LRE_POLL_INTERRUPT();
            break;
        case REOP_lookahead_match:
            /* pop all the saved states until reaching the start of
               the lookahead and keep the updated captures and
               variables and the corresponding undo info. */
            {
                JSValue *sp1, *sp_start, *next_sp;
                REExecStateEnum type;

                sp_start = sp;
                for(;;) {
                    sp1 = sp;
                    sp = bp;
                    pc = RE_VALUE_TO_PC(sp[0]);
                    type = RE_VALUE_TO_TYPE(sp[0]);
                    cptr = JS_VALUE_GET_INT(sp[1]) + cbuf;
                    bp = VALUE_TO_SP(ctx, sp[2]);
                    sp[2] = SP_TO_VALUE(ctx, sp1); /* save the next value for the copy step */
                    sp += 3;
                    if (type == RE_EXEC_STATE_LOOKAHEAD)
                        break;
                }
                if (sp != initial_sp) {
                    /* keep the undo info if there is a saved state */
                    sp1 = sp;
                    while (sp1 != sp_start) {
                        sp1 -= 3;
                        next_sp = VALUE_TO_SP(ctx, sp1[2]);
                        while (sp1 != next_sp) {
                            *--sp = *--sp1;
                        }
                    }
                }
            }
            break;
        case REOP_negative_lookahead_match:
            /* pop all the saved states until reaching start of the negative lookahead */
            for(;;) {
                REExecStateEnum type;
                type = RE_VALUE_TO_TYPE(bp[0]);
                /* undo the modifications to capture[] and regs[] */
                while (sp < bp) {
                    int idx2 = JS_VALUE_GET_INT(sp[0]);
                    capture[idx2] = JS_VALUE_GET_INT(sp[1]);
                    sp += 2;
                }
                pc = RE_VALUE_TO_PC(sp[0]);
                type = RE_VALUE_TO_TYPE(sp[0]);
                cptr = JS_VALUE_GET_INT(sp[1]) + cbuf;
                bp = VALUE_TO_SP(ctx, sp[2]);
                sp += 3;
                if (type == RE_EXEC_STATE_NEGATIVE_LOOKAHEAD)
                    break;
            }
            goto no_match;

        case REOP_char1:
            if ((cbuf_end - cptr) < 1)
                goto no_match;
            if (pc[0] != cptr[0])
                goto no_match;
            pc++;
            cptr++;
            break;
        case REOP_char2:
            if ((cbuf_end - cptr) < 2)
                goto no_match;
            if (get_u16(pc) != get_u16(cptr))
                goto no_match;
            pc += 2;
            cptr += 2;
            break;
        case REOP_char3:
            if ((cbuf_end - cptr) < 3)
                goto no_match;
            if (get_u16(pc) != get_u16(cptr) || pc[2] != cptr[2])
                goto no_match;
            pc += 3;
            cptr += 3;
            break;
        case REOP_char4:
            if ((cbuf_end - cptr) < 4)
                goto no_match;
            if (get_u32(pc) != get_u32(cptr))
                goto no_match;
            pc += 4;
            cptr += 4;
            break;
        case REOP_split_goto_first:
        case REOP_split_next_first:
            {
                const uint8_t *pc1;

                val = get_u32(pc);
                pc += 4;
                CHECK_STACK_SPACE(3);
                if (opcode == REOP_split_next_first) {
                    pc1 = pc + (int)val;
                } else {
                    pc1 = pc;
                    pc = pc + (int)val;
                }
                sp -= 3;
                sp[0] = RE_PC_TYPE_TO_VALUE(pc1, RE_EXEC_STATE_SPLIT);
                sp[1] = JS_NewShortInt(cptr - cbuf);
                sp[2] = SP_TO_VALUE(ctx, bp);
                bp = sp;
            }
            break;
        case REOP_lookahead:
        case REOP_negative_lookahead:
            val = get_u32(pc);
            pc += 4;
            CHECK_STACK_SPACE(3);
            sp -= 3;
            sp[0] = RE_PC_TYPE_TO_VALUE(pc + (int)val,
                                        RE_EXEC_STATE_LOOKAHEAD + opcode - REOP_lookahead);
            sp[1] = JS_NewShortInt(cptr - cbuf);
            sp[2] = SP_TO_VALUE(ctx, bp);
            bp = sp;
            break;
        case REOP_goto:
            val = get_u32(pc);
            pc += 4 + (int)val;
            LRE_POLL_INTERRUPT();
            break;
        case REOP_line_start:
        case REOP_line_start_m:
            if (cptr == cbuf)
                break;
            if (opcode == REOP_line_start)
                goto no_match;
            PEEK_PREV_CHAR(c, cptr, cbuf);
            if (!is_line_terminator(c))
                goto no_match;
            break;
        case REOP_line_end:
        case REOP_line_end_m:
            if (cptr == cbuf_end)
                break;
            if (opcode == REOP_line_end)
                goto no_match;
            PEEK_CHAR(c, cptr, cbuf_end);
            if (!is_line_terminator(c))
                goto no_match;
            break;
        case REOP_dot:
            if (cptr == cbuf_end)
                goto no_match;
            GET_CHAR(c, cptr, cbuf_end);
            if (is_line_terminator(c))
                goto no_match;
            break;
        case REOP_any:
            if (cptr == cbuf_end)
                goto no_match;
            GET_CHAR(c, cptr, cbuf_end);
            break;
        case REOP_space:
        case REOP_not_space:
            {
                BOOL v1;
                if (cptr == cbuf_end)
                    goto no_match;
                c = cptr[0];
                if (c < 128) {
                    cptr++;
                    v1 = unicode_is_space_ascii(c);
                } else {
                    size_t clen;
                    c = __utf8_get(cptr, &clen);
                    cptr += clen;
                    v1 = unicode_is_space_non_ascii(c);
                }
                v1 ^= (opcode - REOP_space);
                if (!v1)
                    goto no_match;
            }
            break;
        case REOP_save_start:
        case REOP_save_end:
            val = *pc++;
            assert(val < capture_count);
            idx = 2 * val + opcode - REOP_save_start;
            SAVE_CAPTURE(idx, cptr - cbuf);
            break;
        case REOP_save_reset:
            {
                uint32_t val2;
                val = pc[0];
                val2 = pc[1];
                pc += 2;
                assert(val2 < capture_count);
                CHECK_STACK_SPACE(2 * (val2 - val + 1));
                while (val <= val2) {
                    idx = 2 * val;
                    SAVE_CAPTURE(idx, 0);
                    idx = 2 * val + 1;
                    SAVE_CAPTURE(idx, 0);
                    val++;
                }
            }
            break;
        case REOP_set_i32:
            idx = pc[0];
            val = get_u32(pc + 1);
            pc += 5;
            SAVE_CAPTURE_CHECK(2 * capture_count + idx, val);
            break;
        case REOP_loop:
            {
                uint32_t val2;
                idx = pc[0];
                val = get_u32(pc + 1);
                pc += 5;

                val2 = capture[2 * capture_count + idx] - 1;
                SAVE_CAPTURE_CHECK(2 * capture_count + idx, val2);
                if (val2 != 0) {
                    pc += (int)val;
                    LRE_POLL_INTERRUPT();
                }
            }
            break;
        case REOP_loop_split_goto_first:
        case REOP_loop_split_next_first:
        case REOP_loop_check_adv_split_goto_first:
        case REOP_loop_check_adv_split_next_first:
            {
                const uint8_t *pc1;
                uint32_t val2, limit;
                idx = pc[0];
                limit = get_u32(pc + 1);
                val = get_u32(pc + 5);
                pc += 9;

                /* decrement the counter */
                val2 = capture[2 * capture_count + idx] - 1;
                SAVE_CAPTURE_CHECK(2 * capture_count + idx, val2);
                
                if (val2 > limit) {
                    /* normal loop if counter > limit */
                    pc += (int)val;
                    LRE_POLL_INTERRUPT();
                } else {
                    /* check advance */
                    if ((opcode == REOP_loop_check_adv_split_goto_first ||
                         opcode == REOP_loop_check_adv_split_next_first) &&
                        capture[2 * capture_count + idx + 1] == (cptr - cbuf) &&
                        val2 != limit) {
                        goto no_match;
                    }
                    
                    /* otherwise conditional split */
                    if (val2 != 0) {
                        CHECK_STACK_SPACE(3);
                        if (opcode == REOP_loop_split_next_first ||
                            opcode == REOP_loop_check_adv_split_next_first) {
                            pc1 = pc + (int)val;
                        } else {
                            pc1 = pc;
                            pc = pc + (int)val;
                        }
                        sp -= 3;
                        sp[0] = RE_PC_TYPE_TO_VALUE(pc1, RE_EXEC_STATE_SPLIT);
                        sp[1] = JS_NewShortInt(cptr - cbuf);
                        sp[2] = SP_TO_VALUE(ctx, bp);
                        bp = sp;
                    }
                }
            }
            break;
        case REOP_set_char_pos:
            idx = pc[0];
            pc++;
            SAVE_CAPTURE_CHECK(2 * capture_count + idx, cptr - cbuf);
            break;
        case REOP_check_advance:
            idx = pc[0];
            pc++;
            if (capture[2 * capture_count + idx] == cptr - cbuf)
                goto no_match;
            break;
        case REOP_word_boundary:
        case REOP_not_word_boundary:
            {
                BOOL v1, v2;
                BOOL is_boundary = (opcode == REOP_word_boundary);
                /* char before */
                if (cptr == cbuf) {
                    v1 = FALSE;
                } else {
                    PEEK_PREV_CHAR(c, cptr, cbuf);
                    v1 = is_word_char(c);
                }
                /* current char */
                if (cptr >= cbuf_end) {
                    v2 = FALSE;
                } else {
                    PEEK_CHAR(c, cptr, cbuf_end);
                    v2 = is_word_char(c);
                }
                if (v1 ^ v2 ^ is_boundary)
                    goto no_match;
            }
            break;
            /* assumption: 8 bit and small number of ranges */
        case REOP_range8:
            {
                int n, i;
                n = pc[0];
                pc++;
                if (cptr >= cbuf_end)
                    goto no_match;
                GET_CHAR(c, cptr, cbuf_end);
                for(i = 0; i < n - 1; i++) {
                    if (c >= pc[2 * i] && c < pc[2 * i + 1])
                        goto range8_match;
                }
                /* 0xff = max code point value */
                if (c >= pc[2 * i] &&
                    (c < pc[2 * i + 1] || pc[2 * i + 1] == 0xff))
                    goto range8_match;
                goto no_match;
            range8_match:
                pc += 2 * n;
            }
            break;
        case REOP_range:
            {
                int n;
                uint32_t low, high, idx_min, idx_max, idx;

                n = get_u16(pc); /* n must be >= 1 */
                pc += 2;
                if (cptr >= cbuf_end || n == 0)
                    goto no_match;
                GET_CHAR(c, cptr, cbuf_end);
                idx_min = 0;
                low = get_u32(pc + 0 * 8);
                if (c < low)
                    goto no_match;
                idx_max = n - 1;
                high = get_u32(pc + idx_max * 8 + 4);
                if (c >= high)
                    goto no_match;
                while (idx_min <= idx_max) {
                    idx = (idx_min + idx_max) / 2;
                    low = get_u32(pc + idx * 8);
                    high = get_u32(pc + idx * 8 + 4);
                    if (c < low)
                        idx_max = idx - 1;
                    else if (c >= high)
                        idx_min = idx + 1;
                    else
                        goto range_match;
                }
                goto no_match;
            range_match:
                pc += 8 * n;
            }
            break;
        case REOP_back_reference:
        case REOP_back_reference_i:
            val = pc[0];
            pc++;
            if (capture[2 * val] != -1 && capture[2 * val + 1] != -1) {
                const uint8_t *cptr1, *cptr1_end;
                int c1, c2;

                cptr1 = cbuf + capture[2 * val];
                cptr1_end = cbuf + capture[2 * val + 1];
                while (cptr1 < cptr1_end) {
                    if (cptr >= cbuf_end)
                        goto no_match;
                    GET_CHAR(c1, cptr1, cptr1_end);
                    GET_CHAR(c2, cptr, cbuf_end);
                    if (opcode == REOP_back_reference_i) {
                        c1 = lre_canonicalize(c1);
                        c2 = lre_canonicalize(c2);
                    }
                    if (c1 != c2)
                        goto no_match;
                }
            }
            break;
        default:
#ifdef DUMP_REEXEC
            printf("unknown opcode pc=%ld\n", pc - 1 - ((JSByteArray *)JS_VALUE_TO_PTR(byte_code))->buf - RE_HEADER_LEN);
#endif            
            abort();
        }
    }
}

/* regexp js interface */

/* return the length */
size_t js_parse_regexp_flags(int *pre_flags, const uint8_t *buf)
{
    const uint8_t *p = buf;
    int mask, re_flags;
    re_flags = 0;
    while (*p != '\0') {
        switch(*p) {
#if 0
        case 'd':
            mask = LRE_FLAG_INDICES;
            break;
#endif                
        case 'g':
            mask = LRE_FLAG_GLOBAL;
            break;
        case 'i':
            mask = LRE_FLAG_IGNORECASE;
            break;
        case 'm':
            mask = LRE_FLAG_MULTILINE;
            break;
        case 's':
            mask = LRE_FLAG_DOTALL;
            break;
        case 'u':
            mask = LRE_FLAG_UNICODE;
            break;
#if 0
        case 'v':
            mask = LRE_FLAG_UNICODE_SETS;
            break;
#endif
        case 'y':
            mask = LRE_FLAG_STICKY;
            break;
        default:
            goto done;
        }
        if ((re_flags & mask) != 0) 
            break;
        re_flags |= mask;
        p++;
    }
 done:
    *pre_flags = re_flags;
    return p - buf;
}

/* pattern and flags must be strings */
JSValue js_compile_regexp(JSContext *ctx, JSValue pattern, JSValue flags)
{
    int re_flags;
    
    re_flags = 0;
    if (!JS_IsUndefined(flags)) {
        JSString *ps;
        JSStringCharBuf buf;
        size_t len;
        ps = get_string_ptr(ctx, &buf, flags);
        len = js_parse_regexp_flags(&re_flags, ps->buf);
        if (len != ps->len)
            return JS_ThrowSyntaxError(ctx, "invalid regular expression flags");
    }

    return JS_Parse2(ctx, pattern, NULL, 0, "<regexp>",
                     JS_EVAL_REGEXP | (re_flags << JS_EVAL_REGEXP_FLAGS_SHIFT));
}

JSRegExp *js_get_regexp(JSContext *ctx, JSValue obj)
{
    JSObject *p;
    p = js_get_object_class(ctx, obj, JS_CLASS_REGEXP);
    if (!p) {
        JS_ThrowTypeError(ctx, "not a regular expression");
        return NULL;
    }
    return &p->u.regexp;
}

JSValue js_regexp_get_lastIndex(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    JSRegExp *re = js_get_regexp(ctx, *this_val);
    if (!re)
        return JS_EXCEPTION;
    return JS_NewInt32(ctx, re->last_index);
}

JSValue js_regexp_get_source(JSContext *ctx, JSValue *this_val,
                             int argc, JSValue *argv)
{
    JSRegExp *re = js_get_regexp(ctx, *this_val);
    if (!re)
        return JS_EXCEPTION;
    /* XXX: not complete */
    return re->source;
}

JSValue js_regexp_set_lastIndex(JSContext *ctx, JSValue *this_val,
                                int argc, JSValue *argv)
{
    JSRegExp *re;
    int last_index;
    if (JS_ToInt32(ctx, &last_index, argv[0]))
        return JS_EXCEPTION;
    re = js_get_regexp(ctx, *this_val);
    if (!re)
        return JS_EXCEPTION;
    re->last_index = last_index;
    return JS_UNDEFINED;
}

#define RE_FLAG_COUNT 6

/* return the string length */
size_t js_regexp_flags_str(char *buf, int re_flags)
{
    static const char flag_char[RE_FLAG_COUNT] = { 'g', 'i', 'm', 's', 'u', 'y' };
    char *p = buf;
    int i;
    
    for(i = 0; i < RE_FLAG_COUNT; i++) {
        if ((re_flags >> i) & 1)
            *p++ = flag_char[i];
    }
    *p = '\0';
    return p - buf;
}

void dump_regexp(JSContext *ctx, JSObject *p)
{
    JSStringCharBuf buf;
    JSString *ps;
    char buf2[RE_FLAG_COUNT + 1];
    JSByteArray *arr;
    
    js_putchar(ctx, '/');
    ps = get_string_ptr(ctx, &buf, p->u.regexp.source);
    if (ps->len == 0) {
        js_printf(ctx, "(?:)");
    } else {
        js_printf(ctx, "%" JSValue_PRI, p->u.regexp.source);
    }
    arr = JS_VALUE_TO_PTR(p->u.regexp.byte_code);
    js_regexp_flags_str(buf2, lre_get_flags(arr->buf));
    js_printf(ctx, "/%s", buf2);
}

JSValue js_regexp_get_flags(JSContext *ctx, JSValue *this_val,
                            int argc, JSValue *argv)
{
    JSRegExp *re;
    JSByteArray *arr;
    size_t len;
    char buf[RE_FLAG_COUNT + 1];

    re = js_get_regexp(ctx, *this_val);
    if (!re)
        return JS_EXCEPTION;
    arr = JS_VALUE_TO_PTR(re->byte_code);
    len = js_regexp_flags_str(buf, lre_get_flags(arr->buf));
    return JS_NewStringLen(ctx, buf, len);
}

JSValue js_regexp_constructor(JSContext *ctx, JSValue *this_val,
                              int argc, JSValue *argv)
{
    JSValue obj, byte_code;
    JSObject *p;
    JSGCRef byte_code_ref;

    argc &= ~FRAME_CF_CTOR;
    
    argv[0] = JS_ToString(ctx, argv[0]);
    if (JS_IsException(argv[0]))
        return JS_EXCEPTION;
    if (!JS_IsUndefined(argv[1])) {
        argv[1] = JS_ToString(ctx, argv[1]);
        if (JS_IsException(argv[1]))
            return JS_EXCEPTION;
    }
    byte_code = js_compile_regexp(ctx, argv[0], argv[1]);
    if (JS_IsException(byte_code))
        return JS_EXCEPTION;
    JS_PUSH_VALUE(ctx, byte_code);
    obj = JS_NewObjectClass(ctx, JS_CLASS_REGEXP, sizeof(JSRegExp));
    JS_POP_VALUE(ctx, byte_code);
    if (JS_IsException(obj))
        return obj;
    p = JS_VALUE_TO_PTR(obj);
    p->u.regexp.source = argv[0];
    p->u.regexp.byte_code = byte_code;
    p->u.regexp.last_index = 0;
    return obj;
}

enum {
    MAGIC_REGEXP_EXEC,
    MAGIC_REGEXP_TEST,
    MAGIC_REGEXP_SEARCH,
    MAGIC_REGEXP_FORCE_GLOBAL, /* same as exec but force the global flag */
};

JSValue js_regexp_exec(JSContext *ctx, JSValue *this_val,
                       int argc, JSValue *argv, int magic)
{
    JSObject *p;
    JSRegExp *re;
    JSValue obj, *capture_buf, res;
    uint32_t *capture, last_index_utf8;
    int rc, capture_count, i, re_flags, last_index;
    JSByteArray *bc_arr, *carr;
    JSGCRef capture_buf_ref, obj_ref;
    JSString *str;
    JSStringCharBuf str_buf;

    re = js_get_regexp(ctx, *this_val);
    if (!re)
        return JS_EXCEPTION;

    argv[0] = JS_ToString(ctx, argv[0]);
    if (JS_IsException(argv[0]))
        return JS_EXCEPTION;

    p = JS_VALUE_TO_PTR(*this_val);
    re = &p->u.regexp;
    last_index = max_int(re->last_index, 0);

    bc_arr = JS_VALUE_TO_PTR(re->byte_code);
    re_flags = lre_get_flags(bc_arr->buf);
    if (magic == MAGIC_REGEXP_FORCE_GLOBAL)
        re_flags |= MAGIC_REGEXP_FORCE_GLOBAL;
    if ((re_flags & (LRE_FLAG_GLOBAL | LRE_FLAG_STICKY)) == 0 ||
        magic == MAGIC_REGEXP_SEARCH) {
        last_index = 0;
    }
    capture_count = lre_get_capture_count(bc_arr->buf);

    carr = js_alloc_byte_array(ctx, sizeof(uint32_t) * lre_get_alloc_count(bc_arr->buf));
    if (!carr)
        goto fail;
    capture_buf = JS_PushGCRef(ctx, &capture_buf_ref);
    *capture_buf = JS_VALUE_FROM_PTR(carr);
    capture = (uint32_t *)carr->buf;
    for(i = 0; i < 2 * capture_count; i++)
        capture[i] = -1;
    
    if (last_index <= 0)
        last_index_utf8 = 0;
    else
        last_index_utf8 = js_string_utf16_to_utf8_pos(ctx, argv[0], last_index) / 2;
    if (last_index_utf8 > js_string_byte_len(ctx, argv[0])) {
        rc = 2;
    } else {
        p = JS_VALUE_TO_PTR(*this_val);
        re = &p->u.regexp;
        str = get_string_ptr(ctx, &str_buf, argv[0]);
        /* JS_VALUE_FROM_PTR(str) is acceptable here because the
           GC ignores pointers outside the heap */
        rc = lre_exec(ctx, *capture_buf, re->byte_code, JS_VALUE_FROM_PTR(str),
                      last_index_utf8);
    }
    if (rc != 1) {
        if (rc >= 0) {
            if (re_flags & (LRE_FLAG_GLOBAL | LRE_FLAG_STICKY)) {
                p = JS_VALUE_TO_PTR(*this_val);
                re = &p->u.regexp;
                re->last_index = 0;
            }
            if (magic == MAGIC_REGEXP_SEARCH)
                obj = JS_NewShortInt(-1);
            else if (magic == MAGIC_REGEXP_TEST)
                obj = JS_FALSE;
            else
                obj = JS_NULL;
        } else {
            goto fail;
        }
    } else {
        capture = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
        if (magic == MAGIC_REGEXP_SEARCH) {
            obj = JS_NewShortInt(js_string_utf8_to_utf16_pos(ctx, argv[0], capture[0] * 2));
            goto done;
        } 
        if (re_flags & (LRE_FLAG_GLOBAL | LRE_FLAG_STICKY)) {
            p = JS_VALUE_TO_PTR(*this_val);
            re = &p->u.regexp;
            re->last_index = js_string_utf8_to_utf16_pos(ctx, argv[0], capture[1] * 2);
        }
        if (magic == MAGIC_REGEXP_TEST) {
            obj = JS_TRUE;
        } else {
            obj = JS_NewArray(ctx, capture_count);
            if (JS_IsException(obj))
                goto fail;

            JS_PUSH_VALUE(ctx, obj);
            capture = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
            res = JS_DefinePropertyValue(ctx, obj, js_get_atom(ctx, JS_ATOM_index),
                                         JS_NewShortInt(js_string_utf8_to_utf16_pos(ctx, argv[0], capture[0] * 2)));
            JS_POP_VALUE(ctx, obj);
            if (JS_IsException(res))
                goto fail;

            JS_PUSH_VALUE(ctx, obj);
            res = JS_DefinePropertyValue(ctx, obj, js_get_atom(ctx, JS_ATOM_input),
                                         argv[0]);
            JS_POP_VALUE(ctx, obj);
            if (JS_IsException(res))
                goto fail;

            for(i = 0; i < capture_count; i++) {
                int start, end;
                JSValue val;

                capture = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
                start = capture[2 * i];
                end = capture[2 * i + 1];
                if (start != -1 && end != -1) {
                    JSValueArray *arr;
                    JS_PUSH_VALUE(ctx, obj);
                    val = js_sub_string_utf8(ctx, argv[0], 2 * start, 2 * end);
                    JS_POP_VALUE(ctx, obj);
                    if (JS_IsException(val))
                        goto fail;
                    p = JS_VALUE_TO_PTR(obj);
                    arr = JS_VALUE_TO_PTR(p->u.array.tab);
                    arr->arr[i] = val;
                }
            }
        }
    }
 done:
    JS_PopGCRef(ctx, &capture_buf_ref);
    return obj;
 fail:
    obj = JS_EXCEPTION;
    goto done;
}

/* if regexp replace: capture_buf != NULL, needle = NULL
   if string replace: capture_buf = NULL, captures_len = 1, needle != NULL
*/
int js_string_concat_subst(JSContext *ctx, StringBuffer *b, JSValue *str, JSValue *rep, uint32_t pos, uint32_t end_of_match, JSValue *capture_buf, uint32_t captures_len, JSValue *needle)
{
    JSStringCharBuf buf_rep;
    JSString *p;
    int rep_len, i, j, j0, c, k;

    if (JS_IsFunction(ctx, *rep)) {
        JSValue res, val;
        JSGCRef val_ref;
        int ret;
        
        if (JS_StackCheck(ctx, 4 + captures_len))
            return -1;
        JS_PushArg(ctx, *str);
        JS_PushArg(ctx, JS_NewShortInt(pos));
        if (capture_buf) {
            for(k = captures_len - 1; k >= 0; k--) {
                uint32_t *captures = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
                if (captures[2 * k] != -1 && captures[2 * k + 1] != -1) {
                    val = js_sub_string_utf8(ctx, *str, captures[2 * k] * 2, captures[2 * k + 1] * 2);
                    if (JS_IsException(val))
                        return -1;
                    JS_PUSH_VALUE(ctx, val);
                    ret = JS_StackCheck(ctx, 3 + k);
                    JS_POP_VALUE(ctx, val);
                    if (ret)
                        return -1;
                } else {
                    val = JS_UNDEFINED;
                }
                JS_PushArg(ctx, val);
            }
        } else {
            JS_PushArg(ctx, *needle);
        }
        JS_PushArg(ctx, *rep); /* function */
        JS_PushArg(ctx, JS_UNDEFINED); /* this_val */
        res = JS_Call(ctx, 2 + captures_len);
        if (JS_IsException(res))
            return -1;
        return string_buffer_concat(ctx, b, res);
    }
    
    p = get_string_ptr(ctx, &buf_rep, *rep);
    rep_len = p->len;
    i = 0;
    for(;;) {
        p = get_string_ptr(ctx, &buf_rep, *rep);
        j = i;
        while (j < rep_len && p->buf[j] != '$')
            j++;
        if (j + 1 >= rep_len)
            break;
        j0 = j++; /* j0 = position of '$' */
        c = p->buf[j++];
        string_buffer_concat_utf8(ctx, b, *rep, 2 * i, 2 * j0);
        if (c == '$') {
            string_buffer_putc(ctx, b, '$');
        } else if (c == '&') {
            if (capture_buf) {
                string_buffer_concat_utf16(ctx, b, *str, pos, end_of_match);
            } else {
                string_buffer_concat_str(ctx, b, *needle);
            }
        } else if (c == '`') {
            string_buffer_concat_utf16(ctx, b, *str, 0, pos);
        } else if (c == '\'') {
            string_buffer_concat_utf16(ctx, b, *str, end_of_match, js_string_len(ctx, *str));
        } else if (c >= '0' && c <= '9') {
            k = c - '0';
            if (j < rep_len) {
                c = p->buf[j];
                if (c >= '0' && c <= '9') {
                    k = k * 10 + c - '0';
                    j++;
                }
            }
            if (k >= 1 && k < captures_len) {
                uint32_t *captures = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
                if (captures[2 * k] != -1 && captures[2 * k + 1] != -1) {
                    string_buffer_concat_utf8(ctx, b, *str,
                                              captures[2 * k] * 2, captures[2 * k + 1] * 2);
                }
            } else {
                goto no_rep;
            }
        } else {
        no_rep:
            string_buffer_concat_utf8(ctx, b, *rep, 2 * j0, 2 * j);
        }
        i = j;
    }
    return string_buffer_concat_utf8(ctx, b, *rep, 2 * i, 2 * rep_len);
}

JSValue js_string_replace(JSContext *ctx, JSValue *this_val,
                          int argc, JSValue *argv, int is_replaceAll)
{
    StringBuffer b_s, *b = &b_s;
    int pos, endOfLastMatch, needle_len, input_len;
    BOOL is_first, is_regexp;

    *this_val = JS_ToString(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    is_regexp = (JS_GetClassID(ctx, argv[0]) == JS_CLASS_REGEXP);
    if (!is_regexp) {
        argv[0] = JS_ToString(ctx, argv[0]);
        if (JS_IsException(argv[0]))
            return JS_EXCEPTION;
    }
    if (!JS_IsFunction(ctx, argv[1])) {
        argv[1] = JS_ToString(ctx, argv[1]);
        if (JS_IsException(argv[1]))
            return JS_EXCEPTION;
    }
    input_len = js_string_len(ctx, *this_val);
    endOfLastMatch = 0;

    string_buffer_push(ctx, b, 0);
    
    if (is_regexp) {
        int start, end, last_index, ret, re_flags, i, capture_count;
        JSObject *p;
        JSByteArray *bc_arr, *carr;
        JSValue *capture_buf;
        uint32_t *capture;
        JSGCRef capture_buf_ref;
        
        p = JS_VALUE_TO_PTR(argv[0]);
        bc_arr = JS_VALUE_TO_PTR(p->u.regexp.byte_code);
        re_flags = lre_get_flags(bc_arr->buf);
        capture_count = lre_get_capture_count(bc_arr->buf);

        if (re_flags & LRE_FLAG_GLOBAL)
            p->u.regexp.last_index = 0;
        
        if ((re_flags & (LRE_FLAG_GLOBAL | LRE_FLAG_STICKY)) == 0) {
            last_index = 0;
        } else {
            last_index = max_int(p->u.regexp.last_index, 0);
        }
        
        carr = js_alloc_byte_array(ctx, sizeof(uint32_t) * lre_get_alloc_count(bc_arr->buf));
        if (!carr) {
            string_buffer_pop(ctx, b);
            return JS_EXCEPTION;
        }
        capture_buf = JS_PushGCRef(ctx, &capture_buf_ref);
        *capture_buf = JS_VALUE_FROM_PTR(carr);
        capture = (uint32_t *)carr->buf;
        for(i = 0; i < 2 * capture_count; i++)
            capture[i] = -1;

        for(;;) {
            if (last_index > input_len) {
                ret = 0;
            } else {
                JSString *str;
                JSStringCharBuf str_buf;
                p = JS_VALUE_TO_PTR(argv[0]);
                str = get_string_ptr(ctx, &str_buf, *this_val);
                /* JS_VALUE_FROM_PTR(str) is acceptable here because the
                   GC ignores pointers outside the heap */
                ret = lre_exec(ctx, *capture_buf, p->u.regexp.byte_code,
                               JS_VALUE_FROM_PTR(str),
                               js_string_utf16_to_utf8_pos(ctx, *this_val, last_index) / 2);
            }
            if (ret < 0) {
                JS_PopGCRef(ctx, &capture_buf_ref);
                string_buffer_pop(ctx, b);
                return JS_EXCEPTION;
            }
            if (ret == 0) {
                if (re_flags & (LRE_FLAG_GLOBAL | LRE_FLAG_STICKY)) {
                    p = JS_VALUE_TO_PTR(argv[0]);
                    p->u.regexp.last_index = 0;
                }
                break;
            }
            capture = (uint32_t *)((JSByteArray *)JS_VALUE_TO_PTR(*capture_buf))->buf;
            start = js_string_utf8_to_utf16_pos(ctx, *this_val, capture[0] * 2);
            end = js_string_utf8_to_utf16_pos(ctx, *this_val, capture[1] * 2);
            string_buffer_concat_utf16(ctx, b, *this_val, endOfLastMatch, start);
            js_string_concat_subst(ctx, b, this_val, &argv[1],
                                   start, end, capture_buf, capture_count, NULL);
            endOfLastMatch = end;
            if (!(re_flags & LRE_FLAG_GLOBAL)) {
                if (re_flags & LRE_FLAG_STICKY) {
                    p = JS_VALUE_TO_PTR(argv[0]);
                    p->u.regexp.last_index = end;
                }
                break;
            }
            if (end == start) {
                int c = string_getcp(ctx, *this_val, end, TRUE);
                /* since regexp are unicode by default, replace is also unicode by default */
                end += 1 + (c >= 0x10000);
            }
            last_index = end;
        }
        JS_PopGCRef(ctx, &capture_buf_ref);
    } else {
        needle_len = js_string_len(ctx, argv[0]);
        
        is_first = TRUE;
        for(;;) {
            if (unlikely(needle_len == 0)) {
                if (is_first)
                    pos = 0;
                else if (endOfLastMatch >= input_len)
                    pos = -1;
                else
                    pos = endOfLastMatch + 1;
            } else {
                pos = js_string_indexof(ctx, *this_val, argv[0], endOfLastMatch,
                                        input_len, needle_len);
            }
            if (pos < 0) {
                if (is_first) {
                    string_buffer_pop(ctx, b);
                    return *this_val;
                } else {
                    break;
                }
            }
            
            string_buffer_concat_utf16(ctx, b, *this_val, endOfLastMatch, pos);
            
            js_string_concat_subst(ctx, b, this_val, &argv[1],
                                   pos, pos + needle_len, NULL, 1, &argv[0]);

            endOfLastMatch = pos + needle_len;
            is_first = FALSE;
            if (!is_replaceAll)
                break;
        }
    }
    string_buffer_concat_utf16(ctx, b, *this_val, endOfLastMatch, input_len);
    return string_buffer_pop(ctx, b);
}

// split(sep, limit)
JSValue js_string_split(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    JSValue *A, T, ret, *z;
    uint32_t lim, lengthA;
    int p, q, s, e;
    BOOL undef_sep;
    JSGCRef A_ref, z_ref;
    BOOL is_regexp;
    
    *this_val = JS_ToString(ctx, *this_val);
    if (JS_IsException(*this_val))
        return JS_EXCEPTION;
    if (JS_IsUndefined(argv[1])) {
        lim = 0xffffffff;
    } else {
        if (JS_ToUint32(ctx, &lim, argv[1]) < 0)
            return JS_EXCEPTION;
    }
    is_regexp = (JS_GetClassID(ctx, argv[0]) == JS_CLASS_REGEXP);
    if (!is_regexp) {
        undef_sep = JS_IsUndefined(argv[0]);
        argv[0] = JS_ToString(ctx, argv[0]);
        if (JS_IsException(argv[0]))
            return JS_EXCEPTION;
    } else {
        undef_sep = FALSE;
    }
    
    A = JS_PushGCRef(ctx, &A_ref);
    z = JS_PushGCRef(ctx, &z_ref);
    *A = JS_NewArray(ctx, 0);
    if (JS_IsException(*A))
        goto exception;
    lengthA = 0;

    s = js_string_len(ctx, *this_val);
    p = 0;
    if (lim == 0)
        goto done;
    if (undef_sep)
        goto add_tail;

    if (is_regexp) {
        int numberOfCaptures, i, re_flags;
        JSObject *p1;
        JSValueArray *arr;
        JSByteArray *bc_arr;
        
        p1 = JS_VALUE_TO_PTR(argv[0]);
        bc_arr = JS_VALUE_TO_PTR(p1->u.regexp.byte_code);
        re_flags = lre_get_flags(bc_arr->buf);
        
        if (s == 0) {
            p1 = JS_VALUE_TO_PTR(argv[0]);
            p1->u.regexp.last_index = 0;
            *z = js_regexp_exec(ctx, &argv[0], 1, this_val, MAGIC_REGEXP_FORCE_GLOBAL);
            if (JS_IsException(*z))
                goto exception;
            if (JS_IsNull(*z))
                goto add_tail;
            goto done;
        }
        q = 0;
        while (q < s) {
            p1 = JS_VALUE_TO_PTR(argv[0]);
            p1->u.regexp.last_index = q;
            /* XXX: need sticky behavior */
            *z = js_regexp_exec(ctx, &argv[0], 1, this_val, MAGIC_REGEXP_FORCE_GLOBAL);
            if (JS_IsException(*z))
                goto exception;
            if (JS_IsNull(*z)) {
                if (!(re_flags & LRE_FLAG_STICKY)) {
                    break;
                } else {
                    int c = string_getcp(ctx, *this_val, q, TRUE);
                    /* since regexp are unicode by default, split is also unicode by default */
                    q += 1 + (c >= 0x10000);
                }
            } else {
                if (!(re_flags & LRE_FLAG_STICKY)) {
                    JSValue res;
                    res = JS_GetProperty(ctx, *z, js_get_atom(ctx, JS_ATOM_index));
                    if (JS_IsException(res))
                        goto exception;
                    q = JS_VALUE_GET_INT(res);
                }
                p1 = JS_VALUE_TO_PTR(argv[0]);
                e = p1->u.regexp.last_index;
                if (e > s)
                    e = s;
                if (e == p) {
                    int c = string_getcp(ctx, *this_val, q, TRUE);
                    /* since regexp are unicode by default, split is also unicode by default */
                    q += 1 + (c >= 0x10000);
                } else {
                    T = js_sub_string(ctx, *this_val, p, q);
                    if (JS_IsException(T))
                        goto exception;
                    ret = JS_SetPropertyUint32(ctx, *A, lengthA++, T);
                    if (JS_IsException(ret))
                        goto exception;
                    if (lengthA == lim)
                        goto done;
                    p1 = JS_VALUE_TO_PTR(*z);
                    numberOfCaptures = p1->u.array.len;
                    for(i = 1; i < numberOfCaptures; i++) {
                        p1 = JS_VALUE_TO_PTR(*z);
                        arr = JS_VALUE_TO_PTR(p1->u.array.tab);
                        T = arr->arr[i];
                        ret = JS_SetPropertyUint32(ctx, *A, lengthA++, T);
                        if (JS_IsException(ret))
                            goto exception;
                    }
                    q = p = e;
                }
            }
        }
    } else {
        int r = js_string_len(ctx, argv[0]);
        if (s == 0) {
            if (r != 0)
                goto add_tail;
            goto done;
        }
        
        for (q = 0; (q += !r) <= s - r - !r; q = p = e + r) {
            
            e = js_string_indexof(ctx, *this_val, argv[0], q, s, r);
            if (e < 0)
                break;
            T = js_sub_string(ctx, *this_val, p, e);
            if (JS_IsException(T))
                goto exception;
            ret = JS_SetPropertyUint32(ctx, *A, lengthA++, T);
            if (JS_IsException(ret))
                goto exception;
            if (lengthA == lim)
                goto done;
        }
    }
add_tail:
    T = js_sub_string(ctx, *this_val, p, s);
    if (JS_IsException(T))
        goto exception;
    ret = JS_SetPropertyUint32(ctx, *A, lengthA++, T);
    if (JS_IsException(ret))
        goto exception;
    
done:
    JS_PopGCRef(ctx, &z_ref);
    return JS_PopGCRef(ctx, &A_ref);

exception:
    JS_PopGCRef(ctx, &z_ref);
    JS_PopGCRef(ctx, &A_ref);
    return JS_EXCEPTION;
}

JSValue js_string_match(JSContext *ctx, JSValue *this_val,
                        int argc, JSValue *argv)
{
    JSRegExp *re;
    int global, n;
    JSValue *A, *result, ret;
    JSObject *p;
    JSValueArray *arr;
    JSByteArray *barr;
    JSGCRef A_ref, result_ref;
    
    re = js_get_regexp(ctx, argv[0]);
    if (!re)
        return JS_EXCEPTION;
    barr = JS_VALUE_TO_PTR(re->byte_code);
    global = lre_get_flags(barr->buf) & LRE_FLAG_GLOBAL;
    if (!global)
        return js_regexp_exec(ctx, &argv[0], 1, this_val, 0);

    p = JS_VALUE_TO_PTR(argv[0]);
    re = &p->u.regexp;
    re->last_index = 0;

    A = JS_PushGCRef(ctx, &A_ref);
    result = JS_PushGCRef(ctx, &result_ref);
    *A = JS_NULL;
    n = 0;
    for(;;) {
        *result = js_regexp_exec(ctx, &argv[0], 1, this_val, 0);
        if (JS_IsException(*result))
            goto fail;
        if (*result == JS_NULL)
            break;
        if (*A == JS_NULL) {
            *A = JS_NewArray(ctx, 1);
            if (JS_IsException(*A))
                goto fail;
        }

        p = JS_VALUE_TO_PTR(*result);
        arr = JS_VALUE_TO_PTR(p->u.array.tab);

        ret = JS_SetPropertyUint32(ctx, *A, n++, arr->arr[0]);
        if (JS_IsException(ret)) {
        fail:
            *A = JS_EXCEPTION;
            break;
        }
    }
    JS_PopGCRef(ctx, &result_ref);
    return JS_PopGCRef(ctx, &A_ref);
}

JSValue js_string_search(JSContext *ctx, JSValue *this_val,
                         int argc, JSValue *argv)
{
    return js_regexp_exec(ctx, &argv[0], 1, this_val, MAGIC_REGEXP_SEARCH);
}
