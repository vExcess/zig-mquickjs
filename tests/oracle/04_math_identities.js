// Math identities that must hold without a C oracle.

function fail(msg) { print("FAIL " + msg); }
function near(a, b, eps) {
    if (a !== a && b !== b) return true;
    var d = a - b;
    if (d < 0) d = -d;
    return d <= eps;
}

if (Math.abs(-3) !== 3) fail("abs");
if (Math.floor(1.9) !== 1) fail("floor");
if (Math.ceil(1.1) !== 2) fail("ceil");
if (Math.trunc(-1.9) !== -1) fail("trunc");
if (Math.round(1.4) !== 1) fail("round");
if (Math.sqrt(4) !== 2) fail("sqrt");
if (Math.pow(2, 10) !== 1024) fail("pow");
if (Math.imul(3, 4) !== 12) fail("imul");
if (Math.clz32(1) !== 31) fail("clz32");
if (Math.sin(0) !== 0) fail("sin0");
if (Math.cos(0) !== 1) fail("cos0");
if (Math.tan(0) !== 0) fail("tan0");
if (Math.asin(0) !== 0) fail("asin0");
if (Math.acos(1) !== 0) fail("acos1");
if (Math.atan(0) !== 0) fail("atan0");
if (!(1 / Math.atan(-0) < 0)) fail("atan-0 sign");
if (Math.sin(-0) !== 0 || !(1 / Math.sin(-0) < 0)) fail("sin-0 sign");

var i, x, s, c;
var trigBad = 0;
for (i = -20; i <= 20; i++) {
    x = i * 0.25;
    s = Math.sin(x);
    c = Math.cos(x);
    if (!near(s * s + c * c, 1, 1e-12)) trigBad++;
    if (Math.sin(-x) !== -Math.sin(x) && x !== 0) trigBad++;
}
if (trigBad) fail("trig identities " + trigBad);
else print("ok trig");

if (!near(Math.acos(-1), Math.PI, 1e-12)) fail("acos(-1)=" + Math.acos(-1));
else print("ok acos-1");

print("ok constants");
print("DONE 04_math_identities.js");
