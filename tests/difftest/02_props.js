// Many unique property names then read back (intern identity / property tables)
var obj = {};
var N = 4000;
for (var i = 0; i < N; i++) {
    obj["key_" + i] = i * 3;
}
var miss = 0, sum = 0;
for (var i = 0; i < N; i++) {
    var k = "key_" + i;
    if (!(k in obj)) { miss++; continue; }
    if (!obj.hasOwnProperty(k)) { miss++; continue; }
    sum += obj[k];
}
print("props miss=" + miss + " sum=" + sum);

// delete half, re-add, verify
for (var i = 0; i < N; i += 2) delete obj["key_" + i];
var afterDelete = 0;
for (var i = 0; i < N; i++) if (obj.hasOwnProperty("key_" + i)) afterDelete++;
print("afterDelete=" + afterDelete);

for (var i = 0; i < N; i += 2) obj["key_" + i] = i * 5;
var sum2 = 0;
for (var i = 0; i < N; i++) sum2 += obj["key_" + i];
print("sum2=" + sum2);

// prototype chain lookups with interned keys
function Base() {}
Base.prototype.method = function () { return "base"; };
function Derived() {}
Derived.prototype = new Base();
Derived.prototype.other = function () { return "derived"; };
var insts = [];
for (var i = 0; i < 500; i++) {
    insts.push(new Derived());
    insts[i]["p" + i] = i;
}
var ok = 0;
for (var i = 0; i < 500; i++) {
    if (insts[i].method() === "base" && insts[i].other() === "derived" && insts[i]["p" + i] === i) ok++;
}
print("protoOk=" + ok);

// Object.keys ordering
var small = {};
small.z = 1; small.a = 2; small.m = 3; small[2] = 4; small[1] = 5;
print("keys=" + Object.keys(small).join(","));

// defineProperty with getters under pressure
var dp = {};
for (var i = 0; i < 300; i++) {
    (function (n) {
        Object.defineProperty(dp, "g" + n, {
            get: function () { return n * 2; },
            configurable: true
        });
    })(i);
}
var gsum = 0;
for (var i = 0; i < 300; i++) gsum += dp["g" + i];
print("gsum=" + gsum);

print("DONE 02_props.js");
