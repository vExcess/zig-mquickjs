# zig-mquickjs debugging notes

Read this before diagnosing GC / parse / math / correctness issues. Compare
Zig against `/home/vexcess/Sync/Workspace/mquickjs/mquickjs.c` (and
`libm.c` / `libm_lib.zig`). Only `zig-mquickjs` and `mquickjs` matter. Do
not search other workspace trees.

Build with `-Doptimize=ReleaseFast` and Zig 0.15.2
(`/home/vexcess/zig-x86_64-linux-0.15.2/zig`). Debug/ReleaseSafe cannot run
this engine (tagged pointers).

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig
$ZIG build -Doptimize=ReleaseFast
./zig-out/bin/mqjs --memory-limit 256M path/to/repro.js
```

Fix **one** correctness bug per turn, then stop for manual verify. Leave
performance for last. Do not rewrite subsystems. Keep the fixes listed below;
they are real.

**Discovery order (2026-08-15):** run `./tests/difftest/run.sh` first. Static
Phase 1A–1D is largely complete; the trig bug (fix 13) was found only by
differential testing after three static passes found nothing new.

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

**Post fix 14 (2026-08-15): gate not yet confirmed.** Fix 14 (JSON `js_atod`
scratch buffer) has not been through a 9-run Octane batch. No engine code was
changed after it — the following turn was discovery only (difftest 19/20 and
the `js_alloc_byte_array` sweep, both clean) — so the batch still applies to
the current tree. Confirm it before landing the next fix.

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

Bytecode (`-o` / `-b`) was checked separately: C and Zig images are
cross-loadable and execute identically in all four combinations. The byte
differences are struct/heap padding (stale bytes in **both** engines), not
a port bug.

### Phase 4 — Hardening

- Document: after `pushValue` + GC-capable call, always `local = popValue`.
- Update this file as audits complete.
- Host fix when useful: `mqjs` argv SEGV for `run.js <suite>` (Zig slice
  as `char**`).

### Execution order (current)

1. `./tests/difftest/run.sh` — any diff is a bug; extend suite for new areas
2. Fix one C-verified bug; add a difftest script if the repro is new
3. Re-run `./tests/difftest/run.sh` + project tests (`tests/test_*.js`)
4. User batch Octane (9+ runs) after substantive fixes
5. Remaining static sweeps: `libm_lib.zig` signedness is **done** (clean);
   Phase 1C watchlist is **done** (covered by difftest 19, clean)
6. `js_alloc_byte_array` scratch-buffer sweep — **done, clean** (see below)

### Success criteria

| Milestone | Gate | Status |
|-----------|------|--------|
| 1A complete | Every `_ = popValue` has C-verified verdict | **done** |
| 1B–1D static | No new must-fix vs C in parser/GC/layout | **done** |
| C differential | `./tests/difftest/run.sh` → ALL MATCH | **done** |
| Octane regression | 9+ consecutive full runs | **done** (re-run after next fix) |

### Do not do yet

- Rewrite GC or intern algorithm
- Change `js_resize_value_array2` memcpy for all arrays
- Re-apply compact-by-`unique_strings_len` or MakeUniqueString extras
- “Fix” `newShortInt` without C proof
- Chase Octane score deltas (timing noise)

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

---

## Historical: Typescript `Parse errors.` (Octane — fixed)

Was intermittent `parseErrors.length` not 192/193 when intern/property keys
were wrong. Resolved with fixes 7–9 and `js_create_property` popValue.

For isolated repro without full Octane: heap pressure from earlier suites;
do not use `mqjs tests/octane/run.js <suite>` (host argv SEGV). Wrappers:
avoid globals `files` / `i`; use `octane_file_list`. Pipe with `stdbuf -oL`.

gdb on silent SEGV: `mov -0x1(%reg)` is `valueToPtr`. `rax=0x7` is `JS_NULL`.

---

## Do not use `mqjs tests/octane/run.js <suite>`

Host bug: `script_argv.ptr` as C `char **` with Zig slices. Second arg
SEGVs. Full Octane via `zig build octane` is fine.

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
the only globals with no difftest coverage are `console`, `load`, and
`Math.random`, all of which are host-side and non-deterministic.

### libm signed/unsigned drift — swept, no behavioural divergence

Priority 1 from the previous handoff is **done**. Every remaining unsigned
`getHighWord` site was compared to `libm.c`: `js_scalbn`, `kernelSin`,
`kernelCos`, `jsRemPio2Impl`, `js_atan2`'s sign flip, `kernelExp`, `js_exp`
and `kernelLog2` all mask or `@bitCast` exactly where C does. ~2700 lines of
adversarial values (subnormals, every power of two both signs, `pow`/`atan2`/
`%` cross products, NaN/Inf) are byte-identical to C.

Two **latent** (non-diverging) spots in `kernelExp`, left alone deliberately:
`@intCast(getHighWord(zz))` and `@as(u32, @intCast(n << 20))` are illegal for
a negative high word / negative `n`, where C relies on well-defined unsigned
wraparound. `zz` is always positive there and LLVM currently emits the
wrapping add, so output matches; revisit only with a C-verified repro.

**Git state:** fixes 1–14 are committed (`8cfc492 json patches` carries fix
14 and `18_gc_explicit.js`; `391c2e1 math patches` carries fix 13). Only
`debug-notes.md`, `tests/difftest/README.md`, `tests/difftest/19_gc_hooks.js`
and `tests/difftest/20_mutate_reentrant.js` are uncommitted. Do not commit
unless asked.

---

## Handoff prompt (paste to a new agent)

See bottom of file — **Post-Octane audit (continued)** prompt.

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
Octane was RESOLVED (9/9) before fix 14. Compare only against ../mquickjs
(mquickjs.c + libm.c). Do not search other workspace dirs. Build
-Doptimize=ReleaseFast with Zig 0.15.2 at
/home/vexcess/zig-x86_64-linux-0.15.2/zig. Fix one C-verified bug per turn,
then stop. Do not rewrite the GC. Do not commit unless asked.

## What's done (do not redo)

- Phase 1A: all `_ = utils.popValue` sites checklist-complete (fixes 10-11)
- Phase 1B-1D static: no new must-fix in parser/lexer/GC layouts (fix 12)
- Phase 1C watchlist: closed by difftest 19 (defineProperty getters/setters,
  hasOwnProperty, JSON stringify keys, all under explicit gc()) - clean
- Fixes 1-14 documented in debug-notes.md - do NOT revert
- libm signed/unsigned sweep: done, no behavioural divergence vs C
- `js_alloc_byte_array` sweep (the fix-14 follow-up): done, clean. Every call
  site matches C in *both* allocation size and in passing
  `vt.byteArrayBuf(arr)` rather than the header. `js_resize_byte_array` and
  `re_parse_quantifier`'s pointer refreshes match C line by line. Do not redo
  this sweep; the notes list every site checked.
- Differential harness: tests/difftest/ (19 scripts + run.sh + README)
  -> ALL MATCH vs ../mquickjs/mqjs at 256M/16M/4M/2M, and both engines OOM at
  byte-identical points at 1M/1200K/800K. tests/test_*.js also match.

## Octane gate status

Fix 14 landed but the user has **not** confirmed the post-fix Octane batch.
No engine code changed after fix 14 (the last turn was discovery only), so a
batch now still covers the current tree. If the user says Octane is clean,
note it in debug-notes.md and proceed. Otherwise wait for 9+ consecutive
`zig build octane -Doptimize=ReleaseFast` runs before landing the next fix.

## Discovery method (use this first)

./tests/difftest/run.sh

Any stdout/exit-code divergence vs C is a port bug. Read
tests/difftest/README.md for rules:
- strip ANSI colour in diffs (run.sh does this)
- every script must end with print("DONE <filename>")
- respect README "Deviations from mquickjs": direct eval = global scope,
  let/const alias var - NOT bugs
- use `(1, eval)(...)` not bare `eval(...)` in new scripts
- catch bindings cannot be reused within a scope; name them e1, e2, ...

SLOW=1 ./tests/difftest/run.sh  # adds slow/17_regexp_deep.js (~2 min)
LIMITS="1M 800K" ./tests/difftest/run.sh  # OOM-boundary comparison

**Call `gc()` explicitly in new probes.** A tight `--memory-limit` only
collects when the allocator runs out; `gc()` forces compaction between
"take pointer" and "use pointer". That is how fix 14 was found. Keep `gc()`
calls cheap - one inside a 3000-element sort comparator cost ~100 s.

## Highest-priority next work

Discovery is hitting diminishing returns at the script level: two full turns
of new differential coverage (19, 20) found nothing. Prefer these next:

1. Areas difftest still cannot reach from script level:
   - the host: `load()`, `console`, bytecode `-o`/`-b` with hand-corrupted or
     truncated images (C and Zig images already round-trip identically)
   - `mqjs` argv handling (known SEGV in `run.js <suite>`, Phase 4 item)
2. Run real-world code differentially instead of synthetic probes: drive the
   Octane suite sources under both engines with a deterministic wrapper
   (fixed iteration counts, no Date.now) and diff the printed results.
3. Static: the remaining `_ = utils.popValue` sites outside the hot files in
   the Phase 1A table (the table covers string/regexp/parser/value/array/std).
4. Latent libm only (no repro yet - do not "fix" without C proof):
   `kernelExp` `@intCast(getHighWord(zz))` and `@as(u32, @intCast(n << 20))`
   for negative high word / negative n. Currently matches C output.

## Already probed clean (do not redo)

- Adversarial libm sweep (~2700 lines, pow/atan2/%/subnormals)
- Integer conversion / typed-array stores / shift counts
- Number<->string (toString radix, toFixed, parseInt/parseFloat)
- Builtin surface enumeration (identical on both engines; the only globals
  with no coverage are console/load/Math.random, all host-side)
- 12k property tables, delete/re-add, for-in with mid-enumeration gc()
- Accessor properties whose getter/setter calls gc()
- Callbacks that mutate the array/object a builtin is walking
- setPrototypeOf chains and swaps under gc(), array index/length edges,
  arguments aliasing, stack-overflow recovery, surrogate/NUL strings

## Do NOT do

- Revert fixes 1-14
- Re-apply compact-by-len, MakeUniqueString post-resize extras, or global
  js_resize_value_array2 memcpy change
- "Fix" newShortInt or kernelExp latent spots without C proof
- Rewrite GC or intern algorithm
- Report direct eval / let-as-var as bugs (documented deviations)
- Use mqjs tests/octane/run.js <suite> (host argv SEGV); full Octane via
  zig build octane is fine
- Temporarily reintroduce a known bug to "prove" a test catches it

## After each fix

1. zig build -Doptimize=ReleaseFast
2. ./tests/difftest/run.sh
3. Add or extend a difftest script for the repro
4. Update debug-notes.md (fix N + session log)
5. Ask user to batch Octane (9 runs) before the next fix

## Git state (do not commit unless asked)

Fixes 1-14 are committed (8cfc492 "json patches" = fix 14). Uncommitted:
debug-notes.md, tests/difftest/README.md, tests/difftest/19_gc_hooks.js,
tests/difftest/20_mutate_reentrant.js.
```
