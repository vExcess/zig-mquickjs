# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-13  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`  
Last known-good: **handoff 12 (builtins port)** — uncommitted; parent commit **`8649a67` (handoff 11 — gc port)**

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
| **Step 6 (7/7)** | Port `mquickjs_builtins.c` → Zig | **Complete** |

**Step 6 is done.** The JavaScript engine runtime is fully Zig. No engine `.c` files are compiled.

### In progress / not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Step 7** | Port stdlib codegen (`mquickjs_build.c`) | **Not started** |
| **Step 8** | Idiomatic refactor, collapse `extern fn` → `@import` where acyclic | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C engine: (none — engine_c_sources is empty)
├── Zig engine (7 modules):
│     mquickjs_utils   — utils.zig + utils_lib.zig + utils_types.zig (+ utils_va.c shim)
│     mquickjs_value   — value.zig + value_lib.zig + value_types.zig
│     mquickjs_runtime — runtime.zig + runtime_lib.zig + runtime_types.zig
│     mquickjs_lexer   — lexer.zig + lexer_lib.zig + lexer_types.zig (+ lexer_va.c shim)
│     mquickjs_parser  — parser.zig + parser_lib.zig + parser_types.zig
│     mquickjs_gc      — gc.zig + gc_lib.zig + gc_types.zig
│     mquickjs_builtins — builtins.zig + builtins_lib.zig + builtins_types.zig
├── Shared engine header: mquickjs_internal.h
├── Zig objects: cutils, dtoa, libm, mquickjs_utils, mquickjs_value, mquickjs_runtime,
│                mquickjs_lexer, mquickjs_parser, mquickjs_gc, mquickjs_builtins, readline
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs, and all **7 engine modules**.  
**Still C:** stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`) + embed `.c` + two `*_va.c` shims.  
**Reference only (not compiled):** `archive/mquickjs_monolith.c`, all split `mquickjs_*.c` files, `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

### Recommended next work (priority order)

1. **Commit handoff 12** — builtins port is green but uncommitted (user must ask).
2. **Update README port-status table** — still says “mquickjs: 7 C files”.
3. **Step 7** — port `mquickjs_build.c` (stdlib atom/codegen host tool).
4. **Step 2 Phase 2b** — softfloat (`-Dsoftfloat=true`).
5. **Step 8** — idiomatic refactor; replace acyclic `extern fn` with `@import`.

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
| [`README.md`](README.md) | Port status table (stale — needs update) |

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

**Circular deps with runtime:** `value_lib` calls runtime symbols via `extern fn`. Do **not** refactor to `@import` until Step 8 (would create import cycle).

### Step 6 (3/7) — port mquickjs_runtime.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_runtime_types.zig`](mquickjs_runtime_types.zig) | ~439 | Re-exports `value_types` as `vt`; opcode enum + `opcode_info_data`; frame offsets; `JSFunctionBytecodeExt`, `JSRegExpExt`; interpreter helpers |
| [`mquickjs_runtime_lib.zig`](mquickjs_runtime_lib.zig) | ~3,094 | Context lifecycle, coercion, operator slow paths, closures, backtrace, **`JS_Call`** interpreter |
| [`mquickjs_runtime.zig`](mquickjs_runtime.zig) | ~259 | Thin `export fn` wrappers + **`export const opcode_info`** |

**`JS_Call` control flow:** C `goto` labels preserved as a `Resume` enum + `outer: while (true)` state machine. Variable named `state` (not `resume` — reserved in Zig).

### Step 6 (4/7) — port mquickjs_lexer.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_lexer_types.zig`](mquickjs_lexer_types.zig) | ~183 | `TOK_*` constants; `JSToken`, `JSParseState`, `JSParsePos`, `BlockEnv`; `fromHex`, `isPtr`, `isExactException` |
| [`mquickjs_lexer_lib.zig`](mquickjs_lexer_lib.zig) | ~711 | Tokenizer, literals, skip/seek, parse-error helpers |
| [`mquickjs_lexer.zig`](mquickjs_lexer.zig) | ~80 | Thin `export fn` wrappers (18 symbols) |
| [`mquickjs_lexer_va.c`](mquickjs_lexer_va.c) | ~17 | C shim for variadic **`js_parse_error`** → `js_vsnprintf` + `longjmp` |

**`js_parse_regexp_flags`:** now exported from `mquickjs_builtins.zig` (was C-only).

### Step 6 (5/7) — port mquickjs_parser.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_parser_types.zig`](mquickjs_parser_types.zig) | ~120 | Re-exports `lt`/`rt`/`vt`; parser enums (`PARSE_FUNC_*`, `PF_*`, `PUT_LVALUE_*`); `ConvertVarEntry`; bytecode header helpers |
| [`mquickjs_parser_lib.zig`](mquickjs_parser_lib.zig) | ~2,930 | Bytecode emit, PARSE coroutines, functions/program, JSON, `JS_Parse2`/`JS_Run`/`JS_Eval` |
| [`mquickjs_parser.zig`](mquickjs_parser.zig) | ~80 | Thin `export fn` wrappers |

**PARSE coroutines:** labeled `switch` + `continue :sw N`; `PARSE_CALL` packed return; internal loop states ≥ 100.

**`parse_func_table`:** last two entries are `extern fn` `re_parse_alternative` / `re_parse_disjunction` from builtins.

### Step 6 (6/7) — port mquickjs_gc.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_gc_types.zig`](mquickjs_gc_types.zig) | ~141 | `GCMarkState`, `BCRelocState`, bytecode headers, 32-bit shrink layouts; re-exports `lt`/`rt`/`vt`/`mc`/`c` |
| [`mquickjs_gc_lib.zig`](mquickjs_gc_lib.zig) | ~968 | Mark/compact GC, Jonkers threading, bytecode save/load/relocate, 64→32 shrink |
| [`mquickjs_gc.zig`](mquickjs_gc.zig) | ~67 | Thin `export fn` wrappers |

### Step 6 (7/7) — port mquickjs_builtins.c to Zig

| File | Lines | Role |
|------|-------|------|
| [`mquickjs_builtins_types.zig`](mquickjs_builtins_types.zig) | ~225 | Re-exports `lt`/`pt`/`rt`/`vt`/`mc`/`c`; `REOP` opcode struct + `reopcode_info_data`; regexp flags/headers; `JSArraySortContext`, `JSDateExt`; `char_range_s`/`w`; JSParseState `re_bits` helpers |
| [`mquickjs_builtins_lib.zig`](mquickjs_builtins_lib.zig) | ~5,016 | Faithful C-order port: function/number/string/object/error/array/math/typed-array/date/global/JSON/regexp parser + `lre_exec` interpreter + string match/replace/split/search |
| [`mquickjs_builtins.zig`](mquickjs_builtins.zig) | ~400 | **97** thin `export fn` wrappers |

**Build:** `engine_c_sources = .{}` (empty); `mquickjs_builtins_obj` added to `addRuntimeObjects` after gc. `addEngineCSources` kept as no-op when empty. `mquickjs_builtins.c` on disk as reference only.

**Cross-module exports (required by other Zig modules):**

| Consumer | Symbols |
|----------|---------|
| `parser_lib` | `js_parse_regexp`, `re_parse_alternative`, `re_parse_disjunction` |
| `lexer_lib` | `js_parse_regexp_flags` |
| `runtime_lib` | `js_object_keys`, `js_set_prototype_internal` |
| `value_lib` | `js_string_charAt` |
| `utils_lib` | `dump_regexp` |

**Also exported:** all stdlib `js_*` handlers from `mqjs_stdlib.c` / `example_stdlib.c`, plus public API `JS_IsArray`, `JS_NewDate`.

**Host-only symbols stay in mqjs/example:** `js_date_constructor`, `js_date_now`, `js_print`, `js_gc`, `js_load`, timeouts, Rectangle, etc.

**Imports:** `builtins_lib` → `@import utils_lib`, `@import cutils_lib`, `@import builtins_types`; `extern fn` for parser/lexer/value/runtime symbols (no `@import` of partner `_lib.zig`).

**Regexp PARSE coroutines:** `re_parse_alternative` / `re_parse_disjunction` use same labeled-switch pattern as parser; **`callconv(.c)`**; resume states 0–2; internal loops at 100+; `js_parse_regexp` calls `js_parse_call(s, pt.PARSE_FUNC_re_parse_disjunction, 0)`.

**Uncommitted changes (2026-08-13):**

```
 M build.zig
?? mquickjs_builtins.zig
?? mquickjs_builtins_types.zig
?? mquickjs_builtins_lib.zig
```

---

## 3. Discoveries / Decisions

### Porting pattern (leaf modules — cutils, dtoa, libm)

1. **Split lib + exports:** `<module>_lib.zig` + `<module>.zig` (thin `export fn`).
2. **Build:** `b.addObject()`; remove `.c` from build; link via `addRuntimeObjects`.
3. **Internal imports:** Always `@import("<module>_lib.zig")`, never the export root.

### Porting pattern (engine modules — Step 6)

1. **Three-file split:** `<module>_types.zig`, `<module>_lib.zig`, `<module>.zig`.
2. **Build:** remove `.c` from `engine_c_sources`; add `*_obj` to `addRuntimeObjects`.
3. **Variadic C bridge:** only if needed — `mquickjs_utils_va.c`, `mquickjs_lexer_va.c`.
4. **One module at a time.** Full test gate after each port.
5. **Faithful port first.** Idiomatic refactor is Step 8.

### Cross-module import rules (critical)

```
runtime_lib  → @import utils_lib, runtime_types (which re-exports value_types)
runtime_lib  → extern fn for ~30 value symbols + builtins (js_object_keys, js_set_prototype_internal, …)
value_lib    → extern fn for ~12 runtime symbols + builtins (js_string_charAt, …)
utils_lib    → extern fn for value/runtime/builtins (dump_regexp, js_dtoa, …)
lexer_lib    → @import utils_lib, cutils_lib; extern fn for value/dtoa/builtins (js_parse_regexp_flags)
parser_lib   → @import utils_lib, cutils_lib, parser_types; extern fn for lexer/value/runtime/builtins/dtoa
gc_lib       → @import utils_lib, gc_types; extern fn for value
builtins_lib → @import utils_lib, cutils_lib, builtins_types; extern fn for parser/lexer/value/runtime
```

**Prefer `mquickjs_value_types.zig` layouts** over `mquickjs_utils_types.zig` where they differ.

**Re-export pattern:** `pub const vt = @import("mquickjs_value_types.zig")` in downstream `*_types.zig`.

### Engine-port pitfalls (learned from all Step 6 modules)

| Issue | Mitigation |
|-------|------------|
| **`JS_VALUE_GET_INT` on negative shorts** | Always use `vt.valueGetInt` |
| **`JS_IsException`** | `vt.isExactException` / `val == c.JS_EXCEPTION` |
| **PARSE coroutines / computed goto** | Labeled `switch` + `continue :sw N`; `PARSE_CALL` packed return; internal states ≥ 100 |
| **`setjmp` / `jmp_buf` types** | `extern fn setjmp(env: *anyopaque)` in parser to avoid cimport clash |
| **JSON `for(;;)` → labeled switch** | Update loop cursor before every `continue :sw` back to loop head |
| **Circular Zig imports** | Never `@import` acyclic partner's `_lib.zig` if partner already `extern fn`s you |
| **`js_parse_error` variadic** | Keep in `mquickjs_lexer_va.c` |
| **GC 64→32 function bytecode** | Read flags from packed `header` word via helper fns |
| **Bitwise NOT on alignment masks** | Use `~@as(usize, c.JSW - 1)` not `~(c.JSW - 1)` |

### Builtins-specific pitfalls (Step 6 module 7)

| Issue | Mitigation |
|-------|------------|
| **C block comments `/* */`** | Zig has no block comments — use `//` |
| **`opaque` parameter name** | Reserved — use `opaque_ptr` |
| **`i1`/`i2` shadow primitives** | Rename to `idx1`/`idx2` in sort/range helpers |
| **`@branchHint(.unlikely)`** | Must be first statement in the branch body — restructure `if` blocks |
| **`-1.0 / 0.0` for ±∞** | Compile error (division by zero) — use `std.math.inf(f64)` |
| **`\b` in switch** | Invalid escape — use `0x08` |
| **`js_object_keys` from runtime** | Runtime passes `NULL` this_val — signature `this_val: ?*c.JSValue` |
| **`js_typed_array_constructor` NULL this** | C passes `NULL` from `js_typed_array_constructor_obj` — use `this_val: ?*c.JSValue` |
| **`js_regexp_exec` argv type** | Internal calls pass `this_val: *c.JSValue` where param is `[*]c.JSValue` — use `@ptrCast(this_val)` |
| **Capture array indexing** | `st.capture[@as(usize, @as(u32, @intCast(2 * st.capture_count)) + idx)]` |
| **`re_parse_*` ABI** | Must be `pub fn … callconv(.c) c_int` for parser `parse_func_table` |
| **Missing value exports used by builtins** | Add `extern fn` for `JS_NewStringLen`, `js_string_byte_len`, `string_buffer_concat_utf16`, `__js_poll_interrupt` |
| **`js_array_sort_cmp` + JS_EXCEPTION** | Comparator is `c_int`; preserve C truncation: `return @truncate(c.JS_EXCEPTION)` |
| **Extra `JS_NewObjectClass` size args** | Bytes: `@intCast(@sizeOf(mc.JSArrayBufferExt))`, `@sizeOf(mc.JSTypedArrayExt)`, `@sizeOf(bt.JSDateExt)`, `@sizeOf(rt.JSRegExpExt)` |

### Architectural decisions

- **Engine port order:** utils → value → runtime → lexer → parser → gc → builtins — **complete**.
- **Makefile:** Legacy; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall`.
- **Do not use** `archive/src-first-attempt/`.
- **README port table:** stale (still lists engine as C) — update in Step 7 or on request.

### Dependencies (current)

```
dtoa_lib.zig              →  cutils_lib.zig
libm_lib.zig              →  libm_softfp.c
mquickjs_utils_lib.zig    →  cutils_lib.zig, mquickjs_utils_types.zig; extern value/runtime/builtins/gc
mquickjs_value_lib.zig    →  value_types; extern runtime/utils/dtoa/builtins
mquickjs_runtime_lib.zig  →  runtime_types, utils_lib, dtoa_lib; extern value/builtins/gc
mquickjs_lexer_lib.zig    →  lexer_types, utils_lib, cutils_lib; extern value/dtoa/builtins
mquickjs_parser_lib.zig   →  parser_types, utils_lib, cutils_lib; extern lexer/value/runtime/builtins/dtoa
mquickjs_gc_lib.zig       →  gc_types, utils_lib; extern value
mquickjs_builtins_lib.zig → builtins_types, utils_lib, cutils_lib; extern parser/lexer/value/runtime
example.zig / mqjs.zig    →  link 7 Zig engine modules + embed + leaf objects (no engine C)
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

**Results after Step 6 builtins port (2026-08-13, uncommitted handoff 12):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` round-trip)
- `zig build example` + `tests/test_rect.js` — pass
- `zig build microbench` — pass (~118s; regexp/sort benches included)
- `run-tests.sh` — pass (test_builtin, test_closure, test_language, test_loop, bytecode, test_rect, mandelbrot)

Critical regressions verified green:

- **`tests/test_builtin.js`** — JSON.parse/stringify, all builtins, regexp compile/exec, String.match/replace/split
- **`tests/test_closure.js`** — GC still green after final engine module switch
- **Bytecode `-o`/`-b`** — unchanged, still green

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)
- Git commit for builtins port — not created (awaiting user request)
- README port-status table — not updated

---

## 5. Next Steps

### Immediate housekeeping (optional, low risk)

1. **Commit handoff 12** — if user asks: `build.zig` + three `mquickjs_builtins*.zig` files.
2. **Update README** — change “mquickjs: 7 C files” to “7 Zig modules”; note engine C is zero.
3. **Remove dead `addEngineCSources` calls** — optional cleanup in `build.zig` (currently no-op).

### Step 7 — port stdlib codegen (`mquickjs_build.c`) ← **recommended next port**

**Goal:** Port the host tool that compiles stdlib definition tables into generated headers/embed `.c` files.

**Still C today:**

- [`mquickjs_build.c`](mquickjs_build.c) — shared codegen logic (`build_atoms`, class/prop table emission)
- [`mqjs_stdlib.c`](mqjs_stdlib.c) — mqjs stdlib definition tables
- [`example_stdlib.c`](example_stdlib.c) — example stdlib definition tables
- Generated: `mqjs_stdlib.h`, `example_stdlib.h`, `*_stdlib_embed.c`

**Build integration:** `build.zig` runs `mqjs_stdlib` / `example_stdlib` host executables at build time (`b.addExecutable` + `addCSourceFiles` with `mquickjs_build.c`). After port, these become Zig host tools.

**Scope notes:**

- Host-only — does not affect runtime engine ABI.
- Tables reference `js_*` function pointers — all now resolve against `mquickjs_builtins.zig` exports at link time for runtime; host tool only needs to emit pointer names/symbols into C headers.
- Likely pattern: `mquickjs_build_lib.zig` + `mqjs_stdlib.zig` / `example_stdlib.zig` host exes, or one shared lib + thin roots.

**Test gate:** full build + `run-tests.sh` (stdlib tables must remain byte-identical or behavior-identical).

### Step 2 Phase 2b — libm softfloat (optional parallel track)

Make `zig build -Dsoftfloat=true` work. Extend `libm_softfp.c` with `-DUSE_SOFTFLOAT`; port softfloat paths in `libm_lib.zig`. Reference: `libm.c` `#ifdef USE_SOFTFLOAT` blocks.

### Step 8 — idiomatic refactor

- Replace acyclic `extern fn` with `@import` where safe (e.g. builtins ↔ value may still cycle — analyze graph first).
- Collapse duplicate type definitions between utils_types and value_types.
- Zig-style naming, comptime where C used macros, remove C-order fidelity comments.
- **Do not start until Step 7 is green** (or user explicitly wants refactor-only work).

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
- Reference `.c` files not in build — port diffs only
- Already-ported Zig engine modules unless fixing build break or Step 8 refactor
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Steps 0–6 complete (all 7 engine modules on Zig).
- Leaf modules cutils, dtoa, libm, readline are on Zig.
- Host apps example and mqjs are on Zig.
- Engine: 7 Zig modules (utils, value, runtime, lexer, parser, gc, builtins).
- engine_c_sources is empty — zero engine C compiled.
- Reference C kept but not compiled: all mquickjs_*.c split files.
- Last green: uncommitted handoff 12 (builtins port); parent commit 8649a67.
- Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 7 — port stdlib codegen (mquickjs_build.c) to Zig

Goal: Replace the C host tools that generate stdlib headers/embed files:
  mquickjs_build.c + mqjs_stdlib.c + example_stdlib.c
So build.zig no longer compiles these as C host executables.

Read first:
- handoff.md (Sections 1, 2 Step 6 builtins, 5 Step 7)
- mquickjs_build.c — build_atoms, JSPropDef/JSClassDef table emission
- mqjs_stdlib.c, example_stdlib.c — stdlib table definitions
- build.zig — mqjs_stdlib_tool / example_stdlib_tool blocks (~lines 105–130, 266–280)
- Generated outputs: mqjs_stdlib.h, example_stdlib.h, *_stdlib_embed.c

Implementation sketch:
1. Create mquickjs_build_lib.zig (shared codegen) + thin host roots if needed.
2. Port build_atoms and table-walking logic faithfully.
3. Wire build.zig to use Zig host tools instead of C addCSourceFiles for stdlib codegen.
4. Verify generated headers/embed .c are equivalent (or accept intentional diffs with test proof).
5. Do NOT refactor engine modules unless build breaks.

Constraints:
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)
- Build/test only with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall
- Do not create git commits unless I ask
- Faithful port first; idiomatic refactor is Step 8

Test gate:
  export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig
  $ZIG build -Doptimize=ReleaseFast
  $ZIG build test -Doptimize=ReleaseFast
  $ZIG build example -Doptimize=ReleaseFast
  ./zig-out/bin/example tests/test_rect.js
  $ZIG build microbench -Doptimize=ReleaseFast
  bash run-tests.sh

Pay special attention: stdlib tables must still wire all js_* handlers; test_builtin.js is the regression gate.
```

**Alternative tasks:**

- **Softfloat:** Step 2 Phase 2b — `-Dsoftfloat=true`; read handoff Section 5.
- **Docs only:** update README port-status table; commit handoff 12 if user asks.
- **Step 8 refactor:** only if user explicitly requests — analyze extern/import graph first; do not break cycles.
