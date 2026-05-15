//
// C utilities
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

const std = @import("std");
const mem = std.mem;

pub const BOOL = c_int;
pub const FALSE = 0;
pub const TRUE = 1;

pub fn min_int(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

pub const UTF8_CHAR_LEN_MAX = 4;

pub fn strlen(buf: [*c]const u8) usize {
    return std.mem.len(@as([*:0]const u8, buf));
}

export fn pstrcpy(_buf: [*c]u8, _bufSize: c_int, _str: [*c]const u8) void {
    // cint can be negative, but buffer length cannot be negative
    if (_bufSize <= 0) return;

    std.debug.assert(_buf != null);
    std.debug.assert(_str != null);

    const bufSize: usize = @intCast(_bufSize);
    const dst = _buf[0..bufSize];
    const srcStr: [*:0]const u8 = @ptrCast(_str);

    var i: usize = 0;
    // Reserve space for null terminator
    const max_write = bufSize - 1;

    // use loop instead of mem copy for performance
    while (i < max_write) {
        const c = srcStr[i];
        if (c == 0) break;
        dst[i] = c;
        i += 1;
    }

    dst[i] = '\x00';
}

// strcat and truncate
export fn pstrcat(buf: [*c]u8, bufSize: c_int, s: [*c]const u8) [*c]u8 {
    const len = strlen(buf);
    if (len < bufSize) {
        pstrcpy(buf + len, bufSize - @as(c_int, @intCast(len)), s);

        // equivelant for when ported from C to Zig typing
        // pstrcpy(buf[len..], bufSize - len, s);
    }
    return buf;
}

export fn strstart(_str: [*c]const u8, _val: [*c]const u8, ptr: ?*[*c]const u8) c_int {
    std.debug.assert(_str != null);
    std.debug.assert(_val != null);
    
    const str: [*:0]const u8 = @ptrCast(_str);
    const val: [*:0]const u8 = @ptrCast(_val);

    var i: usize = 0;
    while (val[i] != '\x00') : (i += 1) {
        if (str[i] != val[i]) return 0;
    }

    if (ptr) |out_ptr| {
        out_ptr.* = str + i;
    }

    return 1;
}

export fn has_suffix(_str: [*c]const u8, _suffix: [*c]const u8) c_int {
    std.debug.assert(_str != null);
    std.debug.assert(_suffix != null);

    const len = strlen(_str);
    const slen = strlen(_suffix);

    const str = _str[0..len];
    const suffix = _suffix[0..slen];
    
    if (len >= slen) {
        const endOfStr = str[(len - slen)..];

        // remove ! because Zig's mem.eql returns true when equal, while C's memcmp return false when equal
        if (mem.eql(u8, endOfStr, suffix)) {
            return 1;
        }
    }
    return 0;
}

pub export fn __unicode_to_utf8(_buf: [*c]u8, _c: c_uint) usize {
    const buf: [*]u8 = @ptrCast(_buf);
    const c: u32 = @intCast(_c);

    var q: usize = 0;

    if (c < 0x800) {
        buf[q] = @intCast((c >> 6) | 0xc0);
        q += 1;
    } else {
        if (c < 0x10000) {
            buf[q] = @intCast((c >> 12) | 0xe0);
            q += 1;
        } else {
            if (c < 0x00200000) {
                buf[q] = @intCast((c >> 18) | 0xf0);
                q += 1;
            } else {
                return 0;
            }
            buf[q] = @intCast(((c >> 12) & 0x3f) | 0x80);
            q += 1;
        }
        buf[q] = @intCast(((c >> 6) & 0x3f) | 0x80);
        q += 1;
    }
    buf[q] = @intCast((c & 0x3f) | 0x80);
    q += 1;
    
    return q;
}

// Note: at most 21 bits are encoded. At most UTF8_CHAR_LEN_MAX bytes
// are output.
pub inline fn unicode_to_utf8(buf: [*c]u8, c: u32) usize {
    if (c < 0x80) {
        buf[0] = @as(u8, @intCast(c));
        return 1;
    } else {
        return __unicode_to_utf8(buf, c);
    }
}

export fn __unicode_from_utf8(_p: [*c]const u8, maxLen: usize, _plen: [*c]usize) c_int {
    std.debug.assert(_p != null);
    std.debug.assert(_plen != null);
    std.debug.assert(maxLen != 0);

    const p = _p[0..maxLen];
    const plen: *usize = @ptrCast(_plen);

    var len: usize = 1;
    var c: u32 = p[0];

    if (c < 0xc0) {
        plen.* = len;
        return -1;
    } else if (c < 0xe0) {
        if (maxLen < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        c = ((@as(u32, p[0]) & 0x1f) << 6) | (@as(u32, p[1]) & 0x3f);
        len = 2;
        if (c < 0x80) {
            plen.* = len;
            return -1;
        }
    } else if (c < 0xf0) {
        if (maxLen < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        if (maxLen < 3 or (p[2] & 0xc0) != 0x80) {
            len = 2;
            plen.* = len;
            return -1;
        }
        c = ((@as(u32, p[0]) & 0x0f) << 12) | ((@as(u32, p[1]) & 0x3f) << 6) | (@as(u32, p[2]) & 0x3f);
        len = 3;
        if (c < 0x800) {
            plen.* = len;
            return -1;
        }
    } else if (c < 0xf8) {
        if (maxLen < 2 or (p[1] & 0xc0) != 0x80) { plen.* = len; return -1; }
        if (maxLen < 3 or (p[2] & 0xc0) != 0x80) { len = 2; plen.* = len; return -1; }
        if (maxLen < 4 or (p[3] & 0xc0) != 0x80) { len = 3; plen.* = len; return -1; }
        
        c = ((@as(u32, p[0]) & 0x07) << 18) | ((@as(u32, p[1]) & 0x3f) << 12) | ((@as(u32, p[2]) & 0x3f) << 6) | (@as(u32, p[3]) & 0x3f);
        len = 4;
        
        // We explicitly accept surrogate pairs
        if (c < 0x10000 or c > 0x10ffff) {
            @branchHint(.unlikely);
            plen.* = len;
            return -1;
        }
    } else {
        plen.* = len;
        return -1;
    }
    
    plen.* = len;
    return @bitCast(c);
}

pub export fn __utf8_get(_p: [*c]const u8, _plen: [*c]usize) c_int {
    const p: [*]const u8 = @ptrCast(_p);
    const plen: *usize = @ptrCast(_plen);

    var len: usize = undefined;
    var c: u32 = p[0];

    if (c < 0xc0) {
        len = 1;
    } else if (c < 0xe0) {
        c = ((@as(u32, p[0]) & 0x1f) << 6) | (@as(u32, p[1]) & 0x3f);
        len = 2;
    } else if (c < 0xf0) {
        c = ((@as(u32, p[0]) & 0x0f) << 12) | ((@as(u32, p[1]) & 0x3f) << 6) | (@as(u32, p[2]) & 0x3f);
        len = 3;
    } else if (c < 0xf8) {
        c = ((@as(u32, p[0]) & 0x07) << 18) | ((@as(u32, p[1]) & 0x3f) << 12) | ((@as(u32, p[2]) & 0x3f) << 6) | (@as(u32, p[3]) & 0x3f);
        len = 4;
    } else {
        len = 1;
    }
    
    plen.* = len;
    return @bitCast(c);
}

// Warning: no error checking is done so the UTF-8 encoding must be
// validated before.
pub inline fn utf8_get(buf: [*c]const u8, plen: [*c]usize) i32 {
    // Zig doesn't have a direct 'likely' macro, but the optimizer 
    // is generally excellent at branch prediction for simple checks.
    if (buf[0] < 0x80) {
        @branchHint(.likely);
        plen.* = 1;
        return @intCast(buf[0]);
    } else {
        return __utf8_get(buf, plen);
    }
}
