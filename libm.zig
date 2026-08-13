//
// Tiny Math Library (C ABI exports)
//
// Copyright (c) 2024 Fabrice Bellard
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

// Ported from C to Zig by VExcess

const lib = @import("libm_lib.zig");

export fn js_scalbn(x: f64, n: c_int) f64 {
    return lib.js_scalbn(x, n);
}

export fn js_floor(x: f64) f64 {
    return lib.js_floor(x);
}

export fn js_ceil(x: f64) f64 {
    return lib.js_ceil(x);
}

export fn js_trunc(x: f64) f64 {
    return lib.js_trunc(x);
}

export fn js_round_inf(a: f64) f64 {
    return lib.js_round_inf(a);
}

export fn js_fabs(x: f64) f64 {
    return lib.js_fabs(x);
}

export fn js_sqrt(x: f64) f64 {
    return lib.js_sqrt(x);
}

export fn js_lrint(a: f64) i32 {
    return lib.js_lrint(a);
}

export fn js_fmod(x: f64, y: f64) f64 {
    return lib.js_fmod(x, y);
}

export fn js_sin(x: f64) f64 {
    return lib.js_sin(x);
}

export fn js_cos(x: f64) f64 {
    return lib.js_cos(x);
}

export fn js_tan(x: f64) f64 {
    return lib.js_tan(x);
}

export fn js_acos(x: f64) f64 {
    return lib.js_acos(x);
}

export fn js_asin(x: f64) f64 {
    return lib.js_asin(x);
}

export fn js_atan(x: f64) f64 {
    return lib.js_atan(x);
}

export fn js_atan2(y: f64, x: f64) f64 {
    return lib.js_atan2(y, x);
}

export fn js_exp(x: f64) f64 {
    return lib.js_exp(x);
}

export fn js_log(x: f64) f64 {
    return lib.js_log(x);
}

export fn js_log2(x: f64) f64 {
    return lib.js_log2(x);
}

export fn js_log10(x: f64) f64 {
    return lib.js_log10(x);
}

export fn js_pow(x: f64, y: f64) f64 {
    return lib.js_pow(x, y);
}

export fn js_rem_pio2(x: f64, y: [*]f64) c_int {
    return lib.js_rem_pio2(x, y);
}
