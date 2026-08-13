# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-13  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`  
Last known-good: **handoff 9 (lexer port)** — uncommitted; parent commit **`a219b2f` (handoff 8 — runtime port)**

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

### In progress / not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 6 (5/7–7/7)** | Port remaining engine modules to Zig | **Next: `mquickjs_parser.c`** |
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Steps 7–8** | Host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C engine (3 files):
│     mquickjs_parser.c, mquickjs_gc.c, mquickjs_builtins.c
├── Zig engine (4 modules):
│     mquickjs_utils   — utils.zig + utils_lib.zig + utils_types.zig (+ utils_va.c shim)
│     mquickjs_value   — value.zig + value_lib.zig + value_types.zig
│     mquickjs_runtime — runtime.zig + runtime_lib.zig + runtime_types.zig
│     mquickjs_lexer   — lexer.zig + lexer_lib.zig + lexer_types.zig (+ lexer_va.c shim)
├── Shared engine header: mquickjs_internal.h
├── Zig objects: cutils, dtoa, libm, mquickjs_utils, mquickjs_value, mquickjs_runtime,
│                mquickjs_lexer, readline
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs, **mquickjs_utils**, **mquickjs_value**, **mquickjs_runtime**, **mquickjs_lexer**.  
**Still C:** 3 engine `.c` files (parser, gc, builtins) + stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`).  
**Reference only (not compiled):** `archive/mquickjs_monolith.c`, `mquickjs_utils.c`, `mquickjs_value.c`, `mquickjs_runtime.c`, **`mquickjs_lexer.c`**, `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

### Recommended port order (remaining)

1. **`mquickjs_parser.c`** (~3,740 lines) ← **NEXT** — depends on lexer; largest compiler chunk
2. **`mquickjs_gc.c`** (~1,198 lines)
3. **`mquickjs_builtins.c`** (~5,311 lines) — largest file overall

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
utils_lib    → extern fn for value/runtime/gc/builtins symbols still in C
lexer_lib    → @import utils_lib, cutils_lib; extern fn for value/dtoa/builtins
parser.c     → links runtime/value/utils/lexer Zig exports + remaining C engine (gc, builtins)
```

**Prefer `mquickjs_value_types.zig` layouts** over `mquickjs_utils_types.zig` where they differ (utils has extra words on some structs — e.g. wrong `JSCFunctionDefExt`, `JSFunctionBytecodeExt`).

**Re-export pattern (runtime):** `pub const vt = @import("mquickjs_value_types.zig")` in `runtime_types.zig`; use `vt.valueGetInt` everywhere.

**Lexer types pattern:** `pub const vt = @import("mquickjs_value_types.zig")` in `lexer_types.zig`; parser port should extend or share `JSParseState` / `BlockEnv` from `lexer_types.zig`.

### Engine-port pitfalls (learned from value + runtime + lexer)

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

- **Engine port order:** utils → value → runtime → lexer → **parser** → gc → builtins.
- **Makefile:** Legacy; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall`.
- **Do not use** `archive/src-first-attempt/`.
- **Optional follow-up (not required for green):** refactor `extern fn` → `@import` where acyclic; update README port table.

### Dependencies (current)

```
dtoa_lib.zig              →  cutils_lib.zig
libm_lib.zig              →  libm_softfp.c
mquickjs_utils_lib.zig    →  cutils_lib.zig, mquickjs_utils_types.zig; extern value/runtime/gc/builtins
mquickjs_utils.zig        →  mquickjs_utils_lib.zig
mquickjs_utils_va.c       →  mqjs_vprintf/mqjs_vsnprintf (Zig exports)
mquickjs_value_types.zig  →  mquickjs_utils_types.zig (mc, c)
mquickjs_value_lib.zig    →  value_types; extern runtime/utils/dtoa/builtins
mquickjs_value.zig        →  mquickjs_value_lib.zig
mquickjs_runtime_types.zig → value_types (re-exported as vt)
mquickjs_runtime_lib.zig  →  runtime_types, utils_lib, dtoa_lib; extern value/gc/builtins (~30 symbols)
mquickjs_runtime.zig      →  mquickjs_runtime_lib.zig; export const opcode_info
mquickjs_lexer_types.zig  →  value_types (re-exported as vt)
mquickjs_lexer_lib.zig    →  lexer_types, utils_lib, cutils_lib; extern value/dtoa/builtins
mquickjs_lexer.zig        →  mquickjs_lexer_lib.zig
mquickjs_lexer_va.c       →  js_vsnprintf (utils_va.c) + longjmp
example.zig / mqjs.zig      →  link 3 engine .c + utils + value + runtime + lexer + embed + runtime objects
mquickjs_parser/gc/builtins.c → mquickjs_internal.h; link Zig engine objects
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

**Results after Step 6 lexer port (2026-08-13, uncommitted handoff 9):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` round-trip)
- `zig build example` + `tests/test_rect.js` — pass
- `zig build microbench` — pass
- `run-tests.sh` — pass (test_builtin, test_closure, test_language, test_loop, bytecode, test_rect, mandelbrot)

Pay special attention after future ports: `tests/test_closure.js`, `tests/test_builtin.js`, bytecode `-o`/`-b` (exercise `JS_Call` + parser + lexer).

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)
- Git commit for lexer port — not created (awaiting user request)

---

## 5. Next Steps

### Step 6 (5/7) — port mquickjs_parser.c to Zig ← **NEXT**

**Goal:** Port `mquickjs_parser.c` (~3,740 lines) following the established three-file engine pattern.

**Why parser is next:** Lexer is Zig; parser is the largest remaining compiler piece and owns bytecode emission, `JS_Parse`/`JS_Run`/`JS_Eval`.

**Scope (key areas):**

| Area | Symbols / notes |
|------|-----------------|
| Public API | `JS_Parse`, `JS_Parse2`, `JS_Run`, `JS_Eval`, `JS_LoadBytecode` (check if in parser or gc) |
| Bytecode emit | `emit_op`, `emit_op_param`, `emit_u8/u16/u32`, `emit_var`, `cpool_add`, `js_emit_push_const`, `js_emit_push_number` |
| pc2line debug | `emit_pc2line`, `pc2line_put_bits`, `get_line_col_delta` |
| Parser state machine | `js_parse_call`, `js_parse_*_expr`, `js_parse_statement`, `js_parse_block`, `js_parse_function_decl`, `js_parse_program` |
| Labels / breaks | `push_break_entry`, `new_label`, `emit_label`, `emit_goto`, `BlockEnv` stack |
| Lvalues | `get_lvalue`, `put_lvalue`, `js_parse_property_name` |
| Stack helpers | `js_parse_push_val`, `js_parse_pop_val`, `parse_stack_alloc` |
| Uses lexer (Zig) | `next_token`, all `js_parse_expect*`, `js_parse_error*` |
| Uses runtime (Zig) | `opcode_info` (via `extern const` or link), coercion, `JS_Call` paths during compile |
| Uses value (Zig) | Atoms, strings, objects, `JS_MakeUniqueString`, property helpers |
| Still C deps | gc (`JS_GC`, alloc during parse?), builtins (`js_parse_regexp` called from postfix expr) |

**Types to mirror in `mquickjs_parser_types.zig`:**

- Extend or re-export from [`mquickjs_lexer_types.zig`](mquickjs_lexer_types.zig): `JSParseState`, `BlockEnv`, `JSToken`, `JSParsePos`, parse enums (`JSParseFunctionEnum`, `PutLValueEnum`, `ParseExprFuncEnum`)
- Parser-specific: `ConvertVarEntry`, bytecode explore tables, any emit-side structs
- Opcode constants: prefer `@import("mquickjs_runtime_types.zig")` for `OP_*` and `opcode_info` sizes
- **Do not** `@cImport(mquickjs_internal.h)` wholesale

**Hard parts (plan ahead):**

1. **C `PARSE_START` / `PARSE_CALL` macros** — coroutine-style parser using `setjmp` + state ints; port as explicit state machine (like runtime `JS_Call` `Resume` enum).
2. **`opcode_info`** — parser reads `.size`, `.n_pop`, `.n_push` for bytecode layout; must stay byte-identical to C table (already exported from runtime).
3. **`get_line_col_delta`** — currently in parser.c; moves with parser port (lexer has `get_line_col`).
4. **Variadic `js_parse_error`** — already in `mquickjs_lexer_va.c`; parser Zig code calls via `extern fn js_parse_error`.
5. **Link surface** — grep `mquickjs_gc.c` and `mquickjs_builtins.c` for symbols defined in parser.c before cutting over.

**Read first:**

- [`mquickjs_parser.c`](mquickjs_parser.c)
- [`mquickjs_lexer_types.zig`](mquickjs_lexer_types.zig) — shared parse state layouts
- [`mquickjs_runtime_types.zig`](mquickjs_runtime_types.zig) — opcodes, `opcode_info_data`, bytecode layouts
- [`mquickjs_internal.h`](mquickjs_internal.h) — `PARSE_*` macros (~566+), parser prototypes
- [`build.zig`](build.zig) — `engine_c_sources`, `addRuntimeObjects`

**Approach:**

1. Create `mquickjs_parser_types.zig` — extend lexer types; parser enums and helper structs.
2. Create `mquickjs_parser_lib.zig` — faithful port; `@import` lexer_types, runtime_types, utils_lib; `extern fn` for gc/builtins/value as needed.
3. Create `mquickjs_parser.zig` — `export fn` wrappers for every cross-module symbol.
4. Remove `mquickjs_parser.c` from `engine_c_sources`; add `mquickjs_parser_obj` to `addRuntimeObjects`.
5. Fix link errors one at a time; run full test gate.

**Do not:** port gc/builtins simultaneously; change behavior; touch app files unless build breaks.

### After parser

| Module | ~Lines | Notes |
|--------|--------|-------|
| `mquickjs_gc.c` | 1,198 | Mark/compact GC, `JS_GC`, `JS_LoadBytecode` (verify which file owns load) |
| `mquickjs_builtins.c` | 5,311 | All `js_*` builtins + regexp engine; `js_parse_regexp_flags` still C |

### Step 2 Phase 2b — libm softfloat (optional parallel track)

Make `zig build -Dsoftfloat=true` work. Extend `libm_softfp.c` with `-DUSE_SOFTFLOAT`; port softfloat paths in `libm_lib.zig`. Reference: `libm.c` `#ifdef USE_SOFTFLOAT` blocks.

### Steps 7–8

- Port stdlib codegen (`mquickjs_build.c`)
- Idiomatic Zig refactor; collapse `extern fn` → `@import` where acyclic

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

Done: Steps 0–5, plus Step 6 modules 1–4/7 (utils, value, runtime, lexer).
- Leaf modules cutils, dtoa, libm, readline are on Zig.
- Host apps example and mqjs are on Zig.
- Engine: 4 Zig modules (utils, value, runtime, lexer); 3 C modules remain (parser, gc, builtins).
- Reference C kept but not compiled: mquickjs_utils.c, mquickjs_value.c, mquickjs_runtime.c, mquickjs_lexer.c.
- Last green: uncommitted handoff 9 (lexer port); parent commit a219b2f.
- Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 6 module 5/7 — port mquickjs_parser.c to Zig

Goal: Port mquickjs_parser.c (~3,740 lines) following the established engine pattern:
  mquickjs_parser_types.zig + mquickjs_parser_lib.zig + mquickjs_parser.zig
One module at a time; zero behavior change; full test gate after port.

Read first:
- handoff.md (Sections 1, 2 Step 6, 3 cross-module rules + pitfalls, 5 parser sketch)
- mquickjs_parser.c
- mquickjs_internal.h (PARSE_* macros, parser structs — mirror in *_types.zig, do NOT @cImport wholesale)
- mquickjs_lexer_types.zig (shared JSParseState, BlockEnv — extend or re-export)
- mquickjs_runtime_types.zig (opcode_info, OP_* enums, bytecode layouts)
- mquickjs_gc.c / mquickjs_builtins.c (grep parser symbols — defines required exports)
- build.zig (engine_c_sources, addRuntimeObjects)

Implementation:
1. Create mquickjs_parser_types.zig — extend lexer types; parser enums and emit-side structs.
2. Create mquickjs_parser_lib.zig — faithful port of mquickjs_parser.c.
3. Create mquickjs_parser.zig — export fn wrappers for all cross-module symbols (JS_Parse, JS_Eval, etc.).
4. Remove mquickjs_parser.c from engine_c_sources; add mquickjs_parser_obj to addRuntimeObjects; addCommonIncludes.
5. Port PARSE_START/PARSE_CALL coroutine macros as explicit state machine (like runtime JS_Call Resume enum).
6. Do NOT port gc or builtins. Do NOT touch example.zig, mqjs.zig, or already-ported modules unless build breaks.

Critical rules (from prior ports):
- Use vt.valueGetInt for all JS_VALUE_GET_INT semantics (negative short ints).
- Prefer mquickjs_value_types.zig heap layouts over mquickjs_utils_types.zig where they differ.
- opcode_info sizes must match C exactly — parser bytecode layout depends on them.
- js_parse_error is variadic — already in mquickjs_lexer_va.c; call via extern fn.
- Circular imports: new module → @import lexer/runtime types + utils_lib; existing modules keep extern fn for new exports.
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
```

**Alternative tasks:**

- **Skip parser:** port `mquickjs_gc.c` (Step 6 module 6/7) — smaller but parser before gc is recommended for dependency order.
- **Softfloat:** Step 2 Phase 2b — read handoff Section 5 Phase 2b sketch.
- **Docs only:** update README port-status table; commit lexer port if user asks.
