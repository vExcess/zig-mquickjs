// Array literal: C goto done on missing comma (mquickjs.c:9506).
// Zig was parsing `[1 2]` as `[1, 2]`.
function tryparse(name, src) {
  try {
    var f = Function("return " + src);
    print(name + "=" + f());
  } catch (e) {
    print(name + "=" + e);
  }
}
tryparse("a", "[1 2]");
tryparse("b", "[1,]");
tryparse("c", "[1, 2]");
tryparse("d", "[1 2, 3]");
print("DONE 28_array_comma.js");
