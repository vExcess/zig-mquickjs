# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-13  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`  
Last known-good: **handoff 11 (gc port)** — uncommitted (staged); parent commit **`e9f3f08` (handoff 10 — parser port)**

---

## 1. Status

### Completed

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 0** | Build hygiene | **Complete** |
| **Step 1** | Port `dtoa.c` → `dtoa.zig` / `dtoa_lib.zig` | **Complete** |
| **Step 2 Phase 2a** | Port `libm.c` → `libm.zig` / `libm_lib.zig` (hard float) | **Complete** |
| **Step 3** | Port `example.c` → `example.zig` | **Complete** |
| **Step 4** | Port `mqjs.c` → `mqjs.zig` | **Complete** |
| **Step 5** | Split `mquickjs.c` into 7 C files | **Complete** |
| **Step 6 (1/7)** | Port `mquickjs_utils.c` → Zig | **Complete** |
| **Step 6 (2/7)** | Port `mquickjs_value.c` → Zig | **Complete** |
| **Step 6 (3/7)** | Port `mquickjs_runtime.c` → Zig | **Complete** |
| **Step 6 (4/7)** | Port `mquickjs_lexer.c` → Zig | **Complete** |
| **Step 6 (5/7)** | Port `mquickjs_parser.c` → Zig | **Complete** |
| **Step 6 (6/7)** | Port `mquickjs_gc.c` → Zig | **Complete** |

### In progress / not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 6 (7/7)** | Port `mquickjs_builtins.c` → Zig | **Next** |
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Steps 7–8** | Host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C engine (1 file):
│     mquickjs_builtins.c
├── Zig engine (6 modules):
│     mquickjs_utils   — utils.zig + utils_lib.zig + utils_types.zig (+ utils_va.c shim)
│     mquickjs_value   — value.zig + value_lib.zig + value_types.zig
│     mquickjs_runtime — runtime.zig + runtime_lib.zig + runtime_types.zig
│     mquickjs_lexer   — lexer.zig + lexer_lib.zig + lexer_types.zig (+ lexer_va.c shim)
│     mquickjs_parser  — parser.zig + parser_lib.zig + parser_types.zig
│     mquickjs_gc      — gc.zig + gc_lib.zig + gc_types.zig
├── Shared engine header: mquickjs_internal.h
├── Zig objects: cutils, dtoa, libm, mquickjs_utils, mquickjs_value, mquickjs_runtime,
│                mquickjs_lexer, mquickjs_parser, mquickjs_gc, readline
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs, **mquickjs_utils**, **mquickjs_value**, **mquickjs_runtime**, **mquickjs_lexer**, **mquickjs_parser**, **mquickjs_gc**.  
**Still C:** 1 engine `.c` file (builtins) + stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`).  
**Reference only (not compiled):** `archive/mquickjs_monolith.c`, `mquickjs_utils.c`, `mquickjs_value.c`, `mquickjs_runtime.c`, `mquickjs_lexer.c`, `mquickjs_parser.c`, **`mquickjs_gc.c`**, `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

### Recommended port order (remaining)

1. **`mquickjs_builtins.c`** (~5,311 lines) ← **NEXT** — last engine module; all `js_*` builtins + regexp engine

---

## 2. Changes Made

### Step 0 — Build hygiene

| File | Change |
|------|--------|
| [`build.zig`](build.zig) | Shared helpers `addEngineCSources`, `addRuntimeObjects`, `addCommonIncludes`; explicit object linking |
| [`cutils_lib.zig`](cutils_lib.zig) | **New** — shared cutils implementation (no C exports) |
| [`cutils.zig`](cutils.zig) | **Refactored** — thin C ABI export wrappers only |
| [`readline.zig`](readline.zig), [`readline_tty.zig`](readline_tty.zig) | Import `cutils_lib.zig` instead of `cutils.zig` |
| [`src/`](src/) | **Removed** — moved to [`archive/src-first-attempt/`](archive/src-first-attempt/) |
| [`Makefile`](Makefile) | Deprecated; delegates to `zig build` |
| [`README.md`](README.md) | Port status table |

### Step 1 — dtoa port

| File | Change |
|------|--------|
| [`dtoa_lib.zig`](dtoa_lib.zig) | **New** — ~1,340 lines; faithful port of `dtoa.c` |
| [`dtoa.zig`](dtoa.zig) | **New** — C ABI exports matching [`dtoa.h`](dtoa.h) |
| [`build.zig`](build.zig) | `dtoa_obj` added; `dtoa.c` removed from build |
| [`dtoa.c`](dtoa.c) | **Kept for reference** — not compiled |

### Step 2 Phase 2a — libm port (hard float)

| File | Change |
|------|--------|
| [`libm_lib.zig`](libm_lib.zig) | **New** — ~1,188 lines; hard-float port of [`libm.c`](libm.c) |
| [`libm.zig`](libm.zig) | **New** — 22 C ABI exports matching [`libm.h`](libm.h) |
| [`libm_softfp.c`](libm_softfp.c) | **New** — auxiliary C: sf32 normalize + sf64 softfp templates |
| [`build.zig`](build.zig) | `libm_obj` with Zig root + `libm_softfp.c`; `libm.c` removed |
| [`libm.c`](libm.c) | **Kept for reference** — not compiled |

### Steps 3–4 — example / mqjs ports

See prior handoff sections; unchanged. Host apps are Zig executables linking engine objects + stdlib embed `.c`.

### Step 5 — split mquickjs.c into 7 C files

Mechanical split of monolith into 7 linkable C TUs. Regenerate with `python3 split_mquickjs.py`. Public headers untouched.

| File | ~Lines | Responsibility |
|------|--------|----------------|
| `mquickjs_utils.c` | 1,076 | GC-ref API, heap alloc, printf, debug printers |
| `mquickjs_value.c` | 2,542 | JSValue, strings, objects, properties, atoms |
| `mquickjs_runtime.c` | 3,135 | Context, coercion, operators, closures, **`JS_Call`** |
| `mquickjs_lexer.c` | 758 | Token enum, `next_token`, parse error helpers |
| `mquickjs_parser.c` | 3,740 | Bytecode emit, parser, `JS_Parse`/`JS_Run`/`JS_Eval` |
| `mquickjs_gc.c` | 1,198 | Mark/compact GC, `JS_GC`, bytecode load |
| `mquickjs_builtins.c` | 5,311 | All `js_*` builtins + regexp |

### Step 6 (1/7) — port mquickjs_utils.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_utils_types.zig`](mquickjs_utils_types.zig) | ~284 | `@cImport` public headers + `JSContextExt` and basic heap layouts |
| [`mquickjs_utils_lib.zig`](mquickjs_utils_lib.zig) | ~969 | GC refs, heap alloc, printf, debug printers |
| [`mquickjs_utils.zig`](mquickjs_utils.zig) | ~149 | Thin `export fn` C ABI wrappers |
| [`mquickjs_utils_va.c`](mquickjs_utils_va.c) | — | C shim for `js_vprintf`/`js_snprintf` → Zig `mqjs_v*` exports |

### Step 6 (2/7) — port mquickjs_value.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_value_types.zig`](mquickjs_value_types.zig) | ~337 | **Authoritative heap layouts** for strings, props, `JSCFunctionDefExt`, etc.; `valueGetInt`, `newShortInt`, property helpers |
| [`mquickjs_value_lib.zig`](mquickjs_value_lib.zig) | ~2,216 | JSValue primitives, strings, objects, properties, atoms, stdlib init |
| [`mquickjs_value.zig`](mquickjs_value.zig) | ~447 | Thin `export fn` wrappers |

**Build:** `mquickjs_value.c` removed from `engine_c_sources`; `mquickjs_value_obj` added to `addRuntimeObjects`.

**Circular deps with runtime:** `value_lib` calls runtime symbols via `extern fn` (`JS_ToString`, `JS_Call`, `JS_ToNumber`, etc.). Do **not** refactor to `@import("mquickjs_runtime_lib.zig")` until the full engine is Zig (would create import cycle).

### Step 6 (3/7) — port mquickjs_runtime.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_runtime_types.zig`](mquickjs_runtime_types.zig) | ~439 | Re-exports `value_types` as `vt`; opcode enum + `opcode_info_data`; frame offsets; `JSFunctionBytecodeExt`, `JSRegExpExt`; interpreter helpers |
| [`mquickjs_runtime_lib.zig`](mquickjs_runtime_lib.zig) | ~3,094 | Context lifecycle, coercion, operator slow paths, closures, backtrace, **`JS_Call`** interpreter |
| [`mquickjs_runtime.zig`](mquickjs_runtime.zig) | ~259 | Thin `export fn` wrappers + **`export const opcode_info`** |

**Build:** `mquickjs_runtime.c` removed from `engine_c_sources`; `mquickjs_runtime_obj` added to `addRuntimeObjects` (after value).

**No `*_va.c` shim** — variadic `cprintf` stays internal; throws go through utils `JS_ThrowError` extern.

**`JS_Call` control flow:** C `goto` labels preserved as a `Resume` enum + `outer: while (true)` state machine. Variable named `state` (not `resume` — reserved in Zig).

### Step 6 (4/7) — port mquickjs_lexer.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_lexer_types.zig`](mquickjs_lexer_types.zig) | ~183 | `TOK_*` constants; `JSToken`, `JSParseState`, `JSParsePos`, `BlockEnv`; `fromHex`, `isPtr`, `isExactException` |
| [`mquickjs_lexer_lib.zig`](mquickjs_lexer_lib.zig) | ~711 | Tokenizer, literals, skip/seek, parse-error helpers |
| [`mquickjs_lexer.zig`](mquickjs_lexer.zig) | ~80 | Thin `export fn` wrappers (18 symbols) |
| [`mquickjs_lexer_va.c`](mquickjs_lexer_va.c) | ~17 | C shim for variadic **`js_parse_error`** → `js_vsnprintf` + `longjmp` |

**Build:** `mquickjs_lexer.c` removed from `engine_c_sources`; `mquickjs_lexer_obj` added to `addRuntimeObjects` (after runtime); `lexer_va.c` attached to lexer object.

**Exports (Zig):** `get_line_col`, `js_parse_error_mem`, `js_parse_error_stack_overflow`, `js_parse_expect*`, `js_skip_*`, `js_parse_get_pos`, `js_parse_seek_token`, `js_parse_skip_parens_token`, `js_parse_escape`, `js_parse_string`, `js_parse_ident`, `js_parse_regexp_token`, `next_token`, `is_regexp_allowed`.

**Export (C shim only):** `js_parse_error` — called from remaining C parser/builtins via variadic ABI.

**Imports:** `lexer_lib` → `@import utils_lib`, `@import cutils_lib`; `extern fn` for value/dtoa/builtins symbols (no `@import value_lib` — avoids cycles).

**Still in C (called by lexer):** `js_parse_regexp_flags` ([`mquickjs_builtins.c`](mquickjs_builtins.c)).

**`JSParseState` layout (x86_64 Linux, verified vs C):** `@sizeOf = 408`; `JSToken = 24`, `JSParsePos = 8`, `BlockEnv = 48`. Regexp bitfields (`re_in_js`, `multi_line`, …) packed as `re_bits: u8` after `capture_count`. `jmp_buf` via `@cImport("setjmp.h")`.

### Step 6 (5/7) — port mquickjs_parser.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_parser_types.zig`](mquickjs_parser_types.zig) | ~120 | Re-exports `lt`/`rt`/`vt`; parser enums (`PARSE_FUNC_*`, `PF_*`, `PUT_LVALUE_*`); `ConvertVarEntry`; bytecode header helpers |
| [`mquickjs_parser_lib.zig`](mquickjs_parser_lib.zig) | ~2,930 | Bytecode emit, PARSE coroutines, functions/program, JSON, `JS_Parse2`/`JS_Run`/`JS_Eval` |
| [`mquickjs_parser.zig`](mquickjs_parser.zig) | ~80 | Thin `export fn` wrappers |

**Build:** `mquickjs_parser.c` removed from `engine_c_sources`; `mquickjs_parser_obj` added to `addRuntimeObjects` (after lexer). No new `*_va.c` — `js_parse_error` stays in `mquickjs_lexer_va.c`.

**Exports:** `JS_Parse`, `JS_Parse2`, `JS_Run`, `JS_Eval`, `js_parse_call`, `emit_u8`/`emit_u16`/`emit_u32`, `emit_insert`, `js_parse_push_val`, `js_parse_pop_val`, `get_line_col_delta`.

**Imports:** `parser_lib` → `@import utils_lib`, `@import cutils_lib`, `@import parser_types`; `extern fn` for lexer/value/runtime/builtins/dtoa (no `@import` of partner `_lib.zig`).

**PARSE_START / PARSE_CALL:** Zig has no computed `goto`. Ported as labeled `switch` + `continue :sw N`. `PARSE_CALL` returns packed `cur_state | (func << 8) | (param << 16)`. Locals are not preserved across calls unless `PARSE_CALL_SAVE*` pushed them. On resume, `js_parse_call` sets `param = -1`. Internal loop states use 100+ so they never collide with C resume states 0–11.

**`parse_func_table`:** last two entries are C `extern fn` `re_parse_alternative` / `re_parse_disjunction`.

**`opcode_info`:** `extern const opcode_info` from runtime — do not duplicate in parser.

**`setjmp`:** `extern fn setjmp(env: *anyopaque) c_int` with `setjmp(@ptrCast(&s.jmp_env))` to avoid cimport type clash with lexer types.

**JSON object loop:** when reconstructing C `for(;;)` with `continue :sw`, update `s.buf_pos` before the jump (after `{` / after `,`). Missing that caused `JSON.parse` of objects to throw and crash `test_builtin.js`.

**Link surface beyond public API:** builtins still call `emit_insert`, `js_parse_push_val`, `js_parse_pop_val` — exported from `mquickjs_parser.zig`.

### Step 6 (6/7) — port mquickjs_gc.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_gc_types.zig`](mquickjs_gc_types.zig) | ~141 | `GCMarkState`, `BCRelocState`, bytecode headers, 32-bit shrink layouts; re-exports `lt`/`rt`/`vt`/`mc`/`c`; header-bit helpers |
| [`mquickjs_gc_lib.zig`](mquickjs_gc_lib.zig) | ~968 | Mark/compact GC, Jonkers threading, bytecode save/load/relocate, 64→32 shrink |
| [`mquickjs_gc.zig`](mquickjs_gc.zig) | ~67 | Thin `export fn` wrappers |

**Build:** `mquickjs_gc.c` removed from `engine_c_sources`; `mquickjs_gc_obj` added to `addRuntimeObjects` (after parser). No new `*_va.c` shim.

**Exports:** `get_mblock_size`, `JS_GC`, `JS_GC2`, `JS_LoadBytecode`, `JS_IsBytecode`, `JS_RelocateBytecode`, `JS_RelocateBytecode2`, `JS_PrepareBytecode`, `JS_PrepareBytecode64to32`.

**Imports:** `gc_lib` → `@import utils_lib`, `@import gc_types`; `extern fn` for value (`js_rehash_props`, `find_atom`, `js_get_short_float`). **`set_free_block` stays in utils** — gc calls via `utils.set_free_block`.

**GC-ref macros:** `JS_PUSH_VALUE`/`JS_POP_VALUE` inlined using `utils.JS_PushGCRef`/`JS_PopGCRef`.

**64→32 bytecode:** when reading 64-bit `JSFunctionBytecode`, use `gt.bytecodeHasArguments` / `gt.bytecodeHasLocalFuncName` / `rt.bytecodeHasColumn` / `rt.bytecodeArgCount` on packed `header` word — not separate C bitfield names.

**DEBUG_GC/DUMP_GC:** omitted (both commented out in `mquickjs_priv.h`; matches ReleaseFast C build).

---

## 3. Discoveries / Decisions

### Porting pattern (leaf modules — cutils, dtoa, libm)

1. **Split lib + exports:** `<module>_lib.zig` + `<module>.zig` (thin `export fn`).
2. **Build:** `b.addObject()`; remove `.c` from `addEngineCSources`; link via `addRuntimeObjects`.
3. **Internal imports:** Always `@import("<module>_lib.zig")`, never the export root.

### Porting pattern (engine modules — Step 6)

Established by utils/value/runtime/lexer ports:

1. **Three-file split:**
   - `<module>_types.zig` — mirror needed pieces from `mquickjs_internal.h` (do **not** `@cImport` it wholesale).
   - `<module>_lib.zig` — implementation.
   - `<module>.zig` — thin `export fn` wrappers (+ `export const` for linker symbols like `opcode_info`).
2. **Build:** remove `.c` from `engine_c_sources`; add `*_obj` to `addRuntimeObjects`; `addCommonIncludes` on the object.
3. **Variadic C bridge:** only if remaining C calls variadic functions — see `mquickjs_utils_va.c`, **`mquickjs_lexer_va.c`**.
4. **One module at a time.** Full test gate after each port.
5. **Faithful port first.** Idiomatic refactor is Step 8.

### Cross-module import rules (critical)

```
runtime_lib  → @import utils_lib, runtime_types (which re-exports value_types)
runtime_lib  → extern fn for ~30 value symbols (resolves against mquickjs_value.zig exports)
value_lib    → extern fn for ~12 runtime symbols (JS_Call, JS_ToString, etc.)
utils_lib    → extern fn for value/runtime/builtins symbols (gc now Zig — resolves against mquickjs_gc.zig)
lexer_lib    → @import utils_lib, cutils_lib; extern fn for value/dtoa/builtins
parser_lib   → @import utils_lib, cutils_lib, parser_types; extern fn for lexer/value/runtime/builtins/dtoa
gc_lib       → @import utils_lib, gc_types; extern fn for value (js_rehash_props, find_atom, js_get_short_float); set_free_block via utils_lib
builtins_lib → (next) @import utils_lib, builtins_types; extern fn for lexer/parser/value/runtime/gc/dtoa/libm
```

**Prefer `mquickjs_value_types.zig` layouts** over `mquickjs_utils_types.zig` where they differ (utils has extra words on some structs — e.g. wrong `JSCFunctionDefExt`, `JSFunctionBytecodeExt`).

**Re-export pattern (runtime):** `pub const vt = @import("mquickjs_value_types.zig")` in `runtime_types.zig`; use `vt.valueGetInt` everywhere.

**Lexer types pattern:** `pub const lt = @import("mquickjs_lexer_types.zig")` in `parser_types.zig`; `JSParseState` / `BlockEnv` live in `lexer_types.zig` only (do not duplicate).

**GC types pattern:** mirror `GCMarkState`, `BCRelocState` from `mquickjs_internal.h`; bytecode headers (`JSBytecodeHeader`, `JSBytecodeHeader32`) from `mquickjs.h` — used by mqjs `-o`/`-b` and `JS_LoadBytecode`.

### Engine-port pitfalls (learned from value + runtime + lexer + parser)

| Issue | Mitigation |
|-------|------------|
| **`JS_VALUE_GET_INT` on negative shorts** | Always use `vt.valueGetInt` (truncate to i32, arithmetic shift). Never unsigned `@intCast` or utils equivalent — caused SIGSEGV in `get_special_prop` during value port |
| **Frame indices like `FRAME_OFFSET_CUR_PC = -1`** | Same — must use signed `valueGetInt` semantics |
| **`JS_IsException`** | Exact `val == JS_EXCEPTION`, not tag-only check (`vt.isExactException`) |
| **`JS_IsExceptionOrTailCall`** | Special tag == `JS_TAG_EXCEPTION` (`rt.isExceptionOrTailCall`) |
| **`opcode_info` table** | Must match C sizes exactly — parser depends on `.size` for bytecode layout. Exported as `export const opcode_info = rt.opcode_info_data` |
| **`JSFunctionBytecodeExt` flags** | Packed in header word (bit 6 = has_column, bits 7–22 = arg_count), not a separate flags word |
| **`closureVarRefs(po)`** | Pointer after `func_bytecode` field (= C `p->u.closure.var_refs`) |
| **C `goto` in `JS_Call`** | State machine with `Resume` enum; preserve SAVE/RESTORE as `saveFrame`/`restorePc`, POLL_INTERRUPT inline |
| **`resume` identifier** | Reserved in Zig — use `state` for the Resume variable |
| **`OP_get_length` string-char path** | Uses `val` not `obj` for `JS_TAG_STRING_CHAR` check (C quirk — preserve) |
| **Detached varrefs on return** | `set_free_block` at `pv + sizeof(JSVarRefExt) - sizeof(JSValue)` |
| **Circular Zig imports** | Never `@import` acyclic partner's `_lib.zig` if the partner already `extern fn`s you |
| **`js_parse_error` variadic** | Keep in tiny `mquickjs_lexer_va.c`; include `<stddef.h>` + `"cutils.h"` before `mquickjs_internal.h` (needs `size_t`, `BOOL`) |
| **`JSString.is_ascii` in C lexer** | Use `vt.stringSetAscii` + `@memcpy` on `vt.stringBuf(p)` — no separate `is_ascii` field in `JSStringExt` |
| **Keyword token mapping** | Compare atom ptr against `ctxExt(ctx).atom_table` .. `+ JS_ATOM_yield`; `token.val = TOK_NULL + idx` |
| **`unicode_from_utf8` for ASCII** | Inline fast path for `p[0] < 0x80` (matches cutils behavior used by lexer) |
| **C range cases in `next_token`** | Zig `switch` range patterns (`'a'...'z'`) work cleanly |
| **PARSE coroutines / computed goto** | Labeled `switch` + `continue :sw N`; `PARSE_CALL` packed return; internal states ≥ 100 |
| **`setjmp` / `jmp_buf` types** | Avoid `@cImport("setjmp.h")` in parser if lexer already defines `jmp_buf` — use `extern fn setjmp(env: *anyopaque)` |
| **JSON `for(;;)` → labeled switch** | Update loop cursor (`s.buf_pos`) before every `continue :sw` back to the loop head |
| **Builtins parser helpers** | Export `emit_insert`, `js_parse_push_val`, `js_parse_pop_val` even if not in public `mquickjs.h` |
| **Negative short ints in parser** | Use `vt.valueGetInt` / `vt.newShortInt`; use `vt.isExactException` for exception checks |
| **Bitwise NOT on alignment masks** | Use `~@as(usize, c.JSW - 1)` not `~(c.JSW - 1)` — comptime_int negation fails in Zig 0.15.2 |
| **Local shadows function name** | Don't name locals `gc_mark` when `gc_mark()` exists in same module |
| **GC compaction + parse_state** | After `memmove`, refresh `ps.source_buf = vt.stringBuf(p)` if parse in progress |
| **GC 64→32 function bytecode** | Read flags from `rt.JSFunctionBytecodeExt.header` via helper fns; write separate fields on `JSFunctionBytecode_32` |

### App port pattern (example, mqjs)

Unchanged from prior handoff: Zig executable + `*_stdlib_embed.c` + `*_host_decls.h`; do not `@cImport` generated stdlib headers.

### Zig 0.15.2 quirks

| Topic | Detail |
|-------|--------|
| `opaque` keyword | Reserved — use `opaque_val` for parameter names |
| `extern` syntax | `extern "C" const js_stdlib: c.JSSTDLibraryDef;` |
| `std.process.argv` | Use `std.process.argsAlloc(allocator)` |
| `@intCast` | Often needs explicit result type |
| `@fabs` | Use `@abs(x)` for `f64` |
| Comptime in `@intCast(@sizeOf(...) - if (cond) ...)` | Split into if/else branches (runtime `if` not allowed in comptime expr) |

### Architectural decisions

- **Engine port order:** utils → value → runtime → lexer → parser → gc → **builtins**.
- **Makefile:** Legacy; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall`.
- **Do not use** `archive/src-first-attempt/`.
- **Optional follow-up (not required for green):** refactor `extern fn` → `@import` where acyclic; update README port table.

### Dependencies (current)

```
dtoa_lib.zig              →  cutils_lib.zig
libm_lib.zig              →  libm_softfp.c
mquickjs_utils_lib.zig    →  cutils_lib.zig, mquickjs_utils_types.zig; extern value/runtime/builtins (gc via mquickjs_gc.zig)
mquickjs_utils.zig        →  mquickjs_utils_lib.zig
mquickjs_utils_va.c       →  mqjs_vprintf/mqjs_vsnprintf (Zig exports)
mquickjs_value_types.zig  →  mquickjs_utils_types.zig (mc, c)
mquickjs_value_lib.zig    →  value_types; extern runtime/utils/dtoa/builtins
mquickjs_value.zig        →  mquickjs_value_lib.zig
mquickjs_runtime_types.zig → value_types (re-exported as vt)
mquickjs_runtime_lib.zig  →  runtime_types, utils_lib, dtoa_lib; extern value/builtins (~30 symbols); get_mblock_size from gc
mquickjs_runtime.zig      →  mquickjs_runtime_lib.zig; export const opcode_info
mquickjs_lexer_types.zig  →  value_types (re-exported as vt)
mquickjs_lexer_lib.zig    →  lexer_types, utils_lib, cutils_lib; extern value/dtoa/builtins
mquickjs_lexer.zig        →  mquickjs_lexer_lib.zig
mquickjs_lexer_va.c       →  js_vsnprintf (utils_va.c) + longjmp
mquickjs_parser_types.zig →  lexer_types + runtime_types (re-exported as lt/rt/vt)
mquickjs_parser_lib.zig   →  parser_types, utils_lib, cutils_lib; extern lexer/value/runtime/builtins/dtoa
mquickjs_parser.zig       →  mquickjs_parser_lib.zig
mquickjs_gc_types.zig     →  lexer_types + runtime_types (re-exported as lt/rt/vt/mc/c)
mquickjs_gc_lib.zig       →  gc_types, utils_lib; extern value (js_rehash_props, find_atom, js_get_short_float)
mquickjs_gc.zig           →  mquickjs_gc_lib.zig
example.zig / mqjs.zig      →  link 1 engine .c (builtins) + 6 Zig engine modules + embed + leaf objects
mquickjs_builtins.c       →  (next) builtins_types + builtins_lib + builtins.zig; last C engine TU
```

---

## 4. Verification

All run with `/home/vexcess/zig-x86_64-linux-0.15.2/zig` and `-Doptimize=ReleaseFast`:

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig

$ZIG build -Doptimize=ReleaseFast
$ZIG build test -Doptimize=ReleaseFast
$ZIG build example -Doptimize=ReleaseFast
./zig-out/bin/example tests/test_rect.js
$ZIG build microbench -Doptimize=ReleaseFast
bash run-tests.sh
```

**Results after Step 6 gc port (2026-08-13, uncommitted handoff 11):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` round-trip)
- `zig build example` + `tests/test_rect.js` — pass
- `zig build microbench` — pass
- `run-tests.sh` — pass (test_builtin, test_closure, test_language, test_loop, bytecode, test_rect, mandelbrot)

Pay special attention after future ports:

- **`tests/test_builtin.js`** — JSON.parse, all builtins, regexp (`js_parse_regexp`, `re_parse_*`)
- **`tests/test_closure.js`** — closures, varrefs, GC compaction (exercises ported gc)
- **Bytecode `-o`/`-b`** — `JS_PrepareBytecode*`, `JS_RelocateBytecode*`, `JS_LoadBytecode`, `JS_IsBytecode` (now in `mquickjs_gc.zig`)
- **`mqjs` REPL `-gc` flag** — calls `JS_GC`

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)
- Git commit for gc port — not created (awaiting user request)
- README port-status table — not updated

---

## 5. Next Steps

### Step 6 (7/7) — port mquickjs_builtins.c to Zig ← **NEXT**

**Goal:** Port `mquickjs_builtins.c` (~5,311 lines) following the established three-file engine pattern. This is the **last engine C file** — after it, the runtime engine is fully Zig (stdlib codegen `.c` files remain).

**Pattern:** `mquickjs_builtins_types.zig` + `mquickjs_builtins_lib.zig` + `mquickjs_builtins.zig`

#### Scope (major sections in `mquickjs_builtins.c`)

| Section | ~Lines | Contents |
|---------|--------|----------|
| Function builtins | 40–240 | `js_function_*` (constructor, call, apply, bind, …) |
| Number/Boolean/String | 241–719 | `js_number_*`, `js_boolean_*`, `js_string_*` |
| Object/Error/Array | 720–1960 | `js_object_*`, `js_error_*`, `js_array_*` (includes sort, reduce, every) |
| Math/TypedArray/Date/Global | 1961–2474 | `js_math_*`, typed arrays, `js_date_*`, `js_global_*` |
| JSON | 2475–2925 | `js_json_parse`, `js_json_stringify` |
| Regexp parser | 2926–4508 | `re_parse_*`, `re_parse_char_class`, `re_parse_quantifier`, … |
| Regexp runtime | 4509–5311 | `js_parse_regexp`, `js_parse_regexp_flags`, `js_regexp_*`, `js_string_replace`/`split`/`match`/`search` |

#### Critical cross-module dependencies (grep before declaring done)

Many Zig modules still `extern fn` builtins symbols:

```sh
rg 'extern fn (js_|re_parse)' --glob '*_lib.zig'
```

| Consumer | Key builtins symbols |
|----------|---------------------|
| `parser_lib` | `js_parse_regexp`, `re_parse_alternative`, `re_parse_disjunction`, `js_atod` |
| `lexer_lib` | `js_parse_regexp_flags` |
| `runtime_lib` | `js_object_keys`, `js_set_prototype_internal`, `js_get_object_class`, `js_lrint`, `js_fmod`, `js_pow`, … |
| `value_lib` | `js_string_charAt`, `js_new_c_function_proto`, `js_atod`, `js_dtoa` |
| `utils_lib` | `js_dtoa`, `js_lrint`, `js_get_short_float` (some may move to value after port) |

**Parser regexp coroutines:** `parse_func_table` last two entries are `re_parse_alternative` / `re_parse_disjunction` — must export with `callconv(.c)` and same PARSE coroutine ABI as parser.

**Lexer:** `js_parse_regexp_flags` called from `lexer_lib` — currently C-only export.

#### Types to mirror in `mquickjs_builtins_types.zig`

- Re-export `lt`/`pt`/`rt`/`vt`/`mc`/`c` like other engine modules
- Any regexp-specific structs from `mquickjs_internal.h` if needed (most are internal to builtins)
- Do **not** `@cImport` `mquickjs_internal.h` wholesale

#### Build changes

1. Remove `mquickjs_builtins.c` from `engine_c_sources` (engine C goes to **zero** files).
2. Add `mquickjs_builtins_obj` after gc; extend `addRuntimeObjects(..., mquickjs_builtins_obj)`.
3. Keep `mquickjs_builtins.c` on disk as reference.
4. **`engine_c_sources` becomes empty** — consider removing `addEngineCSources` call or leaving empty array until Step 7.

#### Builtins-specific pitfalls (anticipated)

| Issue | Mitigation |
|-------|------------|
| **Largest single file** | Faithful port first; consider sub-section comments matching C order; don't refactor until Step 8 |
| **Regexp PARSE coroutines** | Same labeled-switch pattern as parser; `re_parse_alternative`/`re_parse_disjunction` use PARSE_START macros |
| **`js_array_sort`** | Complex; uses parser emit helpers in C — grep for `emit_`/`js_parse_` calls |
| **`js_json_parse`** | Delegates to parser `JS_Parse` path in C — verify call chain |
| **Math builtins** | Use `libm` exports (`js_pow`, `js_fmod`, etc.) via extern or `@import libm_lib` if acyclic |
| **Circular imports** | `builtins_lib` → `@import utils_lib`; `extern fn` for parser/lexer/value/runtime/gc symbols |
| **Export surface** | Export every symbol referenced by grep across Zig modules; builtins has ~80+ public `js_*` functions |

#### Suggested approach

1. Read full `mquickjs_builtins.c` and grep all `extern fn` references from other Zig modules.
2. Create `mquickjs_builtins_types.zig` (minimal — mostly re-exports).
3. Port `mquickjs_builtins_lib.zig` in C file order (function → number → string → object → array → math → typed array → json → regexp).
4. Create `mquickjs_builtins.zig` with all required exports.
5. Remove C from build; fix link errors one symbol at a time.
6. Full test gate — **`test_builtin.js`** is the critical regression test.

### Step 2 Phase 2b — libm softfloat (optional parallel track)

Make `zig build -Dsoftfloat=true` work. Extend `libm_softfp.c` with `-DUSE_SOFTFLOAT`; port softfloat paths in `libm_lib.zig`. Reference: `libm.c` `#ifdef USE_SOFTFLOAT` blocks.

### Steps 7–8

- Port stdlib codegen (`mquickjs_build.c`)
- Idiomatic Zig refactor; collapse `extern fn` → `@import` where acyclic; update README port table

---

## Quick reference commands

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig   # if zig not on PATH

$ZIG build -Doptimize=ReleaseFast
$ZIG build test -Doptimize=ReleaseFast
$ZIG build example -Doptimize=ReleaseFast
$ZIG build microbench -Doptimize=ReleaseFast
bash run-tests.sh

# Regenerate C split from monolith backup:
python3 split_mquickjs.py
```

---

## Files the next agent should not touch without reason

- [`archive/mquickjs_monolith.c`](archive/mquickjs_monolith.c) — edit only when fixing split script source
- [`split_mquickjs.py`](split_mquickjs.py) — regeneration script
- [`mquickjs.h`](mquickjs.h), [`mquickjs_priv.h`](mquickjs_priv.h) — public API
- [`archive/src-first-attempt/`](archive/src-first-attempt/) — stale
- Reference `.c` files not in `engine_c_sources` — port diffs only
- Already-ported Zig modules unless fixing build break
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Steps 0–5, plus Step 6 modules 1–6/7 (utils, value, runtime, lexer, parser, gc).
- Leaf modules cutils, dtoa, libm, readline are on Zig.
- Host apps example and mqjs are on Zig.
- Engine: 6 Zig modules (utils, value, runtime, lexer, parser, gc); 1 C module remains (builtins).
- Reference C kept but not compiled: mquickjs_utils.c, mquickjs_value.c, mquickjs_runtime.c, mquickjs_lexer.c, mquickjs_parser.c, mquickjs_gc.c.
- Last green: uncommitted handoff 11 (gc port); parent commit e9f3f08.
- Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 6 module 7/7 — port mquickjs_builtins.c to Zig

Goal: Port mquickjs_builtins.c (~5,311 lines) following the established engine pattern:
  mquickjs_builtins_types.zig + mquickjs_builtins_lib.zig + mquickjs_builtins.zig
One module at a time; zero behavior change; full test gate after port.

Read first:
- handoff.md (Sections 1, 2 Step 6 gc + builtins sketch, 3 cross-module rules + pitfalls, 5 builtins next steps)
- mquickjs_builtins.c (full file — largest engine module; builtins + regexp engine)
- mquickjs_internal.h — regexp PARSE func declarations, js_* prototypes
- Grep: extern fn (js_|re_parse) across *_lib.zig — full export surface needed
- build.zig (engine_c_sources, addRuntimeObjects)

Implementation:
1. Create mquickjs_builtins_types.zig — re-export lt/pt/rt/vt/mc/c; any regexp-specific types from internal.h.
2. Create mquickjs_builtins_lib.zig — faithful port of mquickjs_builtins.c (~5,311 lines) in C file order.
3. Create mquickjs_builtins.zig — export all js_* / re_parse_* / js_parse_regexp* symbols consumed by other modules.
4. Remove mquickjs_builtins.c from engine_c_sources; add mquickjs_builtins_obj to addRuntimeObjects; addCommonIncludes.
5. Do NOT touch example.zig, mqjs.zig, or already-ported modules unless build breaks.

Critical rules (from prior ports):
- Use vt.valueGetInt for all JS_VALUE_GET_INT semantics (negative short ints).
- Prefer mquickjs_value_types.zig heap layouts over mquickjs_utils_types.zig where they differ.
- Circular imports: new module → @import utils_lib + types; existing modules keep extern fn for new exports.
- Regexp PARSE coroutines (re_parse_alternative/disjunction): same labeled-switch + PARSE_CALL pattern as parser.
- Export js_parse_regexp_flags for lexer_lib.
- Do not use archive/src-first-attempt/.

Constraints:
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)
- Build/test only with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall
- Do not create git commits unless I ask
- Fix link errors one symbol at a time; run test gate before declaring done

Test gate:
  export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig
  $ZIG build -Doptimize=ReleaseFast
  $ZIG build test -Doptimize=ReleaseFast
  $ZIG build example -Doptimize=ReleaseFast
  ./zig-out/bin/example tests/test_rect.js
  $ZIG build microbench -Doptimize=ReleaseFast
  bash run-tests.sh

Pay special attention: test_builtin.js (JSON, all builtins, regexp), test_closure.js (GC still green).
```

**Alternative tasks:**

- **Softfloat:** Step 2 Phase 2b — read handoff Section 5 Phase 2b sketch.
- **Docs only:** update README port-status table; commit gc port if user asks.
