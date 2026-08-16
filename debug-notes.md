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

---

## Octane status — RESOLVED (2026-08-15 evening)

**All Octane suites pass.** User ran `zig build octane -Doptimize=ReleaseFast`
**9 times in a row** with no crashes or suite errors (including Typescript
`parseErrors.length` 192/193 and DeltaBlue `addConstraint`).

C reference score ~2485. Zig scores ~2300–2370 vary with Octane’s
`Date.now()` time budget (different iteration counts). That is normal; the
engine bug class is fixed.

Octane remains the **regression gate** after future fixes. Do not use full
Octane for discovery iteration (slow); use targeted repros below, then ask
the user to batch-verify Octane.

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

#### 1A. Complete the `JS_POP_VALUE` audit

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

#### 1B. Raw-pointer-across-alloc audit

Grep locals holding `source_buf`, raw `p` into source, or `*Ext` from
`valueToPtr` across `js_malloc`. C saves **offsets** (`pos`, `buf_pos`) and
refreshes `JSParseState.source_buf` from `source_str` after GC. Parser and
lexer are main targets.

#### 1C. Intern / property-key audit

Any path that stores a string/`JSValue` as property key, label, or table
slot after a GC-capable call without `popValue` reload. Check comparison
sites (`pr.key == prop`, label break/continue).

#### 1D. Layout / type overlay audit

Compare struct sizes and field order for GC-marked types vs C:
- `JSFunctionBytecodeExt` (extra `flags` in `utils_types` — parser/GC use
  `runtime_types`)
- `JSObjectExt` / regexp overlay on `&p.u`

### Phase 2 — Targeted runtime tests

Use `/tmp/gc_stress_*.js` (delete when done). Low memory forces GC:

```sh
./zig-out/bin/mqjs --memory-limit 8M /tmp/gc_stress_foo.js
```

Scripts to write and run **10× back-to-back**:
1. Labeled `break`/`continue` (label intern identity)
2. 10k+ unique property names, then read back
3. `Function.prototype.bind` chains under stack pressure
4. Large nested `eval` / function declarations (parser finalize)
5. RegExp with many captures (string builtin GC roots)
6. Math edge cases (`Math.pow`, `floor` near zero) vs Node or C mqjs

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
index conversion. `slow/17_regexp_deep.js` (11850 regexp cases, ~2 min/run)
is kept out of the default run.

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

### Execution order

1. Phase 1A checklist → fix must-fix sites one at a time
2. Phase 2 scripts for each fix
3. User batch Octane (9+ runs) as regression
4. Phases 1B–1D, 3, 4 in parallel as 1A narrows

### Success criteria

| Milestone | Gate |
|-----------|------|
| 1A complete | Every `_ = popValue` has C-verified verdict |
| GC-stress | 10/10 runs match oracle on all scripts |
| C differential | Zero diffs on property/intern/bind/eval scripts |
| Octane regression | 9+ consecutive full runs (current bar) |

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

## Handoff prompt (paste to a new agent)

See bottom of file after edits — **Post-Octane audit** prompt.

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

## Handoff prompt — Post-Octane audit (paste to new agent)

```
Read debug-notes.md and .cursor/rules/debug-notes.mdc first.

Octane is RESOLVED (user: 9/9 full runs, no errors). Your job is the
post-Octane audit in debug-notes.md — find silent bugs (stale JSValue after
GC, intern identity, raw pointers across alloc), not Octane suite ports.

Compare only against ../mquickjs (mquickjs.c). Zig 0.15.2 at
/home/vexcess/zig-x86_64-linux-0.15.2/zig. Build -Doptimize=ReleaseFast only.
Fix one correctness bug per turn, then stop. Do not rewrite the GC. Do not
commit unless asked.

Start Phase 1A: grep `_ = utils.popValue` in src/, compare each suspicious
site to C JS_POP_VALUE. Prioritize builtins_string, regexp, parser. Fill the
checklist table in debug-notes.md. Fix the first C-verified must-fix site;
build ReleaseFast; add or run a small /tmp gc_stress repro; ask user to
batch Octane (9 runs) before the next fix.

Do NOT revert fixes 1–9. Do NOT re-apply compact-by-len, MakeUniqueString
post-resize extras, or global js_resize_value_array2 memcpy change. Do NOT
"fix" newShortInt without C proof.

Do not use `mqjs tests/octane/run.js <suite>` (host argv SEGV). Use
/tmp/gc_stress_*.js with --memory-limit 8M for discovery.
```
