# Idiomatic Zig Refactor — Agent Workflow

Last updated: 2026-08-13  
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
| Engine exports | `src/mquickjs_{utils,value,runtime,lexer,parser,gc,builtins}.zig` | Thin `export fn` wrappers (~330 symbols) |
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

Engine-only symbols exported beyond `mquickjs.h` (parser internals, regexp, heap helpers, etc.) must keep their current `export fn` names until the C ABI layer is explicitly consolidated in Step 5.

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

---

## 5. Step index (quick reference)

| Step | Scope |
|------|-------|
| **0** | This doc + baseline timing (**done**) |
| **1** | `cutils_lib.zig` idiomatic cleanup (**done**) |
| **2** | `dtoa_lib.zig` (**done**) |
| **3** | `libm_lib.zig` idiomatic cleanup (**done**) |
| **4** | Consolidate types + `mquickjs_internal.zig` accessors (**done**) |
| **5** | Single engine compilation unit + `mquickjs_c_abi.zig` |
| **6a–6g** | Replace `extern fn` with `@import` (one module per session) |
| **7a–7g** | Deduplicate `pushValue` / `cx` / `get_u32` boilerplate |
| **8a–8i** | Internal idiomatic cleanup (split large `_lib` files) |
| **9a–9b** | Optional: reduce internal `@cImport` |
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

## 7. Current architecture (pre-refactor)

Seven engine object files linked via `export fn` / `extern fn`:

```
utils ↔ value ↔ runtime ↔ builtins
  ↕       ↕        ↕
 lexer   parser    gc
```

Target (Step 5+): one `mquickjs_engine` object, `@import` between `_lib` modules, consolidated `mquickjs_c_abi.zig` exports.

See the full plan for mermaid diagrams and per-step file lists.
