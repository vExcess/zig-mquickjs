// Default-arg evaluation (Zig-only) with gc() between allocate and use.
// C cannot parse `=`; this path was never C-diffed.

function fail(msg) { print("FAIL " + msg); }

function fobj(a = (gc(), { x: 1, y: "ok" })) {
    gc();
    return a.x + a.y;
}
if (fobj() !== "1ok") fail("fobj()=" + fobj());
else print("ok fobj");

function fstr(a = "hello") {
    gc();
    return a + "!";
}
if (fstr() !== "hello!") fail("fstr");
else print("ok fstr");

function make(x) {
    return function (a = x) {
        gc();
        return a.n;
    };
}
var inner = make({ n: 42 });
if (inner() !== 42) fail("closure default=" + inner());
else print("ok closure");

var fexpr = function (a = 7, b = a + 1) {
    gc();
    return a + "," + b;
};
if (fexpr() !== "7,8") fail("fexpr=" + fexpr());
else print("ok fexpr");

var o = {
    m: function (a = 3) {
        gc();
        return a * 2;
    }
};
if (o.m() !== 6) fail("method=" + o.m());
else print("ok method");

function nested(a = function (b = 9) { gc(); return b; }) {
    gc();
    return a();
}
if (nested() !== 9) fail("nested=" + nested());
else print("ok nested");

function ctor(a = 1, b = a + 1) { return a + b; }
var F = Function("a = 1", "b = a + 1", "gc(); return a + ',' + b");
if (F() !== "1,2") fail("Function()=" + F());
else print("ok Function");

function side() {
    var n = 0;
    function g(a = (n++, 5)) { return a; }
    var r1 = g();
    var r2 = g(9);
    var r3 = g();
    return n + ":" + r1 + "," + r2 + "," + r3;
}
if (side() !== "2:5,9,5") fail("side=" + side());
else print("ok side");

print("DONE 02_default_gc.js");
