# microquickjs Zig — Debugging Handoff

Last updated: 2026-08-13  
Zig version: **0.15.2** (see `.zigversion`)

This document is for agents debugging the **completed** C→Zig port. The port is a faithful, line-by-line translation — not idiomatic Zig. Treat bugs as likely port artifacts; compare against the C reference when stuck.

---

## 1. Project overview

MicroQuickJS is a small JavaScript engine for embedded systems. This repo is a full Zig rewrite of the original C engine. Everything is compiled as Zig object files linked into two executables:

| Binary | Root source | Purpose |
|--------|-------------|---------|
| `mqjs` | `src/mqjs.zig` | REPL / CLI |
| `example` | `src/example.zig` | Demo with custom `Rectangle` classes |

**Zero compiled C translation units** — `grep addCSourceFiles build.zig` is empty. C sources under `archive/c/` are reference only.

Public API headers (`include/mquickjs.h`, `include/mquickjs_priv.h`) are still `@cImport`'d for type definitions. Engine logic lives entirely in Zig.

---

## 2. Environment & build

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig   # if zig not on PATH
```

### Required optimize mode

**Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall`.**  
`build.zig` rejects Debug and ReleaseSafe.

Reason: the engine uses **tagged-pointer JSValues** (`value = ptr + 1`). `valueToPtr` produces odd addresses via `@ptrFromInt`, which panics under ReleaseSafe alignment checks. Debug mode also fails to compile `js_vprintf` (`@cVaArg` / `VaListX86_64` error).

### Build commands

```sh
$ZIG build -Doptimize=ReleaseFast              # build mqjs
$ZIG build example -Doptimize=ReleaseFast      # build example
$ZIG build test -Doptimize=ReleaseFast         # run built-in JS tests via mqjs
$ZIG build -Doptimize=ReleaseFast -Dsoftfloat=true   # soft-float libm path
```

### Test commands
Do not test with the microbenchmark test. It takes too long to run
```sh
bash run-tests.sh                               # broader smoke tests
./zig-out/bin/mqjs tests/test_language.js       # single test
./zig-out/bin/example tests/test_rect.js        # example-specific test
./zig-out/bin/mqjs -o out.bin tests/test_builtin.js && ./zig-out/bin/mqjs -b out.bin  # bytecode round-trip
```

Test files: `tests/test_{builtin,closure,language,loop}.js`, `tests/test_rect.js`, `tests/mandelbrot.js`,.

Octane benchmark (`zig build octane`) needs [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz) — not included.

---

## 3. Codebase layout

All source is under `src/`. Generated artifacts land in `.zig-cache/` (headers + stdlib data).

```
src/
├── mqjs.zig / example.zig          # host executables
├── mqjs_stdlib.zig / example_stdlib.zig   # build-time stdlib codegen tools
├── mqjs_stdlib_tables.zig / example_stdlib_tables.zig
├── mquickjs_build_{types,lib}.zig  # stdlib atom/class/prop emitter
│
├── cutils.zig + cutils_lib.zig     # low-level helpers
├── dtoa.zig + dtoa_lib.zig           # float→string conversion
├── libm.zig + libm_lib.zig + libm_softfp.zig   # math (-Dsoftfloat=true)
├── readline.zig + readline_tty.zig   # REPL terminal (mqjs only)
│
└── mquickjs_{utils,value,runtime,lexer,parser,gc,builtins}/
      ├── *_types.zig   # struct layouts, constants, helpers
      ├── *_lib.zig     # implementation (bulk of logic)
      └── *.zig         # thin export fn C ABI wrappers
```

### Generated at build time

| Artifact | Producer | Used by |
|----------|----------|---------|
| `mquickjs_atom.h` | `mqjs_stdlib -a` | `@cImport` in types modules |
| `mqjs_stdlib.h` / `example_stdlib.h` | stdlib tools | reference / headers |
| `mqjs_stdlib_data.zig` / `example_stdlib_data.zig` | stdlib tools `-z` | imported by mqjs/example; call `relocate()` in `main` |

### Link layout

`build.zig` → `addRuntimeObjects()` links 7 engine objects + cutils + dtoa + libm (+ readline for mqjs).

---

## 4. Module responsibilities

Use this map to narrow down where a bug lives.

| Module | Key symbols / areas | When to look here |
|--------|---------------------|-------------------|
| **utils** | heap alloc, GC refs, `js_printf`, `JS_ThrowError`, debug dumps | Crashes in allocation, printf, error formatting |
| **value** | `JSValue`, strings, objects, properties, atoms, `JS_MakeUniqueString` | Type coercion, property access, string ops, atom table |
| **runtime** | `JS_Call` interpreter, coercion, operators, closures | Wrong runtime results, interpreter bugs, stack/frame issues |
| **lexer** | `next_token`, `js_parse_ident`, `js_parse_error` | Tokenization, parse error messages |
| **parser** | bytecode emit, `JS_Parse`/`JS_Run`/`JS_Eval`, PARSE coroutines | Syntax handling, bytecode generation, compile errors |
| **gc** | mark/compact, `JS_GC`, bytecode save/load/relocate | Memory corruption, GC crashes, stale pointers |
| **builtins** | all `js_*` builtins, regexp parse/exec | Built-in method behavior, RegExp |

### Execution pipeline

```
JS source → lexer (tokens) → parser (bytecode) → runtime (JS_Call interpreter) → builtins
                                      ↑                              ↓
                                   value (JSValue ops)          gc (collection)
```

---

## 5. Critical internals (read before debugging)

### Tagged-pointer JSValues

Defined in `include/mquickjs_priv.h`, implemented in `src/mquickjs_utils_types.zig`:

```zig
// valueToPtr / valueFromPtr — pointers stored as (ptr + 1)
pub fn valueToPtr(val: c.JSValue) *anyopaque {
    return @ptrFromInt(@as(usize, @intCast(val - 1)));
}
pub fn valueFromPtr(ptr: *anyopaque) c.JSValue {
    return @as(c.JSWord, @intCast(@intFromPtr(ptr))) + 1;
}
```

Hundreds of call sites use `@ptrCast(@alignCast(mc.valueToPtr(val)))`. This is intentional C-style UB preserved in the port. **Do not "fix" alignment without understanding the full JSValue model.**

Heap blocks have a 4-bit mtag in the header (`JS_MTAG_OBJECT`, `JS_MTAG_STRING`, etc.). See `js_get_mtag()` in utils.

### Three-file module pattern

| File | Role |
|------|------|
| `*_types.zig` | Layouts, constants, small helpers. Downstream modules re-export upstream types (e.g. `pub const vt = @import("mquickjs_value_types.zig")`). |
| `*_lib.zig` | All logic. Import `_types` and peer `_lib` modules where acyclic; use `extern fn` for circular deps. |
| `*.zig` (root) | Thin `export fn` wrappers for C ABI linkage between object files. |

**Prefer `mquickjs_value_types.zig` layouts** over `mquickjs_utils_types.zig` where they differ.

### Cross-module linking via `extern fn`

Engine modules cannot `@import` each other's `_lib.zig` freely — circular dependencies force link-time `extern fn` calls:

```
runtime_lib  → extern fn ~30 value symbols + builtins
value_lib    → extern fn ~12 runtime symbols + builtins
utils_lib    → extern fn value/runtime/builtins/gc symbols
lexer_lib    → extern fn value/dtoa/builtins
parser_lib   → extern fn lexer/value/runtime/builtins/dtoa
gc_lib       → extern fn value
builtins_lib → extern fn parser/lexer/value/runtime
```

When a symbol is "missing" at link time, add an `export fn` in the provider's root `.zig` or declare `extern fn` in the consumer's `_lib.zig`.

### PARSE coroutines (parser + regexp)

C computed-goto was translated to **labeled `switch` + `continue :sw N`**. States 0–N are resume points; internal loop heads use states ≥ 100. `js_parse_call()` dispatches through `parse_func_table`.

If parser/regexp behavior is wrong, check state numbers and that loop cursors are updated before every `continue :sw` back to a loop head.

### JS_Call interpreter (runtime)

C `goto` labels → `Resume` enum + `outer: while (true)` state machine. The resume variable is named `state` (not `resume` — reserved in Zig).

### Variadic C ABI

- `js_vprintf` / `js_vsnprintf` / `js_snprintf` — `src/mquickjs_utils.zig` + `mquickjs_utils_lib.zig` (`@cVaArg`)
- `js_parse_error` — `src/mquickjs_lexer.zig` (variadic, noreturn, uses `longjmp`)
- `JS_ThrowError` — variadic in utils

### Stdlib embed

Host apps import generated `*_stdlib_data.zig` and **must** call `relocate()` at startup to fix ROM pointer offsets.

---

## 6. Common port pitfalls

| Symptom / area | Likely cause | Fix pattern |
|----------------|--------------|-------------|
| Wrong integer from JSValue | Used raw shift instead of helper | Use `vt.valueGetInt` for negative shorts |
| Exception checks fail | `JS_IsException` semantics | Use `vt.isExactException` or `val == c.JS_EXCEPTION` |
| Alignment panic (ReleaseSafe only) | Tagged pointer via `@ptrFromInt` | Expected — use ReleaseFast; real fix needs JSValue redesign |
| Link error on engine symbol | Missing export/extern pair | Add `export fn` in provider root, `extern fn` in consumer `_lib` |
| Regexp parse crash | Wrong `callconv(.c)` on `re_parse_*` | Must match `parse_func_table` entries |
| Bitwise NOT on alignment mask | Sign extension | Use `~@as(usize, c.JSW - 1)` not `~(c.JSW - 1)` |
| GC 64→32 bytecode shrink | Flags in packed header word | Read via helper fns in `gc_types.zig` |
| `setjmp`/`longjmp` type clash | cimport vs Zig types | Parser uses `extern fn setjmp(env: *anyopaque)` |
| NULL `this_val` in builtins | C passed NULL | Several builtins use `this_val: ?*c.JSValue` |

---

## 7. Debugging workflow

### 1. Reproduce minimally

```sh
$ZIG build -Doptimize=ReleaseFast
./zig-out/bin/mqjs path/to/minimal.js
```

Reduce the JS test case as far as possible. Note whether the bug is parse-time, run-time, or GC-related.

### 2. Locate the module

Use section 4. Parse/compile errors → lexer/parser. Wrong output → runtime/builtins/value. Crash after many allocations → gc.

### 3. Compare against C reference

Original logic is in `archive/c/mquickjs_<module>.c` (split from `archive/mquickjs_monolith.c`). The Zig `_lib.zig` file is a faithful translation — diff behavior against the matching C file.

Key C macros in `include/mquickjs_priv.h`:

```c
#define JS_VALUE_TO_PTR(v)   (void *)((uintptr_t)(v) - 1)
#define JS_VALUE_FROM_PTR(p) (JSWord)((uintptr_t)(p) + 1)
```

### 4. Enable engine debug dumps (optional)

Uncomment defines in `include/mquickjs_priv.h` and rebuild:

| Define | Effect |
|--------|--------|
| `DUMP_EXEC` | Trace bytecode execution |
| `DUMP_FUNC_BYTECODE` | Dump compiled function bytecode |
| `DUMP_REOP` | Dump regexp bytecode |
| `DUMP_GC` | GC tracing |
| `DUMP_TOKEN` | Dump parsed tokens |
| `DEBUG_GC` | GC on every malloc (slow) |

These still work through the Zig port's debug printer functions in utils.

### 5. Verify the test gate

After any fix:

```sh
$ZIG build -Doptimize=ReleaseFast
$ZIG build test -Doptimize=ReleaseFast
$ZIG build example -Doptimize=ReleaseFast
./zig-out/bin/example tests/test_rect.js
bash run-tests.sh
$ZIG build -Doptimize=ReleaseFast -Dsoftfloat=true && bash run-tests.sh
```

### 6. Bisect across modules

Engine objects are separate compilation units. If unsure which module is wrong, add temporary logging via `js_printf` (works at runtime) or compare a specific function against its C counterpart.

---

## 8. Reference material

| Path | Purpose |
|------|---------|
| `archive/c/mquickjs_*.c` | Original C per module — **primary debugging reference** |
| `archive/mquickjs_monolith.c` | Full original source (18k lines) |
| `include/mquickjs.h` | Public API |
| `include/mquickjs_priv.h` | Internal macros, mtags, debug flags |
| `README.md` | User-facing docs, test262 instructions |
| `archive/src-first-attempt/` | **Stale** — do not use |

Regenerate C splits from monolith: `python3 archive/tools/split_mquickjs.py` (rarely needed).

---

## 9. Do not touch without reason

- `include/mquickjs.h`, `include/mquickjs_priv.h` — public/stable API
- `archive/` — reference only; edit only to fix split script source
- `.cursor/plans/` — planning artifacts
- Git commits — only when the user explicitly asks

When fixing bugs, **minimize scope**. Match existing naming and patterns. The codebase is deliberately non-idiomatic to stay diffable against C.

---

## 10. Optional future work (not debugging)

An idiomatic refactor (replace `extern fn` with `@import` where acyclic, collapse duplicate types, Zig naming) has **not** been started. Only do this if the user explicitly requests it — it is separate from bug fixing and risks import cycles between utils/value/runtime/builtins.

---

## 11. Agent prompt (copy-paste)

```
Debug the microquickjs Zig codebase.

Read handoff.md first.

Context:
- Full C→Zig port is complete; all logic is in src/*.zig (zero compiled C).
- Faithful line-by-line translation — compare against archive/c/mquickjs_*.c when stuck.
- Build/test requires -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall.
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)

Your task: [describe the bug or failing test]

Workflow:
1. Reproduce with ./zig-out/bin/mqjs or ./zig-out/bin/example
2. Map symptom to module (utils/value/runtime/lexer/parser/gc/builtins)
3. Compare suspicious function against archive/c/ counterpart
4. Fix minimally; run test gate before finishing

Test gate:
  export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig
  $ZIG build -Doptimize=ReleaseFast
  $ZIG build test -Doptimize=ReleaseFast
  bash run-tests.sh

Do not create git commits unless I ask.
```
