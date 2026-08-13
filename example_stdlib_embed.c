/*
 * Embeds the generated example stdlib tables (compiled as C, not @cImport).
 */
#include <stddef.h>
#include "mquickjs.h"

#define JS_CLASS_RECTANGLE (JS_CLASS_USER + 0)
#define JS_CLASS_FILLED_RECTANGLE (JS_CLASS_USER + 1)
#define JS_CLASS_COUNT (JS_CLASS_USER + 2)
#define JS_CFUNCTION_rectangle_closure_test (JS_CFUNCTION_USER + 0)

#include "example_host_decls.h"
#include "example_stdlib.h"
