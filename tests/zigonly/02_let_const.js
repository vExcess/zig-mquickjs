// Documented deviation: let/const are aliases for var (README).
// Assert that behaviour; do not "fix" it to match C (C cannot parse these).

print("typeof_before=" + typeof hoisted);
let hoisted = 1;
print("hoisted=" + hoisted);

let redecl = 1;
let redecl = 2;
print("redecl=" + redecl);

const c = 1;
c = 2;
print("const_reassign=" + c);

{
    let leaked = 3;
}
print("block_leak=" + leaked);

var mixed = 4;
let mixed = 5;
print("mixed=" + mixed);

function f() {
    let inner = 6;
    {
        const inner = 7;
    }
    return inner;
}
print("func_scope=" + f());

var closes = [];
for (let i = 0; i < 3; i++) {
    closes.push(function () { return i; });
}
print("for_let=" + closes[0]() + "," + closes[1]() + "," + closes[2]());

print("DONE 02_let_const.js");
