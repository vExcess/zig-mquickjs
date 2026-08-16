# Differential tests vs C mquickjs

Runs each script on **both** engines and diffs stdout + exit code. Any
divergence is a port bug, because `../mquickjs` is the reference.

```sh
zig build -Doptimize=ReleaseFast
./tests/difftest/run.sh              # -> "ALL MATCH"
SLOW=1 ./tests/difftest/run.sh       # also run slow/ (~2 min per engine/limit)
```

Each script is run at several `--memory-limit` values (default
`256M 16M 4M 2M`) because a tighter heap changes the GC schedule and
exposes stale-pointer bugs that pass at 256M.

## Why this exists

Three static-audit passes over the `JS_POP_VALUE` / pointer-lifetime bug
classes found nothing new. The first differential run immediately caught
`Math.sin`/`cos`/`tan` returning `0` for every negative argument
(`debug-notes.md` fix 13). Prefer this over more static reading.

## Two rules that make results trustworthy

1. **ANSI colour is stripped.** C `mqjs` colourises errors; the Zig host
   does not. Left in, that cosmetic difference masks every real diff.
2. **Every script ends with `print("DONE <filename>")`.** A script that
   dies early produces "matching" output on both engines and silently
   tests nothing. `run.sh` reports truncation separately from diffs.
   Keep the sentinel when adding tests.

## Coverage

| File | Area |
|------|------|
| `01_labels` | labelled break/continue, label intern identity |
| `02_props` | 4k unique keys, delete/re-add, prototype chains, getters |
| `03_bind` | bind chains, apply/call, closures, `arguments` |
| `04_parser` | nested indirect eval, hoisting, try/catch/finally, switch |
| `05_regexp` | captures, replace callbacks, `$` patterns, split, lastIndex |
| `06_math` | rounding, pow, formatting, FP/int edge cases |
| `07_strings` | slicing, concat under GC, coercion |
| `08_arrays_json` | array builtins, sort, growth, JSON round trips |
| `09_objects` | typeof/equality, ToPrimitive, instanceof, errors |
| `10_stack_recursion` | deep recursion, stack growth, many-arg calls, overflow |
| `11_closures_gc` | varref detachment, cycles, dynamic keys |
| `12_typedarrays` | all typed array types, clamping, shared buffers |
| `13_es6_extras` | for-of, imul/clz32/fround/log2, `**`, regexp flags, globalThis |
| `14_hostile_args` | every builtin x hostile arguments (type confusion, boundaries) |
| `15_numeric_sweep` | exhaustive Math + number formatting/parsing |
| `16_unicode_strings` | UTF-8 storage vs UTF-16 indexing, position cache |
| `slow/17_regexp_deep` | 11850 pattern x subject x flag combinations |

## Intended deviations — not bugs

From the README's "Deviations from mquickjs": direct `eval` runs in global
scope, and `let`/`const` alias `var`. Avoid both here.

Unsupported by **both** engines (don't write tests using them): array
elisions (`[1, , 3]`), writing past the end of an array, `**=`,
`Object.freeze`, `Object.getOwnPropertyDescriptor`, reusing a `catch`
binding name.

## Adding a test

Keep it deterministic — no `Date.now()`, no `Math.random()`. Allocate
garbage inside loops so the GC runs at tight memory limits. End with the
`DONE` sentinel.
