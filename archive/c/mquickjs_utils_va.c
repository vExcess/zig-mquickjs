#include <stdarg.h>
#include <stddef.h>
#include "cutils.h"
#include "mquickjs.h"

typedef void JSWriteFunc(void *opaque, const void *buf, size_t buf_len);

void mqjs_vprintf(JSWriteFunc *write_func, void *opaque, const char *fmt, va_list ap);
int mqjs_vsnprintf(char *buf, size_t buf_size, const char *fmt, va_list ap);

void js_vprintf(JSWriteFunc *write_func, void *opaque, const char *fmt, va_list ap)
{
    mqjs_vprintf(write_func, opaque, fmt, ap);
}

int js_vsnprintf(char *buf, size_t buf_size, const char *fmt, va_list ap)
{
    return mqjs_vsnprintf(buf, buf_size, fmt, ap);
}

int js_snprintf(char *buf, size_t buf_size, const char *fmt, ...)
{
    va_list ap;
    int ret;
    va_start(ap, fmt);
    ret = mqjs_vsnprintf(buf, buf_size, fmt, ap);
    va_end(ap);
    return ret;
}
