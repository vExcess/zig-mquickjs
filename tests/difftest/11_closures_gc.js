// Closure var refs (detached varrefs are GC-sensitive) + heavy churn
function p(label, v) { print(label + "=" + v); }

// closures outliving their frame (varref detach on return)
function makePair(n) {
    var a = "a" + n;
    var b = [n, n * 2];
    return {
        get: function () { return a + ":" + b.join("/"); },
        bump: function () { b.push(b.length); return b.length; }
    };
}
var pairs = [];
for (var i = 0; i < 800; i++) {
    pairs.push(makePair(i));
    var junk = [];
    for (var j = 0; j < 12; j++) junk.push("c" + i + "_" + j);
}
var ok = 0;
for (var i = 0; i < 800; i++) {
    pairs[i].bump();
    if (pairs[i].get() === "a" + i + ":" + i + "/" + (i * 2) + "/2") ok++;
}
p("closureOk", ok);

// shared mutable capture
function counterFactory() {
    var count = 0;
    var inc = function () { count++; };
    var get = function () { return count; };
    return { inc: inc, get: get };
}
var cf = counterFactory();
for (var i = 0; i < 5000; i++) {
    cf.inc();
    if (i % 500 === 0) { var junk2 = []; for (var j = 0; j < 100; j++) junk2.push("k" + j); }
}
p("sharedCapture", cf.get());

// closure chains capturing outer-outer scope
function outerA(x) {
    return function outerB(y) {
        return function outerC(z) {
            return x + y + z;
        };
    };
}
var chainSum = 0;
for (var i = 0; i < 600; i++) {
    chainSum += outerA(i)(i * 2)(i * 3);
    var junk3 = "chain" + i;
}
p("chainSum", chainSum);

// recursive closure holding itself
function makeFact() {
    var fact = function (n) { return n <= 1 ? 1 : n * fact(n - 1); };
    return fact;
}
p("fact10", makeFact()(10));
p("fact20", makeFact()(20));

// objects referencing each other (cycles) with heavy allocation
var head = null;
for (var i = 0; i < 2000; i++) {
    var node = { id: i, next: head, tag: "node-" + i };
    if (head) head.prev = node;
    head = node;
}
var walk = 0, cur = head;
while (cur) { walk += cur.id; cur = cur.next; }
p("listSum", walk);
p("listHead", head.tag);

// drop and rebuild to force collection of the old graph
head = null;
var head2 = null;
for (var i = 0; i < 2000; i++) head2 = { id: i, next: head2 };
var walk2 = 0; cur = head2;
while (cur) { walk2 += cur.id; cur = cur.next; }
p("listSum2", walk2);

// string keys built at runtime used as object identity across GC
var reg = {};
for (var i = 0; i < 1200; i++) {
    var key = "dyn" + (i % 300);
    reg[key] = (reg[key] || 0) + 1;
    var junk4 = [];
    for (var j = 0; j < 8; j++) junk4.push(key + j);
}
var total = 0, distinct = 0;
for (var k in reg) { distinct++; total += reg[k]; }
p("regDistinct", distinct);
p("regTotal", total);

print("DONE 11_closures_gc.js");
