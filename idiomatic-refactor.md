# Idiomatic Zig Refactor — Agent Workflow

Last updated: 2026-08-14  
Zig version: **0.15.2** (see `.zigversion`)

This document guides agents converting the completed C→Zig port to **idiomatic internal Zig** while preserving the **C ABI** for embedders. Read [`handoff.md`](handoff.md) first for engine internals.

Full step list: [`.cursor/plans/idiomatic_zig_refactor_f450d4a7.plan.md`](../.cursor/plans/idiomatic_zig_refactor_f450d4a7.plan.md) (or workspace plan copy).

---

## 1. Rules (strict)

1. **One step per agent session.** Complete exactly the step named in the task, then stop and wait for review.
2. **Behavior must not change.** Compare against [`archive/c/mquickjs_*.c`](archive/c/) when unsure.
3. **No performance regressions.** After each step, compare timing to the baseline below. Times within normal run-to-run variance are fine; flag anything wildly slower.
4. **Do not run microbench.** It takes too long. Use `time ./run-tests.sh` instead.
5. **Do not create git commits** unless the user explicitly asks.
6. **Minimize scope.** Do not refactor adjacent code “while you're here.”

---

## 2. API boundary (do not idiomatically rename)

### External — keep C-style

| Surface | Location | Notes |
|---------|----------|-------|
| Public header | [`include/mquickjs.h`](include/mquickjs.h) | Stable embedder API; do not change |
| Private header | [`include/mquickjs_priv.h`](include/mquickjs_priv.h) | Macros, mtags, debug flags |
| Engine exports | `src/mquickjs_c_abi.zig` | Thin `export fn` wrappers (~330 symbols); compiled via `mquickjs_engine.zig`
| Host apps | [`src/mqjs.zig`](src/mqjs.zig), [`src/example.zig`](src/example.zig) | Use `@cImport("mquickjs.h")`; stay C-style |
| Variadic C ABI | `JS_ThrowError`, `js_parse_error`, `js_vprintf`, … | Keep C calling convention at boundary |
| JSValue encoding | Tagged pointer `(ptr + 1)` | Do **not** redesign; ReleaseFast/Small only |

### Internal — target idiomatic Zig

| Surface | Location |
|---------|----------|
| Implementation | `src/*_lib.zig` |
| Layouts/helpers | `src/*_types.zig`, `src/mquickjs_internal.zig` |
| Cross-module calls | Currently `extern fn`; migrate to `@import` after Step 5 |

### Public functions in `include/mquickjs.h` (must remain linkable with C names)

Context lifecycle: `JS_NewContext`, `JS_NewContext2`, `JS_FreeContext`, `JS_SetContextOpaque`, `JS_GetContextOpaque`, `JS_SetInterruptHandler`, `JS_SetRandomSeed`, `JS_SetLogFunc`

Values: `JS_NewFloat64`, `JS_NewInt32`, `JS_NewUint32`, `JS_NewInt64`, `JS_NewString`, `JS_NewStringLen`, `JS_NewObject`, `JS_NewArray`, `JS_NewObjectClassUser`, `JS_NewCFunctionParams`, `JS_NewDate`, `JS_GetGlobalObject`

Property access: `JS_GetPropertyStr`, `JS_GetPropertyUint32`, `JS_SetPropertyStr`, `JS_SetPropertyUint32`

Type tests/coercion: `JS_IsNumber`, `JS_IsString`, `JS_IsError`, `JS_IsFunction`, `JS_IsArray`, `JS_GetClassID`, `JS_SetOpaque`, `JS_GetOpaque`, `JS_ToString`, `JS_ToCString`, `JS_ToCStringLen`, `JS_ToInt32`, `JS_ToUint32`, `JS_ToInt32Sat`, `JS_ToNumber`

Exceptions: `JS_Throw`, `JS_ThrowError`, `JS_ThrowOutOfMemory`, `JS_HasException`, `JS_GetException`

Execution: `JS_Parse`, `JS_Run`, `JS_Eval`, `JS_Call`, `JS_PushArg`, `JS_StackCheck`, `JS_GC`

GC refs: `JS_PushGCRef`, `JS_PopGCRef`, `JS_AddGCRef`, `JS_DeleteGCRef`

Bytecode: `JS_PrepareBytecode`, `JS_PrepareBytecode64to32`, `JS_RelocateBytecode`, `JS_RelocateBytecode2`, `JS_IsBytecode`, `JS_LoadBytecode`

Debug: `JS_PrintValue`, `JS_PrintValueF`, `JS_DumpValue`, `JS_DumpValueF`, `JS_DumpMemory`

Inline macros in the header (`JS_IsInt`, `JS_IsPtr`, `JS_NewBool`, …) are reproduced as Zig helpers in types modules — keep equivalent semantics.

Engine-only symbols exported beyond `mquickjs.h` (parser internals, regexp, heap helpers, etc.) keep their current `export fn` names in `mquickjs_c_abi.zig`.

---

## 3. Verification gate (run after every step)

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig   # adjust if needed

$ZIG build -Doptimize=ReleaseFast
$ZIG build test -Doptimize=ReleaseFast
$ZIG build example -Doptimize=ReleaseFast
time ./run-tests.sh
$ZIG build -Doptimize=ReleaseFast -Dsoftfloat=true && time ./run-tests.sh
```

**Do not run** `zig build microbench` or `tests/microbench.js`.

---

## 4. Performance baseline

Recorded at refactor start (ReleaseFast, `./run-tests.sh`):

| Metric | Baseline (2026-08-13) |
|--------|------------------------|
| real   | **0.02 s** (consistent across 3 runs) |
| user   | **0.02 s** |
| sys    | **0.00 s** |

These tests are short smoke tests; absolute times are less meaningful than **large unexpected deltas** (e.g. 0.02 → 0.10 s). Normal variance between runs is ±0.01 s or less on this suite.

After structural steps (5, 6, 8b), note the new `time ./run-tests.sh` result in your session report.

Step 5 timing (2026-08-14, ReleaseFast): **real 0.028 s** (softfloat: **0.030 s**). Within run-to-run variance of the 0.02–0.029 s recent range.

Step 6a timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 6b timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 6c timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.03 s**). No regression.

Step 6d timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 6e timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 6f timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 6g timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 7a timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 7b timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 7c timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 7d–7g timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8a timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8b timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8c timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8d timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8e timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8f timing (2026-08-14, ReleaseFast): **real 0.02 s** (softfloat: **0.02 s**). No regression.

Step 8g timing (2026-08-14, ReleaseFast): **real 0.027 s** (softfloat: **0.027 s**). No regression.

Step 8h timing (2026-08-14, ReleaseFast): **real 0.027 s** (softfloat: **0.027 s**). No regression.

Step 8i timing (2026-08-14, ReleaseFast): **real 0.027 s** (softfloat: **0.026 s**). No regression.

---

## 5. Step index (quick reference)

| Step | Scope |
|------|-------|
| **0** | This doc + baseline timing (**done**) |
| **1** | `cutils_lib.zig` idiomatic cleanup (**done**) |
| **2** | `dtoa_lib.zig` (**done**) |
| **3** | `libm_lib.zig` idiomatic cleanup (**done**) |
| **4** | Consolidate types + `mquickjs_internal.zig` accessors (**done**) |
| **5** | Single engine compilation unit + `mquickjs_c_abi.zig` (**done**) |
| **6a** | `mquickjs_gc_lib.zig` — replace 3 value-only `extern fn` with `@import` (**done**) |
| **6b** | `mquickjs_lexer_lib.zig` — replace 10 `extern fn` with `@import` (**done**) |
| **6c** | `mquickjs_utils_lib.zig` — replace 18 `extern fn` with `@import`; `js_lrint` stays extern (libm is separate object) (**done**) |
| **6d** | `mquickjs_value_lib.zig` — replace 12 `extern fn` with `@import` (**done**) |
| **6e** | `mquickjs_runtime_lib.zig` — replace 46 `extern fn` with `@import` (`utils`, `gc`, `value`, `builtins`); `js_lrint`/`js_fmod`/`js_pow` stay extern; `@call(.never_inline)` shims for `js_get_short_float`/`JS_NewInt32`/`JS_NewUint32`; C-equivalent `intFromFloat`/`JS_ToUint32` (**done**) |
| **6f** | `mquickjs_parser_lib.zig` — replace 40 `extern fn` with `@import` (`lexer`, `value`, `utils`, `runtime`, `builtins`, `dtoa`); `opcode_info` → `rt.opcode_info_data`; only `setjmp` stays extern (**done**) |
| **6g** | `mquickjs_builtins_lib.zig` — replace 86 `extern fn` with `@import` (`parser`, `lexer`, `value`, `runtime`); `js_pow`/`js_atan2` stay extern (libm); type casts for string_buffer/`js_function_get_length_name1`; rename shadowing params in regexp capture helpers (**done**) |
| **7a** | Shared `get_u8`/`get_u16`/`get_u32`/`put_u16`/`put_u32` in `mquickjs_internal.zig`; shared `pushValue`/`popValue` in `mquickjs_utils_lib.zig`; migrate `mquickjs_gc_lib.zig` — remove local `cx`, use `mc.ctxExt` (**done**) |
| **7b** | Migrate `mquickjs_lexer_lib.zig` — remove local `pushValue`/`popValue`, use `utils.pushValue`/`utils.popValue` (**done**) |
| **7c** | Migrate `mquickjs_value_lib.zig` — remove local `cx`/`pushValue`/`popValue`, use `mc.ctxExt` and `utils.pushValue`/`utils.popValue` (**done**) |
| **7d** | Migrate `mquickjs_runtime_lib.zig` — remove local `cx`/`pushValue`/`popValue`/`get_u16`/`get_u32`, use shared helpers (**done**) |
| **7e** | Migrate `mquickjs_parser_lib.zig` — remove local `cx`/`pushValue`/`popValue`/byte readers, use shared helpers (**done**) |
| **7f** | Migrate `mquickjs_builtins_lib.zig` — remove local `cx`/`pushValue`/`popValue`/byte readers, use shared helpers (**done**) |
| **7g** | Migrate `mquickjs_utils_lib.zig` — remove local `cx`, use `mc.ctxExt` (**done**) |
| **8a** | Split `mquickjs_builtins_regexp_lib.zig` from `mquickjs_builtins_lib.zig` (**done**) |
| **8b** | Split `mquickjs_builtins_std_lib.zig` (Math/TypedArray/Date/Global/JSON) from `mquickjs_builtins_lib.zig` (**done**) |
| **8c** | Split `mquickjs_runtime_coerce_lib.zig` (coercion/slow paths/closures) from `mquickjs_runtime_lib.zig` (**done**) |
| **8d** | Split `mquickjs_runtime_call_lib.zig` (`JS_Call` VM + frame helpers) from `mquickjs_runtime_lib.zig` (**done**) |
| **8e** | Split `mquickjs_parser_emit_lib.zig` (bytecode emit/pc2line/var/lvalue helpers) from `mquickjs_parser_lib.zig` (**done**) |
| **8f** | Split `mquickjs_parser_expr_lib.zig` (expression parser) from `mquickjs_parser_lib.zig` (**done**) |
| **8g** | Split `mquickjs_parser_stmt_lib.zig` (statement parser) from `mquickjs_parser_lib.zig` (**done**) |
| **8h** | Split `mquickjs_builtins_array_lib.zig` (Array builtins) from `mquickjs_builtins_lib.zig` (**done**) |
| **8i** | Split `mquickjs_builtins_string_lib.zig` (String builtins) from `mquickjs_builtins_lib.zig` (**done**) |
| **9a–9b** | Optional: reduce internal `@cImport` (**next**) |
| **10** | Update `handoff.md` and `README.md` |

---

## 6. Agent prompt template

```
Convert microquickjs to idiomatic Zig (one refactor step only).

Read handoff.md and idiomatic-refactor.md first.

Your task: Execute Step N — [description from plan].

Rules:
- Internal code only; keep C ABI exports unchanged
- Do not change JSValue tagged-pointer representation
- Do not run microbench; use time ./run-tests.sh for perf check
- Run the full verification gate before finishing
- Stop after this step; do not start the next step

Do not create git commits unless I ask.
```

---

## 7. Current architecture (after Step 5)

One `mquickjs_engine` object. `_lib` files still use `extern fn` for circular deps (Step 6 migrates those to `@import`):

```
mquickjs_engine.zig  @imports all *_lib.zig + mquickjs_c_abi.zig
mquickjs_c_abi.zig   consolidated export fn symbols (never_inline into *_lib)
```

cutils / dtoa / libm / readline remain separate objects.
