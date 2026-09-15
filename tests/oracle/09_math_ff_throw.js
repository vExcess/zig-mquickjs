// JS_CFUNC_f_f (Math.sin/cos/…): ToNumber ToPrimitive throws must propagate.
// C mquickjs.c:5465 dead-stores JS_EXCEPTION and returns NaN. Do not match C.
// One catch binding: this engine reuses catch vars in the same scope.

function fail(msg) { print("FAIL " + msg); }

function expectThrow(name, fn, want) {
  try {
    var r = fn();
    fail(name + " swallowed r=" + r);
  } catch (e) {
    if (e !== want) fail(name + " throw=" + e);
    else print("ok " + name + " throw");
  }
}

expectThrow("sin", function() {
  return Math.sin({valueOf: function() { throw "X"; }});
}, "X");
expectThrow("sqrt", function() {
  return Math.sqrt({valueOf: function() { throw "Y"; }});
}, "Y");
expectThrow("min", function() {
  return Math.min({valueOf: function() { throw "Z"; }});
}, "Z");

print("DONE 09_math_ff_throw.js");
