// Host print() of C functions and constructors. Wrong JSCFunctionDef
// stride (debug-notes.md fix 16) made Math.sin print as concat() and
// print(Date) SEGV. Do not print Date/Number/String/Boolean *instances*
// here: dump_object has a separate missing-default case vs C.
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
print("DONE 21_print_cfunc.js");
