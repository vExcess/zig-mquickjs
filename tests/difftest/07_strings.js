// String builtins under GC pressure
function p(label, v) { print(label + "=" + v); }

var s = "Hello, World! Hello, Zig!";
p("len", s.length);
p("idx1", s.indexOf("Hello"));
p("idx2", s.indexOf("Hello", 1));
p("idx3", s.indexOf("nope"));
p("last", s.lastIndexOf("Hello"));
p("slice1", s.slice(7, 12));
p("slice2", s.slice(-5));
p("slice3", s.slice(-100, 100));
p("sub1", s.substring(7, 12));
p("sub2", s.substring(12, 7));
p("char1", s.charAt(0));
p("char2", s.charAt(1000));
p("cc1", s.charCodeAt(0));
p("cc2", s.charCodeAt(1000));
p("upper", s.toUpperCase());
p("lower", s.toLowerCase());
p("trim", "   pad   ".trim() + "|");
p("concat", "a".concat("b", "c", 1, null));
p("rep", "ab".repeat(3));
p("rep0", "ab".repeat(0) + "|");
p("fromCC", String.fromCharCode(72, 101, 108, 108, 111));

// unicode
var u = "caf\u00e9 \u4e2d\u6587 \ud83d\ude00";
p("ulen", u.length);
p("ucc", u.charCodeAt(3));
p("uslice", u.slice(0, 4));
p("uupper", u.toUpperCase());
p("ujson", JSON.stringify(u));

// string building under pressure (rope/concat + GC)
var parts = [];
for (var i = 0; i < 2000; i++) parts.push("seg" + i);
var joined = parts.join("-");
p("joinedLen", joined.length);
p("joinedHead", joined.slice(0, 30));
p("joinedTail", joined.slice(-30));

var built = "";
for (var i = 0; i < 1500; i++) built += (i % 10);
p("builtLen", built.length);
p("builtHead", built.slice(0, 20));

// comparison / interning of built strings
var a = "";
for (var i = 0; i < 5; i++) a += "x";
p("eq", a === "xxxxx");
var objk = {};
objk[a] = 1;
p("keyEq", objk["xxxxx"]);

// many substrings then read back
var big = "0123456789".repeat(200);
var acc = 0;
for (var i = 0; i < 1000; i++) {
    var sub = big.substring(i, i + 10);
    acc += sub.charCodeAt(0);
    var junk = [];
    for (var j = 0; j < 10; j++) junk.push("j" + i + j);
}
p("subAcc", acc);

// localeCompare / relational
p("cmp1", "a" < "b");
p("cmp2", "abc" < "abd");
p("cmp3", "Z" < "a");
p("cmp4", "10" < "9");

// String coercion
p("co1", "" + [1, 2, 3]);
p("co2", "" + {});
p("co3", "" + null);
p("co4", "" + undefined);
p("co5", "" + true);
p("co6", "" + [[1], [2]]);
p("co7", "" + [null, undefined, 1]);
p("co8", String(-0));
p("co9", (1.0).toString());

print("DONE 07_strings.js");
