// Default-arg evaluation must see `arguments` and the inner function name.
// Those locals used to be bound *after* default emission, so
// `function f(a = arguments.length) { return arguments; }` threw
// TypeError (undefined.length) and `function foo(a = foo) { return foo; }`
// was a ReferenceError.

function fail(msg) { print("FAIL " + msg); }

function f(a = arguments.length) {
    gc();
    return a + ":" + arguments.length;
}
if (f() !== "0:0") fail("f()=" + f());
else print("ok args none");
if (f(1, 2) !== "1:2") fail("f(1,2)=" + f(1, 2));
else print("ok args two");
if (f(undefined) !== "1:1") fail("f(undefined)=" + f(undefined));
else print("ok args undef");

function g(a = 0, b = arguments.length) {
    return a + ":" + b;
}
if (g() !== "0:0") fail("g()=" + g());
else print("ok args index");
if (g(5) !== "5:1") fail("g(5)=" + g(5));
else print("ok args index one");

var nf = function foo(a = foo) {
    gc();
    return a === foo;
};
if (nf() !== true) fail("named=" + nf());
else print("ok named expr");

var nf2 = function baz(a = baz) {
    gc();
    return typeof a;
};
if (nf2() !== "function") fail("named-only=" + nf2());
else print("ok named default only");

function bar(a = bar) {
    return typeof a;
}
if (bar() !== "function") fail("decl=" + bar());
else print("ok decl default");

var om = { m: function m(a = m) { return typeof a; } };
if (om.m() !== "function") fail("method=" + om.m());
else print("ok method name");

var os = eval("({ m(a = m) { return typeof a; } })");
if (os.m() !== "function") fail("shorthand=" + os.m());
else print("ok shorthand name");

if (eval("(function qux(a = qux) { return typeof a; })()") !== "function")
    fail("eval named");
else print("ok eval named");

function outer() {
    function inner(a = arguments[0]) {
        return a + ":" + arguments.length;
    }
    return inner() + "/" + inner(3);
}
if (outer(8) !== "undefined:0/3:1") fail("nested=" + outer(8));
else print("ok nested");

print("DONE 07_default_scope.js");
