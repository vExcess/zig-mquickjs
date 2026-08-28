// Host scriptArgs. Zig passed a slice-of-slices as C char**, so
// scriptArgs[1] SEGVd (debug-notes.md fix 18). Extra argv comes from
// 22_script_args.argv via run.sh. Print extras only — scriptArgs[0] is
// the script path and differs for bytecode.sh's -b cross-run.
print(scriptArgs.length - 1);
var i = 1;
while (i < scriptArgs.length) {
    print(i, scriptArgs[i]);
    i = i + 1;
}
print("DONE 22_script_args.js");
