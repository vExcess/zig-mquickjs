// Function.prototype.call with no thisArg. C does argc = max_int(argc, 1)
// so fn.call() uses this=undefined. Zig omitted that clamp and threw `?`.
function id() { return typeof this; }
print("call0=" + id.call());
print("callU=" + id.call(undefined));
print("callN=" + id.call(null));
print("callObj=" + id.call({ tag: "x" }));

function add(a, b) { return (this && this.n ? this.n : 0) + (a | 0) + (b | 0); }
print("callArgs=" + add.call({ n: 10 }, 1, 2));
print("callNoThis=" + add.call());

function retThis() { return this; }
print("callRetUndef=" + (retThis.call() === undefined));

print("DONE 25_function_call.js");
