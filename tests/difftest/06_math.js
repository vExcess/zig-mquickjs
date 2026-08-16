// Math edge cases and number formatting
function p(label, v) { print(label + "=" + v); }

p("floor1", Math.floor(-0.5));
p("floor2", Math.floor(0.5));
p("floor3", Math.floor(-1.0000001));
p("ceil1", Math.ceil(-0.5));
p("ceil2", Math.ceil(0.5));
p("round1", Math.round(-0.5));
p("round2", Math.round(0.5));
p("round3", Math.round(2.5));
p("round4", Math.round(-2.5));
p("round5", Math.round(0.49999999999999994));
p("trunc1", Math.trunc(-1.9));
p("trunc2", Math.trunc(1.9));

p("pow1", Math.pow(2, 10));
p("pow2", Math.pow(2, -10));
p("pow3", Math.pow(-2, 3));
p("pow4", Math.pow(-2, 0.5));
p("pow5", Math.pow(0, 0));
p("pow6", Math.pow(-1, Infinity));
p("pow7", Math.pow(1.0000001, 1000000));
p("pow8", Math.pow(10, 308));
p("pow9", Math.pow(10, 309));
p("pow10", Math.pow(2, 0.5));

p("sqrt1", Math.sqrt(2));
p("sqrt2", Math.sqrt(-1));
p("abs1", Math.abs(-0));
p("min1", Math.min(1, 2, -3));
p("max1", Math.max(1, 2, -3));
p("min2", Math.min());
p("max2", Math.max());
p("minNaN", Math.min(1, NaN));

p("exp1", Math.exp(1));
p("log1", Math.log(Math.E));
p("log2", Math.log(0));
p("log3", Math.log(-1));
p("sin1", Math.sin(0));
p("cos1", Math.cos(0));
p("atan2", Math.atan2(1, 1));

// integer edge cases
p("i1", (0x7fffffff | 0) + 1);
p("i2", -2147483648 | 0);
p("i3", 1 << 31);
p("i4", 1 >>> 0);
p("i5", -1 >>> 0);
p("i6", (1 << 30) * 2);
p("i7", 2147483647 + 1);
p("i8", 0.1 + 0.2);
p("i9", 1 / 3);
p("i10", 1e21);
p("i11", 1e-7);
p("i12", -0 === 0);
p("i13", 1 / -0);

// number formatting
p("f1", (1.005).toFixed(2));
p("f2", (1234.5678).toFixed(3));
p("f3", (0).toFixed(2));
p("f4", (255).toString(16));
p("f5", (255).toString(2));
p("f6", (-255).toString(36));
p("f7", (1.5).toString(2));
p("f8", parseInt("0x1f", 16));
p("f9", parseInt("  42abc"));
p("f10", parseFloat("3.14xyz"));
p("f11", parseInt("08"));
p("f12", Number("0x10"));
p("f13", Number(""));
p("f14", Number("  12  "));
p("f15", String(1e100));
p("f16", String(123456789012345678901234567890));
p("f17", (123.456).toPrecision(5));
p("f18", (0.000001234).toExponential(3));

// checksum-style loop (catches accumulated FP/int drift)
var chk = 0;
for (var i = 1; i <= 20000; i++) {
    chk = (chk + Math.floor(Math.sqrt(i) * 1000)) % 1000000007;
    chk = (chk * 31 + (i % 7)) % 1000000007;
}
p("checksum", chk);

var fchk = 0;
for (var i = 1; i <= 5000; i++) {
    fchk += Math.pow(i % 13, 1.5) / (i + 1);
}
p("fchecksum", fchk.toFixed(10));

print("DONE 06_math.js");
