// Systematic regexp engine differential: patterns x subjects x flags.
function show(m) {
    if (m === null) return "null";
    var parts = [m.index];
    for (var i = 0; i < m.length; i++) parts.push(m[i] === undefined ? "u" : JSON.stringify(m[i]));
    return parts.join(",");
}

var PATTERNS = [
    "a", "abc", "a*", "a+", "a?", "a{2}", "a{2,}", "a{2,4}",
    "a*?", "a+?", "a??", "a{2,4}?",
    ".", ".*", ".+", "^a", "a$", "^$", "^a$",
    "[abc]", "[^abc]", "[a-z]", "[^a-z]", "[a-zA-Z0-9_]", "[]]", "[-a]", "[a-]",
    "\\d", "\\D", "\\w", "\\W", "\\s", "\\S", "\\b", "\\B",
    "(a)", "(a)(b)", "(a(b))", "(?:a)", "(a)?", "(a)*", "(a)+",
    "a|b", "ab|cd", "(a|b)+", "^(a|b)*$",
    "(?=a)", "(?!a)", "a(?=b)", "a(?!b)",
    "\\.", "\\\\", "\\/", "\\n", "\\t", "\\0",
    "\\x41", "\\u0041", "\\u{41}",
    "(a)\\1", "(a+)\\1", "(\\w)\\1",
    "a.*b", "a.*?b", "[\\d\\s]+", "(\\d+)-(\\d+)",
    "^(?:(\\d+)|(\\w+))$", "((((a))))", "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)",
    "\\B\\w+\\B", "(?:ab)+", "(?:ab)*c", "[^]", "[\\s\\S]",
    "x(?=y(?=z))", "a{0}", "(){0}", "(|a)", "(a||b)"
];

var SUBJECTS = [
    "", "a", "aa", "aaa", "b", "ab", "abc", "abcabc", "xyz",
    "a1b2c3", "  spaced  ", "\n", "a\nb", "AAA", "aA",
    "123-456", "the quick brown fox", "\u4e2d\u6587", "\ud83d\ude00",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "abababababab", "\\", ".", "]", "-",
    "\u0000", "A", "_", "a-b", "z"
];

var FLAGS = ["", "g", "i", "m", "s"];

var out = [];
for (var pi = 0; pi < PATTERNS.length; pi++) {
    for (var fi = 0; fi < FLAGS.length; fi++) {
        var re;
        try {
            re = new RegExp(PATTERNS[pi], FLAGS[fi]);
        } catch (e1) {
            out.push("p" + pi + "f" + fi + ":CTOR_THROW");
            continue;
        }
        for (var si = 0; si < SUBJECTS.length; si++) {
            var subj = SUBJECTS[si];
            var tag = "p" + pi + "f" + fi + "s" + si;
            try {
                re.lastIndex = 0;
                var m = re.exec(subj);
                var t = re.test(subj);
                re.lastIndex = 0;
                var rep = subj.replace(re, "<$&>");
                var spl = subj.split(re).length;
                var mt = subj.match(re);
                var sr = subj.search(re);
                out.push(tag + "|" + show(m) + "|" + t + "|" + JSON.stringify(rep) +
                         "|" + spl + "|" + (mt === null ? "null" : mt.length) + "|" + sr);
            } catch (e2) {
                out.push(tag + "|THROW:" + (e2 && e2.name ? e2.name : "?"));
            }
        }
    }
}
// hash to keep output manageable but sensitive to any change
var h1 = 0, h2 = 0;
for (var i = 0; i < out.length; i++) {
    var s = out[i];
    for (var j = 0; j < s.length; j++) {
        h1 = (h1 * 31 + s.charCodeAt(j)) % 2147483647;
        h2 = (h2 + h1) % 2147483647;
    }
}
print("cases=" + out.length);
print("hash1=" + h1);
print("hash2=" + h2);

// print a deterministic sample so real diffs are human-readable
for (var i = 0; i < out.length; i += 337) print("S" + i + " " + out[i]);

// global exec loops with lastIndex progression
function loopExec(pat, flags, subj) {
    var r = new RegExp(pat, flags), acc = [], m, guard = 0;
    while ((m = r.exec(subj)) !== null && guard++ < 50) {
        acc.push(m.index + ":" + m[0].length + ":" + r.lastIndex);
        if (m[0] === "" ) r.lastIndex++;
    }
    return acc.join(" ");
}
print("le1=" + loopExec("a", "g", "banana"));
print("le2=" + loopExec("a*", "g", "baaac"));
print("le3=" + loopExec("", "g", "abc"));
print("le4=" + loopExec("(?:)", "g", "ab"));
print("le5=" + loopExec("\\b", "g", "ab cd"));

// replace with function and many captures
print("rf1=" + "a1b2".replace(/(\w)(\d)/g, function (m, a, b, off, str) {
    return "[" + m + a + b + off + str.length + "]";
}));
print("rf2=" + "abc".replace(/(a)(x)?(c)?/g, function () {
    var out = [];
    for (var i = 0; i < arguments.length; i++) out.push(String(arguments[i]));
    return out.join("~");
}));

// catastrophic-ish backtracking bounded
print("bt1=" + /^(a+)+$/.test("aaaaaaaaaaaaaaaaaaaaaaaa!"));
print("bt2=" + /(a|aa)+b/.test("aaaaaaaaaaaaaaaaaaaac"));

// case-insensitive over non-ASCII
print("ci1=" + /\u00e9/i.test("\u00c9"));
print("ci2=" + /abc/i.test("ABC"));
print("ci3=" + /[a-z]/i.test("Q"));

// multiline anchors
print("ml1=" + "a\nb\nc".match(/^./gm).join(","));
print("ml2=" + "a\nb".match(/.$/gm).join(","));

// dotall
print("ds1=" + /a.b/s.test("a\nb"));
print("ds2=" + /a.b/.test("a\nb"));

// sticky progression
var sy = /\d/y;
var syOut = [];
sy.lastIndex = 0;
for (var i = 0; i < 5; i++) syOut.push(String(sy.exec("12a34")) + "@" + sy.lastIndex);
print("sy=" + syOut.join(" "));

// source/flags round trip
var rr = /a\/b[\]]/gi;
print("src=" + rr.source + " flags=" + (rr.flags || "") + " g=" + rr.global + " i=" + rr.ignoreCase);
print("tostr=" + String(/x+/g));

// regexp under GC pressure with captures retained
var keep = [];
for (var i = 0; i < 500; i++) {
    var mm = ("k" + i + "=v" + (i * 3)).match(/^k(\d+)=v(\d+)$/);
    if (mm) keep.push(mm[1] + "/" + mm[2]);
    var junk = [];
    for (var j = 0; j < 12; j++) junk.push("rg" + i + "_" + j);
}
print("gcKeep=" + keep.length + " first=" + keep[0] + " last=" + keep[keep.length - 1]);

print("DONE 17_regexp_deep.js");
