/* Forward declarations for example.zig host callbacks (resolved at link time). */
#ifndef EXAMPLE_HOST_DECLS_H
#define EXAMPLE_HOST_DECLS_H

#include "mquickjs.h"

JSValue js_rectangle_constructor(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
void js_rectangle_finalizer(JSContext *ctx, void *opaque);
JSValue js_rectangle_get_x(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_rectangle_get_y(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_rectangle_closure_test(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv, JSValue params);
JSValue js_rectangle_getClosure(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_rectangle_call(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_filled_rectangle_constructor(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
void js_filled_rectangle_finalizer(JSContext *ctx, void *opaque);
JSValue js_filled_rectangle_get_color(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_print(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_date_constructor(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_date_now(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);
JSValue js_performance_now(JSContext *ctx, JSValue *this_val, int argc, JSValue *argv);

#endif
