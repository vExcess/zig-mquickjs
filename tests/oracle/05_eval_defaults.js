// Documented: direct eval is global. Combine with Zig-only default args.

function fail(msg) { print("FAIL " + msg); }

eval("function from_eval(a = 4) { return a * 2; }");
if (from_eval() !== 8) fail("from_eval=" + from_eval());
else print("ok from_eval");

var g = 1;
function wrap() {
    var g = 2;
    return eval("function inner(a = g) { return a; } inner()");
}
if (wrap() !== 1) fail("eval default saw local? " + wrap());
else print("ok eval-global default");

var F = Function("a = 10", "return a");
if (F() !== 10 || F(3) !== 3) fail("Function single");
else print("ok Function single");

var G = Function("a = [1, 2]", "b = {x: 3}", "return a[1] + b.x");
if (G() !== 5) fail("Function nest=" + G());
else print("ok Function nest");

print("DONE 05_eval_defaults.js");
