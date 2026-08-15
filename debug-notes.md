# zig-mquickjs debugging notes

Read this before chasing Octane / GC / parse crashes. Compare Zig against
`/home/vexcess/Sync/Workspace/mquickjs/mquickjs.c` (and `libm.c` / `libm_lib.zig`).
Only `zig-mquickjs` and `mquickjs` matter. Do not search other workspace trees.

Build with `-Doptimize=ReleaseFast` and Zig 0.15.2
(`/home/vexcess/zig-x86_64-linux-0.15.2/zig`). Debug/ReleaseSafe cannot run
this engine (tagged pointers). **Do not iterate with full `zig build octane`**
— it is slow. Reproduce with a heaped wrapper, then ask the user to verify
full Octane.

```sh
export ZIG=/home/vexcess/zig-x86_64-linux-0.15.2/zig
$ZIG build -Doptimize=ReleaseFast
./zig-out/bin/mqjs --memory-limit 256M path/to/repro.js
```

Fix **one** correctness bug, then stop for a manual verify. Leave performance
for last. Do not rewrite subsystems. Keep the fixes listed below; they are
real.

---

## Octane status (2026-08-15 afternoon) — HANDOFF

C reference ~2485. Zig has **finished** full Octane (score ~2242–2377) on
some process runs. Other runs of the **same binary** fail in different
places. Each `zig build octane` is a **new process** (not leftover heap
from the previous invocation). Non-determinism is ASLR + Octane’s
`Date.now()` time budget (different iteration counts → different GC
timing). `random_state` starts at 1.

These are **not** suite-logic ports. Same class: interned-string identity
and/or stale pointers after GC. Property lookup is **pointer equality** on
unique strings. Two unique `"addConstraint"` objects → method miss.
Wrong intern in the TS compiler → `parseErrors.length` not 192/193.

### User verify after label_name popValue (2026-08-15)

Typescript still `Parse errors.` after the break-entry assign-back.

Static audit vs C `JS_POP_VALUE` (same class as fix 8). Three sites
where Zig discarded the relocated pointer and then stored/called it:

1. `js_create_property` — after alloc/resize GC, `pr.key = prop` and
   `hash_prop(prop)` used the **pre-GC** key. Lookup is pointer
   equality. This is the intern-identity miss (TS parse count).
2. `JS_ToPrimitive` — after `JS_StackCheck`, `method` was discarded
   then `JS_PushArg(method)`.
3. `js_function_bound` — after `JS_StackCheck`, `params` was discarded
   then `valueArr(params)`.

Do not “fix” `newShortInt` (`val << 1` as i32 is in range for
`JS_SHORTINT_MIN/MAX`). Do not re-add MakeUniqueString extras.

`this.v1` is undefined **or** `v1` exists but has no `addConstraint`
(prototype lookup used a different interned key than the one stored on
`Variable.prototype`). Log which before assuming.

| Suite | Notes |
|-------|--------|
| Richards | Usually prints a score |
| DeltaBlue | Intermittent `addConstraint` of undefined |
| Crypto / RayTrace | Fixed (libm UB); still print scores |
| CodeLoad | Was SEGV; `byte_code` re-bind + `JS_POP_VALUE` reload. Do not revert |
| Typescript | Intermittent `Parse errors.` (`parseErrors.length` not 192 or 193) |
| Splay score | ~1600 vs ~2200+ ⇒ heap/intern corruption, not a Splay port |

---

## What the previous agent got wrong (do not repeat)

The GC **mark/compact loop matches C** closely (`src/mquickjs_gc_lib.zig`
vs `mquickjs.c` ~11837–12438). Do **not** rewrite the GC. Do **not**
change `js_resize_value_array2` copy length for all arrays.

Failed attempts this session:

1. **Generic resize “copy post-GC `valueArraySize`”** (`js_resize_value_array2`).
   If the source pointer was not a value array after GC, copy_n=0 and the
   new table was filled with `JS_UNDEFINED` → wipes **property arrays**
   (DeltaBlue). Reverted to C’s `memcpy(old_size)`. **Leave it reverted.**

2. **Unique-string compact `j==0`: keep a marked empty array** instead of
   C’s unmark + `unique_strings = JS_NULL`. Diverges from C; reverted.

3. **Compact scanned `unique_strings_len` instead of `arr->size`.**
   Reverted 2026-08-15: `gc_mark_all` again matches C
   `for (i = 0; i < arr->size; i++)`. If `len` was short, compact dropped
   live interned strings still used as property keys, then
   `JS_MakeUniqueString` inserted a second unique copy (DeltaBlue
   `addConstraint` + Typescript `parseErrors`). **Do not re-apply
   compact-by-len.**

4. Extra `find_atom` after resize + `[len, cap)` `JS_UNDEFINED` fill in
   `JS_MakeUniqueString`. Removed 2026-08-15 to match C. Keep the
   **numeric** re-lookup (fix 7). Do not re-add the resize re-lookup or
   the capacity fill.

Keep fixes 1–8 below. They were verified on earlier successful full runs.

---

## Current failure: Typescript `Parse errors.`

`tests/octane/typescript.js` `runTypescript()`:

```javascript
compiler.addUnit(compiler_input, "compiler_input.ts");
parseErrors = [];
compiler.reTypeCheck();
compiler.emit(...);
if (parseErrors.length != 192 && parseErrors.length != 193)
  throw new Error("Parse errors.");
```

`parseErrors` is filled by `compiler.setErrorCallback`. The compiler is the
bundled `typescript-compiler.js` (~1.2M) parsing `typescript-input.js`
(`compiler_input`, ~1.3M). Expected error count is **192 or 193**. Any other
count fails. A later check is `outfile` checksum (`Wrong checksum.`) — not
hit yet.

This is the TypeScript *compiler running as JS*, not Zig parsing TS. Wrong
`parseErrors.length` means the engine evaluated the compiler/input differently
(corrupted strings, wrong atoms, flaky `eval`/parse, broken property keys).

Same class as earlier CodeLoad flakes: works on a fresh-enough heap, fails
after more GC. Do not assume a deterministic TS parse bug.

### How to reproduce without full Octane

1. **Do not** use `mqjs tests/octane/run.js typescript` — extra script args
   crash the host argv path (see below).
2. Wrapper must not use globals named `files` or `i` (mandreel/box2d/compiler
   overwrite them). Use `octane_file_list` / `octane_fi`.
3. `run.js` defines `var read = function() {};` for zlib. Include that if you
   load zlib.
4. Isolated Typescript (only those three files) often **passes**. Need heap
   pressure: load all Octane sources, and/or actually run Box2D+zlib first,
   then Typescript. Two back-to-back full runs is how the user hit it.
5. Pipe through `stdbuf -oL` — mqjs stdout is fully buffered when not a TTY,
   so a crash can look like “no output”.
6. Delete `/tmp/run_*.js` repros when done. Do not leave `tests/repro_*.js`.

gdb on a silent SEGV: `mov -0x1(%reg)` is `valueToPtr`. `rax=0x7` is `JS_NULL`.

`DEBUG_GC` in `include/mquickjs_priv.h` (GC on every malloc) makes stale
pointers fail immediately. Slow.

---

## Do not use `mqjs tests/octane/run.js <suite>`

`std.process.argsAlloc` returns `[][:0]u8`. `evalFile` treats
`script_argv.ptr` as C `char **`. One script arg works (full Octane). A second
arg makes `argv[1]` the **length** of `run.js` (`0x13`) and `JS_NewString`
segfaults. Host bug, not the engine suite bug.

---

## Fixed already (do not revert; do not re-diagnose)

### 1. `Math.floor` / `ceil` / `trunc` / `round` no-op in ReleaseFast

`src/libm_lib.zig` `rintSf64`. Unbiased exp was `((u >> 52) & 0x7ff) -% 0x3ff`
then `@intCast` to `i32`. `|x| < 1` wraps; ReleaseFast deletes the `< 1`
branch. Crypto: `Math.floor(4/28)` stayed fractional.

Fix: `exp_field - 0x3ff` as signed `c_int`.

### 2–3. `Math.pow`

Same file, `js_pow`. (a) `iy | ly == 0` dropped C parens → always 1 for
integer `y`. (b) overflow test used `u32`; negative `z` (result < 1) looked
like overflow → Infinity. RayTrace checksum 2321.

### 4. `parseNumber` UAF

`src/mquickjs_lexer_lib.zig`. C saves `pos`, allocs `JSATODTempMem` (may GC),
then `p = source_buf + pos`. Zig kept the old `p`.

### 5. `check_free_mem` signed subtract

`src/mquickjs_utils_lib.zig`. C uses signed `ptrdiff_t`
`(stack_bottom - heap_free)`. Zig usize wrap skipped GC when `heap_free` was
already past `stack_bottom` (`js_parse_local_functions` raises `stack_bottom`).

### 6. `byte_code` not attached at finalize (CodeLoad / zlib SEGV)

`src/mquickjs_parser_lib.zig` `js_parse_local_functions`, `cpool_pos == 0`.

C sets `b->byte_code = s->byte_code` at the end of `js_parse_program` /
`js_parse_function`. Under GC that write is lost (stale `JSFunctionBytecode *`).
Then `convert_ext_vars_to_local_vars` does `byteArr(b.byte_code)` while it is
still `JS_NULL` (`0x7`) and patches “bytecode” at address 6 → heap corruption.
Closures (zlib/Emscripten) hit this; later crashes look random
(`mbGetMtag`, `next_token`).

Current code (keep this order):

```zig
s.cur_func = pf.*;
var b = funcBc(pf.*);
b.byte_code = s.byte_code;          // BEFORE convert
convert_ext_vars_to_local_vars(s);
b = funcBc(pf.*);                   // refresh after possible GC
js_shrink_byte_array(...);
```

Assigning only *after* convert is not enough.

### 7. Unique-string insert after `js_is_numeric_string` GC

`src/mquickjs_value_lib.zig` `JS_MakeUniqueString`.

`find_atom` records insertion index `a`, then `js_is_numeric_string` allocates a dtoa temp (may GC). The unique-string table is a **weak** ref, so compact can drop dead entries or set the table to `JS_NULL` and `unique_strings_len = 0`. C then `memmove`s `unique_strings_len - a` slots. If `a` is stale and `len` shrank, that subtract underflows and the move writes off the new array.

Zig hit this more often than C (full Octane heap + numeric-looking idents). Symptom: same binary, first run OK, second run Typescript `parseErrors.length` not 192/193; Splay score jumps.

Fix: skip `find_atom` when the table is `JS_NULL`; after `js_is_numeric_string`, look up again before resize/insert.

### 8. Discarded `JS_POP_VALUE` after parse/resize GC (CodeLoad SEGV)

C `JS_POP_VALUE(ctx, v)` **assigns** `v = v_ref.val` so the local is the
GC-relocated pointer. Zig often did `_ = utils.popValue(...)` and then used
the pre-GC tagged value.

`js_parse_local_functions`: after `js_parse_function` (allocates a lot),
pushed the stale `func` onto the parse stack. Later finalize /
`convert_ext_vars` / `valueToPtr` hits a dangling function object → SEGV
after Gameboy.

Same pattern stored stale pointers into cpool / vars / ext_vars after
`js_resize_value_array`: `cpool_add`, `add_var`, `add_func_ext_var`.

Fix: `func = utils.popValue(...)` (and the same for `val`/`name`) at those
sites. Other `_ = popValue` that do not use the local after a GC are fine.

### 9. Unique-string GC / intern identity — **unfinished, last change likely harmful**

Intern table `ctx->unique_strings` is a **weak** `JSValueArray`. Mark
starts at `current_exception`, **skipping** `unique_strings`. Compact
keeps only `gc_mb_is_marked` entries, may shrink, may set table to
`JS_NULL` and `unique_strings_len = 0`.

`JS_MakeUniqueString` (`src/mquickjs_value_lib.zig`): `find_atom` →
`js_is_numeric_string` (may GC) → re-lookup `a` (fix 7) →
`js_resize_value_array` (may GC) → `memmove` insert. C does **not**
re-lookup after numeric or resize. Keep the numeric re-lookup only.
Post-resize `find_atom` and `[len, cap)` `JS_UNDEFINED` fill were
removed (match C).

C compact (`mquickjs.c` ~12151): `for (i = 0; i < arr->size; i++)`.
Zig matches that again (reverted compact-by-`unique_strings_len`).
Do not re-scan only `len`.

C `js_resize_value_array2` `memcpy`s `old_size` after GC. If compact
already shrank the source, that read walks the FREE tail. Latent in C;
Zig hits it more (slower → more GC under Octane’s 256M limit). Do not
“fix” this by changing memcpy for every value array.

---

## Leads (next agent)

Priority: intern identity / stale unique-string table, not a new GC
algorithm. Compare Zig to C line-by-line at the **call sites** that
allocate.

- Compact-by-len **reverted**. MakeUniqueString extras **removed**.
  `label_name` / `js_create_property` `prop` / ToPrimitive `method` /
  `js_function_bound` `params` now assign `popValue` like C. User
  should run two back-to-back `zig build octane -Doptimize=ReleaseFast`.
- Remaining `_ = utils.popValue` where the local is used after a GC.
  Parser emit sites were fixed (`cpool_add`, `add_var`,
  `add_func_ext_var`). Grep others that store the value after pop.
- Locals holding `source_buf` / `p` / `JSFunctionBytecode *` across
  `js_malloc`. C saves offsets; GC only refreshes `JSParseState.source_buf`
  from `source_str`.
- `find_atom` on a non-string slot (garbage in intern table).
- `newShortInt`: Zig `@as(i64, val << 1)` may shift `i32` first.
- `utils_types.JSFunctionBytecodeExt` has an extra `flags` word.
  Parser/GC use `runtime_types` (correct). `JSObjectExt` union in
  `utils_types` has no `regexp`; GC uses `objectRegexp` overlay on `&p.u`.
- `DEBUG_GC` in `include/mquickjs_priv.h` (GC every malloc). Slow but
  makes stale pointers fail early.
- Do not log `parseErrors.length` by editing `tests/octane/typescript.js`
  unless you revert it. Prefer a `/tmp` wrapper.

---

## Handoff prompt (paste to a new agent)

```
Read debug-notes.md and .cursor/rules/debug-notes.mdc first.

You are taking over zig-mquickjs Octane GC/intern flakes. Compare only
against ../mquickjs (mquickjs.c). Zig 0.15.2 at
/home/vexcess/zig-x86_64-linux-0.15.2/zig. Build -Doptimize=ReleaseFast
only. Do not iterate with full `zig build octane`. Fix one correctness
bug, then stop. Do not rewrite the GC. Do not commit.

Typescript still Parse errors after label_name popValue.

This turn: C-verified JS_POP_VALUE assign-backs —
js_create_property prop (intern key after prop-table GC),
JS_ToPrimitive method, js_function_bound params.

Fixes 1–8 are real — do not revert. Do not re-apply compact-by-len.
Do not change js_resize_value_array2 memcpy size. Do not re-add
MakeUniqueString post-resize find_atom or [len, cap) UNDEFINED fill.
Keep the numeric re-lookup (fix 7). Do not “fix” newShortInt.

Do not use `mqjs tests/octane/run.js <suite>` (host argv SEGV).
```

---

## Other pitfalls

- Tagged JSValues: `value = ptr + 1`. Use `vt.valueGetInt` for short ints.
- Unique-string insert: `copyBackwards` (C `memmove`).
- Catch bindings cannot be reused (`catch variable already exists`).
- `load()` exists. `scriptArgs[0]` is the script path.
- `OP.COUNT=126`. Labels: `LABEL_RESOLVED_FLAG = 1<<29`,
  `LABEL_OFFSET_MASK = (1<<29)-1`. Unresolved goto as PC ≈ 536870911+n.
- `run.js` `files` loop uses `idx` (safe). Wrappers using `i` stop after
  box2d because minified code clobbers `i`.
