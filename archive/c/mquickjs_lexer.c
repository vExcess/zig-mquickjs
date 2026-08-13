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
int get_line_col(int *pcol_num, const uint8_t *buf, size_t len)
{
    int line_num, col_num, c;
    size_t i;
    
    line_num = 0;
    col_num = 0;
    for(i = 0; i < len; i++) {
        c = buf[i];
        if (c == '\n') {
            line_num++;
            col_num = 0;
        } else if (c < 0x80 || c >= 0xc0) {
            col_num++;
        }
    }
    *pcol_num = col_num;
    return line_num;
}

void __attribute__((format(printf, 2, 3), noreturn)) js_parse_error(JSParseState *s, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    js_vsnprintf(s->error_msg, sizeof(s->error_msg), fmt, ap);
    va_end(ap);
    longjmp(s->jmp_env, 1);
}

void js_parse_error_mem(JSParseState *s)
{
    return js_parse_error(s, "not enough memory");
}

void js_parse_error_stack_overflow(JSParseState *s)
{
    return js_parse_error(s, "stack overflow");
}

void js_parse_expect1(JSParseState *s, int ch)
{
    if (s->token.val != ch)
        js_parse_error(s, "expecting '%c'", ch);
}

void js_parse_expect(JSParseState *s, int ch)
{
    js_parse_expect1(s, ch);
    next_token(s);
}

void js_parse_expect_semi(JSParseState *s)
{
    if (s->token.val != ';') {
        /* automatic insertion of ';' */
        if (s->token.val == TOK_EOF || s->token.val == '}' || s->got_lf) {
            return;
        }
        js_parse_error(s, "expecting '%c'", ';');
    }
    next_token(s);
}

#define SKIP_HAS_ARGUMENTS     (1 << 0)
#define SKIP_HAS_FUNC_NAME     (1 << 1)
#define SKIP_HAS_SEMI          (1 << 2) /* semicolon found inside the first level */

/* Skip parenthesis or blocks. The current token should be '(', '[' or
   '{'. 'func_name' can be JS_NULL. */
int js_skip_parens(JSParseState *s, JSValue *pfunc_name)
{
    uint8_t state[128];
    int level, c, bits = 0;
    
    /* protect from underflow */
    level = 0;
    state[level++] = 0;
    for (;;) {
        switch(s->token.val) {
        case '(':
            c = ')';
            goto add_level;
        case '[':
            c = ']';
            goto add_level;
        case '{':
            c = '}';
        add_level:
            if (level >= sizeof(state)) {
                js_parse_error(s, "too many nested blocks");
            }
            state[level++] = c;
            break;
        case ')':
        case ']':
        case '}':
            c = state[--level];
            if (s->token.val != c)
                js_parse_error(s, "expecting '%c'", c);
            break;
        case TOK_EOF:
            js_parse_error(s, "expecting '%c'", state[level - 1]);
        case TOK_IDENT:
            if (s->token.value == js_get_atom(s->ctx, JS_ATOM_arguments))
                bits |= SKIP_HAS_ARGUMENTS;
            if (pfunc_name && s->token.value == *pfunc_name)
                bits |= SKIP_HAS_FUNC_NAME;
            break;
        case ';':
            if (level == 2)
                bits |= SKIP_HAS_SEMI;
            break;
        }
        next_token(s);
        if (level <= 1)
            break;
    }
    return bits;
}

/* skip an expression until ')' */
void js_skip_expr(JSParseState *s)
{
    for(;;) {
        switch(s->token.val) {
        case ')':
            return;
        case ';':
        case TOK_EOF:
            js_parse_error(s, "expecting '%c'", ')');
        case '(':
        case '[':
        case '{':
            js_skip_parens(s, NULL);
            break;
        default:
            next_token(s);
            break;
        }
    }
}


/* return TRUE if a regexp literal is allowed after this token */
BOOL is_regexp_allowed(int tok)
{
    switch (tok) {
    case TOK_NUMBER:
    case TOK_STRING:
    case TOK_REGEXP:
    case TOK_DEC:
    case TOK_INC:
    case TOK_NULL:
    case TOK_FALSE:
    case TOK_TRUE:
    case TOK_THIS:
    case TOK_IF:
    case TOK_WHILE:
    case TOK_FOR:
    case TOK_DO:
    case TOK_CASE:
    case TOK_CATCH:
    case ')':
    case ']':
    case TOK_IDENT:
        return FALSE;
    default:
        return TRUE;
    }
}

void js_parse_get_pos(JSParseState *s, JSParsePos *sp)
{
    sp->source_pos = s->token.source_pos;
    sp->got_lf = s->got_lf;
    sp->regexp_allowed = is_regexp_allowed(s->token.val);
}

void js_parse_seek_token(JSParseState *s, const JSParsePos *sp)
{
    s->buf_pos = sp->source_pos;
    s->got_lf = sp->got_lf;
    /* the previous token value is only needed so that
       is_regexp_allowed() returns the correct value */
    s->token.val = sp->regexp_allowed ? ' ' : ')';
    next_token(s);
}

/* same as js_skip_parens but go back to the current token */
int js_parse_skip_parens_token(JSParseState *s)
{
    JSParsePos pos;
    int bits;
    
    js_parse_get_pos(s, &pos);
    bits = js_skip_parens(s, NULL);
    js_parse_seek_token(s, &pos);
    return bits;
}

/* return the escape value or -1 */
int js_parse_escape(const uint8_t *buf, size_t *plen)
{
    int c;
    const uint8_t *p = buf;
    c = *p++;
    switch(c) {
    case 'b':
        c = '\b';
        break;
    case 'f':
        c = '\f';
        break;
    case 'n':
        c = '\n';
        break;
    case 'r':
        c = '\r';
        break;
    case 't':
        c = '\t';
        break;
    case 'v':
        c = '\v';
        break;
    case '\'':
    case '\"':
    case '\\':
        break;
    case 'x':
        {
            int h0, h1;

            h0 = from_hex(*p++);
            if (h0 < 0)
                return -1;
            h1 = from_hex(*p++);
            if (h1 < 0)
                return -1;
            c = (h0 << 4) | h1;
        }
        break;
    case 'u':
        {
            int h, i;
            
            if (*p == '{') {
                p++;
                c = 0;
                for(;;) {
                    h = from_hex(*p++);
                    if (h < 0)
                        return -1;
                    c = (c << 4) | h;
                    if (c > 0x10FFFF)
                        return -1;
                    if (*p == '}')
                        break;
                }
                p++;
            } else {
                c = 0;
                for(i = 0; i < 4; i++) {
                    h = from_hex(*p++);
                    if (h < 0) {
                        return -1;
                    }
                    c = (c << 4) | h;
                }
            }
        }
        break;
    case '0':
        c -= '0';
        if (c != 0 || is_num(*p))
            return -1;
        break;
    default:
        return -2;
    }
    *plen = p - buf;
    return c;
}

JSValue js_parse_string(JSParseState *s, uint32_t *ppos, int sep)
{
    JSContext *ctx = s->ctx;
    JSValue res;
    const uint8_t *buf;
    uint32_t pos;
    uint32_t c;
    size_t escape_len = 0; /* avoid warning */
    StringBuffer b_s, *b = &b_s;
    
    if (string_buffer_push(ctx, b, 16))
        js_parse_error_mem(s);
    buf = s->source_buf;
    /* string */
    pos = *ppos;
    for(;;) {
        c = buf[pos];
        if (c == '\0' || c == '\n' || c == '\r') {
            js_parse_error(s, "unexpected end of string");
        }
        pos++;
        if (c == sep)
            break;
        if (c == '\\') {
            if (buf[pos] == '\n') {
                /* ignore escaped newline sequence */
                pos++;
                continue;
            }
            c = js_parse_escape(buf + pos, &escape_len);
            if (c == -1) {
                js_parse_error(s, "invalid escape sequence");
            } else if (c == -2) {
                /* ignore invalid escapes */
                continue;
            }
            pos += escape_len;
        } else if (c >= 0x80) {
            size_t clen;
            pos--;
            c = unicode_from_utf8(buf + pos, UTF8_CHAR_LEN_MAX, &clen);
            pos += clen;
            if (c == -1) {
                js_parse_error(s, "invalid UTF-8 sequence");
            }
        }
        if (string_buffer_putc(ctx, b, c))
            break;
        buf = s->source_buf; /* may be reallocated */
    }
    *ppos = pos;
    res = string_buffer_pop(ctx, b);
    if (JS_IsException(res))
        js_parse_error_mem(s);
    return res;
}

void js_parse_ident(JSParseState *s, JSToken *token, uint32_t *ppos, int c)
{
    JSContext *ctx = s->ctx;
    uint32_t pos;
    JSValue val, val2;
    JSGCRef val2_ref;
    const uint8_t *buf;
    StringBuffer b_s, *b = &b_s;
    
    if (string_buffer_push(ctx, b, 16))
        js_parse_error_mem(s);
    string_buffer_putc(ctx, b, c); /* no allocation */
    buf = s->source_buf;
    pos = *ppos;
    while (pos < s->buf_len) {
        c = buf[pos];
        if (!is_ident_next(c))
            break;
        pos++;
        if (string_buffer_putc(ctx, b, c))
            break;
        buf = s->source_buf; /* may be reallocated */
    }
    /* convert to token if necessary */
    token->val = TOK_IDENT;
    val2 = string_buffer_pop(ctx, b);
    JS_PUSH_VALUE(ctx, val2);
    val = JS_MakeUniqueString(ctx, val2);
    JS_POP_VALUE(ctx, val2);
    if (JS_IsException(val))
        js_parse_error_mem(s);
    if (val != val2)
        js_free(ctx, JS_VALUE_TO_PTR(val2));
    token->value = val;
    if (JS_IsPtr(val)) {
        const JSWord *atom_start, *atom_last, *ptr;
        atom_start = ctx->atom_table;
        atom_last = atom_start + JS_ATOM_yield;
        ptr = JS_VALUE_TO_PTR(val);
        if (ptr >= atom_start && ptr <= atom_last) {
            token->val = TOK_NULL + (ptr - atom_start);
        }
    }
    *ppos = pos;
}

void js_parse_regexp_token(JSParseState *s, uint32_t *ppos)
{
    JSContext *ctx = s->ctx;
    uint32_t pos;
    uint32_t c;
    BOOL in_class;
    size_t clen;
    int re_flags, end_pos, start_pos;
    JSString *p;
    
    in_class = FALSE;
    pos = *ppos;
    start_pos = pos;
    for(;;) {
        c = unicode_from_utf8(s->source_buf + pos, UTF8_CHAR_LEN_MAX, &clen);
        if (c == -1) 
            js_parse_error(s, "invalid UTF-8 sequence");
        pos += clen;
        if (c == '\0' || c == '\n' || c == '\r') {
            goto invalid_char;
        } else if (c == '/') {
            if (!in_class)
                break;
        } else if (c == '[') {
            in_class = TRUE;
        } else if (c == ']') {
            in_class = FALSE;
        } else if (c == '\\') {
            c = unicode_from_utf8(s->source_buf + pos, UTF8_CHAR_LEN_MAX, &clen);
            if (c == -1) 
                js_parse_error(s, "invalid UTF-8 sequence");
            if (c == '\0' || c == '\n' || c == '\r') {
            invalid_char:
                js_parse_error(s, "unexpected line terminator in regexp");
            }
            pos += clen;
        }
    }
    end_pos = pos - 1;
    
    clen = js_parse_regexp_flags(&re_flags, s->source_buf + pos);
    pos += clen;
    if (is_ident_next(s->source_buf[pos]))
        js_parse_error(s, "invalid regular expression flags");

    /* XXX: single char string is not optimized */
    p = js_alloc_string(ctx, end_pos - start_pos);
    if (!p)
        js_parse_error_mem(s);
    p->is_ascii = is_ascii_string((char *)(s->source_buf + start_pos), end_pos - start_pos);
    memcpy(p->buf, s->source_buf + start_pos, end_pos - start_pos);
    
    *ppos = pos;
    s->token.val = TOK_REGEXP;
    s->token.value = JS_VALUE_FROM_PTR(p);
    s->token.u.regexp.re_flags = re_flags;
    s->token.u.regexp.re_end_pos = end_pos;
}

void next_token(JSParseState *s)
{
    uint32_t pos;
    const uint8_t *p;
    int c;
    
    pos = s->buf_pos;
    s->got_lf = FALSE;
    s->token.value = JS_NULL;
    p = s->source_buf + s->buf_pos;
 redo:
    s->token.source_pos = p - s->source_buf;
    c = *p;
    switch(c) {
    case 0:
        s->token.val = TOK_EOF;
        break;
    case '\"':
    case '\'':
        p++;
        pos = p - s->source_buf;
        s->token.value = js_parse_string(s, &pos, c);
        s->token.val = TOK_STRING;
        p = s->source_buf + pos;
        break;
    case '\n':
        s->got_lf = TRUE;
        p++;
        goto redo;
    case ' ':
    case '\t':
    case '\f':
    case '\v':
    case '\r':
        p++;
        goto redo;
    case '/':
        if (p[1] == '*') {
            /* comment */
            p += 2;
            for(;;) {
                if (*p == '\0')
                    js_parse_error(s, "unexpected end of comment");
                if (p[0] == '*' && p[1] == '/') {
                    p += 2;
                    break;
                }
                p++;
            }
            goto redo;
        } else if (p[1] == '/') {
            /* line comment */
            p += 2;
            for(;;) {
                if (*p == '\0' || *p == '\n')
                    break;
                p++;
            }
            goto redo;
        } else if (is_regexp_allowed(s->token.val)) {
            /* Note: we recognize regexps in the lexer. It does not
               handle all the cases e.g. "({x:1} / 2)" or "a.void / 2" but
               is consistent when we tokenize the input without
               parsing it. */
            p++;
            pos = p - s->source_buf;
            js_parse_regexp_token(s, &pos);
            p = s->source_buf + pos;
        } else if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_DIV_ASSIGN;
        } else {
            p++;
            s->token.val = c;
        }
        break;
    case 'a' ... 'z':
    case 'A' ... 'Z': 
    case '_': 
    case '$':
        p++;
        pos = p - s->source_buf;
        js_parse_ident(s, &s->token, &pos, c);
        p = s->source_buf + pos;
        break;
    case '.':
        if (is_digit(p[1]))
            goto parse_number;
        else
            goto def_token;
    case '0':
        /* in strict mode, octal literals are not accepted */
        if (is_digit(p[1]))
            goto invalid_number;
        goto parse_number;
    case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8':
    case '9':
        /* number */
        parse_number:
        {
            double d;
            JSByteArray *tmp_arr;
            pos = p - s->source_buf;
            tmp_arr = js_alloc_byte_array(s->ctx, sizeof(JSATODTempMem));
            if (!tmp_arr)
                js_parse_error_mem(s);
            p = s->source_buf + pos;
            d = js_atod((const char *)p, (const char **)&p, 0,
                        JS_ATOD_ACCEPT_BIN_OCT | JS_ATOD_ACCEPT_UNDERSCORES,
                        (JSATODTempMem *)tmp_arr->buf);
            js_free(s->ctx, tmp_arr);
            if (isnan(d)) {
            invalid_number:
                js_parse_error(s, "invalid number literal");
            }
            s->token.val = TOK_NUMBER;
            s->token.u.d = d;
        }
        break;
    case '*':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_MUL_ASSIGN;
        } else if (p[1] == '*') {
            if (p[2] == '=') {
                p += 3;
                s->token.val = TOK_POW_ASSIGN;
            } else {
                p += 2;
                s->token.val = TOK_POW;
            }
        } else {
            goto def_token;
        }
        break;
    case '%':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_MOD_ASSIGN;
        } else {
            goto def_token;
        }
        break;
    case '+':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_PLUS_ASSIGN;
        } else if (p[1] == '+') {
            p += 2;
            s->token.val = TOK_INC;
        } else {
            goto def_token;
        }
        break;
    case '-':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_MINUS_ASSIGN;
        } else if (p[1] == '-') {
            p += 2;
            s->token.val = TOK_DEC;
        } else {
            goto def_token;
        }
        break;
    case '<':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_LTE;
        } else if (p[1] == '<') {
            if (p[2] == '=') {
                p += 3;
                s->token.val = TOK_SHL_ASSIGN;
            } else {
                p += 2;
                s->token.val = TOK_SHL;
            }
        } else {
            goto def_token;
        }
        break;
    case '>':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_GTE;
        } else if (p[1] == '>') {
            if (p[2] == '>') {
                if (p[3] == '=') {
                    p += 4;
                    s->token.val = TOK_SHR_ASSIGN;
                } else {
                    p += 3;
                    s->token.val = TOK_SHR;
                }
            } else if (p[2] == '=') {
                p += 3;
                s->token.val = TOK_SAR_ASSIGN;
            } else {
                p += 2;
                s->token.val = TOK_SAR;
            }
        } else {
            goto def_token;
        }
        break;
    case '=':
        if (p[1] == '=') {
            if (p[2] == '=') {
                p += 3;
                s->token.val = TOK_STRICT_EQ;
            } else {
                p += 2;
                s->token.val = TOK_EQ;
            }
        } else {
            goto def_token;
        }
        break;
    case '!':
        if (p[1] == '=') {
            if (p[2] == '=') {
                p += 3;
                s->token.val = TOK_STRICT_NEQ;
            } else {
                p += 2;
                s->token.val = TOK_NEQ;
            }
        } else {
            goto def_token;
        }
        break;
    case '&':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_AND_ASSIGN;
        } else if (p[1] == '&') {
            p += 2;
            s->token.val = TOK_LAND;
        } else {
            goto def_token;
        }
        break;
    case '^':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_XOR_ASSIGN;
        } else {
            goto def_token;
        }
        break;
    case '|':
        if (p[1] == '=') {
            p += 2;
            s->token.val = TOK_OR_ASSIGN;
        } else if (p[1] == '|') {
            p += 2;
            s->token.val = TOK_LOR;
        } else {
            goto def_token;
        }
        break;
    default:
        if (c >= 128) {
            js_parse_error(s, "unexpected character");
        }
    def_token:
        s->token.val = c;
        p++;
        break;
    }
    s->buf_pos = p - s->source_buf;
#if defined(DUMP_TOKEN)
    dump_token(s, &s->token);
#endif
}
