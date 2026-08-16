// Typed arrays / ArrayBuffer
function p(label, v) { print(label + "=" + v); }

var types = ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array",
             "Uint32Array", "Int32Array", "Float32Array", "Float64Array",
             "Uint8ClampedArray"];
for (var t = 0; t < types.length; t++) {
    var name = types[t];
    var Ctor = globalThis[name];
    if (typeof Ctor !== "function") { p(name, "missing"); continue; }
    var ta = new Ctor(8);
    for (var i = 0; i < 8; i++) ta[i] = i * 37 - 100;
    p(name + ".len", ta.length);
    p(name + ".vals", Array.prototype.join.call(ta, ","));
    p(name + ".bpe", Ctor.BYTES_PER_ELEMENT);
}

// overflow / clamping / truncation semantics
var u8 = new Uint8Array(6);
u8[0] = 255; u8[1] = 256; u8[2] = -1; u8[3] = 1.9; u8[4] = -1.9; u8[5] = NaN;
p("u8", Array.prototype.join.call(u8, ","));

var i8 = new Int8Array(4);
i8[0] = 127; i8[1] = 128; i8[2] = -128; i8[3] = -129;
p("i8", Array.prototype.join.call(i8, ","));

if (typeof Uint8ClampedArray === "function") {
    var uc = new Uint8ClampedArray(5);
    uc[0] = 300; uc[1] = -5; uc[2] = 1.5; uc[3] = 2.5; uc[4] = 3.5;
    p("clamped", Array.prototype.join.call(uc, ","));
}

var f32 = new Float32Array(4);
f32[0] = 0.1; f32[1] = 1 / 3; f32[2] = 1e40; f32[3] = -0;
p("f32", Array.prototype.join.call(f32, ","));

var f64 = new Float64Array(3);
f64[0] = 0.1; f64[1] = 1 / 3; f64[2] = 1e308;
p("f64", Array.prototype.join.call(f64, ","));

// ArrayBuffer sharing between views
if (typeof ArrayBuffer === "function") {
    var buf = new ArrayBuffer(16);
    p("bufLen", buf.byteLength);
    var v8 = new Uint8Array(buf);
    var v32 = new Uint32Array(buf);
    for (var i = 0; i < 16; i++) v8[i] = i;
    p("v32", Array.prototype.join.call(v32, ","));
    v32[0] = 0xdeadbeef;
    p("v8after", Array.prototype.join.call(v8, ","));
    p("v8byteLen", v8.byteLength);
    var sub = new Uint8Array(buf, 4, 4);
    p("sub", Array.prototype.join.call(sub, ",") + " off=" + sub.byteOffset);
}

// construction from array / another typed array
var fromArr = new Uint8Array([1, 2, 3, 250]);
p("fromArr", Array.prototype.join.call(fromArr, ","));
var fromTa = new Int32Array(fromArr);
p("fromTa", Array.prototype.join.call(fromTa, ","));

// set / subarray if present
if (typeof fromArr.set === "function") {
    var dst = new Uint8Array(6);
    dst.set(fromArr, 1);
    p("set", Array.prototype.join.call(dst, ","));
}
if (typeof fromArr.subarray === "function") {
    p("subarray", Array.prototype.join.call(fromArr.subarray(1, 3), ","));
}

// typed arrays under GC pressure
var keep = [];
var acc = 0;
for (var i = 0; i < 400; i++) {
    var a = new Uint16Array(16);
    for (var j = 0; j < 16; j++) a[j] = (i * j) & 0xffff;
    if (i % 20 === 0) keep.push(a);
    acc = (acc + a[15]) % 100000;
    var junk = [];
    for (var j = 0; j < 10; j++) junk.push("ta" + i + j);
}
p("taAcc", acc);
p("taKeep", keep.length + "/" + keep[0][3] + "/" + keep[keep.length - 1][3]);

// out of range reads
var oob = new Uint8Array(2);
p("oob1", oob[5]);
p("oob2", typeof oob[5]);

print("DONE 12_typedarrays.js");
