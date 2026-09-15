# zig-mquickjs debugging notes

Read this before diagnosing GC / parse / math / correctness issues. Compare
Zig against `/home/vexcess/Sync/Workspace/mquickjs/mquickjs.c` (and
`libm.c` / `libm_lib.zig`). Only `zig-mquickjs` and `mquickjs` matter. Do
not search other workspace trees.

Build with Zig 0.16 (`/home/vexcess/zig-x86_64-linux-0.16.0/zig`).
**ReleaseFast** is shipping/perf. **ReleaseSafe** is the UB-detector test
mode (difftest corpus + `-m32` bytecode pass with no panics as of
2026-09-14). Home is ecryptfs, which panics Zig 0.16's atomic rename —
put the cache on ext4:

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast      # shipping / C-diff regression
$ZIG build -Doptimize=ReleaseSafe      # runtime safety checks
$ZIG build -Doptimize=Debug            # self-hosted backend; slower
./zig-out/bin/mqjs --memory-limit 256M path/to/repro.js
./tests/difftest/run.sh && ./tests/difftest/bytecode.sh   # after ReleaseFast
./tests/difftest/run-safe.sh                               # after ReleaseSafe (includes zigonly + oracle)
./tests/zigonly/run.sh                                    # Zig-only expected output
./tests/oracle/run.sh                                     # no-C correctness (JSON/gc, defaults, call, math)
# Debug: LIMITS=16M ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
```

Fix **one** correctness bug per turn, then stop for manual verify. Leave
performance for last. Do not rewrite subsystems. Keep the fixes listed below;
they are real.

**Discovery order (current):** runtime probing is saturated (C-diff, ReleaseSafe,
Octane, zigonly, oracle, Debug `bytecode.sh`, plus the post-fix-25 ad-hoc
sweep). New yield is **static analysis vs C** — omitted clamps, `argc`/`FRAME_CF_CTOR`
handling, `return -1` vs `JS_EXCEPTION`, seek/`regexp_allowed` — the class that
produced fix 25. Do not chase Safe/Debug bytecode padding bytes. Size diffs
are bugs. A Safe/Debug panic is still a bug.

**Probe before every fix (mandatory).** A static C-vs-Zig mismatch is a
hypothesis, not a bug. Run the same snippet on `../mquickjs/mqjs` and
`./zig-out/bin/mqjs` (or a ReleaseSafe panic) and show they differ **before**
editing engine source. False "fix 29" (2026-09-15): Zig unlabeled `break`
inside a `switch` in a `while` already exits the loop; C `break` only leaves
the switch. User ran `[1,2,3].every(() => { n++; return false })` on an old
wasm build and got `n=1`. The labeled-loop change was reverted. Do not repeat.

---

## Octane status — RESOLVED (2026-08-15 evening)

**All Octane suites pass.** User ran `zig build octane -Doptimize=ReleaseFast`
**9 times in a row** with no crashes or suite errors (including Typescript
`parseErrors.length` 192/193 and DeltaBlue `addConstraint`).

C reference score ~2485. Zig scores ~2300–2370 vary with Octane’s
`Date.now()` time budget (different iteration counts). That is normal; the
engine bug class is fixed.

Octane remains the **regression gate** after future fixes. Do not use full
Octane for discovery iteration (slow); use `tests/difftest/` first, then ask
the user to batch-verify Octane after each fix.

**Post fix 13 (2026-08-15):** user confirmed tests still pass after the trig
fix and difftest harness landing. Octane gate should be re-run after the
next fix, not before every discovery turn.

**Post fix 15–21: gate CONFIRMED CLEAN (2026-09-14).** User ran Octane after
fixes 15 (`-m32` float64 blocks), 16 (`JSCFunctionDef` print stride), 17
(`js_dump_object` `default:`), 18 (host `scriptArgs` argv), 19
(`JS_DumpMemory` tag-line `\\n`), 20 (function-body first-token re-lex) and 21
(Zig-only default-arg comma skip) and it **passes**. Fixes 1–21 are therefore
all Octane-gated.

**Post ReleaseSafe (2026-09-14 evening):** user confirmed Octane **passes
under `-Doptimize=ReleaseSafe`**. The UB-detector gate is now the full
difftest corpus + bytecode.sh + Octane. Ask for a fresh batch after the
*next* engine fix, not before discovery turns.

**Post fix 22–24:** user confirmed Octane after each (2026-09-14 night).
**Post fix 25–26 and 28:** user confirmed Octane **runs without error** (2026-09-15).
Zig is slower than C and has gotten slower across fixes; it was slower to
begin with. Leave performance for last.

### What broke Octane (bug classes — still hunt these elsewhere)

These were **not** suite-logic ports. Same classes likely exist in code
paths Octane never exercised:

| Class | Symptom | Example fix |
|-------|---------|-------------|
| Stale `JSValue` after GC | Missing property/method, wrong parse count | `_ = popValue` then use local |
| Intern identity | Two unique strings for same text | Property key stored under old pointer |
| Raw pointer across alloc | UAF, wrong bytecode | `source_buf`, `JSFunctionBytecode *` |
| Numeric UB | Wrong math / checksum | `libm_lib.zig` signedness/precedence |
| Layout drift vs C | Rare heap corruption | `utils_types` vs `runtime_types` |

Property lookup uses **pointer equality** on unique strings. Two unique
`"foo"` objects → method miss / wrong compiler behavior.

---

## Post-Octane audit plan

Goal: find silent correctness bugs (same classes as Octane) before they
surface in other workloads. Work in order; do not skip Phase 1.

### Phase 1 — Static audit (highest ROI)

#### 1A. Complete the `JS_POP_VALUE` audit — **DONE**

Checklist table below is complete. All `_ = utils.popValue` sites in hot
files are C-verified. Fixes 10–11 came from this pass.

Grep `_ = utils.popValue` in `src/` (~57 sites). Most are safe (pop only
cleans GC roots). **Dangerous pattern:**

```
pushValue(ctx, &ref, local)
  → js_malloc / js_alloc_* / js_resize_* / JS_StackCheck / JS_GC
  → _ = popValue(...)     // BUG if local used after
  → store / call / compare local
```

For each site: open matching C in `mquickjs.c`. C `JS_POP_VALUE(ctx, v)`
**assigns** `v = v_ref.val`. Triage: **must fix** / **safe** / **needs test**.

Hot files (compare to C line-by-line):
- `mquickjs_builtins_string_lib.zig` (~45 discards)
- `mquickjs_builtins_regexp_lib.zig`
- `mquickjs_parser_lib.zig` (`js_parse_function_decl` end pops)
- `mquickjs_value_lib.zig` (error paths only — success path fixed)

**Deliverable:** checklist in this file (file:line, C ref, verdict).

Already fixed (do not revert): CodeLoad `func`/`byte_code`; parser
`cpool_add`/`add_var`/`add_func_ext_var`; `push_break_entry`/`emit_break`
`label_name`; `js_create_property` `prop`; `JS_ToPrimitive` `method`;
`js_function_bound` `params`.

#### 1B. Raw-pointer-across-alloc audit — **DONE (no new must-fix)**

Parser/lexer match C offset/`source_buf` refresh discipline. Prior fixes
(parseNumber, explore_arr reload, json paths) intact. Latent shared C+Zig
risk in `compute_stack_size` mid-iteration reload — not a port divergence.

#### 1C. Intern / property-key audit — **DONE (no new must-fix)**

Hot paths fixed or match C. Latent same-as-C watchlist (needs difftest if
suspected): `js_object_defineProperty`, `hasOwnProperty`,
`JS_GetPropertyStr`/`SetPropertyStr`, JSON stringify keys, `js_operator_in`
— all use unrooted `ToPropertyKey` locals like C. Add a difftest script
before fixing any of these.

#### 1D. Layout / type overlay audit — **DONE**

Runtime GC/parser paths use `runtime_types` correctly. Fix 12 removed the
stale `utils_types.JSFunctionBytecodeExt` duplicate (debug dumps only).
Regexp overlay and `JSFunctionBytecodeExt` mark/thread/sizing match C.

### Phase 2 — Targeted runtime tests — **superseded by `tests/difftest/`**

The 16 default difftest scripts cover the original Phase 2 list and more.
For ad-hoc GC pressure while iterating on a fix, still use one-off scripts
with `--memory-limit 8M`:

```sh
./zig-out/bin/mqjs --memory-limit 8M /tmp/gc_stress_foo.js
```

Add a permanent script under `tests/difftest/` when a fix gets a repro.
`DEBUG_GC` in `include/mquickjs_priv.h` (GC every malloc): slow; use to
**validate a fix**, not daily iteration.

### Phase 3 — Differential vs C reference — **HIGHEST YIELD, use this first**

The C reference binary is **already built** at `../mquickjs/mqjs`. Diffing it
against Zig found the trig bug (fix 13) that three static audit passes missed.
Prefer this over more static reading.

Harness is committed at `tests/difftest/` (see its `README.md`):

```sh
./tests/difftest/run.sh            # ALL MATCH == clean
SLOW=1 ./tests/difftest/run.sh     # + slow/17_regexp_deep.js
```

It runs every script on both engines at each memory limit and diffs
stdout+exit code. Two rules learned the hard way:

1. **Strip ANSI colour** — C `mqjs` colourises errors, the Zig host does
   not. Cosmetic; it otherwise masks every real diff.
2. **Require a `DONE <file>` sentinel** — a script that dies early makes
   "matching" output meaningless. `run.sh` flags truncation separately.

Current coverage (all matching): labels, property/intern tables, bind,
parser/eval, regexp, math, strings, arrays+JSON, objects/coercion, deep
recursion + stack growth, closures/varrefs, typed arrays, documented ES6
extras, hostile-argument fuzzing, exhaustive numeric sweep, UTF-8/UTF-16
index conversion, explicit-`gc()` stale-pointer probing, `gc()` called from
inside builtin callbacks, and re-entrant mutation of the structure a builtin
is walking. `slow/17_regexp_deep.js` (11850 regexp cases, ~2 min/run) is kept
out of the default run.

**Call `gc()` explicitly in new scripts.** A tight `--memory-limit` only
collects when the allocator happens to run out; `gc()` puts a compaction
between "take pointer" and "use pointer", which is what this bug class needs.
Fix 14 was invisible to all 16 original scripts at every memory limit and
fell out of `18_gc_explicit.js` immediately. Keep `gc()` calls cheap — one
inside an O(n log n) sort comparator over a 3000-element array cost ~100 s.

Add a differential script for each new fix; that is now the cheapest
regression gate short of full Octane.

Watch for **intended deviations** (README "Deviations from mquickjs") — do
not report these as bugs: direct `eval` runs in global scope, and
`let`/`const` alias `var`. Also unsupported in both engines: array
elisions, writing past array end, `**=`, `Object.freeze`,
`Object.getOwnPropertyDescriptor`, reused `catch` bindings.

Bytecode (`-o` / `-b`) has its own harness, `tests/difftest/bytecode.sh`:
image sizes for `-o` and `-m32 -o`, plus all four cross combinations of
"compiled by A, executed by B". C and Zig 64-bit images are cross-loadable and
execute identically; the remaining byte differences are struct/heap padding
(stale bytes in **both** engines), not a port bug.

**Sizes, unlike bytes, are a hard invariant.** User observation (2026-09-14):
ReleaseFast `-o` images can be **byte-identical** to C; ReleaseSafe still
differs in a few padding bytes (reported as `note:` by `bytecode.sh`, not a
fail). That is LLVM vs Debug/Safe leaving different stale bytes in string
tails — **not a port bug**. Do not zero-fill or rewrite allocators to make
Safe byte-identical. A *size* mismatch still is a bug.

### Phase 4 — Hardening

- Document: after `pushValue` + GC-capable call, always `local = popValue`.
- Update this file as audits complete.
- Host `mqjs` argv SEGV for `run.js <suite>` — **fixed** (fix 18).

### Execution order (current)

1. `$ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh && ./tests/zigonly/run.sh && ./tests/oracle/run.sh`
2. `$ZIG build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh` — any panic is a bug
   (`run-safe.sh` is run.sh + bytecode.sh + zigonly + oracle at 16M)
3. Debug (if parse/JSON/longjmp or bytecode emit): `$ZIG build -Doptimize=Debug` then
   `LIMITS=16M ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh` — both ALL MATCH
   (2026-09-14). Padding-byte notes expected; SIZE or EXEC DIFF is a bug.
4. Fix one C-verified or Zig-only panic/bug; add a difftest / zigonly / oracle script
5. User batch Octane after substantive engine fixes (ReleaseFast; ReleaseSafe
   if it was a safety fix). Debug Octane is optional and slow — ask first.

C script-level differential and post-fix-25 runtime probing are saturated.
Prefer static C-vs-Zig function diffs (the fix 25 class), ReleaseSafe panics,
and image *sizes* over padding-byte chasing or more ad-hoc probe scripts.

### Success criteria

| Milestone | Gate | Status |
|-----------|------|--------|
| 1A complete | Every `_ = popValue` has C-verified verdict | **done** |
| 1B–1D static | No new must-fix vs C in parser/GC/layout | **done** |
| C differential | `./tests/difftest/run.sh` → ALL MATCH | **done** |
| Octane regression | Full runs pass after latest fix | **done** through fix 24 (user); fixes 25–26, 28 **pending** batch |
| Independent oracle | `./tests/oracle/run.sh` → ALL ORACLE MATCH | **done** (fixes 22–25 + JSON/math/gc); Fast/Safe; in `run-safe.sh` |
| ReleaseSafe runnable | difftest + bytecode.sh + zigonly + oracle, no panics | **done** (2026-09-14); `./tests/difftest/run-safe.sh` |
| Debug runnable | compiles; 16M `run.sh` ALL MATCH | **done** (setjmp + `js_vprintf`); `bytecode.sh` ALL MATCH (padding notes only, 2026-09-14 night); Octane under Debug **not gated** (optional, slow) |
| Zig-only suite | `./tests/zigonly/run.sh` → ALL ZIGONLY MATCH | **done** (fix 21 defaults, let/const-as-var, global eval); Fast/Safe/Debug |

### Do not do yet

- Rewrite GC or intern algorithm
- Change `js_resize_value_array2` memcpy for all arrays
- Re-apply compact-by-`unique_strings_len` or MakeUniqueString extras
- “Fix” `newShortInt` without C proof
- Chase Octane score deltas (timing noise)
- Chase ReleaseSafe/Debug `-o` padding-byte diffs when sizes match (Fast may be exact; that is not a requirement)

---

## What previous agents got wrong (do not repeat)

The GC **mark/compact loop matches C** (`src/mquickjs_gc_lib.zig` vs
`mquickjs.c` ~11837–12438). Do **not** rewrite the GC.

Failed attempts (reverted — leave reverted):

1. **Generic resize “copy post-GC `valueArraySize`”** — wiped property arrays.
2. **Unique-string compact keep empty array at j==0** — diverged from C.
3. **Compact scan `unique_strings_len` instead of `arr->size`** — dropped live
   interned keys (DeltaBlue + Typescript). Restored C loop.
4. **MakeUniqueString post-resize `find_atom` + `[len, cap)` UNDEFINED fill**
   — diverged from C. Removed; keep numeric re-lookup only (fix 7).

---

## Fixed already (do not revert; do not re-diagnose)

### 1. `Math.floor` / `ceil` / `trunc` / `round` no-op in ReleaseFast

`src/libm_lib.zig` `rintSf64`. Fix: `exp_field - 0x3ff` as signed `c_int`.

### 2–3. `Math.pow`

`js_pow` precedence and overflow signedness vs C.

### 4. `parseNumber` UAF

`src/mquickjs_lexer_lib.zig`. C saves `pos`, allocs (may GC), then
`p = source_buf + pos`.

### 5. `check_free_mem` signed subtract

`src/mquickjs_utils_lib.zig`. C uses signed `ptrdiff_t`.

### 6. `byte_code` not attached at finalize (CodeLoad / zlib SEGV)

`src/mquickjs_parser_lib.zig` `js_parse_local_functions`. Assign
`b.byte_code` **before** `convert_ext_vars_to_local_vars`; refresh `b` after.

### 7. Unique-string insert after `js_is_numeric_string` GC

`JS_MakeUniqueString`: re-lookup `a` after numeric GC only. Do not revert.

### 8. Discarded `JS_POP_VALUE` (parse / resize / CodeLoad)

`cpool_add`, `add_var`, `add_func_ext_var`, `js_parse_local_functions`
`func`, etc.

### 9. Unique-string GC compact + intern identity (Octane fixes)

- `gc_mark_all`: scan `arr->size` like C (~12151). Do not compact-by-len.
- `JS_MakeUniqueString`: match C insert path; numeric re-lookup only.
- `push_break_entry` / `emit_break`: `label_name = popValue`.
- `js_create_property`: `prop = popValue` before `pr.key` / `hashProp`.
- `JS_ToPrimitive`: `method = popValue` before `JS_PushArg`.
- `js_function_bound`: `params = popValue` before `valueArr`.

C `js_resize_value_array2` `memcpy`s `old_size`. Latent in C too; do not
“fix” globally.

### 10. String replace callback capture stale after stack check

`js_string_concat_subst`: reload `val` from its GC ref after
`JS_StackCheck`, matching C `mquickjs.c:17929-17937`.

### 11. Error object stale after backtrace allocation

`jsThrowErrorVa`: reload `error_obj` after `build_backtrace`, matching C
`mquickjs.c:942-947`, before passing it to `JS_Throw`.

### 12. Debug dump function-bytecode layout drift

Debug object/value dumps now cast bytecode through the authoritative
`runtime_types.JSFunctionBytecodeExt`. Removed the unused
`utils_types.JSFunctionBytecodeExt`, whose extra `flags` word shifted every
field relative to C.

Phase 1B parser/lexer pointer-lifetime and Phase 1C intern/property-key
audits found no additional Zig-vs-C must-fix divergences. Phase 1D runtime
GC layouts and regexp overlay match C after the debug-only type cleanup.

### 13. Trig functions broken for all negative inputs (`libm_lib.zig`)

Found by C-differential testing, **not** static audit. `Math.sin`/`cos`/`tan`
returned `0` for every negative argument; `acos(-1)` returned `0` instead of
pi; `atan`/`asin` dropped the sign. Same class as fix 1.

`getHighWord` returns `u32`, but C declares `int hx, ix` and uses `hx < 0` /
`hx > 0` to test the **sign bit of the double**. As `u32` those tests are
dead. Four defects, all now fixed via a new `getHighWordSigned` helper:

- `jsSinCos`: `ix >= 0x7ff00000` was always true for negative `x`, so it
  returned `x - x` (= 0) immediately. This was the sin/cos/tan bug.
- `jsSinCos`: `n` used `@intCast` on `js_rem_pio2`'s possibly-negative
  return — illegal behavior in ReleaseFast. C relies on modular
  `int` -> `uint32_t` conversion, so use `@bitCast`.
- `jsRemPio2Impl`: `if (hx < 0)` never fired (no argument negation), and
  `j` shifted `hx` where C shifts `ix` (`libm.c:1030`).
- `js_asin` / `js_acos` / `js_atan`: sign-selection branches were dead.

Verified: 4001 values x 13 Math functions now byte-identical to C.

### 14. JSON number scratch buffer overwrote its own block header

`src/mquickjs_parser_lib.zig:723` (`js_parse_json_value`). `JSON.parse` of a
document containing numbers corrupted the heap: **SEGV**, or a bogus
`SyntaxError: invalid number literal` partway through a valid document.

C passes `js_atod` the byte array's **data area**
(`mquickjs.c:11576-11577`, `(JSATODTempMem *)tmp_arr->buf`). Zig passed
`tmp_arr` itself, i.e. the block header. `JSATODTempMem` is 216 bytes and the
block is `header + 216`, so `js_atod`'s scratch space started 8 bytes early:
it destroyed the `JSByteArray` header (GC mtag + size) and left the last 8
bytes of the allocation unwritten. `js_free` then freed a block whose size
word was garbage, so a later allocation overlapped a live block — usually the
JSON source string itself, hence the bogus number error.

The lexer's `parseNumber` (fix 4) already did this correctly with
`vt.byteArrayBuf(tmp_arr)`; the JSON path was the only site that did not.
It stayed hidden because it needs a heap busy enough for the mis-sized free
block to be reused: `JSON.parse` in isolation passes at any memory limit.

Found by the new `tests/difftest/18_gc_explicit.js` (explicit `gc()` between
allocation and use). Regression: `JSON.parse` of ~180-200 element documents
plus every number shape, at all memory limits.

### 15. 32-bit bytecode output: every float64 block was 4 bytes too big

`src/mquickjs_gc_types.zig` `JSFloat64_32`. Any image written with `-m32`
containing a float64 had a wrong heap layout: correct data, wrong block
spacing, so a 32-bit engine walking the heap desynchronises after the first
float and misparses everything following it.

C declares the double **packed** on purpose (`mquickjs.c:12547-12554`):

```c
typedef struct {
    JS_MB_HEADER_32;
    JSWord_32 dummy: JS_MB_PAD_32(JS_MTAG_BITS);
    /* unaligned 64 bit access in 32-bit mode */
    struct __attribute__((packed)) { double dval; } u;
} JSFloat64_32;          /* sizeof == 12, alignof == 4 */
```

Zig used `packed struct { header: u32, dval: f64 }`, which is backed by a
`u96`; `@sizeOf(u96)` is **16**, not 12. `get_mblock_size_32` therefore
advanced the write cursor by 16 per float (`gc_compact_heap_64to32`), while
`convert_mblock_64to32` correctly wrote only 12 bytes. Fixed with an extern
struct that pins the field alignment, which reproduces C exactly:

```zig
pub const JSFloat64_32 = extern struct { header: u32, dval: f64 align(4) };
```

Measured before the fix: `-m32` images were larger than C's by exactly
`4 * (float64 count + 1)` — 4 bytes for 0 floats (the context's `minus_zero`),
404 for 100. After: every `-m32` image matches C's size exactly, and images
are byte-identical apart from stale padding bytes.

Found by comparing **emitted bytecode** rather than program output. No
runtime test could see it: the 64-bit path is unaffected, and a 64-bit host
refuses to load a 32-bit image ("Could not relocate bytecode", both engines),
so the corruption only manifests on a real 32-bit target. The other four
`*_32` structs were checked at the same time and match C (4, 4, 4 and 40
bytes); `JSFloat64_32` was the only one where Zig's packing rules diverge.

Regression: `tests/difftest/bytecode.sh`.

### 16. `JSCFunctionDef` overlay was 8 bytes short (wrong table stride)

`src/mquickjs_utils_types.zig` `JSCFunctionDefExt`. C's `JSCFunctionDef`
(`mquickjs.h:238-244`) is 24 bytes:

```c
typedef struct JSCFunctionDef {
    JSCFunctionType func;  /* 8 */
    JSValue name;          /* 8 */
    uint8_t def_type;
    uint8_t arg_count;
    int16_t magic;
} JSCFunctionDef;          /* sizeof == 24 */
```

Zig's overlay used by `JSContextExt.c_function_table` was

```zig
pub const JSCFunctionDefExt = extern struct {
    name: c.JSValue, def_type: u8, magic: c_int,
};  /* sizeof == 16, name at offset 0, magic is c_int */
```

`print(Math.sin)` walked the ROM table with stride 16 instead of 24, so
`.name` read the next entry's `func` pointer: it printed `function concat()`
and `print(Date)` SEGVd. `vt.cFunctionTable()` already overlayed the correct
24-byte layout (`mquickjs_value_types.zig`), which is why builtin *calls*
worked; only dump/print indexed through the truncated type
(`js_find_class_name`, `JS_TAG_SHORT_FUNC`, `JS_CLASS_C_FUNCTION`).

Found by the struct-layout sweep (highest-priority item after fix 15): a
generated C `sizeof`/`offsetof` dump vs Zig `@sizeOf`/`@offsetOf` for every
`*_32` type and runtime overlay. Every other overlay matched C except:

- this type (16 vs 24) — runtime dump bug, fixed here
- `JSObjectExt` union 16 vs C's 24, so `@sizeOf(JSObjectExt)` is 40 vs
  C's 48, because Zig's union omits `regexp`/`date`/`user`. **Not a heap
  bug**: both engines allocate with `offsetof(JSObject, u) + extra_size * JSW`,
  and regexp/date pass `@sizeOf(JSRegExpExt)` / `@sizeOf(JSDateExt)` as
  `extra_size`. Leave the union incomplete unless a site starts using
  `@sizeOf(JSObjectExt)`.

Regression: `tests/difftest/21_print_cfunc.js`.

### 17. `js_dump_object` missing `default:` (Date / typed-array print blank)

`src/mquickjs_utils_lib.zig` `js_dump_object`. C (`mquickjs.c:6748-6750`) is

```c
default:
case JS_CLASS_ARRAY:
case JS_CLASS_OBJECT:
```

Zig only matched `ARRAY` and `OBJECT`, so any other class_id printed nothing:
`print(new Date(0))` was empty vs C `Date {  }`. Same for ArrayBuffer and
every typed-array instance. Number/String/Boolean constructors are unsupported
in both engines (`TypeError: number constructor not supported`), so boxed
primitives cannot be constructed from JS; Date / ArrayBuffer / typed arrays
are the reachable repro.

The typed-array dump branch lived inside that case and was therefore **dead**
in Zig. C indexes with element pointer arithmetic
(`*((int16_t *)arr->buf + idx)`); `JSTypedArray.offset` is in elements
(`mquickjs.c:304-308`). Zig used `byte_buf[idx]` as a byte offset, which is
wrong for every multi-byte type. Matched the live getter in
`mquickjs_value_lib.zig` (`buf[idx * sizeof(T)]`). Inner switch `else` now
matches C's `default: UINT8C / UINT8`.

Regression: `tests/difftest/21_print_cfunc.js` (extended).

### 18. Host `scriptArgs` SEGV on extra argv (Zig slice as `char **`)

`src/mqjs.zig` `main`. C passes `argv + optind` (`const char **`) into
`eval_file` (`mqjs.c:772`). Zig's `init.args.toSlice` is
`[]const [:0]const u8` — an array of `{ptr, len}` pairs (16 bytes each).
`@ptrCast(script_argv.ptr)` treated that as `[*]const [*:0]const u8`, so
`argv[0]` coincidentally read the first slice's pointer (script still ran)
and `argv[1]` read the first slice's *length* as a pointer → SEGV.

That is why `mqjs tests/octane/run.js <suite>` crashed (second arg) while
`zig build octane` (no extra script argv) was fine. Fixed by copying
`.ptr` of each slice into a real `[][*:0]const u8` before `evalFile`.

Regression: `tests/difftest/22_script_args.js` plus sidecar
`22_script_args.argv` (`foo`, `bar`, `has space`). `run.sh` now appends
a `<script>.argv` sidecar if present.

### 19. `JS_DumpMemory` tag table missing newline

`src/mquickjs_utils_lib.zig` `JS_DumpMemory`. C (`mquickjs.c:7102`) prints
each mtag summary line with a trailing newline:

```c
js_printf(ctx, "%15s %8u %8d %8u %7d%%\n", ...);
```

Zig omitted the newline, so `mqjs -d` ran every tag onto one line
(`free ... 1%         object ...`). Counts, sizes, and heap totals were
already identical to C — only the format was wrong. Same dump class as
fixes 16–17.

Regression: `tests/difftest/23_dump_memory.js` plus sidecar
`23_dump_memory.flags` (`-d`). `run.sh` now prepends a `<script>.flags`
sidecar if present.

`load()` / `console` were probed this turn against C (nested load, throw
inside a loaded file, `console.log`, missing-file `perror`+`exit(1)`).
Happy path matches; missing file is a host `exit(1)` in both engines, not
a JS exception.

### 20. Function body first token re-lexed (`js_parse_seek_token`)

`src/mquickjs_parser_lib.zig` `js_parse_function`. C (`mquickjs.c:11113-11119`)
parses `{` then uses the current token as the first body token. Zig always
saved that position, emitted default-arg initializers (a Zig-only extension;
C has no `function f(a = 1)` path), then `js_parse_seek_token` — which calls
`next_token` and therefore **re-lexed the first body token of every function**,
even when `default_count == 0`.

Each extra `js_parse_ident` of a ROM keyword (`var`, `return`, `print`, …)
leaves a 16-byte non-unique string plus an 8-byte free tail: `js_shrink` after
`string_buffer_pop` plants a free block, and `js_free` only retracts if the
block is last (`mquickjs.c:573-583`). Same leftover class exists in C (~18
`"var"` on `01_labels.js`); Zig had **two extra `"var"` and one extra
`"return"`** on that file, and `+2` leftover `"var"` on a two-function
repro. Heap size, string count, and later unique-string pointers (property
hash chains) then diverged. Bytecode and program stdout still matched.

Fix: only seek back when `default_count > 0`.

Regression: `tests/difftest/24_func_body_relex.js` plus sidecar
`24_func_body_relex.flags` (`-d`). The `-d` tag table’s string count catches
the extra leftovers; `-dd` EXTRA still has ROM `props` offsets that differ
by ASLR on both engines (not a port bug).

### 21. Default-arg skip consumed later parameters (`js_skip_expr`)

Zig-only. C has no `function f(a = 1)` (SyntaxError: expecting ','). After
fix 20, the rewind path (`default_count > 0`) was untested against a
default-arg script and **misbehaved**: `function f(a = 1, b = 2) { return
a + b; }; f()` threw `ReferenceError: variable 'b' is not defined`.

`js_parse_function` skipped each default with `js_skip_expr`, which only
stops at `)` (C’s for-loop third-expr skip, `mquickjs.c:7723-7741`). For
`a = 1, b = 2` that skip ate `, b = 2` as well, so `b` was never
`add_var`’d. Emission uses `js_parse_assign_expr2` (stops at comma), which
was already correct.

Fix: `js_skip_assign_expr` in `mquickjs_lexer_lib.zig` — same as
`js_skip_expr` but also returns on `,`. Nested `,` inside `()`/`[]`/`{}`
still go through `js_skip_parens`. Do **not** change `js_skip_expr` itself
(`for (;; i++, j++)` must still skip through commas to `)`).

No C-compared difftest: C cannot parse the repro. Zig-only checks live in
`tests/zigonly/01_default_args.js`:
`f(a=1,b=2)`, `f(a,b=2)`, `b = a + 1`, `(1, 2)`, `[1,2]`, `{x:1}`,
`Math.max(1,2)`, `f(undefined)` uses the default. `for (i=0,j=10; i<3;
i++, j--)` still matches C.

### 22. Default-arg re-lex treated `/` as division

Zig-only. After fix 21, `function f(a = /x/g)` and `function f(a = 1) { /z/; }`
threw `SyntaxError: unexpected character in expression`.

Default-arg emission seeks back with `js_parse_get_pos` / `js_parse_seek_token`
(C never does this). `get_pos` stores `regexp_allowed =
is_regexp_allowed(current token)`. A default or body that *starts* with a
regexp is already `TOK_REGEXP`, so `is_regexp_allowed` is false; seek fakes a
previous `)` and re-lexes `/` as division.

Fix: after saving `default_pos` (token follows `=`) and `body_pos` (token
follows `{`), set `regexp_allowed = 1`. Do not change `js_parse_get_pos`
itself (C for-loop skip uses it).

Regression: `tests/oracle/06_default_regexp.js` (declaration, method,
`Function()`, mixed params, body starting with `/z/`). Independent oracle
suite lives in `tests/oracle/` — no C reference; self-checking + `.expected`.

### 23. Default args ran before `arguments` / inner name were bound

Zig-only. `function f(a = arguments.length) { return a + ":" + arguments.length; }; f()`
threw `TypeError: cannot read property 'length' of undefined`. Named
`function foo(a = foo) { return foo; }` was a `ReferenceError`.

`js_parse_function` emitted default-arg bytecode *before* `OP.arguments` and
`OP.this_func`. The first pass's param-list skip also discarded skip bits, so
a default that mentioned `arguments` without the body doing so never set
`HAS_ARGUMENTS`.

Fix: bind `arguments` and the inner function name before default emission
(no-default path is the same order as before). `js_skip_assign_expr` now
returns skip bits so `function f(a = arguments.length) { return a; }` still
creates the arguments object. Do not OR first-pass param-list bits globally
(`function foo(foo) {}` would grow `-o` images vs C).

Regression: `tests/oracle/07_default_scope.js`.

### 24. Named function expr default did not bind the inner name

Zig-only leftover of fix 23. `var f = function foo(a = foo) { return typeof a; }; f()`
threw `ReferenceError` when the *body* never mentioned `foo` (same for
`{ m: function m(a = m) {} }` and method shorthand). Declarations already
worked via hoisting.

`js_skip_assign_expr` only returned `SKIP_HAS_ARGUMENTS`. It now takes the
rooted inner name (like body `js_skip_parens`) and sets `HAS_FUNC_NAME`.
Do not OR first-pass param-list bits.

Regression: `tests/oracle/07_default_scope.js` (named-only / method / shorthand / eval).

### 25. `Function.prototype.call()` with no thisArg threw `?`

`fn.call()` (argc 0) omitted C's `argc = max_int(argc, 1)` (`mquickjs.c:13129`).
`newTailCall(-1)` is a plain `JS_EXCEPTION` (not a tail call), so the call
threw a nameless `?` instead of invoking with `this === undefined`.
`fn.call(undefined)` already worked because argc was 1.

Fix: clamp `argc` to at least 1 in `js_function_call`. argv[0] is already
padded to `undefined` (`fd.arg_count` is 1).

Regression: `tests/difftest/25_function_call.js`, `tests/oracle/08_function_call.js`.

Verified Fast `run.sh` / `bytecode.sh` / zigonly / oracle ALL MATCH; ReleaseSafe
`run-safe.sh` ALL MATCH (padding notes only, including the new script).

### 26. `Function(param, body)` ToString error order

C `js_function_constructor` `goto done` on `string_buffer_concat` failure
(`mquickjs.c:13029-13037`) so later argv entries are never `ToString`'d.
Zig `break` from the param loop then still concatenated `argv[n]` (the body).
`Function({toString: throw "A"}, {toString: throw "B"})` threw `B` instead of `A`.

Fix: labeled `concat` block matching C's `goto done`.

Regression: `tests/difftest/26_function_ctor.js`.

Verified Fast `run.sh` / `bytecode.sh` / zigonly / oracle ALL MATCH; ReleaseSafe
`run-safe.sh` ALL MATCH; Debug 16M `run.sh` / `bytecode.sh` ALL MATCH (padding
notes only, including the new script).

The post-fix-25 sweep's `Function()` toString probe used a single argument
(the body), which does not hit this path.

### 27. (reverted) Do not copy C `JS_CFUNC_f_f` throw-to-NaN

C `JS_CFUNC_f_f` (`mquickjs.c:5457-5466`) sets `val = JS_EXCEPTION` on
ToNumber failure, then unconditionally `val = JS_NewFloat64(ctx, d)`.
ToNumber already wrote `d = NAN`, so the exception is a dead store:
`Math.sin({valueOf: throw "X"})` returns NaN. Node and the spec propagate.
`Number()` / `Math.min` on C still throw — only the compact f_f wrappers
hit this.

Zig's original if/else only `JS_NewFloat64` on success (throws). A
match-C change was applied, then reverted: C is wrong here.

Do not re-apply the unconditional `JS_NewFloat64`. Not a difftest — C
prints `sin=NaN`. Regression: `tests/oracle/09_math_ff_throw.js`.

### 28. Array literal `[1 2]` parsed as `[1, 2]`

C array-literal parse (`mquickjs.c:9503-9506`) `goto done` when the token
after an element is neither `,` nor `]`, then `js_parse_expect(']')`.
Zig continued into the `put_array_el` loop, so `Function("return [1 2]")`
returned `1,2` instead of SyntaxError.

Fix: missing comma → `js_parse_expect(']')` (C `goto done`). Trailing
comma and `[1, 2]` unchanged.

Regression: `tests/difftest/28_array_comma.js`.

Verified Fast `run.sh` / `bytecode.sh` / zigonly / oracle ALL MATCH; ReleaseSafe
`run-safe.sh` ALL MATCH; Debug 16M `run.sh` / `bytecode.sh` ALL MATCH (padding
notes only, including the new script).

### Post-fix-25 runtime sweep — no new bug (2026-09-14 night)

Ad-hoc probes vs C (C-parseable) and Zig-only default-arg paths. **No confirmed
next bug.** Do not redo this sweep as discovery.

Probed clean (matches C where C can parse; Zig-only cases did not crash):
`apply`/`bind` (already had C's `max_int(argc-1, 0)`), `fn.call(undefined)` /
`fn.call(null)` / extra args, `Function("a = anonymous")`, `new.target` in
defaults, nested named-expr defaults, getter defaults, `Function()` `toString`
throw/gc, JSON unicode/`-0`/`1e400`/`\u{41}`/circular, typed-array `set`/
`subarray`/clamp, `Object.create(null)`, closures over defaults, `**` in
defaults, regexp after `~`/`!`/`typeof` in defaults, `eval` of non-strings
(ES5: return the value).

**Not bugs** (C-shared or documented; do not "fix"):
- `for (;; /x/.exec())` — `is_regexp_allowed(')')` is false; C SyntaxError
- `"x".repeat({valueOf: function(){ throw "boom"; }})` → nameless `?` —
  C `js_string_repeat` also `return -1` (`mquickjs.c:13704`), not `JS_EXCEPTION`
- sort comparator throw swallowed (`return JS_EXCEPTION` as cmp int, C same)
- `"Array loo long"` typo (C `mquickjs.c:14394`)
- `JSON.parse('"\\u{41}"')` → `"A"` (JSON path uses the JS string lexer)
- `eval` global / `let`/`const` as `var` / array holes SyntaxError / `with`
  SyntaxError
- `function.length` with defaults is the param count, not ES6 length
- Hoisted inner `function g` is visible during default eval (var-hoist)
- Zig unlabeled `break` inside `switch` in a `while` exits the **loop**
  (C `break` only leaves the switch). False "fix 29" (reverted). Probe:
  `var n=0; [1,2,3].every(function(){ n++; return false; }); print(n);`
  → both print `1`. Keep `everyStop`/`someStop` in `08_arrays_json.js`.

How fix 25 was found (reuse this *method*, not more unprobed sweeps): C
`js_function_call` does `argc = max_int(argc, 1)`; Zig omitted it. The VM
passes **original** argc (0 for `fn.call()`), while `fd.arg_count` only
**pads** argv. `newTailCall(-1)` is `JS_EXCEPTION` (EX_NORMAL), not a tail
call. **Still probe C vs Zig before editing** — static mismatch alone is
not enough (see false fix 29).

---

## Historical: Typescript `Parse errors.` (Octane — fixed)

Was intermittent `parseErrors.length` not 192/193 when intern/property keys
were wrong. Resolved with fixes 7–9 and `js_create_property` popValue.

For isolated repro without full Octane: heap pressure from earlier suites;
do not use `mqjs tests/octane/run.js <suite>` for isolated Octane discovery
(use `zig build octane` as the gate). The host argv SEGV that used to crash
the second arg is **fixed** (fix 18). Wrappers:
avoid globals `files` / `i`; use `octane_file_list`. Pipe with `stdbuf -oL`.

gdb on silent SEGV: `mov -0x1(%reg)` is `valueToPtr`. `rax=0x7` is `JS_NULL`.

---

## `mqjs tests/octane/run.js <suite>` (host argv — fixed)

Was a host bug: `script_argv.ptr` as C `char **` with Zig slices. Second arg
SEGVd. Fixed in fix 18. Full Octane via `zig build octane` remains the
regression gate.

---

## JS_POP_VALUE audit checklist (Phase 1A — fill in)

| File:line | C ref | Verdict | Notes |
|-----------|-------|---------|-------|
| `mquickjs_builtins_string_lib.zig:377` | `mquickjs.c:17929-17937` | **must fix — fixed** | C reloads `val` with `JS_POP_VALUE` after `JS_StackCheck`; Zig discarded it, then passed stale `val` to `JS_PushArg`. |
| `mquickjs_builtins_string_lib.zig:512,542` | `mquickjs.c:18075-18078,18108` | safe | `capture_buf` root cleanup; value is not used after pop. |
| `mquickjs_builtins_string_lib.zig:605-606,613,619-620,626-627,630` | `mquickjs.c:18179-18191,18291-18306` | safe | Split early-return/error cleanup; discarded roots are not reused, and `A` is reloaded only where returned. |
| `mquickjs_builtins_string_lib.zig:644-645,651-652,657-658,662` | `mquickjs.c:18203-18211,18291-18306` | safe | Empty-input regexp split cleanup; no popped local is subsequently used. |
| `mquickjs_builtins_string_lib.zig:671-672,686-687,702-703,709-710,714,727-728` | `mquickjs.c:18214-18267,18299-18306` | safe | Regexp split loop error/return cleanup; live values are accessed through `A_ref`/`z_ref` before cleanup. |
| `mquickjs_builtins_string_lib.zig:743-744,749-750,754,768-769,775-776,780,791-792,797-798,802` | `mquickjs.c:18268-18306` | safe | String split tail/error/return cleanup; popped locals are not reused. |
| `mquickjs_builtins_string_lib.zig:849` | `mquickjs.c:18332-18359` | safe | `result` root cleanup; function returns the reloaded `A` root. |
| `mquickjs_builtins_regexp_lib.zig:1956,1966,1974,1988,1999` | `mquickjs.c:17852-17897` | safe | `capture_buf` cleanup on failure/done; value is not used after pop. `obj` reloads already match C at property/sub-string allocation sites. |
| `mquickjs_parser_lib.zig:257-258` | `mquickjs.c:11013-11014` | safe | Function ends immediately after both pops; C assigns locals but never reads them. |
| `mquickjs_value_lib.zig:1595-1596` | `mquickjs.c:2883-2889` | safe | Allocation-failure cleanup returns immediately; successful-path reloads are already fixed below this branch. |
| `mquickjs_builtins_array_lib.zig:256,260` | `mquickjs.c:14327,14332` | safe | `sep` cleanup immediately before return; concatenation uses `sep_ref.val` while rooted. |
| `mquickjs_builtins_std_lib.zig:639` | `mquickjs.c:15544` | safe | JSON quote helper does not use `str` after pop. |

---

## Audit session log (2026-08-15)

| Turn | What | Result |
|------|------|--------|
| GPT | Phase 1A checklist; fixes 10–11 (string replace `val`, error backtrace) | Octane 9/9 clean |
| Opus | Phase 1B–1D static; fix 12 (debug bytecode layout); difftest harness | — |
| Opus | `./tests/difftest/` vs C; fix 13 (trig negative inputs) | 156 hostile diffs → 0 |
| User | Tests still pass after fix 13 + harness | Octane gate OK for now |
| Opus | libm signedness sweep (clean); fix 14 (JSON atod scratch buffer) | difftest 18 added, ALL MATCH |
| Opus | `js_alloc_byte_array` sweep (clean); difftest 19 + 20 added | no bug found; ALL MATCH, Octane gate still pending |
| User | Octane batch after fix 14 | no regressions — gate confirmed |
| Opus | Deterministic Octane differential; GC-root and opcode structural audits (all clean); fix 15 (32-bit float64 block size) | found by bytecode diffing; `bytecode.sh` added |
| Opus | Struct layout sweep vs C `sizeof`/`offsetof`; fix 16 (`JSCFunctionDef` table stride 16 vs 24) | `print(Math.sin)` was `concat()`, `print(Date)` SEGV; difftest 21 added |
| Opus | Fix 17 (`js_dump_object` missing `default:`); Date/ArrayBuffer/typed-array print was blank | difftest 21 extended; ALL MATCH |
| Opus | Fix 18 (host `scriptArgs` argv: slice-of-slices as `char **` SEGV) | `run.js <suite>` no longer SEGVs; difftest 22 added |
| Opus | Fix 19 (`JS_DumpMemory` tag-line missing `\\n`); load()/console probed | `mqjs -d` table was one line; difftest 23 added |
| Opus | Fix 20 (`js_parse_function` re-lexed first body token); `-dd` dump format | extra leftover `"var"`/`"return"`; difftest 24 added |
| Opus | Host `-e`/`-I`/`-o` dump/`dump_error` stacks/`-b` (clean); `-dd` hash-chain EXTRA is `hash_prop` of absolute/ROM pointers (ASLR, not leftover ident — tag tables and leftover `"var"` offsets match). Fix 21 (default-arg skip ate later params) | Zig-only; C cannot parse the repro; ALL MATCH |
| Opus | Leftover-ident counts + `-d` tags on all 24 difftest scripts; `-o` opcode/cpool/vars/stack_size/pc2line + `--no-column`; `-m32` same; compile-time `-o -d`; Function/setTimeout/stacks; more host file/CLI edges | **no bug**; that non-output class is saturated |
| Opus (2026-09-14) | Four instrumented trace differentials vs C: compiled regexp bytecode (5261 compiles), GC per-collection accounting, VM per-opcode trace (11M ops), regexp interpreter trace (9.49e9 steps) | **no bug**; see "Instrumented trace differentials" for the checkpoint-hash method |
| Grok (2026-09-14) | ReleaseSafe phase: relax build guard; `valueToPtr` tagged-pointer safety; wrapping arithmetic (kernelExp/pow/sincos/dtoa/ToInt32/hashProp/short-float); `classObj` from FAM; 64to32 offset-0 as usize | difftest + bytecode.sh ALL MATCH in ReleaseSafe and ReleaseFast |
| Grok (2026-09-14) | Debug: `js_vprintf` `callconv(.c)` (`@cVaArg`); `setjmp` as direct libc extern from `JS_Parse2` (`callconv(.c)`) — wrapper was not inlined, JSON.parse longjmp SEGVd `14_hostile_args.js` | Debug 16M `run.sh` ALL MATCH vs C; user: Fast `-o` exact, Safe padding-only (expected) |
| Grok (2026-09-14 night) | `tests/zigonly/` expected-output suite (fix 21 defaults, let/const-as-var, global eval); Debug `bytecode.sh` | zigonly ALL MATCH Fast/Safe/Debug + `-o`/`-b` roundtrip; Debug bytecode ALL MATCH (28× 64-bit padding notes, no SIZE/EXEC DIFF); `run-safe.sh` now includes zigonly |
| Grok (2026-09-14 night) | Independent `tests/oracle/` (no C); fix 22 (default-arg `/` re-lexed as division) | oracle ALL MATCH Fast/Safe; zigonly ALL MATCH |
| Grok (2026-09-14 night) | Fix 23: bind `arguments` / inner name before default-arg emission; skip-assign bits for `arguments` | oracle 07; Fast/Safe |
| Grok (2026-09-14 night) | Fix 24: `js_skip_assign_expr` also sets `HAS_FUNC_NAME` when a default mentions the inner name | oracle 07 named-only/method/shorthand/eval |
| Grok (2026-09-14 night) | Fix 25: `fn.call()` argc 0 omitted C `max_int(argc, 1)`; `newTailCall(-1)` threw `?` | difftest 25; oracle 08; Fast/Safe gates; Octane pending |
| Grok (2026-09-14 night) | Post-25 runtime sweep (call/apply/bind leftovers, default-arg edges, JSON, typed arrays, Function() GC) | **no bug**; that probe class is saturated — next is static C-vs-Zig |
| Grok (2026-09-14 night) | Notes + cursor rule: regression mode DONE as discovery; CURRENT handoff is static analysis vs C | — |
| Grok (2026-09-14 night) | Fix 27 applied then reverted: C `JS_CFUNC_f_f` dead-stores EXCEPTION → NaN; Zig/Node throw | oracle 09; do not match C |
| Grok (2026-09-15) | Fix 28: array literal missing comma parsed as implicit comma (`[1 2]` → `[1, 2]`) | difftest 28; C `goto done` |
| Grok (2026-09-15) | **False fix 29 (reverted):** treated Zig `break` in `js_array_every` switch as C switch-break. User wasm probe: `every` short-circuit `n=1`. Unlabeled Zig `break` already exits the `while`. | `08_arrays_json.js` `everyStop`/`someStop` kept as C-diff coverage |
| Grok (2026-09-15) | Static C-vs-Zig: `js_string_split`/`replace`/`concat_subst`; `js_array_concat`/`indexOf`/`slice`/`splice`; JS_Call slow paths (`js_add_slow` / binary+unary arith / logic / relational / `js_eq_slow` / `js_for_of_start`/`next`). No omitted clamp, argc, or continue-after-goto. `captures_len-1` only runs when `capture_buf` is set; regexp `capture_count` starts at 1. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: parser unary/postfix/logical + cond/assign/comma (direct-eval skip is documented); `get_lvalue`/`put_lvalue`; `js_error_toString`; Date ctor/now; `JS_DefinePropertyInternal`/`js_create_property`; `JS_DeleteProperty`; `JS_ToUint8Clamp`; `define_var`/`js_parse_var`; OP_put_field/put_array_el/define_field; `js_operator_in`/`instanceof`/`typeof`; JSON parse/quote/stringify; `js_string_indexOf`; `js_parse_function_decl` C path; array ctor/push/pop/shift/reverse; FRAME_CF_CTOR sites; typed-array ctor/subarray/`JS_ToIndex`; apply/bind/bound; `js_math_clz32`; `JS_ToPropertyKey`; `compute_stack_size`; `js_fmod` wrapper. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `js_object_keys`/`hasOwnProperty`; `JS_ToBool` + OP_if_false/if_true/lnot; `js_parse_string`/`js_parse_escape`; postfix `new`/object/array/`./[`/`++` (minus documented direct eval); `js_parse_property_name`; statement try/switch remaining states; `js_exp`/`kernelLog2`/`js_log`/`log2`/`log10`; `js_math_min_max`/`sign`/`fround`/`imul`; `js_string_fromCharCode`/`concat`. hypot/cbrt/hyperbolic are **not in this engine**. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `js_object_defineProperty`/`getPrototypeOf`/`setPrototypeOf`/`create`; `js_string_slice`/`substring`/`charAt`; `js_regexp_exec`/`match`/`search`; `js_scalbn`; `js_fmin`/`fmax`; `js_get_array`/`js_array_resize`; `string_getcp`/`js_sub_string`/`js_sub_string_utf8`; `js_string_convert_pos`; `jsSinCos`/`js_asin`; floor/ceil/trunc wrappers. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `js_acos`/`js_atan`/`js_pow`/`js_round_inf`/`rintSf64`; `js_array_join`/`reduce`/`sort`/`rqsort_idx`; `js_string_toLowerCase`/`trim`/`constructor`; `js_typed_array_set`; `js_global_eval`/`isNaN`/`isFinite`; parser statement if/while/do/for/return/throw (let/const-as-var documented); unary `TOK_POW`; remaining JS_Call CFUNC types; `JS_ToPrimitive`/`ToString`/`ToNumber`/`js_atod1`; `js_get_object_class`; `js_function_get_length_name1`; coerce add/arith/logic/relational/`js_eq_slow`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `jsSqrtSoft` vs `__ieee754_sqrt` (dead on this arch; live `js_sqrt` is hw `@sqrt` vs C `sqrt`); `js_rem_pio2`/`remPio2Large`/`kernelSin`/`kernelCos`; Get/SetProperty typed-array elements; `JS_IsNumericProperty`; `js_for_of_start`/`next`; Date host ctor; regexp flags/parse/constructor; `JS_HasProperty`; `findOwnPropertyInlined`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: OP_throw/catch/gosub/ret + exception unwind + `JS_Throw`; `lre_exec` (poll/stack/save/split/lookahead/range/backref); `js_atod` prefix/digits/exp/`build_float`; `js_dtoa_max_len`; OP_drop/nip/dup. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: remaining `js_dtoa` output + `output_digits`/`mul_pow`/`mul_pow_round`/`round_to_d`/`insert_dot`; OP insert/perm/swap + get/put loc/arg/var_ref; `js_function_get/set_prototype`/`toString`; `js_number_toString`/`toFixed`; `js_object_toString`; `js_math_atan2`/`pow`/`random`; `js_tan` (`USE_TAN_SHORTCUT`); `js_error_get_message`; `js_array_get_length`/`isArray`; `js_typed_array_constructor`; parser break/continue/labels; `js_dtoa2`; `JS_ToInt32Sat`/`ToUint32`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `mpb_shr_round`/`mpb_cmp`/`mpb_get_bit`; `JS_ToInt32Internal`; JSON stringify recursion; `js_atan2` internals; OP_get_field/get_length/put_field/get_array_el (+ *2 fallthroughs); parser `put_var`/`emit_var`; `js_parse_json_value`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: GetProperty string/char/`STRING_CHAR`; Date `valueOf`; `skip_spaces`; `js_operator_typeof`/`js_eq_get_type`; OP plus/neg/inc/dec/post_inc/not/shl/shr/sar; `js_pow` libm internals; `js_string_get/set_length`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: OP add/sub/mul/div/mod/pow fast paths; `js_not_slow`; `kernelExp`/`js_exp`; `next_token`/`parseNumber`; `is_regexp_allowed`; `js_parse_ident`; `js_parse_get/seek_pos`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `js_skip_parens`/`js_skip_expr`/`js_parse_skip_parens_token`; `get_special_prop`/`js_update_props`; SetPropertyInternal leftover (proto lookup / ROM convert / getter-setter); `js_add_slow` + `JS_ConcatString`/`string_buffer_*`; OP delete/for_in/for_of; `JS_DeleteProperty`; `js_typed_array_get_length`/`subarray`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: OP arguments/fclosure/call/call_method/call_constructor/array_from/regexp/object/this_func/new_target; `js_closure`/`js_reverse_val`/`get_var_ref`/`add_global_var`; generic_function_call + CFUNC dispatch; `js_compact_props`/`js_rehash_props`/`get_prop_hash_size_log2`/`js_shrink_value_array`; `js_json_parse`/`js_parse_json`; `js_call_constructor_start`; `__js_poll_interrupt`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: JS_Call generic_return/return_call (varref detach + ctor this + POP_RET/PC_ADD1); `js_parse_program`/`js_parse_source_element`/`js_parse_local_functions`; `convert_ext_vars*`; `resolve_var_refs`/`reset_parse_state`; `find_func_var`/`find_func_ext_var`/`add_func_ext_var`; `JS_NewDate`/`js_date_valueOf`; host Date ctor/now. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `compute_stack_size`/`compute_stack_size_push` (return/throw skip-push ≡ C `goto done`); `add_var`/`js_resize_value_array2`; `js_parse_push_val`/`pop_val`/`parse_stack_alloc`; opcode_info call/array_from vs `mquickjs_opcode.h`; mqjs `js_load`/`load_file`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `JS_Parse2`/`jsParseBody`/`handleParseError`; mqjs `js_print`/`dump_error`; emit leftover (`emit_op_pos`/`param`/`insert`/`label*`/`goto`/`cpool_add`/`js_emit_push_const`/`emit_var`); `js_alloc_function_bytecode`; `js_object_constructor`; ArrayBuffer leftover; `JS_NewObject*`; `js_new_c_function_proto`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `js_parse_statement` leftover (`push/pop_break_entry`/`emit_return`/`emit_break`/`js_parse_block`/`js_parse_var`); `JS_MakeUniqueString`/`find_atom`; `get_mblock_size`/`gc_mark`/`flush`/`mark_all`; `gc_thread_block`/`gc_compact_heap`; `JS_GC`/`JS_GC2`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `JS_NewContext2`/`JS_FreeContext`; `stdlib_init`/`stdlib_init_class` (no `JS_SetPropertyFunctionList` in C); `JS_PrepareBytecode`/`JS_PrepareBytecode64to32`; `JS_StackCheck`/`js_malloc`/`js_mallocz`/`check_free_mem`; `js_number_constructor`/`js_boolean_constructor`; regexp lastIndex/source/flags. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `JS_DumpMemory`/`JS_DumpUniqueStrings`; `JS_PrintValueF` leftover + `js_dump_object`/`dump_string`; mqjs `eval_file`/`eval_buf`/`compile_file`; `JS_ToString` leftover + `JS_ToStringCheckObject`/`JS_ToPrimitive`/`js_dtoa2`; `JS_IsPrimitive`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `reloc_c_func_name` (identity); `JS_Throw`/`ThrowError`/`ThrowOutOfMemory`/`ThrowTypeErrorNotAnObject`; `build_backtrace`/`get_func_name`; `get_short_string`; `js_vprintf`; mqjs `main`/`setTimeout`/`runTimers`/`repl_run`; `JS_NewStringLen`; `JS_ToCStringLen`; `js_get_length32`; number `toExponential`/`toPrecision`/`parseInt`/`parseFloat`; `JS_Get/SetPropertyUint32`; `js_parse_call`; `JS_NewCFunctionParams`; `js_is_live_code`; array `set_length`/`toString`; `JS_NewArray`; typed-array `constructor_obj`; `JS_IsBytecode`/`RelocateBytecode*`/`LoadBytecode`; `js_function_constructor`. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: remaining `string_buffer_*` + `js_alloc/resize/shrink_byte_array`/`js_byte_array_to_string`; `JS_SetPropertyStr`/`JS_ToPropertyKey`; `JS_GetGlobalObject`; intern leftover (`js_is_numeric_string`/`find_atom`); `get_u8`/`get_u16`/`get_i8`/`get_i16`; `js_parse_expect*`/`js_parse_error*`; `JS_SetInterruptHandler`/`JS_GetClassID`. `dump_byte_code` is C-only (`__maybe_unused`); Zig has no port; `DUMP_FUNC_BYTECODE`/`DUMP_EXEC` off in both shipping trees. | **no Zig-only bug**; no engine edit |
| Grok (2026-09-15) | Static C-vs-Zig: `JS_SetOpaque`/`JS_GetOpaque`; `js_emit_push_number`/`JS_NewFloat64`/`__JS_NewFloat64`/`js_to_short_float`; `js_emit_delete` + unary delete/`TOK_POW`; `js_emit_push_const`; `JS_ConcatString` + `js_function_toString`; `JS_NewObjectClassUser`/`JS_NewObjectPrealloc`; `js_set_prototype_internal` + OP_set_proto; `js_error_constructor`; `JS_Parse`/`JS_Run`/`JS_Eval`. | **no Zig-only bug**; no engine edit |

### Instrumented trace differentials — clean (2026-09-14)

Four **internal traces** compared against C, none of which is program output.
`mquickjs.c` already has the C side of each behind an `#ifdef` in
`mquickjs_priv.h` (`DUMP_REOP`, `DUMP_GC`, `DUMP_EXEC`, `DUMP_REEXEC`); the
Zig side was added temporarily, compared, then reverted. **All four match.**

| Probe | C hook | Coverage | Result |
|-------|--------|----------|--------|
| Compiled regexp bytecode | `js_parse_regexp` (`mquickjs.c:16926`) | 5261 compiles | byte-identical |
| GC heap accounting per collection | `JS_GC2` (`mquickjs.c:12442`) | 24 scripts x 256M/16M/4M | identical |
| VM per-opcode trace (`sp`/`pc`/opcode) | `JS_CallInternal` (`mquickjs.c:5137`) | 11M opcodes, 23 scripts | identical |
| Regexp interpreter trace (`pc`/`cp`/`bp`/`sp`/opcode) | `lre_exec` (`mquickjs.c:17120`) | 2.4M steps breadth + 9.49e9 deep | identical |

Method notes, because the naive version of this does not work:

- **Never write per-step text traces.** `slow/17_regexp_deep.js` executes
  **9,490,890,752** regexp steps. One line per step is ~34 GB per engine and
  does not finish. Instead keep an in-engine FNV-1a rolling hash over the same
  per-step tuple and print a checkpoint (`step count`, `hash`) every 4096
  steps. Identical sensitivity — the hash chains every step, so any single
  differing step changes every later checkpoint — at ~85 MB and ~5 min/engine.
- Keep the hash to **one multiply-xor per value** (5 per step). A byte-wise
  FNV loop (40 rounds/step) made the deep suite unfinishable on its own.
- **Never print per call** (e.g. one line per `lre_exec` entry). Unbounded:
  a zero-width-match `/g` corpus produced 57M calls and another 42 GB file.
- **Time any new corpus on a stock engine before instrumenting it.** The first
  regexp-exec corpus looked small (16k cases) but included `/g` patterns that
  can match empty, so `replace`/`split`/`match` iterated over every position
  forever. The fixed corpus (non-global only) runs in 28 ms.
- For the regexp interpreter, **breadth beats depth**: 16k distinct
  pattern/subject pairs (2.4M steps, 47 ms) visit far more opcode paths than
  9.5e9 steps of catastrophic backtracking, which re-runs the same few opcodes.
- Print opcode **numbers**, not names, so the Zig side needs no name table.
  Opcode numbering is already a hard invariant (images are cross-loadable).

Instrument a copy of the C tree under `/tmp`, never `../mquickjs` itself.

### ReleaseSafe phase — DONE for the difftest corpus (2026-09-14)

**Why this was the highest-value work.** Differential testing against C has
saturated: every *comparable* surface matches. Two classes are invisible to C
differencing **by construction**:

1. **ReleaseFast-only illegal behavior.** `@intCast` / `@alignCast` / signed
   overflow that C wraps or never dereferences. Fixes 1, 5, 13, the
   `kernelExp` spots, and the sites below are this class.
2. **Zig-only features.** Invisible to the C differential harness.
   Covered by `tests/zigonly/` (fix 21 defaults, `let`/`const`-as-`var`,
   global-`eval`). Add a script there when a new Zig-only path lands.

**Status:** `zig build -Doptimize=ReleaseSafe` runs the 24-script difftest
corpus, `tests/test_{builtin,closure,language,loop}.js`, and
`tests/difftest/bytecode.sh` (`-o` and `-m32 -o`) with **no panics**. stdout,
exit codes, and bytecode sizes still ALL MATCH vs C. ReleaseFast is unbroken.
`./tests/difftest/run-safe.sh` is the panic gate (run.sh + bytecode.sh + zigonly + oracle at 16M).

`build.zig` no longer refuses Debug/ReleaseSafe; it prints a "test mode,
slower" note. Debug **compiles**. `setjmp` must be a direct libc call from
`JS_Parse2` (`callconv(.c)`): a Zig wrapper is not inlined in Debug, so
`longjmp` from `js_parse_error` resumed a dead frame — that was the
`14_hostile_args.js` `JSON.parse` SEGV at address 0x8. Dump/print and the
full 16M difftest corpus now ALL MATCH vs C under Debug.

**Payoff:** a ReleaseSafe panic from here on is a genuine bug. Keep
ReleaseFast as shipping/perf; ReleaseSafe is a test mode. Octane under
ReleaseSafe **passes** (user-confirmed 2026-09-14 evening).

#### Site table (verdict: (a) real latent UB, (b) safe-but-unprovable pattern)

| Site | Shape | Verdict |
|------|-------|---------|
| `build.zig` Debug/ReleaseSafe guard | refused tagged-pointer alignment | (b) relaxed to a note; ReleaseFast stays default |
| `valueToPtr` | `val - 1` underflows at 0; result unaligned when `val` is not a pointer | **(b)** `@setRuntimeSafety(false)` + wrapping sub + return `*align(JSWord)`. Callers' `@alignCast` become no-ops. One site instead of 414. Dereferencing a non-pointer still faults. |
| `find_var` speculative `valueArr` before `local_vars_len` | empty var list → unaligned `val-1` | **(b)** covered by `valueToPtr`; C computes the same garbage pointer and never reads it |
| `classObj` / `classObjBase` | `x.class_obj.?` then `@ptrCast` to `[*]JSValue` | **(b)** derive `class_proto + class_count` (C invariant `mquickjs.c:239,3571`) |
| `gc_update_threaded_pointers` 64to32 | `@ptrFromInt(new_offset)` with offset 0 | **(b)** take `usize` and `valueFromAddr`. C casts `(uint8_t *)new_offset` (`mquickjs.c:12736`); 0 is the first live block, not a null dereference |
| `kernelExp` `@intCast(getHighWord(zz))` + `n<<20` | signed/unsigned reinterpret; `n < 0` on `exp(x<0)` | **(a)** `@bitCast` + wrapping add. Settles the long-standing latent item (`libm.c:1865-1870`) |
| `js_pow` `setHighWord(@intCast(n & ~mask))` | `n` negative when `z < 1` | **(a)** `@bitCast` (`libm.c:2247`) |
| `jsSinCos` `n + flag` | `n` is modular reinterpret of a negative quadrant | **(a)** wrapping add (`libm.c:1138`) |
| `remPio2Large` 128-bit accumulators | wrap detected by `sum < addend` | **(a)** wrapping add (`libm.c:865-872, 899-911`) |
| `intFromFloat` negate of `0x80000000` | ToInt32 modulo 2^32 | **(a)** wrapping negate (`mquickjs.c:4375-4376`) |
| `js_get_short_float` `rotl64 + ADDEND` | tagged-float encoding wrap | **(a)** wrapping add |
| `hashProp` `@intCast((prop/jsw)^(prop%jsw))` | pointer keys, C returns `uint32_t` | **(a)** `@truncate` (`mquickjs.c:2451-2454`) |
| `dtoa` `udiv1norm` extra `- d` | unsigned borrow into `q` | **(a)** wrapping sub/add (`dtoa.c:127-129`) |
| `js_vprintf` `@cVaArg` | Debug self-hosted backend: `auto does not support var args` | **(b)** `callconv(.c)` on the consumer of an already-started `va_list` (`mquickjs_utils_lib.zig`). LLVM (ReleaseSafe/Fast) already accepted `.auto`. |
| `sjlj.setjmp` wrapper | Debug does not inline; `longjmp` resumed a dead frame | **(a)** `pub extern fn setjmp` called directly from `JS_Parse2` (`callconv(.c)`). ReleaseFast/Safe inlined the wrapper so JSON.parse errors looked fine. |

Do not sprinkle more `@setRuntimeSafety(false)`. `valueToPtr` is the one
tagged-pointer exception, with a comment naming the invariant.

### Next phase: Zig-only coverage + finish the Debug gate — DONE (2026-09-14 night)

C-comparable surfaces, ReleaseSafe/Octane, Zig-only core coverage, and Debug
`bytecode.sh` are **done as discovery**.

1. **`tests/zigonly/`** — expected-output suite (no C oracle). Fast, Safe, and
   Debug all ALL ZIGONLY MATCH, including `-o`/`-b` roundtrip.
   - `01_default_args.js`: fix 21 lock-in — `f(a=1,b=2)`, `f(a,b=2)`,
     `b = a + 1`, `(1, 2)`, `[1,2]`, `{x:1}`, `Math.max(1,2)`, `f(undefined)`
     uses the default, plus nested commas in `[]`/`{}`/`()`/`Math.max` with a
     later parameter. `f(null)` does **not** take the default (strict `===`
     undefined).
   - `02_let_const.js`: documented `let`/`const`-as-`var` — hoisted
     (`typeof` before init is `"undefined"`), redeclare, `const` reassign,
     block leak, `var`/`let` mix, function-scope inner redeclare, `for (let i)`
     closures share the same `i` (all return 3).
   - `03_eval_global.js`: documented direct-eval-is-global — `eval("g")`
     sees the global, not the function local; `eval("var leaked")` leaks;
     `eval("typeof local")` is `"undefined"`.
   Do not remove these features to match C. Do not change `js_skip_expr`.
2. **Debug `bytecode.sh`** — ALL BYTECODE MATCH (2026-09-14 night). 28× 64-bit
   images differ in 4 padding bytes (same class as Safe; `note:`, not a fail).
   No 32-bit padding notes. No SIZE or EXEC DIFF. Cross-exec (compile on
   C/Zig, run on C/Zig) matches source. `SLOW=1` and Debug Octane remain
   optional, slow — ask the user.

Do **not**: re-run saturated C traces, leftover-ident dumps, struct-layout
sweeps, or "fix" Safe/Debug padding to match Fast. JSObjectExt union 40 vs 48
is not a heap bug.

ReleaseSafe remains the UB detector (`run-safe.sh` = run.sh + bytecode.sh +
zigonly + oracle). A panic there is a genuine bug.

**What's next (regression mode) — DONE as discovery.** Runtime probing of
the old kind is saturated. Optional leftover gates (`SLOW=1`, Debug Octane)
still need a user go-ahead. Add a `tests/zigonly/` or `tests/oracle/` script
when landing a new Zig-only path.

### Next phase: static analysis vs C (CURRENT — 2026-09-14 night)

New yield is the **fix 25 class**: a C line omitted or mis-translated in Zig
that C-diff never hits because the corpus does not exercise the rare branch
(`fn.call()` argc 0, Zig-only defaults, `@intCast` of 0, etc.).

**Method:** open the C function and the Zig function side by side. A line
that *looks* omitted is not enough. **Do not edit engine code until a
runtime probe disagrees with C** (or Zig panics in ReleaseSafe/Debug). Do
not invent more ad-hoc runtime sweeps. Probe recipe:

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
# C-parseable snippet (no Zig-only defaults):
printf '%s\n' 'PROBE_JS_HERE' > /tmp/probe.js
../mquickjs/mqjs --memory-limit 16M /tmp/probe.js
./zig-out/bin/mqjs --memory-limit 16M /tmp/probe.js
```

If both print the same, it is **not** a Zig-only bug. Log it under
"Not bugs" / last-compared and keep hunting. If the snippet needs
Zig-only syntax, use `tests/zigonly/` or `tests/oracle/` **and** still
run it on the current `mqjs` *before* changing the engine (old wasm /
pre-change binary is the baseline).

Hunt:
- omitted `max_int` / argc clamps; C `argc &= ~FRAME_CF_CTOR` vs Zig
  `_ = argc & ~…` (the latter does not clear the flag)
- `return -1` as a `JSValue` where C uses `JS_EXCEPTION` (C-shared
  `js_string_repeat` at `mquickjs.c:13704` is **not** a Zig-only bug)
- `goto done` vs Zig `break` then fallthrough / continue. Zig unlabeled
  `break` inside a `switch` in a `while` **exits the loop** (not C
  switch-break). Probe C vs Zig before treating that as a bug.
- `@intCast` / u32 underflow on values JS can make 0 or negative
  (ReleaseSafe panic class), e.g. `captures_len - 1` if count were 0
- discarded `_ = popValue` after a GC-capable call if the local is used
  after — **new sites only**; Phase 1A table is complete for listed files
- parser: `js_parse_function` default emission vs
  `define_hoisted_functions` `emit_insert(0, …)`; do **not** OR first-pass
  param-list skip bits globally (`function foo(foo) {}` would grow `-o`
  vs C)

Do **not** redo: Phase 1A popValue table, 1B–1D layout/intern, leftover-ident,
instrumented `DUMP_*` traces, post-fix-25 runtime sweep, padding-byte chasing.

`src/wasm_host.zig` is untested by the harness — optional, ask first.

**Last compared (2026-09-15, no new Zig-only bug):** `js_atod`; 64to32
convert+compact+expand; `emit_u*`+cpool; `JS_Run`+`JS_Eval`;
parseInt+toPrecision+toExponential; mqjs print/load/timers/`evalBuf`;
`JS_PrintValueF`; regexp compile+`lre_exec`; `JS_Call` opcode dispatch
(incl. put_field / put_array_el / define_field / set_proto);
`JS_GetPropertyInternal`+Str/Uint32/`HasProperty`;
`JS_SetPropertyInternal`; `JS_DefinePropertyInternal`/`js_create_property`;
`JS_DeleteProperty`; `JS_ToPropertyKey`; `JS_ToUint8Clamp`/`JS_ToInt32Clamp`;
`bc_reloc`/`JS_LoadBytecode`; `js_array_every`/`some` (false 29);
`js_string_split` / replace / `concat_subst` / `indexOf`;
`js_array_concat` / indexOf / slice / splice / ctor / push / pop / shift /
reverse; JS_Call slow paths; parser unary/postfix/logical (minus documented
direct eval) + cond/assign/comma; `get_lvalue`/`put_lvalue`; `define_var`/
`js_parse_var`; `js_parse_function_decl` C path + `define_hoisted_functions`;
`compute_stack_size`; `js_error_toString`; Date ctor/now; JSON parse/quote/
stringify; `js_operator_in`/`instanceof`/`typeof`; typed-array ctor/
subarray/`JS_ToIndex`; apply/bind/bound; FRAME_CF_CTOR sites; `js_math_clz32`;
`js_fmod` wrapper; `js_object_keys`/`hasOwnProperty`; `JS_ToBool` +
OP_if_false/if_true/lnot; `js_parse_string`/`js_parse_escape`; postfix
`new`/object/array/`./[`/`++`; `js_parse_property_name`; statement
try/switch remaining states; `js_exp`/`kernelLog2`/`js_log`/`log2`/`log10`;
`js_math_min_max`/`sign`/`fround`/`imul`; `js_string_fromCharCode`/`concat`;
`js_object_defineProperty`/`getPrototypeOf`/`setPrototypeOf`/`create`;
`js_string_slice`/`substring`/`charAt`; `js_regexp_exec`/`match`/`search`;
`js_scalbn`; `js_fmin`/`fmax`; `js_get_array`/`js_array_resize`;
`string_getcp`/`js_sub_string`/`js_sub_string_utf8`; `js_string_convert_pos`;
`jsSinCos`/`js_asin`; floor/ceil/trunc wrappers;
`js_acos`/`js_atan`/`js_pow`/`js_round_inf`; `js_array_join`/`reduce`/`sort`;
`js_string_toLowerCase`/`trim`; `js_typed_array_set`; `js_global_eval`;
parser if/while/do/for; `JS_ToPrimitive`/`ToString`/`ToNumber`;
`js_get_object_class`; coerce add/eq;
`jsSqrtSoft` (hw `@sqrt` live here); `js_rem_pio2`/`remPio2Large`/
`kernelSin`/`kernelCos`; Get/SetProperty typed-array elements;
`JS_IsNumericProperty`; `js_for_of_start`/`next`; Date host ctor;
regexp flags/parse/constructor; `JS_HasProperty`;
`findOwnPropertyInlined`; OP_throw/catch/gosub/ret + exception unwind;
`lre_exec` poll/stack/save/split/lookahead/range/backref; `js_atod`
prefix/digits/exp; `js_dtoa_max_len`; OP_drop/nip/dup;
remaining `js_dtoa` output + `output_digits`/`mul_pow`/`round_to_d`;
OP insert/perm/swap + get/put loc/arg/var_ref;
`js_function_get/set_prototype`/`toString`; `js_number_toString`/`toFixed`;
`js_object_toString`; `js_math_atan2`/`pow`/`random`; `js_tan`;
`js_error_get_message`; `js_array_get_length`/`isArray`;
`js_typed_array_constructor`; parser break/continue/labels; `js_dtoa2`;
`JS_ToInt32Sat`/`ToUint32`; `mpb_shr_round`/`JS_ToInt32Internal`;
JSON stringify recursion; `js_atan2` internals; OP_get_field/put_field/
get_length/get_array_el; parser `put_var`/`emit_var`; `js_parse_json_value`;
GetProperty string/char/`STRING_CHAR`; Date `valueOf`; `skip_spaces`;
`js_operator_typeof`/`js_eq_get_type`; OP plus/neg/inc/dec/post_inc/not/
shl/shr/sar; `js_pow` libm internals; `js_string_get/set_length`;
OP add/sub/mul/div/mod/pow; `js_not_slow`; `kernelExp`/`js_exp`;
`next_token`/`parseNumber`; `is_regexp_allowed`; `js_parse_ident`;
`js_skip_parens`/`js_skip_expr`; `get_special_prop`/`js_update_props`;
SetPropertyInternal leftover; `js_add_slow` + `JS_ConcatString`;
OP delete/for_in/for_of; `JS_DeleteProperty`; typed-array get_length/subarray;
OP arguments/fclosure/call/array_from; `js_closure`/`js_reverse_val`;
`js_compact_props`/`js_rehash_props`; `js_json_parse`/`js_parse_json`;
JS_Call generic_return/return_call; `js_parse_program`/`js_parse_local_functions`;
`convert_ext_vars*`; `resolve_var_refs`; `JS_NewDate`/`js_date_valueOf`;
`compute_stack_size`; `add_var`; mqjs `js_load`;
`JS_Parse2`/`jsParseBody`; mqjs `js_print`; emit leftover (`label*`/`cpool`/`emit_var`);
`js_object_constructor`; ArrayBuffer leftover; `JS_NewObject*`;
`js_parse_statement` leftover; `JS_MakeUniqueString`; `get_mblock_size`/
`gc_mark`/`compact_heap`; `JS_NewContext2`; `stdlib_init`; `JS_PrepareBytecode`;
`js_malloc`/`JS_StackCheck`; `JS_DumpMemory`;
mqjs `eval_file`; `JS_ToString` leftover; `JS_ToPrimitive`;
`reloc_c_func_name`; `JS_Throw` leftover; mqjs `main` leftover;
`JS_NewStringLen`; `JS_ToCStringLen`; number parseInt/toExponential;
`JS_Get/SetPropertyUint32`; `js_parse_call`; `JS_LoadBytecode`;
`js_function_constructor`; remaining `string_buffer_*`;
`JS_SetPropertyStr`; intern leftover; `js_parse_expect*`;
`JS_GetClassID`. `dump_byte_code` is C-only (DUMP off in both);
`JS_SetOpaque`; `js_emit_push_number`/`delete`; `JS_ConcatString`;
`JS_NewFloat64`; `js_error_constructor`; `JS_Eval`.

**Next hunt:** remaining `js_error_toString` leftover; remaining
`JS_DefinePropertyGetSet`; remaining leftover of remaining OP
`define_field` callers.
C-diff of return values misses side-effect / short-circuit /
throw-order bugs — probe those by printing counts or exception
identity **on both engines first**.

### Deterministic Octane differential — clean

Octane's `run.js` iterates for a *time budget*, so the two engines run
different iteration counts and their final state is not comparable. A
generated per-suite driver (fixed iteration count, `BenchmarkSuite.ResetRNG()`
**before** the suite files load, then an FNV hash of everything reachable from
`globalThis`) makes it comparable. All 15 suites — including mandreel, pdfjs,
typescript, gbemu and zlib — produce identical per-iteration and final hashes
on both engines, with and without a forced `gc()` between iterations, at
512M/64M/24M. At 64M and below mandreel runs out of memory identically on
both.

One trap worth knowing: `crypto.js` seeds its RNG pool at **load** time from
`Math.random`, which both engines seed from the clock, so the hash is
nondeterministic unless `ResetRNG` runs before the file is loaded. Always
sanity-check a state hash by running the same engine twice before believing a
cross-engine difference.

### Structural audits vs C — clean

Two mechanical whole-file comparisons, both worth re-running after large
changes:

- **GC-root discipline per function.** Count `JS_PUSH_VALUE`/`JS_POP_VALUE`
  (and `JS_PushGCRef`/`JS_PopGCRef`) per C function, compare with
  `pushValue`/`popValue` in the same-named Zig function. 66 C functions use GC
  roots; the only mismatches were refactoring artifacts, each verified by
  hand: `JS_SetPropertyInternal` (Zig splits it into
  `setPropertyProtoLookup`/`setPropertyGetSet`/`setPropertyOwnAndProto`,
  4+3+3 = C's 10), `lre_exec` (pushes live in `lreCheckStackSpace` and
  `lrePollInterrupt`, 4 poll sites in both), and extra Zig pops that are
  error-path cleanups. Also checked: `js_create_property` recomputes
  `prop_count`/`hash_mask` after the `empty_props` branch where C does not,
  which is a no-op because `js_alloc_props(ctx, 1)` yields `hash_mask == 0`,
  the same as `empty_props`.
- **Opcode dispatch coverage.** The set of opcodes handled by C's
  `JS_CallInternal` and by the Zig interpreter is identical. Watch for two
  false positives: Zig spells reserved words `OP.@"and"` / `OP.@"or"` /
  `OP.@"catch"` / `OP.@"return"`, and the short opcodes declared with
  lowercase `def(...)` in `mquickjs_opcode.h` (`call0`-`call3`, `goto8`,
  `if_true8`, `push_const8`, `dup1`, `nop`, ...) are handled by neither
  engine because neither emits them.

All remaining `_ = utils.popValue` discard sites are exactly the ones already
in the Phase 1A table — no uncovered files.

### `js_alloc_byte_array` scratch-buffer sweep — done, no divergence

The follow-up to fix 14. Every `js_alloc_byte_array` call site in `src/` was
compared with its C counterpart on **both** axes:

- *What the callee receives.* Fix 14's mistake (passing the block header
  instead of the data area) exists nowhere else. All consumers take
  `vt.byteArrayBuf(arr)`: `js_dtoa2` and `js_atod1`
  (`runtime_coerce_lib.zig:98-113,208-221` vs `mquickjs.c:4113-4125,4252-4268`),
  `js_is_numeric_string` (`value_lib.zig:818-830` vs `mquickjs.c:1952-1963`),
  lexer `parseNumber` (fix 4), the parser explore tab, regexp capture buffers
  and the regexp compiler's `arr->buf` refreshes.
- *How big the block is.* Sizes match C everywhere, including the easily
  missed `max_int(sizeof(JSATODTempMem), sizeof(JSDTOATempMem))` in
  `js_is_numeric_string` — that one buffer is used for an `js_atod` *and* a
  `js_dtoa`, so an ATOD-only allocation would be a fix-14 repeat.
  `byteArrayAllocSize` is `sizeof(header) + n` (8 + n, same as C) and
  `JS_BYTE_ARRAY_SIZE_MAX` is `(1 << 28) - 1` in both.

`js_resize_byte_array` also matches `mquickjs.c:2308-2335` exactly, including
the `old_size + old_size / 2` growth and the `JS_POP_VALUE` reload before the
`memcpy`.

`re_parse_quantifier` (`builtins_regexp_lib.zig:628-725` vs
`mquickjs.c:16410-16578`) was read line by line because it is the densest
raw-pointer code in the port: every `emit_insert` is followed by a fresh
`byteArr(s.byte_code)` / `byteArrayBuf(arr)` exactly where C re-reads
`arr = JS_VALUE_TO_PTR(s->byte_code)`, and no stale `buf` survives a
`re_emit_*` call.

### Difftest 19 and 20 — new coverage, no divergence found

- `19_gc_hooks.js`: 12k-key property tables (grow / delete every third key /
  re-add / `for-in` with a `gc()` mid-enumeration), 4k numeric-string keys,
  accessor properties whose getter and setter call `gc()`, inherited
  accessors, `JSON.stringify` over gc-ing getters, regexp replace/split
  callbacks that collect, `exec` + `lastIndex` across collections, array
  callbacks (`map`/`filter`/`reduce`/`every`/`some`) that collect, a sort
  comparator that collects every 64th compare, `valueOf`/`toString` hooks
  that collect, and `eval`-compiled functions called after a collection.
  This closes the Phase 1C watchlist (`js_object_defineProperty`,
  `hasOwnProperty`, `JS_GetPropertyStr`, JSON stringify keys).
- `20_mutate_reentrant.js`: the re-entrancy angle — comparators that push to
  or truncate the array being sorted, `map`/`filter`/`reduce` callbacks that
  resize the backing array, getters that add or delete properties during
  `JSON.stringify` / `Object.keys` / `for-in`, `valueOf` on an argument that
  truncates the receiver mid-call, `Object.setPrototypeOf` chains and swaps
  under `gc()`, array index/length/`delete` edges, `arguments` aliasing,
  stack-overflow recovery, and surrogate/NUL string edges.

Both match C at 256M/16M/4M/2M. Also verified: at 1M/1200K/800K the two
engines run out of memory at byte-identical points (only `run.sh`'s
truncation warning fires, never a diff), and `tests/test_*.js` +
`mandelbrot.js` match at 256M and 4M.

The engine's builtin surface was enumerated on both engines and is identical;
`print()` of C functions/constructors is covered (fix 16 / difftest 21), as is
`print()` of Date/ArrayBuffer/typed-array *instances* (fix 17). Number/String/
Boolean constructors are unsupported in both engines, so boxed primitives
cannot be constructed from JS. `console.log` and `load()` happy path match
C (probed with fix 19). Missing `load()` target is `perror`+`exit(1)` in
both engines. `scriptArgs` extra argv is covered (fix 18 / difftest 22).
`mqjs -d` dump is covered (fix 19 / difftest 23). `Math.random` is host /
non-deterministic.

### libm signed/unsigned drift — swept, no behavioural divergence

Priority 1 from the previous handoff is **done**. Every remaining unsigned
`getHighWord` site was compared to `libm.c`: `js_scalbn`, `kernelSin`,
`kernelCos`, `jsRemPio2Impl`, `js_atan2`'s sign flip, `kernelExp`, `js_exp`
and `kernelLog2` all mask or `@bitCast` exactly where C does. ~2700 lines of
adversarial values (subnormals, every power of two both signs, `pow`/`atan2`/
`%` cross products, NaN/Inf) are byte-identical to C.

Two **kernelExp** spots that were latent are now **fixed** (ReleaseSafe phase):
`@intCast(getHighWord(zz))` and `@as(u32, @intCast(n << 20))` fired on every
`exp(x)` with `x < 0`. Replaced with `@bitCast` / wrapping add matching C
`libm.c:1865-1870`. See the ReleaseSafe site table.

**Git state:** fixes 1–21 committed; ReleaseSafe + Debug setjmp committed
(`b66e1d8` safe/debug builds, `7f62eac` setjmp). zigonly, oracle, and fixes
22–26, 28 are in the working tree. False "fix 29" was reverted; keep
`everyStop`/`someStop` in `tests/difftest/08_arrays_json.js`. Do not
commit/push unless asked.

---

## Handoff prompt (paste to a new agent)

See bottom of file. The **current** prompt is *Handoff prompt — static
analysis vs C*; regression-mode / Zig-only + Debug gate / post-ReleaseSafe /
ReleaseSafe-phase prompts above it are historical.

---

## Other pitfalls

- Tagged JSValues: `value = ptr + 1`. Use `vt.valueGetInt` for short ints.
- Unique-string insert: `copyBackwards` (C `memmove`).
- Catch bindings cannot be reused (`catch variable already exists`).
- `load()` exists. `scriptArgs[0]` is the script path.
- `OP.COUNT=126`. Labels: `LABEL_RESOLVED_FLAG = 1<<29`,
  `LABEL_OFFSET_MASK = (1<<29)-1`.
- `run.js` `files` loop uses `idx` (safe). Wrappers using `i` stop after
  box2d because minified code clobbers `i`.

---

## Handoff prompt — Post-Octane audit (continued) (paste to new agent)

```
Read debug-notes.md and .cursor/rules/debug-notes.mdc first.
You are continuing the post-Octane correctness audit for zig-mquickjs.
Compare only against ../mquickjs (mquickjs.c + libm.c). Do not search other
workspace dirs. Build -Doptimize=ReleaseFast with Zig 0.16 at
/home/vexcess/zig-x86_64-linux-0.16.0/zig. Home is ecryptfs — set
ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache and
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache or the build panics on
renameat2. Fix one C-verified bug per turn, then stop. Do not rewrite the
GC. Do not commit unless asked.
## Octane gate status
**Clean through fix 21** — user confirmed Octane passes on 2026-09-14. The
gate is NOT blocking: land the next C-verified fix, then ask for a fresh
`zig build octane -Doptimize=ReleaseFast` batch after it.
## What's done (do not redo)
- Fixes 1–21 documented in debug-notes.md — do NOT revert
- Phase 1A–1D static audit: complete. Every `_ = utils.popValue` discard site
  is in the Phase 1A table; there are no uncovered files.
- libm signed/unsigned sweep: clean
- `js_alloc_byte_array` sweep (fix-14 follow-up): clean
- Struct layout sweep: done. Every `*_32` type and runtime overlay compared
  via C sizeof/offsetof vs Zig @sizeOf/@offsetOf. Only two diffs: fix 16
  (JSCFunctionDef 16 vs 24) and JSObject union 16 vs 24 (not a heap bug —
  allocation uses offsetof(u)+extra_size; do not "fix" the union unless a
  site starts using @sizeOf(JSObjectExt)).
- Structural audits vs C, both clean: GC-root push/pop counts, opcode
  dispatch coverage.
- Runtime differential: tests/difftest/ (24 scripts) ALL MATCH at
  256M/16M/4M/2M, both engines OOM identically at 1M/800K
- Bytecode differential: tests/difftest/bytecode.sh ALL BYTECODE MATCH
- Deterministic whole-Octane differential: all 15 suites produce identical
  state hashes at 512M/64M/24M, with and without forced gc()
- Leftover-ident / `-d` tags / `-o` opcodes+metadata / pc2line / `-m32`
  internals / compile-time `-o -d`: saturated this turn, all match C
## Latest fixes this session (do not revert)
- Fix 17 (92bbefb): `js_dump_object` missing C `default:`. Date/ArrayBuffer/
  typed-array instances printed blank. Typed-array dump was dead and used
  byte index instead of element index. Difftest 21 extended.
  Number/String/Boolean constructors are unsupported in both engines.
- Fix 18 (f5a1bcf): host `scriptArgs` SEGV. Zig passed a slice-of-slices as
  C `char **`, so argv[1] read the first arg's length as a pointer.
  `mqjs tests/octane/run.js <suite>` no longer SEGVs. Difftest 22 + `.argv`.
- Fix 19 (d38f6ec): `JS_DumpMemory` tag summary missing `\n`. Heap counts
  already matched C; `mqjs -d` ran every tag onto one line. Difftest 23 +
  `.flags` (`-d`).
- Fix 20 (working tree, not committed): `js_parse_function` always called
  `js_parse_seek_token` after `{`, re-lexing the first body token of every
  function. C (`mquickjs.c:11113-11119`) does not rewind. Extra leftover
  non-unique `"var"`/`"return"`/`"print"` vs C (16-byte string + 8-byte
  free tail). Seek only when `default_count > 0`. Default-arg emission is
  Zig-only (C has no `function f(a = 1)`). Difftest 24 + `.flags` (`-d`).
  After the fix, leftover counts and heap size match C on 01_labels.js and
  the two-function repro.
- Fix 21 (working tree, not committed): Zig-only default-arg skip. First
  pass used `js_skip_expr` (stops only at `)`), so `function f(a = 1, b = 2)`
  never `add_var`'d `b`. `f()` threw `ReferenceError: variable 'b' is not
  defined`. New `js_skip_assign_expr` also returns on `,`. Do not change
  `js_skip_expr` (`for (;; i++, j++)`). No C-compared script — C SyntaxError.
## Discovery method
Script-level differential has saturated except remaining host APIs. Last
real bugs came from comparing things that are *not* normal program output:
scratch pointer (14), emitted image size (15), struct sizeof (16), dump
switch fallthrough (17), host argv layout (18), dump-memory format (19),
function-body first-token re-lex (20). Fix 21 was the Zig-only default-arg
path the previous handoff said to test if it misbehaved.
```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast
./tests/difftest/run.sh          # any stdout/exit-code diff is a port bug
./tests/difftest/bytecode.sh     # any *size* diff is a port bug
SLOW=1 ./tests/difftest/run.sh   # adds slow/17_regexp_deep.js (~2 min)
LIMITS="1M 800K" ./tests/difftest/run.sh   # OOM-boundary comparison
```
Rules in tests/difftest/README.md:
- strip ANSI colour in diffs (run.sh does this)
- every script must end with print("DONE ")
- respect README "Deviations from mquickjs": direct eval = global scope,
  let/const alias var — NOT bugs
- use (1, eval)(...) not bare eval(...) in new scripts
- catch bindings cannot be reused in a scope (name them e1, e2, ...)
- optional sidecar <script>.argv (one arg per line) is appended after the
  script path; <script>.flags (one mqjs option per line) is prepended
  before --memory-limit
## Highest-priority next work
0. **NEW PHASE (2026-09-14): make Debug/ReleaseSafe runnable.** C differential
   has saturated; see "Next phase: make Debug / ReleaseSafe runnable". This is
   now the main line of work and has its own handoff prompt at the very bottom
   of this file. The C-comparison items below are retained as reference only.
1. Octane gate is **clear through fix 21** (user-confirmed 2026-09-14). Land
   the next C-verified fix, then ask for a fresh batch.
2. Leftover-ident / `-d` tags / `-o` opcodes+metadata / pc2line / `-m32`
   internals are **saturated**. So are all four **instrumented internal
   traces** (2026-09-14): compiled regexp bytecode, GC per-collection
   accounting, VM per-opcode trace, regexp interpreter trace. Do not redo
   any of them. The `#ifdef` hooks in `mquickjs_priv.h` that remain unused
   are `DUMP_BYTECODE`/`DUMP_FUNC_BYTECODE` (already covered by `-o`) and
   `DUMP_PC2LINE_STATS` (covered). Read "Instrumented trace differentials"
   for the checkpoint-hash method before building any new trace probe —
   the naive text-trace version writes 34 GB and never finishes.
   Line-by-line `dump_string` / `is_ident_*` / `get_special_prop` is low
   yield after dump probes. Do not treat ROM dump offsets as bugs
   (`val_to_offset` does not check `JS_IS_ROM_PTR`; hex > 0x00100000 is
   ASLR). REPL is skippable. `--memory-limit xyz` is C `assert` abort vs
   Zig SEGV (C debug assert; do not add a ReleaseFast check without a C
   release-build policy). `example.c` / `example_stdlib.c` are outside the
   stated comparison set (`mquickjs.c` + `libm.c`) — ask before probing them.
3. Default-arg path is skip-correct (fix 21). Trailing comma, comma-expr
   defaults, and `Math.max` defaults work on Zig. Further edges only if a
   Zig script misbehaves. Do not remove the feature to match C. Do not
   change `js_skip_expr`.
4. Latent libm only (no repro — do not "fix" without C proof):
   `kernelExp` `@intCast(getHighWord(zz))` and `@as(u32, @intCast(n << 20))`.
   Currently matches C output.
5. JSObjectExt union omits regexp/date/user (sizeof 40 vs 48). Not a heap
   bug. Leave unless @sizeOf(JSObjectExt) starts being used.
6. Latent: Zig `js_vprintf` maps `' '` to `PF_PAD_POS`; C uses `PF_MARK_POS`.
   Neither flag is read. No output diff. Zig also consumes `%*` width;
   C does not increment `fmt` after `*` (would treat `*` as the spec).
   No format string uses `%*`. Do not "fix" either.
## Already probed clean (do not redo)
- Struct layout sweep of every *_32 and runtime overlay
- Adversarial libm sweep; integer conversion / typed-array stores / shifts
- Number↔string; builtin surface enumeration (identical on both engines)
- print() of C functions/constructors (fix 16)
- print() of Date/ArrayBuffer/typed-array instances (fix 17)
- host scriptArgs extra argv (fix 18)
- host mqjs -d JS_DumpMemory summary (fix 19)
- host mqjs -e/--eval, -I include, -o compile dump, dump_error stacks
  (file:line:col), -b bytecode load, clustered shorts
- host mqjs -dd dump format when heaps match (ROM offsets excluded); extra
  leftover ident strings were fix 20, not a dump-printer bug. -dd EXTRA
  hash-bucket diffs with matching tag tables are hash_prop ASLR, not a bug
- Zig default-arg skip (fix 21); trailing comma / comma-expr / Math.max
  defaults work; do not change js_skip_expr
- leftover-ident *counts* and `"var"` offsets on all 24 difftest scripts
  (including large 02/14/15/16/18/19/20); `-d` tag tables match
- `-o` opcode bytes, cpool, vars, ext_vars, stack_size, unique-string
  order, pc2line, `--no-column` images; same for `-m32`; compile-time
  `-o -d` tag tables; tests/test_*.js included
- Function() constructor / toString / bind print; setTimeout(0) /
  clearTimeout / not-a-function; --no-column exception stacks
- empty / comment-only / syntax-error compile+run; `-I` missing; load
  bytecode with and without `-b`; unknown options; `-o` missing args;
  print(Function); JSON.stringify(Date/regexp)
- load() / console.log happy path (nested load, throw-in-load, missing file
  is perror+exit(1) in both)
- 12k property tables, delete/re-add, for-in with mid-enumeration gc()
- Accessor properties whose getter/setter calls gc()
- Callbacks that mutate the array/object a builtin is walking
- setPrototypeOf under gc(), index/length edges, arguments aliasing,
  stack-overflow recovery, surrogate/NUL strings
- All 15 Octane suites under a deterministic fixed-iteration driver
- js_alloc_byte_array scratch-buffer sites; GC-root and opcode audits
- Instrumented internal traces vs C (2026-09-14): compiled regexp bytecode
  (5261 compiles, byte-identical), GC per-collection heap accounting (24
  scripts x 3 limits), VM per-opcode sp/pc/opcode trace (11M opcodes),
  regexp interpreter pc/cp/bp/sp/opcode trace (2.4M breadth + 9.49e9 deep)
## Do NOT do
- Revert fixes 1–21
- Re-apply compact-by-len, MakeUniqueString post-resize extras, or global
  js_resize_value_array2 memcpy change
- "Fix" newShortInt or kernelExp latent spots without C proof
- "Fix" JSObjectExt union size without a site that uses @sizeOf(JSObjectExt)
- "Fix" -dd EXTRA hash-bucket diffs when tag tables / leftover offsets match
  (hash_prop of absolute pointers)
- Change js_skip_expr to also stop at ',' (breaks for-loop third expr)
- Rewrite GC or intern algorithm
- Report direct eval / let-as-var as bugs (documented deviations)
- Report `-m32` padding byte differences as bugs; size differences ARE bugs
- Prefer zig build octane as the Octane gate (run.js argv SEGV is fixed,
  but the build target is still the batch gate)
- Temporarily reintroduce a known bug to "prove" a test catches it
## After each fix
1. zig build -Doptimize=ReleaseFast
2. ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
3. Add or extend a difftest script for the repro
4. Update debug-notes.md (fix N + session log)
5. Ask user to batch Octane (9 runs) before the next fix
## Git state (do not commit unless asked)
Fixes 1–21 are **all committed** (`5eab78a` = fix 20, `739f3ee` = fix 21,
`3441a88` = notes). Working tree is clean. Do not push/commit unless asked.
```

---

## Handoff prompt — ReleaseSafe phase (DONE 2026-09-14; kept for reference)

```
Only edit zig-mquickjs.

Read debug-notes.md and .cursor/rules/debug-notes.mdc first, especially the
section "Next phase: make Debug / ReleaseSafe runnable".

## Mission
Make zig-mquickjs run under -Doptimize=ReleaseSafe (then Debug), so Zig's
runtime safety checks catch undefined behaviour that ReleaseFast silently
allows. This is a NEW phase: differential testing against C has saturated and
is no longer the discovery method. You are not looking for port regressions.
You are making the safety checks runnable, then reading what they report.

## Build
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast      # shipping / perf mode, must keep working
$ZIG build -Doptimize=ReleaseSafe      # the goal (blocked by a guard, see below)
Home is ecryptfs — the two cache vars are mandatory or the build panics in
renameat2. Zig 0.16.

## Starting state (already scoped — do not redo)
- `build.zig:49-52` hard-refuses Debug/ReleaseSafe with the message
  "tagged-pointer JSValues violate Zig's alignment checks". Relax this guard.
  Suggestion: keep ReleaseFast the default and allow ReleaseSafe through,
  rather than deleting the check silently.
- With the guard relaxed, ReleaseSafe **compiles cleanly** — zero compile
  errors. This is purely a runtime-assert problem.
- It then panics on `print("hello")`:
    thread panic: incorrect alignment
    src/mquickjs_parser_emit_lib.zig:389 in find_var
    <- src/mquickjs_parser_expr_lib.zig:158 js_parse_postfix_expr
    <- src/mquickjs_parser_lib.zig:972 JS_Parse2
- Root cause of that first one: `find_var` computes
  `valueArr(b.vars)` + `vt.valueArrayItems(arr)` BEFORE the
  `i < s.local_vars_len` loop bound. With an empty var list `b.vars` is not a
  pointer, `valueToPtr` returns `val - 1` (unaligned), and `@alignCast`
  asserts — even though `local_vars_len == 0` means `items` is never read.
  C computes the same garbage pointer and never dereferences it.

## The archetype you will keep hitting
Speculative pointer casts that are never dereferenced. There are 414
`@alignCast` and 1517 `@intCast` sites and zero `@setRuntimeSafety`
annotations, so expect many.

Fix policy, in order of preference:
1. **Defer the cast** until after the emptiness / length / tag check. This is
   the correct fix and is what `find_var` needs.
2. If a value is legitimately only-sometimes a pointer, guard with the existing
   `vt.isPtr` / tag predicates before casting.
3. Only if 1 and 2 would cost measurable performance on a hot path, wrap the
   narrow scope in `@setRuntimeSafety(false)` **with a comment naming the
   tagged-pointer invariant that makes it safe**. Do not sprinkle this — the
   whole point of the phase is to keep the checks on.

Never "fix" a panic by weakening a cast to `@ptrCast` alone or by widening a
type just to silence the assert. `valueToPtr` is
`@ptrFromInt(@intCast(val - 1))` (`mquickjs_internal.zig:20`); its `@intCast`
also asserts in safe modes when `val == 0`.

## Triage discipline
Every panic is one of two things — say which, in the notes, for each:
- **(a) A real latent bug.** An `@intCast` that can genuinely receive an
  out-of-range value, an OOB index, a wrong enum. These are the prize. Two are
  already suspected and documented: `kernelExp`'s `@intCast(getHighWord(zz))`
  and `@as(u32, @intCast(n << 20))` in `src/libm_lib.zig`. ReleaseSafe may
  finally prove or disprove them — that would settle a long-standing "latent,
  do not touch without C proof" item.
- **(b) A safe-but-unprovable pattern** (the speculative-cast archetype).
  Restructure per the policy above.

## Working rhythm
Work in small increments and keep both modes green:
1. Fix one panic site (or one tight cluster of identical shape).
2. $ZIG build -Doptimize=ReleaseSafe && ./zig-out/bin/mqjs --memory-limit 16M
   /tmp/tiny.js   (`print("hello")` — get this passing first)
3. Then walk up: tests/difftest/*.js under ReleaseSafe, one at a time.
4. Re-verify ReleaseFast is unbroken:
   $ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh
   && ./tests/difftest/bytecode.sh    (both must stay ALL MATCH)
5. Update debug-notes.md as you go: list each site, its shape, and verdict
   (a) or (b). A running table is more useful than prose here.

Do not try to fix all 414 sites in one pass. Getting `print("hello")` to run
under ReleaseSafe is a real milestone; ship that first.

## Definition of done for the phase
- `zig build -Doptimize=ReleaseSafe` runs the whole difftest corpus with no
  panics, and `run.sh` / `bytecode.sh` still ALL MATCH in ReleaseFast.
- Then add a ReleaseSafe run to the regression routine, and re-run the corpus
  plus Octane under it — that is the new UB detector, and any panic it reports
  from then on is a genuine bug.
- Debug mode after ReleaseSafe (Debug adds more checks and is slower; do not
  block on it).

## Do NOT do
- Do not revert fixes 1–21 (all committed, all Octane-gated as of 2026-09-14).
- Do not rewrite the GC or the intern algorithm.
- Do not re-run the saturated C-differential probes (see "Already probed
  clean" and "Instrumented trace differentials"). C comparison is now only a
  tie-breaker when you need to know what C does at a specific line.
- Do not report direct `eval` (global scope) or `let`/`const`-as-`var` as bugs;
  documented deviations.
- Do not disable safety globally, per-file, or by reverting the guard change to
  "ReleaseFast only" once you hit something hard.
- Do not commit or push unless asked.

## Secondary task if you want a small win first
Zig-only features have no tests at all, because the harness is differential and
C cannot parse them. `function f(a = 1)` (fix 21) has no permanent regression
test. A `tests/zigonly/` suite (run against Zig only, expected-output files)
locking in fix 21's cases — `f(a=1,b=2)`, `f(a,b=2)`, `b = a + 1`, `(1, 2)`,
`[1,2]`, `{x:1}`, `Math.max(1,2)`, `f(undefined)` uses the default — plus
`let`/`const` and global-`eval` behaviour, is worth having regardless.

## Git state
Fixes 1–21 all committed; working tree clean except debug-notes.md edits.
Do not commit unless asked.
```

---

## Handoff prompt — post-ReleaseSafe (DONE 2026-09-14 night; kept for reference)

```
Only edit zig-mquickjs.

Read debug-notes.md and .cursor/rules/debug-notes.mdc first, especially
"ReleaseSafe phase — DONE for the difftest corpus".

## Mission
ReleaseSafe is runnable. Use it as the UB detector. A panic under
-Doptimize=ReleaseSafe is a genuine bug. C differential testing is saturated
and is only a tie-breaker. Do not rewrite the GC. Do not commit unless asked.

## Build
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
$ZIG build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
Home is ecryptfs — the two cache vars are mandatory.

## What's done
- Fixes 1–21, all Octane-gated.
- ReleaseSafe: 24-script difftest + test_*.js + bytecode.sh (`-o` and `-m32 -o`)
  no panics, ALL MATCH vs C. Site table in debug-notes.md. Do not revert
  valueToPtr's @setRuntimeSafety, wrapping arithmetic, classObj FAM derivation,
  or gc_update_threaded_pointers taking usize.
- kernelExp latent @intCast spots are fixed (@bitCast / wrapping).
- Debug **compiles** (`js_vprintf` `callconv(.c)`; `setjmp` is a direct libc
  extern from `JS_Parse2`). 16M difftest ALL MATCH vs C.

## Highest-priority next work
1. Octane under ReleaseSafe **passes** (user-confirmed 2026-09-14 evening).
   Do not re-run it for discovery; it is a regression gate after the next fix.
2. Debug **compiles** (`js_vprintf` `callconv(.c)`; `setjmp` is a direct
   libc extern from `JS_Parse2`). `14_hostile_args.js` JSON.parse SEGV is
   fixed; 16M difftest ALL MATCH vs C.
3. Zig-only suite still missing: `tests/zigonly/` for fix 21 default args,
   let/const-as-var, global eval. Highest-yield remaining *test* work: C
   cannot cover these.
4. JSObjectExt union sizeof 40 vs 48 — not a heap bug; leave it.
5. Do not sprinkle more @setRuntimeSafety(false). valueToPtr is the one
   tagged-pointer exception.

## Do NOT do
- Revert fixes 1–21 or the ReleaseSafe site-table changes
- Re-apply compact-by-len / MakeUniqueString extras / global resize memcpy
- Rewrite GC or intern
- Report eval-global / let-as-var as bugs
- Report -m32 padding byte diffs as bugs; size diffs ARE bugs
- Disable safety globally or restore the ReleaseFast-only build guard

## After each fix
1. zig build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
2. zig build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
3. Update debug-notes.md site table if it was a safety panic
4. Ask user to batch Octane (ReleaseFast; ReleaseSafe when it was a safety fix)
## Git state
Fixes 1–21 committed. ReleaseSafe work is in the working tree. Do not
commit/push unless asked.
```

---

## Handoff prompt — Zig-only + Debug gate (DONE 2026-09-14 night; kept for reference)

```
Only edit zig-mquickjs.

Read debug-notes.md and .cursor/rules/debug-notes.mdc first, especially
"Next phase: Zig-only coverage + finish the Debug gate".

## Mission
C differential testing, ReleaseSafe, and Octane (Fast + Safe) are saturated
as discovery. You are not hunting C-vs-Zig stdout diffs. Highest yield:
(1) a Zig-only test suite for features C cannot parse, (2) finish Debug as
a regression gate (`bytecode.sh` under Debug was never completed). Do not
rewrite the GC. Do not commit unless asked.

## Build
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
$ZIG build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
$ZIG build -Doptimize=Debug && LIMITS=16M ./tests/difftest/run.sh
Home is ecryptfs — the two cache vars are mandatory. Zig 0.16.

## What's done (do not redo)
- Fixes 1–21, Octane-gated (ReleaseFast). ReleaseSafe Octane also passes
  (user, 2026-09-14 evening).
- C script/bytecode/trace differentials: saturated. See "Already probed
  clean" and "Instrumented trace differentials".
- ReleaseSafe: 24-script difftest + test_*.js + bytecode.sh, no panics,
  ALL MATCH vs C. Site table in debug-notes.md. Do not revert valueToPtr
  @setRuntimeSafety, wrapping arithmetic, classObj FAM derivation,
  gc_update_threaded_pointers usize, kernelExp @bitCast.
- Debug compiles: js_vprintf is callconv(.c); setjmp is a *direct* libc
  extern from JS_Parse2 (callconv(.c)). A Zig setjmp wrapper is not inlined
  in Debug — that caused 14_hostile_args.js JSON.parse to SEGV. 16M run.sh
  ALL MATCH vs C under Debug.
- ./tests/difftest/run-safe.sh is the ReleaseSafe panic gate.
- User: ReleaseFast -o can be byte-identical to C; ReleaseSafe still has
  padding-byte notes. Expected (stale string tails). Size diffs ARE bugs.

## Highest-priority next work
1. **tests/zigonly/** (highest yield). Zig-only expected-output suite. C
   cannot parse these, so difftest never covers them. Lock in fix 21:
   f(a=1,b=2), f(a,b=2), b = a + 1, (1, 2), [1,2], {x:1}, Math.max(1,2),
   f(undefined) uses the default. Also let/const-as-var and global eval
   (documented deviations — assert the documented behaviour, do not "fix"
   them to match C). Do not change js_skip_expr (breaks for-loop third expr).
2. **Debug bytecode.sh** — never completed after the 14_hostile_args crash.
   Run with Z_MQJS=Debug binary. Padding notes expected; SIZE or EXEC DIFF
   is a bug. Optional: SLOW=1, ask user before Debug Octane (slow).
3. JSObjectExt union sizeof 40 vs 48 — not a heap bug; leave it.
4. Do not sprinkle more @setRuntimeSafety(false). valueToPtr is the one
   tagged-pointer exception.

## Do NOT do
- Revert fixes 1–21 or ReleaseSafe/Debug site-table changes
- Re-apply compact-by-len / MakeUniqueString extras / global resize memcpy
- Rewrite GC or intern
- Report eval-global / let-as-var as bugs
- Report -m32 / Safe / Debug padding byte diffs as bugs; size diffs ARE bugs
- Zero-fill padding to make Safe byte-identical to Fast
- Disable safety globally or restore the ReleaseFast-only build guard
- Re-run saturated C traces / leftover-ident / struct-layout sweeps
- Wrap setjmp in a Zig function (Debug will not inline; longjmp resumes dead)

## After each fix
1. zig build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
2. zig build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
3. If parse/JSON/longjmp: LIMITS=16M Debug run.sh (include 14_hostile_args.js)
4. Update debug-notes.md
5. Ask user to batch Octane after substantive engine fixes
## Git state
Fixes 1–21, ReleaseSafe, and Debug setjmp are committed (b66e1d8, 7f62eac).
Do not commit/push unless asked.
```

---

## Handoff prompt — regression mode (DONE 2026-09-14 night; kept for reference)

```
Only edit zig-mquickjs.

Read debug-notes.md and .cursor/rules/debug-notes.mdc first, especially
"Next phase: Zig-only coverage + finish the Debug gate — DONE".

## Mission
Discovery of the old kind is saturated: C differential, ReleaseSafe, Octane
(Fast + Safe), Zig-only core coverage, and Debug bytecode.sh. You are not
hunting C-vs-Zig stdout diffs or padding bytes. A Safe/Debug panic, a
zigonly expected-output mismatch, or a crash on a new workload is a bug.
Do not rewrite the GC. Do not commit unless asked.

## Build
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh && ./tests/zigonly/run.sh
$ZIG build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
$ZIG build -Doptimize=Debug && LIMITS=16M ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
Home is ecryptfs — the two cache vars are mandatory. Zig 0.16.

## What's done (do not redo)
- Fixes 1–21, Octane-gated (ReleaseFast). ReleaseSafe Octane also passes
  (user, 2026-09-14 evening).
- C script/bytecode/trace differentials: saturated. See "Already probed
  clean" and "Instrumented trace differentials".
- ReleaseSafe: 24-script difftest + test_*.js + bytecode.sh + zigonly, no
  panics, ALL MATCH vs C. Site table in debug-notes.md. Do not revert
  valueToPtr @setRuntimeSafety, wrapping arithmetic, classObj FAM
  derivation, gc_update_threaded_pointers usize, kernelExp @bitCast.
- Debug: js_vprintf is callconv(.c); setjmp is a *direct* libc extern from
  JS_Parse2 (callconv(.c)). Do not wrap setjmp. 16M run.sh ALL MATCH;
  bytecode.sh ALL MATCH (28× 64-bit padding notes, no SIZE/EXEC DIFF).
- tests/zigonly/ locks fix 21 defaults, let/const-as-var, and global eval
  (documented deviations — do not "fix" them to match C). Fast/Safe/Debug
  ALL ZIGONLY MATCH, including -o/-b roundtrip.
- ./tests/difftest/run-safe.sh is the ReleaseSafe panic gate (includes
  zigonly).
- User: ReleaseFast -o can be byte-identical to C; ReleaseSafe/Debug still
  have padding-byte notes. Expected (stale string tails). Size diffs ARE bugs.

## Highest-priority next work
1. Regression: a Safe/Debug panic, zigonly mismatch, or new-workload crash.
   Add a tests/zigonly/ script when landing a new Zig-only path. Do not
   change js_skip_expr (breaks for-loop third expr).
2. Optional leftover gates — ask first: SLOW=1 run.sh, Debug Octane (slow).
3. JSObjectExt union sizeof 40 vs 48 — not a heap bug; leave it.
4. Do not sprinkle more @setRuntimeSafety(false). valueToPtr is the one
   tagged-pointer exception.

## Do NOT do
- Revert fixes 1–21 or ReleaseSafe/Debug site-table changes
- Re-apply compact-by-len / MakeUniqueString extras / global resize memcpy
- Rewrite GC or intern
- Report eval-global / let-as-var as bugs
- Report -m32 / Safe / Debug padding byte diffs as bugs; size diffs ARE bugs
- Zero-fill padding to make Safe byte-identical to Fast
- Disable safety globally or restore the ReleaseFast-only build guard
- Re-run saturated C traces / leftover-ident / struct-layout sweeps
- Wrap setjmp in a Zig function (Debug will not inline; longjmp resumes dead)

## After each fix
1. zig build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh && ./tests/zigonly/run.sh
2. zig build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
3. If parse/JSON/longjmp or bytecode emit: LIMITS=16M Debug run.sh (include
   14_hostile_args.js) && bytecode.sh
4. Update debug-notes.md
5. Ask user to batch Octane after substantive engine fixes
## Git state
Fixes 1–21, ReleaseSafe, and Debug setjmp are committed (b66e1d8, 7f62eac).
tests/zigonly/ and Debug bytecode gating are in the working tree. Do not
commit/push unless asked.
```

---

## Handoff prompt — static analysis vs C (CURRENT; paste to new agent)

```
Only edit zig-mquickjs. Compare only against ../mquickjs (C). Do not
search other workspace dirs. Do not touch src/wasm_host.zig unless asked.
Do not commit unless asked. One real correctness fix per turn. Leave
performance for last. Do not rewrite GC.

Read debug-notes.md and .cursor/rules/debug-notes.mdc first, especially
"Next phase: static analysis vs C", "Probe before every fix", and
"Post-fix-25 runtime sweep". Vincent prefers working directly in code.

## HARD RULE — probe before any engine edit
A static C-vs-Zig mismatch is a hypothesis, not a bug. Do not edit
src/*.zig until you have run the SAME snippet on BOTH engines and shown
they disagree (or Zig panics in ReleaseSafe/Debug).

Recipe (C-parseable JS; no Zig-only default-arg syntax):

export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
# build Zig mqjs if zig-out/bin/mqjs is stale
$ZIG build -Doptimize=ReleaseFast
printf '%s\n' 'PROBE_JS_HERE' > /tmp/probe.js
../mquickjs/mqjs --memory-limit 16M /tmp/probe.js
./zig-out/bin/mqjs --memory-limit 16M /tmp/probe.js

Paste both outputs in your notes. If they MATCH, it is not a Zig-only
bug — log under last-compared / Not bugs and keep hunting. C-diff of
return values misses side-effect / short-circuit / throw-order bugs;
probe those by printing counts or exception identity. Zig-only syntax
goes in tests/zigonly/ or tests/oracle/, but still run the CURRENT mqjs
BEFORE changing the engine (old wasm / pre-change binary is the
baseline). Context going stale is not an excuse to skip this.

## False "fix 29" (reverted 2026-09-15) — do not repeat
Claim: js_array_every/some Zig `break` inside switch only left the
switch, so callbacks kept running (C goto done at mquickjs.c:14648).
Reality: Zig unlabeled `break` exits the enclosing loop, not the
switch (opposite of C). Original code already short-circuited.
User-confirmed on an old wasm build:
  var n=0; [1,2,3].every(function(){ n++; return false; }); print(n);
both engines print 1. The labeled-loop change was reverted. Keep
everyStop/someStop in tests/difftest/08_arrays_json.js. Do not treat
Zig switch-in-while `break` as a C-style switch-break bug.

## Mission
Runtime discovery is saturated (C-diff, ReleaseSafe, Octane through
fix 28, zigonly, oracle, Debug bytecode.sh, post-fix-25 ad-hoc probes).
Find the next correctness bug by static C-vs-Zig function diffs, the
class that produced fix 25.

Fix 25 archetype: C js_function_call does argc = max_int(argc, 1)
(mquickjs.c:13129); Zig omitted it. fn.call() arrived with argc 0;
newTailCall(-1) is a plain JS_EXCEPTION (EX_NORMAL), so the engine
threw nameless "?" instead of invoking with this === undefined.
fd.arg_count only pads argv — the VM still passes original argc.
apply/bind already matched C. Still: that class was proven with a
C-vs-Zig probe before the edit. Do the same.

C is the tie-breaker EXCEPT C JS_CFUNC_f_f (mquickjs.c:5465)
dead-stores JS_EXCEPTION then JS_NewFloat64(NAN). Zig/Node/ES throw.
Do not copy that (oracle 09_math_ff_throw.js). Direct-eval parse is
a documented deviation (C SyntaxError via get_ext_var_name; Zig
allows eval() as global) — do not add C's check. eval always global
and let/const as var are documented deviations — not bugs.

## Build
export ZIG=/home/vexcess/zig-x86_64-linux-0.16.0/zig
export ZIG_LOCAL_CACHE_DIR=/tmp/zig-mquickjs-cache
export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache
$ZIG build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh && ./tests/zigonly/run.sh && ./tests/oracle/run.sh
$ZIG build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
$ZIG build -Doptimize=Debug && LIMITS=16M ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh
Home is ecryptfs — the two cache vars are mandatory. Zig 0.16.

## Method
1. Pick a C builtin/parser/runtime function not in Last compared.
   Open it next to the Zig port. Read every branch, return, argc
   mutation, and error path.
2. If you see a mismatch, write a MINIMAL probe and run the HARD RULE
   recipe. Show C and Zig outputs in the chat. If they match, STOP —
   do not edit engine code.
3. Only then fix one proven bug. Do not batch "while I'm here"
   cleanups. Do not invent more ad-hoc runtime sweeps.

Hunt (highest yield):
- omitted max_int / argc clamps; C argc &= ~FRAME_CF_CTOR vs Zig
  `_ = argc & ~…` (the latter does not clear the flag — grep that)
- return -1 as JSValue where C uses JS_EXCEPTION (C-shared
  js_string_repeat at mquickjs.c:13704 is NOT a Zig-only bug; it is
  the only @bitCast(-1) JSValue site)
- goto done vs Zig that CONTINUES AFTER the switch, or uses
  `continue` wrongly. Unlabeled Zig `break` in switch-in-while
  already exits the loop — see false 29.
- @intCast / u32 underflow on values JS can make 0 or negative
  (ReleaseSafe panic), e.g. captures_len - 1 if count were 0
- discarded `_ = popValue` after a GC-capable call if the local is
  used after — NEW sites only; Phase 1A table is complete for listed
  files. C JS_POP_VALUE assigns the GC-updated pointer back.
- parser: js_parse_function default emission vs
  define_hoisted_functions emit_insert(0, …). Do NOT OR first-pass
  param-list skip bits globally (function foo(foo) {} would grow -o
  vs C). Do not change js_skip_expr / js_parse_get_pos (breaks
  for-loop third expr / regexp-after-')' ).

## Last compared (matched; no Zig-only bug) — skip these
js_atod; convert_mblock_64to32 / get_mblock_size_32 /
gc_compact_heap_64to32 / expand_short_floats /
JS_PrepareBytecode64to32; emit_u8/u16/u32 / emit_claim_size /
cpool_add (and emit_op/pc2line earlier); mqjs evalBuf / print /
load / timers; JS_PrintValueF; js_thisNumberValue / toExponential;
parseInt / parseFloat / toPrecision; js_atod done/fail/overflow/
underflow; get_class_atom / re_parse_char_class /
re_parse_quantifier / re_parse_alternative (incl. capture resume) /
re_parse_disjunction / re_compute_register_count / js_parse_regexp /
re_range_optimize / add_interval_intersect / lre_exec /
js_parse_regexp_flags / js_compile_regexp; JS_Call opcode dispatch
(call/return/exception, get_field2/get_length2/get_array_el2
fallthroughs, put_field / put_array_el / define_field / set_proto);
JS_Run is only the closure+call wrapper;
JS_GetPropertyInternal + Str/Uint32/HasProperty;
JS_SetPropertyInternal (array grow, typed-array write, proto
getter/setter, ROM convert); JS_DefinePropertyInternal /
js_create_property; JS_DeleteProperty; JS_ToPropertyKey;
JS_ToUint8Clamp / JS_ToInt32Clamp; bc_reloc_value /
JS_RelocateBytecode2 / JS_RelocateBytecode / JS_LoadBytecode;
js_array_every / some; js_string_split / replace / concat_subst /
indexOf; js_array_concat / indexOf / slice / splice / ctor / push /
pop / shift / reverse; JS_Call slow paths (js_add_slow, binary/unary
arith, logic, relational, js_eq_slow, js_for_of_start / next);
parser unary / postfix / logical_and_or (minus documented direct
eval) / cond_expr / assign_expr / expr_comma; get_lvalue / put_lvalue;
define_var / js_parse_var; js_parse_function_decl C path /
define_hoisted_functions; compute_stack_size; js_error_toString;
Date ctor / now; JSON parse / quote / stringify; js_operator_in /
instanceof / typeof; typed-array ctor / subarray / JS_ToIndex;
js_function_apply / bind / bound; FRAME_CF_CTOR sites;
js_math_clz32; js_fmod wrapper; js_object_keys / hasOwnProperty;
JS_ToBool + OP_if_false / if_true / lnot; js_parse_string /
js_parse_escape; postfix new / object / array / . / [ / ++ (minus
documented direct eval); js_parse_property_name; statement try /
switch remaining states; js_exp / kernelLog2 / js_log / log2 / log10;
js_math_min_max / sign / fround / imul; js_string_fromCharCode /
concat; js_object_defineProperty / getPrototypeOf / setPrototypeOf /
create; js_string_slice / substring / charAt; js_regexp_exec / match /
search; js_scalbn; js_fmin / js_fmax; js_get_array / js_array_resize;
string_getcp / js_sub_string / js_sub_string_utf8; js_string_convert_pos;
jsSinCos / js_asin; floor / ceil / trunc wrappers;
`js_acos` / `js_atan` / `js_pow` / `js_round_inf` / `rintSf64`;
`js_array_join` / `reduce` / `sort` / `rqsort_idx`;
`js_string_toLowerCase` / `trim` / constructor;
`js_typed_array_set`; `js_global_eval` / `isNaN` / `isFinite`;
parser statement if / while / do / for / return / throw (let/const
as var is documented); unary `TOK_POW`; remaining JS_Call CFUNC
types; `JS_ToPrimitive` / `ToString` / `ToNumber` / `js_atod1`;
`js_get_object_class`; `js_function_get_length_name1`; coerce
add / arith / logic / relational / `js_eq_slow`;
`jsSqrtSoft` (hw `@sqrt` live here) / `js_rem_pio2` / `remPio2Large` /
`kernelSin` / `kernelCos`; Get/SetProperty typed-array elements;
`JS_IsNumericProperty`; `js_for_of_start` / `next`; Date host ctor;
regexp flags / parse / constructor; `JS_HasProperty`;
`findOwnPropertyInlined`; OP_throw / catch / gosub / ret + exception
unwind; `lre_exec` poll / stack / save / split / lookahead / range /
backref; `js_atod` prefix / digits / exp; `js_dtoa_max_len`;
OP_drop / nip / dup; remaining `js_dtoa` output + helpers;
OP insert / perm / swap + get/put loc/arg/var_ref;
`js_function_get/set_prototype` / `toString`; `js_number_toString` /
`toFixed`; `js_object_toString`; `js_math_atan2` / `pow` / `random`;
`js_tan`; `js_error_get_message`; `js_array_get_length` / `isArray`;
`js_typed_array_constructor`; parser break / continue / labels;
`js_dtoa2`; `JS_ToInt32Sat` / `ToUint32`; `mpb_shr_round` /
`JS_ToInt32Internal`; JSON stringify recursion; `js_atan2` internals;
OP_get_field / put_field / get_length / get_array_el; parser `put_var`
/ `emit_var`; `js_parse_json_value`; GetProperty string/char/`STRING_CHAR`;
Date `valueOf`; `skip_spaces`; `js_operator_typeof` / `js_eq_get_type`;
OP plus/neg/inc/dec/post_inc/not/shl/shr/sar; `js_pow` libm internals;
`js_string_get/set_length`; OP add/sub/mul/div/mod/pow; `js_not_slow`;
`kernelExp` / `js_exp`; `next_token` / `parseNumber`; `is_regexp_allowed`;
`js_parse_ident`; `js_skip_parens` / `js_skip_expr`; `get_special_prop` /
`js_update_props`; SetPropertyInternal leftover; `js_add_slow` +
`JS_ConcatString`; OP delete / for_in / for_of; `JS_DeleteProperty`;
typed-array get_length / subarray; OP arguments / fclosure / call /
array_from; `js_closure` / `js_reverse_val`; `js_compact_props` /
`js_rehash_props`; `js_json_parse` / `js_parse_json`; JS_Call generic_return /
return_call; `js_parse_program` / `js_parse_local_functions`;
`convert_ext_vars*`; `resolve_var_refs`; `JS_NewDate` / `js_date_valueOf`;
`compute_stack_size`; `add_var`; mqjs `js_load`; `JS_Parse2` /
`jsParseBody`; mqjs `js_print`; emit leftover (`label*` / `cpool` /
`emit_var`); `js_object_constructor`; ArrayBuffer leftover; `JS_NewObject*`;
`js_parse_statement` leftover; `JS_MakeUniqueString`; `get_mblock_size` /
`gc_mark` / `gc_compact_heap`; `JS_NewContext2`; `stdlib_init`;
`JS_PrepareBytecode`; `js_malloc` / `JS_StackCheck`; `JS_DumpMemory`;
mqjs `eval_file`; `JS_ToString` leftover; `JS_ToPrimitive`;
`reloc_c_func_name`; `JS_Throw` leftover; mqjs `main` leftover;
`JS_NewStringLen`; `JS_ToCStringLen`; number parseInt/toExponential;
`JS_Get/SetPropertyUint32`; `js_parse_call`; `JS_LoadBytecode`;
`js_function_constructor`; remaining `string_buffer_*`;
`JS_SetPropertyStr`; intern leftover; `js_parse_expect*`;
`JS_GetClassID`. `dump_byte_code` is C-only (DUMP off in both);
`JS_SetOpaque`; `js_emit_push_number`/`delete`; `JS_ConcatString`;
`JS_NewFloat64`; `js_error_constructor`; `JS_Eval`.

C-shared (do not "fix"): OP_get_length leftover val for STRING_CHAR;
REOP_range idx_max = idx - 1 unsigned wrap; js_error_constructor
argc &= ~FRAME_CF_CTOR unused after mask; array-literal second loop
(idx >= 32) missing-comma (C same); **= not in TOK_MUL_ASSIGN..
TOK_OR_ASSIGN in either engine; `js_vprintf` space flag unused
(C sets `PF_MARK_POS`, Zig `PF_PAD_POS`); C `%*` does not increment
`fmt` — unused in this tree; `parseInt` always reads `argv[1]`
(call pads); `Array.prototype.toString` passes `argv=NULL` in C /
dummy in Zig with `argc=0`; `dump_byte_code` is C-only under
`DUMP_BYTECODE` (`__maybe_unused`); Zig has no port; both shipping
trees leave `DUMP_FUNC_BYTECODE`/`DUMP_EXEC` off.

## Next hunt (uncompared)
- remaining `js_error_toString` leftover
- remaining `JS_DefinePropertyGetSet`
- remaining leftover of remaining OP `define_field` callers
- hypot / cbrt / hyperbolic / expm1 / log1p are not in this engine

## What's done (do not redo)
- Fixes 1–26 and 28. Octane-gated through 28 (user, 2026-09-15).
  Debug Octane is optional/slow — ask first. Zig is slower than C;
  leave perf last. Do not revert fixes 1–26 or 28.
- C script/bytecode/trace differentials, leftover-ident,
  struct-layout, instrumented DUMP_* traces, Phase 1A–1D
  popValue/layout/intern audits.
- Post-fix-25 runtime sweep (call/apply/bind leftovers, default-arg
  edges, JSON, typed arrays, Function() GC) — no bug.
- ReleaseSafe: run-safe.sh = run.sh + bytecode.sh + zigonly + oracle,
  no panics. Do not revert valueToPtr @setRuntimeSafety, wrapping
  arithmetic, classObj FAM, gc_update_threaded_pointers usize,
  kernelExp @bitCast.
- Debug: js_vprintf callconv(.c); setjmp is a *direct* libc extern
  from JS_Parse2. Do not wrap setjmp.
- tests/zigonly/: fix 21 defaults, let/const-as-var, global eval.
- tests/oracle/: JSON/gc, defaults+gc, defineProperty+gc, math,
  eval+defaults, regexp defaults (22), scope (23–24), call() (25),
  f_f throw (09).
- User: Fast -o can be byte-identical to C; Safe/Debug padding-byte
  notes when sizes match are expected. Size diffs ARE bugs.

## Not bugs (do not "fix")
- eval always global; let/const as var; array holes / write-past-end;
  unsupported ES6+; with is SyntaxError; direct-eval parse
- for (;; /x/.exec()) SyntaxError — is_regexp_allowed(')') is false in C
- "x".repeat({valueOf: throw}) → "?" — C js_string_repeat return -1
- C Math.sin({valueOf: throw}) → NaN is a C dead-store bug; Zig/Node
  throw. Do not copy C. oracle 09.
- sort comparator throw swallowed (C same)
- "Array loo long" typo (C mquickjs.c:14394)
- JSON.parse('"\\u{41}"') → "A"; JSON.parse("01") → 1;
  JSON.parse("1.") → 1
- function.length with defaults is the param count, not ES6 length
- arguments is JS_CLASS_ARRAY here (Array.isArray(arguments) is true)
- reused catch bindings; Octane score noise; -dd hash-bucket ASLR
- JSObjectExt union sizeof 40 vs 48 — not a heap bug
- Zig unlabeled `break` inside `switch` in a `while` exits the loop
  (false 29). Keep everyStop/someStop in 08_arrays_json.js.
- `js_vprintf` space/`*` flags unused in both engines (C space sets
  `PF_MARK_POS`; C `%*` does not increment `fmt`). No `%*` in this tree.

## Do NOT do
- Revert fixes 1–26 or 28, or ReleaseSafe/Debug site-table changes
- Re-apply JS_CFUNC_f_f unconditional NewFloat64 (C throw-to-NaN)
- Re-apply compact-by-len / MakeUniqueString extras / global resize
  memcpy
- Rewrite GC or intern
- Sprinkle more @setRuntimeSafety(false); valueToPtr is the one
  exception
- Re-run saturated C traces / leftover-ident / struct-layout /
  DUMP_* / post-25 runtime probing
- Zero-fill padding to make Safe byte-identical to Fast
- Wrap setjmp in a Zig function
- Touch src/wasm_host.zig unless the user says so
- Edit engine code on a static mismatch whose C-vs-Zig probe matches

## After each REAL (probed) fix
1. zig build -Doptimize=ReleaseFast && ./tests/difftest/run.sh && ./tests/difftest/bytecode.sh && ./tests/zigonly/run.sh && ./tests/oracle/run.sh
2. zig build -Doptimize=ReleaseSafe && ./tests/difftest/run-safe.sh
3. If parse/JSON/longjmp or bytecode emit: LIMITS=16M Debug run.sh
   (include 14_hostile_args.js) && bytecode.sh
4. Update debug-notes.md (audit log + this prompt if the phase
   changes)
5. Ask user to batch Octane after substantive engine fixes — do not
   run Debug Octane unless asked

## Git state
Fixes 1–21, ReleaseSafe, and Debug setjmp are committed (b66e1d8,
7f62eac). zigonly, oracle, and fixes 22–26, 28 are in the working
tree. False 29 reverted. Do not commit/push unless asked.
```

