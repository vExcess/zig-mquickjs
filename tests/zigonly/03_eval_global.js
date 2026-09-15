// Documented deviation: direct eval always runs in global scope (README).
// Indirect eval is C-comparable and lives in tests/difftest/04_parser.js.
// Assert the documented Zig behaviour; do not "fix" it to match C.

var g = 10;

function read_global() {
    var g = 20;
    return eval("g");
}
print("read_global=" + read_global());

function write_global() {
    var g = 20;
    eval("g = 30");
    return g;
}
print("write_global_local=" + write_global());
print("write_global_g=" + g);

function leak_var() {
    eval("var leaked = 99");
}
leak_var();
print("leaked=" + leaked);

function no_local() {
    var local = 42;
    return eval("typeof local");
}
print("no_local=" + no_local());

print("eval_val=" + eval("1 + 2"));

eval("function from_eval() { return 8; }");
print("from_eval=" + from_eval());

print("DONE 03_eval_global.js");
