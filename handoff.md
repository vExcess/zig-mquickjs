# microquickjs C→Zig Port — Agent Handoff

Last updated: 2026-08-12  
Zig version: **0.15.2** (see `.zigversion`)  
Zig path used in session: `/home/vexcess/zig-x86_64-linux-0.15.2/zig`

---

## 1. Status

### Completed (plan steps 0 and 1)

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 0** | Build hygiene | **Complete** |
| **Step 1** | Port `dtoa.c` → `dtoa.zig` / `dtoa_lib.zig` | **Complete** |

### Not yet started

| Plan step | Description | Status |
|-----------|-------------|--------|
| **Step 2** | Port `libm.c` → `libm.zig` (hard float first, softfloat later) | **Not started** — still compiled from C |
| **Step 3** | Port `example.c` → `example.zig` | **Not started** |
| Steps 4–8 | `mqjs`, split `mquickjs.c`, engine modules, host tools, idiomatic refactor | **Not started** |

**Clarification:** If “Steps 1 and 2” meant *plan* steps 1 and 2, only **Step 1 (dtoa)** is done. **Step 2 (libm) is still C.** The next incremental port should either be Step 2 (libm) or Step 3 (example); example can be ported while libm remains C.

### Current runtime link layout

```
mqjs / example
├── C: mqjs.c or example.c
├── C: mquickjs.c, libm.c
├── Zig objects: cutils, dtoa, readline (+ readline_tty, mqjs stub via @import)
└── Generated headers: mquickjs_atom.h, mqjs_stdlib.h, example_stdlib.h
```

---

## 2. Changes Made

### Step 0 — Build hygiene

| File | Change |
|------|--------|
| [`build.zig`](build.zig) | Shared helpers `addEngineCSources`, `addRuntimeObjects`, `addCommonIncludes`; explicit `cutils_obj` + `dtoa_obj` linking; `engine_c_sources` = `mquickjs.c`, `libm.c` only |
| [`cutils_lib.zig`](cutils_lib.zig) | **New** — shared cutils implementation (no C exports) |
| [`cutils.zig`](cutils.zig) | **Refactored** — thin C ABI export wrappers only |
| [`readline.zig`](readline.zig), [`readline_tty.zig`](readline_tty.zig) | Import `cutils_lib.zig` instead of `cutils.zig` (avoids duplicate symbols when both objects are linked) |
| [`src/`](src/) | **Removed** — first-attempt files moved to [`archive/src-first-attempt/`](archive/src-first-attempt/) |
| [`Makefile`](Makefile) | Deprecated; delegates to `zig build -Doptimize=ReleaseFast`; `ZIG=` override supported |
| [`README.md`](README.md) | Port status table, `-Doptimize=ReleaseFast` on all build commands |

### Step 1 — dtoa port

| File | Change |
|------|--------|
| [`dtoa_lib.zig`](dtoa_lib.zig) | **New** — ~1,340 lines; faithful port of `dtoa.c` logic |
| [`dtoa.zig`](dtoa.zig) | **New** — C ABI exports matching [`dtoa.h`](dtoa.h) |
| [`build.zig`](build.zig) | `dtoa_obj` added; `dtoa.c` removed from `engine_c_sources` |
| [`dtoa.c`](dtoa.c) | **Kept for reference** — no longer compiled |
| [`README.md`](README.md) | dtoa marked as ported |

---

## 3. Discoveries / Decisions

### Porting pattern (use for all future modules)

1. **Split lib + exports:** `<module>_lib.zig` (implementation, `@import` by other Zig modules) + `<module>.zig` (thin `export fn` wrappers for C callers).
2. **Build:** `b.addObject()` for the export root; remove `.c` from `addEngineCSources`; link via `addRuntimeObjects`.
3. **Headers:** Keep `.h` files during hybrid phase; C code unchanged.
4. **Internal Zig imports:** Always `@import("<module>_lib.zig")`, never the export object root, when another Zig file needs the same helpers (see cutils/readline split).
5. **Optimize mode:** Must use `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSmall` (C engine relies on UB; Debug/ReleaseSafe abort in `build.zig`).

### dtoa-specific fixes (critical for future ports)

| Issue | Fix |
|-------|-----|
| Duplicate symbols linking `cutils_obj` + readline importing `cutils.zig` | Split into `cutils_lib.zig` / `cutils.zig` |
| `u32toa` wrong length: `q - start` vs `end - q` | Use `@intFromPtr(&buf1[0]) + buf1.len - @intFromPtr(q)` |
| Bump allocator used byte diff in broken `std.debug.assert` | Removed bad assert; use C-style `mpb_alloc_size(limbs)` = `@offsetOf(mpb_t, "tab") + limbs * @sizeOf(limb_t)` |
| `std.mem.copyBackwards` corrupted overlapping FRAC memmove (`toFixed` → `"3333"`) | Added `overlap_move_left()` and `insert_dot()` helpers |
| Temp mem pointer init | Use `tmp_mem.mem[0..].ptr`, not `&tmp_mem.mem` |

### Architectural decisions (from planning session)

- **libm (Step 2):** C-ABI-first; keep `softfp_template.h` via `@cInclude` or auxiliary C object initially; comptime softfp replacement is a sub-milestone. Do **not** build on `archive/src-first-attempt/`.
- **mquickjs (later):** Split `mquickjs.c` into ~7 C files first, then port module-by-module.
- **Makefile:** Legacy only; `zig build` is source of truth.

### Dependencies

```
dtoa_lib.zig  →  cutils_lib.zig (min_int, strstart, BOOL)
readline.zig  →  cutils_lib.zig, readline_tty.zig, mqjs.zig (stub)
mquickjs.c    →  dtoa.h, libm.h, cutils.h (dtoa now from Zig object)
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

**Results after Step 1:**

- `zig build test` — pass (including bytecode `-o` / `-b` path)
- `zig build microbench` — pass (~2982 ms total in last run)
- `run-tests.sh` — pass (`test_builtin`, `test_closure`, `test_language`, `test_loop`, bytecode round-trip, `test_rect`, `mandelbrot`)
- Manual smoke during dtoa debug: `js_dtoa(1.125, FRAC, n=2)` → `"1.13"` (toFixed)

**Not run:** `zig build octane` (requires [mquickjs-extras](https://bellard.org/mquickjs/mquickjs-extras.tar.xz) octane tree).

---

## 5. Next Steps

### Recommended order

1. **Step 2 — libm** (~2,260 lines, softfp templates) — unblocks eventual full C removal; engine still needs it.
2. **Step 3 — example** (~311 lines) — smaller, good validation of C API usage from Zig.

Step 3 can proceed **before** Step 2 if you want a quick win; `example` links the same C `libm.c` as today.

---

### Step 3 prompt: Port `example.c` → `example.zig`

**Goal:** Replace [`example.c`](example.c) with a Zig port while keeping the hybrid build working. No change to `mquickjs.c` / `libm.c` yet.

**Read first:**

- [`example.c`](example.c) (~311 lines) — C API demo (custom JS classes `Rectangle`, `FilledRectangle`, `print`, eval)
- [`mquickjs.h`](mquickjs.h) — public API
- [`example_stdlib.c`](example_stdlib.c) / generated `example_stdlib.h` — ROM stdlib tables (stay C for now)
- [`build.zig`](build.zig) — `example_exe` target (~lines 149–182)
- Reference ports: [`cutils.zig`](cutils.zig), [`dtoa.zig`](dtoa.zig)

**Implementation plan:**

1. **Create `example.zig`** (or `example_lib.zig` + `example.zig` if you only need exports for a future C caller — for the main binary, a single `example.zig` with `pub fn main()` is enough).

2. **C API access during hybrid phase:**
   - Use `@cImport` of `mquickjs.h` (and generated `example_stdlib.h` via include path already set in build).
   - Include path: `wf.getDirectory()` + project root (already on `example_exe`).

3. **Port logic faithfully:**
   - `JS_NewContext` with stack `mem_buf` and `js_stdlib` from `example_stdlib.h`
   - User class IDs, C function callbacks (`js_print`, rectangle methods, etc.)
   - `JS_PushGCRef` / `JS_PopGCRef` discipline (critical — compacting GC)
   - Script load/run from argv or default test script
   - Match error handling and `JS_FreeContext` finalization

4. **Update [`build.zig`](build.zig):**
   - Change `example_exe` to use `.root_source_file = b.path("example.zig")` instead of compiling `example.c`.
   - Keep: `addEngineCSources`, `addRuntimeObjects(example_exe, cutils_obj, dtoa_obj, null)`, includes, `example_stdlib` codegen.
   - Do **not** remove `example.c` until tests pass (keep for diff/reference).

5. **libc / POSIX:** `example.c` uses `stdio`, `stdlib`, `fcntl`, etc. Use `@cImport` or `std.c` / `std.fs` as appropriate; match existing behavior (file load, stderr output).

6. **Do not port yet:** `example_stdlib.c`, `mquickjs_build.c`, `mqjs_stdlib.c`.

**Test gate:**

```sh
/home/vexcess/zig-x86_64-linux-0.15.2/zig build example -Doptimize=ReleaseFast
./zig-out/bin/example tests/test_rect.js
bash run-tests.sh   # includes test_rect via example
```

**Success criteria:**

- `example` binary runs `tests/test_rect.js` without errors.
- Full `run-tests.sh` still passes.
- No regressions in `zig build test` / `microbench`.

**Optional follow-up after Step 3:**

- Update [`README.md`](README.md) port status table (`example` → Ported).
- Proceed to **Step 2 (libm)** or **Step 4 (mqjs.c)** per original plan in `.cursor/plans/` or project discussion.

---

### Step 2 sketch (if doing libm before example)

Port [`libm.c`](libm.c) → `libm.zig` + `libm_lib.zig`; export all symbols in [`libm.h`](libm.h); Phase 2a hard float with `@cInclude("softfp_template.h")` or tiny auxiliary C object; remove `libm.c` from `engine_c_sources`; verify with `zig build test`, `microbench`, and `-Dsoftfloat=true` after Phase 2b.

See archived plan: finish C-to-Zig port (Steps 2–8).

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

- [`mquickjs.c`](mquickjs.c) — engine core; port is a later milestone
- [`archive/src-first-attempt/`](archive/src-first-attempt/) — stale; reference only
- [`dtoa.c`](dtoa.c) — reference for dtoa port diff
