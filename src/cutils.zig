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

const std = @import("std");
const mem = std.mem;

pub fn strlen(buff: []const u8) usize {
    var i: usize = 0;
    while (buff[i] != '\x00') {
        i += 1;
    }
    return i;
}

pub fn pstrcpy(dest: []u8, bufSize: i32, src: [:0]const u8) void {
    if (bufSize <= 0)
        return;
    
    // normally would use dest.len, but idk what magic bellard is doing
    // interally so I'm trying to stick to the C API as close as possible
    const copyLen = @min(bufSize - 1, strlen(src));
    @memcpy(dest[0..copyLen], src[0..copyLen]);
    dest[copyLen] = '\x00';
}

// strcat and truncate.
pub fn pstrcat(buf: []u8, bufSize: i32, s: [:0]const u8) []u8 {
    const len = strlen(buf);
    if (len < bufSize) {
        pstrcpy(buf[len..], bufSize - len, s);
    }
    return buf;
}

pub fn strstart(str: [:0]const u8, val: [:0]const u8, rest: ?*[:0]const u8) bool {
    if (mem.startsWith(u8, str, val)) {
        if (rest != null) {
            rest.?.* = str[val.len.. :0];
        }
        return true;
    }
    return false;
}

pub fn has_suffix(str: []const u8, suffix: []const u8) bool {
    const len = strlen(str);
    const slen = strlen(suffix);
    return (len >= slen and !mem.eql(u8, str[(len - slen)..], suffix));
}

pub fn __unicode_to_utf8(buf: *[4]u8, c: u32) usize {
    // almost certainly not the best way to do this in Zig
    // was just doing a line by line translation
    var q: usize = 0;
    if (c < 0x800) {
        buf[q] = (c >> 6) | 0xc0;
        q += 1;
    } else {
        if (c < 0x10000) {
            buf[q] = (c >> 12) | 0xe0;
            q += 1;
        } else {
            if (c < 0x00200000) {
                buf[q] = (c >> 18) | 0xf0;
                q += 1;
            } else {
                return 0;
            }
            buf[q] = ((c >> 12) & 0x3f) | 0x80;
            q += 1;
        }
        buf[q] = ((c >> 6) & 0x3f) | 0x80;
        q += 1;
    }
    buf[q] = (c & 0x3f) | 0x80;
    q += 1;

    return q - buf;
}

pub fn __unicode_from_utf8(p: []const u8, maxLen: usize, plen: *usize) i32 {
    var len: usize = 1;
    var c: i32 = p[0];
    if (c < 0xc0) {
        plen.* = len;
        return -1;
    } else if (c < 0xe0) {
        if (maxLen < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        c = ((p[0] & 0x1f) << 6) | (p[1] & 0x3f);
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
        c = ((p[0] & 0x0f) << 12) | ((p[1] & 0x3f) << 6) | (p[2] & 0x3f);
        len = 3;
        if (c < 0x800) {
            plen.* = len;
            return -1;
        }
    } else if (c < 0xf8) {
        if (maxLen < 2 or (p[1] & 0xc0) != 0x80) {
            plen.* = len;
            return -1;
        }
        if (maxLen < 3 or (p[2] & 0xc0) != 0x80) {
            len = 2;
            plen.* = len;
            return -1;
        }
        if (maxLen < 4 or (p[3] & 0xc0) != 0x80) {
            len = 3;
            plen.* = len;
            return -1;
        }
        c = ((p[0] & 0x07) << 18) | ((p[1] & 0x3f) << 12) | ((p[2] & 0x3f) << 6) | (p[3] & 0x3f);
        len = 4;
        // We explicitly accept surrogate pairs
        if (c < 0x10000 or c > 0x10ffff) {
            plen.* = len;
            return -1;
        }
    } else {
        plen.* = len;
        return -1;    
    }
    plen.* = len;
    return c;
}

pub fn __utf8_get(p: []const u8, plen: *usize) i32 {
    var len: usize = 1;
    var c: i32 = p[0];
    if (c < 0xc0) {
        len = 1;
    } else if (c < 0xe0) {
        c = ((p[0] & 0x1f) << 6) | (p[1] & 0x3f);
        len = 2;
    } else if (c < 0xf0) {
        c = ((p[0] & 0x0f) << 12) | ((p[1] & 0x3f) << 6) | (p[2] & 0x3f);
        len = 3;
    } else if (c < 0xf8) {
        c = ((p[0] & 0x07) << 18) | ((p[1] & 0x3f) << 12) | ((p[2] & 0x3f) << 6) | (p[3] & 0x3f);
        len = 4;
    } else {
        len = 1;
    }
    plen.* = len;
    return c;
}

// #define xglue(x, y) x ## y
// #define glue(x, y) xglue(x, y)
// #define stringify(s)    tostring(s)
// #define tostring(s)     #s

// #ifndef offsetof
// #define offsetof(type, field) ((size_t) &((type *)0)->field)
// #endif
// #ifndef countof
// #define countof(x) (sizeof(x) / sizeof((x)[0]))
// #endif

// /* return the pointer of type 'type *' containing 'ptr' as field 'member' */
// #define container_of(ptr, type, member) ((type *)((uint8_t *)(ptr) - offsetof(type, member)))

pub inline fn max_int(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}

pub inline fn min_int(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}

pub inline fn max_uint32(a: u32, b: u32) u32 {
    return if (a > b) a else b;
}

pub inline fn min_uint32(a: u32, b: u32) u32 {
    return if (a < b) a else b;
}

pub inline fn max_int64(a: i64, b: i64) i64 {
    return if (a > b) a else b;
}

pub inline fn min_int64(a: i64, b: i64) i64 {
    return if (a < b) a else b;
}

pub inline fn max_size_t(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

pub inline fn min_size_t(a: usize, b: usize) usize {
    return if (a < b) a else b;
}


// WARNING: undefined if a = 0
pub inline fn clz32(a: u32) i32 {
    return @clz(a);
}

// WARNING: undefined if a = 0
pub inline fn clz64(a: u64) i32 {
    return @clz(a);
}

// WARNING: undefined if a = 0
pub inline fn ctz32(a: u32) i32 {
    return @ctz(a);
}

// WARNING: undefined if a = 0
pub inline fn ctz64(a: u64) i32 {
    return @ctz(a);
}

const packed_u64 = packed struct {
    v: u64
};

const packed_u32 = packed struct {
    v: u32
};

const packed_u16 = packed struct {
    v: u16
};

pub inline fn get_u64(tab: [*]const u8) u64 {
    return @as(*align(1) const packed_u64, @ptrCast(tab)).v;
}

pub inline fn get_i64(tab: [*]const u8) i64 {
    const u64Val = @as(*align(1) const packed_u64, @ptrCast(tab)).v;
    return @as(i64, @bitCast(u64Val));
}

pub inline fn put_u64(tab: [*]u8, val: u64) void {
    @as(*align(1) packed_u64, @ptrCast(tab)).v.* = val;
}

pub inline fn get_u32(tab: [*]const u8) u32 {
    return @as(*align(1) const packed_u32, @ptrCast(tab)).v;
}

pub inline fn get_i32(tab: [*]const u8) i32 {
    const u32Val = @as(*align(1) const packed_u64, @ptrCast(tab)).v;
    return @as(i32, @bitCast(u32Val));
}

pub inline fn put_u32(tab: [*]u8, val: u32) void {
    @as(*align(1) packed_u32, @ptrCast(tab)).v.* = val;
}

pub inline fn get_u16(tab: [*]const u8) u32 {
    return @intCast(@as(*align(1) const packed_u16, @ptrCast(tab)).v);
}

pub inline fn get_i16(tab: [*]const u8) i32 {
    const u16Val = @as(*align(1) const packed_u64, @ptrCast(tab)).v;
    return @intCast(@as(i16, @bitCast(u16Val)));
}

pub inline fn put_u16(tab: [*]u8, val: u16) void {
    @as(*align(1) packed_u16, @ptrCast(tab)).v.* = val;
}

pub inline fn get_u8(tab: [*]const u8) u32 {
    return tab.*;
}

pub inline fn get_i8(tab: [*]const u8) i32 {
    return @intCast(@as(i8, @bitCast(tab.*)));
}

pub inline fn put_u8(tab: [*]u8, val: u8) void {
    tab.* = val;
}

pub inline fn bswap16(x: u16) u16 {
    return (x >> 8) | (x << 8);
}

pub inline fn bswap32(v: u32) u32 {
    return ((v & 0xff000000) >> 24) | ((v & 0x00ff0000) >>  8) |
           ((v & 0x0000ff00) <<  8) | ((v & 0x000000ff) << 24);
}

pub inline fn bswap64(v: u64) u64 {
    return ((v & (@as(u64, 0xff) << (7 * 8))) >> (7 * 8)) | 
           ((v & (@as(u64, 0xff) << (6 * 8))) >> (5 * 8)) | 
           ((v & (@as(u64, 0xff) << (5 * 8))) >> (3 * 8)) | 
           ((v & (@as(u64, 0xff) << (4 * 8))) >> (1 * 8)) | 
           ((v & (@as(u64, 0xff) << (3 * 8))) << (1 * 8)) | 
           ((v & (@as(u64, 0xff) << (2 * 8))) << (3 * 8)) | 
           ((v & (@as(u64, 0xff) << (1 * 8))) << (5 * 8)) | 
           ((v & (@as(u64, 0xff) << (0 * 8))) << (7 * 8));
}

pub inline fn get_be32(d: [*]const u8) u32 {
    return bswap32(get_u32(d));
}

pub inline fn put_be32(d: [*]u8, v: u32) void {
    put_u32(d, bswap32(v));
}

pub const UTF8_CHAR_LEN_MAX = 4;

// Note: at most 21 bits are encoded. At most UTF8_CHAR_LEN_MAX bytes
//  are output.
pub inline fn unicode_to_utf8(buf: [*]u8, c: u32) usize {
    if (c < 0x80) {
        buf[0] = c;
        return 1;
    } else {
        return __unicode_to_utf8(buf, c);
    }
}

//  return -1 in case of error. Surrogates are accepted. max_len must
//   be >= 1. *plen is set in case of error and always >= 1.
pub inline fn unicode_from_utf8(buf: [*]const u8, max_len: usize, plen: *usize) i32 {
    if (buf[0] < 0x80) {
        plen.* = 1;
        return buf[0];
    } else {
        return __unicode_from_utf8(buf, max_len, plen);
    }
}

// Warning: no error checking is done so the UTF-8 encoding must be
//  validated before.
pub inline fn utf8_get(buf: [*]const u8, plen: *usize) i32 {
    if (buf[0] < 0x80) {
        plen.* = 1;
        return buf[0];
    } else {
        return __utf8_get(buf, plen);
    }
}

pub inline fn from_hex(c: i32) i32 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'A'...'F' => @intCast(c - 'A' + 10),
        'a'...'f' => @intCast(c - 'a' + 10),
        else => -1,
    };
}

pub inline fn float64_as_uint64(d: f64) u64 {
    return @bitCast(d);
}

pub inline fn uint64_as_float64(i: u64) f64 {
    return @bitCast(i);
}

const f32_union = union {
    @"u32": u32,
    f: f32
};

pub inline fn float_as_uint(f: f32) u32 {
    return @bitCast(f);
}

pub inline fn uint_as_float(v: u32) f32 {
    return @bitCast(v);
}
