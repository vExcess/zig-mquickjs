// RegExp with many captures, replace callbacks, split, match (string builtin GC roots)
var text = "The quick brown fox jumps over the lazy dog 12345 and 67890 times";

print("m1=" + JSON.stringify(text.match(/(\w+)\s+(\w+)\s+(\w+)/)));
print("m2=" + JSON.stringify(text.match(/\d+/g)));
print("s1=" + text.search(/fox/));
print("s2=" + text.search(/nothere/));

var re = /(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/g;
var src = "abcdefghij".repeat(50);
var calls = 0;
var replaced = src.replace(re, function () {
    calls++;
    var parts = [];
    for (var i = 1; i <= 10; i++) parts.push(arguments[i]);
    return parts.reverse().join("");
});
print("re calls=" + calls + " len=" + replaced.length + " head=" + replaced.slice(0, 20));

// replace with $ patterns
print("d1=" + "abcabc".replace(/b/g, "[$&]"));
print("d2=" + "abcabc".replace(/(a)(b)/g, "$2$1"));
print("d3=" + "abcabc".replace(/b/, "$`"));
print("d4=" + "abcabc".replace(/b/, "$'"));
print("d5=" + "abc".replace(/b/, "$$"));
print("d6=" + "abc".replace(/(b)/, "$1$1$1"));
print("d7=" + "abc".replace("b", "X"));
print("d8=" + "aaa".replace(/a/g, function (m, off) { return off; }));

// split variants
print("sp1=" + JSON.stringify("a,b,,c".split(",")));
print("sp2=" + JSON.stringify("a1b2c3d".split(/\d/)));
print("sp3=" + JSON.stringify("abc".split("")));
print("sp4=" + JSON.stringify("abc".split("", 2)));
print("sp5=" + JSON.stringify("a1b2c".split(/(\d)/)));
print("sp6=" + JSON.stringify("".split(",")));
print("sp7=" + JSON.stringify("".split("")));
print("sp8=" + JSON.stringify("abc".split(undefined)));
print("sp9=" + JSON.stringify("a,b,c".split(",", 0)));

// exec with lastIndex under global
var g = /(\d)(\d)/g;
var s = "12 34 56 78";
var acc = [];
var m;
while ((m = g.exec(s)) !== null) {
    acc.push(m[0] + ":" + m[1] + ":" + m[2] + ":" + m.index + ":" + g.lastIndex);
}
print("exec=" + acc.join("|"));

// test + lastIndex
var t = /ab/g;
print("t1=" + t.test("xxabxx") + " li=" + t.lastIndex);
print("t2=" + t.test("xxabxx") + " li=" + t.lastIndex);

// heavy loop to force GC during regexp work
var count = 0;
for (var i = 0; i < 400; i++) {
    var subject = "id-" + i + "-value-" + (i * 7) + "-end";
    var mm = subject.match(/id-(\d+)-value-(\d+)-end/);
    if (mm && +mm[1] === i && +mm[2] === i * 7) count++;
    var junk = [];
    for (var j = 0; j < 15; j++) junk.push("g" + i + "_" + j);
}
print("loopMatch=" + count);

// replace under pressure with captures
var rcount = 0;
for (var i = 0; i < 300; i++) {
    var out = ("x" + i + "y" + i + "z").replace(/(\d+)y(\d+)/, function (m, a, b) {
        return b + "Y" + a;
    });
    if (out === "x" + i + "Y" + i + "z") rcount++;
}
print("loopReplace=" + rcount);

print("DONE 05_regexp.js");
