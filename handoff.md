# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-12  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`

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

### Not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Steps 6–8** | Engine module ports, host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C engine (7 files):
│     mquickjs_utils.c, mquickjs_value.c, mquickjs_runtime.c,
│     mquickjs_lexer.c, mquickjs_parser.c, mquickjs_gc.c, mquickjs_builtins.c
├── Shared engine header: mquickjs_internal.h
├── Zig objects: cutils, dtoa, libm, readline (+ readline_tty)
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs.  
**Still C:** 7 engine `.c` files + stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`).  
**Reference only (not compiled):** `archive/mquickjs_monolith.c`, `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

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
| [`libm_softfp.c`](libm_softfp.c) | **New** — auxiliary C: sf32 normalize + sf64 softfp templates, 3 wrapper exports |
| [`libm_softfp.h`](libm_softfp.h) | **New** — declarations for Zig `extern fn` bindings |
| [`build.zig`](build.zig) | `libm_obj` with Zig root + `libm_softfp.c`; `libm.c` removed from `engine_c_sources` |
| [`libm.c`](libm.c) | **Kept for reference** — not compiled |

**Excluded from Phase 2a (still in C reference only):**

- `#ifdef USE_SOFTFLOAT` compiler-rt wrappers (`__adddf3`, etc.)
- Softfloat `js_sqrt` / alternate `js_rem_pio2`
- Full `__kernel_tan` path (`USE_TAN_SHORTCUT` tan via `js_sin_cos` is ported)

### Step 3 — example port

| File | Change |
|------|--------|
| [`example.zig`](example.zig) | **New** — ~343 lines; `pub fn main()` + 14 `export fn` host callbacks |
| [`example_host_decls.h`](example_host_decls.h) | **New** — forward declarations for host callbacks (linker resolution) |
| [`example_stdlib_embed.c`](example_stdlib_embed.c) | **New** — embeds generated `example_stdlib.h` as C (see discoveries below) |
| [`build.zig`](build.zig) | `example_exe` root = `example.zig`; compiles `example_stdlib_embed.c` + engine C sources; links runtime objects |
| [`example.c`](example.c) | **Kept for reference** — not compiled |
| [`README.md`](README.md) | example marked as ported |

### Step 4 — mqjs port

| File | Change |
|------|--------|
| [`mqjs.zig`](mqjs.zig) | **New** — ~826 lines; full REPL CLI (was 3-line stub) |
| [`mqjs_host_decls.h`](mqjs_host_decls.h) | **New** — forward declarations for 8 host callbacks |
| [`mqjs_stdlib_embed.c`](mqjs_stdlib_embed.c) | **New** — embeds generated `mqjs_stdlib.h` as C |
| [`build.zig`](build.zig) | `mqjs` root = `mqjs.zig`; compiles `mqjs_stdlib_embed.c` + engine C sources; links readline_obj |
| [`readline.zig`](readline.zig) | Removed circular `@import("mqjs.zig")` (unused `readline_find_completion` binding) |
| [`readline.zig`](readline.zig), [`readline_tty.zig`](readline_tty.zig) | Added `pub` on `term_colors`, `readline_tty`, `readline_is_interrupted` for cross-module access |
| [`mqjs.c`](mqjs.c) | **Kept for reference** — not compiled |
| [`README.md`](README.md) | mqjs marked as ported |

**mqjs.zig features ported:** `js_print`, `js_gc`, `js_date_*`, `js_performance_now`, `js_load`, `js_setTimeout`/`js_clearTimeout`, REPL with syntax highlighting, CLI arg parsing, bytecode compile (`-o`/`-m32`), `-b` bytecode load, `-I` includes, `--memory-limit`, `readline_find_completion` (empty export).

### Step 5 — split mquickjs.c into 7 C files

**Goal achieved:** Mechanical split of the ~18,366-line engine monolith into 7 linkable C translation units with zero behavior change. Public API unchanged (`mquickjs.h`, `mquickjs_priv.h` untouched).

| File | ~Lines | Monolith line ranges | Responsibility |
|------|--------|----------------------|----------------|
| [`mquickjs_utils.c`](mquickjs_utils.c) | 1,076 | 436–965, 6646–7157 | GC-ref API, heap alloc/free/shrink, printf/snprintf, `#ifdef JS_DUMP` debug printers |
| [`mquickjs_value.c`](mquickjs_value.c) | 2,542 | 965–3544 | JSValue primitives, strings, objects, properties, atoms, `JS_NewContext*`, stdlib init |
| [`mquickjs_runtime.c`](mquickjs_runtime.c) | 3,135 | 3545–6641 | Context helpers, type coercion, operators, closures, **`JS_Call` interpreter loop** |
| [`mquickjs_lexer.c`](mquickjs_lexer.c) | 758 | 7602–7743, 7749–8329 | Token enum, `JSParseState`/`JSToken`/`BlockEnv`, `next_token`, parse error helpers |
| [`mquickjs_parser.c`](mquickjs_parser.c) | 3,740 | 7337–7601, 8330–11831 | Bytecode emit (`emit_*`), expression/statement parser, `JS_Parse`/`JS_Run`/`JS_Eval`, JSON parse |
| [`mquickjs_gc.c`](mquickjs_gc.c) | 1,198 | 11833–13009 | `get_mblock_size`, mark/compact GC, `JS_GC`, bytecode prepare/load/relocate |
| [`mquickjs_builtins.c`](mquickjs_builtins.c) | 5,311 | 13011–18366 | All `js_*` builtins + regexp compile/exec |

| File | Change |
|------|--------|
| [`mquickjs_internal.h`](mquickjs_internal.h) | **New** — ~1,323 lines; shared internal structs, macros, opcode/parser/regexp types, inline helpers, ~483 cross-module prototypes |
| [`split_mquickjs.py`](split_mquickjs.py) | **New** — regeneration script; reads `archive/mquickjs_monolith.c`, writes all 7 `.c` files + `mquickjs_internal.h` |
| [`build.zig`](build.zig) | `engine_c_sources` lists 7 split files (not monolith) |
| [`archive/mquickjs_monolith.c`](archive/mquickjs_monolith.c) | **Moved from root** — original monolith, reference/backup only |
| [`README.md`](README.md) | mquickjs row updated to "7 C files" |

**Per-module `.h` pairs** from the original plan were consolidated into `mquickjs_internal.h` (single shared internal header). This simplified linkage; optional thin per-module headers can be added later if desired.

**Regenerate split files:**

```sh
python3 split_mquickjs.py
```

---

## 3. Discoveries / Decisions

### Porting pattern (leaf modules — cutils, dtoa, libm)

1. **Split lib + exports:** `<module>_lib.zig` (implementation) + `<module>.zig` (thin `export fn` for C callers).
2. **Build:** `b.addObject()` for export root; remove `.c` from `addEngineCSources`; link via `addRuntimeObjects`.
3. **Internal Zig imports:** Always `@import("<module>_lib.zig")`, never the export root.

### App port pattern (example, mqjs — Steps 3–4)

1. **Executable root:** single `*.zig` with `pub fn main()` + `export fn` host callbacks for stdlib function-pointer tables.
2. **Do NOT `@cImport` generated `*_stdlib.h` directly** — `JS_ROM_VALUE` uses runtime pointer math; Zig `@cImport` fails at comptime. Instead compile a tiny `*_stdlib_embed.c` that `#include`s the generated header (same as C did at bottom of `example.c`/`mqjs.c`).
3. **Host callback forward declarations:** `*_host_decls.h` included before `*_stdlib.h` in the embed `.c` file; callbacks are `export fn` in the Zig executable.
4. **`@cImport` in app:** only `mquickjs.h` (+ libc headers). Access stdlib via `extern "C" const js_stdlib: c.JSSTDLibraryDef;` defined by embed `.c`.
5. **Variadic C macros:** `JS_ThrowTypeError` etc. do not translate through `@cImport`. Call `JS_ThrowError(ctx, JS_CLASS_TYPE_ERROR, msg)` via a Zig helper instead.
6. **Avoid duplicate symbols:** do not `@import` a Zig object module (e.g. `readline.zig`) from an executable that also links that module's object file. Use `@cImport` of the `.h` for types/externs, or link-only.

### Step 5 split-specific notes

| Topic | Detail |
|-------|--------|
| Static promotion | ~200+ `static` helpers were promoted to file-scope and declared in `mquickjs_internal.h`. `split_mquickjs.py` strips `static` from function definitions only (not static data arrays). |
| Inline helpers | `JS_NewTailCall`, `JS_IsIntOrShortFloat`, `utf8_char_len`, `hash_prop`, `find_own_property_inlined`, `unicode_is_space*` live as `static` inline/force_inline in `mquickjs_internal.h`; excluded from owning `.c` files via `EXCLUDE_LINES`. |
| Overlap avoidance | Parser range ends at 7601 (before lexer-owned `get_line_col`/`js_parse_error` at 7602+). Lexer owns those helpers. |
| Table definitions | `js_mtag_name[]` injected into utils.c; `opcode_info[]` into runtime.c; `reopcode_info[]` into builtins.c after split. |
| Regeneration | Always edit `archive/mquickjs_monolith.c` or adjust `split_mquickjs.py` ranges, then re-run script. Do not hand-edit split files unless fixing script bugs. |
| Public headers | `mquickjs.h` and `mquickjs_priv.h` were **not modified**. All internal types moved to `mquickjs_internal.h`. |

### Zig 0.15.2 quirks (hit during Steps 3–4)

| Topic | Detail |
|-------|--------|
| `opaque` keyword | Reserved in Zig 0.15 — cannot use as parameter name |
| `extern` syntax | `extern "C" const js_stdlib: c.JSSTDLibraryDef;` (not old `extern const c.Type name`) |
| `std.process.argv` | Removed — use `std.process.argsAlloc(allocator)` |
| `posix.clock_gettime` | Returns `timespec` directly (`.sec`/`.nsec`, not `.tv_sec`/`.tv_nsec`); no output pointer |
| `JS_NewContext` return | Optional pointer — unwrap with `.?` |
| `@intCast` | Often needs explicit result type: `@as(u64, @intCast(x))` |
| `malloc` → typed ptr | Use `@ptrCast(@alignCast(c.malloc(...)))` |
| C `fprintf` with slices | Pass `@as([*:0]const u8, @ptrCast(slice.ptr))` for `%s` |

### libm-specific notes (Phase 2a)

| Topic | Detail |
|-------|--------|
| Softfp bridge | Even hard-float libm needs `cvt_sf64_i32`, `fmod_sf64`, `mul_u64` from [`softfp_template.h`](softfp_template.h). Implemented as [`libm_softfp.c`](libm_softfp.c) compiled into `libm_obj`. |
| sf32 include required | sf64 template references sf32 helpers. **Both** includes needed (sf32 with `F_NORMALIZE_ONLY`, then sf64 full). |
| Hardware sqrt | `@sqrt(x)` on x86_64 / aarch64 / x86; bit-by-bit fallback elsewhere. |
| No `@fabs` in Zig 0.15.2 | Use `@abs(x)` for `f64`. |
| `std.math.copysign` | Two-arg API: `std.math.copysign(magnitude, sign)`. |

### dtoa-specific fixes (Step 1 — still relevant)

| Issue | Fix |
|-------|-----|
| Duplicate symbols | Split `cutils_lib.zig` / `cutils.zig`; never import export roots from other Zig modules |
| Overlapping memmove in dtoa | `overlap_move_left()` helper |

### Architectural decisions

- **libm Phase 2b:** Add `-DUSE_SOFTFLOAT` to `libm_softfp.c` flags + Zig `build_options`; export compiler-rt symbols; port softfloat code paths. Do **not** use `archive/src-first-attempt/`.
- **Engine port (Steps 6–8):** Port split C modules to Zig one at a time, smallest-first. Recommended order matches split: utils → value → runtime → lexer → parser → gc → builtins.
- **Makefile:** Legacy only; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall` (Debug/ReleaseSafe abort in `build.zig`).

### Dependencies

```
dtoa_lib.zig          →  cutils_lib.zig
readline.zig          →  cutils_lib.zig, readline_tty.zig
readline_tty.zig      →  cutils_lib.zig, readline.zig
libm_lib.zig          →  libm_softfp.c (extern: libm_cvt_sf64_i32, libm_fmod_sf64, libm_mul_u64)
libm.zig              →  libm_lib.zig
example.zig           →  @cImport(mquickjs.h); links 7 engine .c files + example_stdlib_embed.c + runtime objects
mqjs.zig              →  @cImport(mquickjs.h, readline.h, readline_tty.h); links 7 engine .c files + mqjs_stdlib_embed.c + runtime objects + readline_obj
mquickjs_*.c          →  mquickjs_internal.h, dtoa.h, libm.h, cutils.h (satisfied by Zig objects + headers)
split_mquickjs.py     →  archive/mquickjs_monolith.c (source of truth for regeneration)
```

---

## 4. Verification

All run with `/home/vexcess/zig-x86_64-linux-0.15.2/zig` and `-Doptimize=ReleaseFast`:

```sh
zig build -Doptimize=ReleaseFast
zig build test -Doptimize=ReleaseFast
zig build example -Doptimize=ReleaseFast
./zig-out/bin/example tests/test_rect.js
zig build microbench -Doptimize=ReleaseFast
bash run-tests.sh
```

**Results after Step 5 (2026-08-12):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` path included)
- `zig build example` + `tests/test_rect.js` — pass
- `zig build microbench` — pass (~3575 ms total)
- `run-tests.sh` — pass (all JS tests, bytecode round-trip, test_rect, mandelbrot)

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)

---

## 5. Next Steps

### Recommended order

1. **Step 6 — port engine modules to Zig** (one module at a time, test gate after each):
   1. `mquickjs_utils.c` → `mquickjs_utils_lib.zig` + `mquickjs_utils.zig` (smallest, fewest deps)
   2. `mquickjs_value.c` → value module
   3. `mquickjs_runtime.c` → runtime/interpreter (largest, most complex)
   4. `mquickjs_lexer.c` → lexer
   5. `mquickjs_parser.c` → parser/compiler
   6. `mquickjs_gc.c` → GC
   7. `mquickjs_builtins.c` → builtins + regexp (largest file)
2. **Step 2 Phase 2b — libm softfloat** — optional parallel track; needed only for `-Dsoftfloat=true` targets.
3. **Steps 7–8** — port stdlib codegen (`mquickjs_build.c`); idiomatic refactor.

### Step 6 sketch (port first engine module — utils)

**Goal:** Port `mquickjs_utils.c` to Zig following the established leaf-module pattern (`*_lib.zig` + `*.zig` C exports).

**Read first:**

- [`mquickjs_utils.c`](mquickjs_utils.c) — GC refs, heap alloc, printf, debug dumps
- [`mquickjs_internal.h`](mquickjs_internal.h) — types and cross-module prototypes utils depends on
- [`cutils_lib.zig`](cutils_lib.zig) / [`dtoa_lib.zig`](dtoa_lib.zig) — reference for lib+export split pattern
- [`build.zig`](build.zig) — `addEngineCSources`, `addRuntimeObjects`, `engine_c_sources`

**Approach:**

1. Create `mquickjs_utils_lib.zig` with Zig implementations of utils functions.
2. Create `mquickjs_utils.zig` with thin `export fn` wrappers for symbols other C engine modules call.
3. Remove `mquickjs_utils.c` from `engine_c_sources`; add `mquickjs_utils_obj` Zig object.
4. Keep `mquickjs_internal.h` as shared header until all modules are ported (or split incrementally).
5. Run full test gate after each module port.

**Do not:** port multiple modules at once; change behavior; touch app files unless build breaks.

### Step 2 Phase 2b sketch (libm softfloat)

**Goal:** Make `zig build -Dsoftfloat=true` work.

**Work:** Extend [`libm_softfp.c`](libm_softfp.c) with `-DUSE_SOFTFLOAT`; port softfloat paths in [`libm_lib.zig`](libm_lib.zig); export compiler-rt symbols from C bridge; wire `build.zig` option.

**Reference:** [`libm.c`](libm.c) `#ifdef USE_SOFTFLOAT` blocks (not `archive/src-first-attempt/`).

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

- [`archive/mquickjs_monolith.c`](archive/mquickjs_monolith.c) — original engine monolith; edit only if fixing split script source
- [`split_mquickjs.py`](split_mquickjs.py) — regeneration script; edit when adjusting split boundaries
- [`mquickjs.h`](mquickjs.h), [`mquickjs_priv.h`](mquickjs_priv.h) — public API; avoid changes unless required
- [`archive/src-first-attempt/`](archive/src-first-attempt/) — stale; reference only
- [`example.c`](example.c), [`mqjs.c`](mqjs.c), [`dtoa.c`](dtoa.c), [`libm.c`](libm.c) — reference for port diffs
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Steps 0–5.
- Leaf modules cutils, dtoa, libm, readline are on Zig.
- Host apps example and mqjs are on Zig.
- Engine split into 7 C files (mquickjs_utils/value/runtime/lexer/parser/gc/builtins.c)
  plus shared mquickjs_internal.h.
- Original monolith archived at archive/mquickjs_monolith.c.
- Regeneration: python3 split_mquickjs.py
- Stdlib codegen stays C.
- Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 6 — port the first engine module (mquickjs_utils.c) to Zig

Goal: Port mquickjs_utils.c following the established *_lib.zig + *.zig export pattern.
One module at a time; zero behavior change; full test gate after port.

Read first:
- handoff.md (Sections 1, 2 Step 5, 3, 5 Step 6 sketch)
- mquickjs_utils.c
- mquickjs_internal.h (types/prototypes utils uses)
- cutils_lib.zig / dtoa_lib.zig (reference port pattern)
- build.zig (engine_c_sources, addEngineCSources, addRuntimeObjects)

Implementation:
1. Create mquickjs_utils_lib.zig with Zig implementations.
2. Create mquickjs_utils.zig with thin export fn wrappers for cross-module C symbols.
3. Replace mquickjs_utils.c in engine_c_sources with mquickjs_utils Zig object.
4. Do NOT port other engine modules yet. Do NOT touch example.zig, mqjs.zig, or already-ported leaf modules.
5. Keep mquickjs_internal.h until more modules are ported (or trim incrementally).

Constraints:
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)
- Build/test only with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall
- Do not create git commits unless I ask

Test gate:
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build -Doptimize=ReleaseFast
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build test -Doptimize=ReleaseFast
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build example -Doptimize=ReleaseFast
  ./zig-out/bin/example tests/test_rect.js
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build microbench -Doptimize=ReleaseFast
  bash run-tests.sh
```

**Alternative tasks:**

- **Next engine module:** after utils, port `mquickjs_value.c` (Step 6 continued).
- **Softfloat first:** replace task with "Step 2 Phase 2b — libm softfloat" and read handoff Section 5 Phase 2b sketch.
