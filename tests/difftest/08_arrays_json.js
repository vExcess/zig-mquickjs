// Array builtins + JSON round trips under GC pressure
function p(label, v) { print(label + "=" + v); }

var a = [5, 3, 9, 1, 7, 2, 8];
p("join", a.join("-"));
p("rev", a.slice().reverse().join(","));
p("sortDefault", [10, 9, 1, 100, 20].sort().join(","));
p("sortNum", a.slice().sort(function (x, y) { return x - y; }).join(","));
p("sortDesc", a.slice().sort(function (x, y) { return y - x; }).join(","));
p("concat", [1, 2].concat([3, 4], 5, [[6]]).join("|"));
p("slice1", a.slice(2, 5).join(","));
p("slice2", a.slice(-3).join(","));
p("indexOf", a.indexOf(9));
p("lastIndexOf", [1, 2, 1].lastIndexOf(1));
p("push", (function () { var x = [1]; x.push(2, 3); return x.join(","); })());
p("pop", (function () { var x = [1, 2, 3]; var v = x.pop(); return v + "/" + x.join(","); })());
p("shift", (function () { var x = [1, 2, 3]; var v = x.shift(); return v + "/" + x.join(","); })());
p("unshift", (function () { var x = [3]; x.unshift(1, 2); return x.join(","); })());
p("splice1", (function () { var x = [1, 2, 3, 4, 5]; var r = x.splice(1, 2); return r.join(",") + "/" + x.join(","); })());
p("splice2", (function () { var x = [1, 2, 3]; x.splice(1, 0, 9, 9); return x.join(","); })());
p("map", a.map(function (v) { return v * 2; }).join(","));
p("filter", a.filter(function (v) { return v > 4; }).join(","));
p("reduce", a.reduce(function (x, y) { return x + y; }, 0));
p("reduceRight", ["a", "b", "c"].reduceRight(function (x, y) { return x + y; }));
p("some", a.some(function (v) { return v > 8; }));
p("every", a.every(function (v) { return v > 0; }));
p("forEach", (function () { var s = 0; a.forEach(function (v) { s += v; }); return s; })());

// sparse / holes / length (no elisions: unsupported by mquickjs)
var sp = [1, 2, 3];
delete sp[1];
p("sparseLen", sp.length);
p("sparseJoin", sp.join(","));
p("sparse1", sp[1]);
var la = [1, 2, 3];
la.length = 1;
p("truncLen", la.join(","));
la.length = 3;
p("growLen", la.length + "/" + la.join(","));

// array growth under GC pressure
var grow = [];
for (var i = 0; i < 5000; i++) {
    grow.push({ id: i, name: "item-" + i });
}
var gsum = 0;
for (var i = 0; i < grow.length; i++) gsum += grow[i].id;
p("growSum", gsum);
p("growName", grow[4999].name);

// sort stability / comparator that allocates
var objs = [];
for (var i = 0; i < 400; i++) objs.push({ k: i % 20, v: i });
objs.sort(function (x, y) {
    var junk = "cmp" + x.v + "_" + y.v;
    return x.k - y.k;
});
var order = [];
for (var i = 0; i < 10; i++) order.push(objs[i].k + ":" + objs[i].v);
p("sortObjs", order.join(","));

// JSON round trip
var data = {
    n: 42, f: 3.5, s: "text \"quoted\" \\ back / slash\n\ttab",
    b: true, nul: null,
    arr: [1, "two", false, null, { nested: true }],
    obj: { a: { b: { c: [1, 2, 3] } } }
};
var js = JSON.stringify(data);
p("jsonLen", js.length);
p("json", js);
var back = JSON.parse(js);
p("roundtrip", JSON.stringify(back) === js);
p("deep", back.obj.a.b.c.join(","));

// JSON with many keys (intern pressure)
var wide = {};
for (var i = 0; i < 800; i++) wide["k" + i] = i;
var wjs = JSON.stringify(wide);
var wback = JSON.parse(wjs);
var wsum = 0, wmiss = 0;
for (var i = 0; i < 800; i++) {
    if (wback["k" + i] !== i) wmiss++;
    wsum += wback["k" + i];
}
p("wideSum", wsum + " miss=" + wmiss);

// JSON edge cases
p("je1", JSON.stringify(undefined));
p("je2", JSON.stringify(null));
p("je3", JSON.stringify([undefined, function () {}]));
p("je4", JSON.stringify({ a: undefined }));
p("je5", JSON.stringify(NaN));
p("je6", JSON.stringify(Infinity));
p("je7", JSON.stringify("\u001f\u007f"));
p("je8", JSON.parse("[1,2,3]").length);
p("je9", JSON.stringify({ "":1 }));
p("je10", JSON.stringify([1.0, 2.5, -0]));

print("DONE 08_arrays_json.js");
