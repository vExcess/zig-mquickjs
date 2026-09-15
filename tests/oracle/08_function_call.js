// Function.prototype.call() with no thisArg must not throw. Combined with
// Zig-only default args: defaults still run when this is supplied via call.

function fail(msg) { print("FAIL " + msg); }

function id() { return typeof this; }
if (id.call() !== "undefined") fail("call0=" + id.call());
else print("ok call0");
if (id.call(undefined) !== "undefined") fail("callU");
else print("ok callU");
if (id.call(null) !== "object") fail("callN=" + id.call(null));
else print("ok callN");
if (id.call({ x: 1 }) !== "object") fail("callObj");
else print("ok callObj");

function g(a = 7) {
    gc();
    return a + ":" + typeof this;
}
if (g.call() !== "7:undefined") fail("g.call=" + g.call());
else print("ok default call0");
if (g.call({ x: 1 }) !== "7:object") fail("g.call obj=" + g.call({ x: 1 }));
else print("ok default this");
if (g.call(undefined, 9) !== "9:undefined") fail("g.call arg=" + g.call(undefined, 9));
else print("ok default override");

print("DONE 08_function_call.js");
