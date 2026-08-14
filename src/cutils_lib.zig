//
// C utilities (shared implementation)
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

// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess

const std = @import("std");
const mem = std.mem;

pub const BOOL = c_int;
pub const FALSE = 0;
pub const TRUE = 1;

pub const UTF8_CHAR_LEN_MAX = 4;

fn cString(ptr: [*c]const u8) [*:0]const u8 {
    std.debug.assert(ptr != null);
    return @ptrCast(ptr);
}

fn cStringSlice(ptr: [*c]const u8) [:0]const u8 {
    return mem.span(cString(ptr));
}

fn plenPtr(plen: [*c]usize) *usize {
    std.debug.assert(plen != null);
    return @ptrCast(plen);
}

fn boolToCInt(v: bool) c_int {
    return @intFromBool(v);
}

pub fn min_int(a: c_int, b: c_int) c_int {
    return @min(a, b);
}

pub fn strlen(buf: [*c]const u8) usize {
    return mem.len(cString(buf));
}

pub fn pstrcpy(buf: [*c]u8, buf_size: c_int, str: [*c]const u8) void {
    if (buf_size <= 0) return;

    std.debug.assert(buf != null);
    std.debug.assert(str != null);

    const dst = buf[0..@intCast(buf_size)];
    const src = cStringSlice(str);
    const copy_len = @min(src.len, dst.len - 1);

    if (copy_len > 0) {
        @memcpy(dst[0..copy_len], src[0..copy_len]);
    }
    dst[copy_len] = 0;
}

pub fn pstrcat(buf: [*c]u8, buf_size: c_int, s: [*c]const u8) [*c]u8 {
    const len = strlen(buf);
    const capacity = @as(usize, @intCast(buf_size));
    if (len < capacity) {
        pstrcpy(buf + len, @intCast(capacity - len), s);
    }
    return buf;
}

pub fn strstart(str: [*c]const u8, val: [*c]const u8, ptr: ?*[*c]const u8) c_int {
    std.debug.assert(str != null);
    std.debug.assert(val != null);

    const haystack = cStringSlice(str);
    const prefix = cStringSlice(val);
    if (!mem.startsWith(u8, haystack, prefix)) return FALSE;

    if (ptr) |out| {
        out.* = str + prefix.len;
    }
    return TRUE;
}

pub fn has_suffix(str: [*c]const u8, suffix: [*c]const u8) c_int {
    std.debug.assert(str != null);
    std.debug.assert(suffix != null);
    return boolToCInt(mem.endsWith(u8, cStringSlice(str), cStringSlice(suffix)));
}

fn encodeUnicodeToUtf8(buf: []u8, cp: u32) usize {
    var q: usize = 0;

    if (cp < 0x800) {
        buf[q] = @intCast((cp >> 6) | 0xc0);
        q += 1;
    } else {
        if (cp < 0x10000) {
            buf[q] = @intCast((cp >> 12) | 0xe0);
            q += 1;
        } else {
            if (cp < 0x00200000) {
                buf[q] = @intCast((cp >> 18) | 0xf0);
                q += 1;
            } else {
                return 0;
            }
            buf[q] = @intCast(((cp >> 12) & 0x3f) | 0x80);
            q += 1;
        }
        buf[q] = @intCast(((cp >> 6) & 0x3f) | 0x80);
        q += 1;
    }
    buf[q] = @intCast((cp & 0x3f) | 0x80);
    q += 1;

    return q;
}

pub fn unicode_to_utf8_impl(buf: [*c]u8, c: c_uint) usize {
    std.debug.assert(buf != null);
    return encodeUnicodeToUtf8(@as([*]u8, @ptrCast(buf))[0..UTF8_CHAR_LEN_MAX], @intCast(c));
}

pub inline fn unicode_to_utf8(buf: [*c]u8, c: u32) usize {
    if (c < 0x80) {
        buf[0] = @intCast(c);
        return 1;
    }
    return unicode_to_utf8_impl(buf, c);
}

fn decodeUnicodeFromUtf8(p: []const u8, plen: *usize) c_int {
    std.debug.assert(p.len != 0);

    var len: usize = 1;
    var cp: u32 = p[0];

    if (cp < 0xc0) {
        plen.* = len;
        return -1;
    } else if (cp < 0xe0) {
        if (p.len < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        cp = ((@as(u32, p[0]) & 0x1f) << 6) | (@as(u32, p[1]) & 0x3f);
        len = 2;
        if (cp < 0x80) {
            plen.* = len;
            return -1;
        }
    } else if (cp < 0xf0) {
        if (p.len < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        if (p.len < 3 or (p[2] & 0xc0) != 0x80) {
            len = 2;
            plen.* = len;
            return -1;
        }
        cp = ((@as(u32, p[0]) & 0x0f) << 12) | ((@as(u32, p[1]) & 0x3f) << 6) | (@as(u32, p[2]) & 0x3f);
        len = 3;
        if (cp < 0x800) {
            plen.* = len;
            return -1;
        }
    } else if (cp < 0xf8) {
        if (p.len < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        if (p.len < 3 or (p[2] & 0xc0) != 0x80) {
            len = 2;
            plen.* = len;
            return -1;
        }
        if (p.len < 4 or (p[3] & 0xc0) != 0x80) {
            len = 3;
            plen.* = len;
            return -1;
        }

        cp = ((@as(u32, p[0]) & 0x07) << 18) | ((@as(u32, p[1]) & 0x3f) << 12) | ((@as(u32, p[2]) & 0x3f) << 6) | (@as(u32, p[3]) & 0x3f);
        len = 4;

        if (cp < 0x10000 or cp > 0x10ffff) {
            @branchHint(.unlikely);
            plen.* = len;
            return -1;
        }
    } else {
        plen.* = len;
        return -1;
    }

    plen.* = len;
    return @bitCast(cp);
}

pub fn unicode_from_utf8(p: [*c]const u8, max_len: usize, plen: [*c]usize) c_int {
    std.debug.assert(p != null);
    std.debug.assert(max_len != 0);
    return decodeUnicodeFromUtf8(p[0..max_len], plenPtr(plen));
}

fn decodeUtf8Codepoint(p: [*]const u8, plen: *usize) c_int {
    var len: usize = undefined;
    var cp: u32 = p[0];

    if (cp < 0xc0) {
        len = 1;
    } else if (cp < 0xe0) {
        cp = ((@as(u32, p[0]) & 0x1f) << 6) | (@as(u32, p[1]) & 0x3f);
        len = 2;
    } else if (cp < 0xf0) {
        cp = ((@as(u32, p[0]) & 0x0f) << 12) | ((@as(u32, p[1]) & 0x3f) << 6) | (@as(u32, p[2]) & 0x3f);
        len = 3;
    } else if (cp < 0xf8) {
        cp = ((@as(u32, p[0]) & 0x07) << 18) | ((@as(u32, p[1]) & 0x3f) << 12) | ((@as(u32, p[2]) & 0x3f) << 6) | (@as(u32, p[3]) & 0x3f);
        len = 4;
    } else {
        len = 1;
    }

    plen.* = len;
    return @bitCast(cp);
}

pub fn utf8_get_impl(p: [*c]const u8, plen: [*c]usize) c_int {
    std.debug.assert(p != null);
    return decodeUtf8Codepoint(@ptrCast(p), plenPtr(plen));
}

pub inline fn utf8_get(buf: [*c]const u8, plen: [*c]usize) i32 {
    if (buf[0] < 0x80) {
        @branchHint(.likely);
        plen.* = 1;
        return @intCast(buf[0]);
    }
    return utf8_get_impl(buf, plen);
}
