// User callbacks that run *inside* engine internals, with gc() forced from
// the callback. 18_gc_explicit.js puts a collection between allocation and
// use at the script level; this one puts one in the middle of a builtin
// while the builtin still holds raw pointers (property table, capture
// buffer, sort scratch, ToPrimitive method).
//
// Also covers property tables an order of magnitude larger than 02_props.js
// (10k+ keys with delete / re-add / for-in), which the Phase 1C watchlist
// in debug-notes.md called out as untested.

// 1. large property tables: grow, delete, re-add, enumerate -- with gc()
// interleaved so the table is rehashed/compacted between operations.
var big = {}, N = 12000;
for (var i = 0; i < N; i++) {
    big["p" + i] = i;
    if ((i % 3000) === 0) gc();
}
gc();
var missing = 0, wrong = 0;
for (var i = 0; i < N; i++) {
    if (!big.hasOwnProperty("p" + i)) missing++;
    else if (big["p" + i] !== i) wrong++;
}
print("bigtable missing=" + missing + " wrong=" + wrong + " keys=" + Object.keys(big).length);

// delete every third key, gc, then put them back with fresh key strings
var deleted = 0;
for (var i = 0; i < N; i += 3) { delete big["p" + i]; deleted++; }
gc();
var ghost = 0;
for (var i = 0; i < N; i += 3) if (big.hasOwnProperty("p" + i)) ghost++;
for (var i = 0; i < N; i += 3) big["p" + i] = i * 2;
gc();
var readd = 0;
for (var i = 0; i < N; i += 3) if (big["p" + i] !== i * 2) readd++;
print("bigtable deleted=" + deleted + " ghost=" + ghost + " readd_bad=" + readd +
      " keys=" + Object.keys(big).length);

// for-in over the whole table, with a gc() partway through the enumeration
var seen = 0, sum = 0, gcDone = false;
for (var k in big) {
    seen++;
    sum = (sum + big[k]) % 1000003;
    if (!gcDone && seen === (N >> 1)) { gc(); gcDone = true; }
}
print("forin seen=" + seen + " sum=" + sum);

// numeric-looking keys share the interning path with is_num_string
var numKeys = {};
for (var i = 0; i < 4000; i++) { numKeys["" + i] = i; if ((i % 1000) === 0) gc(); }
gc();
var nkBad = 0;
for (var i = 0; i < 4000; i++) if (numKeys[i] !== i || numKeys["" + i] !== i) nkBad++;
print("numkeys bad=" + nkBad + " len=" + Object.keys(numKeys).length);

// 2. accessor properties whose getter/setter collects
var acc = {}, store = {};
for (var i = 0; i < 200; i++) {
    (function (n) {
        Object.defineProperty(acc, "g" + n, {
            get: function () { gc(); return "v" + n + ":" + ("t" + n).length; },
            set: function (v) { gc(); store["g" + n] = v + "!" + n; }
        });
    })(i);
}
gc();
var accBad = 0;
for (var i = 0; i < 200; i++) {
    if (acc["g" + i] !== "v" + i + ":" + ("t" + i).length) accBad++;
    acc["g" + i] = "s" + i;
    if (store["g" + i] !== "s" + i + "!" + i) accBad++;
}
print("accessors bad=" + accBad + " stored=" + Object.keys(store).length);

// accessor inherited through a prototype, read after the proto table moved
function Base() {}
Object.defineProperty(Base.prototype, "computed", {
    get: function () { gc(); return this.raw * 3 + "-" + this.tag; }
});
var insts = [];
for (var i = 0; i < 120; i++) { var o = new Base(); o.raw = i; o.tag = "t" + i; insts.push(o); }
gc();
var protoBad = 0;
for (var i = 0; i < 120; i++) if (insts[i].computed !== i * 3 + "-t" + i) protoBad++;
print("protoaccessor bad=" + protoBad);

// JSON.stringify walks the object while a getter collects underneath it
var jo = { plain: 1 };
for (var i = 0; i < 40; i++) {
    (function (n) {
        Object.defineProperty(jo, "j" + n, {
            get: function () { gc(); return { n: n, s: "j" + n, a: [n, n + 1] }; },
            enumerable: true
        });
    })(i);
}
gc();
var js = JSON.stringify(jo);
gc();
var back = JSON.parse(js);
var jBad = 0;
for (var i = 0; i < 40; i++) {
    var e = back["j" + i];
    if (!e || e.n !== i || e.s !== "j" + i || e.a[1] !== i + 1) jBad++;
}
print("stringify_getter bad=" + jBad + " len=" + js.length + " plain=" + back.plain);

// 3. regexp callbacks that collect while the engine holds the capture buffer
var subject = "";
for (var i = 0; i < 60; i++) subject += "k" + i + "=" + (i * 11) + ";";
var repl = subject.replace(/k(\d+)=(\d+)/g, function (all, key, val) {
    gc();
    return "K" + key + ":" + (val.length + all.length);
});
gc();
print("replace len=" + repl.length + " head=" + repl.slice(0, 24) + " tail=" + repl.slice(-14));

var joined = subject.split(/[=;]/).join("|");
gc();
print("split parts=" + subject.split(/[=;]/).length + " same=" + (joined === subject.split(/[=;]/).join("|")) +
      " head=" + joined.slice(0, 18));

// nested: a replace callback that itself runs a regexp and collects
var nested = "aa bb cc dd".replace(/(\w)\1/g, function (all, ch) {
    gc();
    var inner = ("x" + ch + "x").replace(/x/g, function (m) { gc(); return m.toUpperCase(); });
    return inner + all.length;
});
print("nested " + nested);

// exec results and lastIndex across gc on a stateful global regexp
var re = /(\d+)([a-z])/g, hits = [];
var stream = "";
for (var i = 0; i < 50; i++) stream += i + String.fromCharCode(97 + (i % 26)) + " ";
var m;
while ((m = re.exec(stream)) !== null) { hits.push(m[1] + m[2] + "@" + m.index); gc(); }
print("exec hits=" + hits.length + " first=" + hits[0] + " last=" + hits[hits.length - 1] +
      " lastIndex=" + re.lastIndex);

// 4. array builtins whose callback collects
var src = [];
for (var i = 0; i < 500; i++) src.push(i);
var mapped = src.map(function (x) { if ((x % 100) === 0) gc(); return { v: x, s: "m" + x }; });
gc();
var mBad = 0;
for (var i = 0; i < 500; i++) if (mapped[i].v !== i || mapped[i].s !== "m" + i) mBad++;
var filtered = mapped.filter(function (o) { if ((o.v % 100) === 0) gc(); return (o.v % 7) === 0; });
var reduced = filtered.reduce(function (a, o) { if ((o.v % 100) === 0) gc(); return a + o.v; }, 0);
var everyOk = src.every(function (x) { if ((x % 200) === 0) gc(); return x < 500; });
var someOk = src.some(function (x) { if ((x % 200) === 0) gc(); return x === 499; });
print("map bad=" + mBad + " filtered=" + filtered.length + " reduced=" + reduced +
      " every=" + everyOk + " some=" + someOk);

// sort comparator that allocates (a cheap gc every 64th compare only: a gc on
// every compare of a large array costs ~100 s, see difftest README)
var toSort = [], cmpCount = 0;
for (var i = 0; i < 300; i++) toSort.push({ k: (i * 149) % 300, s: "s" + i });
toSort.sort(function (a, b) {
    if ((++cmpCount & 63) === 0) gc();
    var pad = "cmp" + a.k + b.k;
    return a.k - b.k + (pad.length - pad.length);
});
gc();
var sortBad = 0;
for (var i = 0; i < 300; i++) if (toSort[i].k !== i) sortBad++;
print("sort bad=" + sortBad + " first=" + toSort[0].s + " last=" + toSort[299].s);

// 5. ToPrimitive hooks that collect (valueOf / toString run inside coercion).
// This engine's ToPrimitive prefers valueOf for both hints, so record what
// actually comes back rather than asserting spec behaviour -- a divergence
// between the two engines is what matters here.
function Coercible(n) { this.n = n; }
Coercible.prototype.valueOf = function () { gc(); return this.n * 2; };
Coercible.prototype.toString = function () { gc(); return "C<" + this.n + ">"; };
var cs = [], coHash = 0, coStr = "";
for (var i = 0; i < 120; i++) cs.push(new Coercible(i));
gc();
for (var i = 0; i < 120; i++) {
    coHash = (coHash * 31 + (cs[i] + 0)) % 1000003;
    coStr = ("" + cs[i]) + ("x" + cs[i]);
    if (coStr.length > 40) coStr = "?";
}
function StrOnly(n) { this.n = n; }
StrOnly.prototype.toString = function () { gc(); return "S<" + this.n + ">"; };
var soBad = 0, sos = [];
for (var i = 0; i < 120; i++) sos.push(new StrOnly(i));
gc();
for (var i = 0; i < 120; i++) if (("" + sos[i]) !== "S<" + i + ">") soBad++;
var keyObj = { toString: function () { gc(); return "computed_key"; } };
var host = {};
host[keyObj] = "hit";
gc();
print("coerce hash=" + coHash + " sample=" + (cs[7] + 0) + "/" + ("" + cs[7]) +
      " stronly bad=" + soBad + " computedkey=" + host.computed_key +
      " has=" + host.hasOwnProperty("computed_key"));

// 6. strings built and sliced with collections in between
var parts = [];
for (var i = 0; i < 300; i++) { parts.push("frag" + i); if ((i % 75) === 0) gc(); }
var joinedStr = parts.join("-");
gc();
var re2 = joinedStr.split("-");
print("strjoin len=" + joinedStr.length + " parts=" + re2.length + " mid=" + re2[150] +
      " sub=" + joinedStr.substring(10, 24) + " idx=" + joinedStr.indexOf("frag299"));

var acc2 = "";
for (var i = 0; i < 400; i++) {
    acc2 += String.fromCharCode(65 + (i % 26));
    if ((i % 80) === 0) { gc(); acc2 = acc2.slice(0); }
}
gc();
print("strbuild len=" + acc2.length + " head=" + acc2.slice(0, 10) + " tail=" + acc2.slice(-10) +
      " charAt=" + acc2.charAt(200) + " code=" + acc2.charCodeAt(399));

// 7. parser paths with a collection between compile and call
var compiled = [];
for (var i = 0; i < 30; i++) {
    var srcTxt = "(function h" + i + "(a, b) {" +
        " var t = { key" + i + ": a + b, tag: 'g" + i + "' };" +
        " for (var q = 0; q < 3; q++) { t.tag += q; }" +
        " return t.key" + i + " + t.tag.length; })";
    compiled.push((1, eval)(srcTxt));
    gc();
}
gc();
var pBad = 0;
for (var i = 0; i < 30; i++) if (compiled[i](i, 1) !== i + 1 + ("g" + i + "012").length) pBad++;
print("parsefns bad=" + pBad);

print("DONE 19_gc_hooks.js");
