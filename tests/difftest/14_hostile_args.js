// Call every builtin with hostile arguments. Deterministic; diff C vs Zig.
// A Zig crash where C throws cleanly is a memory-safety bug.

var HOSTILE = [
    undefined, null, true, false,
    0, -0, 1, -1, 0.5, -0.5,
    NaN, Infinity, -Infinity,
    2147483647, -2147483648, 2147483648, -2147483649,
    4294967295, 4294967296, 9007199254740991, -9007199254740991,
    1e21, -1e21, 1e-300,
    "", "0", "-1", "abc", "\u0000", "\ud800", "\udfff", "\ud83d\ude00",
    [], [1, 2, 3], {}, { length: 4294967295 }, { valueOf: function () { return -1; } },
    function () { return 1; }, /re/g
];

function show(v) {
    try {
        if (typeof v === "string") return JSON.stringify(v);
        if (v !== v) return "NaN";
        if (v === Infinity) return "Inf";
        if (v === -Infinity) return "-Inf";
        if (typeof v === "function") return "fn";
        if (typeof v === "object" && v !== null) {
            var s = JSON.stringify(v);
            return s === undefined ? "obj" : (s.length > 40 ? s.slice(0, 40) + "~" : s);
        }
        return String(v);
    } catch (e) { return "SHOW_ERR"; }
}

function probe(label, fn) {
    var r;
    try { r = show(fn()); } catch (e) {
        r = "THROW:" + (e && e.name ? e.name : typeof e);
    }
    print(label + " => " + r);
}

// ---- String.prototype ----
var strMethods = ["charAt", "charCodeAt", "codePointAt", "indexOf", "lastIndexOf",
    "slice", "substring", "repeat", "split", "concat", "replace", "replaceAll",
    "toUpperCase", "toLowerCase", "trim", "trimStart", "trimEnd", "match", "search"];
var subjects = ["", "a", "hello world", "\ud83d\ude00x"];
for (var si = 0; si < subjects.length; si++) {
    for (var mi = 0; mi < strMethods.length; mi++) {
        var m = strMethods[mi];
        if (typeof String.prototype[m] !== "function") { print("str." + m + " missing"); continue; }
        for (var hi = 0; hi < HOSTILE.length; hi++) {
            (function (subj, meth, arg, tag) {
                probe(tag, function () { return String.prototype[meth].call(subj, arg); });
            })(subjects[si], m, HOSTILE[hi], "s" + si + "." + m + "[" + hi + "]");
        }
    }
}

// ---- Array.prototype ----
var arrMethods = ["join", "slice", "indexOf", "lastIndexOf", "concat", "push", "fill",
    "splice", "reverse", "sort", "map", "filter", "forEach", "reduce", "some", "every"];
for (var mi = 0; mi < arrMethods.length; mi++) {
    var m = arrMethods[mi];
    if (typeof Array.prototype[m] !== "function") { print("arr." + m + " missing"); continue; }
    for (var hi = 0; hi < HOSTILE.length; hi++) {
        (function (meth, arg, tag) {
            probe(tag, function () {
                var base = [3, 1, 2];
                var out = Array.prototype[meth].call(base, arg);
                return out === base ? "self:" + base.join(",") : show(out) + "|" + base.join(",");
            });
        })(m, HOSTILE[hi], "a." + m + "[" + hi + "]");
    }
}

// ---- Array methods on non-array this (type confusion) ----
var fakeThis = [
    "string", 42, true, {}, { length: 3 }, { length: -1 }, { length: 1e9 },
    { length: "3", 0: "a", 1: "b", 2: "c" }, null, undefined
];
for (var fi = 0; fi < fakeThis.length; fi++) {
    for (var mi = 0; mi < arrMethods.length; mi++) {
        (function (t, meth, tag) {
            if (typeof Array.prototype[meth] !== "function") return;
            probe(tag, function () { return Array.prototype[meth].call(t, 1); });
        })(fakeThis[fi], arrMethods[mi], "fa" + fi + "." + arrMethods[mi]);
    }
}

// ---- String methods on non-string this ----
for (var fi = 0; fi < fakeThis.length; fi++) {
    for (var mi = 0; mi < strMethods.length; mi++) {
        (function (t, meth, tag) {
            if (typeof String.prototype[meth] !== "function") return;
            probe(tag, function () { return String.prototype[meth].call(t, 1); });
        })(fakeThis[fi], strMethods[mi], "fs" + fi + "." + strMethods[mi]);
    }
}

// ---- Math with hostile args ----
var mathFns = ["abs", "floor", "ceil", "round", "trunc", "sqrt", "exp", "log",
    "log2", "log10", "sin", "cos", "tan", "asin", "acos", "atan", "fround", "clz32", "imul"];
for (var mi = 0; mi < mathFns.length; mi++) {
    var fn = mathFns[mi];
    if (typeof Math[fn] !== "function") { print("math." + fn + " missing"); continue; }
    for (var hi = 0; hi < HOSTILE.length; hi++) {
        (function (f, arg, tag) {
            probe(tag, function () { return Math[f](arg); });
        })(fn, HOSTILE[hi], "m." + fn + "[" + hi + "]");
    }
}
probe("m.pow2", function () { return Math.pow(HOSTILE[20], HOSTILE[21]); });
probe("m.atan2", function () { return Math.atan2(NaN, Infinity); });
probe("m.minmax", function () { return Math.min.apply(null, HOSTILE) + "/" + Math.max.apply(null, HOSTILE); });

// ---- Number / parse ----
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("num[" + hi + "]", function () { return Number(arg); });
        probe("pi[" + hi + "]", function () { return parseInt(arg); });
        probe("pf[" + hi + "]", function () { return parseFloat(arg); });
        probe("str[" + hi + "]", function () { return String(arg); });
        probe("bool[" + hi + "]", function () { return Boolean(arg); });
    })(HOSTILE[hi], hi);
}

// toFixed / toString radix boundaries
var radixes = [-1, 0, 1, 2, 10, 36, 37, 100, NaN, Infinity, 2.5];
for (var ri = 0; ri < radixes.length; ri++) {
    (function (r, ri) {
        probe("radix[" + ri + "]", function () { return (255.5).toString(r); });
        probe("fixed[" + ri + "]", function () { return (1.23456).toFixed(r); });
        probe("prec[" + ri + "]", function () { return (1.23456).toPrecision(r); });
        probe("expo[" + ri + "]", function () { return (1.23456).toExponential(r); });
    })(radixes[ri], ri);
}

// ---- JSON hostile ----
var jsonBad = ["", "{", "[", "null", "undefined", "{a:1}", '{"a":}', "[1,]",
    '"\\u"', '"\\ud800"', "1e999", "-", "00", "[[[[[[[[[[]]]]]]]]]]", '{"__proto__":1}'];
for (var ji = 0; ji < jsonBad.length; ji++) {
    (function (s, ji) {
        probe("jp[" + ji + "]", function () { return JSON.parse(s); });
    })(jsonBad[ji], ji);
}
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("js[" + hi + "]", function () { return JSON.stringify(arg); });
    })(HOSTILE[hi], hi);
}

// ---- RegExp hostile ----
var rePatterns = ["", "(", ")", "[", "a{2,1}", "\\", "(?:", "(?=a)", "(?!a)",
    "a**", "[z-a]", "\\u{110000}", "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)"];
for (var ri = 0; ri < rePatterns.length; ri++) {
    (function (pat, ri) {
        probe("rec[" + ri + "]", function () { return new RegExp(pat).source; });
        probe("rex[" + ri + "]", function () { return new RegExp(pat).test("abc"); });
    })(rePatterns[ri], ri);
}
var reFlags = ["", "g", "i", "m", "s", "y", "u", "gimsyu", "gg", "x"];
for (var fi = 0; fi < reFlags.length; fi++) {
    (function (fl, fi) {
        probe("ref[" + fi + "]", function () { return new RegExp("a", fl).test("A"); });
    })(reFlags[fi], fi);
}

// lastIndex tampering
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("reli[" + hi + "]", function () {
            var r = /a/g; r.lastIndex = arg; return r.exec("aaa") + "/" + r.lastIndex;
        });
    })(HOSTILE[hi], hi);
}

// ---- typed array hostile construction / indexing ----
if (typeof Uint8Array === "function") {
    for (var hi = 0; hi < HOSTILE.length; hi++) {
        (function (arg, hi) {
            probe("ta[" + hi + "]", function () { var t = new Uint8Array(arg); return t.length; });
            probe("tai[" + hi + "]", function () {
                var t = new Uint8Array(4); t[arg] = 1; return Array.prototype.join.call(t, ",");
            });
            probe("tar[" + hi + "]", function () { var t = new Uint8Array(4); return t[arg]; });
        })(HOSTILE[hi], hi);
    }
}

// ---- property access with hostile keys ----
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("pk[" + hi + "]", function () {
            var o = { a: 1 }; o[arg] = 2; return Object.keys(o).length + ":" + o[arg];
        });
        probe("pin[" + hi + "]", function () { return (arg in { a: 1 }); });
        probe("pdel[" + hi + "]", function () { var o = { a: 1 }; return delete o[arg]; });
    })(HOSTILE[hi], hi);
}

// ---- Object statics hostile ----
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("ok[" + hi + "]", function () { return Object.keys(arg).length; });
        probe("ocr[" + hi + "]", function () { return typeof Object.create(arg); });
        probe("ogp[" + hi + "]", function () { return typeof Object.getPrototypeOf(arg); });
    })(HOSTILE[hi], hi);
}

// ---- apply/call/bind hostile ----
function sink() { return arguments.length; }
for (var hi = 0; hi < HOSTILE.length; hi++) {
    (function (arg, hi) {
        probe("ap[" + hi + "]", function () { return sink.apply(null, arg); });
        probe("cl[" + hi + "]", function () { return sink.call(arg, 1, 2); });
        probe("bd[" + hi + "]", function () { return sink.bind(arg)(1); });
    })(HOSTILE[hi], hi);
}

print("DONE 14_hostile_args.js");
