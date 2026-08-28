// Host print() of C functions/constructors (fix 16: JSCFunctionDef stride)
// and of Date/ArrayBuffer/typed-array instances (fix 17: js_dump_object
// missing C default:). Number/String/Boolean constructors are unsupported
// in both engines — cannot probe boxed primitives. new Date(0) is epoch,
// not Date.now() — keep this deterministic.
print(Math.sin);
print(Math.cos);
print(Math.floor);
print(parseInt);
print(eval);
print(isNaN);
print(isFinite);
print(Object);
print(Array);
print(Date);
print(RegExp);
print(Function);
print(Error);
print(Number);
print(String);
print(Boolean);
print([]);
print({});
print(/abc/g);
print(new Error("e"));
print(new Date(0));
print(new ArrayBuffer(4));
print(new Uint8Array([1, 2, 255]));
print(new Uint8ClampedArray([1, 2, 255]));
print(new Int8Array([-1, 0, 127]));
print(new Int16Array([-1, 256, 32767]));
print(new Uint16Array([0, 256, 65535]));
print(new Int32Array([-1, 65536]));
print(new Uint32Array([0, 4294967295]));
print(new Float32Array([0, 1.5, -2]));
print(new Float64Array([0, 1.5, -2]));
var buf = new ArrayBuffer(16);
var u16 = new Uint16Array(buf, 4, 3);
u16[0] = 0x1111;
u16[1] = 0x2222;
u16[2] = 0x3333;
print(u16);
print(new Uint8Array(buf));
var d = new Date(0);
d.foo = 1;
print(d);
print("DONE 21_print_cfunc.js");
