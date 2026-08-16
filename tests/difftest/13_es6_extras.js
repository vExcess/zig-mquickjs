// Documented extras: for-of, extra Math fns, **, regexp flags, extra String fns, globalThis
function p(label, v) { print(label + "=" + v); }

// for-of over arrays
var arr = [10, 20, 30, 40];
var acc = [];
for (var v of arr) acc.push(v);
p("forof", acc.join(","));

var sum = 0;
for (var v of [1, 2, 3, 4, 5]) { if (v === 3) continue; if (v === 5) break; sum += v; }
p("forofCtl", sum);

// for-of under GC pressure
var big = [];
for (var i = 0; i < 3000; i++) big.push(i);
var total = 0;
for (var v of big) {
    total += v;
    if (v % 500 === 0) { var junk = []; for (var j = 0; j < 40; j++) junk.push("f" + v + j); }
}
p("forofBig", total);

// extra Math functions
p("imul1", Math.imul(3, 4));
p("imul2", Math.imul(-5, 12));
p("imul3", Math.imul(0x7fffffff, 2));
p("imul4", Math.imul(0xffffffff, 5));
p("clz1", Math.clz32(1));
p("clz2", Math.clz32(0));
p("clz3", Math.clz32(0x80000000));
p("fround1", Math.fround(0.1));
p("fround2", Math.fround(1 / 3));
p("fround3", Math.fround(1e40));
p("trunc1", Math.trunc(-4.7));
p("log2a", Math.log2(8));
p("log2b", Math.log2(0));
p("log10a", Math.log10(1000));
p("log10b", Math.log10(0));

// exponentiation operator
p("pow1", 2 ** 10);
p("pow2", 2 ** -2);
p("pow3", (-2) ** 3);
p("pow4", 2 ** 0.5);
p("pow5", (3 ** 2) ** 2);

// regexp flags: dotall, sticky, unicode
var dot = /a.b/s;
p("dotall", dot.test("a\nb"));
p("dotallOff", /a.b/.test("a\nb"));

var sticky = /\d+/y;
sticky.lastIndex = 0;
p("sticky1", JSON.stringify(sticky.exec("12ab34")) + " li=" + sticky.lastIndex);
p("sticky2", JSON.stringify(sticky.exec("12ab34")) + " li=" + sticky.lastIndex);

var uni = /./u;
p("unicode", uni.test("\ud83d\ude00"));
p("uniFlags", /ab/gimsy.flags !== undefined ? /ab/gs.flags : "noflags");
p("reSource", /a\/b/.source);
p("reGlobal", /x/g.global + "," + /x/.global);

// extra String functions
p("cpAt1", "abc".codePointAt(0));
p("cpAt2", "\ud83d\ude00".codePointAt(0));
p("replAll1", "a-b-c".replaceAll("-", "+"));
p("replAll2", "aaa".replaceAll("a", function (m, i) { return i; }));
p("trimStart", "|" + "  x  ".trimStart() + "|");
p("trimEnd", "|" + "  x  ".trimEnd() + "|");

// \u{hex} literals
p("uhex1", "\u{48}\u{49}");
p("uhex2", "\u{1f600}".length);

// globalThis
p("gt1", typeof globalThis);
globalThis.myGlobalX = 77;
p("gt2", myGlobalX);
p("gt3", globalThis.Math === Math);

// Date.now only
p("dateType", typeof Date.now());
p("dateMono", Date.now() >= 0);

// function prototype/length/name getters
function named(a, b, c) {}
p("fnName", named.name);
p("fnLen", named.length);
p("fnProtoType", typeof named.prototype);
var anon = function (a) {};
p("anonLen", anon.length);
p("boundLen", named.bind(null, 1).length);

// for-in over own properties only
var protoObj = Object.create({ notMine: 1 });
protoObj.mine = 2;
var ks = [];
for (var k in protoObj) ks.push(k);
p("forinOwn", ks.join(","));

print("DONE 13_es6_extras.js");
