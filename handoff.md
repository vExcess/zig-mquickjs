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

### Not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Step 5** | Split `mquickjs.c` into ~7 C files | **Not started** |
| Steps 6–8 | Engine module ports, host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C: mquickjs.c only                    (engine monolith — do not port yet)
├── Zig objects: cutils, dtoa, libm, readline (+ readline_tty)
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs.  
**Still C:** `mquickjs.c`, stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`).  
**Reference only (not compiled):** `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

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
| [`build.zig`](build.zig) | `example_exe` root = `example.zig`; compiles `example_stdlib_embed.c` + `mquickjs.c`; links runtime objects |
| [`example.c`](example.c) | **Kept for reference** — not compiled |
| [`README.md`](README.md) | example marked as ported |

### Step 4 — mqjs port

| File | Change |
|------|--------|
| [`mqjs.zig`](mqjs.zig) | **New** — ~826 lines; full REPL CLI (was 3-line stub) |
| [`mqjs_host_decls.h`](mqjs_host_decls.h) | **New** — forward declarations for 8 host callbacks |
| [`mqjs_stdlib_embed.c`](mqjs_stdlib_embed.c) | **New** — embeds generated `mqjs_stdlib.h` as C |
| [`build.zig`](build.zig) | `mqjs` root = `mqjs.zig`; compiles `mqjs_stdlib_embed.c` + `mquickjs.c`; links readline_obj |
| [`readline.zig`](readline.zig) | Removed circular `@import("mqjs.zig")` (unused `readline_find_completion` binding) |
| [`readline.zig`](readline.zig), [`readline_tty.zig`](readline_tty.zig) | Added `pub` on `term_colors`, `readline_tty`, `readline_is_interrupted` for cross-module access |
| [`mqjs.c`](mqjs.c) | **Kept for reference** — not compiled |
| [`README.md`](README.md) | mqjs marked as ported |

**mqjs.zig features ported:** `js_print`, `js_gc`, `js_date_*`, `js_performance_now`, `js_load`, `js_setTimeout`/`js_clearTimeout`, REPL with syntax highlighting, CLI arg parsing, bytecode compile (`-o`/`-m32`), `-b` bytecode load, `-I` includes, `--memory-limit`, `readline_find_completion` (empty export).

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
- **mquickjs (Step 5+):** Split `mquickjs.c` into ~7 C files first, then port module-by-module.
- **Makefile:** Legacy only; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall` (Debug/ReleaseSafe abort in `build.zig`).

### Dependencies

```
dtoa_lib.zig          →  cutils_lib.zig
readline.zig          →  cutils_lib.zig, readline_tty.zig
readline_tty.zig      →  cutils_lib.zig, readline.zig
libm_lib.zig          →  libm_softfp.c (extern: libm_cvt_sf64_i32, libm_fmod_sf64, libm_mul_u64)
libm.zig              →  libm_lib.zig
example.zig           →  @cImport(mquickjs.h); links mquickjs.c + example_stdlib_embed.c + runtime objects
mqjs.zig              →  @cImport(mquickjs.h, readline.h, readline_tty.h); links mquickjs.c + mqjs_stdlib_embed.c + runtime objects + readline_obj
mquickjs.c            →  dtoa.h, libm.h, cutils.h (satisfied by Zig objects + headers)
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

**Results after Steps 3–4 (2026-08-12):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` path included)
- `zig build example` + `tests/test_rect.js` — pass
- `zig build microbench` — pass (~3115 ms total)
- `run-tests.sh` — pass (all JS tests, bytecode round-trip, test_rect, mandelbrot)

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)

---

## 5. Next Steps

### Recommended order

1. **Step 5 — split `mquickjs.c`** (~18k lines) into ~7 logical C files. Prerequisite for engine port. Do not port engine logic to Zig yet.
2. **Step 2 Phase 2b — libm softfloat** — optional parallel track; needed only for `-Dsoftfloat=true` targets.
3. **Steps 6–8** — port split engine modules to Zig one at a time; port stdlib codegen; idiomatic refactor.

### Step 5 sketch (split mquickjs.c)

**Goal:** Mechanical split of monolithic [`mquickjs.c`](mquickjs.c) into ~7 `.c` files with no behavior change. Keep all symbols linkable; update `engine_c_sources` in [`build.zig`](build.zig).

**Suggested split (adjust after reading file):** lexer, parser, compiler/bytecode, runtime/interpreter, GC, builtins, utilities.

**Do not:** port to Zig yet; change behavior; touch app files unless build breaks.

**Test gate:** same as Section 4 — all must pass after split.

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
```

---

## Files the next agent should not touch without reason

- [`mquickjs.c`](mquickjs.c) — engine core; split carefully in Step 5, do not port yet
- [`archive/src-first-attempt/`](archive/src-first-attempt/) — stale; reference only
- [`example.c`](example.c), [`mqjs.c`](mqjs.c), [`dtoa.c`](dtoa.c), [`libm.c`](libm.c) — reference for port diffs
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Steps 0 (build hygiene), 1 (dtoa), 2 Phase 2a (libm hard float), 3 (example), 4 (mqjs).
Leaf modules cutils, dtoa, libm, readline are on Zig. Host apps example and mqjs are on Zig.
Engine is still monolithic mquickjs.c. Stdlib codegen stays C.
Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 5 — split mquickjs.c into ~7 C files (mechanical split, no Zig port yet)

Goal: Break the ~18k-line engine monolith into linkable C translation units so future
engine ports can proceed module-by-module. Zero behavior change.

Read first:
- handoff.md (Sections 1, 3, 5)
- mquickjs.c (structure — lexer, parser, compiler, runtime, GC, builtins)
- build.zig (engine_c_sources, addEngineCSources)
- mquickjs.h, mquickjs_priv.h (shared declarations)

Implementation:
1. Identify ~7 natural split points in mquickjs.c (follow handoff Section 5 sketch).
2. Create new .c/.h file pairs; move code; keep all public symbols identical.
3. Update build.zig engine_c_sources array with all new .c files.
4. Do NOT port any engine logic to Zig. Do NOT touch example.zig, mqjs.zig, or leaf modules.
5. Keep original mquickjs.c on disk renamed or as reference until tests pass (or single-file
   backup — your call, but build must use split files only).

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

**Alternative task (if user prefers softfloat first):** replace "Step 5" with "Step 2 Phase 2b — libm softfloat" and read handoff Section 5 Phase 2b sketch instead.
