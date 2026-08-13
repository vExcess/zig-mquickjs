//
// Tiny float64 printing and parsing library (C ABI exports)
//
// Copyright (c) 2024-2025 Fabrice Bellard
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

// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess

const lib = @import("dtoa_lib.zig");

export fn js_dtoa_max_len(d: f64, radix: c_int, n_digits: c_int, flags: c_int) c_int {
    return lib.js_dtoa_max_len(d, radix, n_digits, flags);
}

export fn js_dtoa(
    buf: [*c]u8,
    d: f64,
    radix: c_int,
    n_digits: c_int,
    flags: c_int,
    tmp_mem: *lib.JSDTOATempMem,
) c_int {
    return lib.js_dtoa(buf, d, radix, n_digits, flags, tmp_mem);
}

export fn js_atod(
    str: [*c]const u8,
    pnext: ?*[*c]const u8,
    radix: c_int,
    flags: c_int,
    tmp_mem: *lib.JSATODTempMem,
) f64 {
    return lib.js_atod(str, pnext, radix, flags, tmp_mem);
}

export fn u32toa(buf: [*c]u8, n: c_uint) usize {
    return lib.u32toa(buf, n);
}

export fn i32toa(buf: [*c]u8, n: c_int) usize {
    return lib.i32toa(buf, n);
}

export fn u64toa(buf: [*c]u8, n: c_ulonglong) usize {
    return lib.u64toa(buf, @intCast(n));
}

export fn i64toa(buf: [*c]u8, n: c_longlong) usize {
    return lib.i64toa(buf, @intCast(n));
}

export fn u64toa_radix(buf: [*c]u8, n: c_ulonglong, radix: c_uint) usize {
    return lib.u64toa_radix(buf, @intCast(n), radix);
}

export fn i64toa_radix(buf: [*c]u8, n: c_longlong, radix: c_uint) usize {
    return lib.i64toa_radix(buf, @intCast(n), radix);
}
