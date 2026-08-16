// Deep recursion + many-arg calls: JS_StackCheck grows the stack (allocates -> GC).
// This is exactly the pattern that hid the js_string_concat_subst stale-value bug.
function p(label, v) { print(label + "=" + v); }

function deep(n) {
    if (n <= 0) return 0;
    var pad = "d" + n;
    return deep(n - 1) + (pad.length > 0 ? 1 : 0);
}
p("deep200", deep(200));
p("deep1000", deep(1000));

// recursion that allocates at every level
function deepAlloc(n) {
    if (n <= 0) return [];
    var arr = deepAlloc(n - 1);
    arr.push("lvl" + n);
    return arr;
}
var da = deepAlloc(300);
p("deepAllocLen", da.length);
p("deepAllocLast", da[da.length - 1]);
p("deepAllocFirst", da[0]);

// mutual recursion
function isEven(n) { return n === 0 ? true : isOdd(n - 1); }
function isOdd(n) { return n === 0 ? false : isEven(n - 1); }
p("even500", isEven(500));
p("odd501", isOdd(501));

// many-argument calls (stack check with large argc)
function manyArgs() {
    var s = 0;
    for (var i = 0; i < arguments.length; i++) s += arguments[i];
    return s;
}
var callAcc = 0;
for (var i = 0; i < 200; i++) {
    var args = [];
    for (var j = 0; j < 40; j++) args.push(j + i);
    callAcc += manyArgs.apply(null, args);
}
p("manyArgs", callAcc);

// stack overflow must be caught identically
function infinite(n) { return infinite(n + 1) + 1; }
try {
    infinite(0);
    p("overflow", "no-throw");
} catch (e) {
    p("overflow", e instanceof RangeError ? "RangeError" : String(e).slice(0, 40));
}

// recursion returning through finally
function finRec(n) {
    try {
        if (n <= 0) return "base";
        return finRec(n - 1) + "";
    } finally {
        var junk = "f" + n;
    }
}
p("finRec", finRec(150));

// exception thrown deep, caught shallow, across allocating frames
function throwDeep(n) {
    var junk = [];
    for (var i = 0; i < 10; i++) junk.push("t" + n + i);
    if (n <= 0) throw new Error("deep-bottom");
    return throwDeep(n - 1);
}
try { throwDeep(120); } catch (e5) { p("throwDeep", e5.message); }

// callbacks nested in builtins (map inside map inside sort comparator)
var nested = [];
for (var i = 0; i < 60; i++) nested.push(i);
var res = nested.map(function (v) {
    return nested.filter(function (w) { return w % (v + 1) === 0; }).length;
});
p("nestedCb", res.join(","));

var sorted = nested.slice().sort(function (a, b) {
    var t = [a, b].map(function (x) { return x % 7; });
    return t[0] - t[1] || a - b;
});
p("nestedSort", sorted.join(","));

print("DONE 10_stack_recursion.js");
