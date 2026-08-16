// Function.prototype.bind chains under stack/heap pressure
function target(a, b, c, d) {
    return [this && this.tag, a, b, c, d].join("|");
}

var out = [];
for (var i = 0; i < 200; i++) {
    var ctx = { tag: "t" + i };
    var b1 = target.bind(ctx, i);
    var b2 = b1.bind(null, i + 1);
    var b3 = b2.bind(null, i + 2);
    out.push(b3(i + 3));
    var junk = [];
    for (var j = 0; j < 20; j++) junk.push("junk" + i + "_" + j);
}
print("bind0=" + out[0]);
print("bind199=" + out[199]);
print("bindLen=" + out.length);

// bind + apply + call
function sum3(a, b, c) { return (a | 0) + (b | 0) + (c | 0); }
var total = 0;
for (var i = 0; i < 500; i++) {
    total += sum3.apply(null, [i, i + 1, i + 2]);
    total += sum3.call(null, i, 1, 2);
    total += sum3.bind(null, i)(2, 3);
}
print("callTotal=" + total);

// recursion depth with closures
function makeCounter() {
    var n = 0;
    return function () { n++; return n; };
}
var counters = [];
for (var i = 0; i < 300; i++) counters.push(makeCounter());
var csum = 0;
for (var i = 0; i < 300; i++) { counters[i](); counters[i](); csum += counters[i](); }
print("csum=" + csum);

// arguments object
function withArgs() {
    var s = 0;
    for (var i = 0; i < arguments.length; i++) s += arguments[i];
    return s + "/" + arguments.length;
}
print("args=" + withArgs(1, 2, 3, 4, 5));
print("argsEmpty=" + withArgs());

print("DONE 03_bind.js");
