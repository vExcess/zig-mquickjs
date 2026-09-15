// JSON.parse(JSON.stringify(x)) must equal x for supported shapes.
// Interleave gc() so heap compaction cannot clobber scratch buffers (fix 14 class).

function check(label, x) {
    var s = JSON.stringify(x);
    gc();
    var y = JSON.parse(s);
    gc();
    var s2 = JSON.stringify(y);
    if (s !== s2) {
        print("FAIL " + label + " stringify " + s + " vs " + s2);
        return;
    }
    print("ok " + label);
}

check("num", { n: 1, z: 0, neg: -2, f: 1.5 });
check("str", { a: "hello", b: "", c: "x\ny" });
check("bool", { t: true, f: false, n: null });
check("arr", [1, "a", true, null, [2, 3]]);
check("obj", { a: 1, b: { c: [4, 5] } });

var shapes = [0, 1, -1, 1.5, 1e3, -1.5e-7, 9007199254740992];
var doc = JSON.stringify(shapes);
gc();
var back = JSON.parse(doc);
gc();
var bad = 0;
for (var i = 0; i < shapes.length; i++) {
    if (back[i] !== shapes[i]) bad++;
}
if (bad) print("FAIL nums bad=" + bad);
else print("ok nums");
var mz = JSON.parse("-0");
if (mz !== 0 || !(1 / mz < 0)) print("FAIL JSON.parse(-0)");
else print("ok JSON -0");

var deep = [];
for (var i = 0; i < 80; i++) deep.push({ i: i, s: "e" + i, k: [i, i + 1] });
var ds = JSON.stringify(deep);
gc();
var dp = JSON.parse(ds);
gc();
var dbad = 0;
for (var i = 0; i < 80; i++) {
    if (dp[i].i !== i || dp[i].s !== "e" + i || dp[i].k[1] !== i + 1) dbad++;
}
if (dbad) print("FAIL deep bad=" + dbad);
else print("ok deep " + dp.length);

print("DONE 01_json_roundtrip.js");
