// Exhaustive numeric differential: every Math fn + number formatting.
function p(l, v) { print(l + "=" + v); }

var UNARY = ["abs", "sign", "floor", "ceil", "round", "trunc", "sqrt",
             "sin", "cos", "tan", "asin", "acos", "atan",
             "exp", "log", "log2", "log10", "fround", "clz32"];

// wide sweep incl. negatives, denormals, extremes
var SPECIAL = [0, -0, 1, -1, 0.5, -0.5, 1e-320, -1e-320, 5e-324, -5e-324,
    1e308, -1e308, 1.7976931348623157e308, -1.7976931348623157e308,
    NaN, Infinity, -Infinity, 2147483647, -2147483648, 4294967295, -4294967296,
    9007199254740991, -9007199254740993, 0.1, -0.1, 1/3, -1/3,
    1e-7, -1e-7, 123456789.987654321, -123456789.987654321,
    Math.PI, -Math.PI, Math.E, -Math.E, 0.9999999999999999, -0.9999999999999999];

for (var f = 0; f < UNARY.length; f++) {
    var name = UNARY[f], out = [];
    for (var i = 0; i < SPECIAL.length; i++) out.push(Math[name](SPECIAL[i]));
    p("sp." + name, out.join(" "));
}

// dense hashed sweep over negatives and positives
for (var f = 0; f < UNARY.length; f++) {
    var name = UNARY[f], h = 0;
    for (var i = -1500; i <= 1500; i++) {
        var r = Math[name](i / 37.0);
        if (r !== r) r = 1.5; else if (r === Infinity) r = 2.5; else if (r === -Infinity) r = -2.5;
        h = (h * 33 + Math.floor(r * 1000000)) % 2147483647;
    }
    p("h." + name, h);
}

// binary functions
var bh = 0;
for (var i = -200; i <= 200; i += 3) {
    for (var j = -20; j <= 20; j += 7) {
        var a = i / 13.0, b = j / 5.0;
        var vals = [Math.pow(a, b), Math.atan2(a, b), Math.min(a, b), Math.max(a, b), Math.imul(i, j)];
        for (var k = 0; k < vals.length; k++) {
            var r = vals[k];
            if (r !== r) r = 7.5; else if (r === Infinity) r = 8.5; else if (r === -Infinity) r = -8.5;
            bh = (bh + Math.floor(r * 10000)) % 2147483647;
        }
    }
}
p("binary", bh);

// integer / bitwise operator semantics
var ih = 0;
var ints = [0, 1, -1, 31, 32, 33, -31, -32, 2147483647, -2147483648, 4294967295, 1e10, -1e10, NaN, Infinity];
for (var i = 0; i < ints.length; i++) {
    for (var j = 0; j < ints.length; j++) {
        var a = ints[i], b = ints[j];
        var r = [a | 0, a & b, a | b, a ^ b, ~a, a << (b & 31), a >> (b & 31), a >>> (b & 31)];
        for (var k = 0; k < r.length; k++) ih = (ih * 17 + (r[k] | 0)) % 2147483647;
    }
}
p("bitwise", ih);

// division / modulo edge cases
var dm = [];
var dvals = [0, -0, 1, -1, 7, -7, 0.5, Infinity, -Infinity, NaN];
for (var i = 0; i < dvals.length; i++) {
    for (var j = 0; j < dvals.length; j++) {
        dm.push(dvals[i] / dvals[j]);
        dm.push(dvals[i] % dvals[j]);
    }
}
p("divmod", dm.join(" "));

// number -> string across radixes and magnitudes
var strs = [];
var nums = [0, -0, 1, -1, 255, -255, 0.5, -0.5, 1e21, 1e-7, 123456789,
            0.1, 1/3, 1e308, 5e-324, 2147483648, 9007199254740991];
for (var i = 0; i < nums.length; i++) {
    strs.push(String(nums[i]));
    for (var r = 2; r <= 36; r += 17) strs.push(nums[i].toString(r));
}
p("numstr", strs.join(" "));

// toFixed / toPrecision / toExponential
var fx = [];
for (var i = 0; i < nums.length; i++) {
    for (var d = 0; d <= 20; d += 5) {
        try { fx.push(nums[i].toFixed(d)); } catch (e1) { fx.push("E"); }
    }
    for (var d = 1; d <= 21; d += 10) {
        try { fx.push(nums[i].toPrecision(d)); } catch (e2) { fx.push("E"); }
        try { fx.push(nums[i].toExponential(d > 20 ? 20 : d)); } catch (e3) { fx.push("E"); }
    }
}
p("fixed", fx.join(" "));

// string -> number
var parses = [];
var pstrs = ["", " ", "0", "-0", "1", "-1", ".5", "-.5", "1.", "1e3", "1e-3",
    "0x10", "0X10", "0b11", "0o17", "08", "09", "Infinity", "-Infinity", "NaN",
    "  12  ", "12abc", "abc", "1e999", "-1e999", "1e-999", ".", "-", "+",
    "1_000", "0xg", "1e", "1e+", "٣"];
for (var i = 0; i < pstrs.length; i++) {
    parses.push(Number(pstrs[i]));
    parses.push(parseInt(pstrs[i]));
    parses.push(parseFloat(pstrs[i]));
}
p("parses", parses.join(" "));

// parseInt with explicit radix
var pr = [];
for (var r = 0; r <= 37; r += 1) pr.push(parseInt("zz10", r));
p("parseRadix", pr.join(" "));

// Number constants
p("consts", [Number.MAX_VALUE, Number.MIN_VALUE, Number.EPSILON,
    Number.MAX_SAFE_INTEGER, Number.MIN_SAFE_INTEGER,
    Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY].join(" "));
p("mathconsts", [Math.E, Math.LN10, Math.LN2, Math.LOG2E, Math.LOG10E,
    Math.PI, Math.SQRT1_2, Math.SQRT2].join(" "));

// float round-trip through string
var rt = 0, bad = 0;
for (var i = 1; i <= 4000; i++) {
    var v = (i * 7919) / 1e6 * (i % 2 ? 1 : -1);
    if (Number(String(v)) !== v) bad++;
    rt = (rt + String(v).length) % 1000000;
}
p("roundtrip", rt + " bad=" + bad);

print("DONE 15_numeric_sweep.js");
