/*
 * Variadic C shim for js_parse_error (Zig lexer port).
 */
#include <stddef.h>
#include <stdarg.h>
#include <setjmp.h>
#include "cutils.h"
#include "mquickjs_internal.h"

void js_parse_error(JSParseState *s, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    js_vsnprintf(s->error_msg, sizeof(s->error_msg), fmt, ap);
    va_end(ap);
    longjmp(s->jmp_env, 1);
}
