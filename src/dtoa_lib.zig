//
// Tiny float64 printing and parsing library (shared implementation)
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

const std = @import("std");
const mem = std.mem;
const cutils = @import("cutils_lib.zig");

const min_int = cutils.min_int;
const strstart = cutils.strstart;

const USE_POW5_TABLE = true;
const USE_FAST_INT = true;

const LIMB_LOG2_BITS = 5;
const LIMB_BITS = 1 << LIMB_LOG2_BITS;
const slimb_t = i32;
const limb_t = u32;
const dlimb_t = u64;
const LIMB_DIGITS = 9;
const JS_RADIX_MAX = 36;
const DBIGNUM_LEN_MAX = 52;
const MANT_LEN_MAX = 18;
const mp_size_t = isize;

pub const JS_DTOA_MAX_DIGITS = 101;
pub const JS_DTOA_FORMAT_FREE = 0 << 0;
pub const JS_DTOA_FORMAT_FIXED = 1 << 0;
pub const JS_DTOA_FORMAT_FRAC = 2 << 0;
pub const JS_DTOA_FORMAT_MASK = 3 << 0;
pub const JS_DTOA_EXP_AUTO = 0 << 2;
pub const JS_DTOA_EXP_ENABLED = 1 << 2;
pub const JS_DTOA_EXP_DISABLED = 2 << 2;
pub const JS_DTOA_EXP_MASK = 3 << 2;
pub const JS_DTOA_MINUS_ZERO = 1 << 4;
pub const JS_ATOD_INT_ONLY = 1 << 0;
pub const JS_ATOD_ACCEPT_BIN_OCT = 1 << 1;
pub const JS_ATOD_ACCEPT_LEGACY_OCTAL = 1 << 2;
pub const JS_ATOD_ACCEPT_UNDERSCORES = 1 << 3;

pub const JSDTOATempMem = extern struct {
    mem: [37]u64,
};

pub const JSATODTempMem = extern struct {
    mem: [27]u64,
};

pub const mpb_t = struct {
    len: c_int,
    tab: [DBIGNUM_LEN_MAX]limb_t,
};

inline fn clz32(a: u32) c_int {
    return @intCast(@clz(a));
}

inline fn clz64(a: u64) c_int {
    return @intCast(@clz(a));
}

inline fn ctz32(a: u32) c_int {
    return @intCast(@ctz(a));
}

inline fn max_int(a: c_int, b: c_int) c_int {
    return @max(a, b);
}

inline fn float64_as_uint64(d: f64) u64 {
    return @bitCast(d);
}

inline fn uint64_as_float64(u64_val: u64) f64 {
    return @bitCast(u64_val);
}

inline fn likely(v: bool) bool {
    if (v) {
        @branchHint(.likely);
    }
    return v;
}

inline fn unlikely(v: bool) bool {
    if (v) {
        @branchHint(.unlikely);
    }
    return v;
}

fn bufOffset(base: [*]u8, cur: [*]u8) usize {
    return @intFromPtr(cur) - @intFromPtr(base);
}

fn digitToChar(digit: u64) u8 {
    if (digit < 10) return @intCast(digit + '0');
    return @intCast(digit + 'a' - 10);
}

fn overlap_move_left(buf: [*]u8, len: usize) void {
    if (len == 0) return;
    mem.copyForwards(u8, buf[0..len], buf[1 .. len + 1]);
}

fn insert_dot(buf: [*]u8, dot_pos: c_int, len: *c_int) void {
    const out_len: usize = @intCast(len.*);
    const pos: usize = @intCast(dot_pos);
    const out = buf[0 .. out_len + 1];
    mem.copyBackwards(u8, out[pos + 1 .. out_len + 1], out[pos..out_len]);
    out[pos] = '.';
    len.* += 1;
}

fn mp_add_ui(tab: []limb_t, b: limb_t, n: usize) limb_t {
    var i: usize = 0;
    var k = b;
    while (i < n) : (i += 1) {
        if (k == 0) break;
        const a = tab[i] +% k;
        k = @intFromBool(a < k);
        tab[i] = a;
    }
    return k;
}

fn mp_mul1(tabr: []limb_t, taba: []const limb_t, n: limb_t, b: limb_t, l: limb_t) limb_t {
    var i: limb_t = 0;
    var carry = l;
    while (i < n) : (i += 1) {
        const t: dlimb_t = @as(dlimb_t, taba[i]) * @as(dlimb_t, b) + carry;
        tabr[i] = @truncate(t);
        carry = @truncate(t >> LIMB_BITS);
    }
    return carry;
}

inline fn udiv1norm_init(d: limb_t) limb_t {
    const a1: limb_t = -%d - 1;
    const a0: limb_t = 0xffffffff;
    return @truncate(((@as(dlimb_t, a1) << LIMB_BITS) | a0) / d);
}

inline fn udiv1norm(pr: *limb_t, a1: limb_t, a0: limb_t, d: limb_t, d_inv: limb_t) limb_t {
    const n1m: limb_t = @bitCast(@as(slimb_t, @bitCast(a0)) >> (LIMB_BITS - 1));
    const n_adj = a0 +% (n1m & d);
    var a: dlimb_t = @as(dlimb_t, d_inv) * @as(dlimb_t, a1 -% n1m) + n_adj;
    var q: limb_t = @as(limb_t, @truncate(a >> LIMB_BITS)) +% a1;
    a = (@as(dlimb_t, a1) << LIMB_BITS) | a0;
    a = a -% @as(dlimb_t, q) * @as(dlimb_t, d) - @as(dlimb_t, d);
    const ah: limb_t = @truncate(a >> LIMB_BITS);
    q +%= 1 + ah;
    const r: limb_t = @as(limb_t, @truncate(a)) +% (ah & d);
    pr.* = r;
    return q;
}

fn mp_div1(tabr: []limb_t, taba: []const limb_t, n: limb_t, b: limb_t, r_in: limb_t) limb_t {
    var i: slimb_t = @intCast(n - 1);
    var r = r_in;
    while (i >= 0) : (i -= 1) {
        const a1: dlimb_t = (@as(dlimb_t, r) << LIMB_BITS) | taba[@intCast(i)];
        tabr[@intCast(i)] = @truncate(a1 / b);
        r = @truncate(a1 % b);
    }
    return r;
}

fn mp_shr(tab_r: []limb_t, tab: []const limb_t, n: mp_size_t, shift: c_int, high: limb_t) limb_t {
    std.debug.assert(shift >= 1 and shift < LIMB_BITS);
    var i: mp_size_t = n - 1;
    var l = high;
    while (i >= 0) : (i -= 1) {
        const a = tab[@intCast(i)];
        tab_r[@intCast(i)] = (a >> @intCast(shift)) | (l << @intCast(LIMB_BITS - shift));
        l = a;
    }
    return l & ((@as(limb_t, 1) << @intCast(shift)) - 1);
}

fn mp_shl(tab_r: []limb_t, tab: []const limb_t, n: mp_size_t, shift: c_int, low: limb_t) limb_t {
    std.debug.assert(shift >= 1 and shift < LIMB_BITS);
    var i: mp_size_t = 0;
    var l = low;
    while (i < n) : (i += 1) {
        const a = tab[@intCast(i)];
        tab_r[@intCast(i)] = (a << @intCast(shift)) | l;
        l = a >> @intCast(LIMB_BITS - shift);
    }
    return l;
}

noinline fn mp_div1norm(
    tabr: []limb_t,
    taba: []const limb_t,
    n: limb_t,
    b: limb_t,
    r_in: limb_t,
    b_inv: limb_t,
    shift: c_int,
) limb_t {
    var i: slimb_t = undefined;
    var r = r_in;
    if (shift != 0) {
        r = (r << @intCast(shift)) | mp_shl(tabr, taba, n, shift, 0);
    }
    i = @intCast(n - 1);
    while (i >= 0) : (i -= 1) {
        tabr[@intCast(i)] = udiv1norm(&r, r, taba[@intCast(i)], b, b_inv);
    }
    r >>= @intCast(shift);
    return r;
}

fn mpb_renorm(r: *mpb_t) void {
    while (r.len > 1 and r.tab[@intCast(r.len - 1)] == 0)
        r.len -= 1;
}

const pow5_table = [17]u32{
    0x00000005, 0x00000019, 0x0000007d, 0x00000271,
    0x00000c35, 0x00003d09, 0x0001312d, 0x0005f5e1,
    0x001dcd65, 0x009502f9, 0x02e90edd, 0x0e8d4a51,
    0x48c27395, 0x6bcc41e9, 0x1afd498d, 0x86f26fc1,
    0xa2bc2ec5,
};

const pow5h_table = [4]u8{
    0x00000001, 0x00000007, 0x00000023, 0x000000b1,
};

const pow5_inv_table = [13]u32{
    0x99999999, 0x47ae147a, 0x0624dd2f, 0xa36e2eb1,
    0x4f8b588e, 0x0c6f7a0b, 0xad7f29ab, 0x5798ee23,
    0x12e0be82, 0xb7cdfd9d, 0x5fd7fe17, 0x19799812,
    0xc25c2684,
};

fn pow_ui(a: u32, b: u32) u64 {
    if (b == 0) return 1;
    if (b == 1) return a;
    if (USE_POW5_TABLE) {
        if ((a == 5 or a == 10) and b <= 17) {
            var r64 = @as(u64, pow5_table[b - 1]);
            if (b >= 14) {
                r64 |= @as(u64, pow5h_table[b - 14]) << 32;
            }
            if (a == 10) r64 <<= @intCast(b);
            return r64;
        }
    }
    var r: u64 = a;
    const n_bits: c_int = 32 - clz32(b);
    var i: c_int = n_bits - 2;
    while (i >= 0) : (i -= 1) {
        r *= r;
        if ((b >> @intCast(i)) & 1 != 0) r *= a;
    }
    return r;
}

fn pow_ui_inv(pr_inv: *u32, pshift: *c_int, a: u32, b: u32) u32 {
    var r: u32 = undefined;
    var shift: c_int = undefined;
    if (USE_POW5_TABLE) {
        if (a == 5 and b >= 1 and b <= 13) {
            r = pow5_table[b - 1];
            shift = clz32(r);
            r <<= @intCast(shift);
            pr_inv.* = pow5_inv_table[b - 1];
        } else {
            r = @truncate(pow_ui(a, b));
            shift = clz32(r);
            r <<= @intCast(shift);
            pr_inv.* = udiv1norm_init(r);
        }
    } else {
        r = @truncate(pow_ui(a, b));
        shift = clz32(r);
        r <<= @intCast(shift);
        pr_inv.* = udiv1norm_init(r);
    }
    pshift.* = shift;
    return r;
}

const JS_RNDN = 0;
const JS_RNDNA = 1;
const JS_RNDZ = 2;

fn mpb_get_bit(r: *const mpb_t, k: c_int) c_int {
    const l = @divTrunc(@as(c_uint, @intCast(k)), LIMB_BITS);
    const kb = k & (LIMB_BITS - 1);
    if (l >= r.len) return 0;
    return @intCast((r.tab[@intCast(l)] >> @intCast(kb)) & 1);
}

fn mpb_shr_round(r: *mpb_t, shift: c_int, rnd_mode: c_int) void {
    if (shift == 0) return;
    if (shift < 0) {
        var neg_shift = -shift;
        const l = @divTrunc(@as(c_uint, @intCast(neg_shift)), LIMB_BITS);
        neg_shift &= LIMB_BITS - 1;
        if (neg_shift != 0) {
            r.tab[@intCast(r.len)] = mp_shl(r.tab[0..], r.tab[0..], @intCast(r.len), neg_shift, 0);
            r.len += 1;
            mpb_renorm(r);
        }
        if (l > 0) {
            var i: c_int = r.len - 1;
            while (i >= 0) : (i -= 1) {
                r.tab[@intCast(i + @as(c_int, @intCast(l)))] = r.tab[@intCast(i)];
            }
            i = 0;
            while (i < l) : (i += 1) {
                r.tab[@intCast(i)] = 0;
            }
            r.len += @intCast(l);
        }
    } else {
        var l: c_uint = undefined;
        var bit1: limb_t = undefined;
        var bit2: limb_t = undefined;
        var k: c_int = undefined;
        var add_one: c_int = undefined;
        var i: c_int = undefined;

        switch (rnd_mode) {
            JS_RNDZ => add_one = 0,
            JS_RNDN, JS_RNDNA => {
                bit1 = @intCast(mpb_get_bit(r, shift - 1));
                if (bit1 != 0) {
                    if (rnd_mode == JS_RNDNA) {
                        bit2 = 1;
                    } else {
                        bit2 = 0;
                        if (shift >= 2) {
                            k = shift - 1;
                            l = @divTrunc(@as(c_uint, @intCast(k)), LIMB_BITS);
                            k &= LIMB_BITS - 1;
                            i = 0;
                            while (i < min_int(@intCast(l), r.len)) : (i += 1) {
                                bit2 |= r.tab[@intCast(i)];
                            }
                            if (l < @as(c_uint, @intCast(r.len)))
                                bit2 |= r.tab[@intCast(l)] & ((@as(limb_t, 1) << @intCast(k)) - 1);
                        }
                    }
                    if (bit2 != 0) {
                        add_one = 1;
                    } else {
                        add_one = mpb_get_bit(r, shift);
                    }
                } else {
                    add_one = 0;
                }
            },
            else => add_one = 0,
        }

        l = @divTrunc(@as(c_uint, @intCast(shift)), LIMB_BITS);
        const shift1 = shift & (LIMB_BITS - 1);
        if (l >= @as(c_uint, @intCast(r.len))) {
            r.len = 1;
            r.tab[0] = @intCast(add_one);
        } else {
            if (l > 0) {
                r.len -= @intCast(l);
                i = 0;
                while (i < r.len) : (i += 1) {
                    r.tab[@intCast(i)] = r.tab[@intCast(i + @as(c_int, @intCast(l)))];
                }
            }
            if (shift1 != 0) {
                _ = mp_shr(r.tab[0..], r.tab[0..], @intCast(r.len), shift1, 0);
                mpb_renorm(r);
            }
            if (add_one != 0) {
                const a = mp_add_ui(r.tab[0..], 1, @intCast(r.len));
                if (a != 0) {
                    r.tab[@intCast(r.len)] = a;
                    r.len += 1;
                }
            }
        }
    }
}

fn mpb_cmp(a: *const mpb_t, b: *const mpb_t) c_int {
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    var i: mp_size_t = a.len - 1;
    while (i >= 0) : (i -= 1) {
        if (a.tab[@intCast(i)] != b.tab[@intCast(i)]) {
            if (a.tab[@intCast(i)] < b.tab[@intCast(i)]) return -1;
            return 1;
        }
    }
    return 0;
}

fn mpb_set_u64(r: *mpb_t, m: u64) void {
    r.tab[0] = @truncate(m);
    r.tab[1] = @truncate(m >> LIMB_BITS);
    if (r.tab[1] == 0)
        r.len = 1
    else
        r.len = 2;
}

fn mpb_get_u64(r: *const mpb_t) u64 {
    if (r.len == 1) {
        return r.tab[0];
    } else {
        return r.tab[0] | (@as(u64, r.tab[1]) << LIMB_BITS);
    }
}

fn mpb_floor_log2(a: *const mpb_t) c_int {
    const v = a.tab[@intCast(a.len - 1)];
    if (v == 0) return -1;
    return a.len * LIMB_BITS - 1 - clz32(v);
}

const MUL_LOG2_RADIX_BASE_LOG2 = 24;

const mul_log2_radix_table = [JS_RADIX_MAX - 1]u32{
    0x000000, 0xa1849d, 0x000000, 0x6e40d2,
    0x6308c9, 0x5b3065, 0x000000, 0x50c24e,
    0x4d104d, 0x4a0027, 0x4768ce, 0x452e54,
    0x433d00, 0x418677, 0x000000, 0x3ea16b,
    0x3d645a, 0x3c43c2, 0x3b3b9a, 0x3a4899,
    0x39680b, 0x3897b3, 0x37d5af, 0x372069,
    0x367686, 0x35d6df, 0x354072, 0x34b261,
    0x342bea, 0x33ac62, 0x000000, 0x32bfd9,
    0x3251dd, 0x31e8d6, 0x318465,
};

fn mul_log2_radix(a: c_int, radix: c_int) c_int {
    if ((radix & (radix - 1)) == 0) {
        const radix_bits: c_int = 31 - clz32(@intCast(radix));
        var a1 = a;
        if (a1 < 0) a1 -= radix_bits - 1;
        return @divTrunc(a1, radix_bits);
    } else {
        const mult = mul_log2_radix_table[@as(usize, @intCast(radix - 2))];
        return @intCast((@as(i64, a) * mult) >> MUL_LOG2_RADIX_BASE_LOG2);
    }
}

fn u32toa_len(buf: [*]u8, n: u32, len: usize) void {
    var n1 = n;
    var i: isize = @intCast(len - 1);
    while (i >= 0) : (i -= 1) {
        const digit = n1 % 10;
        n1 = n1 / 10;
        buf[@intCast(i)] = @intCast(digit + '0');
    }
}

fn u64toa_bin_len(buf: [*]u8, n: u64, radix_bits: u32, len: c_int) void {
    var n1 = n;
    const mask = (@as(u32, 1) << @intCast(radix_bits)) - 1;
    var i: c_int = len - 1;
    while (i >= 0) : (i -= 1) {
        const digit = n1 & mask;
        n1 >>= @intCast(radix_bits);
        buf[@intCast(i)] = digitToChar(@intCast(digit));
    }
}

fn limb_to_a(buf: [*]u8, n: limb_t, radix: u32, len: c_int) void {
    if (radix == 10) {
        u32toa_len(buf, n, @intCast(len));
    } else {
        var n1 = n;
        var i: c_int = len - 1;
        while (i >= 0) : (i -= 1) {
            const digit = n1 % radix;
            n1 = n1 / radix;
            buf[@intCast(i)] = digitToChar(digit);
        }
    }
}

pub fn u32toa(buf: [*]u8, n: u32) usize {
    var digits: [10]u8 = undefined;
    var n1 = n;
    var end: usize = digits.len;
    while (true) {
        end -= 1;
        digits[end] = @intCast(n1 % 10 + '0');
        n1 /= 10;
        if (n1 == 0) break;
    }
    const len = digits.len - end;
    @memcpy(buf[0..len], digits[end..]);
    return len;
}

pub fn i32toa(buf: [*]u8, n: i32) usize {
    if (n >= 0) {
        return u32toa(buf, @intCast(n));
    } else {
        buf[0] = '-';
        return u32toa(buf + 1, @bitCast(-n)) + 1;
    }
}

pub fn u64toa(buf: [*]u8, n_in: u64) usize {
    if (n_in < 0x100000000) {
        return u32toa(buf, @truncate(n_in));
    }
    var n = n_in;
    var offset: usize = 0;
    var n1 = n / 1000000000;
    n = n % 1000000000;
    if (n1 >= 0x100000000) {
        var n2: u32 = @truncate(n1 / 1000000000);
        n1 = n1 % 1000000000;
        if (n2 >= 10) {
            buf[offset] = @intCast(n2 / 10 + '0');
            offset += 1;
            n2 %= 10;
        }
        buf[offset] = @intCast(n2 + '0');
        offset += 1;
        u32toa_len(buf + offset, @truncate(n1), 9);
        offset += 9;
    } else {
        offset += u32toa(buf + offset, @truncate(n1));
    }
    u32toa_len(buf + offset, @truncate(n), 9);
    offset += 9;
    return offset;
}

pub fn i64toa(buf: [*]u8, n: i64) usize {
    if (n >= 0) {
        return u64toa(buf, @intCast(n));
    } else {
        buf[0] = '-';
        return u64toa(buf + 1, @bitCast(-n)) + 1;
    }
}

pub fn u64toa_radix(buf: [*]u8, n: u64, radix: u32) usize {
    if (likely(radix == 10))
        return u64toa(buf, n);
    if ((radix & (radix - 1)) == 0) {
        const radix_bits: u32 = @intCast(31 - clz32(radix));
        const l: usize = if (n == 0)
            1
        else
            @intCast(@divTrunc(64 - clz64(n) + @as(c_int, @intCast(radix_bits)) - 1, @as(c_int, @intCast(radix_bits))));
        u64toa_bin_len(buf, n, radix_bits, @intCast(l));
        return l;
    } else {
        var digits: [41]u8 = undefined;
        var n1 = n;
        var end: usize = digits.len;
        while (true) {
            const digit = n1 % radix;
            n1 /= radix;
            end -= 1;
            digits[end] = digitToChar(digit);
            if (n1 == 0) break;
        }
        const len = digits.len - end;
        @memcpy(buf[0..len], digits[end..]);
        return len;
    }
}

pub fn i64toa_radix(buf: [*]u8, n: i64, radix: u32) usize {
    if (n >= 0) {
        return u64toa_radix(buf, @intCast(n), radix);
    } else {
        buf[0] = '-';
        return u64toa_radix(buf + 1, @bitCast(-n), radix) + 1;
    }
}

const digits_per_limb_table = [JS_RADIX_MAX - 1]u8{
    32, 20, 16, 13, 12, 11, 10, 10, 9, 9, 8, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
};

const radix_base_table = [JS_RADIX_MAX - 1]u32{
    0x00000000, 0xcfd41b91, 0x00000000, 0x48c27395,
    0x81bf1000, 0x75db9c97, 0x40000000, 0xcfd41b91,
    0x3b9aca00, 0x8c8b6d2b, 0x19a10000, 0x309f1021,
    0x57f6c100, 0x98c29b81, 0x00000000, 0x18754571,
    0x247dbc80, 0x3547667b, 0x4c4b4000, 0x6b5a6e1d,
    0x94ace180, 0xcaf18367, 0x0b640000, 0x0e8d4a51,
    0x1269ae40, 0x17179149, 0x1cb91000, 0x23744899,
    0x2b73a840, 0x34e63b41, 0x40000000, 0x4cfa3cc1,
    0x5c13d840, 0x6d91b519, 0x81bf1000,
};

var dtoa_max_digits_table = [JS_RADIX_MAX - 1]u8{
    54, 35, 28, 24, 22, 20, 19, 18, 17, 17, 16, 16, 15, 15, 15, 14, 14, 14, 14, 14, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12, 12, 12, 12, 12, 12,
};

var atod_max_digits_table = [JS_RADIX_MAX - 1]u8{
    64, 80, 32, 55, 49, 45, 21, 40, 38, 37, 35, 34, 33, 32, 16, 31, 30, 30, 29, 29, 28, 28, 27, 27, 27, 26, 26, 26, 26, 25, 12, 25, 25, 24, 24,
};

const max_exponent = [JS_RADIX_MAX - 1]i16{
    1024, 647, 512, 442, 397, 365, 342, 324,
    309,  297, 286, 277, 269, 263, 256, 251,
    246,  242, 237, 234, 230, 227, 224, 221,
    218,  216, 214, 211, 209, 207, 205, 203,
    202,  200, 199,
};

const min_exponent = [JS_RADIX_MAX - 1]i16{
    -1075, -679, -538, -463, -416, -383, -359, -340,
    -324,  -311, -300, -291, -283, -276, -269, -263,
    -258,  -254, -249, -245, -242, -238, -235, -232,
    -229,  -227, -224, -222, -220, -217, -215, -214,
    -212,  -210, -208,
};

fn output_digits(
    buf: [*]u8,
    a: *mpb_t,
    radix: c_int,
    n_digits1: c_int,
    dot_pos: c_int,
) c_int {
    var n_digits = n_digits1;
    var radix_bits: c_int = 0;
    if ((radix & (radix - 1)) == 0) {
        radix_bits = 31 - clz32(@intCast(radix));
    }
    const digits_per_limb = digits_per_limb_table[@as(usize, @intCast(radix - 2))];
    if (radix_bits != 0) {
        while (true) {
            const n = min_int(n_digits, @intCast(digits_per_limb));
            n_digits -= n;
            u64toa_bin_len(buf + @as(usize, @intCast(n_digits)), a.tab[0], @intCast(radix_bits), n);
            if (n_digits == 0) break;
            mpb_shr_round(a, digits_per_limb * radix_bits, JS_RNDZ);
        }
    } else {
        while (n_digits != 0) {
            const n = min_int(n_digits, @intCast(digits_per_limb));
            n_digits -= n;
            const r = mp_div1(a.tab[0..], a.tab[0..], @intCast(a.len), radix_base_table[@as(usize, @intCast(radix - 2))], 0);
            mpb_renorm(a);
            limb_to_a(buf + @as(usize, @intCast(n_digits)), r, @intCast(radix), n);
        }
    }

    var len = n_digits1;
    if (dot_pos != n_digits1) {
        insert_dot(buf, dot_pos, &len);
    }
    return len;
}

fn mul_pow(a: *mpb_t, radix1: c_int, radix_shift: c_int, f: c_int, is_int: bool, e: c_int) c_int {
    var e_offset = -f * radix_shift;
    if (radix1 != 1) {
        const d = digits_per_limb_table[@as(usize, @intCast(radix1 - 2))];
        if (f >= 0) {
            var f1 = f;
            var b: limb_t = 0;
            var n0: c_int = 0;
            while (f1 != 0) {
                const n = min_int(f1, @intCast(d));
                if (n != n0) {
                    b = @truncate(pow_ui(@intCast(radix1), @intCast(n)));
                    n0 = n;
                }
                const h = mp_mul1(a.tab[0..], a.tab[0..], @intCast(a.len), b, 0);
                if (h != 0) {
                    a.tab[@intCast(a.len)] = h;
                    a.len += 1;
                }
                f1 -= n;
            }
        } else {
            var f1 = -f;
            const l = @divTrunc(f1 + d - 1, d);
            e_offset += @intCast(l * LIMB_BITS);
            const extra_bits: c_int = if (!is_int)
                max_int(e - mpb_floor_log2(a), 0)
            else
                max_int(2 + e - e_offset, 0);
            e_offset += extra_bits;
            mpb_shr_round(a, -@as(c_int, @intCast(l * LIMB_BITS + extra_bits)), JS_RNDZ);

            var b: limb_t = 0;
            var b_inv: limb_t = 0;
            var shift: c_int = 0;
            var n0: c_int = 0;
            var rem: limb_t = 0;
            while (f1 != 0) {
                const n = min_int(f1, @intCast(d));
                if (n != n0) {
                    var shift1: c_int = undefined;
                    var r_inv: u32 = undefined;
                    b = @truncate(pow_ui_inv(&r_inv, &shift1, @intCast(radix1), @intCast(n)));
                    b_inv = r_inv;
                    shift = shift1;
                    n0 = n;
                }
                const r = mp_div1norm(a.tab[0..], a.tab[0..], @intCast(a.len), b, 0, b_inv, shift);
                rem |= r;
                mpb_renorm(a);
                f1 -= n;
            }
            a.tab[0] |= @intFromBool(rem != 0);
        }
    }
    return e_offset;
}

fn mul_pow_round(
    tmp1: *mpb_t,
    m: u64,
    e: c_int,
    radix1: c_int,
    radix_shift: c_int,
    f: c_int,
    rnd_mode: c_int,
) void {
    mpb_set_u64(tmp1, m);
    const e_offset = mul_pow(tmp1, radix1, radix_shift, f, true, e);
    mpb_shr_round(tmp1, -e + e_offset, rnd_mode);
}

fn round_to_d(pe: *c_int, a: *mpb_t, e_offset: c_int, rnd_mode: c_int) u64 {
    if (a.tab[0] == 0 and a.len == 1) {
        pe.* = 0;
        return 0;
    } else {
        var e = mpb_floor_log2(a) + 1 - e_offset;
        const prec1: c_int = 53;
        const e_min: c_int = -1021;
        const prec: c_int = if (e < e_min)
            prec1 - (e_min - e)
        else
            prec1;
        mpb_shr_round(a, e + e_offset - prec, rnd_mode);
        var m = mpb_get_u64(a);
        m <<= @intCast(53 - prec);
        if (m >= @as(u64, 1) << 53) {
            m >>= 1;
            e += 1;
        }
        pe.* = e;
        return m;
    }
}

fn mul_pow_round_to_d(
    pe: *c_int,
    a: *mpb_t,
    radix1: c_int,
    radix_shift: c_int,
    f: c_int,
    rnd_mode: c_int,
) u64 {
    const e_offset = mul_pow(a, radix1, radix_shift, f, false, 55);
    return round_to_d(pe, a, e_offset, rnd_mode);
}

fn mpb_alloc_size(limbs: usize) usize {
    return @offsetOf(mpb_t, "tab") + limbs * @sizeOf(limb_t);
}

fn dtoaAlloc(mptr: *[*]u64, limbs: usize) *mpb_t {
    const size = mpb_alloc_size(limbs);
    const ret: [*]u8 = @ptrCast(mptr.*);
    mptr.* = mptr.* + (size + 7) / 8;
    return @ptrCast(@alignCast(ret));
}

fn dtoa_free(_: *mpb_t) void {}

pub fn js_dtoa_max_len(d: f64, radix: c_int, n_digits: c_int, flags: c_int) c_int {
    const fmt = flags & JS_DTOA_FORMAT_MASK;
    var n: c_int = undefined;

    if (fmt != JS_DTOA_FORMAT_FRAC) {
        if (fmt == JS_DTOA_FORMAT_FREE) {
            n = dtoa_max_digits_table[@as(usize, @intCast(radix - 2))];
        } else {
            n = n_digits;
        }
        if ((flags & JS_DTOA_EXP_MASK) == JS_DTOA_EXP_DISABLED) {
            const a = float64_as_uint64(d);
            var e: c_int = @intCast((a >> 52) & 0x7ff);
            if (e == 0x7ff) {
                n = 0;
            } else {
                e -= 1023;
                n += 10 + @as(c_int, @intCast(@abs(mul_log2_radix(e - 1, radix))));
            }
        } else {
            n += 1 + 1 + 6;
        }
    } else {
        const a = float64_as_uint64(d);
        var e: c_int = @intCast((a >> 52) & 0x7ff);
        if (e == 0x7ff) {
            n = 0;
        } else {
            e -= 1023;
            if (e < 0) {
                n = 1;
            } else {
                n = 2 + mul_log2_radix(e - 1, radix);
            }
            n += 1 + 1 + 1 + n_digits;
        }
    }
    return max_int(n, 9);
}

pub fn js_dtoa(
    buf: [*]u8,
    d: f64,
    radix: c_int,
    n_digits: c_int,
    flags: c_int,
    tmp_mem: *JSDTOATempMem,
) c_int {
    var mptr: [*]u64 = tmp_mem.mem[0..].ptr;
    const tmp1 = dtoaAlloc(&mptr, DBIGNUM_LEN_MAX);
    const mant_max = dtoaAlloc(&mptr, MANT_LEN_MAX);

    const fmt = flags & JS_DTOA_FORMAT_MASK;
    const radix_shift = ctz32(@intCast(radix));
    const radix1 = radix >> @intCast(radix_shift);
    const a = float64_as_uint64(d);
    var e: c_int = @intCast((a >> 52) & 0x7ff);
    var m = a & ((@as(u64, 1) << 52) - 1);
    const sgn: u64 = a >> 63;
    var q: [*]u8 = buf;
    var E: c_int = undefined;
    var P: c_int = undefined;
    var goto_output = false;

    if (e == 0x7ff) {
        if (m == 0) {
            if (sgn != 0) {
                q[0] = '-';
                q += 1;
            }
            std.mem.copyForwards(u8, q[0..8], "Infinity"[0..8]);
            q += 8;
        } else {
            std.mem.copyForwards(u8, q[0..3], "NaN"[0..3]);
            q += 3;
        }
        q[0] = 0;
        dtoa_free(mant_max);
        dtoa_free(tmp1);
        return @intCast(bufOffset(buf, q));
    }

    if (e == 0) {
        if (m == 0) {
            tmp1.len = 1;
            tmp1.tab[0] = 0;
            E = 1;
            if (fmt == JS_DTOA_FORMAT_FREE)
                P = 1
            else if (fmt == JS_DTOA_FORMAT_FRAC)
                P = n_digits + 1
            else
                P = n_digits;
            if (sgn != 0 and (flags & JS_DTOA_MINUS_ZERO) != 0) {
                q[0] = '-';
                q += 1;
            }
            goto_output = true;
        } else {
            const l: c_int = clz64(m) - 11;
            e -= l - 1;
            m <<= @intCast(l);
        }
    } else {
        m |= @as(u64, 1) << 52;
    }

    if (!goto_output) {
        if (sgn != 0) {
            q[0] = '-';
            q += 1;
        }
        e -= 1022;

        if (USE_FAST_INT and fmt == JS_DTOA_FORMAT_FREE and
            e >= 1 and e <= 53 and
            (m & ((@as(u64, 1) << @intCast(53 - e)) - 1)) == 0 and
            (flags & JS_DTOA_EXP_MASK) != JS_DTOA_EXP_ENABLED)
        {
            m >>= @intCast(53 - e);
            q += u64toa_radix(q, m, @intCast(radix));
            q[0] = 0;
            dtoa_free(mant_max);
            dtoa_free(tmp1);
            return @intCast(bufOffset(buf, q));
        }

        E = 1 + mul_log2_radix(e - 1, radix);

        if (fmt == JS_DTOA_FORMAT_FREE) {
            const P_max: c_int = dtoa_max_digits_table[@as(usize, @intCast(radix - 2))];
            const E0 = E;
            var E_found: c_int = 0;
            var P_found: c_int = 0;
            var mant_found: u64 = 0;
            P = P_max;
            while (true) {
                const mant_max1 = pow_ui(@intCast(radix), @intCast(P));
                E = E0;
                while (true) {
                    mul_pow_round(tmp1, m, e - 53, radix1, @intCast(radix_shift), P - E, JS_RNDN);
                    const mant = mpb_get_u64(tmp1);
                    if (mant < mant_max1) break;
                    E += 1;
                }
                var mant1 = mpb_get_u64(tmp1);
                while (mant1 % @as(u64, @intCast(radix)) == 0) {
                    mant1 /= @as(u64, @intCast(radix));
                    P -= 1;
                }
                if (P_found == 0) {
                    P_found = P;
                    E_found = E;
                    mant_found = mant1;
                    if (P == 1) break;
                    P -= 1;
                } else {
                    mpb_set_u64(tmp1, mant1);
                    var e1: c_int = undefined;
                    const m1 = mul_pow_round_to_d(&e1, tmp1, radix1, @intCast(radix_shift), E - P, JS_RNDN);
                    if (m1 == m and e1 == e) {
                        P_found = P;
                        E_found = E;
                        mant_found = mant1;
                        if (P == 1) break;
                        P -= 1;
                    } else {
                        break;
                    }
                }
            }
            P = P_found;
            E = E_found;
            mpb_set_u64(tmp1, mant_found);
        } else if (fmt == JS_DTOA_FORMAT_FRAC) {
            std.debug.assert(n_digits >= 0 and n_digits <= JS_DTOA_MAX_DIGITS);
            mul_pow_round(tmp1, m, e - 53, radix1, @intCast(radix_shift), n_digits, JS_RNDNA);
            var len = output_digits(q, tmp1, radix, max_int(E + 1, 1) + n_digits, max_int(E + 1, 1));
            if (q[0] == '0' and len >= 2 and q[1] != '.') {
                len -= 1;
                overlap_move_left(q, @intCast(len));
            }
            q += @intCast(len);
            q[0] = 0;
            dtoa_free(mant_max);
            dtoa_free(tmp1);
            return @intCast(bufOffset(buf, q));
        } else {
            std.debug.assert(n_digits >= 1 and n_digits <= JS_DTOA_MAX_DIGITS);
            P = n_digits;
            mant_max.len = 1;
            mant_max.tab[0] = 1;
            const pow_shift = mul_pow(mant_max, radix1, @intCast(radix_shift), P, false, 0);
            mpb_shr_round(mant_max, pow_shift, JS_RNDZ);
            while (true) {
                mul_pow_round(tmp1, m, e - 53, radix1, @intCast(radix_shift), P - E, JS_RNDNA);
                if (mpb_cmp(tmp1, mant_max) < 0) break;
                E += 1;
            }
        }
    }

    const E_max: c_int = if (fmt == JS_DTOA_FORMAT_FIXED)
        n_digits
    else
        dtoa_max_digits_table[@as(usize, @intCast(radix - 2))] + 4;
    if ((flags & JS_DTOA_EXP_MASK) == JS_DTOA_EXP_ENABLED or
        ((flags & JS_DTOA_EXP_MASK) == JS_DTOA_EXP_AUTO and (E <= -6 or E > E_max)))
    {
        q += @intCast(output_digits(q, tmp1, radix, P, 1));
        E -= 1;
        if (radix == 10) {
            q[0] = 'e';
        } else if (radix1 == 1 and radix_shift <= 4) {
            E *= radix_shift;
            q[0] = 'p';
        } else {
            q[0] = '@';
        }
        q += 1;
        if (E < 0) {
            q[0] = '-';
            q += 1;
            E = -E;
        } else {
            q[0] = '+';
            q += 1;
        }
        q += u32toa(q, @intCast(E));
    } else if (E <= 0) {
        q[0] = '0';
        q += 1;
        q[0] = '.';
        q += 1;
        var i: c_int = 0;
        while (i < -E) : (i += 1) {
            q[0] = '0';
            q += 1;
        }
        q += @intCast(output_digits(q, tmp1, radix, P, P));
    } else {
        q += @intCast(output_digits(q, tmp1, radix, P, min_int(P, E)));
        var i: c_int = 0;
        while (i < E - P) : (i += 1) {
            q[0] = '0';
            q += 1;
        }
    }

    q[0] = 0;
    dtoa_free(mant_max);
    dtoa_free(tmp1);
    return @intCast(bufOffset(buf, q));
}

inline fn to_digit(c: u8) c_int {
    if (c >= '0' and c <= '9')
        return c - '0'
    else if (c >= 'A' and c <= 'Z')
        return c - 'A' + 10
    else if (c >= 'a' and c <= 'z')
        return c - 'a' + 10
    else
        return 36;
}

fn mpb_mul1_base(r: *mpb_t, radix_base: limb_t, a: limb_t) void {
    if (r.tab[0] == 0 and r.len == 1) {
        r.tab[0] = a;
    } else {
        if (radix_base == 0) {
            var i: c_int = r.len;
            while (i >= 0) : (i -= 1) {
                r.tab[@intCast(i + 1)] = r.tab[@intCast(i)];
            }
            r.tab[0] = a;
        } else {
            r.tab[@intCast(r.len)] = mp_mul1(r.tab[0..], r.tab[0..], @intCast(r.len), radix_base, a);
        }
        r.len += 1;
        mpb_renorm(r);
    }
}

pub fn js_atod(
    str: [*c]const u8,
    pnext: ?*[*c]const u8,
    radix_in: c_int,
    flags: c_int,
    tmp_mem: *JSATODTempMem,
) f64 {
    var mptr: [*]u64 = tmp_mem.mem[0..].ptr;
    const tmp0 = dtoaAlloc(&mptr, DBIGNUM_LEN_MAX);

    var sep: c_int = if ((flags & JS_ATOD_ACCEPT_UNDERSCORES) != 0) '_' else 256;
    var p: [*c]const u8 = str;
    var is_neg: c_int = 0;
    var p_start: [*c]const u8 = undefined;
    var radix = radix_in;

    if (p[0] == '+') {
        p += 1;
        p_start = p;
    } else if (p[0] == '-') {
        is_neg = 1;
        p += 1;
        p_start = p;
    } else {
        p_start = p;
    }

    var prefix_consumed = false;
    if (p[0] == '0') {
        if ((p[1] == 'x' or p[1] == 'X') and (radix == 0 or radix == 16)) {
            p += 2;
            radix = 16;
            prefix_consumed = true;
        } else if ((p[1] == 'o' or p[1] == 'O') and radix == 0 and (flags & JS_ATOD_ACCEPT_BIN_OCT) != 0) {
            p += 2;
            radix = 8;
            prefix_consumed = true;
        } else if ((p[1] == 'b' or p[1] == 'B') and radix == 0 and (flags & JS_ATOD_ACCEPT_BIN_OCT) != 0) {
            p += 2;
            radix = 2;
            prefix_consumed = true;
        } else if ((p[1] >= '0' and p[1] <= '9') and radix == 0 and (flags & JS_ATOD_ACCEPT_LEGACY_OCTAL) != 0) {
            sep = 256;
            var i: usize = 1;
            while (p[i] >= '0' and p[i] <= '7') : (i += 1) {}
            if (p[i] != '8' and p[i] != '9') {
                p += 1;
                radix = 8;
                prefix_consumed = true;
            }
        }
        if (prefix_consumed and to_digit(@intCast(p[0])) >= radix) {
            return js_atod_fail(pnext, p, tmp0);
        }
    } else {
        var p1 = p;
        if ((flags & JS_ATOD_INT_ONLY) == 0 and strstart(p, "Infinity", &p1) != 0) {
            return js_atod_overflow(pnext, p1, is_neg, tmp0);
        }
    }

    if (radix == 0) radix = 10;

    var cur_limb: limb_t = 0;
    var expn_offset: c_int = 0;
    var digit_count: c_int = 0;
    var limb_digit_count: c_int = 0;
    const max_digits: c_int = atod_max_digits_table[@as(usize, @intCast(radix - 2))];
    const digits_per_limb = digits_per_limb_table[@as(usize, @intCast(radix - 2))];
    const radix_base = radix_base_table[@as(usize, @intCast(radix - 2))];
    const radix_shift = ctz32(@intCast(radix));
    const radix1 = radix >> @intCast(radix_shift);
    const radix_bits: c_int = if (radix1 == 1) radix_shift else 0;

    tmp0.len = 1;
    tmp0.tab[0] = 0;
    var extra_digits: limb_t = 0;
    var pos: c_int = 0;
    var dot_pos: c_int = -1;

    while (true) {
        if (p[0] == '.' and (p > p_start or to_digit(p[1]) < radix) and (flags & JS_ATOD_INT_ONLY) == 0) {
            if (p[0] == sep) return js_atod_fail(pnext, p, tmp0);
            if (dot_pos >= 0) break;
            dot_pos = pos;
            p += 1;
        }
        if (p[0] == sep and p > p_start and p[1] == '0') p += 1;
        if (p[0] != '0') break;
        p += 1;
        pos += 1;
    }

    const sig_pos = pos;
    while (true) {
        if (p[0] == '.' and (p > p_start or to_digit(p[1]) < radix) and (flags & JS_ATOD_INT_ONLY) == 0) {
            if (p[0] == sep) return js_atod_fail(pnext, p, tmp0);
            if (dot_pos >= 0) break;
            dot_pos = pos;
            p += 1;
        }
        if (p[0] == sep and p > p_start and to_digit(p[1]) < radix) p += 1;
        const c = to_digit(p[0]);
        if (c >= radix) break;
        p += 1;
        pos += 1;
        if (digit_count < max_digits) {
            cur_limb = cur_limb * @as(limb_t, @intCast(radix)) + @as(limb_t, @intCast(c));
            limb_digit_count += 1;
            if (limb_digit_count == digits_per_limb) {
                mpb_mul1_base(tmp0, radix_base, cur_limb);
                cur_limb = 0;
                limb_digit_count = 0;
            }
            digit_count += 1;
        } else {
            extra_digits |= @intCast(c);
        }
    }

    if (limb_digit_count != 0) {
        mpb_mul1_base(tmp0, @truncate(pow_ui(@intCast(radix), @intCast(limb_digit_count))), cur_limb);
    }

    var is_zero: bool = undefined;
    if (digit_count == 0) {
        is_zero = true;
        expn_offset = 0;
    } else {
        is_zero = false;
        if (dot_pos < 0) dot_pos = pos;
        expn_offset = sig_pos + digit_count - dot_pos;
    }

    if (radix_bits != 0 and extra_digits != 0) {
        tmp0.tab[0] |= 1;
    }

    var expn: c_int = 0;
    var expn_overflow = false;
    var is_bin_exp = false;

    if ((flags & JS_ATOD_INT_ONLY) == 0 and
        ((radix == 10 and (p[0] == 'e' or p[0] == 'E')) or
            (radix != 10 and (p[0] == '@' or
                (radix_bits >= 1 and radix_bits <= 4 and (p[0] == 'p' or p[0] == 'P'))))) and
        p > p_start)
    {
        is_bin_exp = p[0] == 'p' or p[0] == 'P';
        p += 1;
        var exp_is_neg: c_int = 0;
        if (p[0] == '+') {
            p += 1;
        } else if (p[0] == '-') {
            exp_is_neg = 1;
            p += 1;
        }
        var c = to_digit(p[0]);
        if (c >= 10) return js_atod_fail(pnext, p, tmp0);
        expn = c;
        p += 1;
        while (true) {
            if (p[0] == sep and to_digit(p[1]) < 10) p += 1;
            c = to_digit(p[0]);
            if (c >= 10) break;
            if (!expn_overflow) {
                if (unlikely(expn > ((std.math.maxInt(i32) - 2 - 9) / 10))) {
                    expn_overflow = true;
                } else {
                    expn = expn * 10 + c;
                }
            }
            p += 1;
        }
        if (exp_is_neg != 0) expn = -expn;
        if (!is_zero and expn_overflow) {
            if (exp_is_neg != 0) {
                return js_atod_done(pnext, p, is_neg, 0, tmp0);
            } else {
                return js_atod_done(pnext, p, is_neg, @as(u64, 0x7ff) << 52, tmp0);
            }
        }
    }

    if (p == p_start) return js_atod_fail(pnext, p, tmp0);

    var a: u64 = undefined;
    if (is_zero) {
        a = 0;
    } else {
        var expn1: c_int = undefined;
        if (radix_bits != 0) {
            if (!is_bin_exp) expn *= radix_bits;
            expn -= expn_offset * radix_bits;
            expn1 = expn + digit_count * radix_bits;
            if (expn1 >= 1024 + radix_bits) {
                return js_atod_overflow(pnext, p, is_neg, tmp0);
            } else if (expn1 <= -1075) {
                return js_atod_underflow(pnext, p, is_neg, tmp0);
            }
            var e: c_int = undefined;
            const m = round_to_d(&e, tmp0, -expn, JS_RNDN);
            a = js_atod_build_float(m, e);
        } else {
            expn -= expn_offset;
            expn1 = expn + digit_count;
            if (expn1 >= max_exponent[@as(usize, @intCast(radix - 2))] + 1) {
                return js_atod_overflow(pnext, p, is_neg, tmp0);
            } else if (expn1 <= min_exponent[@as(usize, @intCast(radix - 2))]) {
                return js_atod_underflow(pnext, p, is_neg, tmp0);
            }
            var e: c_int = undefined;
            const m = mul_pow_round_to_d(&e, tmp0, radix1, @intCast(radix_shift), expn, JS_RNDN);
            a = js_atod_build_float(m, e);
        }
    }

    return js_atod_done(pnext, p, is_neg, a, tmp0);
}

fn js_atod_build_float(m: u64, e: c_int) u64 {
    if (m == 0) {
        return 0;
    } else if (e > 1024) {
        return @as(u64, 0x7ff) << 52;
    } else if (e < -1073) {
        return 0;
    } else if (e < -1021) {
        return m >> @intCast(-e - 1021);
    } else {
        return (@as(u64, @intCast(e + 1022)) << 52) | (m & ((@as(u64, 1) << 52) - 1));
    }
}

fn js_atod_done(pnext: ?*[*c]const u8, p: [*c]const u8, is_neg: c_int, a_in: u64, tmp0: *mpb_t) f64 {
    var a = a_in;
    if (pnext) |pp| pp.* = p;
    dtoa_free(tmp0);
    a |= @as(u64, @intCast(is_neg)) << 63;
    return uint64_as_float64(a);
}

fn js_atod_fail(pnext: ?*[*c]const u8, p: [*c]const u8, tmp0: *mpb_t) f64 {
    if (pnext) |pp| pp.* = p;
    dtoa_free(tmp0);
    return std.math.nan(f64);
}

fn js_atod_overflow(pnext: ?*[*c]const u8, p: [*c]const u8, is_neg: c_int, tmp0: *mpb_t) f64 {
    return js_atod_done(pnext, p, is_neg, @as(u64, 0x7ff) << 52, tmp0);
}

fn js_atod_underflow(pnext: ?*[*c]const u8, p: [*c]const u8, is_neg: c_int, tmp0: *mpb_t) f64 {
    return js_atod_done(pnext, p, is_neg, 0, tmp0);
}
