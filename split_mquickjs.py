#!/usr/bin/env python3
"""Mechanically split mquickjs.c into 7 translation units."""
import re
import sys

SRC = "archive/mquickjs_monolith.c"
lines = open(SRC).readlines()
LICENSE = "\n".join(open(SRC).read().split("\n")[:24]) + "\n"
COMMON = """#include <stdlib.h>
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
"""

SPLIT = {
    "mquickjs_utils.c": [(436, 965), (6646, 7157)],
    "mquickjs_value.c": [(965, 3544)],
    "mquickjs_runtime.c": [(3545, 6641)],
    "mquickjs_lexer.c": [(7602, 7743), (7749, 8329)],
    "mquickjs_parser.c": [(7337, 7601), (8330, 11831)],
    "mquickjs_gc.c": [(11833, 13009)],
    "mquickjs_builtins.c": [(13011, 18366)],
}


EXCLUDE_LINES = {
    "mquickjs_utils.c": [(493, 496)],
    "mquickjs_value.c": [(1196, 1203), (1252, 1269), (2451, 2475)],
    "mquickjs_builtins.c": [(13636, 13660)],
}


def line_excluded(n, exclude_ranges):
    for a, b in exclude_ranges:
        if a <= n <= b:
            return True
    return False


def extract(ranges, exclude_ranges=None):
    parts = []
    for s, e in ranges:
        for n in range(s, e + 1):
            if exclude_ranges and line_excluded(n, exclude_ranges):
                continue
            parts.append(lines[n - 1])
    return LICENSE + COMMON + "".join(parts)


def strip_static_functions(content):
    """Remove 'static' from file-scope function definitions only."""
    out_lines = []
    ls = content.splitlines(keepends=True)
    i = 0
    while i < len(ls):
        line = ls[i]
        if not line.startswith("static "):
            out_lines.append(line)
            i += 1
            continue
        rest = line[7:]
        indent = line[: len(line) - len(line.lstrip())]
        # Static data with brace initializer (arrays etc.)
        if "{" in rest and "(" not in rest.split("=")[0]:
            out_lines.append(line)
            i += 1
            continue
        # Single-line variable or forward declaration
        if rest.rstrip().endswith(";"):
            if "(" in rest:
                out_lines.append(indent + rest)
            else:
                out_lines.append(line)
            i += 1
            continue
        # Multi-line: scan until ';' (forward decl) or '{' (definition)
        parts = [rest.rstrip("\n")]
        j = i + 1
        end = None
        while j < len(ls):
            stripped = ls[j].strip()
            if stripped == "{":
                end = "brace"
                break
            parts.append(ls[j].rstrip("\n"))
            if stripped.endswith(";"):
                end = "semi"
                break
            j += 1
        sig = re.sub(r"\s+", " ", " ".join(p.strip() for p in parts if p.strip()))
        if end == "semi":
            if "(" in sig:
                out_lines.append(indent + sig + "\n")
            else:
                out_lines.append(line)
            i = j + 1
            continue
        if end == "brace" and "(" in sig:
            out_lines.append(indent + sig + "\n")
            out_lines.append(ls[j])
            i = j + 1
            continue
        out_lines.append(line)
        i += 1
    return "".join(out_lines)


def remove_duplicate_types(content):
    """Remove typedefs/enums that also live in mquickjs_internal.h."""
    patterns = [
        r"typedef struct \{\s*JSGCRef buffer_ref;.*?\} StringBuffer;\n\n",
        r"typedef struct \{\s*JSContext \*ctx;\s*JSValue \*gsp;.*?\} GCMarkState;\n\n",
        r"typedef struct \{\s*JSContext \*ctx;\s*uintptr_t offset;.*?\} BCRelocState;\n\n",
        r"typedef struct JSParsePos \{.*?\} JSParsePos;\n\n",
        r"typedef enum \{\s*JS_PARSE_FUNC_STATEMENT,.*?\} JSParseFunctionEnum;\n\n",
        r"typedef enum \{\s*PUT_LVALUE_KEEP_TOP,.*?\} PutLValueEnum;\n\n",
        r"typedef enum \{\s*PARSE_FUNC_js_parse_expr_comma,.*?\} ParseExprFuncEnum;\n\n",
        r"typedef int JSParseFunc\(JSParseState \*s, int state, int param\);\n\n",
        r"typedef struct \{\s*uint16_t new_var_idx;.*?\} ConvertVarEntry;\n\n",
    ]
    for pat in patterns:
        content = re.sub(pat, "", content, flags=re.DOTALL)
    return content


def strip_lexer_dupes(content):
    si = content.find("/**************************************************/\n/* JS parser */")
    if si < 0:
        return content
    ei = content.find("} JSParseState;\n", si)
    if ei < 0:
        return content
    ei += len("} JSParseState;\n")
    return content[:si] + "/**************************************************/\n/* JS parser */\n\n" + content[ei:]


def strip_builtins_dupes(content):
    si = content.find("/**********************************************************************/\n/* regexp */")
    if si < 0:
        return content
    ei = content.find("} CharRangeEnum;\n\n", si)
    if ei < 0:
        return content
    ei += len("} CharRangeEnum;\n\n")
    return content[:si] + "/**********************************************************************/\n/* regexp */\n\n" + content[ei:]


JS_MTAG = """
const char *js_mtag_name[JS_MTAG_COUNT] = {
    "free", "object", "float64", "string",
    "func_bytecode", "value_array", "byte_array", "varref",
};
"""

OPCODE = """
const JSOpCode opcode_info[OP_COUNT] = {
#define FMT(f)
#ifdef DUMP_BYTECODE
#define DEF(id, size, n_pop, n_push, f) { #id, size, n_pop, n_push, OP_FMT_ ## f },
#else
#define DEF(id, size, n_pop, n_push, f) { size, n_pop, n_push, OP_FMT_ ## f },
#endif
#include "mquickjs_opcode.h"
#undef DEF
#undef FMT
};
"""

REOP = """
const REOpCode reopcode_info[REOP_COUNT] = {
#ifdef DUMP_REOP
#define REDEF(id, size) { #id, size },
#else
#define REDEF(id, size) { size },
#endif
#include "mquickjs_opcode.h"
#undef REDEF
};
"""


def add_after_include(content, snippet):
    return content.replace(
        '#include "mquickjs_internal.h"\n',
        '#include "mquickjs_internal.h"\n' + snippet,
        1,
    )


# Write split .c files
for fname, ranges in SPLIT.items():
    content = extract(ranges, EXCLUDE_LINES.get(fname))
    content = strip_static_functions(content)
    content = remove_duplicate_types(content)
    if fname == "mquickjs_builtins.c":
        content = strip_builtins_dupes(content)
    open(fname, "w").write(content)
    print(f"{fname}: {len(content.splitlines())} lines")

utils_content = open("mquickjs_utils.c").read()
open("mquickjs_utils.c", "w").write(add_after_include(utils_content, JS_MTAG))
runtime_content = open("mquickjs_runtime.c").read()
open("mquickjs_runtime.c", "w").write(add_after_include(runtime_content, OPCODE))
builtins_content = open("mquickjs_builtins.c").read()
open("mquickjs_builtins.c", "w").write(
    builtins_content.replace("/* regexp */\n\n", "/* regexp */\n\n" + REOP, 1)
)

# Build internal.h
extra_types = (
    "".join(lines[7743:7748])
    + "".join(lines[8652:8657])
    + "".join(lines[8963:8969])
    + "".join(lines[9099:9115])
    + "".join(lines[11182:11186])
    + "".join(lines[11894:11901])
    + "".join(lines[12870:12875])
    + "".join(lines[9116:9118])
    + "".join(lines[9155:9277])
)
extra_macros = (
    """
#define SKIP_HAS_ARGUMENTS (1 << 0)
#define SKIP_HAS_FUNC_NAME (1 << 1)
#define SKIP_HAS_SEMI (1 << 2)
#define LRE_FLAG_GLOBAL (1 << 0)
#define LABEL_RESOLVED_FLAG (1 << 29)
#define LABEL_OFFSET_MASK ((1 << 29) - 1)
#define LABEL_NONE JS_NewShortInt(-1)
#define JS_DEF_PROP_LOOKUP  (1 << 0)
#define JS_DEF_PROP_RET_VAL (1 << 1)
#define JS_DEF_PROP_HAS_VALUE (1 << 2)
#define JS_DEF_PROP_HAS_GET   (1 << 3)
#define JS_DEF_PROP_HAS_SET   (1 << 4)
#define SP_TO_VALUE(ctx, fp) JS_NewShortInt((uint8_t *)(fp) - (uint8_t *)ctx)
#define VALUE_TO_SP(ctx, val) (void *)((uint8_t *)ctx + JS_VALUE_GET_INT(val))
"""
)
header_parts = [
    """#ifndef MQUICKJS_INTERNAL_H
#define MQUICKJS_INTERNAL_H

#include "mquickjs_priv.h"
#include "mquickjs_atom.h"

#define __exception __attribute__((warn_unused_result))

""",
    "".join(lines[59:73]),
    "".join(lines[85:374]),
    "".join(lines[390:421]),
    "#define JS_SHORTINT_MIN (-(1 << 30))\n#define JS_SHORTINT_MAX ((1 << 30) - 1)\n",
    "".join(lines[1592:1597]),
    "\n",
    "".join(lines[7162:7329]),
    extra_types,
    extra_macros,
    "".join(lines[15712:15728])
    + "".join(lines[15740:15762]),
]
inline_defs = (
    "".join(lines[492:496])
    + "".join(lines[1195:1203])
    + "".join(lines[1251:1269])
    + "".join(lines[2450:2475])
    + "".join(lines[13635:13660])
)
header_parts.append("\n/* inline helpers (included by all engine TUs) */\n")
header_parts.append(inline_defs)

protos = set()
proto_re = re.compile(
    r"^([A-Za-z_][\w\s\*]*?\s+\**[a-zA-Z_][\w]*\s*\([^)]*\))\s*\n\s*\{",
    re.MULTILINE,
)
bad_proto = re.compile(
    r"[\\{};]|^\s*(if|for|switch|while)\b|JS_(PUSH|POP)_|PARSE_|\\ if"
)
for fname in SPLIT:
    text = open(fname).read()
    for m in proto_re.finditer(text):
        sig = re.sub(r"\s+", " ", m.group(1).strip())
        sig = re.sub(r"^inline\s+", "", sig)
        sig = re.sub(r"^force_inline\s+", "", sig)
        if re.search(r"\b(force_inline|Inlined|_inlined)\b", sig):
            continue
        if re.search(r"\binline\b", sig):
            continue
        if sig.startswith("JSValue JS_NewTailCall"):
            continue
        if bad_proto.search(sig):
            continue
        n = re.search(r"([A-Za-z_][\w]*)\s*\(", sig)
        if n and n.group(1) not in ("if", "while", "for", "switch"):
            protos.add(sig + ";")
    # single-line inline functions
    for m in re.finditer(
        r"^(inline\s+[A-Za-z_][\w\s\*]*?\s+[a-zA-Z_][\w]*\s*\([^)]*\))\s*\{",
        text,
        re.MULTILINE,
    ):
        sig = re.sub(r"\s+", " ", m.group(1).strip())
        sig = re.sub(r"^inline\s+", "", sig)
        sig = re.sub(r"^force_inline\s+", "", sig)
        if re.search(r"\b(force_inline|Inlined|_inlined)\b", sig):
            continue
        if re.search(r"\binline\b", sig):
            continue
        if sig.startswith("JSValue JS_NewTailCall"):
            continue
        if bad_proto.search(sig):
            continue
        n = re.search(r"([A-Za-z_][\w]*)\s*\(", sig)
        if n and n.group(1) not in ("if", "while", "for", "switch"):
            protos.add(sig + ";")

header_parts.append("\n/* cross-module prototypes */\n")
header_parts.append("\n".join(sorted(protos)))
header_parts.append(
    """
void __js_printf_like(2, 3) js_printf(JSContext *ctx, const char *fmt, ...);
int js_vsnprintf(char *buf, size_t buf_size, const char *fmt, va_list ap);
int __maybe_unused __js_printf_like(3, 4) js_snprintf(char *buf, size_t buf_size, const char *fmt, ...);
void __attribute__((format(printf, 2, 3), noreturn)) js_parse_error(JSParseState *s, const char *fmt, ...);
void js_parse_error_stack_overflow(JSParseState *s);
void js_parse_error_mem(JSParseState *s);
BOOL label_is_none(JSValue label);
"""
)
header_parts.append(
    """

extern const char *js_mtag_name[JS_MTAG_COUNT];
extern const JSOpCode opcode_info[OP_COUNT];
extern const REOpCode reopcode_info[REOP_COUNT];

#endif /* MQUICKJS_INTERNAL_H */
"""
)

open("mquickjs_internal.h", "w").write("".join(header_parts))
print(f"mquickjs_internal.h: {len(protos)} prototypes")
