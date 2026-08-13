//
// Tiny Math Library (shared implementation)
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

// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess

const std = @import("std");
const builtin = @import("builtin");
const softfp = @import("libm_softfp.zig");
const build_options = @import("build_options");

pub const RM_RNE: c_int = 0;
pub const RM_RTZ: c_int = 1;
pub const RM_RDN: c_int = 2;
pub const RM_RUP: c_int = 3;
pub const RM_RMM: c_int = 4;
pub const RM_RMMUP: c_int = 5;

pub const use_softfloat = build_options.softfloat;

const libm_cvt_sf64_i32 = softfp.libm_cvt_sf64_i32;
const libm_fmod_sf64 = softfp.libm_fmod_sf64;
const libm_mul_u64 = softfp.libm_mul_u64;

const use_hw_sqrt = builtin.cpu.arch == .x86_64 or
    builtin.cpu.arch == .x86 or
    builtin.cpu.arch == .aarch64;

inline fn float64_as_uint64(a: f64) u64 {
    return @bitCast(a);
}

inline fn uint64_as_float64(a: u64) f64 {
    return @bitCast(a);
}

inline fn clz64(a: u64) c_int {
    return @intCast(@clz(a));
}

inline fn extract_words(ix0: *u32, ix1: *u32, d: f64) void {
    const u = float64_as_uint64(d);
    ix0.* = @truncate(u >> 32);
    ix1.* = @truncate(u);
}

inline fn get_high_word(d: f64) u32 {
    return @truncate(float64_as_uint64(d) >> 32);
}

inline fn get_low_word(d: f64) u32 {
    return @truncate(float64_as_uint64(d));
}

inline fn set_high_word(d: f64, h: u32) f64 {
    var u = float64_as_uint64(d);
    u = (u & 0xffffffff) | (@as(u64, h) << 32);
    return uint64_as_float64(u);
}

inline fn zero_low(x: f64) f64 {
    var u = float64_as_uint64(x);
    u &= 0xffffffff00000000;
    return uint64_as_float64(u);
}

inline fn float64_from_u32(h: u32, l: u32) f64 {
    return uint64_as_float64((@as(u64, h) << 32) | l);
}

const zero: f64 = 0.0;
const one: f64 = 1.0;
const half: f64 = 5.00000000000000000000e-01;
const tiny_val: f64 = 1.0e-300;
const huge_val: f64 = 1.0e300;

const two54: f64 = 1.80143985094819840000e+16;
const twom54: f64 = 5.55111512312578270212e-17;

inline fn rint_sf64(a: f64, rm: c_int) f64 {
    var u = float64_as_uint64(a);
    var frac_mask: u64 = undefined;
    var one_u: u64 = undefined;
    var m: u64 = undefined;
    var addend: u64 = undefined;
    const e = @as(c_int, @intCast(((u >> 52) & 0x7ff) -% 0x3ff));
    const s: u32 = @truncate(u >> 63);
    if (e < 0) {
        m = u & ((@as(u64, 1) << 52) - 1);
        if (e != -0x3ff or m != 0) {
            one_u = @as(u64, 0x3ff) << 52;
            u = 0;
            switch (rm) {
                RM_RUP, RM_RDN => {
                    if ((s ^ @as(u32, @intCast(rm & 1))) != 0)
                        u = one_u;
                },
                RM_RMM, RM_RMMUP => {
                    if (e == -1 and (m != 0 or (m == 0 and (s == 0 or rm == RM_RMM))))
                        u = one_u;
                },
                RM_RTZ, RM_RNE => {},
                else => {},
            }
            u |= @as(u64, s) << 63;
        }
    }
    if (e >= 0 and e < 52) {
        one_u = @as(u64, 1) << @intCast(52 - e);
        frac_mask = one_u - 1;
        addend = 0;
        switch (rm) {
            RM_RMMUP => addend = (one_u >> 1) - s,
            RM_RMM, RM_RNE => addend = one_u >> 1,
            RM_RTZ => {},
            RM_RUP, RM_RDN => {
                if ((s ^ @as(u32, @intCast(rm & 1))) != 0)
                    addend = one_u - 1;
            },
            else => {},
        }
        u += addend;
        u &= ~frac_mask;
    }
    return uint64_as_float64(u);
}

pub fn js_lrint(a: f64) i32 {
    return libm_cvt_sf64_i32(float64_as_uint64(a), RM_RNE);
}

pub fn js_fmod(a: f64, b: f64) f64 {
    return uint64_as_float64(libm_fmod_sf64(float64_as_uint64(a), float64_as_uint64(b)));
}

pub fn js_floor(x: f64) f64 {
    return rint_sf64(x, RM_RDN);
}

pub fn js_ceil(x: f64) f64 {
    return rint_sf64(x, RM_RUP);
}

pub fn js_trunc(x: f64) f64 {
    return rint_sf64(x, RM_RTZ);
}

pub fn js_round_inf(x: f64) f64 {
    return rint_sf64(x, RM_RMMUP);
}

pub fn js_fabs(x: f64) f64 {
    return @abs(x);
}

pub fn js_scalbn(x: f64, n: c_int) f64 {
    var xv = x;
    var k: c_int = undefined;
    var hx: u32 = undefined;
    var lx: u32 = undefined;
    extract_words(&hx, &lx, xv);
    k = @as(c_int, @intCast((hx & 0x7ff00000) >> 20));
    if (k == 0) {
        if ((lx | (hx & 0x7fffffff)) == 0) return xv;
        const xx = xv * two54;
        hx = get_high_word(xx);
        k = @as(c_int, @intCast((hx & 0x7ff00000) >> 20)) - 54;
        if (n < -50000) return tiny_val * xx;
        xv = xx;
    }
    if (k == 0x7ff) return xv + xv;
    k += n;
    if (k > 0x7fe) return huge_val * std.math.copysign(huge_val, xv);
    if (k > 0) {
        return set_high_word(xv, (hx & 0x800fffff) | (@as(u32, @intCast(k)) << 20));
    }
    if (k <= -54) {
        if (n > 50000)
            return huge_val * std.math.copysign(huge_val, xv);
        return tiny_val * std.math.copysign(tiny_val, xv);
    }
    k += 54;
    xv = set_high_word(xv, (hx & 0x800fffff) | (@as(u32, @intCast(k)) << 20));
    return xv * twom54;
}

fn js_sqrt_soft(x: f64) f64 {
    var ix0: c_int = undefined;
    var ix1: c_int = undefined;
    const sign: u32 = 0x80000000;
    var r: u32 = undefined;
    var t1: u32 = undefined;
    var s1: u32 = undefined;
    var q1: u32 = undefined;
    var s0: c_int = undefined;
    var q: c_int = undefined;
    var m: c_int = undefined;
    var t: c_int = undefined;
    var i: c_int = undefined;
    extract_words(@ptrCast(&ix0), @ptrCast(&ix1), x);
    if ((ix0 & 0x7ff00000) == 0x7ff00000) {
        return x * x + x;
    }
    if (ix0 <= 0) {
        if (((ix0 & ~@as(c_int, @bitCast(sign))) | ix1) == 0) return x;
        if (ix0 < 0) return (x - x) / (x - x);
    }
    m = ix0 >> 20;
    if (m == 0) {
        while (ix0 == 0) {
            m -= 21;
            ix0 |= ix1 >> 11;
            ix1 = @as(c_int, @intCast(@as(u32, @intCast(ix1)) << 21));
        }
        i = 0;
        while ((ix0 & 0x00100000) == 0) : (i += 1) {
            ix0 <<= 1;
        }
        m -= i - 1;
        ix0 |= ix1 >> @intCast(32 - i);
        ix1 = @as(c_int, @intCast(@as(u32, @intCast(ix1)) << @intCast(i)));
    }
    m -= 1023;
    ix0 = (ix0 & 0x000fffff) | 0x00100000;
    if ((m & 1) != 0) {
        ix0 += ix0 + @as(c_int, @intCast((@as(u32, @intCast(ix1)) & sign) >> 31));
        ix1 += ix1;
    }
    m >>= 1;
    ix0 += ix0 + @as(c_int, @intCast((@as(u32, @intCast(ix1)) & sign) >> 31));
    ix1 += ix1;
    q = 0;
    q1 = 0;
    s0 = 0;
    s1 = 0;
    r = 0x00200000;
    while (r != 0) {
        t = s0 + @as(c_int, @intCast(r));
        if (t <= ix0) {
            s0 = t + @as(c_int, @intCast(r));
            ix0 -= t;
            q += @as(c_int, @intCast(r));
        }
        ix0 += ix0 + @as(c_int, @intCast((@as(u32, @intCast(ix1)) & sign) >> 31));
        ix1 += ix1;
        r >>= 1;
    }
    r = sign;
    while (r != 0) {
        t1 = s1 + r;
        t = s0;
        if (t < ix0 or (t == ix0 and t1 <= @as(u32, @intCast(ix1)))) {
            s1 = t1 + r;
            if (((t1 & sign) == sign) and (s1 & sign) == 0) s0 += 1;
            ix0 -= t;
            if (@as(u32, @intCast(ix1)) < t1) ix0 -= 1;
            ix1 -= @as(c_int, @intCast(t1));
            q1 += r;
        }
        ix0 += ix0 + @as(c_int, @intCast((@as(u32, @intCast(ix1)) & sign) >> 31));
        ix1 += ix1;
        r >>= 1;
    }
    if ((ix0 | ix1) != 0) {
        var z = one - tiny_val;
        if (z >= one) {
            z = one + tiny_val;
            if (q1 == 0xffffffff) {
                q1 = 0;
                q += 1;
            } else if (z > one) {
                if (q1 == 0xfffffffe) q += 1;
                q1 += 2;
            } else {
                q1 += q1 & 1;
            }
        }
    }
    ix0 = (q >> 1) + 0x3fe00000;
    ix1 = @as(c_int, @intCast(q1 >> 1));
    if ((q & 1) == 1) ix1 |= @as(c_int, @bitCast(sign));
    ix0 += m << 20;
    return float64_from_u32(@intCast(ix0), @intCast(ix1));
}

pub fn js_sqrt(x: f64) f64 {
    if (use_softfloat) {
        return uint64_as_float64(softfp.sf64.sqrt_sf(float64_as_uint64(x), RM_RNE));
    }
    if (use_hw_sqrt) {
        return @sqrt(x);
    }
    return js_sqrt_soft(x);
}

inline fn eval_poly(x: f64, coefs: []const f64, n: c_int) f64 {
    var r = coefs[@intCast(n - 1)];
    var i: c_int = n - 2;
    while (i >= 0) : (i -= 1) {
        r = r * x + coefs[@intCast(i)];
    }
    return r;
}

const S1: f64 = -1.66666666666666324348e-01;
const S_tab = [_]f64{
    8.33333333332248946124e-03,
    -1.98412698298579493134e-04,
    2.75573137070700676789e-06,
    -2.50507602534068634195e-08,
    1.58969099521155010221e-10,
};

inline fn kernel_sin(x: f64, y: f64, iy: c_int) f64 {
    const ix = get_high_word(x) & 0x7fffffff;
    if (ix < 0x3e400000) {
        if (@as(c_int, @intFromFloat(x)) == 0) return x;
    }
    const z = x * x;
    const v = z * x;
    const r = eval_poly(z, &S_tab, 5);
    if (iy == 0) return x + v * (S1 + z * r);
    return x - ((z * (half * y - v * r) - y) - v * S1);
}

const C_tab = [_]f64{
    4.16666666666666019037e-02,
    -1.38888888888741095749e-03,
    2.48015872894767294178e-05,
    -2.75573143513906633035e-07,
    2.08757232129817482790e-09,
    -1.13596475577881948265e-11,
};

inline fn kernel_cos(x: f64, y: f64) f64 {
    const ix = get_high_word(x) & 0x7fffffff;
    if (ix < 0x3e400000) {
        if (@as(c_int, @intFromFloat(x)) == 0) return one;
    }
    const z = x * x;
    const r = z * eval_poly(z, &C_tab, 6);
    if (ix < 0x3FD33333) {
        return one - (0.5 * z - (z * r - x * y));
    } else {
        const qx: f64 = if (ix > 0x3fe90000)
            0.28125
        else
            float64_from_u32(ix - 0x00200000, 0);
        const hz = 0.5 * z - qx;
        const a = one - qx;
        return a - (hz - (z * r - x * y));
    }
}

const t_len: u32 = 19;

const T = [_]u64{
    0x1580cc11bf1edaea,
    0x9afed7ec47e35742,
    0xcf41ce7de294a4ba,
    0x5d49eeb1faf97c5e,
    0xd3d18fd9a797fa8b,
    0xdb4d9fb3c9f2c26d,
    0xfbcbc462d6829b47,
    0xc7fe25fff7816603,
    0x272117e2ef7e4a0e,
    0x4e64758e60d4ce7d,
    0x3a671c09ad17df90,
    0xba208d7d4baed121,
    0x3f877ac72c4a69cf,
    0x01924bba82746487,
    0x6dc91b8e909374b8,
    0x7f9458eaf7aef158,
    0x36d8a5664f10e410,
    0x7f09d5f47d4d3770,
    0x28be60db9391054a,
};

const PIO4 = [_]u64{
    0xc4c6628b80dc1cd1,
    0xc90fdaa22168c234,
};

inline fn get_u64_at_bit(tab: []const u64, tab_len: u32, pos: u32) u64 {
    const p = pos / 64;
    const shift: u6 = @intCast(pos % 64);
    var v = tab[p] >> shift;
    if (shift != 0 and (p + 1) < tab_len)
        v |= tab[p + 1] << @as(u6, @intCast(64 - @as(u32, shift)));
    return v;
}

fn rem_pio2_large(x: f64, y: *[2]f64) c_int {
    var m = float64_as_uint64(x);
    const sgn: u32 = @truncate(m >> 63);
    var e: c_int = @intCast((m >> 52) & 0x7ff);
    m = (m & ((@as(u64, 1) << 52) - 1)) | (@as(u64, 1) << 52);
    const j: u32 = @intCast(@as(i32, t_len * 64) - (e - 1075) - 192);
    var d: [3]u64 = undefined;
    var c: [2]u64 = undefined;
    var r0: u64 = undefined;
    var r1: u64 = undefined;
    var carry: u32 = undefined;
    var carry1: u32 = undefined;
    for (0..3) |ii| {
        d[ii] = get_u64_at_bit(&T, t_len, j + @as(u32, @intCast(ii)) * 64);
    }
    r1 = libm_mul_u64(&r0, m, d[0]);
    c[0] = r1;
    r1 = libm_mul_u64(&r0, m, d[1]);
    c[0] += r0;
    carry = @intFromBool(c[0] < r0);
    c[1] = r1 + carry;
    _ = libm_mul_u64(&r0, m, d[2]);
    c[1] += r0;
    var n: c_int = @intCast(c[1] >> 62);
    const rnd: c_int = @intCast((c[1] >> 61) & 1);
    n += rnd;
    var y_sgn: u32 = sgn;
    c[1] = (c[1] << 2) | (c[0] >> 62);
    c[0] = c[0] << 2;
    if (rnd != 0) {
        y_sgn ^= 1;
        c[0] = ~c[0];
        c[1] = ~c[1];
        if (c[0] +% 1 == 0)
            c[1] +%= 1;
    }
    r1 = libm_mul_u64(&r0, c[0], PIO4[1]);
    var dd: [3]u64 = .{ r0, r1, 0 };
    r1 = libm_mul_u64(&r0, c[1], PIO4[0]);
    dd[0] += r0;
    carry = @intFromBool(dd[0] < r0);
    dd[1] += r1;
    carry1 = @intFromBool(dd[1] < r1);
    dd[1] += carry;
    carry1 |= @intFromBool(dd[1] < carry);
    dd[2] = carry1;
    r1 = libm_mul_u64(&r0, c[1], PIO4[1]);
    dd[1] += r0;
    carry = @intFromBool(dd[1] < r0);
    dd[2] += r1 + carry;
    if (dd[2] == 0) {
        y[0] = 0;
        y[1] = 0;
    } else {
        var m0: u64 = undefined;
        var m1: u64 = undefined;
        var e1: c_int = undefined;
        e = clz64(dd[2]);
        dd[2] = (dd[2] << @intCast(e)) | (dd[1] >> @intCast(64 - e));
        dd[1] = dd[1] << @intCast(e);
        m0 = (dd[2] >> 11) & ((@as(u64, 1) << 52) - 1);
        m1 = ((dd[2] & 0x7ff) << 42) | (dd[1] >> @intCast(64 - 42));
        y[0] = uint64_as_float64((@as(u64, y_sgn) << 63) |
            (@as(u64, @intCast(1023 - e)) << 52) |
            m0);
        if (m1 == 0) {
            y[1] = 0;
        } else {
            e1 = clz64(m1) - 11;
            m1 = (m1 << @intCast(e1)) & ((@as(u64, 1) << 52) - 1);
            y[1] = uint64_as_float64((@as(u64, y_sgn) << 63) |
                (@as(u64, @intCast(1023 - e - 53 - e1)) << 52) |
                m1);
        }
    }
    if (sgn != 0)
        n = -n;
    return n;
}

const invpio2: f64 = 6.36619772367581382433e-01;
const pio2_tab = [_]f64{
    1.57079632673412561417e+00,
    6.07710050630396597660e-11,
    2.02226624871116645580e-21,
};
const pio2_t_tab = [_]f64{
    6.07710050650619224932e-11,
    2.02226624879595063154e-21,
    8.47842766036889956997e-32,
};
const rem_pio2_emax = [2]u8{ 16, 49 };

pub fn js_rem_pio2(x: f64, y: [*]f64) c_int {
    return js_rem_pio2_impl(x, y[0..2]);
}

fn js_rem_pio2_impl(x: f64, y: *[2]f64) c_int {
    const hx = get_high_word(x);
    const ix = hx & 0x7fffffff;
    if (ix <= 0x3fe921fb) {
        y[0] = x;
        y[1] = 0;
        return 0;
    }
    if (use_softfloat) {
        if (ix >= 0x7ff00000) {
            y[0] = x - x;
            y[1] = y[0];
            return 0;
        }
        return rem_pio2_large(x, y);
    }
    if (ix <= 0x413921fb) {
        var t = @abs(x);
        var n: c_int = undefined;
        var fn_val: f64 = undefined;
        if (ix < 0x4002d97c) {
            n = 1;
            fn_val = 1;
        } else {
            n = @as(c_int, @intFromFloat(t * invpio2 + half));
            fn_val = @floatFromInt(n);
        }
        var it: c_int = 0;
        var r: f64 = undefined;
        var w: f64 = undefined;
        var j: c_int = undefined;
        var i: c_int = undefined;
        while (true) {
            r = t - fn_val * pio2_tab[@intCast(it)];
            w = fn_val * pio2_t_tab[@intCast(it)];
            y[0] = r - w;
            j = @as(c_int, @intCast(hx >> 20));
            i = j - @as(c_int, @intCast((get_high_word(y[0]) >> 20) & 0x7ff));
            if (it == 2 or i <= rem_pio2_emax[@intCast(it)])
                break;
            t = r;
            it += 1;
        }
        y[1] = (r - y[0]) - w;
        if (hx < 0) {
            y[0] = -y[0];
            y[1] = -y[1];
            return -n;
        } else {
            return n;
        }
    }
    if (ix >= 0x7ff00000) {
        y[0] = x - x;
        y[1] = y[0];
        return 0;
    }
    return rem_pio2_large(x, y);
}

fn js_sin_cos(x: f64, flag: c_int) f64 {
    var y: [2]f64 = undefined;
    var s: f64 = 0;
    var c: f64 = 0;
    const ix = get_high_word(x);
    if (ix >= 0x7ff00000)
        return x - x;
    const n: u32 = @intCast(js_rem_pio2(x, &y));
    if (flag == 3 or (n & 1) == @as(u32, @intCast(flag))) {
        s = kernel_sin(y[0], y[1], 1);
        if (flag != 3) {
            if ((n + @as(u32, @intCast(flag))) & 2 != 0) s = -s;
            return s;
        }
    }
    if (flag == 3 or (n & 1) != @as(u32, @intCast(flag))) {
        c = kernel_cos(y[0], y[1]);
        if (flag != 3) {
            s = c;
            if ((n + @as(u32, @intCast(flag))) & 2 != 0) s = -s;
            return s;
        }
    }
    const z: f64 = if (n & 1 != 0) -c / s else s / c;
    return z;
}

pub fn js_sin(x: f64) f64 {
    return js_sin_cos(x, 0);
}

pub fn js_cos(x: f64) f64 {
    return js_sin_cos(x, 1);
}

pub fn js_tan(x: f64) f64 {
    return js_sin_cos(x, 3);
}

const pio2_hi: f64 = 1.57079632679489655800e+00;
const pio2_lo: f64 = 6.12323399573676603587e-17;
const pio4_hi: f64 = 7.85398163397448278999e-01;

const pS = [_]f64{
    1.66666666666666657415e-01,
    -3.25565818622400915405e-01,
    2.01212532134862925881e-01,
    -4.00555345006794114027e-02,
    7.91534994289814532176e-04,
    3.47933107596021167570e-05,
};

const qS = [_]f64{
    -2.40339491173441421878e+00,
    2.02094576023350569471e+00,
    -6.88283971605453293030e-01,
    7.70381505559019352791e-02,
};

inline fn R_poly(t: f64) f64 {
    const p = t * eval_poly(t, &pS, 6);
    const q = one + t * eval_poly(t, &qS, 4);
    return p / q;
}

pub fn js_asin(x: f64) f64 {
    var t: f64 = undefined;
    var w: f64 = undefined;
    var r: f64 = undefined;
    var s: f64 = undefined;
    var c: f64 = undefined;
    var p: f64 = undefined;
    var q: f64 = undefined;
    const hx = get_high_word(x);
    const ix = hx & 0x7fffffff;
    if (ix >= 0x3ff00000) {
        if (((ix - 0x3ff00000) | get_low_word(x)) == 0)
            return x * pio2_hi + x * pio2_lo;
        return (x - x) / (x - x);
    } else if (ix < 0x3fe00000) {
        if (ix < 0x3e400000) {
            if (huge_val + x > one) return x;
        } else {
            t = x * x;
            w = R_poly(t);
            return x + x * w;
        }
    }
    w = one - @abs(x);
    t = w * 0.5;
    r = R_poly(t);
    s = js_sqrt(t);
    if (ix >= 0x3FEF3333) {
        w = r;
        t = pio2_hi - (2.0 * (s + s * w) - pio2_lo);
    } else {
        w = zero_low(s);
        c = (t - w * w) / (s + w);
        p = 2.0 * s * r - (pio2_lo - 2.0 * c);
        q = pio4_hi - 2.0 * w;
        t = pio4_hi - (p - q);
    }
    if (hx > 0) return t else return -t;
}

const pi_val: f64 = 3.14159265358979311600e+00;

pub fn js_acos(x: f64) f64 {
    var z: f64 = undefined;
    var r: f64 = undefined;
    var w: f64 = undefined;
    var s: f64 = undefined;
    var c: f64 = undefined;
    var df: f64 = undefined;
    const hx = get_high_word(x);
    const ix = hx & 0x7fffffff;
    if (ix >= 0x3ff00000) {
        if (((ix - 0x3ff00000) | get_low_word(x)) == 0) {
            if (hx > 0) return 0.0;
            return pi_val + 2.0 * pio2_lo;
        }
        return (x - x) / (x - x);
    }
    if (ix < 0x3fe00000) {
        if (ix <= 0x3c600000) return pio2_hi + pio2_lo;
        z = x * x;
        r = R_poly(z);
        return pio2_hi - (x - (pio2_lo - x * r));
    } else {
        z = (one - @abs(x)) * 0.5;
        r = R_poly(z);
        s = js_sqrt(z);
        if (hx < 0) {
            w = r * s - pio2_lo;
            return pi_val - 2.0 * (s + w);
        } else {
            df = zero_low(s);
            c = (z - df * df) / (s + df);
            w = r * s + c;
            return 2.0 * (df + w);
        }
    }
}

const atanhi = [_]f64{
    4.63647609000806093515e-01,
    7.85398163397448278999e-01,
    9.82793723247329054082e-01,
    1.57079632679489655800e+00,
};

const atanlo = [_]f64{
    2.26987774529616870924e-17,
    3.06161699786838301793e-17,
    1.39033110312309984516e-17,
    6.12323399573676603587e-17,
};

const aT_even = [_]f64{
    3.33333333333329318027e-01,
    1.42857142725034663711e-01,
    9.09088713343650656196e-02,
    6.66107313738753120669e-02,
    4.97687799461593236017e-02,
    1.62858201153657823623e-02,
};

const aT_odd = [_]f64{
    -1.99999999998764832476e-01,
    -1.11111104054623557880e-01,
    -7.69187620504482999495e-02,
    -5.83357013379057348645e-02,
    -3.65315727442169155270e-02,
};

pub fn js_atan(x: f64) f64 {
    var xx = x;
    var w: f64 = undefined;
    var s1: f64 = undefined;
    var s2: f64 = undefined;
    var z: f64 = undefined;
    const hx = get_high_word(x);
    const ix = hx & 0x7fffffff;
    var id: c_int = undefined;
    if (ix >= 0x44100000) {
        if (ix > 0x7ff00000 or (ix == 0x7ff00000 and get_low_word(x) != 0))
            return x + x;
        if (hx > 0) return atanhi[3] + atanlo[3];
        return -atanhi[3] - atanlo[3];
    }
    if (ix < 0x3fdc0000) {
        if (ix < 0x3e200000) {
            if (huge_val + x > one) return x;
        }
        id = -1;
    } else {
        xx = @abs(x);
        if (ix < 0x3ff30000) {
            if (ix < 0x3fe60000) {
                id = 0;
                xx = (2.0 * xx - one) / (2.0 + xx);
            } else {
                id = 1;
                xx = (xx - one) / (xx + one);
            }
        } else {
            if (ix < 0x40038000) {
                id = 2;
                xx = (xx - 1.5) / (one + 1.5 * xx);
            } else {
                id = 3;
                xx = -1.0 / xx;
            }
        }
    }
    z = xx * xx;
    w = z * z;
    s1 = z * eval_poly(w, &aT_even, 6);
    s2 = w * eval_poly(w, &aT_odd, 5);
    if (id < 0) return xx - xx * (s1 + s2);
    z = atanhi[@intCast(id)] - ((xx * (s1 + s2) - atanlo[@intCast(id)]) - xx);
    if (hx < 0) return -z;
    return z;
}

const pi_o_4: f64 = 7.8539816339744827900E-01;
const pi_o_2: f64 = 1.5707963267948965580E+00;
const pi_lo: f64 = 1.2246467991473531772E-16;

pub fn js_atan2(y: f64, x: f64) f64 {
    var z: f64 = undefined;
    var k: c_int = undefined;
    var m: c_int = undefined;
    var hx: c_int = undefined;
    var hy: c_int = undefined;
    var ix: c_int = undefined;
    var iy: c_int = undefined;
    var lx: u32 = undefined;
    var ly: u32 = undefined;
    extract_words(@ptrCast(&hx), &lx, x);
    extract_words(@ptrCast(&hy), &ly, y);
    ix = hx & 0x7fffffff;
    iy = hy & 0x7fffffff;
    if ((ix > 0x7ff00000 or (ix == 0x7ff00000 and lx != 0)) or
        (iy > 0x7ff00000 or (iy == 0x7ff00000 and ly != 0)))
        return x + y;
    if (((hx - 0x3ff00000) | @as(c_int, @bitCast(lx))) == 0)
        return js_atan(y);
    m = ((hy >> 31) & 1) | ((hx >> 30) & 2);
    if (@as(u32, @intCast(iy)) | ly == 0) {
        z = 0;
    } else if (@as(u32, @intCast(ix)) | lx == 0) {
        return if (hy < 0) -pi_o_2 - tiny_val else pi_o_2 + tiny_val;
    } else if (ix == 0x7ff00000) {
        if (iy == 0x7ff00000) {
            z = pi_o_4;
        } else {
            z = 0;
        }
    } else if (iy == 0x7ff00000) {
        return if (hy < 0) -pi_o_2 - tiny_val else pi_o_2 + tiny_val;
    } else {
        k = (iy - ix) >> 20;
        if (k > 60) {
            z = pi_o_2 + 0.5 * pi_lo;
        } else if (hx < 0 and k < -60) {
            z = 0.0;
        } else {
            z = js_atan(@abs(y / x));
        }
    }
    switch (m) {
        0 => return z,
        1 => {
            z = set_high_word(z, get_high_word(z) ^ 0x80000000);
            return z;
        },
        2 => return pi_val - (z - pi_lo),
        else => return (z - pi_lo) - pi_val,
    }
}

const two: f64 = 2.0;
const halF = [_]f64{ 0.5, -0.5 };
const twom1000: f64 = 9.33263618503218878990e-302;
const o_threshold: f64 = 7.09782712893383973096e+02;
const u_threshold: f64 = -7.45133219101941108420e+02;
const ln2HI = [_]f64{ 6.93147180369123816490e-01, -6.93147180369123816490e-01 };
const ln2LO = [_]f64{ 1.90821492927058770002e-10, -1.90821492927058770002e-10 };
const invln2: f64 = 1.44269504088896338700e+00;

const P_tab = [_]f64{
    1.66666666666666019037e-01,
    -2.77777777770155933842e-03,
    6.61375632143793436117e-05,
    -1.65339022054652515390e-06,
    4.13813679705723846039e-08,
};

inline fn kernel_exp(z: f64, w: f64, lo: f64, hi: f64, n: c_int) f64 {
    const t = z * z;
    const t1 = z - t * eval_poly(t, &P_tab, 5);
    const r = (z * t1) / (t1 - two) - (w + z * w);
    var zz = one - ((lo + r) - hi);
    var j: c_int = @intCast(get_high_word(zz));
    j += n << 20;
    if ((j >> 20) <= 0) {
        zz = js_scalbn(zz, n);
    } else {
        zz = set_high_word(zz, get_high_word(zz) + @as(u32, @intCast(n << 20)));
    }
    return zz;
}

pub fn js_exp(x: f64) f64 {
    var xv = x;
    var hi: f64 = undefined;
    var lo: f64 = 0;
    var t: f64 = undefined;
    var k: c_int = undefined;
    const hx = get_high_word(xv);
    const xsb: c_int = @intCast((hx >> 31) & 1);
    const hx_abs = hx & 0x7fffffff;
    if (hx_abs >= 0x40862E42) {
        if (hx_abs >= 0x7ff00000) {
            if (((hx & 0xfffff) | get_low_word(xv)) != 0)
                return xv + xv;
            return if (xsb == 0) xv else 0.0;
        }
        if (xv > o_threshold) return huge_val * huge_val;
        if (xv < u_threshold) return twom1000 * twom1000;
    }
    if (hx_abs > 0x3fd62e42) {
        if (hx_abs < 0x3FF0A2B2) {
            hi = xv - ln2HI[@intCast(xsb)];
            lo = ln2LO[@intCast(xsb)];
            k = 1 - xsb - xsb;
        } else {
            k = @as(c_int, @intFromFloat(invln2 * xv + halF[@intCast(xsb)]));
            t = @floatFromInt(k);
            hi = xv - t * ln2HI[0];
            lo = t * ln2LO[0];
        }
        xv = hi - lo;
    } else if (hx_abs < 0x3e300000) {
        if (huge_val + xv > one) return one + xv;
        k = 0;
    } else {
        k = 0;
    }
    if (k == 0) {
        lo = 0;
        hi = xv;
    }
    return kernel_exp(xv, 0, lo, hi, k);
}

const bp = [_]f64{ 1.0, 1.5 };
const dp_h = [_]f64{ 0.0, 5.84962487220764160156e-01 };
const dp_l = [_]f64{ 0.0, 1.35003920212974897128e-08 };
const two53: f64 = 9007199254740992.0;
const lg2: f64 = 6.93147180559945286227e-01;
const lg2_h: f64 = 6.93147182464599609375e-01;
const lg2_l: f64 = -1.90465429995776804525e-09;
const ovt: f64 = 8.0085662595372944372e-0017;
const cp: f64 = 9.61796693925975554329e-01;
const cp_h: f64 = 9.61796700954437255859e-01;
const cp_l: f64 = -7.02846165095275826516e-09;
const ivln2: f64 = 1.44269504088896338700e+00;
const ivln2_h: f64 = 1.44269502162933349609e+00;
const ivln2_l: f64 = 1.92596299112661746887e-08;
const ivlg10b2: f64 = 0.3010299956639812;
const ivlg10b2_h: f64 = 0.30102992057800293;
const ivlg10b2_l: f64 = 7.508597826552624e-8;

const L_tab = [_]f64{
    5.99999999999994648725e-01,
    4.28571428578550184252e-01,
    3.33333329818377432918e-01,
    2.72728123808534006489e-01,
    2.30660745775561754067e-01,
    2.06975017800338417784e-01,
};

fn kernel_log2(pt1: *f64, pt2: *f64, ax: f64) void {
    var t: f64 = undefined;
    var u: f64 = undefined;
    var v: f64 = undefined;
    var t1: f64 = undefined;
    var t2: f64 = undefined;
    var r: f64 = undefined;
    var n: c_int = 0;
    var j: c_int = undefined;
    var ix: c_int = undefined;
    var k: c_int = undefined;
    var ss: f64 = undefined;
    var s2: f64 = undefined;
    var s_h: f64 = undefined;
    var s_l: f64 = undefined;
    var t_h: f64 = undefined;
    var t_l: f64 = undefined;
    var p_l: f64 = undefined;
    var p_h: f64 = undefined;
    var z_h: f64 = undefined;
    var z_l: f64 = undefined;
    var xx = ax;
    ix = @as(c_int, @bitCast(get_high_word(ax)));
    if (ix < 0x00100000) {
        xx *= two53;
        n -= 53;
        ix = @as(c_int, @bitCast(get_high_word(xx)));
    }
    n += (ix >> 20) - 0x3ff;
    j = ix & 0x000fffff;
    ix = j | 0x3ff00000;
    if (j <= 0x3988E) {
        k = 0;
    } else if (j < 0xBB67A) {
        k = 1;
    } else {
        k = 0;
        n += 1;
        ix -= 0x00100000;
    }
    xx = set_high_word(xx, @intCast(ix));
    u = xx - bp[@intCast(k)];
    v = one / (xx + bp[@intCast(k)]);
    ss = u * v;
    s_h = zero_low(ss);
    t_h = zero;
    t_h = set_high_word(t_h, @as(u32, @intCast((@as(u32, @bitCast(ix)) >> 1) | 0x20000000)) + 0x00080000 + @as(u32, @intCast(k << 18)));
    t_l = xx - (t_h - bp[@intCast(k)]);
    s_l = v * ((u - s_h * t_h) - s_h * t_l);
    s2 = ss * ss;
    r = s2 * s2 * eval_poly(s2, &L_tab, 6);
    r += s_l * (s_h + ss);
    s2 = s_h * s_h;
    t_h = zero_low(3.0 + s2 + r);
    t_l = r - ((t_h - 3.0) - s2);
    u = s_h * t_h;
    v = s_l * t_h + t_l * ss;
    p_h = zero_low(u + v);
    p_l = v - (p_h - u);
    z_h = cp_h * p_h;
    z_l = cp_l * p_h + p_l * cp + dp_l[@intCast(k)];
    t = @floatFromInt(n);
    t1 = zero_low(((z_h + z_l) + dp_h[@intCast(k)]) + t);
    t2 = z_l - (((t1 - t) - dp_h[@intCast(k)]) - z_h);
    pt1.* = t1;
    pt2.* = t2;
}

fn js_log_internal(x: f64, flag: c_int) f64 {
    var p_h: f64 = undefined;
    var p_l: f64 = undefined;
    var t: f64 = undefined;
    var u: f64 = undefined;
    var v: f64 = undefined;
    var hx: c_int = undefined;
    var lx: u32 = undefined;
    extract_words(@ptrCast(&hx), &lx, x);
    if (hx <= 0) {
        if ((@as(u32, @bitCast(hx)) & 0x7fffffff) | lx == 0)
            return -std.math.inf(f64);
        if (hx < 0)
            return std.math.nan(f64);
    } else if (hx >= 0x7ff00000) {
        return x + x;
    }
    kernel_log2(&p_h, &p_l, x);
    t = p_h + p_l;
    if (flag == 0) {
        return t;
    } else {
        t = zero_low(t);
        if (flag == 1) {
            u = t * lg2_h;
            v = (p_l - (t - p_h)) * lg2 + t * lg2_l;
        } else {
            u = t * ivlg10b2_h;
            v = (p_l - (t - p_h)) * ivlg10b2 + t * ivlg10b2_l;
        }
        return u + v;
    }
}

pub fn js_log2(x: f64) f64 {
    return js_log_internal(x, 0);
}

pub fn js_log(x: f64) f64 {
    return js_log_internal(x, 1);
}

pub fn js_log10(x: f64) f64 {
    return js_log_internal(x, 2);
}

pub fn js_pow(x: f64, y: f64) f64 {
    var z: f64 = undefined;
    var ax: f64 = undefined;
    var p_h: f64 = undefined;
    var p_l: f64 = undefined;
    var y1: f64 = undefined;
    var t1: f64 = undefined;
    var t2: f64 = undefined;
    var s: f64 = undefined;
    var t: f64 = undefined;
    var u: f64 = undefined;
    var v: f64 = undefined;
    var w: f64 = undefined;
    var i: u32 = undefined;
    var ju: u32 = undefined;
    var jz: u32 = undefined;
    var k: c_int = undefined;
    var yisint: c_int = undefined;
    var n: c_int = undefined;
    var hx: c_int = undefined;
    var hy: c_int = undefined;
    var ix: c_int = undefined;
    var iy: c_int = undefined;
    var lx: u32 = undefined;
    var ly: u32 = undefined;
    extract_words(@ptrCast(&hx), &lx, x);
    extract_words(@ptrCast(&hy), &ly, y);
    ix = hx & 0x7fffffff;
    iy = hy & 0x7fffffff;
    if (@as(u32, @intCast(iy)) | ly == 0) return one;
    if (ix > 0x7ff00000 or (ix == 0x7ff00000 and lx != 0) or
        iy > 0x7ff00000 or (iy == 0x7ff00000 and ly != 0))
        return x + y;
    yisint = 0;
    if (hx < 0) {
        if (iy >= 0x43400000) {
            yisint = 2;
        } else if (iy >= 0x3ff00000) {
            k = (iy >> 20) - 0x3ff;
            if (k > 20) {
                ju = ly >> @intCast(52 - k);
                if ((ju << @intCast(52 - k)) == ly) yisint = 2 - @as(c_int, @intCast(ju & 1));
            } else if (ly == 0) {
                ju = @as(u32, @intCast(iy)) >> @intCast(20 - k);
                if ((ju << @intCast(20 - k)) == @as(u32, @intCast(iy))) yisint = 2 - @as(c_int, @intCast(ju & 1));
            }
        }
    }
    if (ly == 0) {
        if (iy == 0x7ff00000) {
            if (((ix - 0x3ff00000) | @as(c_int, @bitCast(lx))) == 0)
                return y - y;
            if (ix >= 0x3ff00000)
                return if (hy >= 0) y else zero;
            return if (hy < 0) -y else zero;
        }
        if (iy == 0x3ff00000) {
            if (hy < 0) return one / x else return x;
        }
        if (hy == 0x40000000) return x * x;
        if (hy == 0x3fe00000) {
            if (hx >= 0)
                return js_sqrt(x);
        }
    }
    ax = @abs(x);
    if (lx == 0) {
        if (ix == 0x7ff00000 or ix == 0 or ix == 0x3ff00000) {
            z = ax;
            if (hy < 0) z = one / z;
            if (hx < 0) {
                if (((ix - 0x3ff00000) | yisint) == 0) {
                    z = (z - z) / (z - z);
                } else if (yisint == 1) {
                    z = -z;
                }
            }
            return z;
        }
    }
    n = (hx >> 31) + 1;
    if ((n | yisint) == 0) return (x - x) / (x - x);
    s = one;
    if ((n | (yisint - 1)) == 0) s = -one;
    if (iy > 0x41e00000) {
        if (iy > 0x43f00000) {
            if (ix <= 0x3fefffff) return if (hy < 0) huge_val * huge_val else tiny_val * tiny_val;
            if (ix >= 0x3ff00000) return if (hy > 0) huge_val * huge_val else tiny_val * tiny_val;
        }
        if (ix < 0x3fefffff) return if (hy < 0) s * huge_val * huge_val else s * tiny_val * tiny_val;
        if (ix > 0x3ff00000) return if (hy > 0) s * huge_val * huge_val else s * tiny_val * tiny_val;
        t = ax - one;
        w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
        u = ivln2_h * t;
        v = t * ivln2_l - w * ivln2;
        t1 = zero_low(u + v);
        t2 = v - (t1 - u);
    } else {
        kernel_log2(&t1, &t2, ax);
    }
    y1 = zero_low(y);
    p_l = (y - y1) * t1 + y * t2;
    p_h = y1 * t1;
    z = p_l + p_h;
    extract_words(&jz, &i, z);
    if (jz >= 0x40900000) {
        if (((jz -% 0x40900000) | i) != 0)
            return s * huge_val * huge_val;
        if (p_l + ovt > z - p_h)
            return s * huge_val * huge_val;
    } else if ((jz & 0x7fffffff) >= 0x4090cc00) {
        if (((jz -% 0xc090cc00) | i) != 0)
            return s * tiny_val * tiny_val;
        if (p_l <= z - p_h)
            return s * tiny_val * tiny_val;
    }
    jz = jz & 0x7fffffff;
    k = (@as(c_int, @intCast(jz >> 20))) - 0x3ff;
    n = 0;
    if (jz > 0x3fe00000) {
        n = @as(c_int, @bitCast(jz)) + @as(c_int, @intCast(@as(u32, 0x00100000) >> @intCast(k + 1)));
        k = ((n & 0x7fffffff) >> 20) - 0x3ff;
        t = zero;
        t = set_high_word(t, @as(u32, @intCast(@as(c_int, @bitCast(n)) & ~(@as(c_int, 0x000fffff) >> @intCast(k)))));
        n = ((n & 0x000fffff) | 0x00100000) >> @intCast(20 - k);
        if (@as(c_int, @bitCast(jz)) < 0) n = -n;
        p_h -= t;
    }
    t = zero_low(p_l + p_h);
    u = t * lg2_h;
    v = (p_l - (t - p_h)) * lg2 + t * lg2_l;
    z = u + v;
    w = v - (z - u);
    return s * kernel_exp(z, w, 0, z, n);
}

inline fn float_as_uint(a: f32) u32 {
    return @bitCast(a);
}

inline fn uint_as_float(a: u32) f32 {
    return @bitCast(a);
}

pub fn __adddf3(a: f64, b: f64) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.add_sf(float64_as_uint64(a), float64_as_uint64(b), RM_RNE));
}

pub fn __subdf3(a: f64, b: f64) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.sub_sf(float64_as_uint64(a), float64_as_uint64(b), RM_RNE));
}

pub fn __muldf3(a: f64, b: f64) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.mul_sf(float64_as_uint64(a), float64_as_uint64(b), RM_RNE));
}

pub fn __divdf3(a: f64, b: f64) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.div_sf(float64_as_uint64(a), float64_as_uint64(b), RM_RNE));
}

pub fn __eqdf2(a: f64, b: f64) callconv(.c) c_int {
    return softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
}

pub fn __nedf2(a: f64, b: f64) callconv(.c) c_int {
    const ret = softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
    if (ret == 2) {
        @branchHint(.unlikely);
        return 0;
    }
    return ret;
}

pub fn __ledf2(a: f64, b: f64) callconv(.c) c_int {
    return softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
}

pub fn __ltdf2(a: f64, b: f64) callconv(.c) c_int {
    return softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
}

pub fn __gedf2(a: f64, b: f64) callconv(.c) c_int {
    const ret = softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
    if (ret == 2) {
        @branchHint(.unlikely);
        return -1;
    }
    return ret;
}

pub fn __gtdf2(a: f64, b: f64) callconv(.c) c_int {
    const ret = softfp.sf64.cmp_sf(float64_as_uint64(a), float64_as_uint64(b));
    if (ret == 2) {
        @branchHint(.unlikely);
        return -1;
    }
    return ret;
}

pub fn __unorddf2(a: f64, b: f64) callconv(.c) c_int {
    return @intFromBool(softfp.sf64.isnan_sf(float64_as_uint64(a)) or
        softfp.sf64.isnan_sf(float64_as_uint64(b)));
}

pub fn __floatsidf(a: i32) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.cvt_i32_sf(a, RM_RNE));
}

pub fn __floatdidf(a: i64) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.cvt_i64_sf(a, RM_RNE));
}

pub fn __floatunsidf(a: c_uint) callconv(.c) f64 {
    return uint64_as_float64(softfp.sf64.cvt_u32_sf(a, RM_RNE));
}

pub fn __fixdfsi(a: f64) callconv(.c) i32 {
    return softfp.sf64.cvt_sf_i32(float64_as_uint64(a), RM_RTZ);
}

pub fn __extendsfdf2(a: f32) callconv(.c) f64 {
    return uint64_as_float64(softfp.cvt_sf32_sf64(float_as_uint(a)));
}

pub fn __truncdfsf2(a: f64) callconv(.c) f32 {
    return uint_as_float(softfp.cvt_sf64_sf32(float64_as_uint64(a), RM_RNE));
}
