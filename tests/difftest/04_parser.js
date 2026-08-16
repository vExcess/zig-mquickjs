// Nested eval / function declarations (parser finalize, bytecode attach).
// Indirect eval only: direct eval is a documented zig-mquickjs deviation.
var geval = (1, eval);
var results = [];
for (var i = 0; i < 120; i++) {
    var src = "(function outer" + i + "(){" +
        "  function inner1(a){ return a * 2; }" +
        "  function inner2(a){ return inner1(a) + " + i + "; }" +
        "  var arr = [];" +
        "  for (var k = 0; k < 5; k++) arr.push(inner2(k));" +
        "  return arr.join('-');" +
        "})()";
    results.push(geval(src));
}
print("eval0=" + results[0]);
print("eval119=" + results[119]);

// eval defining globals
var acc = 0;
for (var i = 0; i < 100; i++) {
    acc += geval("var tmp" + i + " = " + i + "; tmp" + i + " * 2");
}
print("evalAcc=" + acc);

// deeply nested function declarations
function d1() {
    function d2() {
        function d3() {
            function d4() {
                function d5() { return 5; }
                return d5() + 4;
            }
            return d4() + 3;
        }
        return d3() + 2;
    }
    return d2() + 1;
}
print("deep=" + d1());

// hoisting
function hoisted() {
    var r = typeof later;
    function later() {}
    return r;
}
print("hoist=" + hoisted());

// closures capturing loop vars
var fns = [];
for (var i = 0; i < 50; i++) {
    (function (n) { fns.push(function () { return n * n; }); })(i);
}
var fsum = 0;
for (var i = 0; i < 50; i++) fsum += fns[i]();
print("fsum=" + fsum);

// try/catch/finally and throw
function tcf(n) {
    var log = [];
    try {
        log.push("t");
        if (n % 3 === 0) throw new Error("e" + n);
        log.push("no-throw");
    } catch (e) {
        log.push("c:" + e.message);
    } finally {
        log.push("f");
    }
    return log.join(",");
}
var tout = [];
for (var i = 0; i < 9; i++) tout.push(tcf(i));
print("tcf=" + tout.join(";"));

// switch with many cases
function sw(n) {
    switch (n % 7) {
        case 0: return "zero";
        case 1: return "one";
        case 2: return "two";
        case 3: return "three";
        case 4: return "four";
        case 5: return "five";
        default: return "six";
    }
}
var sacc = [];
for (var i = 0; i < 14; i++) sacc.push(sw(i));
print("switch=" + sacc.join(","));

print("DONE 04_parser.js");
