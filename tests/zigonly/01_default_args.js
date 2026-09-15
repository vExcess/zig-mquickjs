// Zig-only default parameters (C SyntaxError: expecting ',').
// Locks in debug-notes.md fix 21: js_skip_assign_expr stops at ',' at
// depth 0, so later parameters are still add_var'd. Nested ',' inside
// () / [] / {} must not terminate the skip (js_skip_parens).
// Do not change js_skip_expr — that is the for-loop third-expr skip.

function both(a = 1, b = 2) {
    return a + b;
}
print("both()=" + both());
print("both(10)=" + both(10));
print("both(10,20)=" + both(10, 20));

function second(a, b = 2) {
    return a + "," + b;
}
print("second(1)=" + second(1));
print("second(1,9)=" + second(1, 9));

function dep(a = 1, b = a + 1) {
    return a + "," + b;
}
print("dep()=" + dep());
print("dep(5)=" + dep(5));
print("dep(5,0)=" + dep(5, 0));

function comma(a = (1, 2)) {
    return a;
}
print("comma()=" + comma());

function arr(a = [1, 2]) {
    return a[0] + "," + a[1];
}
print("arr()=" + arr());

function obj(a = {x: 1}) {
    return a.x;
}
print("obj()=" + obj());

function mx(a = Math.max(1, 2)) {
    return a;
}
print("mx()=" + mx());

function und(a = 1) {
    return a;
}
print("und()=" + und());
print("und(undefined)=" + und(undefined));
print("und(null)=" + und(null));
print("und(0)=" + und(0));

// Nested commas in every bracket kind, plus a later parameter. If skip
// ate past ',' at depth 0 incorrectly, `d` would not exist.
function nest(a = [1, 2], b = {x: 1, y: 2}, c = Math.max(1, 2), d = (1, 2)) {
    return a[1] + "," + b.y + "," + c + "," + d;
}
print("nest()=" + nest());
print("nest(undefined,undefined,undefined,9)=" + nest(undefined, undefined, undefined, 9));

print("DONE 01_default_args.js");
