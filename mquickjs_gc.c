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
/* garbage collector */

/* return the size in bytes */
int get_mblock_size(const void *ptr)
{
    int mtag = ((JSMemBlockHeader *)ptr)->mtag;
    int size;
    switch(mtag) {
    case JS_MTAG_OBJECT:
        {
            const JSObject *p = ptr;
            size = offsetof(JSObject, u) + p->extra_size * JSW;
        }
        break;
    case JS_MTAG_FLOAT64:
        size = sizeof(JSFloat64);
        break;
    case JS_MTAG_STRING:
        {
            const JSString *p = ptr;
            size = sizeof(JSString) + ((p->len + JSW) & ~(JSW - 1));
        }
        break;
    case JS_MTAG_BYTE_ARRAY:
        {
            const JSByteArray *p = ptr;
            size = sizeof(JSByteArray) + ((p->size + JSW - 1) & ~(JSW - 1));
        }
        break;
    case JS_MTAG_VALUE_ARRAY:
        {
            const JSValueArray *p = ptr;
            size = sizeof(JSValueArray) + p->size * sizeof(p->arr[0]);
        }
        break;
    case JS_MTAG_FREE:
        {
            const JSFreeBlock *p = ptr;
            size = sizeof(JSFreeBlock) + p->size * sizeof(JSWord);
        }
        break;
    case JS_MTAG_VARREF:
        {
            const JSVarRef *p = ptr;
            size = sizeof(JSVarRef);
            if (p->is_detached)
                size -= sizeof(JSValue);
        }
        break;
    case JS_MTAG_FUNCTION_BYTECODE:
        size = sizeof(JSFunctionBytecode);
        break;
    default:
        size = 0;
        assert(0);
    }
    return size;
}

/* gc mark pass */

BOOL mtag_has_references(int mtag)
{
    return (mtag == JS_MTAG_OBJECT ||
            mtag == JS_MTAG_VALUE_ARRAY ||
            mtag == JS_MTAG_VARREF ||
            mtag == JS_MTAG_FUNCTION_BYTECODE);
}

void gc_mark(GCMarkState *s, JSValue val)
{
    JSContext *ctx = s->ctx;
    void *ptr;
    JSMemBlockHeader *mb;

    if (!JS_IsPtr(val))
        return;
    ptr = JS_VALUE_TO_PTR(val);
    if (JS_IS_ROM_PTR(ctx, ptr))
        return;
    mb = ptr;
    if (mb->gc_mark)
        return;
    mb->gc_mark = 1;
    if (mtag_has_references(mb->mtag)) {
        if (mb->mtag == JS_MTAG_VALUE_ARRAY) {
            /* value array are handled specifically to save stack space */
            if ((s->gsp - s->gs_bottom) < 2) {
                s->overflow = TRUE;
            } else {
                *--s->gsp = 0;
                *--s->gsp = val;
            }
        } else {
            if ((s->gsp - s->gs_bottom) < 1) {
                s->overflow = TRUE;
            } else {
                *--s->gsp = val;
            }
        }
    }
}

/* flush the GC mark stack */
void gc_mark_flush(GCMarkState *s)
{
    void *ptr;
    JSMemBlockHeader *mb;
    JSValue val;
    
    while (s->gsp < s->gs_top) {
        val = *s->gsp++;
        ptr = JS_VALUE_TO_PTR(val);
        mb = ptr;

        switch(mb->mtag) {
        case JS_MTAG_OBJECT:
            {
                const JSObject *p = ptr;
                gc_mark(s, p->proto);
                gc_mark(s, p->props);
                switch(p->class_id) {
                case JS_CLASS_CLOSURE:
                    {
                        int i;
                        gc_mark(s, p->u.closure.func_bytecode);
                        for(i = 0; i < p->extra_size - 1; i++)
                            gc_mark(s, p->u.closure.var_refs[i]);
                    }
                    break;
                case JS_CLASS_C_FUNCTION:
                    if (p->extra_size > 1)
                        gc_mark(s, p->u.cfunc.params);
                    break;
                case JS_CLASS_ARRAY:
                    gc_mark(s, p->u.array.tab);
                    break;
                case JS_CLASS_ERROR:
                    gc_mark(s, p->u.error.message);
                    gc_mark(s, p->u.error.stack);
                    break;
                case JS_CLASS_ARRAY_BUFFER:
                    gc_mark(s, p->u.array_buffer.byte_buffer);
                    break;
                case JS_CLASS_UINT8C_ARRAY:
                case JS_CLASS_INT8_ARRAY:
                case JS_CLASS_UINT8_ARRAY:
                case JS_CLASS_INT16_ARRAY:
                case JS_CLASS_UINT16_ARRAY:
                case JS_CLASS_INT32_ARRAY:
                case JS_CLASS_UINT32_ARRAY:
                case JS_CLASS_FLOAT32_ARRAY:
                case JS_CLASS_FLOAT64_ARRAY:
                    gc_mark(s, p->u.typed_array.buffer);
                    break;
                case JS_CLASS_REGEXP:
                    gc_mark(s, p->u.regexp.source);
                    gc_mark(s, p->u.regexp.byte_code);
                    break;
                }
            }
            break;
        case JS_MTAG_VALUE_ARRAY:
            {
                const JSValueArray *p = ptr;
                int pos;

                pos = *s->gsp++;

                /* fast path to skip non objects */
                while (pos < p->size && !JS_IsPtr(p->arr[pos]))
                    pos++;

                if (pos < p->size) {
                    if ((pos + 1) < p->size) {
                        /* the next element needs to be scanned */
                        *--s->gsp = pos + 1;
                        *--s->gsp = val;
                    }
                    /* mark the current element */
                    gc_mark(s, p->arr[pos]);
                }
            }
            break;
        case JS_MTAG_VARREF:
            {
                const JSVarRef *p = ptr;
                gc_mark(s, p->u.value);
            }
            break;
        case JS_MTAG_FUNCTION_BYTECODE:
            {
                const JSFunctionBytecode *b = ptr;
                gc_mark(s, b->func_name);
                gc_mark(s, b->byte_code);
                gc_mark(s, b->cpool);
                gc_mark(s, b->vars);
                gc_mark(s, b->ext_vars);
                gc_mark(s, b->filename);
                gc_mark(s, b->pc2line);
            }
            break;
        default:
            break;
        }
    }
}

void gc_mark_root(GCMarkState *s, JSValue val)
{
    gc_mark(s, val);
    gc_mark_flush(s);
}

/* return true if the memory block is marked i.e. it won't be freed by the GC */
BOOL gc_mb_is_marked(JSValue val)
{
    JSFreeBlock *b;
    if (!JS_IsPtr(val))
        return FALSE;
    b = (JSFreeBlock *)JS_VALUE_TO_PTR(val);
    return b->gc_mark;
}

void gc_mark_all(JSContext *ctx, BOOL keep_atoms)
{
    GCMarkState s_s, *s = &s_s;
    JSValue *sp, *sp_end;

    s->ctx = ctx;
    /* initialize the GC stack */
    s->overflow = FALSE;
    s->gs_top = ctx->sp;
    s->gsp = s->gs_top;
#if 1
    s->gs_bottom = (JSValue *)ctx->heap_free;
#else
    s->gs_bottom = s->gs_top - 3; /* TEST small stack space */
#endif

    /* keep the atoms if they are in RAM (only used when compiling to file) */
    if ((uint8_t *)ctx->atom_table == ctx->heap_base &&
        keep_atoms) {
        uint8_t *ptr;
        for(ptr = (uint8_t *)ctx->atom_table;
            ptr < (uint8_t *)(ctx->atom_table + JS_ATOM_END);
            ptr += get_mblock_size(ptr)) {
            gc_mark_root(s, JS_VALUE_FROM_PTR(ptr));
        }
    }
    
    /* mark all the memory blocks */
    sp_end = ctx->class_proto + 2 * ctx->class_count;
    for(sp = &ctx->current_exception; sp < sp_end; sp++) {
        gc_mark_root(s, *sp);
    }

    for(sp = ctx->sp; sp < (JSValue *)ctx->stack_top; sp++) {
        gc_mark_root(s, *sp);
    }

    {
        JSGCRef *ref;
        for(ref = ctx->top_gc_ref; ref != NULL; ref = ref->prev) {
            gc_mark_root(s, ref->val);
        }
        for(ref = ctx->last_gc_ref; ref != NULL; ref = ref->prev) {
            gc_mark_root(s, ref->val);
        }
    }
    if (ctx->parse_state) {
        JSParseState *ps = ctx->parse_state;

        gc_mark_root(s, ps->source_str);
        gc_mark_root(s, ps->filename_str);
        gc_mark_root(s, ps->token.value);
        gc_mark_root(s, ps->cur_func);
        gc_mark_root(s, ps->byte_code);
    }

    /* if the mark stack overflowed, need to scan the heap */
    while (s->overflow) {
        uint8_t *ptr;
        int size;
        JSMemBlockHeader *mb;
        
        s->overflow = FALSE;
        
        ptr = ctx->heap_base;
        while (ptr < ctx->heap_free) {
            size = get_mblock_size(ptr);
            mb = (JSMemBlockHeader *)ptr;
            if (mb->gc_mark && mtag_has_references(mb->mtag)) {
                if (mb->mtag == JS_MTAG_VALUE_ARRAY)
                    *--s->gsp = 0;
                *--s->gsp = JS_VALUE_FROM_PTR(ptr);
                gc_mark_flush(s);
            }
            ptr += size;
        }
    }

    /* update the unique string table (its elements are considered as
       weak string references) */
    if (!JS_IsNull(ctx->unique_strings)) {
        JSValueArray *arr = JS_VALUE_TO_PTR(ctx->unique_strings);
        int i, j;

        j = 0;
        for(i = 0; i < arr->size; i++) {
            if (gc_mb_is_marked(arr->arr[i])) {
                arr->arr[j++] = arr->arr[i];
            }
        }
        ctx->unique_strings_len = j;
        if (j > 0) {
            arr->gc_mark = 1;
            if (j < arr->size) {
                /* shrink the array */
                set_free_block(&arr->arr[j], (arr->size - j) * sizeof(JSValue));
                arr->size = j;
            }
        } else {
            arr->gc_mark = 0;
            ctx->unique_strings = JS_NULL;
        }
    }

    /* update the weak references in the string position cache  */
    {
        int i;
        JSStringPosCacheEntry *ce;
        for(i = 0; i < JS_STRING_POS_CACHE_SIZE; i++) {
            ce = &ctx->string_pos_cache[i];
            if (!gc_mb_is_marked(ce->str))
                ce->str = JS_NULL;
        }
    }
    
    /* reset the gc marks and mark the free blocks as free */
    {
        uint8_t *ptr, *ptr1;
        int size;
        JSFreeBlock *b;

        ptr = ctx->heap_base;
        while (ptr < ctx->heap_free) {
            size = get_mblock_size(ptr);
            b = (JSFreeBlock *)ptr;
            if (b->gc_mark) {
                b->gc_mark = 0;
            } else {
                JSObject *p = (void *)ptr;
                /* call the user finalizer if needed */
                if (p->mtag == JS_MTAG_OBJECT && p->class_id >= JS_CLASS_USER &&
                    ctx->c_finalizer_table[p->class_id - JS_CLASS_USER] != NULL) {
                    ctx->c_finalizer_table[p->class_id - JS_CLASS_USER](ctx, p->u.user.opaque);
                }
                /* merge all the consecutive free blocks */
                ptr1 = ptr + size;
                while (ptr1 < ctx->heap_free && ((JSFreeBlock *)ptr1)->gc_mark == 0) {
                    ptr1 += get_mblock_size(ptr1);
                }
                size = ptr1 - ptr;
                set_free_block(b, size);
            }
            ptr += size;
        }
    }
}

JSValue js_value_from_pval(JSContext *ctx, JSValue *pval)
{
    return JS_VALUE_FROM_PTR(pval);
}

JSValue *js_value_to_pval(JSContext *ctx, JSValue val)
{
    return JS_VALUE_TO_PTR(val);
}

void gc_thread_pointer(JSContext *ctx, JSValue *pval)
{
    JSValue val;
    JSValue *ptr;
    
    val = *pval;
    if (!JS_IsPtr(val))
        return;
    ptr = JS_VALUE_TO_PTR(val);
    if (JS_IS_ROM_PTR(ctx, ptr))
        return;
    /* gc_mark = 0 indicates a normal memory block header, gc_mark = 1
       indicates a pointer to another element */
    *pval = *ptr;
    *ptr = js_value_from_pval(ctx, pval);
}

void gc_update_threaded_pointers(JSContext *ctx, void *ptr, void *new_ptr)
{
    JSValue val, *pv;

    val = *(JSValue *)ptr;
    if (JS_IsPtr(val)) {
        /* update the threaded pointers to the node 'ptr' and
           unthread it. */
        for(;;) {
            pv = js_value_to_pval(ctx, val);
            val = *pv;
            *pv = JS_VALUE_FROM_PTR(new_ptr);
            if (!JS_IsPtr(val))
                break;
        }
        *(JSValue *)ptr = val;
    }
}

void gc_thread_block(JSContext *ctx, void *ptr)
{
    int mtag;
    
    mtag = ((JSMemBlockHeader *)ptr)->mtag;
    switch(mtag) {
    case JS_MTAG_OBJECT:
        {
            JSObject *p = ptr;
            gc_thread_pointer(ctx, &p->proto);
            gc_thread_pointer(ctx, &p->props);
            switch(p->class_id) {
            case JS_CLASS_CLOSURE:
                {
                    int i;
                    gc_thread_pointer(ctx, &p->u.closure.func_bytecode);
                    for(i = 0; i < p->extra_size - 1; i++)
                        gc_thread_pointer(ctx, &p->u.closure.var_refs[i]);
                }
                break;
            case JS_CLASS_C_FUNCTION:
                if (p->extra_size > 1)
                    gc_thread_pointer(ctx, &p->u.cfunc.params);
                break;
            case JS_CLASS_ARRAY:
                gc_thread_pointer(ctx, &p->u.array.tab);
                break;
            case JS_CLASS_ERROR:
                gc_thread_pointer(ctx, &p->u.error.message);
                gc_thread_pointer(ctx, &p->u.error.stack);
                break;
            case JS_CLASS_ARRAY_BUFFER:
                gc_thread_pointer(ctx, &p->u.array_buffer.byte_buffer);
                break;
            case JS_CLASS_UINT8C_ARRAY:
            case JS_CLASS_INT8_ARRAY:
            case JS_CLASS_UINT8_ARRAY:
            case JS_CLASS_INT16_ARRAY:
            case JS_CLASS_UINT16_ARRAY:
            case JS_CLASS_INT32_ARRAY:
            case JS_CLASS_UINT32_ARRAY:
            case JS_CLASS_FLOAT32_ARRAY:
            case JS_CLASS_FLOAT64_ARRAY:
                gc_thread_pointer(ctx, &p->u.typed_array.buffer);
                break;
            case JS_CLASS_REGEXP:
                gc_thread_pointer(ctx, &p->u.regexp.source);
                gc_thread_pointer(ctx, &p->u.regexp.byte_code);
                break;
            }
        }
        break;
    case JS_MTAG_VALUE_ARRAY:
        {
            JSValueArray *p = ptr;
            int i;
            for(i = 0; i < p->size; i++) {
                gc_thread_pointer(ctx, &p->arr[i]);
            }
        }
        break;
    case JS_MTAG_VARREF:
        {
            JSVarRef *p = ptr;
            gc_thread_pointer(ctx, &p->u.value);
        }
        break;
    case JS_MTAG_FUNCTION_BYTECODE:
        {
            JSFunctionBytecode *b = ptr;
            gc_thread_pointer(ctx, &b->func_name);
            gc_thread_pointer(ctx, &b->byte_code);
            gc_thread_pointer(ctx, &b->cpool);
            gc_thread_pointer(ctx, &b->vars);
            gc_thread_pointer(ctx, &b->ext_vars);
            gc_thread_pointer(ctx, &b->filename);
            gc_thread_pointer(ctx, &b->pc2line);
        }
        break;
    default:
        break;
    }
}

/* Heap compaction using Jonkers algorithm */
void gc_compact_heap(JSContext *ctx)
{
    uint8_t *ptr, *new_ptr;
    int size;
    JSValue *sp, *sp_end;
    
    /* thread all the external pointers */
    sp_end = ctx->class_proto + 2 * ctx->class_count;
    for(sp = &ctx->unique_strings; sp < sp_end; sp++) {
        gc_thread_pointer(ctx, sp);
    }
    {
        int i;
        JSStringPosCacheEntry *ce;
        for(i = 0; i < JS_STRING_POS_CACHE_SIZE; i++) {
            ce = &ctx->string_pos_cache[i];
            gc_thread_pointer(ctx, &ce->str);
        }
    }
    
    for(sp = ctx->sp; sp < (JSValue *)ctx->stack_top; sp++) {
        gc_thread_pointer(ctx, sp);
    }

    {
        JSGCRef *ref;
        for(ref = ctx->top_gc_ref; ref != NULL; ref = ref->prev) {
            gc_thread_pointer(ctx, &ref->val);
        }
        for(ref = ctx->last_gc_ref; ref != NULL; ref = ref->prev) {
            gc_thread_pointer(ctx, &ref->val);
        }
    }

    if (ctx->parse_state) {
        JSParseState *ps = ctx->parse_state;

        gc_thread_pointer(ctx, &ps->source_str);
        gc_thread_pointer(ctx, &ps->filename_str);
        gc_thread_pointer(ctx, &ps->token.value);
        gc_thread_pointer(ctx, &ps->cur_func);
        gc_thread_pointer(ctx, &ps->byte_code);
    }

    /* pass 1: thread the pointers and update the previous ones */
    new_ptr = ctx->heap_base;
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        gc_update_threaded_pointers(ctx, ptr, new_ptr);
        size = get_mblock_size(ptr);
        if (js_get_mtag(ptr) != JS_MTAG_FREE) {
            gc_thread_block(ctx, ptr);
            new_ptr += size;
        }
        ptr += size;
    }
    
    /* pass 2: update the threaded pointers and move the block to its
       final position */
    new_ptr = ctx->heap_base;
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        gc_update_threaded_pointers(ctx, ptr, new_ptr);
        size = get_mblock_size(ptr);
        if (js_get_mtag(ptr) != JS_MTAG_FREE) {
            if (new_ptr != ptr) {
                memmove(new_ptr, ptr, size);
            }
            new_ptr += size;
        }
        ptr += size;
    }
    ctx->heap_free = new_ptr;

    /* update the source pointer in the parser */
    if (ctx->parse_state) {
        JSParseState *ps = ctx->parse_state;
        if (JS_IsPtr(ps->source_str)) {
            JSString *p = JS_VALUE_TO_PTR(ps->source_str);
            ps->source_buf = p->buf;
        }
    }
    
    /* rehash the object properties */
    /* XXX: try to do it in the previous pass (add a specific tag ?) */
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        size = get_mblock_size(ptr);
        if (js_get_mtag(ptr) == JS_MTAG_OBJECT) {
            js_rehash_props(ctx, (JSObject *)ptr, TRUE);
        }
        ptr += size;
    }
}

void JS_GC2(JSContext *ctx, BOOL keep_atoms)
{
#ifdef DUMP_GC
    js_printf(ctx, "GC   : heap size=%u/%u stack_size=%u\n",
           (uint32_t)(ctx->heap_free - ctx->heap_base),
           (uint32_t)(ctx->stack_top - ctx->heap_base),
           (uint32_t)(ctx->stack_top - (uint8_t *)ctx->sp));
#endif
#if defined(DEBUG_GC)
    /* reduce the dummy block size at each GC to change the addresses
       after compaction */
    /* XXX: only works a finite number of times */
    {
        JSByteArray *arr;
        if (JS_IsPtr(ctx->dummy_block)) {
            arr = JS_VALUE_TO_PTR(ctx->dummy_block);
            if (arr->size >= 8) {
                js_shrink_byte_array(ctx, &ctx->dummy_block, arr->size - 4);
                if (arr->size == 4) {
                    js_printf(ctx, "WARNING: debug GC: no longer modifying the addresses\n");
                }
            }
        }
    }
#endif
    gc_mark_all(ctx, keep_atoms);
    gc_compact_heap(ctx);
#ifdef DUMP_GC
    js_printf(ctx, "AFTER: heap size=%u/%u stack_size=%u\n",
           (uint32_t)(ctx->heap_free - ctx->heap_base),
           (uint32_t)(ctx->stack_top - ctx->heap_base),
           (uint32_t)(ctx->stack_top - (uint8_t *)ctx->sp));
#endif
}

void JS_GC(JSContext *ctx)
{
    JS_GC2(ctx, TRUE);
}

/* bytecode saving and loading */

#define JS_BYTECODE_VERSION_32 0x0001
/* bit 15 of bytecode version is a 64-bit indicator */
#define JS_BYTECODE_VERSION (JS_BYTECODE_VERSION_32 | ((JSW & 8) << 12))

void JS_PrepareBytecode(JSContext *ctx,
                        JSBytecodeHeader *hdr,
                        const uint8_t **pdata_buf, uint32_t *pdata_len,
                        JSValue eval_code)
{
    JSGCRef eval_code_ref;
    int i;
    
    /* remove all the objects except the compiled code */
    ctx->empty_props = JS_NULL;
    for(i = 0; i < ctx->class_count; i++) {
        ctx->class_proto[i] = JS_NULL;
        ctx->class_obj[i] = JS_NULL;
    }
    ctx->global_obj = JS_NULL;
#ifdef DEBUG_GC
    ctx->dummy_block = JS_NULL;
#endif
    
    JS_PUSH_VALUE(ctx, eval_code);
    JS_GC2(ctx, FALSE);
    JS_POP_VALUE(ctx, eval_code);

    hdr->magic = JS_BYTECODE_MAGIC;
    hdr->version = JS_BYTECODE_VERSION;
    hdr->base_addr = (uintptr_t)ctx->heap_base;
    hdr->unique_strings =  ctx->unique_strings;
    hdr->main_func = eval_code;

    *pdata_buf = ctx->heap_base;
    *pdata_len = ctx->heap_free - ctx->heap_base;
}

#if JSW == 8

typedef uint32_t JSValue_32;
typedef uint32_t JSWord_32;

#define JS_MB_HEADER_32  \
    JSWord_32 gc_mark: 1; \
    JSWord_32 mtag: (JS_MTAG_BITS - 1)

#define JS_MB_PAD_32(n)  (32 - (n))

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 dummy: JS_MB_PAD_32(JS_MTAG_BITS);
} JSMemBlockHeader_32;

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 size: JS_MB_PAD_32(JS_MTAG_BITS);
    JSValue_32 arr[];
} JSValueArray_32;

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 size: JS_MB_PAD_32(JS_MTAG_BITS);
    uint8_t buf[];
} JSByteArray_32;

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 dummy: JS_MB_PAD_32(JS_MTAG_BITS);
    /* unaligned 64 bit access in 32-bit mode */
    struct __attribute__((packed)) {
        double dval;
    } u;
} JSFloat64_32;

#define JS_STRING_LEN_MAX_32 ((1 << (32 - JS_MTAG_BITS - 3)) - 1)

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 is_unique: 1;
    JSWord_32 is_ascii: 1;
    /* true if the string content represents a number, only meaningful
       is is_unique = true */
    JSWord_32 is_numeric: 1;
    JSWord_32 len: JS_MB_PAD_32(JS_MTAG_BITS + 3);
    uint8_t buf[];
} JSString_32;

typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 has_arguments : 1; /* only used during parsing */
    JSWord_32 has_local_func_name : 1; /* only used during parsing */
    JSWord_32 has_column : 1; /* column debug info is present */
    JSWord_32 arg_count : 16;
    JSWord_32 dummy: JS_MB_PAD_32(JS_MTAG_BITS + 3 + 16);

    JSValue_32 func_name; /* JS_NULL if anonymous function */
    JSValue_32 byte_code; /* JS_NULL if the function is not parsed yet */
    JSValue_32 cpool; /* constant pool */
    JSValue_32 vars; /* only for debug */
    JSValue_32 ext_vars; /* records of (var_name, var_kind (2 bits) var_idx (16 bits)) */
    uint16_t stack_size; /* maximum stack size */
    uint16_t ext_vars_len; /* XXX: only used during parsing */
    JSValue_32 filename; /* filename in which the function is defined */
    JSValue_32 pc2line; /* JSByteArray or JS_NULL if not initialized */
    uint32_t source_pos; /* only used during parsing (XXX: shrink) */
} JSFunctionBytecode_32;

/* warning: ptr1 and ptr may overlap. However there is always: ptr1 <= ptr. Return 0 if OK. */
int convert_mblock_64to32(void *ptr1, const void *ptr)
{
    int mtag, i;

    mtag = ((JSMemBlockHeader*)ptr)->mtag;
    switch(mtag) {
    case JS_MTAG_FUNCTION_BYTECODE:
        {
            const JSFunctionBytecode *b = ptr;
            JSFunctionBytecode_32 *b1 = ptr1;
            b1->gc_mark = b->gc_mark;
            b1->mtag = b->mtag;
            b1->has_arguments = b->has_arguments;
            b1->has_local_func_name = b->has_local_func_name;
            b1->has_column = b->has_column;
            b1->arg_count = b->arg_count;
            b1->dummy = 0;
            b1->func_name = b->func_name;
            b1->byte_code = b->byte_code;
            b1->cpool = b->cpool;
            b1->vars = b->vars;
            b1->ext_vars = b->ext_vars;
            b1->stack_size = b->stack_size;
            b1->ext_vars_len = b->ext_vars_len;
            b1->filename = b->filename;
            b1->pc2line = b->pc2line;
            b1->source_pos = b->source_pos;
        }
        break;
    case JS_MTAG_FLOAT64:
        {
            const JSFloat64 *b = ptr;
            JSFloat64_32 *b1 = ptr1;

            b1->gc_mark = b->gc_mark;
            b1->mtag = b->mtag;
            b1->dummy = 0;
            b1->u.dval = b->u.dval;
        }
        break;
    case JS_MTAG_VALUE_ARRAY:
        {
            const JSValueArray *b = ptr;
            JSValueArray_32 *b1 = ptr1;

            b1->gc_mark = b->gc_mark;
            b1->mtag = b->mtag;
            b1->size = b->size; /* no test needed as long as JS_VALUE_ARRAY_SIZE_MAX is identical */
            for(i = 0; i < b1->size; i++)
                b1->arr[i] = b->arr[i];
        }
        break;
    case JS_MTAG_BYTE_ARRAY:
        {
            const JSByteArray *b = ptr;
            JSByteArray_32 *b1 = ptr1;

            b1->gc_mark = b->gc_mark;
            b1->mtag = b->mtag;
            b1->size = b->size; /* no test needed as long as JS_BYTE_ARRAY_SIZE_MAX is identical */
            memmove(b1->buf, b->buf, b1->size);
        }
        break;
    case JS_MTAG_STRING:
        {
            const JSString *b = ptr;
            JSString_32 *b1 = ptr1;

            if (b->len > JS_STRING_LEN_MAX_32)
                return -1;
            b1->gc_mark = b->gc_mark;
            b1->mtag = b->mtag;
            b1->is_unique = b->is_unique;
            b1->is_ascii = b->is_ascii;
            b1->is_numeric = b->is_numeric;
            b1->len = b->len;
            memmove(b1->buf, b->buf, b1->len + 1);
        }
        break;
    default:
        abort();
    }
    return 0;
}

/* return the size in bytes */
int get_mblock_size_32(const void *ptr)
{
    int mtag = ((JSMemBlockHeader_32 *)ptr)->mtag;
    int size;
    switch(mtag) {
    case JS_MTAG_FLOAT64:
        size = sizeof(JSFloat64_32);
        break;
    case JS_MTAG_STRING:
        {
            const JSString_32 *p = ptr;
            size = sizeof(JSString_32) + ((p->len + 4) & ~(4 - 1));
        }
        break;
    case JS_MTAG_BYTE_ARRAY:
        {
            const JSByteArray_32 *p = ptr;
            size = sizeof(JSByteArray_32) + ((p->size + 4 - 1) & ~(4 - 1));
        }
        break;
    case JS_MTAG_VALUE_ARRAY:
        {
            const JSValueArray_32 *p = ptr;
            size = sizeof(JSValueArray_32) + p->size * sizeof(p->arr[0]);
        }
        break;
    case JS_MTAG_FUNCTION_BYTECODE:
        size = sizeof(JSFunctionBytecode_32);
        break;
    default:
        size = 0;
        assert(0);
    }
    return size;
}

/* Compact and convert a 64 bit heap to a 32 bit heap at offset
   0. Only used for code compilation. Return 0 if OK. */
int gc_compact_heap_64to32(JSContext *ctx)
{
    uint8_t *ptr;
    int size, size_32;
    uintptr_t new_offset;
    
    gc_thread_pointer(ctx, &ctx->unique_strings);

    /* thread all the external pointers */
    {
        JSGCRef *ref;
        /* necessary because JS_PUSH_VAL() is called before
           gc_compact_heap_64to32() */
        for(ref = ctx->top_gc_ref; ref != NULL; ref = ref->prev) {
            gc_thread_pointer(ctx, &ref->val);
        }
    }

    /* pass 1: thread the pointers and update the previous ones */
    new_offset = 0;
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        gc_update_threaded_pointers(ctx, ptr, (uint8_t *)new_offset);
        size = get_mblock_size(ptr);
        if (js_get_mtag(ptr) != JS_MTAG_FREE) {
            gc_thread_block(ctx, ptr);
            size_32 = get_mblock_size_32(ptr);
            new_offset += size_32;
        }
        ptr += size;
    }
    
    /* pass 2: update the threaded pointers and move the block to its
       final position */
    new_offset = 0;
    ptr = ctx->heap_base;
    while (ptr < ctx->heap_free) {
        gc_update_threaded_pointers(ctx, ptr, (uint8_t *)new_offset);
        size = get_mblock_size(ptr);
        if (js_get_mtag(ptr) != JS_MTAG_FREE) {
            size_32 = get_mblock_size_32(ptr);
            if (convert_mblock_64to32(ctx->heap_base + new_offset, ptr))
                return -1;
            new_offset += size_32;
        }
        ptr += size;
    }
    ctx->heap_free = ctx->heap_base + new_offset;
    return 0;
}

#ifdef JS_USE_SHORT_FLOAT

int expand_short_float(JSContext *ctx, JSValue *pval)
{
    JSFloat64 *f;
    if (JS_IsShortFloat(*pval)) {
        f = js_malloc(ctx, sizeof(JSFloat64), JS_MTAG_FLOAT64);
        if (!f)
            return -1;
        f->u.dval = js_get_short_float(*pval);
        *pval = JS_VALUE_FROM_PTR(f);
    }
    return 0;
}

/* Expand all the short floats to JSFloat64 structures. Return < 0 if
   not enough memory. */
int expand_short_floats(JSContext *ctx)
{
    uint8_t *ptr, *p_end;
    int mtag, size;
    
    ptr = ctx->heap_base;
    p_end = ctx->heap_free;
    while (ptr < p_end) {
        size = get_mblock_size(ptr);
        mtag = ((JSMemBlockHeader *)ptr)->mtag;
        switch(mtag) {
        case JS_MTAG_FUNCTION_BYTECODE:
            /* we assume no short floats here */
            break;
        case JS_MTAG_VALUE_ARRAY:
            {
                JSValueArray *p = (JSValueArray *)ptr;
                int i;
                for(i = 0; i < p->size; i++) {
                    if (expand_short_float(ctx, &p->arr[i]))
                        return -1;
                }
            }
            break;
        case JS_MTAG_STRING:
        case JS_MTAG_FLOAT64:
        case JS_MTAG_BYTE_ARRAY:
            break;
        default:
            abort();
        }
        ptr += size;
    }
    return 0;
}

#endif /* JS_USE_SHORT_FLOAT */

int JS_PrepareBytecode64to32(JSContext *ctx,
                             JSBytecodeHeader32 *hdr,
                             const uint8_t **pdata_buf, uint32_t *pdata_len,
                             JSValue eval_code)
{
    JSGCRef eval_code_ref;
    int i;
    
    /* remove all the objects except the compiled code */
    ctx->empty_props = JS_NULL;
    for(i = 0; i < ctx->class_count; i++) {
        ctx->class_proto[i] = JS_NULL;
        ctx->class_obj[i] = JS_NULL;
    }
    ctx->global_obj = JS_NULL;
#ifdef DEBUG_GC
    ctx->dummy_block = JS_NULL;
#endif
    
    JS_PUSH_VALUE(ctx, eval_code);
#ifdef JS_USE_SHORT_FLOAT
    JS_GC2(ctx, FALSE);
    if (expand_short_floats(ctx))
        return -1;
#else
    gc_mark_all(ctx, FALSE);
#endif    
    if (gc_compact_heap_64to32(ctx))
        return -1;
    JS_POP_VALUE(ctx, eval_code);

    hdr->magic = JS_BYTECODE_MAGIC;
    hdr->version = JS_BYTECODE_VERSION_32;
    hdr->base_addr = 0;
    hdr->unique_strings =  ctx->unique_strings;
    hdr->main_func = eval_code;

    *pdata_buf = ctx->heap_base;
    *pdata_len = ctx->heap_free - ctx->heap_base;
    /* ensure that JS_FreeContext() will do nothing */
    ctx->heap_free = ctx->heap_base; 
    return 0;
}
#endif /* JSW == 8 */

BOOL JS_IsBytecode(const uint8_t *buf, size_t buf_len)
{
    const JSBytecodeHeader *hdr = (const JSBytecodeHeader *)buf;
    return (buf_len >= sizeof(*hdr) && hdr->magic == JS_BYTECODE_MAGIC);
}

void bc_reloc_value(BCRelocState *s, JSValue *pval)
{
    JSContext *ctx = s->ctx;
    JSString *p;
    JSValue val, str;

    val = *pval;
    if (JS_IsPtr(val)) {
        val += s->offset;

        /* unique strings must be unique, so modify the unique string
           value if it already exists in the context */
        if (s->update_atoms) {
            p = JS_VALUE_TO_PTR(val);
            if (p->mtag == JS_MTAG_STRING && p->is_unique) {
                const JSValueArray *arr1;
                int a, i;
                for(i = 0; i < ctx->n_rom_atom_tables; i++) {
                    arr1 = ctx->rom_atom_tables[i];
                    str = find_atom(ctx, &a, arr1, arr1->size, val); 
                    if (!JS_IsNull(str)) {
                        val = str;
                        break;
                    }
                }
            }
        }
        *pval = val;
    }
}

int JS_RelocateBytecode2(JSContext *ctx, JSBytecodeHeader *hdr,
                         uint8_t *buf, uint32_t buf_len,
                         uintptr_t new_base_addr, BOOL update_atoms)
{
    uint8_t *ptr, *p_end;
    int size, mtag;
    BCRelocState ss, *s = &ss;
    
    if (hdr->magic != JS_BYTECODE_MAGIC)
        return -1;
    if (hdr->version != JS_BYTECODE_VERSION)
        return -1;

    /* XXX: add atom checksum to avoid problems if the stdlib is
       modified */
    s->ctx = ctx;
    s->offset = new_base_addr - hdr->base_addr;
    s->update_atoms = update_atoms;

    bc_reloc_value(s, &hdr->unique_strings);
    bc_reloc_value(s, &hdr->main_func);

    ptr = buf;
    p_end = buf + buf_len;
    while (ptr < p_end) {
        size = get_mblock_size(ptr);
        mtag = ((JSMemBlockHeader *)ptr)->mtag;
        switch(mtag) {
        case JS_MTAG_FUNCTION_BYTECODE:
            {
                JSFunctionBytecode *b = (JSFunctionBytecode *)ptr;
                bc_reloc_value(s, &b->func_name);
                bc_reloc_value(s, &b->byte_code);
                bc_reloc_value(s, &b->cpool);
                bc_reloc_value(s, &b->vars);
                bc_reloc_value(s, &b->ext_vars);
                bc_reloc_value(s, &b->filename);
                bc_reloc_value(s, &b->pc2line);
            }
            break;
        case JS_MTAG_VALUE_ARRAY:
            {
                JSValueArray *p = (JSValueArray *)ptr;
                int i;
                for(i = 0; i < p->size; i++) {
                    bc_reloc_value(s, &p->arr[i]);
                }
            }
            break;
        case JS_MTAG_STRING:
        case JS_MTAG_FLOAT64:
        case JS_MTAG_BYTE_ARRAY:
            break;
        default:
            abort();
        }
        ptr += size;
    }
    hdr->base_addr = new_base_addr;
    return 0;
}

/* Relocate the bytecode in 'buf' so that it can be executed
   later. Return 0 if OK, != 0 if error */
int JS_RelocateBytecode(JSContext *ctx,
                        uint8_t *buf, uint32_t buf_len)
{
    uint8_t *data_ptr;

    if (buf_len < sizeof(JSBytecodeHeader))
        return -1;
    data_ptr = buf + sizeof(JSBytecodeHeader);
    return JS_RelocateBytecode2(ctx, (JSBytecodeHeader *)buf,
                                data_ptr,
                                buf_len - sizeof(JSBytecodeHeader),
                                (uintptr_t)data_ptr, TRUE);
}

/* Load the precompiled bytecode from 'buf'. 'buf' must be allocated
   as long as the JSContext exists. Use JS_Run() to execute
   it. warning: the bytecode is not checked so it should come from a
   trusted source. */
JSValue JS_LoadBytecode(JSContext *ctx, const uint8_t *buf)
{
    const JSBytecodeHeader *hdr = (const JSBytecodeHeader *)buf;
    
    if (ctx->unique_strings_len != 0)
        return JS_ThrowInternalError(ctx, "no atom must be defined in RAM");
    /* XXX: could stack atom_tables */
    if (ctx->n_rom_atom_tables >= N_ROM_ATOM_TABLES_MAX)
        return JS_ThrowInternalError(ctx, "too many rom atom tables");
    if (hdr->magic != JS_BYTECODE_MAGIC)
        return JS_ThrowInternalError(ctx, "invalid bytecode magic");
    if ((hdr->version & 0x8000) != (JS_BYTECODE_VERSION & 0x8000))
        return JS_ThrowInternalError(ctx, "bytecode not saved for %d-bit", JSW * 8);
    if (hdr->version != JS_BYTECODE_VERSION)
        return JS_ThrowInternalError(ctx, "invalid bytecode version");
    if (hdr->base_addr != (uintptr_t)(hdr + 1))
        return JS_ThrowInternalError(ctx, "bytecode not relocated");
    ctx->rom_atom_tables[ctx->n_rom_atom_tables++] = (JSValueArray *)JS_VALUE_TO_PTR(hdr->unique_strings);
    return hdr->main_func;
}
