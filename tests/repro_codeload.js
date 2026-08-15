function BenchmarkSuite() {}
function Benchmark() {}
load("tests/octane/code-load.js");
setupCodeLoad();
salt = 1501;
try {
    runClosure();
    print("isolated 1501 ok");
} catch (e) {
    print("isolated 1501 FAIL", e);
}

setupCodeLoad();
var n;
for (n = 0; n < 1501; n++) {
    salt = 0;
    runClosure();
}
print("1501 times salt0 ok");
salt = 1501;
try {
    runClosure();
    print("1501 after repeats ok");
} catch (e2) {
    print("1501 after repeats FAIL", e2);
}
