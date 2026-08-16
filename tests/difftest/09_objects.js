// Object semantics, coercion, prototypes, operators
function p(label, v) { print(label + "=" + v); }

// typeof
p("t1", typeof undefined);
p("t2", typeof null);
p("t3", typeof 1);
p("t4", typeof "s");
p("t5", typeof true);
p("t6", typeof {});
p("t7", typeof []);
p("t8", typeof function () {});
p("t9", typeof notDefinedAnywhere);

// equality
p("e1", 1 == "1");
p("e2", 1 === "1");
p("e3", null == undefined);
p("e4", null === undefined);
p("e5", NaN == NaN);
p("e6", 0 == "");
p("e7", 0 == false);
p("e8", [] == false);
p("e9", [1] == 1);
p("e10", "0" == false);
p("e11", null == 0);
p("e12", ({}) == "[object Object]");

// ToPrimitive / valueOf / toString
var custom = {
    valueOf: function () { return 42; },
    toString: function () { return "custom"; }
};
p("tp1", custom + 1);
p("tp2", "" + custom);
p("tp3", String(custom));
p("tp4", custom * 2);

var strOnly = { toString: function () { return "5"; } };
p("tp5", strOnly * 2);
p("tp6", strOnly + 1);

// ToPrimitive that allocates + triggers GC
var allocy = {
    valueOf: function () {
        var junk = [];
        for (var i = 0; i < 200; i++) junk.push("alloc" + i);
        return junk.length;
    }
};
var tpsum = 0;
for (var i = 0; i < 300; i++) tpsum += allocy + 0;
p("tpAlloc", tpsum);

// instanceof / constructor
function Animal() {}
function Dog() {}
Dog.prototype = Object.create(Animal.prototype);
var d = new Dog();
p("i1", d instanceof Dog);
p("i2", d instanceof Animal);
p("i3", d instanceof Object);
p("i4", [] instanceof Array);
p("i5", Object.getPrototypeOf(d) === Dog.prototype);

// in operator with prototype chain under pressure
Animal.prototype.inherited = 1;
var inCount = 0;
for (var i = 0; i < 400; i++) {
    var o = new Dog();
    o["own" + i] = i;
    if (("inherited" in o) && ("own" + i in o) && !o.hasOwnProperty("inherited")) inCount++;
    var junk = [];
    for (var j = 0; j < 10; j++) junk.push("x" + i + j);
}
p("inCount", inCount);

// for-in enumeration
var fi = { a: 1, b: 2, c: 3 };
var keys = [];
for (var k in fi) keys.push(k);
p("forin", keys.join(","));

var fiProto = Object.create({ pinherit: 1 });
fiProto.own = 2;
var pkeys = [];
for (var k in fiProto) pkeys.push(k);
p("forinProto", pkeys.sort().join(","));

// getters/setters
var gs = {
    _v: 0,
    get v() { return this._v * 10; },
    set v(x) { this._v = x + 1; }
};
gs.v = 5;
p("gs", gs.v + "/" + gs._v);

// Object statics
p("os1", Object.keys({ a: 1, b: 2 }).join(","));
p("os3", Object.getPrototypeOf([]) === Array.prototype);
p("os4", Object.keys(Object.create({ inherited: 1 })).length);

// error objects and stack (catch bindings cannot be reused in mquickjs)
function thrower() { throw new TypeError("boom"); }
try { thrower(); } catch (e1) {
    p("err1", e1 instanceof TypeError);
    p("err2", e1 instanceof Error);
    p("err3", e1.message);
    p("err4", e1.name);
    p("err5", String(e1));
}

// errors under GC pressure (backtrace allocation)
var ecount = 0;
for (var i = 0; i < 500; i++) {
    try {
        var junk = [];
        for (var j = 0; j < 15; j++) junk.push("e" + i + j);
        null.prop;
    } catch (e2) {
        if (e2 instanceof TypeError) ecount++;
    }
}
p("errLoop", ecount);

// throwing non-errors
try { throw "raw string"; } catch (e3) { p("rawthrow", typeof e3 + ":" + e3); }
try { throw 42; } catch (e4) { p("numthrow", typeof e4 + ":" + e4); }

print("DONE 09_objects.js");
