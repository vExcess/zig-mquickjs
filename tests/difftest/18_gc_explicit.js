// Explicit gc() between allocation and use. A tight --memory-limit only
// collects when the allocator happens to run out; calling gc() directly puts
// a compaction between "get pointer" and "use pointer", which is what the
// Octane bug class needed. Found fix 14 (JSON number scratch buffer).

// 1. JSON.parse with numbers -- fix 14 repro. The number path allocates a
// scratch byte array for js_atod; passing the block header instead of its
// data area corrupted the header and the neighbouring block, so this failed
// with "invalid number literal" or SEGV once the heap was busy enough.
function buildJson(n) {
    var a = [];
    for (var i = 0; i < n; i++) a.push({ i: i, s: "e" + i, nested: { k: [i, i + 1] } });
    return JSON.stringify({ v: 0, arr: a });
}
for (var n = 180; n <= 200; n += 4) {
    var js = buildJson(n);
    var back = JSON.parse(js);
    print("json n=" + n + " len=" + js.length + " arr=" + back.arr.length +
          " last=" + back.arr[n - 1].s + " nested=" + back.arr[n >> 1].nested.k[1]);
}
// numbers of every shape, parsed with a live heap and gc() interleaved
var shapes = ["0", "-0", "1", "-1", "1e3", "-1.5e-7", "123456789012345678901234567890",
              "0.1", "1e308", "1e-308", "9007199254740993", "-0.0000000001",
              "1.7976931348623157e308", "5e-324", "3.141592653589793"];
for (var r = 0; r < 3; r++) {
    var doc = "[" + shapes.join(",") + "]";
    var arr = JSON.parse(doc);
    gc();
    var out = "nums" + r + ":";
    for (var i = 0; i < arr.length; i++) out += " " + arr[i];
    print(out);
    var junk = [];
    for (var i = 0; i < 400; i++) junk.push({ pad: "p" + i });
}
// deeply nested + long string values, gc() between parse and read
var deepDoc = '{"a":[';
for (var i = 0; i < 120; i++) deepDoc += (i ? "," : "") + '{"n":' + i + ',"t":"' + ("x" + i) + '","d":[' + i + ',' + (i + 1) + ',' + (i * 2) + ']}';
deepDoc += ']}';
var parsed = JSON.parse(deepDoc);
gc();
var jbad = 0;
for (var i = 0; i < 120; i++) {
    var ent = parsed.a[i];
    if (ent.n !== i || ent.t !== "x" + i || ent.d[2] !== i * 2) jbad++;
}
print("deepjson bad=" + jbad + " len=" + deepDoc.length);

// 2. typed array / ArrayBuffer data pointers across compaction
var bufs = [], tas = [];
for (var i = 0; i < 40; i++) {
    var ab = new ArrayBuffer(64);
    var u8 = new Uint8Array(ab);
    for (var j = 0; j < 64; j++) u8[j] = (i * 7 + j) & 0xff;
    bufs.push(ab); tas.push(u8);
    if ((i & 7) === 0) gc();
}
gc();
var taBad = 0;
for (var i = 0; i < tas.length; i++) {
    for (var j = 0; j < 64; j++) if (tas[i][j] !== ((i * 7 + j) & 0xff)) taBad++;
    if (tas[i].length !== 64 || bufs[i].byteLength !== 64) taBad++;
}
print("ta bad=" + taBad);
var ab2 = new ArrayBuffer(32);
var vi32 = new Int32Array(ab2), vu8 = new Uint8Array(ab2), vf64 = new Float64Array(ab2);
vi32[0] = 0x01020304; gc(); vu8[8] = 0xab; gc(); vf64[2] = 1.5; gc();
print("views " + vi32[0] + " " + vu8[8] + " " + vf64[2] + " " +
      vu8[0] + "," + vu8[1] + "," + vu8[2] + "," + vu8[3] + " " + vi32.length);

// 3. strings and interned property keys created before a gc, read after
var strs = [];
for (var i = 0; i < 150; i++) { strs.push("str" + i + "_" + ("pad" + i).length); if ((i % 25) === 0) gc(); }
gc();
var sBad = 0;
for (var i = 0; i < 150; i++) if (strs[i] !== "str" + i + "_" + ("pad" + i).length) sBad++;
var big = "";
for (var i = 0; i < 200; i++) { big += "chunk" + (i % 10); if ((i % 50) === 0) gc(); }
gc();
var sl = big.slice(100, 200);
print("strings bad=" + sBad + " big=" + big.length + " tail=" + big.slice(-15) +
      " slice=" + sl.slice(0, 10) + " stable=" + (sl === big.slice(100, 200)));
var o = {}, keys = [];
for (var i = 0; i < 300; i++) { var k = "dyn" + i + "key"; keys.push(k); o[k] = i; if ((i % 50) === 0) gc(); }
gc();
var kBad = 0;
for (var i = 0; i < 300; i++) {
    if (o[keys[i]] !== i || o["dyn" + i + "key"] !== i || !o.hasOwnProperty(keys[i])) kBad++;
}
print("keys bad=" + kBad + " count=" + Object.keys(o).length);

// 4. regexp match arrays held across gc, callbacks that gc
var results = [];
for (var i = 0; i < 80; i++) {
    results.push(/(\w+)-(\d+)/.exec("item" + i + "-" + (i * 3)));
    if ((i % 20) === 0) gc();
}
gc();
var rBad = 0;
for (var i = 0; i < 80; i++) {
    var m = results[i];
    if (m[1] !== "item" + i || m[2] !== "" + (i * 3) || m.index !== 0) rBad++;
    if (m[0] !== "item" + i + "-" + (i * 3)) rBad++;
}
print("regexp bad=" + rBad);
print("replace cb " + "a1 b2 c3 d4 e5".replace(/([a-z])(\d)/g, function (all, l, d) { gc(); return d + l.toUpperCase(); }));

// 5. functions compiled at runtime, then gc'd before being called
var fns = [];
for (var i = 0; i < 40; i++) {
    fns.push((1, eval)("(function f" + i + "(a){ return a + " + i + " + \"s" + i + "\".length; })"));
    if ((i % 10) === 0) gc();
}
gc();
var fBad = 0;
for (var i = 0; i < 40; i++) if (fns[i](10) !== 10 + i + ("s" + i).length) fBad++;
var cf = [];
for (var i = 0; i < 30; i++) { cf.push(new Function("x", "return x * " + i + " + " + i + ";")); if ((i % 10) === 0) gc(); }
gc();
var cBad = 0;
for (var i = 0; i < 30; i++) if (cf[i](3) !== 3 * i + i) cBad++;
print("evalfns bad=" + fBad + " name=" + fns[5].name + " ctorfns bad=" + cBad);

// 6. closures, varrefs and bound functions across gc
function mkCounter(n) {
    var count = n, tag = "c" + n;
    return { inc: function () { count += 1; return count; }, tag: function () { return tag + ":" + count; } };
}
var cs = [];
for (var i = 0; i < 120; i++) { cs.push(mkCounter(i)); if ((i % 30) === 0) gc(); }
gc();
for (var i = 0; i < cs.length; i++) cs[i].inc();
gc();
var clBad = 0;
for (var i = 0; i < cs.length; i++) if (cs[i].tag() !== "c" + i + ":" + (i + 1)) clBad++;
function target(a, b, c) { return this.base + a + b + c; }
var bfs = [];
for (var i = 0; i < 60; i++) { bfs.push(target.bind({ base: i }, i, i)); if ((i % 15) === 0) gc(); }
gc();
var bBad = 0;
for (var i = 0; i < 60; i++) if (bfs[i](1) !== i * 3 + 1) bBad++;
print("closures bad=" + clBad + " bound bad=" + bBad);

// 7. errors and backtraces across gc
var errs = [];
for (var i = 0; i < 40; i++) {
    try { (function lvl1() { (function lvl2() { throw new Error("boom" + i); })(); })(); }
    catch (e) { errs.push(e); }
    if ((i % 10) === 0) gc();
}
gc();
var eBad = 0;
for (var i = 0; i < 40; i++) {
    if (errs[i].message !== "boom" + i) eBad++;
    if (typeof errs[i].stack !== "string" || errs[i].stack.indexOf("lvl2") < 0) eBad++;
}
print("errors bad=" + eBad);

// 8. array growth, sort and splice with gc in the comparator
var arr = [];
for (var i = 0; i < 400; i++) { arr.push((i * 137) % 400); if ((i % 100) === 0) gc(); }
gc();
arr.sort(function (a, b) { gc(); return a - b; });
var sp = arr.splice(100, 50);
gc();
print("sorted " + arr[0] + " " + arr[200] + " len=" + arr.length +
      " splice=" + sp.length + "," + sp[0] + "," + sp[49] + " idx=" + arr.indexOf(350));
print("DONE 18_gc_explicit.js");
