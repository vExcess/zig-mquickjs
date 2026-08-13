//
// C utilities (C ABI exports)
//
// Copyright (c) 2017 Fabrice Bellard
// Copyright (c) 2018 Charlie Gordon
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

const lib = @import("cutils_lib.zig");

export fn pstrcpy(buf: [*c]u8, buf_size: c_int, str: [*c]const u8) void {
    lib.pstrcpy(buf, buf_size, str);
}

export fn pstrcat(buf: [*c]u8, buf_size: c_int, s: [*c]const u8) [*c]u8 {
    return lib.pstrcat(buf, buf_size, s);
}

export fn strstart(str: [*c]const u8, val: [*c]const u8, ptr: ?*[*c]const u8) c_int {
    return lib.strstart(str, val, ptr);
}

export fn has_suffix(str: [*c]const u8, suffix: [*c]const u8) c_int {
    return lib.has_suffix(str, suffix);
}

export fn __unicode_to_utf8(buf: [*c]u8, c: c_uint) usize {
    return lib.unicode_to_utf8_impl(buf, c);
}

export fn __unicode_from_utf8(p: [*c]const u8, max_len: usize, plen: [*c]usize) c_int {
    return lib.unicode_from_utf8(p, max_len, plen);
}

export fn __utf8_get(p: [*c]const u8, plen: [*c]usize) c_int {
    return lib.utf8_get_impl(p, plen);
}
