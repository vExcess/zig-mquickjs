# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-12  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`

---

## 1. Status

### Completed (plan steps 0, 1, and 2 Phase 2a)

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 0** | Build hygiene | **Complete** |
| **Step 1** | Port `dtoa.c` → `dtoa.zig` / `dtoa_lib.zig` | **Complete** |
| **Step 2 Phase 2a** | Port `libm.c` → `libm.zig` / `libm_lib.zig` (hard float) | **Complete** |
| **Step 2 Phase 2b** | Softfloat (`-Dsoftfloat=true`) | **Not started** |

### Not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 3** | Port `example.c` → `example.zig` | **Not started** |
| **Step 4** | Port `mqjs.c` → full `mqjs.zig` | **Not started** (only 3-line completion stub exists) |
| Steps 5–8 | Split `mquickjs.c`, engine modules, host tools, idiomatic refactor | **Not started** |

### Current runtime link layout

```
mqjs / example
├── C: mqjs.c or example.c
├── C: mquickjs.c only          (engine monolith — do not port yet)
├── Zig objects: cutils, dtoa, libm, readline (+ readline_tty, mqjs stub via @import)
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

**Leaf modules on Zig:** cutils, dtoa, libm. **Engine + apps still C:** `mquickjs.c`, `mqjs.c`, `example.c`.

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
| [`build.zig`](build.zig) | `libm_obj` with Zig root + `libm_softfp.c`; `libm.c` removed from `engine_c_sources`; `addRuntimeObjects` takes `libm_obj` |
| [`libm.c`](libm.c) | **Kept for reference** — not compiled |
| [`README.md`](README.md) | libm marked as ported |

**Excluded from Phase 2a (still in C reference only):**

- `#ifdef USE_SOFTFLOAT` compiler-rt wrappers (`__adddf3`, etc.)
- Softfloat `js_sqrt` / alternate `js_rem_pio2`
- Full `__kernel_tan` path (`USE_TAN_SHORTCUT` tan via `js_sin_cos` is ported)

---

## 3. Discoveries / Decisions

### Porting pattern (use for all future modules)

1. **Split lib + exports:** `<module>_lib.zig` (implementation) + `<module>.zig` (thin `export fn` for C callers).
2. **Build:** `b.addObject()` for export root; remove `.c` from `addEngineCSources`; link via `addRuntimeObjects`.
3. **Headers:** Keep `.h` during hybrid phase; C callers unchanged.
4. **Internal Zig imports:** Always `@import("<module>_lib.zig")`, never the export root.
5. **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall` (Debug/ReleaseSafe abort in `build.zig`).

### libm-specific notes (Phase 2a)

| Topic | Detail |
|-------|--------|
| Softfp bridge | Even hard-float libm needs `cvt_sf64_i32`, `fmod_sf64`, `mul_u64` from [`softfp_template.h`](softfp_template.h). Implemented as [`libm_softfp.c`](libm_softfp.c) compiled into `libm_obj`. |
| sf32 include required | Plan said skip F_SIZE=32 for Phase 2a, but sf64 template references sf32 helpers (`unpack_sf32`, `pack_sf32`, …). **Both** includes are needed (sf32 with `F_NORMALIZE_ONLY`, then sf64 full). Also need `#include <assert.h>`. |
| Hardware sqrt | `@sqrt(x)` on x86_64 / aarch64 / x86; bit-by-bit fallback elsewhere (`use_hw_sqrt` comptime in `libm_lib.zig`). |
| No `@fabs` in Zig 0.15.2 | Use `@abs(x)` for `f64`. |
| `std.math.copysign` | Two-arg API: `std.math.copysign(magnitude, sign)` — not C's three-arg form. |
| C `(int)x` idiom | Use `@as(c_int, @intFromFloat(x)) == 0` in kernel_sin/cos. |
| Parameter reassignment | Use `var xv = x` when C mutates the parameter (e.g. `js_scalbn`, `js_exp`). |
| Mixed int/u32 bit ops | `extract_words` yields u32 lx/ly; use `@as(u32, @intCast(iy)) \| ly` for C-style `(iy\|ly)==0`; use wrapping u32 sub for pow overflow checks (`jz -% 0xc090cc00`). |
| `js_rem_pio2` | Public API takes `[*]f64`; impl uses `*[2]f64` via slice `y[0..2]`. |

### dtoa-specific fixes (from Step 1 — still relevant)

| Issue | Fix |
|-------|-----|
| Duplicate symbols | Split `cutils_lib.zig` / `cutils.zig`; never import export roots from other Zig modules |
| Overlapping memmove in dtoa | `overlap_move_left()` helper |
| Bump allocator assert | Removed; use `@offsetOf(mpb_t, "tab") + limbs * @sizeOf(limb_t)` |

### Architectural decisions

- **libm Phase 2b:** Add `-DUSE_SOFTFLOAT` to `libm_softfp.c` flags + Zig `build_options`; export compiler-rt symbols; port softfloat code paths. Do **not** use `archive/src-first-attempt/`.
- **mquickjs (Step 5+):** Split `mquickjs.c` into ~7 C files first, then port module-by-module.
- **Makefile:** Legacy only; `zig build` is source of truth.

### Dependencies

```
dtoa_lib.zig   →  cutils_lib.zig
readline.zig   →  cutils_lib.zig, readline_tty.zig, mqjs.zig (stub)
libm_lib.zig   →  libm_softfp.c (extern: libm_cvt_sf64_i32, libm_fmod_sf64, libm_mul_u64)
libm.zig       →  libm_lib.zig
mquickjs.c     →  dtoa.h, libm.h, cutils.h (all satisfied by Zig objects + headers)
```

---

## 4. Verification

All run with `/home/vexcess/zig-x86_64-linux-0.15.2/zig` and `-Doptimize=ReleaseFast`:

```sh
zig build -Doptimize=ReleaseFast
zig build test -Doptimize=ReleaseFast
zig build example -Doptimize=ReleaseFast
zig build microbench -Doptimize=ReleaseFast
bash run-tests.sh
```

**Results after Step 2 Phase 2a:**

- `zig build` — pass
- `zig build test` — pass (bytecode `-o` / `-b` path included)
- `zig build microbench` — pass (~3195 ms total)
- `zig build example` + `tests/test_rect.js` — pass
- `run-tests.sh` — pass (all JS tests, bytecode round-trip, test_rect, mandelbrot)

**Not run / not done:**

- `zig build -Dsoftfloat=true` — Phase 2b not implemented
- `zig build octane` — requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz)

---

## 5. Next Steps

### Recommended order

1. **Step 3 — example** (~311 lines) — smallest app; validates `@cImport("mquickjs.h")` from Zig.
2. **Step 4 — mqjs** (~798 lines) — REPL CLI; readline already Zig.
3. **Step 2 Phase 2b — libm softfloat** — optional before or after Step 4; needed only for `-Dsoftfloat=true` targets.
4. **Step 5 — split `mquickjs.c`** — prerequisite for engine port.

### Step 3 implementation sketch

**Goal:** Replace [`example.c`](example.c) with [`example.zig`](example.zig); keep hybrid build.

**Read first:** `example.c`, `mquickjs.h`, `build.zig` (example_exe ~lines 167–198), generated `example_stdlib.h` flow.

**Work:**

1. Create `example.zig` with `pub fn main()` (single file OK — no export object needed).
2. `@cImport` of `mquickjs.h` + `example_stdlib.h` (include paths on `example_exe` via `addCommonIncludes`).
3. Port: `JS_NewContext`, custom classes (`Rectangle`, `FilledRectangle`), `js_print`, GC ref discipline, argv script loading, `JS_FreeContext`.
4. **Update `build.zig`:** `.root_source_file = b.path("example.zig")`; remove `example.c` from `addCSourceFiles`; keep `addEngineCSources`, `addRuntimeObjects(..., libm_obj, null)`, stdlib codegen.
5. Keep `example.c` for reference; update README when done.

**Test gate:**

```sh
/home/vexcess/zig-x86_64-linux-0.15.2/zig build example -Doptimize=ReleaseFast
./zig-out/bin/example tests/test_rect.js
/home/vexcess/zig-x86_64-linux-0.15.2/zig build test -Doptimize=ReleaseFast
/home/vexcess/zig-x86_64-linux-0.15.2/zig build microbench -Doptimize=ReleaseFast
bash run-tests.sh
```

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

- [`mquickjs.c`](mquickjs.c) — engine core; split/port is Step 5+
- [`archive/src-first-attempt/`](archive/src-first-attempt/) — stale; reference only
- [`dtoa.c`](dtoa.c), [`libm.c`](libm.c) — reference for port diffs
- Plan files under `.cursor/plans/` — do not edit unless asked

---

## Next agent prompt (copy-paste)

```
Continue the microquickjs C→Zig port.

Read handoff.md first — it has full context from prior sessions.

Done: Plan Steps 0 (build hygiene), 1 (dtoa), and 2 Phase 2a (libm hard float).
Leaf modules cutils, dtoa, libm are on Zig. Engine is still monolithic mquickjs.c.
Tests pass with Zig 0.15.2 and -Doptimize=ReleaseFast.

Your task: Step 3 — port example.c → example.zig

Goal: Replace example.c with a Zig main while keeping the hybrid build working.
Do not touch mquickjs.c. example_stdlib codegen stays C for now.

Read first:
- handoff.md (Section 5)
- example.c (~311 lines)
- mquickjs.h (public API)
- build.zig (example_exe target)
- mqjs.c for similar engine usage patterns (optional)

Implementation:
1. Create example.zig with pub fn main() (single file OK — no C callers need exports).
2. Use @cImport of mquickjs.h + generated example_stdlib.h (include paths already on example_exe).
3. Port faithfully: JS_NewContext, custom classes (Rectangle, FilledRectangle), js_print,
   JS_PushGCRef/JS_PopGCRef discipline, script load from argv, JS_FreeContext.
4. Update build.zig: example_exe root_source_file = example.zig; remove example.c from
   addCSourceFiles; keep addEngineCSources, addRuntimeObjects(..., libm_obj, null), stdlib codegen.
5. Keep example.c on disk for reference until tests pass.
6. Update README.md port status when done.

Constraints:
- Zig 0.15.2 (/home/vexcess/zig-x86_64-linux-0.15.2/zig if not on PATH)
- Build/test only with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall
- Do not create git commits unless I ask

Test gate:
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build example -Doptimize=ReleaseFast
  ./zig-out/bin/example tests/test_rect.js
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build test -Doptimize=ReleaseFast
  /home/vexcess/zig-x86_64-linux-0.15.2/zig build microbench -Doptimize=ReleaseFast
  bash run-tests.sh
```
