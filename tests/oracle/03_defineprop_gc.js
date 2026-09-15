// Object.defineProperty / hasOwnProperty with gc() while keys intern.
// Phase 1C watchlist: ToPropertyKey locals across alloc.

function fail(msg) { print("FAIL " + msg); }

var o = {};
var i;
for (i = 0; i < 200; i++) {
    Object.defineProperty(o, "k" + i, {
        value: i,
        enumerable: true,
        writable: true,
        configurable: true
    });
    if ((i % 40) === 0) gc();
}
gc();
var bad = 0;
for (i = 0; i < 200; i++) {
    if (!o.hasOwnProperty("k" + i) || o["k" + i] !== i) bad++;
}
if (bad) fail("define " + bad);
else print("ok define " + Object.keys(o).length);

var acc = {};
Object.defineProperty(acc, "hot", {
    get: function () { gc(); return "H"; },
    enumerable: true
});
gc();
if (acc.hot !== "H") fail("getter=" + acc.hot);
else print("ok getter");

var key = { toString: function () { gc(); return "dyn"; } };
var d = {};
d[key] = 7;
gc();
if (d.dyn !== 7) fail("dynkey=" + d.dyn);
else print("ok dynkey");

var proto = { p: 1 };
var child = {};
Object.setPrototypeOf(child, proto);
gc();
if (!("p" in child) || child.p !== 1) fail("in proto");
else print("ok in");

print("DONE 03_defineprop_gc.js");
