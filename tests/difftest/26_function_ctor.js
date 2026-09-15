// Function() ToString of a param must not continue into the body.
// C goto done on concat failure (mquickjs.c:13029); Zig used to break
// the param loop then still ToString argv[n].
try {
  Function({toString: function() { throw "A"; }}, {toString: function() { throw "B"; }});
  print("no throw");
} catch (e) {
  print("throw=" + e);
}
print("DONE 26_function_ctor.js");
