# Independent oracles (no C reference)

Zig-only correctness tests that do **not** compare against C mquickjs.
Each `.js` has a `.expected` stdout file and ends with `DONE <filename>`.
Scripts self-check: they print `FAIL` on a broken invariant.

```sh
zig build -Doptimize=ReleaseFast
./tests/oracle/run.sh
```

`run.sh` also compiles each script with `-o` and runs the image with `-b`.

## Not bugs (do not "fix")

From README "Deviations from mquickjs" and the stricter-mode subset:

- Direct `eval` always runs in global scope
- `let` / `const` alias `var` (no TDZ, no block scope, `const` is assignable)
- Array holes, writing past array end, `[1,,3]`
- Unsupported ES6+: Promises, classes, modules, `**=`, `Object.freeze`, …
- `-o` padding-byte diffs when **sizes** match (ReleaseSafe/Debug)

Crashes, ReleaseSafe panics, non-deterministic stdout, and failed self-checks
on supported stricter-mode JS **are** bugs.

| File | Area |
|------|------|
| `01_json_roundtrip` | JSON.parse(JSON.stringify) + `gc()`; `JSON.parse("-0")` sign |
| `02_default_gc` | default args + `gc()`, closures, `Function()`, side effects |
| `03_defineprop_gc` | defineProperty / hasOwnProperty / `in` with `gc()` |
| `04_math_identities` | sin²+cos², sign of `sin(-0)`, `acos(-1)` |
| `05_eval_defaults` | global eval defining default-arg functions |
| `06_default_regexp` | fix 22: default/body starting with `/` re-lexed as division |
| `07_default_scope` | fix 23–24: `arguments` / inner name bound before defaults; name seen only in the default |

Env overrides: `Z_MQJS`, `LIMITS` (default `16M`).
