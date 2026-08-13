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
#ifdef DUMP_BYTECODE
__maybe_unused void dump_byte_code(JSContext *ctx, JSFunctionBytecode *b)
{
    JSByteArray *arr, *pc2line;
    JSValueArray *cpool, *vars, *ext_vars;
    const JSOpCode *oi;
    int pos, op, size, addr, idx, arg_count, len, i, line_num, col_num;
    int line_num1, col_num1, hoisted_code_len;
    uint8_t *tab;
    uint32_t pc2line_pos;
    
    arr = JS_VALUE_TO_PTR(b->byte_code);
    if (b->cpool != JS_NULL)
        cpool = JS_VALUE_TO_PTR(b->cpool);
    else
        cpool = NULL;
    if (b->vars != JS_NULL)
        vars = JS_VALUE_TO_PTR(b->vars);
    else
        vars = NULL;
    if (b->ext_vars != JS_NULL)
        ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
    else
        ext_vars = NULL;
    if (b->pc2line != JS_NULL)
        pc2line = JS_VALUE_TO_PTR(b->pc2line);
    else
        pc2line = NULL;

    arg_count = b->arg_count;

    JS_PrintValueF(ctx, b->filename, JS_DUMP_NOQUOTE);
    js_printf(ctx, ": function ");
    JS_PrintValueF(ctx, b->func_name, JS_DUMP_NOQUOTE);
    js_printf(ctx, ":\n");

    if (b->arg_count && vars) {
        js_printf(ctx, "  args:");
        for(i = 0; i < b->arg_count; i++) {
            js_printf(ctx, " ");
            JS_PrintValue(ctx, vars->arr[i]);
        }
        js_printf(ctx, "\n");
    }
    if (vars) {
        js_printf(ctx, "  locals:");
        for(i = 0; i < vars->size - b->arg_count; i++) {
            js_printf(ctx, " ");
            JS_PrintValue(ctx, vars->arr[i + b->arg_count]);
        }
        js_printf(ctx, "\n");
    }
    if (ext_vars) {
        js_printf(ctx, "  refs:");
        for(i = 0; i < b->ext_vars_len; i++) {
            int var_kind, var_idx, decl;
            static const char *var_kind_str[] = { "arg", "var", "ref", "global" };
            js_printf(ctx, " ");
            JS_PrintValue(ctx, ext_vars->arr[2 * i]);
            decl = JS_VALUE_GET_INT(ext_vars->arr[2 * i + 1]);
            var_kind = decl >> 16;
            var_idx = decl & 0xffff;
            js_printf(ctx, " (%s:%d)", var_kind_str[var_kind], var_idx);
        }
        js_printf(ctx, "\n");
    }
    
    js_printf(ctx, "  cpool_size: %d\n", cpool ? (int)cpool->size : 0);
    js_printf(ctx, "  stack_size: %d\n", b->stack_size);
    js_printf(ctx, "  opcodes:\n");
    tab = arr->buf;
    len = arr->size;
    pos = 0;
    pc2line_pos = 0;
    hoisted_code_len = 0;
    if (pc2line)
        hoisted_code_len = get_pc2line_hoisted_code_len(pc2line->buf, pc2line->size);
    line_num = 1;
    col_num = 1;
    line_num1 = 0;
    col_num1 = 0;
    while (pos < len) {
        /* extract the debug info */
        if (pc2line && pos >= hoisted_code_len) {
            get_pc2line(&line_num, &col_num, pc2line->buf, pc2line->size,
                        &pc2line_pos, b->has_column);
            if (line_num != line_num1 || col_num != col_num1) {
                js_printf(ctx, "    # %d", line_num);
                if (b->has_column)
                    js_printf(ctx, ", %d", col_num);
                js_printf(ctx, "\n");
                line_num1 = line_num;
                col_num1 = col_num;
            }
        }
        op = tab[pos];
        js_printf(ctx, "%5d: ", pos);
        if (op >= OP_COUNT) {
            js_printf(ctx, "invalid opcode (0x%02x)\n", op); 
            pos++;
            continue;
        }
        oi = &opcode_info[op];
        size = oi->size;
        if ((pos + size) > len) {
            js_printf(ctx, "truncated opcode (0x%02x)\n", op);
            break;
        }
        js_printf(ctx, "%s", oi->name);
        pos++;
        switch(oi->fmt) {
        case OP_FMT_u8:
            js_printf(ctx, " %u", (int)get_u8(tab + pos));
            break;
        case OP_FMT_i8:
            js_printf(ctx, " %d", (int)get_i8(tab + pos));
            break;
        case OP_FMT_u16:
        case OP_FMT_npop:
            js_printf(ctx, " %u", (int)get_u16(tab + pos));
            break;
        case OP_FMT_i16:
            js_printf(ctx, " %d", (int)get_i16(tab + pos));
            break;
        case OP_FMT_i32:
            js_printf(ctx, " %d", (int)get_i32(tab + pos));
            break;
        case OP_FMT_u32:
            js_printf(ctx, " %u", (int)get_u32(tab + pos));
            break;
        case OP_FMT_none_int:
            js_printf(ctx, " %d", op - OP_push_0);
            break;
#if 0
        case OP_FMT_npopx:
            js_printf(ctx, " %d", op - OP_call0);
            break;
#endif
        case OP_FMT_label8:
            addr = get_i8(tab + pos);
            goto has_addr1;
        case OP_FMT_label16:
            addr = get_i16(tab + pos);
            goto has_addr1;
        case OP_FMT_label:
            addr = get_u32(tab + pos);
            goto has_addr1;
        has_addr1:
            js_printf(ctx, " %u", addr + pos);
            break;
        case OP_FMT_const8:
            idx = get_u8(tab + pos);
            goto has_pool_idx;
        case OP_FMT_const16:
            idx = get_u16(tab + pos);
            goto has_pool_idx;
        has_pool_idx:
            js_printf(ctx, " %u: ", idx);
            if (idx < cpool->size) {
                JS_PrintValue(ctx, cpool->arr[idx]);
            }
            break;
        case OP_FMT_none_loc:
            idx = (op - OP_get_loc0) % 4;
            goto has_loc;
        case OP_FMT_loc8:
            idx = get_u8(tab + pos);
            goto has_loc;
        case OP_FMT_loc:
            idx = get_u16(tab + pos);
        has_loc:
            js_printf(ctx, " %d: ", idx);
            idx += arg_count;
            if (idx < vars->size) {
                JS_PrintValue(ctx, vars->arr[idx]);
            }
            break;
        case OP_FMT_none_arg:
            idx = (op - OP_get_arg0) % 4;
            goto has_arg;
        case OP_FMT_arg:
            idx = get_u16(tab + pos);
        has_arg:
            js_printf(ctx, " %d: ", idx);
            if (idx < vars->size) {
                JS_PrintValue(ctx, vars->arr[idx]);
            }
            break;
#if 0
        case OP_FMT_none_var_ref:
            idx = (op - OP_get_var_ref0) % 4;
            goto has_var_ref;
#endif            
        case OP_FMT_var_ref:
            idx = get_u16(tab + pos);
            //        has_var_ref:
            js_printf(ctx, " %d: ", idx);
            if (2 * idx < ext_vars->size) {
                JS_PrintValue(ctx, ext_vars->arr[2 * idx]);
            }
            break;
        case OP_FMT_value:
            js_printf(ctx, " ");
            idx = get_u32(tab + pos);
            JS_PrintValue(ctx, idx);
            break;
        default:
            break;
        }
        js_printf(ctx, "\n");
        pos += oi->size - 1;
    }
}
#endif /* DUMP_BYTECODE */

void next_token(JSParseState *s);

void __attribute((unused)) dump_token(JSParseState *s, const JSToken *token)
{
    JSContext *ctx = s->ctx;
    switch(token->val) {
    case TOK_NUMBER:
        /* XXX: TODO */
        js_printf(ctx, "number: %d\n", (int)token->u.d);
        break;
    case TOK_IDENT:
        {
            js_printf(ctx, "ident: ");
            JS_PrintValue(s->ctx, token->value);
            js_printf(ctx, "\n");
        }
        break;
    case TOK_STRING:
        {
            js_printf(ctx, "string: ");
            JS_PrintValue(s->ctx, token->value);
            js_printf(ctx, "\n");
        }
        break;
    case TOK_REGEXP:
        {
            js_printf(ctx, "regexp: ");
            JS_PrintValue(s->ctx, token->value);
            js_printf(ctx, "\n");
        }
        break;
    case TOK_EOF:
        js_printf(ctx, "eof\n");
        break;
    default:
        if (s->token.val >= TOK_FIRST_KEYWORD) {
            js_printf(ctx, "token: ");
            JS_PrintValue(s->ctx, token->value);
            js_printf(ctx, "\n");
        } else if (s->token.val >= 128) {
            js_printf(ctx, "token: %d\n", token->val);
        } else {
            js_printf(ctx, "token: '%c'\n", token->val);
        }
        break;
    }
}

/* return the zero based line and column number in the source. */

/* test if the current token is a label. XXX: we assume there is no
   space between the identifier and the ':' to avoid having to push
   back a token */
BOOL is_label(JSParseState *s)
{
    return (s->token.val == TOK_IDENT && s->source_buf[s->buf_pos] == ':');
}

inline uint8_t *get_byte_code(JSParseState *s)
{
    JSByteArray *arr;
    arr = JS_VALUE_TO_PTR(s->byte_code);
    return arr->buf;
}

void emit_claim_size(JSParseState *s, int n)
{
    JSValue val;
    val = js_resize_byte_array(s->ctx, s->byte_code, s->byte_code_len + n);
    if (JS_IsException(val))
        js_parse_error_mem(s);
    s->byte_code = val;
}

void emit_u8(JSParseState *s, uint8_t val)
{
    JSByteArray *arr;
    emit_claim_size(s, 1);
    arr = JS_VALUE_TO_PTR(s->byte_code);
    arr->buf[s->byte_code_len++] = val;
}

void emit_u16(JSParseState *s, uint16_t val)
{
    JSByteArray *arr;
    emit_claim_size(s, 2);
    arr = JS_VALUE_TO_PTR(s->byte_code);
    put_u16(arr->buf + s->byte_code_len, val);
    s->byte_code_len += 2;
}

void emit_u32(JSParseState *s, uint32_t val)
{
    JSByteArray *arr;
    emit_claim_size(s, 4);
    arr = JS_VALUE_TO_PTR(s->byte_code);
    put_u32(arr->buf + s->byte_code_len, val);
    s->byte_code_len += 4;
}

/* precondition: 1 <= n <= 25. */
void pc2line_put_bits_short(JSParseState *s, int n, uint32_t bits)
{
    JSFunctionBytecode *b;
    JSValue val1;
    JSByteArray *arr;
    uint32_t index, pos;
    unsigned int val;
    int shift;
    uint8_t *p;

    index = s->pc2line_bit_len;
    pos = index >> 3;

    /* resize the array if needed */
    b = JS_VALUE_TO_PTR(s->cur_func);
    val1 = js_resize_byte_array(s->ctx, b->pc2line, pos + 4);
    if (JS_IsException(val1))
        js_parse_error_mem(s);
    b = JS_VALUE_TO_PTR(s->cur_func);
    b->pc2line = val1;

    arr = JS_VALUE_TO_PTR(val1);
    p = arr->buf + pos;
    val = get_be32(p);
    shift = (32 - (index & 7) - n);
    val &= ~(((1U << n) - 1) << shift); /* reset the bits */
    val |= bits << shift;
    put_be32(p, val);
    s->pc2line_bit_len = index + n;
}

/* precondition: 1 <= n <= 32 */
void pc2line_put_bits(JSParseState *s, int n, uint32_t bits)
{
    int n_max = 25;
    if (unlikely(n > n_max)) {
        pc2line_put_bits_short(s, n - n_max, bits >> n_max);
        bits &= (1 << n_max) - 1;
        n = n_max;
    }
    pc2line_put_bits_short(s, n, bits);
}

/* 0 <= v < 2^32-1 */
void put_ugolomb(JSParseState *s, uint32_t v)
{
    int n;
    //    printf("put_ugolomb: %u\n", v);
    v++;
    n = 32 - clz32(v);
    if (n > 1)
        pc2line_put_bits(s, n - 1, 0);
    pc2line_put_bits(s, n, v);
}

/* v != -2^31 */
void put_sgolomb(JSParseState *s, int32_t v1)
{
    uint32_t v = v1;
    put_ugolomb(s, (2 * v) ^ -(v >> 31));
}

//#define DUMP_PC2LINE_STATS

#ifdef DUMP_PC2LINE_STATS
static int pc2line_freq[256];
static int pc2line_freq_tot;
#endif

/* return the difference between the line numbers from 'pos1' to
   'pos2'. If the difference is zero, '*pcol_num' contains the
   difference between the column numbers. Otherwise it contains the
   zero based absolute column number.
*/
int get_line_col_delta(int *pcol_num, const uint8_t *buf, int pos1, int pos2)
{
    int line_num, col_num, c, i;
    line_num = 0;
    col_num = 0;
    if (pos2 >= pos1) {
        line_num = get_line_col(&col_num, buf + pos1, pos2 - pos1);
    } else {
        line_num = get_line_col(&col_num, buf + pos2, pos1 - pos2);
        line_num = -line_num;
        col_num = -col_num;
        if (line_num != 0) {
            /* find the absolute column position */
            col_num = 0;
            for(i = pos2 - 1; i >= 0; i--) {
                c = buf[i];
                if (c == '\n') {
                    break;
                } else if (c < 0x80 || c >= 0xc0) {
                    col_num++;
                }
            }
        }
    }
    *pcol_num = col_num;
    return line_num;
}

void emit_pc2line(JSParseState *s, JSSourcePos pos)
{
    int line_delta, col_delta;

    line_delta = get_line_col_delta(&col_delta, s->source_buf,
                                    s->pc2line_source_pos, pos);
    put_sgolomb(s, line_delta);
    if (s->has_column) {
        if (line_delta == 0) {
#ifdef DUMP_PC2LINE_STATS
            pc2line_freq[min_int(max_int(col_delta + 128, 0), 255)]++;
            pc2line_freq_tot++;
#endif
            put_sgolomb(s, col_delta);
        } else {
            put_ugolomb(s, col_delta);
        }
    }
    s->pc2line_source_pos = pos;
}

#ifdef DUMP_PC2LINE_STATS
void dump_pc2line(void)
{
    int i;
    for(i = 0; i < 256; i++) {
        if (pc2line_freq[i] != 0) {
            printf("%d: %d %0.2f\n",
                   i - 128, pc2line_freq[i],
                   -log2((double)pc2line_freq[i] / pc2line_freq_tot));
        }
    }
}
#endif

/* warning: pc2line info must be associated to each generated opcode */
void emit_op_pos(JSParseState *s, uint8_t op, JSSourcePos source_pos)
{
    s->last_opcode_pos = s->byte_code_len;
    s->last_pc2line_pos = s->pc2line_bit_len;
    s->last_pc2line_source_pos = s->pc2line_source_pos;

    emit_pc2line(s, source_pos);
    emit_u8(s, op);
}

void emit_op(JSParseState *s, uint8_t op)
{
    emit_op_pos(s, op, s->pc2line_source_pos);
}

void emit_op_param(JSParseState *s, uint8_t op, uint32_t param, JSSourcePos source_pos)
{
    const JSOpCode *oi;

    emit_op_pos(s, op, source_pos);
    oi = &opcode_info[op];
    switch(oi->fmt) {
    case OP_FMT_none:
        break;
    case OP_FMT_npop:
        emit_u16(s, param);
        break;
    default:
        assert(0);
    }
}

/* insert 'n' bytes at position pos */
void emit_insert(JSParseState *s, int pos, int n)
{
    JSByteArray *arr;
    emit_claim_size(s, n);
    arr = JS_VALUE_TO_PTR(s->byte_code);
    memmove(arr->buf + pos + n, arr->buf + pos, s->byte_code_len - pos);
    s->byte_code_len += n;
}

inline int get_prev_opcode(JSParseState *s)
{
    if (s->last_opcode_pos < 0) {
        return OP_invalid;
    } else {
        uint8_t *byte_code = get_byte_code(s);
        return byte_code[s->last_opcode_pos];
    }
}

BOOL js_is_live_code(JSParseState *s) { switch (get_prev_opcode(s)) { case OP_return: case OP_return_undef: case OP_throw: case OP_goto: case OP_ret: return FALSE;
    default:
        return TRUE;
    }
}

void remove_last_op(JSParseState *s)
{
    s->byte_code_len = s->last_opcode_pos;
    s->pc2line_bit_len = s->last_pc2line_pos;
    s->pc2line_source_pos = s->last_pc2line_source_pos;
    s->last_opcode_pos = -1;
}

void emit_push_short_int(JSParseState *s, int val)
{
    if (val >= -1 && val <= 7) {
        emit_op(s, OP_push_0 + val);
    } else if (val == (int8_t)val) {
        emit_op(s, OP_push_i8);
        emit_u8(s, val);
    } else if (val == (int16_t)val) {
        emit_op(s, OP_push_i16);
        emit_u16(s, val);
    } else {
        emit_op(s, OP_push_value);
        emit_u32(s, JS_NewShortInt(val));
    }
}

void emit_var(JSParseState *s, int opcode, int var_idx, JSSourcePos source_pos)
{
    switch(opcode) {
    case OP_get_loc:
        if (var_idx < 4) {
            emit_op_pos(s, OP_get_loc0 + var_idx, source_pos);
            return;
        } else if (var_idx < 256) {
            emit_op_pos(s, OP_get_loc8, source_pos);
            emit_u8(s, var_idx);
            return;
        }
        break;
    case OP_put_loc:
        if (var_idx < 4) {
            emit_op_pos(s, OP_put_loc0 + var_idx, source_pos);
            return;
        } else if (var_idx < 256) {
            emit_op_pos(s, OP_put_loc8, source_pos);
            emit_u8(s, var_idx);
            return;
        }
        break;
    case OP_get_arg:
        if (var_idx < 4) {
            emit_op_pos(s, OP_get_arg0 + var_idx, source_pos);
            return;
        }
        break;
    case OP_put_arg:
        if (var_idx < 4) {
            emit_op_pos(s, OP_put_arg0 + var_idx, source_pos);
            return;
        }
        break;
    }
    emit_op_pos(s, opcode, source_pos);
    emit_u16(s, var_idx);
}


void js_parse_function_decl(JSParseState *s, JSParseFunctionEnum func_type, JSValue func_name);

/* labels are short integers so they can be used as JSValue. -1 is not
   a valid label. */
#define LABEL_RESOLVED_FLAG (1 << 29)
#define LABEL_OFFSET_MASK ((1 << 29) - 1)

#define LABEL_NONE JS_NewShortInt(-1)

BOOL label_is_none(JSValue label)
{
    return JS_VALUE_GET_INT(label) < 0;
}

JSValue new_label(JSParseState *s)
{
    return JS_NewShortInt(LABEL_OFFSET_MASK);
}

void emit_label_pos(JSParseState *s, JSValue *plabel, int pos)
{
    int label;
    JSByteArray *arr;
    int next;

    label = JS_VALUE_GET_INT(*plabel);
    assert(!(label & LABEL_RESOLVED_FLAG));
    arr = JS_VALUE_TO_PTR(s->byte_code);
    while (label != LABEL_OFFSET_MASK) {
        next = get_u32(arr->buf + label);
        put_u32(arr->buf + label, pos - label);
        label = next;
    }
    *plabel = JS_NewShortInt(pos | LABEL_RESOLVED_FLAG);
}

void emit_label(JSParseState *s, JSValue *plabel)
{
    emit_label_pos(s, plabel, s->byte_code_len);
    /* prevent get_lvalue from using the last expression as an
       lvalue. */
    s->last_opcode_pos = -1;
}

void emit_goto(JSParseState *s, int opcode, JSValue *plabel)
{
    int label;
    /* XXX: generate smaller gotos when possible */
    emit_op(s, opcode);
    label = JS_VALUE_GET_INT(*plabel);
    if (label & LABEL_RESOLVED_FLAG) {
        emit_u32(s, (label & LABEL_OFFSET_MASK) - s->byte_code_len);
    } else {
        emit_u32(s, label);
        *plabel = JS_NewShortInt(s->byte_code_len - 4);
    }
}

/* return the constant pool index. 'val' is not duplicated. */
int cpool_add(JSParseState *s, JSValue val)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    int i;
    JSValue new_cpool;
    JSGCRef val_ref;
    
    b = JS_VALUE_TO_PTR(s->cur_func);
    arr = JS_VALUE_TO_PTR(b->cpool);
    /* check if the value is already present */
    for(i = 0; i < s->cpool_len; i++) {
        if (arr->arr[i] == val)
            return i;
    }

    if (s->cpool_len > 65535)
        js_parse_error(s, "too many constants");
    JS_PUSH_VALUE(s->ctx, val);
    new_cpool = js_resize_value_array(s->ctx, b->cpool, max_int(s->cpool_len + 1, 4));
    JS_POP_VALUE(s->ctx, val);
    if (JS_IsException(new_cpool))
        js_parse_error_mem(s);
    b = JS_VALUE_TO_PTR(s->cur_func);
    b->cpool = new_cpool;
    arr = JS_VALUE_TO_PTR(b->cpool);
    arr->arr[s->cpool_len++] = val;
    return s->cpool_len - 1;
}

void js_emit_push_const(JSParseState *s, JSValue val)
{
    int idx;

    if (JS_IsPtr(val)
#ifdef JS_USE_SHORT_FLOAT
        || JS_IsShortFloat(val)
#endif
        ) {
        /* We use a constant pool to avoid scanning the bytecode
           during the GC. XXX: is it a good choice ? */
        idx = cpool_add(s, val);
        emit_op(s, OP_push_const);
        emit_u16(s, idx);
    } else {
        /* no GC mark */
        emit_op(s, OP_push_value);
        emit_u32(s, val);
    }
}

/* return the local variable index or -1 if not found */
int find_func_var(JSContext *ctx, JSValue func, JSValue name)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    int i;

    b = JS_VALUE_TO_PTR(func);
    if (b->vars == JS_NULL)
        return -1;
    arr = JS_VALUE_TO_PTR(b->vars);
    for(i = 0; i < arr->size; i++) {
        if (arr->arr[i] == name)
            return i;
    }
    return -1;
}

int find_var(JSParseState *s, JSValue name)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    int i;

    b = JS_VALUE_TO_PTR(s->cur_func);
    arr = JS_VALUE_TO_PTR(b->vars);
    for(i = 0; i < s->local_vars_len; i++) {
        if (arr->arr[i] == name)
            return i;
    }
    return -1;
}

JSValue get_ext_var_name(JSParseState *s, int var_idx)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;

    b = JS_VALUE_TO_PTR(s->cur_func);
    arr = JS_VALUE_TO_PTR(b->ext_vars);
    return arr->arr[2 * var_idx];
}

int find_func_ext_var(JSParseState *s, JSValue func, JSValue name)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    int i;

    b = JS_VALUE_TO_PTR(func);
    arr = JS_VALUE_TO_PTR(b->ext_vars);
    for(i = 0; i < b->ext_vars_len; i++) {
        if (arr->arr[2 * i] == name)
            return i;
    }
    return -1;
}

/* return the external variable index or -1 if not found */
int find_ext_var(JSParseState *s, JSValue name)
{
    return find_func_ext_var(s, s->cur_func, name);
}

/* return the external variable index */
int add_func_ext_var(JSParseState *s, JSValue func, JSValue name, int decl)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    JSValue new_ext_vars;
    JSGCRef name_ref, func_ref;
    
    b = JS_VALUE_TO_PTR(func);
    if (b->ext_vars_len >= JS_MAX_LOCAL_VARS) 
        js_parse_error(s, "too many variable references");
    JS_PUSH_VALUE(s->ctx, func);
    JS_PUSH_VALUE(s->ctx, name);
    new_ext_vars = js_resize_value_array(s->ctx, b->ext_vars, max_int(b->ext_vars_len + 1, 2) * 2);
    JS_POP_VALUE(s->ctx, name);
    JS_POP_VALUE(s->ctx, func);
    if (JS_IsException(new_ext_vars))
        js_parse_error_mem(s);
    b = JS_VALUE_TO_PTR(func);
    b->ext_vars = new_ext_vars;
    arr = JS_VALUE_TO_PTR(b->ext_vars);
    arr->arr[2 * b->ext_vars_len] = name;
    arr->arr[2 * b->ext_vars_len + 1] = JS_NewShortInt(decl);
    b->ext_vars_len++;
    return b->ext_vars_len - 1;
}

/* return the external variable index */
int add_ext_var(JSParseState *s, JSValue name, int decl)
{
    return add_func_ext_var(s, s->cur_func, name, decl);
}

/* return the local variable index */
int add_var(JSParseState *s, JSValue name)
{
    JSFunctionBytecode *b;
    JSValueArray *arr;
    JSValue new_vars;
    JSGCRef name_ref;
    
    b = JS_VALUE_TO_PTR(s->cur_func);
    if (s->local_vars_len >= JS_MAX_LOCAL_VARS) 
        js_parse_error(s, "too many local variables");
    JS_PUSH_VALUE(s->ctx, name);
    new_vars = js_resize_value_array(s->ctx, b->vars, max_int(s->local_vars_len + 1, 4));
    JS_POP_VALUE(s->ctx, name);
    if (JS_IsException(new_vars))
        js_parse_error_mem(s);
    b = JS_VALUE_TO_PTR(s->cur_func);
    b->vars = new_vars;
    arr = JS_VALUE_TO_PTR(b->vars);
    arr->arr[s->local_vars_len++] = name;
    return s->local_vars_len - 1;
}

void get_lvalue(JSParseState *s, int *popcode, int *pvar_idx, JSSourcePos *psource_pos, BOOL keep)
{
    int opcode, var_idx;
    JSSourcePos source_pos;
    
    /* we check the last opcode to get the lvalue type */
    opcode = get_prev_opcode(s);
    switch(opcode) {
    case OP_get_loc0:
    case OP_get_loc1:
    case OP_get_loc2:
    case OP_get_loc3:
        var_idx = opcode - OP_get_loc0;
        opcode = OP_get_loc;
        break;
    case OP_get_arg0:
    case OP_get_arg1:
    case OP_get_arg2:
    case OP_get_arg3:
        var_idx = opcode - OP_get_arg0;
        opcode = OP_get_arg;
        break;
    case OP_get_loc8:
        var_idx = get_u8(get_byte_code(s) + s->last_opcode_pos + 1);
        opcode = OP_get_loc;
        break;
    case OP_get_loc:
    case OP_get_arg:
    case OP_get_var_ref:
    case OP_get_field:
        var_idx = get_u16(get_byte_code(s) + s->last_opcode_pos + 1);
        break;
    case OP_get_array_el:
    case OP_get_length:
        var_idx = -1;
        break;
    default:
        js_parse_error(s, "invalid lvalue");
    }
    source_pos = s->pc2line_source_pos;

    /* remove the last opcode */
    remove_last_op(s);

    if (keep) {
        /* get the value but keep the object/fields on the stack */
        switch(opcode) {
        case OP_get_loc:
        case OP_get_arg:
        case OP_get_var_ref:
            emit_var(s, opcode, var_idx, source_pos);
            break;
        case OP_get_field:
            emit_op_pos(s, OP_get_field2, source_pos);
            emit_u16(s, var_idx);
            break;
        case OP_get_length:
            emit_op_pos(s, OP_get_length2, source_pos);
            break;
        case OP_get_array_el:
            emit_op(s, OP_dup2);
            emit_op_pos(s, OP_get_array_el, source_pos); /* XXX: add OP_get_array_el3 but need to modify tail call */
            break;
        default:
            abort();
        }
    }

    *popcode = opcode;
    *pvar_idx = var_idx;
    *psource_pos = source_pos;
}

void put_lvalue(JSParseState *s, int opcode, int var_idx, JSSourcePos source_pos, PutLValueEnum special)
{
    switch(opcode) {
    case OP_get_loc:
    case OP_get_arg:
    case OP_get_var_ref:
        if (special == PUT_LVALUE_KEEP_TOP)
            emit_op(s, OP_dup);
        if (opcode == OP_get_var_ref && s->is_repl)
            opcode = OP_put_var_ref_nocheck; /* an assignment defines the variable in the REPL */
        else
            opcode++;
        emit_var(s, opcode, var_idx, source_pos);
        break;
    case OP_get_field:
    case OP_get_length:
        switch(special) {
        case PUT_LVALUE_KEEP_TOP:
            emit_op(s, OP_insert2); /* obj a -> a obj a */
            break;
        case PUT_LVALUE_NOKEEP_TOP:
            break;
        case PUT_LVALUE_NOKEEP_BOTTOM:
            emit_op(s, OP_swap); /* a obj -> obj a */
            break;
        default:
        case PUT_LVALUE_KEEP_SECOND:
            emit_op(s, OP_perm3); /* obj a b -> a obj b */
            break;
        }
        emit_op_pos(s, OP_put_field, source_pos);
        if (opcode == OP_get_length) {
            emit_u16(s, cpool_add(s, js_get_atom(s->ctx, JS_ATOM_length)));
        } else {
            emit_u16(s, var_idx);
        }
        break;
    case OP_get_array_el:
        switch(special) {
        case PUT_LVALUE_KEEP_TOP:
            emit_op(s, OP_insert3); /* obj prop a -> a obj prop a */
            break;
        case PUT_LVALUE_NOKEEP_TOP:
            break;
        case PUT_LVALUE_NOKEEP_BOTTOM: /* a obj prop -> obj prop a */
            emit_op(s, OP_rot3l); /* obj prop a b -> a obj prop b */
            break;
        default:
        case PUT_LVALUE_KEEP_SECOND:
            emit_op(s, OP_perm4); /* obj prop a b -> a obj prop b */
            break;
        }
        emit_op_pos(s, OP_put_array_el, source_pos);
        break;
    default:
        abort();
    }
}

enum {
    PARSE_PROP_FIELD,
    PARSE_PROP_GET,
    PARSE_PROP_SET,
    PARSE_PROP_METHOD,
};

int js_parse_property_name(JSParseState *s, JSValue *pname)
{
    JSContext *ctx = s->ctx;
    JSValue name;
    JSGCRef name_ref;
    int prop_type;

    prop_type = PARSE_PROP_FIELD;

    if (s->token.val == TOK_IDENT) {
        int is_set;
        if (s->token.value == js_get_atom(ctx, JS_ATOM_get))
            is_set = 0;
        else if (s->token.value == js_get_atom(ctx, JS_ATOM_set))
            is_set = 1;
        else
            is_set = -1;
        if (is_set >= 0) {
            next_token(s);
            if (s->token.val == ':' || s->token.val == ',' ||
                s->token.val == '}' || s->token.val == '(') {
                /* not a get set */
                name = js_get_atom(ctx, is_set ? JS_ATOM_set : JS_ATOM_get);
                goto done;
            }
            prop_type = PARSE_PROP_GET + is_set;
        }
    }

    if (s->token.val == TOK_IDENT || s->token.val >= TOK_FIRST_KEYWORD) {
        name = s->token.value;
    } else if (s->token.val == TOK_STRING) {
        name = s->token.value;
    } else if (s->token.val == TOK_NUMBER) {
        name = JS_NewFloat64(s->ctx, s->token.u.d);
        if (JS_IsException(name))
            js_parse_error_mem(s);
    } else {
        js_parse_error(s, "invalid property name");
    }
    name = JS_ToPropertyKey(s->ctx, name);
    if (JS_IsException(name))
        js_parse_error_mem(s);
    JS_PUSH_VALUE(ctx, name);
    next_token(s);
    JS_POP_VALUE(ctx, name);
 done:
    if (prop_type == PARSE_PROP_FIELD && s->token.val == '(')
        prop_type = PARSE_PROP_METHOD;
    *pname = name;
    return prop_type;
}

/* recursion free parser definitions */

#define PF_NO_IN         (1 << 0) /* the 'in' operator is not accepted*/
#define PF_DROP          (1 << 1) /* drop result */
#define PF_ACCEPT_LPAREN (1 << 2) /* js_parse_postfix_expr only */
#define PF_LEVEL_SHIFT 4 /* optional level parameter */
#define PF_LEVEL_MASK  (0xf << PF_LEVEL_SHIFT)

#define PARSE_STATE_INIT 0xfe
#define PARSE_STATE_RET  0xff

/* may trigger a gc */
JSValue parse_stack_alloc(JSParseState *s, JSValue val)
{
    JSGCRef val_ref;
    
    JS_PUSH_VALUE(s->ctx, val);
    if (JS_StackCheck(s->ctx, 1))
        js_parse_error_stack_overflow(s);
    JS_POP_VALUE(s->ctx, val);
    return val;
}

/* WARNING: 'val' may be modified after this val if it is a pointer */
void js_parse_push_val(JSParseState *s, JSValue val)
{
    JSContext *ctx = s->ctx;
    if (unlikely(ctx->sp <= ctx->stack_bottom)) {
        val = parse_stack_alloc(s, val);
    }
    *--(ctx->sp) = val;
}

/* update the stack bottom when there is a large stack space */
JSValue js_parse_pop_val(JSParseState *s)
{
    JSContext *ctx = s->ctx;
    JSValue val;
    val = *(ctx->sp)++;
    if (unlikely(ctx->sp - JS_STACK_SLACK > ctx->stack_bottom))
        ctx->stack_bottom = ctx->sp - JS_STACK_SLACK;
    return val;
}

#define PARSE_PUSH_VAL(s, v) js_parse_push_val(s, v)
#define PARSE_POP_VAL(s, v) v = js_parse_pop_val(s)

#define PARSE_PUSH_INT(s, v) js_parse_push_val(s, JS_NewShortInt(v))
#define PARSE_POP_INT(s, v) v = JS_VALUE_GET_INT(js_parse_pop_val(s))

#define PARSE_START1()                          \
    switch(state) {\
    case PARSE_STATE_INIT: break;\
    default: abort();\
    case 0: goto parse_state0;\
    }

#define PARSE_START2()                          \
    switch(state) {\
    case PARSE_STATE_INIT: break;\
    default: abort();\
    case 0: goto parse_state0;\
    case 1: goto parse_state1;\
    }

#define PARSE_START3()                          \
    switch(state) {\
    case PARSE_STATE_INIT: break;\
    default: abort();\
    case 0: goto parse_state0;\
    case 1: goto parse_state1;\
    case 2: goto parse_state2;\
    }

#define PARSE_START7()                          \
    switch(state) {\
    case PARSE_STATE_INIT: break;\
    default: abort();\
    case 0: goto parse_state0;\
    case 1: goto parse_state1;\
    case 2: goto parse_state2;\
    case 3: goto parse_state3;                  \
    case 4: goto parse_state4;\
    case 5: goto parse_state5;\
    case 6: goto parse_state6;\
    }

#define PARSE_START12()                          \
    switch(state) {\
    case PARSE_STATE_INIT: break;\
    default: abort();\
    case 0: goto parse_state0;\
    case 1: goto parse_state1;\
    case 2: goto parse_state2;\
    case 3: goto parse_state3;                  \
    case 4: goto parse_state4;\
    case 5: goto parse_state5;\
    case 6: goto parse_state6;\
    case 7: goto parse_state7;                  \
    case 8: goto parse_state8;\
    case 9: goto parse_state9;\
    case 10: goto parse_state10;\
    case 11: goto parse_state11;\
    }

/* WARNING: local variables are not preserved across PARSE_CALL(). So
   they must be explicitly saved and restored */
#define PARSE_CALL(s, cur_state, func, param) return (cur_state | (PARSE_FUNC_ ## func << 8) | ((param) << 16)); parse_state ## cur_state : ;

/* preserve var1, ... across the call */
#define PARSE_CALL_SAVE1(s, cur_state, func, param, var1) \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var1);

#define PARSE_CALL_SAVE2(s, cur_state, func, param, var1, var2) \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_PUSH_INT(s, var2);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var2);                                     \
    PARSE_POP_INT(s, var1);

#define PARSE_CALL_SAVE3(s, cur_state, func, param, var1, var2, var3)        \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_PUSH_INT(s, var2);                                    \
    PARSE_PUSH_INT(s, var3);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var3);                                     \
    PARSE_POP_INT(s, var2);                                     \
    PARSE_POP_INT(s, var1);

#define PARSE_CALL_SAVE4(s, cur_state, func, param, var1, var2, var3, var4)  \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_PUSH_INT(s, var2);                                    \
    PARSE_PUSH_INT(s, var3);                                    \
    PARSE_PUSH_INT(s, var4);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var4);                                     \
    PARSE_POP_INT(s, var3);                                     \
    PARSE_POP_INT(s, var2);                                     \
    PARSE_POP_INT(s, var1);

#define PARSE_CALL_SAVE5(s, cur_state, func, param, var1, var2, var3, var4, var5) \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_PUSH_INT(s, var2);                                    \
    PARSE_PUSH_INT(s, var3);                                    \
    PARSE_PUSH_INT(s, var4);                                    \
    PARSE_PUSH_INT(s, var5);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var5);                                     \
    PARSE_POP_INT(s, var4);                                     \
    PARSE_POP_INT(s, var3);                                     \
    PARSE_POP_INT(s, var2);                                     \
    PARSE_POP_INT(s, var1);

#define PARSE_CALL_SAVE6(s, cur_state, func, param, var1, var2, var3, var4, var5, var6) \
    PARSE_PUSH_INT(s, var1);                                    \
    PARSE_PUSH_INT(s, var2);                                    \
    PARSE_PUSH_INT(s, var3);                                    \
    PARSE_PUSH_INT(s, var4);                                    \
    PARSE_PUSH_INT(s, var5);                                    \
    PARSE_PUSH_INT(s, var6);                                    \
    PARSE_CALL(s, cur_state, func, param);                      \
    PARSE_POP_INT(s, var6);                                     \
    PARSE_POP_INT(s, var5);                                     \
    PARSE_POP_INT(s, var4);                                     \
    PARSE_POP_INT(s, var3);                                     \
    PARSE_POP_INT(s, var2);                                     \
    PARSE_POP_INT(s, var1);

static JSParseFunc *parse_func_table[];

void js_parse_call(JSParseState *s, ParseExprFuncEnum func_idx, int param)
{
    JSContext *ctx = s->ctx;
    int ret, state;
    JSValue *stack_top;

    stack_top = ctx->sp;
    state = PARSE_STATE_INIT;
    for(;;) {
        ret = parse_func_table[func_idx](s, state, param);
        state = ret & 0xff;
        if (state == PARSE_STATE_RET) {
            /* the function terminated: go back to the calling
               function if any */
            if (ctx->sp == stack_top)
                break;
            PARSE_POP_INT(s, ret);
            state = ret & 0xff;
            func_idx = (ret >> 8) & 0xff;
            param = -1; /* the parameter is not saved */
        } else {
            /* push the call position and call another function */
            PARSE_PUSH_INT(s, state | (func_idx << 8));
            state = PARSE_STATE_INIT;
            func_idx = (ret >> 8) & 0xff;
            param = (ret >> 16);
        }
    }
}

BOOL may_drop_result(JSParseState *s, int parse_flags)
{
    return ((parse_flags & PF_DROP) &&
            (s->token.val == ';' || s->token.val == ')' ||
             s->token.val == ','));
}

void js_emit_push_number(JSParseState *s, double d)
{
    JSValue val;
    
    val = JS_NewFloat64(s->ctx, d);
    if (JS_IsException(val))
        js_parse_error_mem(s);
    if (JS_IsInt(val)) {
        emit_push_short_int(s, JS_VALUE_GET_INT(val));
    } else {
        js_emit_push_const(s, val);
    }
}

int js_parse_postfix_expr(JSParseState *s, int state, int parse_flags)
{
    BOOL is_new = FALSE;

    PARSE_START7();
    switch(s->token.val) {
    case TOK_NUMBER:
        js_emit_push_number(s, s->token.u.d);
        next_token(s);
        break;
    case TOK_STRING:
        {
            js_emit_push_const(s, s->token.value);
            next_token(s);
        }
        break;
    case TOK_REGEXP:
        {
            uint32_t saved_buf_pos, saved_buf_len;
            uint32_t saved_byte_code_len;
            JSValue byte_code;
            JSFunctionBytecode *b;

            js_emit_push_const(s, s->token.value); /* regexp source */

            saved_buf_pos = s->buf_pos;
            saved_buf_len = s->buf_len;
            /* save the current bytecode back to the function */
            b = JS_VALUE_TO_PTR(s->cur_func);
            b->byte_code = s->byte_code;
            saved_byte_code_len = s->byte_code_len;
            
            /* modify the parser to parse the regexp. This way we
               avoid instantiating a new JSParseState */
            /* XXX: find a better way as it relies on the regexp
               parser to correctly handle the end of regexp */
            s->buf_pos = s->token.source_pos + 1;
            s->buf_len = s->token.u.regexp.re_end_pos;
            byte_code = js_parse_regexp(s, s->token.u.regexp.re_flags);

            s->buf_pos = saved_buf_pos;
            s->buf_len = saved_buf_len;
            b = JS_VALUE_TO_PTR(s->cur_func);
            s->byte_code = b->byte_code;
            s->byte_code_len = saved_byte_code_len;
            
            js_emit_push_const(s, byte_code);
            emit_op(s, OP_regexp);
            next_token(s);
        }
        break;
    case '(':
        next_token(s);
        PARSE_CALL_SAVE1(s, 0, js_parse_expr_comma, 0, parse_flags);
        js_parse_expect(s, ')');
        break;
    case TOK_FUNCTION:
        js_parse_function_decl(s, JS_PARSE_FUNC_EXPR, JS_NULL);
        break;
    case TOK_NULL:
        emit_op(s, OP_null);
        next_token(s);
        break;
    case TOK_THIS:
        emit_op(s, OP_push_this);
        next_token(s);
        break;
    case TOK_FALSE:
    case TOK_TRUE:
        emit_op(s, OP_push_false + (s->token.val == TOK_TRUE));
        next_token(s);
        break;
    case TOK_IDENT:
        {
            JSFunctionBytecode *b;
            JSValue name;
            int var_idx, arg_count, opcode;

            b = JS_VALUE_TO_PTR(s->cur_func);
            arg_count = b->arg_count;
            
            name = s->token.value;
            
            var_idx = find_var(s, name);
            if (var_idx >= 0) {
                if (var_idx < arg_count) {
                    opcode = OP_get_arg;
                } else {
                    opcode = OP_get_loc;
                    var_idx -= arg_count;
                }
            } else {
                var_idx = find_ext_var(s, name);
                if (var_idx < 0) {
                    var_idx = add_ext_var(s, name, (JS_VARREF_KIND_GLOBAL << 16) | 0);
                }
                opcode = OP_get_var_ref;
            }
            emit_var(s, opcode, var_idx, s->token.source_pos);
            next_token(s);
        }
        break;
    case '{':
        {
            JSValue name;
            int prop_idx, prop_type, count_pos;
            BOOL has_proto;
            
            next_token(s);
            emit_op(s, OP_object);
            count_pos = s->byte_code_len;
            emit_u16(s, 0);

            has_proto = FALSE;
            while (s->token.val != '}') {
                prop_type = js_parse_property_name(s, &name);
                if (prop_type == PARSE_PROP_FIELD &&
                    name == js_get_atom(s->ctx, JS_ATOM___proto__)) {
                    if (has_proto)
                        js_parse_error(s, "duplicate __proto__ property name");
                    has_proto = TRUE;
                    prop_idx = -1;
                } else {
                    uint8_t *byte_code;
                    int count;
                    prop_idx = cpool_add(s, name);
                    /* increment the count */
                    byte_code = get_byte_code(s);
                    count = get_u16(byte_code + count_pos);
                    put_u16(byte_code + count_pos, min_int(count + 1, 0xffff));
                }
                if (prop_type == PARSE_PROP_FIELD) {
                    js_parse_expect(s, ':');
                    PARSE_CALL_SAVE4(s, 1, js_parse_assign_expr, 0, prop_idx, parse_flags, has_proto, count_pos);
                    if (prop_idx >= 0) {
                        emit_op(s, OP_define_field);
                        emit_u16(s, prop_idx);
                    } else {
                        emit_op(s, OP_set_proto);
                    }
                } else {
                    /* getter/setter/method */
                    js_parse_function_decl(s, JS_PARSE_FUNC_METHOD, name);
                    if (prop_type == PARSE_PROP_METHOD)
                        emit_op(s, OP_define_field);
                    else if (prop_type == PARSE_PROP_GET)
                        emit_op(s, OP_define_getter);
                    else
                        emit_op(s, OP_define_setter);
                    emit_u16(s, prop_idx);
                }
                if (s->token.val != ',')
                    break;
                next_token(s);
            }
            js_parse_expect(s, '}');
        }
        break;
    case '[':
        {
            uint32_t idx;
            
            next_token(s);
            /* small regular arrays are created on the stack */
            idx = 0;
            while (s->token.val != ']' && idx < 32) {
                /* SPEC: we don't accept empty elements */
                PARSE_CALL_SAVE2(s, 2, js_parse_assign_expr, 0, idx, parse_flags);
                idx++;
                /* accept trailing comma */
                if (s->token.val == ',') {
                    next_token(s);
                } else if (s->token.val != ']') {
                    goto done;
                }
            }
            
            emit_op_param(s, OP_array_from, idx, s->pc2line_source_pos);
            
            while (s->token.val != ']') {
                if (idx >= JS_SHORTINT_MAX)
                    js_parse_error(s, "too many elements");
                emit_op(s, OP_dup);
                emit_push_short_int(s, idx);
                PARSE_CALL_SAVE2(s, 3, js_parse_assign_expr, 0, idx, parse_flags);
                emit_op(s, OP_put_array_el);
                idx++;
                /* accept trailing comma */
                if (s->token.val == ',') {
                    next_token(s);
                }
            }
        done:
            js_parse_expect(s, ']');
        }
        break;
    case TOK_NEW:
        next_token(s);
        if (s->token.val == '.') {
            next_token(s);
            if (s->token.val != TOK_IDENT ||
                s->token.value != js_get_atom(s->ctx, JS_ATOM_target)) {
                js_parse_error(s, "expecting target");
            }
            next_token(s);
            emit_op(s, OP_new_target);
        } else {
            PARSE_CALL_SAVE1(s, 4, js_parse_postfix_expr, 0, parse_flags);
            if (s->token.val != '(') {
                /* new operator on an object */
                emit_op_param(s, OP_call_constructor, 0, s->token.source_pos);
            } else {
                is_new = TRUE;
                break;
            }
        }
        break;
    default:
        js_parse_error(s, "unexpected character in expression");
    }

    for(;;) {
        if (s->token.val == '(' && (parse_flags & PF_ACCEPT_LPAREN)) {
            int opcode, arg_count;
            uint8_t *byte_code;
            JSSourcePos op_source_pos;
            
            /* function call */
            op_source_pos = s->token.source_pos;
            next_token(s);

            if (!is_new) {
                opcode = get_prev_opcode(s);
                byte_code = get_byte_code(s);
                switch(opcode) {
                case OP_get_field:
                    byte_code[s->last_opcode_pos] = OP_get_field2;
                    break;
                case OP_get_length:
                    byte_code[s->last_opcode_pos] = OP_get_length2;
                    break;
                case OP_get_array_el:
                    byte_code[s->last_opcode_pos] = OP_get_array_el2;
                    break;
                case OP_get_var_ref:
                    {
                        int var_idx = get_u16(byte_code + s->last_opcode_pos + 1);
                        if (get_ext_var_name(s, var_idx) == js_get_atom(s->ctx, JS_ATOM_eval)) {
                            js_parse_error(s, "direct eval is not supported. Use (1,eval) instead for indirect eval");
                        }
                    }
                    /* fall thru */
                default:
                    opcode = OP_invalid;
                    break;
                }
            } else {
                opcode = OP_invalid;
            }
            
            arg_count = 0;
            if (s->token.val != ')') {
                for(;;) {
                    if (arg_count >= JS_MAX_ARGC)
                        js_parse_error(s, "too many call arguments");
                    arg_count++;
                    PARSE_CALL_SAVE5(s, 5, js_parse_assign_expr, 0,
                                     parse_flags, arg_count, opcode, is_new, op_source_pos);
                    if (s->token.val == ')')
                        break;
                    js_parse_expect(s, ',');
                }
            }
            next_token(s);
            if (opcode == OP_get_field ||
                opcode == OP_get_length ||
                opcode == OP_get_array_el) {
                emit_op_param(s, OP_call_method, arg_count, op_source_pos);
            } else {
                if (is_new) {
                    emit_op_param(s, OP_call_constructor, arg_count, op_source_pos);
                } else {
                    emit_op_param(s, OP_call, arg_count, op_source_pos);
                }
            }
            is_new = FALSE;
        } else if (s->token.val == '.') {
            JSSourcePos op_source_pos;
            int prop_idx;
            
            op_source_pos = s->token.source_pos;
            next_token(s);
            if (!(s->token.val == TOK_IDENT || s->token.val >= TOK_FIRST_KEYWORD)) {
                js_parse_error(s, "expecting field name");
            }
            /* we ensure that no numeric property is used with
               OP_get_field to enable some optimizations. The only
               possible identifiers are NaN and Infinity */
            if (s->token.value == js_get_atom(s->ctx, JS_ATOM_NaN) ||
                s->token.value == js_get_atom(s->ctx, JS_ATOM_Infinity)) {
                js_emit_push_const(s, s->token.value);
                emit_op_pos(s, OP_get_array_el, op_source_pos);
            } else if (s->token.value == js_get_atom(s->ctx, JS_ATOM_length)) {
                emit_op_pos(s, OP_get_length, op_source_pos);
            } else {
                prop_idx = cpool_add(s, s->token.value);
                emit_op_pos(s, OP_get_field, op_source_pos);
                emit_u16(s, prop_idx);
            }
            next_token(s);
        } else if (s->token.val == '[') {
            JSSourcePos op_source_pos;
            op_source_pos = s->token.source_pos;
            next_token(s);
            PARSE_CALL_SAVE3(s, 6, js_parse_expr_comma, 0,
                             parse_flags, is_new, op_source_pos);
            js_parse_expect(s, ']');
            emit_op_pos(s, OP_get_array_el, op_source_pos);
        } else if (!s->got_lf && (s->token.val == TOK_DEC || s->token.val == TOK_INC)) {
            int opcode, op, var_idx;
            JSSourcePos op_source_pos, source_pos;
            
            op = s->token.val;
            op_source_pos = s->token.source_pos;
            next_token(s);
            get_lvalue(s, &opcode, &var_idx, &source_pos, TRUE);
            if (may_drop_result(s, parse_flags)) {
                s->dropped_result = TRUE;
                emit_op_pos(s, OP_dec + op - TOK_DEC, op_source_pos);
                put_lvalue(s, opcode, var_idx, source_pos, PUT_LVALUE_NOKEEP_TOP);
            } else {
                emit_op_pos(s, OP_post_dec + op - TOK_DEC, op_source_pos);
                put_lvalue(s, opcode, var_idx, source_pos, PUT_LVALUE_KEEP_SECOND);
            }
        } else {
            break;
        }
    }
    return PARSE_STATE_RET;
}

void js_emit_delete(JSParseState *s)
{
    int opcode;
    
    opcode = get_prev_opcode(s);
    switch(opcode) {
    case OP_get_field:
        {
            JSByteArray *byte_code;
            int prop_idx;
            byte_code = JS_VALUE_TO_PTR(s->byte_code);
            prop_idx = get_u16(byte_code->buf + s->last_opcode_pos + 1);
            remove_last_op(s);
            emit_op(s, OP_push_const);
            emit_u16(s, prop_idx);
        }
        break;
    case OP_get_length:
        remove_last_op(s);
        js_emit_push_const(s, js_get_atom(s->ctx, JS_ATOM_length));
        break;
    case OP_get_array_el:
        remove_last_op(s);
        break;
    default:
        js_parse_error(s, "invalid lvalue for delete");
    }
    emit_op(s, OP_delete);
}

int js_parse_unary(JSParseState *s, int state, int parse_flags)
{
    PARSE_START7();

    switch(s->token.val) {
    case '+':
    case '-':
    case '!':
    case '~':
        {
            int op;
            JSSourcePos op_source_pos;
            
            op = s->token.val;
            op_source_pos = s->token.source_pos;
            next_token(s);
            
            /* XXX: could handle more cases */
            if (s->token.val == TOK_NUMBER && (op == '-' || op == '+')) {
                double d = s->token.u.d;
                if (op == '-')
                    d = -d;
                js_emit_push_number(s, d);
                next_token(s);
            } else {
                PARSE_CALL_SAVE2(s, 0, js_parse_unary, 0, op, op_source_pos);
                switch(op) {
                case '-':
                    emit_op_pos(s, OP_neg, op_source_pos);
                    break;
                case '+':
                    emit_op_pos(s, OP_plus, op_source_pos);
                    break;
                case '!':
                    emit_op_pos(s, OP_lnot, op_source_pos);
                    break;
                case '~':
                    emit_op_pos(s, OP_not, op_source_pos);
                    break;
                default:
                    abort();
                }
            }
        }
        break;
    case TOK_VOID:
        next_token(s);
        PARSE_CALL(s, 1, js_parse_unary, 0);
        emit_op(s, OP_drop);
        emit_op(s, OP_undefined);
        break;
    case TOK_DEC:
    case TOK_INC:
        {
            int opcode, op, var_idx;
            PutLValueEnum special;
            JSSourcePos op_source_pos, source_pos;
            
            op = s->token.val;
            op_source_pos = s->token.source_pos;
            next_token(s);
            PARSE_CALL_SAVE3(s, 2, js_parse_unary, 0, op, parse_flags, op_source_pos);
            get_lvalue(s, &opcode, &var_idx, &source_pos, TRUE);
            emit_op_pos(s, OP_dec + op - TOK_DEC, op_source_pos);

            if (may_drop_result(s, parse_flags)) {
                special = PUT_LVALUE_NOKEEP_TOP;
                s->dropped_result = TRUE;
            } else {
                special = PUT_LVALUE_KEEP_TOP;
            }
            put_lvalue(s, opcode, var_idx, source_pos, special);
        }
        break;
    case TOK_TYPEOF:
        {
            next_token(s);
            PARSE_CALL(s, 3, js_parse_unary, 0);
            /* access to undefined variable should not return an
               exception, so we patch the get_var */
            if (get_prev_opcode(s) == OP_get_var_ref) {
                uint8_t *byte_code = get_byte_code(s);
                byte_code[s->last_opcode_pos] = OP_get_var_ref_nocheck;
            }
            emit_op(s, OP_typeof);
        }
        break;
    case TOK_DELETE:
        next_token(s);
        PARSE_CALL(s, 4, js_parse_unary, 0);
        js_emit_delete(s);
        break;
    default:
        PARSE_CALL(s, 5, js_parse_postfix_expr, parse_flags | PF_ACCEPT_LPAREN);
        /* XXX: we do not follow the ES7 grammar in order to have a
         * more natural expression */
        if (s->token.val == TOK_POW) {
            JSSourcePos op_source_pos;
            op_source_pos = s->token.source_pos;
            next_token(s);
            PARSE_CALL_SAVE1(s, 6, js_parse_unary, 0, op_source_pos);
            emit_op_pos(s, OP_pow, op_source_pos);
        }
        break;
    }
    return PARSE_STATE_RET;
}

int js_parse_expr_binary(JSParseState *s, int state, int parse_flags)
{
    int op, opcode, level;
    JSSourcePos op_source_pos;
    
    PARSE_START3();
    level = (parse_flags & PF_LEVEL_MASK) >> PF_LEVEL_SHIFT;
    if (level == 0) {
        PARSE_CALL(s, 0, js_parse_unary, parse_flags);
        return PARSE_STATE_RET;
    }
    PARSE_CALL_SAVE1(s, 1, js_parse_expr_binary, parse_flags - (1 << PF_LEVEL_SHIFT), parse_flags);
    parse_flags &= ~PF_DROP;
    for(;;) {
        op = s->token.val;
        op_source_pos = s->token.source_pos;
        level = (parse_flags & PF_LEVEL_MASK) >> PF_LEVEL_SHIFT;
        switch(level) {
        case 1:
            switch(op) {
            case '*':
                opcode = OP_mul;
                break;
            case '/':
                opcode = OP_div;
                break;
            case '%':
                opcode = OP_mod;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 2:
            switch(op) {
            case '+':
                opcode = OP_add;
                break;
            case '-':
                opcode = OP_sub;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 3:
            switch(op) {
            case TOK_SHL:
                opcode = OP_shl;
                break;
            case TOK_SAR:
                opcode = OP_sar;
                break;
            case TOK_SHR:
                opcode = OP_shr;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 4:
            switch(op) {
            case '<':
                opcode = OP_lt;
                break;
            case '>':
                opcode = OP_gt;
                break;
            case TOK_LTE:
                opcode = OP_lte;
                break;
            case TOK_GTE:
                opcode = OP_gte;
                break;
            case TOK_INSTANCEOF:
                opcode = OP_instanceof;
                break;
            case TOK_IN:
                if (!(parse_flags & PF_NO_IN)) {
                    opcode = OP_in;
                } else {
                    return PARSE_STATE_RET;
                }
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 5:
            switch(op) {
            case TOK_EQ:
                opcode = OP_eq;
                break;
            case TOK_NEQ:
                opcode = OP_neq;
                break;
            case TOK_STRICT_EQ:
                opcode = OP_strict_eq;
                break;
            case TOK_STRICT_NEQ:
                opcode = OP_strict_neq;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 6:
            switch(op) {
            case '&':
                opcode = OP_and;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 7:
            switch(op) {
            case '^':
                opcode = OP_xor;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        case 8:
            switch(op) {
            case '|':
                opcode = OP_or;
                break;
            default:
                return PARSE_STATE_RET;
            }
            break;
        default:
            abort();
        }
        next_token(s);
        PARSE_CALL_SAVE3(s, 2, js_parse_expr_binary, parse_flags - (1 << PF_LEVEL_SHIFT), parse_flags, opcode, op_source_pos);
        emit_op_pos(s, opcode, op_source_pos);
    }
    return PARSE_STATE_RET;
}

int js_parse_logical_and_or(JSParseState *s, int state, int parse_flags)
{
    JSValue label1;
    int level, op;

    PARSE_START3();
    level = (parse_flags & PF_LEVEL_MASK) >> PF_LEVEL_SHIFT;
    if (level == 0) {
        PARSE_CALL(s, 0, js_parse_expr_binary, (parse_flags & ~PF_LEVEL_MASK) | (8 << PF_LEVEL_SHIFT));
        return PARSE_STATE_RET;
    }

    PARSE_CALL_SAVE1(s, 1, js_parse_logical_and_or, parse_flags - (1 << PF_LEVEL_SHIFT), parse_flags);

    level = (parse_flags & PF_LEVEL_MASK) >> PF_LEVEL_SHIFT;
    if (level == 1)
        op = TOK_LAND;
    else
        op = TOK_LOR;
    parse_flags &= ~PF_DROP;
    if (s->token.val == op) {
        label1 = new_label(s);

        for(;;) {
            next_token(s);
            emit_op(s, OP_dup);
            emit_goto(s, op == TOK_LAND ? OP_if_false : OP_if_true, &label1);
            emit_op(s, OP_drop);
            
            PARSE_PUSH_VAL(s, label1);
            PARSE_CALL_SAVE1(s, 2, js_parse_logical_and_or, parse_flags - (1 << PF_LEVEL_SHIFT), parse_flags);
            PARSE_POP_VAL(s, label1);

            level = (parse_flags & PF_LEVEL_MASK) >> PF_LEVEL_SHIFT;
            if (level == 1)
                op = TOK_LAND;
            else
                op = TOK_LOR;
            
            if (s->token.val != op)
                break;
        }

        emit_label(s, &label1);
    }
    return PARSE_STATE_RET;
}

int js_parse_cond_expr(JSParseState *s, int state, int parse_flags)
{
    JSValue label1, label2;
    
    PARSE_START3();

    PARSE_CALL_SAVE1(s, 2, js_parse_logical_and_or, parse_flags | (2 << PF_LEVEL_SHIFT), parse_flags);
    
    parse_flags &= ~PF_DROP;
    if (s->token.val == '?') {
        next_token(s);
        label1 = new_label(s);
        emit_goto(s, OP_if_false, &label1);
        
        PARSE_PUSH_VAL(s, label1);
        PARSE_CALL_SAVE1(s, 0, js_parse_assign_expr, parse_flags,
                         parse_flags);
        PARSE_POP_VAL(s, label1);

        label2 = new_label(s);
        emit_goto(s, OP_goto, &label2);

        js_parse_expect(s, ':');
        
        emit_label(s, &label1);
        
        PARSE_PUSH_VAL(s, label2);
        PARSE_CALL_SAVE1(s, 1, js_parse_assign_expr, parse_flags,
                         parse_flags);
        PARSE_POP_VAL(s, label2);

        emit_label(s, &label2);
    }
    return PARSE_STATE_RET;
}

int js_parse_assign_expr(JSParseState *s, int state, int parse_flags)
{
    int opcode, op, var_idx;
    PutLValueEnum special;
    JSSourcePos op_source_pos, source_pos;
    
    PARSE_START2();

    PARSE_CALL_SAVE1(s, 1, js_parse_cond_expr, parse_flags, parse_flags);
    
    op = s->token.val;
    if (op == '=' || (op >= TOK_MUL_ASSIGN && op <= TOK_OR_ASSIGN)) {
        op_source_pos = s->token.source_pos;
        next_token(s);
        get_lvalue(s, &opcode, &var_idx, &source_pos, (op != '='));

        PARSE_CALL_SAVE6(s, 0, js_parse_assign_expr, parse_flags & ~PF_DROP,
                         op, opcode, var_idx, parse_flags,
                         op_source_pos, source_pos);

        if (op != '=') {
            static const uint8_t assign_opcodes[] = {
                OP_mul, OP_div, OP_mod, OP_add, OP_sub,
                OP_shl, OP_sar, OP_shr, OP_and, OP_xor, OP_or,
                OP_pow,
            };
            emit_op_pos(s, assign_opcodes[op - TOK_MUL_ASSIGN], op_source_pos);
        }

        if (may_drop_result(s, parse_flags)) {
            special = PUT_LVALUE_NOKEEP_TOP;
            s->dropped_result = TRUE;
        } else {
            special = PUT_LVALUE_KEEP_TOP;
        }
        put_lvalue(s, opcode, var_idx, source_pos, special);
    }
    return PARSE_STATE_RET;
}

int js_parse_expr_comma(JSParseState *s, int state, int parse_flags)
{
    BOOL comma = FALSE;

    PARSE_START1();

    for(;;) {
        s->dropped_result = FALSE;
        PARSE_CALL_SAVE2(s, 0, js_parse_assign_expr, parse_flags,
                         comma, parse_flags);
        if (comma) {
            /* prevent get_lvalue from using the last expression as an
               lvalue. */
            s->last_opcode_pos = -1;
        }
        if (s->token.val != ',')
            break;
        comma = TRUE;
        if (!s->dropped_result)
            emit_op(s, OP_drop);
        next_token(s);
    }
    if ((parse_flags & PF_DROP) && !s->dropped_result) {
        emit_op(s, OP_drop);
    }
    return PARSE_STATE_RET;
}

void js_parse_assign_expr2(JSParseState *s, int parse_flags)
{
    js_parse_call(s, PARSE_FUNC_js_parse_assign_expr, parse_flags);
}

void js_parse_expr2(JSParseState *s, int parse_flags)
{
    js_parse_call(s, PARSE_FUNC_js_parse_expr_comma, parse_flags);
}

void js_parse_expr(JSParseState *s)
{
    js_parse_expr2(s, 0);
}

void js_parse_expr_paren(JSParseState *s)
{
    js_parse_expect(s, '(');
    js_parse_expr(s);
    js_parse_expect(s, ')');
}

BlockEnv *push_break_entry(JSParseState *s, JSValue label_name, JSValue label_break, JSValue label_cont, int drop_count)
{
    JSContext *ctx = s->ctx;
    JSGCRef label_name_ref;
    int ret, block_env_len;
    BlockEnv *be;
    
    block_env_len = sizeof(BlockEnv) / sizeof(JSValue);
    JS_PUSH_VALUE(ctx, label_name);
    ret = JS_StackCheck(ctx, block_env_len);
    JS_POP_VALUE(ctx, label_name);
    if (ret)
        js_parse_error_stack_overflow(s);
    ctx->sp -= block_env_len;
    be = (BlockEnv *)ctx->sp;
    be->prev = s->top_break;
    s->top_break = SP_TO_VALUE(ctx, be);
    be->label_name = label_name;
    be->label_break = label_break;
    be->label_cont = label_cont;
    be->label_finally = LABEL_NONE;
    be->drop_count = JS_NewShortInt(drop_count);
    return be;
}

void pop_break_entry(JSParseState *s)
{
    JSContext *ctx = s->ctx;
    BlockEnv *be;
    
    be = VALUE_TO_SP(ctx, s->top_break);
    s->top_break = be->prev;
    ctx->sp += sizeof(BlockEnv) / sizeof(JSValue);
    ctx->stack_bottom = ctx->sp;
}

void emit_return(JSParseState *s, BOOL hasval, JSSourcePos source_pos)
{
    JSValue top_val;
    BlockEnv *top;
    int i, drop_count;

    drop_count = 0;
    top_val = s->top_break;
    while (!JS_IsNull(top_val)) {
        top = VALUE_TO_SP(s->ctx, top_val);
        /* no need to drop if no "finally" */
        drop_count += JS_VALUE_GET_INT(top->drop_count); 

        if (!label_is_none(top->label_finally)) {
            if (!hasval) {
                emit_op(s, OP_undefined);
                hasval = TRUE;
            }
            for(i = 0; i < drop_count; i++)
                emit_op(s, OP_nip); /* must keep the stack stop */
            drop_count = 0;
            /* execute the "finally" block */
            emit_goto(s, OP_gosub, &top->label_finally);
        }
        top_val = top->prev;
    }
    emit_op_pos(s, hasval ? OP_return : OP_return_undef, source_pos);
}

void emit_break(JSParseState *s, JSValue label_name, int is_cont)
{
    JSValue top_val;
    BlockEnv *top;
    int i;
    JSValue *plabel;
    JSGCRef label_name_ref;
    BOOL is_labelled_stmt;
    
    top_val = s->top_break;
    while (!JS_IsNull(top_val)) {
        top = VALUE_TO_SP(s->ctx, top_val);
        is_labelled_stmt = (top->label_cont == LABEL_NONE &&
                            JS_VALUE_GET_INT(top->drop_count) == 0);
        if ((label_name == JS_NULL && !is_labelled_stmt) ||
            top->label_name == label_name) {
            if (is_cont)
                plabel = &top->label_cont;
            else
                plabel = &top->label_break;
            if (!label_is_none(*plabel)) {
                emit_goto(s, OP_goto, plabel);
                return;
            }
        }
        JS_PUSH_VALUE(s->ctx, label_name);
        for(i = 0; i < JS_VALUE_GET_INT(top->drop_count); i++)
            emit_op(s, OP_drop);
        if (!label_is_none(top->label_finally)) {
            /* must push dummy value to keep same stack depth */
            emit_op(s, OP_undefined);
            emit_goto(s, OP_gosub, &top->label_finally);
            emit_op(s, OP_drop);
        }
        JS_POP_VALUE(s->ctx, label_name);
        top_val = top->prev;
    }
    if (label_name == JS_NULL) {
        if (is_cont)
            js_parse_error(s, "continue must be inside loop");
        else
            js_parse_error(s, "break must be inside loop or switch");
    } else {
        js_parse_error(s, "break/continue label not found");
    }
}

int define_var(JSParseState *s, JSVarRefKindEnum *pvar_kind, JSValue name)
{
    JSVarRefKindEnum var_kind;
    int var_idx;

    if (s->is_eval) {
        var_idx = find_ext_var(s, name);
        if (var_idx < 0) {
            var_idx = add_ext_var(s, name, (JS_VARREF_KIND_GLOBAL << 16) | 1);
        } else {
            JSFunctionBytecode *b = JS_VALUE_TO_PTR(s->cur_func);
            JSValueArray *arr = JS_VALUE_TO_PTR(b->ext_vars);
            arr->arr[2 * var_idx + 1] = JS_NewShortInt((JS_VARREF_KIND_GLOBAL << 16) | 1);
        }
        var_kind = JS_VARREF_KIND_VAR_REF;
    } else {
        JSFunctionBytecode *b;
        int arg_count;

        b = JS_VALUE_TO_PTR(s->cur_func);
        arg_count = b->arg_count;
        
        var_idx = find_var(s, name);
        if (var_idx >= 0) {
            if (var_idx < arg_count) {
                var_kind = JS_VARREF_KIND_ARG;
            } else {
                var_kind = JS_VARREF_KIND_VAR;
                var_idx -= arg_count;
            }
        } else {
            var_idx = add_var(s, name);
            var_kind = JS_VARREF_KIND_VAR;
            var_idx -= arg_count;
        }
    }
    *pvar_kind = var_kind;
    return var_idx;
}

void put_var(JSParseState *s, JSVarRefKindEnum var_kind, int var_idx, JSSourcePos source_pos)
{
    int opcode;
    if (var_kind == JS_VARREF_KIND_ARG)
        opcode = OP_put_arg;
    else if (var_kind == JS_VARREF_KIND_VAR)
        opcode = OP_put_loc;
    else
        opcode = OP_put_var_ref_nocheck;
    emit_var(s, opcode, var_idx, source_pos);
}

void js_parse_var(JSParseState *s, BOOL in_accepted)
{
    JSVarRefKindEnum var_kind;
    int var_idx;
    JSSourcePos ident_source_pos;
    
    for(;;) {
        ident_source_pos = s->token.source_pos;
        if (s->token.val != TOK_IDENT)
            js_parse_error(s, "variable name expected");
        if (s->token.value == js_get_atom(s->ctx, JS_ATOM_arguments))
            js_parse_error(s, "invalid variable name");
        var_idx = define_var(s, &var_kind, s->token.value);
        next_token(s);
        if (s->token.val == '=') {
            next_token(s);
            js_parse_assign_expr2(s, in_accepted ? 0 : PF_NO_IN);
            put_var(s, var_kind, var_idx, ident_source_pos);
        }
        if (s->token.val != ',')
            break;
        next_token(s);
    }
}

void set_eval_ret_undefined(JSParseState *s)
{
    if (s->eval_ret_idx >= 0) {
        emit_op(s, OP_undefined);
        emit_var(s, OP_put_loc, s->eval_ret_idx, s->pc2line_source_pos);
    }
}

int js_parse_block(JSParseState *s, int state, int dummy_param)
{
    PARSE_START1();
    js_parse_expect(s, '{');
    if (s->token.val != '}') {
        for(;;) {
            PARSE_CALL(s, 0, js_parse_statement, 0);
            if (s->token.val == '}')
                break;
        }
    }
    next_token(s);
    return PARSE_STATE_RET;
}

/* The statement parser assumes that the stack contains the result of
   the last statement. Note: if not in eval code, the return value of
   a statement does not matter */
int js_parse_statement(JSParseState *s, int state, int dummy_param)
{
    JSValue label_name;
    JSGCRef label_name_ref;
    
    PARSE_START12();
    
    /* specific label handling */
    if (is_label(s)) {
        JSValue top_val;
        BlockEnv *top;
        
        label_name = s->token.value;
        JS_PUSH_VALUE(s->ctx, label_name);
        next_token(s);
        js_parse_expect(s, ':');
        JS_POP_VALUE(s->ctx, label_name);

        for(top_val = s->top_break; !JS_IsNull(top_val); top_val = top->prev) {
            top = VALUE_TO_SP(s->ctx, top_val);
            if (top->label_name == label_name)
                js_parse_error(s, "duplicate label name");
        }

        if (s->token.val != TOK_FOR &&
            s->token.val != TOK_DO &&
            s->token.val != TOK_WHILE) {
            /* labelled regular statement */
            BlockEnv *be;
            push_break_entry(s, label_name, new_label(s), LABEL_NONE, 0);

            PARSE_CALL(s, 11, js_parse_statement, 0);

            be = VALUE_TO_SP(s->ctx, s->top_break);
            emit_label(s, &be->label_break);
            pop_break_entry(s);
            goto done;
        }
    } else {
        label_name = JS_NULL;
    }
    
    switch(s->token.val) {
    case '{':
        PARSE_CALL(s, 0, js_parse_block, 0);
        break;
    case TOK_RETURN:
        {
            BOOL has_val;
            JSSourcePos op_source_pos;
            if (s->is_eval)
                js_parse_error(s, "return not in a function");
            op_source_pos = s->token.source_pos;
            next_token(s);
            if (s->token.val != ';' && s->token.val != '}' && !s->got_lf) {
                js_parse_expr(s);
                has_val = TRUE;
            } else {
                has_val = FALSE;
            }
            emit_return(s, has_val, op_source_pos);
            js_parse_expect_semi(s);
        }
        break;
    case TOK_THROW:
        {
            JSSourcePos op_source_pos;
            op_source_pos = s->token.source_pos;
            next_token(s);
            if (s->got_lf)
                js_parse_error(s, "line terminator not allowed after throw");
            js_parse_expr(s);
            emit_op_pos(s, OP_throw, op_source_pos);
            js_parse_expect_semi(s);
        }
        break;
    case TOK_VAR:
        next_token(s);
        js_parse_var(s, TRUE);
        js_parse_expect_semi(s);
        break;
    case TOK_IF:
        {
            JSValue label1, label2;
            next_token(s);
            set_eval_ret_undefined(s);
            js_parse_expr_paren(s);
            label1 = new_label(s);
            emit_goto(s, OP_if_false, &label1);

            PARSE_PUSH_VAL(s, label1);
            PARSE_CALL(s, 1, js_parse_statement, 0);
            PARSE_POP_VAL(s, label1);
            
            if (s->token.val == TOK_ELSE) {
                next_token(s);
                
                label2 = new_label(s);
                emit_goto(s, OP_goto, &label2);

                emit_label(s, &label1);
                
                PARSE_PUSH_VAL(s, label2);
                PARSE_CALL(s, 2, js_parse_statement, 0);
                PARSE_POP_VAL(s, label2);
                
                label1 = label2;
            }
            emit_label(s, &label1);
        }
        break;
    case TOK_WHILE:
        {
            BlockEnv *be;
            
            be = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
            next_token(s);

            set_eval_ret_undefined(s);

            emit_label(s, &be->label_cont);
            js_parse_expr_paren(s);
            emit_goto(s, OP_if_false, &be->label_break);
            
            PARSE_CALL(s, 3, js_parse_statement, 0);

            be = VALUE_TO_SP(s->ctx, s->top_break);
            emit_goto(s, OP_goto, &be->label_cont);

            emit_label(s, &be->label_break);

            pop_break_entry(s);
        }
        break;
    case TOK_DO:
        {
            JSValue label1;
            BlockEnv *be;

            be = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
            
            label1 = new_label(s);
            
            next_token(s);
            set_eval_ret_undefined(s);

            emit_label(s, &label1);

            PARSE_PUSH_VAL(s, label1);
            PARSE_CALL(s, 4, js_parse_statement, 0);
            PARSE_POP_VAL(s, label1);

            be = VALUE_TO_SP(s->ctx, s->top_break);
            emit_label(s, &be->label_cont);
            js_parse_expect(s, TOK_WHILE);
            js_parse_expr_paren(s);
            /* Insert semicolon if missing */
            if (s->token.val == ';') {
                next_token(s);
            }
            emit_goto(s, OP_if_true, &label1);

            emit_label(s, &be->label_break);

            pop_break_entry(s);
        }
        break;
    case TOK_FOR:
        {
            int bits;
            BlockEnv *be;
            
            be = push_break_entry(s, label_name, new_label(s), new_label(s), 0);
            
            next_token(s);
            set_eval_ret_undefined(s);

            js_parse_expect1(s, '(');
            bits = js_parse_skip_parens_token(s);
            next_token(s);
            
            if (!(bits & SKIP_HAS_SEMI)) {
                JSValue label_expr, label_body, label_next;
                int opcode, var_idx;
                
                be->drop_count = JS_NewShortInt(1);
                
                label_expr = new_label(s);
                label_body = new_label(s);
                label_next = new_label(s);
                
                emit_goto(s, OP_goto, &label_expr);
                
                emit_label(s, &label_next);
                
                if (s->token.val == TOK_VAR) {
                    JSVarRefKindEnum var_kind;
                    next_token(s);
                    var_idx = define_var(s, &var_kind, s->token.value);
                    put_var(s, var_kind, var_idx, s->pc2line_source_pos);
                    
                    next_token(s);
                } else {
                    JSSourcePos source_pos;
                    
                    /* XXX: js_parse_left_hand_side_expr */
                    js_parse_assign_expr2(s, PF_NO_IN);
                    
                    get_lvalue(s, &opcode, &var_idx, &source_pos, FALSE);
                    put_lvalue(s, opcode, var_idx, source_pos,
                               PUT_LVALUE_NOKEEP_BOTTOM);
                }
                
                emit_goto(s, OP_goto, &label_body);
                
                if (s->token.val == TOK_IN) {
                    opcode = OP_for_in_start;
                } else if (s->token.val == TOK_IDENT &&
                           s->token.value == js_get_atom(s->ctx, JS_ATOM_of)) {
                    opcode = OP_for_of_start;
                } else {
                    js_parse_error(s, "expected 'of' or 'in' in for control expression");
                }
                
                next_token(s);
                
                emit_label(s, &label_expr);
                js_parse_expr(s);
                emit_op(s, opcode);
                
                emit_goto(s, OP_goto, &be->label_cont);
                
                js_parse_expect(s, ')');
                
                emit_label(s, &label_body);
                
                PARSE_PUSH_VAL(s, label_next);
                PARSE_CALL(s, 5, js_parse_statement, 0);
                PARSE_POP_VAL(s, label_next);
                
                be = VALUE_TO_SP(s->ctx, s->top_break);
                emit_label(s, &be->label_cont);
                emit_op(s, OP_for_of_next);
                
                /* on stack: enum_rec / enum_obj value bool */
                emit_goto(s, OP_if_false, &label_next);
                /* drop the undefined value from for_xx_next */
                emit_op(s, OP_drop);

                emit_label(s, &be->label_break);
                emit_op(s, OP_drop);
            } else {
                JSValue label_test;
                JSParsePos expr3_pos;
                int tmp_val;
                
                /* initial expression */
                if (s->token.val != ';') {
                    if (s->token.val == TOK_VAR) {
                        next_token(s);
                        js_parse_var(s, FALSE);
                    } else {
                        js_parse_expr2(s, PF_NO_IN | PF_DROP);
                    }
                }
                js_parse_expect(s, ';');
                
                label_test = new_label(s);
                
                /* test expression */
                emit_label(s, &label_test);
                if (s->token.val != ';') {
                    js_parse_expr(s);
                    emit_goto(s, OP_if_false, &be->label_break);
                }
                js_parse_expect(s, ';');

                if (s->token.val != ')') {
                    /* skip the third expression if present */
                    js_parse_get_pos(s, &expr3_pos);
                    js_skip_expr(s);
                } else {
                    expr3_pos.source_pos = -1;
                    expr3_pos.got_lf = 0; /* avoid warning */
                    expr3_pos.regexp_allowed = 0; /* avoid warning */
                }
                js_parse_expect(s, ')');

                PARSE_PUSH_VAL(s, label_test);
                PARSE_PUSH_INT(s, expr3_pos.got_lf | (expr3_pos.regexp_allowed << 1));
                PARSE_PUSH_INT(s, expr3_pos.source_pos);
                PARSE_CALL(s, 6, js_parse_statement, 0);
                PARSE_POP_INT(s, expr3_pos.source_pos);
                PARSE_POP_INT(s, tmp_val);
                expr3_pos.got_lf = tmp_val & 1;
                expr3_pos.regexp_allowed = tmp_val >> 1;
                PARSE_POP_VAL(s, label_test);
                
                be = VALUE_TO_SP(s->ctx, s->top_break);
                emit_label(s, &be->label_cont);

                /* parse the third expression, if present, after the
                   statement */
                if (expr3_pos.source_pos != -1) {
                    JSParsePos end_pos;
                    js_parse_get_pos(s, &end_pos);
                    js_parse_seek_token(s, &expr3_pos);
                    js_parse_expr2(s, PF_DROP);
                    js_parse_seek_token(s, &end_pos);
                }

                emit_goto(s, OP_goto, &label_test);
                
                be = VALUE_TO_SP(s->ctx, s->top_break);
                emit_label(s, &be->label_break);
            }
            pop_break_entry(s);
        }
        break;
    case TOK_BREAK:
    case TOK_CONTINUE:
        {
            int is_cont = (s->token.val == TOK_CONTINUE);
            JSValue label_name;
            
            next_token(s);
            if (!s->got_lf && s->token.val == TOK_IDENT)
                label_name = s->token.value;
            else
                label_name = JS_NULL;
            emit_break(s, label_name, is_cont);
            if (label_name != JS_NULL) {
                next_token(s);
            }
            js_parse_expect_semi(s);
        }
        break;
    case TOK_SWITCH:
        {
            JSValue label_case;
            int default_label_pos;
            BlockEnv *be;

            be = push_break_entry(s, label_name, new_label(s), LABEL_NONE, 1);

            next_token(s);
            set_eval_ret_undefined(s);

            js_parse_expr_paren(s);

            js_parse_expect(s, '{');
            default_label_pos = -1;
            label_case = LABEL_NONE; /* label to the next case */
            while (s->token.val != '}') {
                if (s->token.val == TOK_CASE) {
                    JSValue label1 = LABEL_NONE;
                    if (!label_is_none(label_case)) {
                        /* skip the case if needed */
                        label1 = new_label(s);
                        emit_goto(s, OP_goto, &label1);
                        emit_label(s, &label_case);
                        label_case = LABEL_NONE;
                    }
                    for (;;) {
                        /* parse a sequence of case clauses */
                        next_token(s);
                        emit_op(s, OP_dup);
                        js_parse_expr(s);
                        js_parse_expect(s, ':');
                        emit_op(s, OP_strict_eq);
                        if (s->token.val == TOK_CASE) {
                            if (label_is_none(label1))
                                label1 = new_label(s);
                            emit_goto(s, OP_if_true, &label1);
                        } else {
                            label_case = new_label(s);
                            emit_goto(s, OP_if_false, &label_case);
                            if (!label_is_none(label1))
                                emit_label(s, &label1);
                            break;
                        }
                    }
                } else if (s->token.val == TOK_DEFAULT) {
                    next_token(s);
                    js_parse_expect(s, ':');
                    if (default_label_pos >= 0)
                        js_parse_error(s, "duplicate default");
                    if (label_is_none(label_case)) {
                        /* falling thru direct from switch expression */
                        label_case = new_label(s);
                        emit_goto(s, OP_goto, &label_case);
                    }
                    default_label_pos = s->byte_code_len; 
                } else {
                    if (label_is_none(label_case))
                        js_parse_error(s, "invalid switch statement");
                    PARSE_PUSH_VAL(s, label_case);
                    PARSE_CALL_SAVE1(s, 7, js_parse_statement, 0,
                                     default_label_pos);
                    PARSE_POP_VAL(s, label_case);
                }
            }
            js_parse_expect(s, '}');
            if (default_label_pos >= 0) {
                /* patch the default label */
                emit_label_pos(s, &label_case, default_label_pos);
            } else if (!label_is_none(label_case)) {
                emit_label(s, &label_case);
            }
            be = VALUE_TO_SP(s->ctx, s->top_break);
            emit_label(s, &be->label_break);
            emit_op(s, OP_drop); /* drop the switch expression */

            pop_break_entry(s);
        }
        break;
    case TOK_TRY:
        {
            JSValue label_catch, label_finally, label_end;
            BlockEnv *be;
            
            set_eval_ret_undefined(s);
            next_token(s);
            label_catch = new_label(s);
            label_finally = new_label(s);

            emit_goto(s, OP_catch, &label_catch);
            
            be = push_break_entry(s, JS_NULL, LABEL_NONE, LABEL_NONE, 1);
            be->label_finally = label_finally;

            PARSE_PUSH_VAL(s, label_catch);
            PARSE_CALL(s, 8, js_parse_block, 0);
            PARSE_POP_VAL(s, label_catch);

            be = VALUE_TO_SP(s->ctx, s->top_break);
            label_finally = be->label_finally;
            pop_break_entry(s);

            /* drop the catch offset */
            emit_op(s, OP_drop);

            /* must push dummy value to keep same stack size */
            emit_op(s, OP_undefined);
            emit_goto(s, OP_gosub, &label_finally);
            emit_op(s, OP_drop);

            label_end = new_label(s);
            emit_goto(s, OP_goto, &label_end);
            
            if (s->token.val == TOK_CATCH) {
                JSValue label_catch2;
                int var_idx;
                JSValue name;

                label_catch2 = new_label(s);

                next_token(s);
                js_parse_expect(s, '(');
                if (s->token.val != TOK_IDENT)
                    js_parse_error(s, "identifier expected");
                name = s->token.value;
                /* XXX: the local scope is not implemented, so we add
                   a normal variable */
                if (find_var(s, name) >= 0 || find_ext_var(s, name) >= 0) {
                    js_parse_error(s, "catch variable already exists");
                }
                var_idx = add_var(s, name);
                next_token(s);
                js_parse_expect(s, ')');
                
                /* store the exception value in the variable */
                emit_label(s, &label_catch);
                {
                    JSFunctionBytecode *b = JS_VALUE_TO_PTR(s->cur_func);
                    emit_var(s, OP_put_loc, var_idx - b->arg_count, s->pc2line_source_pos);
                }

                emit_goto(s, OP_catch, &label_catch2);
                
                be = push_break_entry(s, JS_NULL, LABEL_NONE, LABEL_NONE, 1);
                be->label_finally = label_finally;
                
                PARSE_PUSH_VAL(s, label_end);
                PARSE_PUSH_VAL(s, label_catch2);
                PARSE_CALL(s, 9, js_parse_block, 0);
                PARSE_POP_VAL(s, label_catch2);
                PARSE_POP_VAL(s, label_end);

                be = VALUE_TO_SP(s->ctx, s->top_break);
                label_finally = be->label_finally;
                pop_break_entry(s);

                /* drop the catch2 offset */
                emit_op(s, OP_drop);
                /* must push dummy value to keep same stack size */
                emit_op(s, OP_undefined);
                emit_goto(s, OP_gosub, &label_finally);
                emit_op(s, OP_drop);
                emit_goto(s, OP_goto, &label_end);

                /* catch exceptions thrown in the catch block to execute the
                 * finally clause and rethrow the exception */
                emit_label(s, &label_catch2);
                /* catch value is at TOS, no need to push undefined */
                emit_goto(s, OP_gosub, &label_finally);
                emit_op(s, OP_throw);
                
            } else if (s->token.val == TOK_FINALLY) {
                /* finally without catch : execute the finally clause
                 * and rethrow the exception */
                emit_label(s, &label_catch);
                /* catch value is at TOS, no need to push undefined */
                emit_goto(s, OP_gosub, &label_finally);
                emit_op(s, OP_throw);
            } else {
                js_parse_error(s, "expecting catch or finally");
            }

            emit_label(s, &label_finally);
            if (s->token.val == TOK_FINALLY) {
                next_token(s);
                /* XXX: we don't return the correct value in eval() */
                /* on the stack: ret_value gosub_ret_value */
                push_break_entry(s, JS_NULL, LABEL_NONE, LABEL_NONE, 2);

                PARSE_PUSH_VAL(s, label_end);
                PARSE_CALL(s, 10, js_parse_block, 0);
                PARSE_POP_VAL(s, label_end);

                pop_break_entry(s);
            }
            emit_op(s, OP_ret);
            emit_label(s, &label_end);
        }
        break;
    case ';':
        /* empty statement */
        next_token(s);
        break;
    default:
        if (s->eval_ret_idx >= 0) {
            /* store the expression value so that it can be returned
               by eval() */
            js_parse_expr(s);
            emit_var(s, OP_put_loc, s->eval_ret_idx, s->pc2line_source_pos);
        } else {
            js_parse_expr2(s, PF_DROP);
        }
        js_parse_expect_semi(s);
        break;
    }
 done:
    return PARSE_STATE_RET;
}

static JSParseFunc *parse_func_table[] = {
    js_parse_expr_comma,
    js_parse_assign_expr,
    js_parse_cond_expr,
    js_parse_logical_and_or,
    js_parse_expr_binary,
    js_parse_unary,
    js_parse_postfix_expr,
    js_parse_statement,
    js_parse_block,
    js_parse_json_value,
    re_parse_alternative,
    re_parse_disjunction,
};

void js_parse_source_element(JSParseState *s)
{
    if (s->token.val == TOK_FUNCTION) {
        js_parse_function_decl(s, JS_PARSE_FUNC_STATEMENT, JS_NULL);
    } else {
        js_parse_call(s, PARSE_FUNC_js_parse_statement, 0);
    }
}
    
JSFunctionBytecode *js_alloc_function_bytecode(JSContext *ctx)
{
    JSFunctionBytecode *b;
    b = js_mallocz(ctx, sizeof(JSFunctionBytecode), JS_MTAG_FUNCTION_BYTECODE);
    if (!b)
        return NULL;
    b->func_name = JS_NULL;
    b->byte_code = JS_NULL;
    b->cpool = JS_NULL;
    b->vars = JS_NULL;
    b->ext_vars = JS_NULL;
    b->filename = JS_NULL;
    b->pc2line = JS_NULL;
    return b;
}

/* the current token must be TOK_FUNCTION for JS_PARSE_FUNC_STATEMENT
   or JS_PARSE_FUNC_EXPR. Otherwise it is '('. */
void js_parse_function_decl(JSParseState *s, JSParseFunctionEnum func_type, JSValue func_name)
{
    JSContext *ctx = s->ctx;
    BOOL is_expr;
    JSFunctionBytecode *b;
    int idx, skip_bits;
    JSVarRefKindEnum var_kind;
    JSValue bfunc;
    JSGCRef func_name_ref, bfunc_ref;
    
    is_expr = (func_type != JS_PARSE_FUNC_STATEMENT);

    if (func_type == JS_PARSE_FUNC_STATEMENT ||
        func_type == JS_PARSE_FUNC_EXPR) {
        next_token(s);
        if (s->token.val != TOK_IDENT && !is_expr)
            js_parse_error(s, "function name expected");
        if (s->token.val == TOK_IDENT) {
            func_name = s->token.value;
            JS_PUSH_VALUE(ctx, func_name);
            next_token(s);
            JS_POP_VALUE(ctx, func_name);
        }
    }

    JS_PUSH_VALUE(ctx, func_name);
    b = js_alloc_function_bytecode(s->ctx);
    if (!b)
        js_parse_error_mem(s);
    bfunc = JS_VALUE_FROM_PTR(b);
    JS_PUSH_VALUE(ctx, bfunc);

    b->filename = s->filename_str;
    b->func_name = func_name_ref.val;
    b->source_pos = s->token.source_pos;
    b->has_column = s->has_column;
    
    js_parse_expect1(s, '(');
    /* skip the arguments */
    js_skip_parens(s, NULL);
    
    js_parse_expect1(s, '{');

    /* skip the code */
    skip_bits = js_skip_parens(s, is_expr ? &func_name_ref.val : NULL);
                  
    b = JS_VALUE_TO_PTR(bfunc_ref.val);
    b->has_arguments = ((skip_bits & SKIP_HAS_ARGUMENTS) != 0);
    b->has_local_func_name = ((skip_bits & SKIP_HAS_FUNC_NAME) != 0);
    
    idx = cpool_add(s, bfunc_ref.val);
    if (is_expr) {
        /* create the function object */
        emit_op(s, OP_fclosure);
        emit_u16(s, idx);
    } else {
        idx = define_var(s, &var_kind, func_name_ref.val);
        /* size of hoisted for OP_fclosure + OP_put_loc/OP_put_arg/OP_put_ref */
        s->hoisted_code_len += 3 + 3;
        if (var_kind == JS_VARREF_KIND_VAR) {
            b = JS_VALUE_TO_PTR(s->cur_func);
            idx += b->arg_count;
        }
        b = JS_VALUE_TO_PTR(bfunc_ref.val);
        /* hoisted function definition: save the variable index to
           define it at the start of the function */
        b->arg_count = idx + 1;
    }
    JS_POP_VALUE(ctx, bfunc);
    JS_POP_VALUE(ctx, func_name);
}

void define_hoisted_functions(JSParseState *s, BOOL is_eval)
{
    JSValueArray *cpool;
    JSValue val;
    JSFunctionBytecode *b;
    int idx, saved_byte_code_len, arg_count, i, op;
    
    /* add pc2line info */
    b = JS_VALUE_TO_PTR(s->cur_func);
    if (b->pc2line != JS_NULL) {
        int h, n;

        /* byte align */
        n = (-s->pc2line_bit_len) & 7;
        if (n != 0)
            pc2line_put_bits(s, n, 0);

        n = s->hoisted_code_len;
        h = 0;
        for(;;) {
            pc2line_put_bits(s, 8, (n & 0x7f) | h);
            n >>= 7;
            if (n == 0)
                break;
            h |= 0x80;
        }
    }

    if (s->hoisted_code_len == 0)
        return;
    emit_insert(s, 0, s->hoisted_code_len);

    b = JS_VALUE_TO_PTR(s->cur_func);
    arg_count = b->arg_count;

    saved_byte_code_len = s->byte_code_len;
    s->byte_code_len = 0;
    cpool = JS_VALUE_TO_PTR(b->cpool);
    for(i = 0; i < s->cpool_len; i++) {
        val = cpool->arr[i];
        if (JS_IsPtr(val)) {
            b = JS_VALUE_TO_PTR(val);
            if (b->mtag == JS_MTAG_FUNCTION_BYTECODE &&
                b->arg_count != 0) {
                idx = b->arg_count - 1;
                /* XXX: could use smaller opcodes */
                if (is_eval) {
                    op = OP_put_var_ref_nocheck;
                } else if (idx < arg_count) {
                    op = OP_put_arg;
                } else {
                    idx -= arg_count;
                    op = OP_put_loc;
                }
                /* no realloc possible here */
                emit_u8(s, OP_fclosure);
                emit_u16(s, i);

                emit_u8(s, op);
                emit_u16(s, idx);
            }
        }
    }
    s->byte_code_len = saved_byte_code_len;
}

void js_parse_function(JSParseState *s)
{
    JSFunctionBytecode *b;
    int arg_count;
    
    next_token(s);

    js_parse_expect(s, '(');

    while (s->token.val != ')') {
        JSValue name;
        /* XXX: gc */
        if (s->token.val != TOK_IDENT)
            js_parse_error(s, "missing formal parameter");
        name = s->token.value;
        if (name == js_get_atom(s->ctx, JS_ATOM_eval) ||
            name == js_get_atom(s->ctx, JS_ATOM_arguments)) {
            js_parse_error(s, "invalid argument name");
        }
        if (find_var(s, name) >= 0)
            js_parse_error(s, "duplicate argument name");
        add_var(s, name);
        next_token(s);
        if (s->token.val == ')')
            break;
        js_parse_expect(s, ',');
    }
    b = JS_VALUE_TO_PTR(s->cur_func);
    arg_count = b->arg_count = s->local_vars_len;

    next_token(s);
    
    js_parse_expect(s, '{');

    /* initialize the arguments */
    b = JS_VALUE_TO_PTR(s->cur_func);
    if (b->has_arguments) {
        int var_idx;
        var_idx = add_var(s, js_get_atom(s->ctx, JS_ATOM_arguments));
        emit_op(s, OP_arguments);
        put_var(s, JS_VARREF_KIND_VAR, var_idx - arg_count, s->pc2line_source_pos);
    }

    /* XXX: initialize the function name */
    b = JS_VALUE_TO_PTR(s->cur_func);
    if (b->has_local_func_name) {
        int var_idx;
        /* XXX: */
        var_idx = add_var(s, b->func_name);
        emit_op(s, OP_this_func);
        put_var(s, JS_VARREF_KIND_VAR, var_idx - arg_count, s->pc2line_source_pos);
    }
    
    while (s->token.val != '}') {
        js_parse_source_element(s);
    }

    if (js_is_live_code(s))
        emit_op(s, OP_return_undef);

    next_token(s);

    define_hoisted_functions(s, FALSE);
    
    /* save the bytecode to the function */
    b = JS_VALUE_TO_PTR(s->cur_func);
    b->byte_code = s->byte_code;
}

void js_parse_program(JSParseState *s)
{
    JSFunctionBytecode *b;

    next_token(s);

    /* hidden variable for the return value */
    if (s->has_retval) {
        s->eval_ret_idx = add_var(s, js_get_atom(s->ctx, JS_ATOM__ret_));
    }
    
    while (s->token.val != TOK_EOF) {
        js_parse_source_element(s);
    }

    if (s->eval_ret_idx >= 0) {
        emit_var(s, OP_get_loc, s->eval_ret_idx, s->pc2line_source_pos);
        emit_op(s, OP_return);
    } else {
        emit_op(s, OP_return_undef);
    }

    define_hoisted_functions(s, TRUE);

    /* save the bytecode to the function */
    b = JS_VALUE_TO_PTR(s->cur_func);
    b->byte_code = s->byte_code;
}

#define CVT_VAR_SIZE_MAX 16

void convert_ext_vars_to_local_vars_bytecode(JSParseState *s, uint8_t *byte_code, int byte_code_len, int var_start, const ConvertVarEntry *cvt_tab, int tab_len)
{
    int pos, var_end, j, op, var_idx;
    const JSOpCode *oi;
    
    var_end = var_start + tab_len;
    pos = 0;
    while (pos < byte_code_len) {
        op = byte_code[pos];
        oi = &opcode_info[op];
        switch(op) {
        case OP_get_var_ref:
        case OP_put_var_ref:
        case OP_get_var_ref_nocheck:
        case OP_put_var_ref_nocheck:
            var_idx = get_u16(byte_code + pos + 1);
            if (var_idx >= var_start && var_idx < var_end) {
                j = var_idx - var_start;
                put_u16(byte_code + pos + 1, cvt_tab[j].new_var_idx);
                if (cvt_tab[j].is_local) {
                    if (op == OP_get_var_ref || op == OP_get_var_ref_nocheck) {
                        byte_code[pos] = OP_get_loc;
                    } else {
                        byte_code[pos] = OP_put_loc;
                    }
                }
            }
            break;
        default:
            break;
        }
        pos += oi->size;
    }
}

/* no allocation */
void convert_ext_vars_to_local_vars(JSParseState *s)
{
    JSValueArray *ext_vars;
    JSFunctionBytecode *b;
    JSByteArray *bc_arr;
    JSValue var_name, decl;
    int i0, i, j, var_idx, l;
    ConvertVarEntry cvt_tab[CVT_VAR_SIZE_MAX];
    
    b = JS_VALUE_TO_PTR(s->cur_func);
    if (s->local_vars_len == 0 || b->ext_vars_len == 0)
        return;
    bc_arr = JS_VALUE_TO_PTR(b->byte_code);
    ext_vars = JS_VALUE_TO_PTR(b->ext_vars);

    /* do it by parts to save memory */
    j = 0;
    for(i0 = 0; i0 < b->ext_vars_len; i0 += CVT_VAR_SIZE_MAX) {
        l = min_int(b->ext_vars_len - i0, CVT_VAR_SIZE_MAX);
        for(i = 0; i < l; i++) {
            var_name = ext_vars->arr[2 * (i0 + i)];
            decl = ext_vars->arr[2 * (i0 + i) + 1];
            var_idx = find_var(s, var_name);
            /* fail safe: we avoid arguments even if they cannot appear */
            if (var_idx >= b->arg_count) {
                cvt_tab[i].new_var_idx = var_idx - b->arg_count;
                cvt_tab[i].is_local = TRUE;
            } else {
                cvt_tab[i].new_var_idx = j;
                cvt_tab[i].is_local = FALSE;
                ext_vars->arr[2 * j] = var_name;
                ext_vars->arr[2 * j + 1] = decl;
                j++;
            }
        }
        if (j != (i0 + l)) {
            convert_ext_vars_to_local_vars_bytecode(s, bc_arr->buf, s->byte_code_len,
                                                    i0, cvt_tab, l);
        }
    }
    b->ext_vars_len = j;
}

/* prepare the analysis of the code starting at position 'pos' */
void compute_stack_size_push(JSParseState *s, JSByteArray *arr, uint8_t *explore_tab, uint32_t pos, int stack_len)
{
    int short_stack_len;
    
#if 0
    js_printf(s->ctx, "%5d: %d\n", pos, stack_len);
#endif
    if (pos >= (uint32_t)arr->size)
        js_parse_error(s, "bytecode buffer overflow (pc=%d)", pos);
    /* XXX: could avoid the division */
    short_stack_len = 1 + ((unsigned)stack_len % 255);
    if (explore_tab[pos] != 0) {
        /* already explored: check that the stack size is consistent */
        if (explore_tab[pos] != short_stack_len) {
            js_parse_error(s, "inconsistent stack size: %d %d (pc=%d)", explore_tab[pos] - 1, short_stack_len - 1, (int)pos);
        }
    } else {
        explore_tab[pos] = short_stack_len;
        /* may initiate a GC */
        PARSE_PUSH_INT(s, pos);
        PARSE_PUSH_INT(s, stack_len);
    }
}

void compute_stack_size(JSParseState *s, JSValue *pfunc)
{
    JSContext *ctx = s->ctx;
    JSByteArray *explore_arr, *arr;
    JSFunctionBytecode *b;
    uint8_t *explore_tab;
    JSValue *stack_top, explore_arr_val;
    uint32_t pos;
    int op, op_len, pos1, n_pop, stack_len;
    const JSOpCode *oi;
    JSGCRef explore_arr_val_ref;
    
    b = JS_VALUE_TO_PTR(*pfunc);
    arr = JS_VALUE_TO_PTR(b->byte_code);

    explore_arr = js_alloc_byte_array(s->ctx, arr->size);
    if (!explore_arr)
        js_parse_error_mem(s);

    b = JS_VALUE_TO_PTR(*pfunc);
    arr = JS_VALUE_TO_PTR(b->byte_code);

    explore_arr_val = JS_VALUE_FROM_PTR(explore_arr);
    explore_tab = explore_arr->buf;
    memset(explore_tab, 0, arr->size);

    JS_PUSH_VALUE(ctx, explore_arr_val);

    stack_top = ctx->sp;

    compute_stack_size_push(s, arr, explore_tab, 0, 0);

    while (ctx->sp < stack_top) {
        PARSE_POP_INT(s, stack_len);
        PARSE_POP_INT(s, pos);
        
        /* compute_stack_size_push may have initiated a GC */
        b = JS_VALUE_TO_PTR(*pfunc);
        arr = JS_VALUE_TO_PTR(b->byte_code);
        explore_arr = JS_VALUE_TO_PTR(explore_arr_val_ref.val);
        explore_tab = explore_arr->buf;
        
        op = arr->buf[pos++];
        if (op == OP_invalid || op >= OP_COUNT)
            js_parse_error(s, "invalid opcode (pc=%d)", (int)(pos - 1));
        oi = &opcode_info[op];
        op_len = oi->size;
        if ((pos + op_len - 1) > arr->size) {
            js_parse_error(s, "bytecode buffer overflow (pc=%d)", (int)(pos - 1));
        }
        n_pop = oi->n_pop;
        if (oi->fmt == OP_FMT_npop)
            n_pop += get_u16(arr->buf + pos);

        if (stack_len < n_pop) {
            js_parse_error(s, "stack underflow (pc=%d)", (int)(pos - 1));
        }
        stack_len += oi->n_push - n_pop;
        if (stack_len > b->stack_size) {
            if (stack_len > JS_MAX_FUNC_STACK_SIZE)
                js_parse_error(s, "stack overflow (pc=%d)", (int)(pos - 1));
            b->stack_size = stack_len;
        }
        switch(op) {
        case OP_return:
        case OP_return_undef:
        case OP_throw:
        case OP_ret:
            goto done; /* no code after */
        case OP_goto:
            pos += get_u32(arr->buf + pos);
            break;
        case OP_if_true:
        case OP_if_false:
            pos1 = pos + get_u32(arr->buf + pos);
            compute_stack_size_push(s, arr, explore_tab, pos1, stack_len);
            pos += op_len - 1;
            break;
        case OP_gosub:
            pos1 = pos + get_u32(arr->buf + pos);
            compute_stack_size_push(s, arr, explore_tab, pos1, stack_len + 1);
            pos += op_len - 1;
            break;
        default:
            pos += op_len - 1;
            break;
        }
        compute_stack_size_push(s, arr, explore_tab, pos, stack_len);
    done: ;
    }

    JS_POP_VALUE(ctx, explore_arr_val);
    explore_arr = JS_VALUE_TO_PTR(explore_arr_val);
    js_free(s->ctx, explore_arr);
}

void resolve_var_refs(JSParseState *s, JSValue *pfunc, JSValue *pparent_func)
{
    JSContext *ctx = s->ctx;
    int i, decl, var_idx, arg_count, ext_vars_len;
    JSValueArray *ext_vars;
    JSValue var_name;
    JSFunctionBytecode *b1, *b;

    b = JS_VALUE_TO_PTR(*pfunc);
    if (b->ext_vars_len == 0)
        return;
    b1 = JS_VALUE_TO_PTR(*pparent_func);
    arg_count = b1->arg_count;
    
    ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
    ext_vars_len = b->ext_vars_len;
    
    for(i = 0; i < ext_vars_len; i++) {
        b = JS_VALUE_TO_PTR(*pfunc);
        ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
        var_name = ext_vars->arr[2 * i];
        var_idx = find_func_var(ctx, *pparent_func, var_name);
        if (var_idx >= 0) {
            if (var_idx < arg_count) {
                decl = (JS_VARREF_KIND_ARG << 16) | var_idx;
            } else {
                decl = (JS_VARREF_KIND_VAR << 16) | (var_idx - arg_count);
            }
        } else {
            var_idx = find_func_ext_var(s, *pparent_func, var_name);
            if (var_idx < 0) {
                /* the global type may be patched later */
                var_idx = add_func_ext_var(s, *pparent_func, var_name,
                                           (JS_VARREF_KIND_GLOBAL << 16));
            }
            decl = (JS_VARREF_KIND_VAR_REF << 16) | var_idx;
        }
        b = JS_VALUE_TO_PTR(*pfunc);
        ext_vars = JS_VALUE_TO_PTR(b->ext_vars);
        ext_vars->arr[2 * i + 1] = JS_NewShortInt(decl);
    }
}

void reset_parse_state(JSParseState *s, uint32_t input_pos, JSValue cur_func)
{
    s->buf_pos = input_pos;
    s->token.val = ' ';

    s->cur_func = cur_func;
    s->byte_code = JS_NULL;
    s->byte_code_len = 0;
    s->last_opcode_pos = -1;

    s->pc2line_bit_len = 0;
    s->pc2line_source_pos = 0;
    
    s->cpool_len = 0;
    s->hoisted_code_len = 0;
    
    s->local_vars_len = 0;

    s->eval_ret_idx = -1;
}

void js_parse_local_functions(JSParseState *s, JSValue *pfunc)
{
    JSContext *ctx = s->ctx;
    JSValue *pparent_func;
    JSValueArray *cpool;
    int err, cpool_pos;
    JSValue func;
    JSFunctionBytecode *b, *b1;
    JSGCRef func_ref;
    JSValue *stack_top;
    
    err = JS_StackCheck(ctx, 3);
    if (err)
        js_parse_error_stack_overflow(s);
    stack_top = ctx->sp;
    
    *--ctx->sp = JS_NULL; /* parent_func */
    *--ctx->sp = *pfunc; /* func */
    *--ctx->sp = JS_NewShortInt(0); /* cpool_pos */

    while (ctx->sp < stack_top) {
        pparent_func = &ctx->sp[2];
        pfunc = &ctx->sp[1];
        cpool_pos = JS_VALUE_GET_INT(ctx->sp[0]);
#if 0
        JS_DumpValue(ctx, "func", *pfunc);
        JS_DumpValue(ctx, "parent", *pparent_func);
        JS_DumpValue(ctx, "cpool_pos", ctx->sp[0]);
#endif
        if (cpool_pos == 0) {
            b = JS_VALUE_TO_PTR(*pfunc);
            
            convert_ext_vars_to_local_vars(s);
            
            js_shrink_byte_array(ctx, &b->byte_code, s->byte_code_len);
            js_shrink_value_array(ctx, &b->cpool, s->cpool_len);
            js_shrink_value_array(ctx, &b->vars, s->local_vars_len);
            js_shrink_byte_array(ctx, &b->pc2line, (s->pc2line_bit_len + 7) / 8);
            
            compute_stack_size(s, pfunc);
        }

        b = JS_VALUE_TO_PTR(*pfunc);
        if (b->cpool != JS_NULL) {
            int cpool_size;
            cpool = JS_VALUE_TO_PTR(b->cpool);
            cpool_size = cpool->size;
            for(; cpool_pos < cpool_size; cpool_pos++) {
                b = JS_VALUE_TO_PTR(*pfunc);
                cpool = JS_VALUE_TO_PTR(b->cpool);
                func = cpool->arr[cpool_pos];
                if (!JS_IsPtr(func))
                    continue;
                b1 = JS_VALUE_TO_PTR(func);
                if (b1->mtag != JS_MTAG_FUNCTION_BYTECODE)
                    continue;
                
                reset_parse_state(s, b1->source_pos, func);
                
                s->is_eval = FALSE;
                s->is_repl = FALSE;
                s->has_retval = FALSE;
                
                JS_PUSH_VALUE(ctx, func);
                js_parse_function(s);
                
                /* parse a local function */
                err = JS_StackCheck(ctx, 3);
                JS_POP_VALUE(ctx, func);
                if (err)
                    js_parse_error_stack_overflow(s);
                /* set the next cpool position */
                *ctx->sp = JS_NewShortInt(cpool_pos + 1); 

                *--ctx->sp = *pfunc; /* parent_func */
                *--ctx->sp = func; /* func */
                *--ctx->sp = JS_NewShortInt(0); /* cpool_pos */
                goto next;
            }
        }
        
        if (*pparent_func != JS_NULL) {
            resolve_var_refs(s, pfunc, pparent_func);
        }
        /* now we can shrink the external vars */
        b = JS_VALUE_TO_PTR(*pfunc);
        js_shrink_value_array(ctx, &b->ext_vars, 2 * b->ext_vars_len);
#ifdef DUMP_FUNC_BYTECODE
        dump_byte_code(ctx, b);
#endif
        /* remove the stack entry */
        ctx->sp += 3;
        ctx->stack_bottom = ctx->sp;
    next: ;
    }
}

/* return the parsed value in s->token.value */
/* XXX: use exact JSON white space definition */
int js_parse_json_value(JSParseState *s, int state, int dummy_param)
{
    JSContext *ctx = s->ctx;
    const uint8_t *p;
    JSValue val;

    PARSE_START2();
    
    p = s->source_buf + s->buf_pos;
    p += skip_spaces((const char *)p);
    s->buf_pos = p - s->source_buf;
    if ((*p >= '0' && *p <= '9') || *p == '-') {
        double d;
        JSByteArray *tmp_arr;
        tmp_arr = js_alloc_byte_array(s->ctx, sizeof(JSATODTempMem));
        if (!tmp_arr)
            js_parse_error_mem(s);
        p = s->source_buf + s->buf_pos;
        d = js_atod((const char *)p, (const char **)&p, 10, 0,
                    (JSATODTempMem *)tmp_arr->buf);
        js_free(s->ctx, tmp_arr);
        if (isnan(d))
            js_parse_error(s, "invalid number literal");
        val = JS_NewFloat64(s->ctx, d);
    } else if (*p == 't' &&
               p[1] == 'r' && p[2] == 'u' && p[3] == 'e') {
        p += 4;
        val = JS_TRUE;
    } else if (*p == 'f' &&
               p[1] == 'a' && p[2] == 'l' && p[3] == 's' && p[4] == 'e') {
        p += 5;
        val = JS_FALSE;
    } else if (*p == 'n' &&
               p[1] == 'u' && p[2] == 'l' && p[3] == 'l') {
        p += 4;
        val = JS_NULL;
    } else if (*p == '\"') {
        uint32_t pos;
        pos = p + 1 - s->source_buf;
        val = js_parse_string(s, &pos, '\"');
        p = s->source_buf + pos;
    } else if (*p == '[') {
        JSValue val2;
        uint32_t idx;
        
        val = JS_NewArray(ctx, 0);
        if (JS_IsException(val))
            js_parse_error_mem(s);
        PARSE_PUSH_VAL(s, val); /* 'val' is not usable after this call */
        p = s->source_buf + s->buf_pos + 1;
        p += skip_spaces((const char *)p);
        if (*p != ']') {
            idx = 0;
            for(;;) {
                s->buf_pos = p - s->source_buf;
                PARSE_PUSH_INT(s, idx);
                PARSE_CALL(s, 0, js_parse_json_value, 0);
                PARSE_POP_INT(s, idx);
                val2 = s->token.value;
                val2 = JS_SetPropertyUint32(ctx, *ctx->sp, idx, val2);
                if (JS_IsException(val2))
                    js_parse_error_mem(s);
                idx++;
                p = s->source_buf + s->buf_pos;
                p += skip_spaces((const char *)p);
                if (*p != ',')
                    break;
                p++;
            }
        }
        if (*p != ']')
            js_parse_error(s, "expecting ']'");
        p++;
        PARSE_POP_VAL(s, val);
    } else if (*p == '{') {
        JSValue val2, prop;
        uint32_t pos;
        
        val = JS_NewObject(ctx);
        if (JS_IsException(val))
            js_parse_error_mem(s);
        PARSE_PUSH_VAL(s, val); /* 'val' is not usable after this call */
        p = s->source_buf + s->buf_pos + 1;
        p += skip_spaces((const char *)p);
        if (*p != '}') {
            for(;;) {
                p += skip_spaces((const char *)p);
                s->buf_pos = p - s->source_buf;
                if (*p != '\"')
                    js_parse_error(s, "expecting '\"'");
                pos = p + 1 - s->source_buf;
                prop = js_parse_string(s, &pos, '\"');
                prop = JS_ToPropertyKey(ctx, prop);
                if (JS_IsException(prop))
                    js_parse_error_mem(s);
                p = s->source_buf + pos;
                p += skip_spaces((const char *)p);
                if (*p != ':')
                    js_parse_error(s, "expecting ':'");
                p++;
                s->buf_pos = p - s->source_buf;
                PARSE_PUSH_VAL(s, prop);
                PARSE_CALL(s, 1, js_parse_json_value, 0);
                val2 = s->token.value;
                PARSE_POP_VAL(s, prop);
                val2 = JS_DefinePropertyValue(ctx, *ctx->sp, prop, val2);
                if (JS_IsException(val2))
                    js_parse_error_mem(s);
                p = s->source_buf + s->buf_pos;
                p += skip_spaces((const char *)p);
                if (*p != ',')
                    break;
                p++;
            }
        }
        if (*p != '}')
            js_parse_error(s, "expecting '}'");
        p++;
        PARSE_POP_VAL(s, val);
    } else {
        js_parse_error(s, "unexpected character");
    }
    s->buf_pos = p - s->source_buf;
    s->token.value = val;
    return PARSE_STATE_RET;
}

JSValue js_parse_json(JSParseState *s)
{
    s->buf_pos = 0;
    js_parse_call(s, PARSE_FUNC_js_parse_json_value, 0);
    s->buf_pos += skip_spaces((const char *)(s->source_buf + s->buf_pos));
    if (s->buf_pos != s->buf_len) {
        js_parse_error(s, "unexpected character");
    }
    return s->token.value;
}

/* source_str must be a string or JS_NULL. (input, input_len) is
   meaningful only if source_str is JS_NULL. */
JSValue JS_Parse2(JSContext *ctx, JSValue source_str, const char *input, size_t input_len, const char *filename, int eval_flags)
{
    JSParseState parse_state, *s;
    JSFunctionBytecode *b;
    JSValue top_func, *saved_sp;
    JSGCRef top_func_ref, *saved_top_gc_ref;
    uint8_t str_buf[5];
    
    /* XXX: start gc at the start of parsing ? */
    /* XXX: if the parse state is too large, move it to JSContext */
    s = &parse_state;
    memset(s, 0, sizeof(*s));
    
    s->ctx = ctx;
    ctx->parse_state = s;
    s->source_str = JS_NULL;
    s->filename_str = JS_NULL;
    s->has_column = ((eval_flags & JS_EVAL_STRIP_COL) == 0);

    if (JS_IsPtr(source_str)) {
        JSString *p = JS_VALUE_TO_PTR(source_str);
        s->source_str = source_str;
        s->buf_len = p->len;
        s->source_buf = p->buf;
    } else if (JS_VALUE_GET_SPECIAL_TAG(source_str) == JS_TAG_STRING_CHAR) {
        s->buf_len = get_short_string(str_buf, source_str);
        s->source_buf = str_buf;
    } else {
        s->buf_len = input_len;
        s->source_buf = (const uint8_t *)input;
    }
    s->top_break = JS_NULL;
    saved_top_gc_ref = ctx->top_gc_ref;
    saved_sp = ctx->sp;
    
    if (setjmp(s->jmp_env)) {
        int line_num, col_num;
        JSValue val;

        ctx->parse_state = NULL;
        ctx->top_gc_ref = saved_top_gc_ref;
        ctx->sp = saved_sp;
        ctx->stack_bottom = ctx->sp;
        
        line_num = get_line_col(&col_num, s->source_buf,
                                (eval_flags & (JS_EVAL_JSON | JS_EVAL_REGEXP)) ?
                                s->buf_pos : s->token.source_pos);
        val = JS_ThrowError(ctx, JS_CLASS_SYNTAX_ERROR, "%s", s->error_msg);
        build_backtrace(ctx, ctx->current_exception, filename, line_num + 1, col_num + 1, 0);
        return val;
    }

    if (eval_flags & JS_EVAL_JSON) {
        top_func = js_parse_json(s);
    } else if (eval_flags & JS_EVAL_REGEXP) {
        top_func = js_parse_regexp(s, eval_flags >> JS_EVAL_REGEXP_FLAGS_SHIFT);
    } else {
        s->filename_str = JS_NewString(ctx, filename);
        if (JS_IsException(s->filename_str))
            js_parse_error_mem(s);
        
        b = js_alloc_function_bytecode(ctx);
        if (!b)
            js_parse_error_mem(s);
        b->filename = s->filename_str;
        b->func_name = js_get_atom(ctx, JS_ATOM__eval_);
        b->has_column = s->has_column;
        top_func = JS_VALUE_FROM_PTR(b);
        
        reset_parse_state(s, 0, top_func);
        
        s->is_eval = TRUE;
        s->has_retval = ((eval_flags & JS_EVAL_RETVAL) != 0);
        s->is_repl = ((eval_flags & JS_EVAL_REPL) != 0);
        
        JS_PUSH_VALUE(ctx, top_func);
        
        js_parse_program(s);
        
        js_parse_local_functions(s, &top_func_ref.val);
        
        JS_POP_VALUE(ctx, top_func);
    }
    ctx->parse_state = NULL;
    return top_func;
}

/* warning: it is assumed that input[input_len] = '\0' */
JSValue JS_Parse(JSContext *ctx, const char *input, size_t input_len,
                 const char *filename, int eval_flags)
{
    return JS_Parse2(ctx, JS_NULL, input, input_len, filename, eval_flags);
}

JSValue JS_Run(JSContext *ctx, JSValue val)
{
    JSFunctionBytecode *b;
    JSGCRef val_ref;
    int err;
    
    if (!JS_IsPtr(val))
        goto fail;
    b = JS_VALUE_TO_PTR(val);
    if (b->mtag != JS_MTAG_FUNCTION_BYTECODE) {
    fail:
        return JS_ThrowTypeError(ctx, "bytecode function expected");
    }

    val = js_closure(ctx, val, NULL);
    if (JS_IsException(val))
        return val;
    JS_PUSH_VALUE(ctx, val);
    err = JS_StackCheck(ctx, 2);
    JS_POP_VALUE(ctx, val);
    if (err)
        return JS_EXCEPTION;
    JS_PushArg(ctx, val);
    JS_PushArg(ctx, JS_NULL);
    val = JS_Call(ctx, 0);
    return val;
}

/* warning: it is assumed that input[input_len] = '\0' */
JSValue JS_Eval(JSContext *ctx, const char *input, size_t input_len,
                const char *filename, int eval_flags)
{
    JSValue val;
    val = JS_Parse(ctx, input, input_len, filename, eval_flags);
    if (JS_IsException(val))
        return val;
    return JS_Run(ctx, val);
}
