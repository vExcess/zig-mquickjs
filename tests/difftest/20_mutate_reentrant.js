// Re-entrant mutation: user code that runs *inside* a builtin and changes the
// thing the builtin is walking (array being sorted, property table being
// enumerated, regexp being matched), plus object-shape and index boundary
// edges. These are the places where an engine is most likely to be holding a
// raw pointer into a structure that the callback just reallocated.
//
// Expectations are deliberately not spec-based: several of these are
// implementation-defined and mquickjs answers them its own way. The C engine
// is the reference, so the only thing that matters is that both engines print
// the same line.

function t(name, fn) {
    try { print(name + " => " + fn()); } catch (e) { print(name + " THREW " + e); }
}

// 1. Array.prototype.sort with a comparator that resizes the array
t("sort push", function () {
    var a = [];
    for (var i = 0; i < 60; i++) a.push((i * 17) % 60);
    var n = 0;
    a.sort(function (x, y) { if ((n++ & 7) === 0) a.push(999); return x - y; });
    return a.length + " " + a[0] + " " + a[a.length - 1];
});
t("sort truncate", function () {
    var a = [];
    for (var i = 0; i < 60; i++) a.push((i * 17) % 60);
    var n = 0;
    a.sort(function (x, y) { if (n++ === 10) a.length = 5; return x - y; });
    return a.length + " " + a.join(",").slice(0, 30);
});
t("sort gc+push", function () {
    var a = [];
    for (var i = 0; i < 80; i++) a.push({ k: (i * 31) % 80 });
    var n = 0;
    a.sort(function (x, y) { if ((n++ & 15) === 0) { a.push({ k: 1000 }); gc(); } return x.k - y.k; });
    return a.length + " " + a[0].k;
});

// 2. iteration builtins whose callback resizes the backing array
t("forEach push", function () {
    var a = [1, 2, 3], seen = 0;
    a.forEach(function (x) { seen++; if (a.length < 20) a.push(x + 10); });
    return seen + " " + a.length;
});
t("map shrink", function () {
    var a = [];
    for (var i = 0; i < 40; i++) a.push(i);
    var out = a.map(function (x, i) { if (i === 5) a.length = 10; return x * 2; });
    return out.length + " " + out.join(",").slice(0, 40);
});
t("filter gc shrink", function () {
    var a = [];
    for (var i = 0; i < 40; i++) a.push(i);
    var out = a.filter(function (x, i) { if (i === 3) { a.length = 8; gc(); } return true; });
    return out.length + " " + out.join(",");
});
t("reduce mutate", function () {
    var a = [];
    for (var i = 0; i < 20; i++) a.push(i);
    return a.reduce(function (acc, x, i) { if (i === 2) a.push(100); return acc + x; }, 0) + " " + a.length;
});
t("reduceRight mutate", function () {
    var a = [];
    for (var i = 0; i < 20; i++) a.push(i);
    return a.reduceRight(function (acc, x, i) { if (i === 17) { a.length = 5; gc(); } return acc + x; }, 0) + " " + a.length;
});
t("join with toString mutating", function () {
    var a = [1, { toString: function () { a.push(9); gc(); return "M"; } }, 3];
    return a.join("-") + " len=" + a.length;
});

// 3. property tables mutated from inside a getter / setter
t("stringify getter deletes", function () {
    var o = { a: 1, b: 2, c: 3 };
    Object.defineProperty(o, "hot", { get: function () { delete o.b; gc(); return "H"; }, enumerable: true });
    o.d = 4;
    return JSON.stringify(o);
});
t("stringify getter adds", function () {
    var o = { a: 1 };
    Object.defineProperty(o, "hot", { get: function () { o["new" + o.a] = o.a++; gc(); return "H"; }, enumerable: true });
    return JSON.stringify(o) + " keys=" + Object.keys(o).length;
});
t("Object.keys getter mutates", function () {
    var o = {};
    for (var i = 0; i < 10; i++) o["k" + i] = i;
    Object.defineProperty(o, "hot", { get: function () { delete o.k3; gc(); return 1; }, enumerable: true });
    var ks = Object.keys(o), sum = 0;
    for (var i = 0; i < ks.length; i++) sum += ("" + o[ks[i]]).length;
    return ks.length + " " + sum;
});
t("forin add during", function () {
    var o = { a: 1, b: 2, c: 3 }, out = "", n = 0;
    for (var k in o) { out += k; if (n++ === 0) { o.zz = 9; gc(); } }
    return out + " keys=" + Object.keys(o).length;
});
t("forin delete during", function () {
    var o = {};
    for (var i = 0; i < 12; i++) o["d" + i] = i;
    var out = "", n = 0;
    for (var k in o) { out += k + ","; if (n++ === 2) { delete o.d7; delete o.d8; gc(); } }
    return out;
});
t("setter adds props", function () {
    var o = {}, log = [];
    Object.defineProperty(o, "s", {
        set: function (v) { for (var i = 0; i < 30; i++) o["x" + v + "_" + i] = i; gc(); log.push(v); }
    });
    for (var i = 0; i < 5; i++) o.s = i;
    return log.join(",") + " keys=" + Object.keys(o).length;
});

// 4. regexp re-entrancy
t("replace cb sets lastIndex", function () {
    var re = /(\d)/g;
    return "1a2b3c".replace(re, function (all, d) { re.lastIndex = 0; gc(); return "[" + d + "]"; });
});
t("replace cb recursive replace", function () {
    return "aXbXc".replace(/X/g, function () { gc(); return "yZy".replace(/Z/g, function () { gc(); return "-"; }); });
});
t("exec while recompiling", function () {
    var out = "";
    for (var i = 0; i < 20; i++) {
        var r = new RegExp("(a{" + (i % 5 + 1) + "})(b+)", "g");
        gc();
        var m = r.exec("aaaaabbb");
        out += (m ? m[1].length + ":" + m[2].length : "-") + " ";
    }
    return out.slice(0, 40);
});

// 5. coercion of an argument mutates the receiver mid-call
t("concat with getter", function () {
    var a = [1, 2, 3];
    var b = { valueOf: function () { a.push(4); gc(); return 7; } };
    return a.concat([b]).length + " " + a.length;
});
t("indexOf with valueOf mutate", function () {
    var a = [];
    for (var i = 0; i < 30; i++) a.push(i);
    var needle = { valueOf: function () { a.length = 5; gc(); return 20; } };
    return a.indexOf(needle) + " " + a.length;
});
t("slice args with valueOf mutate", function () {
    var a = [];
    for (var i = 0; i < 30; i++) a.push(i);
    var lo = { valueOf: function () { a.length = 4; gc(); return 2; } };
    return a.slice(lo, 25).join(",") + " len=" + a.length;
});
t("splice with valueOf mutate", function () {
    var a = [];
    for (var i = 0; i < 30; i++) a.push(i);
    var at = { valueOf: function () { a.length = 6; gc(); return 3; } };
    return a.splice(at, 10).join(",") + " left=" + a.join(",");
});
t("string method with mutating arg", function () {
    var s = "hello world";
    var idx = { valueOf: function () { gc(); return 3; } };
    return s.slice(idx) + "|" + s.substring(idx, 8) + "|" + s.indexOf("o", idx);
});

// 6. prototype surgery under gc
t("setPrototypeOf chain", function () {
    var protos = [];
    for (var i = 0; i < 60; i++) { var p = {}; p["m" + i] = "v" + i; protos.push(p); }
    for (var i = 1; i < 60; i++) Object.setPrototypeOf(protos[i], protos[i - 1]);
    gc();
    var leaf = protos[59], hits = 0;
    for (var i = 0; i < 60; i++) if (leaf["m" + i] === "v" + i) hits++;
    return hits + " proto=" + (Object.getPrototypeOf(leaf) === protos[58]);
});
t("setPrototypeOf swap", function () {
    var o = { own: 1 }, a = { s: "A" }, b = { s: "B" }, out = "";
    for (var i = 0; i < 20; i++) { Object.setPrototypeOf(o, (i & 1) ? a : b); gc(); out += o.s; }
    return out + " own=" + o.own;
});
t("setPrototypeOf null", function () {
    var o = { x: 1 };
    Object.setPrototypeOf(o, null); gc();
    return o.x + " " + (typeof o.toString) + " " + (Object.getPrototypeOf(o) === null);
});
t("shadowing", function () {
    var base = { v: "base", f: function () { return "bf"; } };
    var mid = Object.create(base); mid.v = "mid";
    var leaf = Object.create(mid);
    gc();
    var r = leaf.v + leaf.f();
    leaf.v = "leaf"; delete mid.v; gc();
    return r + " " + leaf.v + " " + mid.v + " " + base.v;
});

// 7. array length / element edges (both engines reject out-of-range
// subscripts, so keep indices in range here and check the boundary
// rejection separately)
t("bad subscript rejected", function () {
    var a = [1, 2, 3], caught = 0;
    var bad = [-1, 1e10, 2147483648, 4294967295];
    for (var i = 0; i < bad.length; i++) {
        try { a[bad[i]] = 1; } catch (e6) { caught++; }
    }
    return caught + "/" + bad.length + " len=" + a.length;
});
t("length assignment", function () {
    var a = [];
    for (var i = 0; i < 20; i++) a.push(i);
    a.length = 10; gc();
    var r1 = a.length + ":" + a[9] + ":" + a[10];
    a.length = 15; gc();
    return r1 + " -> " + a.length + ":" + a[14] + ":" + a.join(",").length;
});
t("delete elements", function () {
    var a = [];
    for (var i = 0; i < 10; i++) a.push(i);
    delete a[3]; delete a[9]; gc();
    var ks = ""; for (var k in a) ks += k + ",";
    return a.length + " " + a.join("|") + " keys=" + ks;
});

// 8. call/frame edges
t("arguments alias", function () {
    function f(a, b) { arguments[0] = 99; gc(); return a + "," + b + "," + arguments.length + "," + arguments[1]; }
    return f(1, 2);
});
t("arguments apply 200", function () {
    function f() { var s = 0; for (var i = 0; i < arguments.length; i++) s += arguments[i]; gc(); return s + ":" + arguments.length; }
    var big = [];
    for (var i = 0; i < 200; i++) big.push(i);
    return f(1, 2, 3) + " " + f.apply(null, big);
});
t("new with return value", function () {
    function C1() { this.a = 1; return { b: 2 }; }
    function C2() { this.a = 1; return 5; }
    gc();
    return JSON.stringify(new C1()) + " " + JSON.stringify(new C2());
});
t("recursive ctor gc", function () {
    function Node(d) { this.d = d; this.child = d > 0 ? new Node(d - 1) : null; if ((d % 5) === 0) gc(); }
    var n = new Node(40), depth = 0, p = n;
    while (p) { depth++; p = p.child; }
    return depth + " " + n.d;
});
t("throw through finally", function () {
    var log = "";
    function deep(n) {
        try { if (n === 0) throw new Error("bottom"); return deep(n - 1); }
        finally { log += n; if ((n % 7) === 0) gc(); }
    }
    try { deep(20); } catch (e3) { return e3.message + " log=" + log.length; }
    return "no throw";
});
t("rethrow chain", function () {
    var e = null;
    for (var i = 0; i < 30; i++) {
        try { throw new Error("lvl" + i); } catch (e4) { e = e4; gc(); }
    }
    return e.message + " " + (e.stack.indexOf("lvl") >= 0);
});
t("stack overflow recovery", function () {
    function rec() { return rec(); }
    try { rec(); } catch (e5) { gc(); return (e5 instanceof Error) + " " + (("" + e5).indexOf("stack") >= 0); }
    return "no overflow";
});

// 9. string/char edges around the UTF-8 storage
t("fromCodePoint", function () {
    return String.fromCodePoint(65, 0x1F600, 0x10FFFF).length + " " + String.fromCharCode(0x41, 0xD83D, 0xDE00).length;
});
t("nul and escapes", function () {
    var s = "a\u0000b\u00ff\u07ff\u0800\uffff";
    gc();
    return s.length + " " + s.charCodeAt(1) + " " + s.charCodeAt(5) + " " + JSON.stringify(s).length;
});
t("surrogate slicing", function () {
    var s = "a\uD83D\uDE00b";
    gc();
    return s.length + " " + s.slice(1, 3).length + " " + s.charCodeAt(1) + " " + s.codePointAt(1);
});
t("long string ops", function () {
    var s = "";
    for (var i = 0; i < 500; i++) s += "z";
    gc();
    return s.length + " " + s.indexOf("z", 400) + " " + s.lastIndexOf("z") + " " + s.replace(/z{100}/g, "-").length;
});

print("DONE 20_mutate_reentrant.js");
