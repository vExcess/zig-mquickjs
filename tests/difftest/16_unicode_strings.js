// UTF-8 storage + UTF-16 index conversion + string position cache.
function p(l, v) { print(l + "=" + v); }

// Mixed-width corpus: ASCII(1B), Latin(2B), CJK(3B), astral(4B surrogate pair)
var PIECES = ["a", "\u00e9", "\u4e2d", "\ud83d\ude00", "z", "\u00ff", "\uffff", "\ud800\udc00"];
var s = "";
for (var i = 0; i < 200; i++) s += PIECES[i % PIECES.length];
p("len", s.length);

// forward index scan
var h = 0;
for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 2147483647;
p("fwd", h);

// backward index scan (defeats a monotonic position cache)
h = 0;
for (var i = s.length - 1; i >= 0; i--) h = (h * 31 + s.charCodeAt(i)) % 2147483647;
p("bwd", h);

// random-ish jumping access (worst case for position cache)
h = 0;
var idx = 0;
for (var i = 0; i < 3000; i++) {
    idx = (idx * 1103515245 + 12345) % 2147483647;
    if (idx < 0) idx = -idx;
    var j = idx % s.length;
    h = (h * 17 + s.charCodeAt(j)) % 2147483647;
}
p("jump", h);

// codePointAt across surrogate boundaries
var cps = [];
for (var i = 0; i < 40; i++) cps.push(s.codePointAt(i));
p("cps", cps.join(","));

// charAt / slice / substring at every offset of a small mixed string
var m = "a\u00e9\u4e2d\ud83d\ude00z";
p("mlen", m.length);
var parts = [];
for (var i = 0; i <= m.length; i++) {
    for (var j = i; j <= m.length; j++) parts.push(m.slice(i, j).length);
}
p("sliceLens", parts.join(""));
var chars = [];
for (var i = 0; i < m.length; i++) chars.push(m.charCodeAt(i).toString(16));
p("mchars", chars.join(","));

// negative and out-of-range indices
p("neg1", m.slice(-3));
p("neg2", m.substring(-5, 100).length);
p("neg3", m.charAt(-1) + "|" + m.charAt(999) + "|");
p("neg4", m.charCodeAt(-1));
p("neg5", m.indexOf("\u4e2d"));
p("neg6", m.lastIndexOf("\ud83d\ude00"));

// indexOf/lastIndexOf with multibyte needles at many positions
var hay = "";
for (var i = 0; i < 120; i++) hay += (i % 3 === 0 ? "\u4e2d" : (i % 3 === 1 ? "ab" : "\ud83d\ude00"));
var found = [];
for (var i = 0; i < 30; i++) found.push(hay.indexOf("\ud83d\ude00", i * 3));
p("idxScan", found.join(","));
p("lastIdx", hay.lastIndexOf("\u4e2d"));
p("hayLen", hay.length);

// split/join round trip preserving code units
var sp = s.split("");
p("splitLen", sp.length);
p("rejoin", sp.join("") === s);
p("splitCJK", hay.split("\u4e2d").length);

// concatenation building long mixed strings under GC pressure
var acc = "";
for (var i = 0; i < 800; i++) {
    acc += PIECES[i % PIECES.length];
    if (i % 100 === 0) { var junk = []; for (var k = 0; k < 30; k++) junk.push(acc.length + "x" + k); }
}
p("accLen", acc.length);
p("accHash", (function () { var q = 0; for (var i = 0; i < acc.length; i++) q = (q * 7 + acc.charCodeAt(i)) % 1000003; return q; })());

// substring of long mixed string then index into it (cache invalidation)
var subs = [];
for (var i = 0; i < 100; i++) {
    var sub = acc.substring(i * 3, i * 3 + 12);
    subs.push(sub.length + ":" + (sub.length ? sub.charCodeAt(0) : -1) + ":" + (sub.length > 5 ? sub.charCodeAt(5) : -1));
}
p("subs", subs.join("|"));

// case conversion (ASCII only per spec) on mixed content
p("upper", "abc\u00e9\u4e2d\ud83d\ude00".toUpperCase());
p("lower", "ABC\u00c9\u4e2d".toLowerCase());

// comparison / ordering with multibyte
var arr = ["\u4e2d", "a", "\u00e9", "\ud83d\ude00", "Z", "\uffff", "b"];
p("sorted", arr.slice().sort().join(","));
p("cmp1", "\u4e2d" > "a");
p("cmp2", "\ud83d\ude00" > "\uffff");

// JSON round trip of full corpus
var js = JSON.stringify(s);
p("jsonLen", js.length);
p("jsonRT", JSON.parse(js) === s);
p("jsonLone", JSON.stringify("\ud800") + "|" + JSON.stringify("\udfff"));

// fromCharCode with surrogates
p("fcc", String.fromCharCode(0xd83d, 0xde00).length);
p("fcc2", String.fromCharCode(0xd83d, 0xde00) === "\ud83d\ude00");
p("fcc3", String.fromCharCode(65, 0x4e2d, 0xe9));

// lone surrogates survive round trips
var lone = "a\ud800b\udfffc";
p("loneLen", lone.length);
p("loneCodes", [lone.charCodeAt(0), lone.charCodeAt(1), lone.charCodeAt(2), lone.charCodeAt(3), lone.charCodeAt(4)].join(","));
p("loneSlice", lone.slice(1, 4).length);
p("loneConcat", (lone + lone).length);

// replace on multibyte with captures
p("rep1", "\u4e2dab\u4e2d".replace(/ab/, "[$&]"));
p("rep2", "\ud83d\ude00x".replace(/x/, "\u00e9"));
p("rep3", hay.replace(/\u4e2d/g, "-").length);

// regexp index positions must be UTF-16 based
var rm = /\ud83d\ude00/.exec(m);
p("reIdx", rm ? rm.index : -1);
var rm2 = /z/.exec(m);
p("reIdx2", rm2 ? rm2.index : -1);
var rm3 = /(\u4e2d)(\ud83d\ude00)/.exec(m);
p("reIdx3", rm3 ? rm3.index + ":" + rm3[1].length + ":" + rm3[2].length : -1);

// repeat + trim with multibyte whitespace
p("rep4", "\u4e2d".repeat(5).length);
p("trim1", "|" + "  \u4e2d  ".trim() + "|");
p("trim2", "|" + "\t\n\r \u4e2d".trim() + "|");

print("DONE 16_unicode_strings.js");
