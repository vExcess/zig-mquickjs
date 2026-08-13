# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-13  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`  
Last known-good commit: **`98b507c` (handoff 6)**

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

### In progress / not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 6 (2/7–7/7)** | Port remaining engine modules to Zig | **Next: `mquickjs_value.c`** |
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |
| **Steps 7–8** | Host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── Zig: mqjs.zig or example.zig (executable roots)
├── C embed: mqjs_stdlib_embed.c or example_stdlib_embed.c (generated stdlib tables)
├── C engine (6 files):
│     mquickjs_value.c, mquickjs_runtime.c, mquickjs_lexer.c,
│     mquickjs_parser.c, mquickjs_gc.c, mquickjs_builtins.c
├── Zig engine (1 module):
│     mquickjs_utils.zig + mquickjs_utils_lib.zig + mquickjs_utils_types.zig
│     (+ mquickjs_utils_va.c shim for C va_list callers)
├── Shared engine header: mquickjs_internal.h
├── Zig objects: cutils, dtoa, libm, mquickjs_utils, readline (+ readline_tty)
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**On Zig:** cutils, dtoa, libm, readline, readline_tty, example, mqjs, **mquickjs_utils**.  
**Still C:** 6 engine `.c` files + stdlib codegen (`mquickjs_build.c`, `mqjs_stdlib.c`, `example_stdlib.c`).  
**Reference only (not compiled):** `archive/mquickjs_monolith.c`, `mquickjs_utils.c`, `example.c`, `mqjs.c`, `dtoa.c`, `libm.c`.

### Session note (2026-08-13)

A subsequent agent attempt to continue Step 6 produced **non-compiling code** and was **reverted by the user**. The repo is back at the last green state above. **Do not assume partial work from that attempt exists** — start from the committed utils port only.

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

### Step 6 (1/7) — port mquickjs_utils.c to Zig

**Goal achieved:** First engine module ported; zero behavior change; full test gate passes.

| File | Change |
|------|--------|
| [`mquickjs_utils_types.zig`](mquickjs_utils_types.zig) | **New** — ~284 lines; `@cImport` of public headers + manual `JSContextExt` and heap object struct layouts |
| [`mquickjs_utils_lib.zig`](mquickjs_utils_lib.zig) | **New** — ~969 lines; GC refs, heap alloc/free/shrink, printf/snprintf, debug printers |
| [`mquickjs_utils.zig`](mquickjs_utils.zig) | **New** — ~150 lines; thin `export fn` C ABI wrappers |
| [`mquickjs_utils_va.c`](mquickjs_utils_va.c) | **New** — C shim: `js_vprintf`, `js_vsnprintf`, `js_snprintf` → `mqjs_v*` Zig exports (remaining C engine code calls these) |
| [`mquickjs_utils_zig.h`](mquickjs_utils_zig.h) | **New** — placeholder include stub (may be used if C modules need Zig-side headers later) |
| [`build.zig`](build.zig) | `mquickjs_utils.c` removed from `engine_c_sources`; `mquickjs_utils_obj` added; linked via `addRuntimeObjects` |
| [`mquickjs_utils.c`](mquickjs_utils.c) | **Kept for reference** — not compiled |

**Exports from `mquickjs_utils.zig`:** GC ref API, heap alloc, `js_get_atom`, stack check, throw/print/dump helpers, `mqjs_vprintf`/`mqjs_vsnprintf`, variadic `js_printf`/`JS_ThrowError`, `export const js_mtag_name`.

**Cross-module `extern fn` in utils lib** (still satisfied by remaining C engine): `JS_NewString`, `JS_NewObjectProtoClass`, `find_own_property`, `get_special_prop`, `reloc_c_func_name`, `JS_GC`, `get_mblock_size`, `build_backtrace`, `dump_regexp`, `JS_IsString`, dtoa/libm symbols.

**Internal-only in lib (not exported):** `js_find_class_name`, `JS_DumpUniqueStrings`, dump helpers — same as C original (only used within utils dump code paths).

---

## 3. Discoveries / Decisions

### Porting pattern (leaf modules — cutils, dtoa, libm)

1. **Split lib + exports:** `<module>_lib.zig` (implementation) + `<module>.zig` (thin `export fn` for C callers).
2. **Build:** `b.addObject()` for export root; remove `.c` from `addEngineCSources`; link via `addRuntimeObjects`.
3. **Internal Zig imports:** Always `@import("<module>_lib.zig")`, never the export root.

### Porting pattern (engine modules — Step 6+)

Established by the utils port; **follow this for all remaining engine modules**:

1. **Three-file split:**
   - `<module>_types.zig` — `@cImport` public headers + manual extensions for internal struct layouts the C code accesses via pointer casts (see `mquickjs_utils_types.zig`).
   - `<module>_lib.zig` — implementation; import `@import("cutils_lib.zig")`, `@import("mquickjs_utils_types.zig")` (or shared types as they accumulate), and `extern fn` for symbols still in C modules.
   - `<module>.zig` — thin `export fn` wrappers only.
2. **Build:** `b.addObject()` for export root; remove `.c` from `engine_c_sources`; add object param to `addRuntimeObjects`; call `addCommonIncludes` on the object (needs generated atom/stdlib headers).
3. **Variadic C bridge:** If remaining C code calls `foo(...)` with `va_list` internally, add a tiny `<module>_va.c` shim that forwards to Zig `mqjs_*` or direct exports — see [`mquickjs_utils_va.c`](mquickjs_utils_va.c).
4. **Do NOT `@cImport(mquickjs_internal.h)`** in Zig — it is huge and pulls in C-only constructs. Instead mirror only the struct layouts and helpers you need in `*_types.zig`, reusing/ extending `mquickjs_utils_types.zig` where possible.
5. **Value helpers:** Put JSValue bit-manipulation helpers in types file (`isInt`, `valueFromPtr`, `mbInit`, etc.) — utils already has these in `mquickjs_utils_types.zig`; value port should reuse, not duplicate.
6. **One module at a time.** Run full test gate after each port. Do not touch `example.zig`, `mqjs.zig`, or already-ported modules unless build breaks.
7. **Faithful port first.** Match C behavior line-for-line; idiomatic Zig refactor is Step 8.

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

### Engine-port quirks (Step 6 — utils)

| Topic | Detail |
|-------|--------|
| `JSContext` layout | Public `mquickjs.h` exposes opaque `JSContext`; internal fields accessed via `JSContextExt` in `mquickjs_utils_types.zig` with `@ptrCast` |
| Heap block headers | `mbInit`, `mbGetMtag`, `mbSetFreeBlock` helpers mirror C macros in `mquickjs_internal.h` |
| Variadic exports | `js_printf` / `JS_ThrowError` use `@cVaStart()` in Zig export root; C callers of `js_vprintf`/`js_snprintf` go through `mquickjs_utils_va.c` |
| Symbol naming | Zig exports use `mqjs_vprintf`/`mqjs_vsnprintf` names; C shim re-exports as `js_vprintf`/`js_vsnprintf`/`js_snprintf` |
| Cross-module deps | Utils dump code calls into value/runtime/builtins via `extern fn` — these resolve at link time against remaining C objects |
| `jsThrowErrorVa` | Non-exported Zig helper used by variadic `JS_ThrowError` export (avoids duplicating va_list logic) |

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
- **Engine port (Steps 6–8):** Port split C modules to Zig one at a time. Order: ~~utils~~ → **value** → runtime → lexer → parser → gc → builtins. Utils done; value is next.
- **Makefile:** Legacy only; `zig build` is source of truth.
- **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall` (Debug/ReleaseSafe abort in `build.zig`).
- **Failed attempt lesson:** Do not port multiple engine modules simultaneously or refactor shared types aggressively mid-port — compile incrementally and run test gate often.

### Dependencies

```
dtoa_lib.zig              →  cutils_lib.zig
readline.zig              →  cutils_lib.zig, readline_tty.zig
readline_tty.zig          →  cutils_lib.zig, readline.zig
libm_lib.zig              →  libm_softfp.c (extern: libm_cvt_sf64_i32, libm_fmod_sf64, libm_mul_u64)
libm.zig                  →  libm_lib.zig
mquickjs_utils_lib.zig    →  cutils_lib.zig, mquickjs_utils_types.zig; extern dtoa/libm/remaining C engine
mquickjs_utils.zig        →  mquickjs_utils_lib.zig, mquickjs_utils_types.zig
mquickjs_utils_va.c       →  mqjs_vprintf/mqjs_vsnprintf (Zig exports)
example.zig               →  @cImport(mquickjs.h); links 6 engine .c + utils Zig + embed + runtime objects
mqjs.zig                  →  @cImport(mquickjs.h, readline.h, readline_tty.h); links 6 engine .c + utils Zig + embed + runtime objects + readline_obj
mquickjs_*.c (remaining)  →  mquickjs_internal.h, dtoa.h, libm.h, cutils.h, js_vprintf via mquickjs_utils_va.c
split_mquickjs.py         →  archive/mquickjs_monolith.c (source of truth for regeneration)
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

**Results after Step 6 utils port (2026-08-13, commit `98b507c`):**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` path included)
- `zig build example` + `tests/test_rect.js` — pass
- `run-tests.sh` — pass (all JS tests, bytecode round-trip, test_rect, mandelbrot)

*(Re-run microbench locally if needed; not re-verified in this session.)*

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)

---

## 5. Next Steps

### Recommended order (updated 2026-08-13)

1. **Step 6 — port remaining engine modules** (one at a time, test gate after each):
   1. ~~`mquickjs_utils.c`~~ — **done**
   2. **`mquickjs_value.c`** → `mquickjs_value_lib.zig` + `mquickjs_value.zig` ← **NEXT**
   3. `mquickjs_runtime.c` → runtime/interpreter (largest, most complex)
   4. `mquickjs_lexer.c` → lexer
   5. `mquickjs_parser.c` → parser/compiler
   6. `mquickjs_gc.c` → GC
   7. `mquickjs_builtins.c` → builtins + regexp (largest file)
2. **Step 2 Phase 2b — libm softfloat** — optional parallel track; needed only for `-Dsoftfloat=true` targets.
3. **Steps 7–8** — port stdlib codegen (`mquickjs_build.c`); idiomatic refactor.

### Step 6 sketch (port next engine module — value)

**Goal:** Port `mquickjs_value.c` (~2,542 lines) following the utils three-file pattern.

**Scope:** JSValue primitives, strings, objects, properties, atoms, `JS_NewContext*`, stdlib init. This is the foundation layer most other engine modules depend on.

**Read first:**

- [`mquickjs_value.c`](mquickjs_value.c) — source to port
- [`mquickjs_utils_lib.zig`](mquickjs_utils_lib.zig) / [`mquickjs_utils_types.zig`](mquickjs_utils_types.zig) — reference port pattern and reusable types/helpers
- [`mquickjs_internal.h`](mquickjs_internal.h) — cross-module prototypes value implements (do not `@cImport` wholesale)
- [`build.zig`](build.zig) — `engine_c_sources`, `addRuntimeObjects`, `mquickjs_utils_obj` wiring

**Approach:**

1. Extend or reuse `mquickjs_utils_types.zig` for any new internal struct layouts value needs (prefer extending over duplicating).
2. Create `mquickjs_value_lib.zig` with Zig implementations; call utils via `@import("mquickjs_utils_lib.zig")` for heap/GC-ref helpers, or `extern fn` for exported utils symbols.
3. Create `mquickjs_value.zig` with thin `export fn` wrappers for every symbol other modules call (grep `mquickjs_internal.h` prototypes owned by value.c).
4. Remove `mquickjs_value.c` from `engine_c_sources`; add `mquickjs_value_obj` to `addRuntimeObjects`.
5. Add `addCommonIncludes` on the value object (like utils).
6. Add `*_va.c` shim only if value exposes variadic functions C callers need.
7. Run full test gate. Fix link errors one symbol at a time.

**Do not:** port multiple modules at once; `@cImport(mquickjs_internal.h)`; change behavior; touch app files unless build breaks; reuse code from `archive/src-first-attempt/`.

**After value port:** Update utils `extern fn` declarations that pointed at C value symbols — they can become `@import("mquickjs_value_lib.zig")` calls where appropriate (optional cleanup, not required for green build).

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
- [`example.c`](example.c), [`mqjs.c`](mqjs.c), [`dtoa.c`](dtoa.c), [`libm.c`](libm.c), [`mquickjs_utils.c`](mquickjs_utils.c) — reference for port diffs
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Steps 0–5, plus Step 6 module 1/7 (mquickjs_utils).
- Leaf modules cutils, dtoa, libm, readline are on Zig.
- Host apps example and mqjs are on Zig.
- Engine split into 7 C files; utils is now Zig (mquickjs_utils_lib/types/zig + mquickjs_utils_va.c shim).
- 6 engine modules still C: value, runtime, lexer, parser, gc, builtins.
- Original monolith archived at archive/mquickjs_monolith.c.
- Regeneration: python3 split_mquickjs.py
- Stdlib codegen stays C.
- Last green commit: 98b507c (handoff 6). A later broken attempt was reverted — start from this state only.
- Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 6 module 2/7 — port mquickjs_value.c to Zig

Goal: Port mquickjs_value.c following the established engine pattern:
  *_types.zig (extend/reuse mquickjs_utils_types.zig) + *_lib.zig + *.zig exports.
One module at a time; zero behavior change; full test gate after port.

Read first:
- handoff.md (Sections 1, 2 Step 6, 3 engine-port pattern, 5 value sketch)
- mquickjs_value.c (~2542 lines)
- mquickjs_utils_lib.zig / mquickjs_utils_types.zig (reference — reuse types/helpers)
- mquickjs_internal.h (grep prototypes implemented in value.c — do NOT @cImport wholesale)
- build.zig (engine_c_sources, addRuntimeObjects, mquickjs_utils_obj wiring)

Implementation:
1. Extend mquickjs_utils_types.zig OR add mquickjs_value_types.zig for any new internal layouts.
2. Create mquickjs_value_lib.zig with Zig implementations.
3. Create mquickjs_value.zig with export fn wrappers for all cross-module symbols.
4. Remove mquickjs_value.c from engine_c_sources; add mquickjs_value_obj to addRuntimeObjects.
5. Add addCommonIncludes on the value object.
6. Add *_va.c shim only if needed for variadic C callers.
7. Do NOT port other engine modules. Do NOT touch example.zig, mqjs.zig, or already-ported modules.

Constraints:
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)
- Build/test only with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall
- Do not use archive/src-first-attempt/
- Do not create git commits unless I ask
- Compile incrementally; fix link errors one symbol at a time; run test gate before declaring done

Test gate:
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build -Doptimize=ReleaseFast
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build test -Doptimize=ReleaseFast
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build example -Doptimize=ReleaseFast
  ./zig-out/bin/example tests/test_rect.js
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build microbench -Doptimize=ReleaseFast
  bash run-tests.sh
```

**Alternative tasks:**

- **Next after value:** port `mquickjs_runtime.c` (Step 6 module 3/7).
- **Softfloat first:** replace task with "Step 2 Phase 2b — libm softfloat" and read handoff Section 5 Phase 2b sketch.
- **Docs only:** update README port-status table (still says "7 C files"; should reflect utils on Zig).
