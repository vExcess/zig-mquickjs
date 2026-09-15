# Zig-only tests

C mquickjs cannot parse these scripts, so `tests/difftest/` never covers
them. Each `.js` has a `.expected` stdout file. Any mismatch is a Zig
regression (or a change to a documented deviation — update the expected
file only then).

```sh
zig build -Doptimize=ReleaseFast
./tests/zigonly/run.sh
```

`run.sh` also compiles each script with `-o` and runs the image with `-b`.
Default-arg initializers are emitted into bytecode; a source-only pass
would miss that.

| File | Area |
|------|------|
| `01_default_args` | fix 21: `js_skip_assign_expr` (`f(a=1,b=2)`, nested `,`, `f(undefined)`) |
| `02_let_const` | documented deviation: `let`/`const` alias `var` |
| `03_eval_global` | documented deviation: direct `eval` runs in global scope |

Do not change `js_skip_expr` to stop at `,` (breaks `for (;; i++, j++)`).
Do not "fix" let/const or global eval to match C.

Env overrides: `Z_MQJS`, `LIMITS` (default `16M`).
