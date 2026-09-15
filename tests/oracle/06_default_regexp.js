// Zig-only default-arg re-lex. js_parse_get_pos infers regexp_allowed from
// the current token, so a default (or body-after-default) that starts with
// `/` was re-lexed as division (SyntaxError). After `=` / `{`, `/` is a regexp.

function fail(msg) { print("FAIL " + msg); }

function f(a = /x/g) {
    gc();
    return a.source + ":" + a.flags;
}
if (f() !== "x:g") fail("f()=" + f());
else print("ok re default");
var passed = /y/i;
if (f(passed) !== "y:i") fail("f(re)=" + f(passed));
else print("ok re passed");

function g(a = 1) {
    /z/;
    gc();
    return a;
}
if (g() !== 1) fail("g body re=" + g());
else print("ok body re");

var o = {
    m: function (a = /ab+c/) {
        gc();
        return a.test("abbbc");
    }
};
if (o.m() !== true) fail("method re=" + o.m());
else print("ok method re");

var F = Function("a = /q+/", "return a.source");
if (F() !== "q+") fail("Function re=" + F());
else print("ok Function re");

function mix(a = /a/, b = 2, c = /c/i) {
    return a.source + b + c.flags;
}
if (mix() !== "a2i") fail("mix=" + mix());
else print("ok mix");

print("DONE 06_default_regexp.js");
