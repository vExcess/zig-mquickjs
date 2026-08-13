//
// SoftFP Library (Zig port of softfp_template.h)
//
// Copyright (c) 2016 Fabrice Bellard
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

pub const RM_RNE: c_int = 0;
pub const RM_RTZ: c_int = 1;
pub const RM_RDN: c_int = 2;
pub const RM_RUP: c_int = 3;
pub const RM_RMM: c_int = 4;
pub const RM_RMMUP: c_int = 5;

fn SoftFP(comptime F_SIZE: u32) type {
    return struct {
        pub const F_UINT = std.meta.Int(.unsigned, F_SIZE);
        pub const F_ULONG = std.meta.Int(.unsigned, F_SIZE * 2);

        pub const MANT_SIZE: u32 = switch (F_SIZE) {
            32 => 23,
            64 => 52,
            else => @compileError("unsupported F_SIZE"),
        };
        pub const EXP_SIZE: u32 = switch (F_SIZE) {
            32 => 8,
            64 => 11,
            else => @compileError("unsupported F_SIZE"),
        };

        pub const EXP_MASK: u32 = (1 << EXP_SIZE) - 1;
        pub const MANT_MASK: F_UINT = (@as(F_UINT, 1) << MANT_SIZE) - 1;
        pub const SIGN_MASK: F_UINT = @as(F_UINT, 1) << (F_SIZE - 1);
        pub const IMANT_SIZE: u32 = F_SIZE - 2;
        pub const RND_SIZE: u32 = IMANT_SIZE - MANT_SIZE;
        pub const F_QNAN: F_UINT = (@as(F_UINT, EXP_MASK) << MANT_SIZE) | (@as(F_UINT, 1) << (MANT_SIZE - 1));

        inline fn clz(a: F_UINT) i32 {
            return @intCast(@clz(a));
        }

        pub fn pack_sf(a_sign: u32, a_exp: u32, a_mant: F_UINT) F_UINT {
            return (@as(F_UINT, a_sign) << (F_SIZE - 1)) |
                (@as(F_UINT, a_exp) << MANT_SIZE) |
                (a_mant & MANT_MASK);
        }

        pub fn unpack_sf(pa_sign: *u32, pa_exp: *i32, a: F_UINT) F_UINT {
            pa_sign.* = @intCast(a >> (F_SIZE - 1));
            pa_exp.* = @intCast((a >> MANT_SIZE) & EXP_MASK);
            return a & MANT_MASK;
        }

        pub fn rshift_rnd(a_in: F_UINT, d: i32) F_UINT {
            var a = a_in;
            if (d != 0) {
                if (d >= F_SIZE) {
                    a = @intFromBool(a != 0);
                } else if (d > 0) {
                    const ud: std.math.Log2Int(F_UINT) = @intCast(d);
                    const mask = (@as(F_UINT, 1) << ud) - 1;
                    a = (a >> ud) | @intFromBool((a & mask) != 0);
                }
            }
            return a;
        }

        pub fn round_pack_sf(a_sign: u32, a_exp_in: i32, a_mant_in: F_UINT, rm: c_int) F_UINT {
            var a_exp = a_exp_in;
            var a_mant = a_mant_in;
            var addend: u32 = undefined;
            var rnd_bits: F_UINT = undefined;

            switch (rm) {
                RM_RNE, RM_RMM => {
                    addend = (1 << (RND_SIZE - 1));
                },
                RM_RTZ => {
                    addend = 0;
                },
                else => {
                    if ((a_sign ^ @as(u32, @intCast(rm & 1))) != 0)
                        addend = (1 << RND_SIZE) - 1
                    else
                        addend = 0;
                },
            }

            if (a_exp <= 0) {
                const is_subnormal = (a_exp < 0 or
                    (a_mant + addend) < (@as(F_UINT, 1) << (F_SIZE - 1)));
                const diff = 1 - a_exp;
                a_mant = rshift_rnd(a_mant, diff);
                rnd_bits = a_mant & ((@as(F_UINT, 1) << RND_SIZE) - 1);
                _ = is_subnormal;
                a_exp = 1;
            } else {
                rnd_bits = a_mant & ((@as(F_UINT, 1) << RND_SIZE) - 1);
            }
            a_mant = (a_mant + addend) >> RND_SIZE;
            if (rm == RM_RNE and rnd_bits == (@as(F_UINT, 1) << (RND_SIZE - 1)))
                a_mant &= ~@as(F_UINT, 1);
            a_exp += @intCast(a_mant >> (MANT_SIZE + 1));
            if (a_mant <= MANT_MASK) {
                a_exp = 0;
            } else if (a_exp >= EXP_MASK) {
                if (addend == 0) {
                    a_exp = EXP_MASK - 1;
                    a_mant = MANT_MASK;
                } else {
                    a_exp = EXP_MASK;
                    a_mant = 0;
                }
            }
            return pack_sf(a_sign, @intCast(a_exp), a_mant);
        }

        pub fn normalize_sf(a_sign: u32, a_exp_in: i32, a_mant_in: F_UINT, rm: c_int) F_UINT {
            var a_exp = a_exp_in;
            var a_mant = a_mant_in;
            const shift: i32 = clz(a_mant) - @as(i32, F_SIZE - 1 - IMANT_SIZE);
            a_exp -= shift;
            if (shift > 0) {
                a_mant <<= @intCast(shift);
            }
            return round_pack_sf(a_sign, a_exp, a_mant, rm);
        }

        pub fn normalize_subnormal_sf(pa_exp: *i32, a_mant: F_UINT) F_UINT {
            const shift: i32 = @as(i32, @intCast(MANT_SIZE)) - ((@as(i32, F_SIZE - 1) - clz(a_mant)));
            pa_exp.* = 1 - shift;
            if (shift > 0)
                return a_mant << @intCast(shift);
            return a_mant;
        }

        pub fn isnan_sf(a: F_UINT) bool {
            const a_exp = (a >> MANT_SIZE) & EXP_MASK;
            const a_mant = a & MANT_MASK;
            return (a_exp == EXP_MASK and a_mant != 0);
        }

        pub fn add_sf(a_in: F_UINT, b_in: F_UINT, rm: c_int) F_UINT {
            var a = a_in;
            var b = b_in;
            if ((a & ~SIGN_MASK) < (b & ~SIGN_MASK)) {
                const tmp = a;
                a = b;
                b = tmp;
            }
            var a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: u32 = @intCast(b >> (F_SIZE - 1));
            var a_exp: u32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var b_exp: u32 = @intCast((b >> MANT_SIZE) & EXP_MASK);
            var a_mant = (a & MANT_MASK) << 3;
            var b_mant = (b & MANT_MASK) << 3;
            if (a_exp == EXP_MASK) {
                @branchHint(.unlikely);
                if (a_mant != 0) {
                    return F_QNAN;
                } else if (b_exp == EXP_MASK and a_sign != b_sign) {
                    return F_QNAN;
                } else {
                    return a;
                }
            }
            if (a_exp == 0) {
                a_exp = 1;
            } else {
                a_mant |= @as(F_UINT, 1) << (MANT_SIZE + 3);
            }
            if (b_exp == 0) {
                b_exp = 1;
            } else {
                b_mant |= @as(F_UINT, 1) << (MANT_SIZE + 3);
            }
            b_mant = rshift_rnd(b_mant, @as(i32, @intCast(a_exp)) - @as(i32, @intCast(b_exp)));
            if (a_sign == b_sign) {
                a_mant += b_mant;
            } else {
                a_mant -= b_mant;
                if (a_mant == 0) {
                    a_sign = @intFromBool(rm == RM_RDN);
                }
            }
            const a_exp_i: i32 = @as(i32, @intCast(a_exp)) + @as(i32, @intCast(RND_SIZE - 3));
            return normalize_sf(a_sign, a_exp_i, a_mant, rm);
        }

        pub fn sub_sf(a: F_UINT, b: F_UINT, rm: c_int) F_UINT {
            return add_sf(a, b ^ SIGN_MASK, rm);
        }

        pub fn mul_u(plow: *F_UINT, a: F_UINT, b: F_UINT) F_UINT {
            const r: F_ULONG = @as(F_ULONG, a) * @as(F_ULONG, b);
            plow.* = @truncate(r);
            return @intCast(r >> F_SIZE);
        }

        pub fn mul_sf(a: F_UINT, b: F_UINT, rm: c_int) F_UINT {
            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: u32 = @intCast(b >> (F_SIZE - 1));
            const r_sign = a_sign ^ b_sign;
            var a_exp: i32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var b_exp: i32 = @intCast((b >> MANT_SIZE) & EXP_MASK);
            var a_mant = a & MANT_MASK;
            var b_mant = b & MANT_MASK;
            if (a_exp == EXP_MASK or b_exp == EXP_MASK) {
                if (isnan_sf(a) or isnan_sf(b)) {
                    return F_QNAN;
                } else {
                    if ((a_exp == EXP_MASK and (b_exp == 0 and b_mant == 0)) or
                        (b_exp == EXP_MASK and (a_exp == 0 and a_mant == 0)))
                    {
                        return F_QNAN;
                    } else {
                        return pack_sf(r_sign, EXP_MASK, 0);
                    }
                }
            }
            if (a_exp == 0) {
                if (a_mant == 0)
                    return pack_sf(r_sign, 0, 0);
                a_mant = normalize_subnormal_sf(&a_exp, a_mant);
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            if (b_exp == 0) {
                if (b_mant == 0)
                    return pack_sf(r_sign, 0, 0);
                b_mant = normalize_subnormal_sf(&b_exp, b_mant);
            } else {
                b_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            const r_exp = a_exp + b_exp - (1 << (EXP_SIZE - 1)) + 2;
            var r_mant_low: F_UINT = undefined;
            var r_mant = mul_u(&r_mant_low, a_mant << RND_SIZE, b_mant << (RND_SIZE + 1));
            r_mant |= @intFromBool(r_mant_low != 0);
            return normalize_sf(r_sign, r_exp, r_mant, rm);
        }

        fn divrem_u(pr: *F_UINT, ah: F_UINT, al: F_UINT, b: F_UINT) F_UINT {
            const a: F_ULONG = (@as(F_ULONG, ah) << F_SIZE) | al;
            pr.* = @intCast(a % b);
            return @intCast(a / b);
        }

        pub fn div_sf(a: F_UINT, b: F_UINT, rm: c_int) F_UINT {
            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: u32 = @intCast(b >> (F_SIZE - 1));
            const r_sign = a_sign ^ b_sign;
            var a_exp: i32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var b_exp: i32 = @intCast((b >> MANT_SIZE) & EXP_MASK);
            var a_mant = a & MANT_MASK;
            var b_mant = b & MANT_MASK;
            if (a_exp == EXP_MASK) {
                if (a_mant != 0 or isnan_sf(b)) {
                    return F_QNAN;
                } else if (b_exp == EXP_MASK) {
                    return F_QNAN;
                } else {
                    return pack_sf(r_sign, EXP_MASK, 0);
                }
            } else if (b_exp == EXP_MASK) {
                if (b_mant != 0) {
                    return F_QNAN;
                } else {
                    return pack_sf(r_sign, 0, 0);
                }
            }

            if (b_exp == 0) {
                if (b_mant == 0) {
                    if (a_exp == 0 and a_mant == 0) {
                        return F_QNAN;
                    } else {
                        return pack_sf(r_sign, EXP_MASK, 0);
                    }
                }
                b_mant = normalize_subnormal_sf(&b_exp, b_mant);
            } else {
                b_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            if (a_exp == 0) {
                if (a_mant == 0)
                    return pack_sf(r_sign, 0, 0);
                a_mant = normalize_subnormal_sf(&a_exp, a_mant);
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            const r_exp = a_exp - b_exp + (1 << (EXP_SIZE - 1)) - 1;
            var r: F_UINT = undefined;
            var r_mant = divrem_u(&r, a_mant, 0, b_mant << 2);
            if (r != 0)
                r_mant |= 1;
            return normalize_sf(r_sign, r_exp, r_mant, rm);
        }

        fn sqrtrem_u(pr: *F_UINT, ah: F_UINT, al: F_UINT) i32 {
            var l: i32 = undefined;
            if (ah != 0) {
                l = @as(i32, 2 * F_SIZE) - clz(ah - 1);
            } else {
                if (al == 0) {
                    pr.* = 0;
                    return 0;
                }
                l = @as(i32, F_SIZE) - clz(al - 1);
            }
            const a: F_ULONG = (@as(F_ULONG, ah) << F_SIZE) | al;
            var u: F_ULONG = @as(F_ULONG, 1) << @intCast(@divFloor(l + 1, 2));
            var s: F_ULONG = undefined;
            while (true) {
                s = u;
                u = ((a / s) + s) / 2;
                if (u >= s)
                    break;
            }
            const inexact: i32 = @intFromBool((a - s * s) != 0);
            pr.* = @intCast(s);
            return inexact;
        }

        pub fn sqrt_sf(a: F_UINT, rm: c_int) F_UINT {
            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            var a_exp: i32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var a_mant = a & MANT_MASK;
            if (a_exp == EXP_MASK) {
                if (a_mant != 0) {
                    return F_QNAN;
                } else if (a_sign != 0) {
                    return F_QNAN;
                } else {
                    return a;
                }
            }
            if (a_sign != 0) {
                if (a_exp == 0 and a_mant == 0)
                    return a;
                return F_QNAN;
            }
            if (a_exp == 0) {
                if (a_mant == 0)
                    return pack_sf(0, 0, 0);
                a_mant = normalize_subnormal_sf(&a_exp, a_mant);
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            a_exp -= @as(i32, @intCast(EXP_MASK / 2));
            if ((a_exp & 1) != 0) {
                a_exp -= 1;
                a_mant <<= 1;
            }
            a_exp = @divFloor(a_exp, 2) + @as(i32, @intCast(EXP_MASK / 2));
            a_mant <<= (F_SIZE - 4 - MANT_SIZE);
            if (sqrtrem_u(&a_mant, a_mant, 0) != 0)
                a_mant |= 1;
            return normalize_sf(a_sign, a_exp, a_mant, rm);
        }

        pub fn eq_quiet_sf(a: F_UINT, b: F_UINT) i32 {
            if (isnan_sf(a) or isnan_sf(b)) {
                return 0;
            }
            if (@as(F_UINT, (a | b) << 1) == 0)
                return 1;
            return @intFromBool(a == b);
        }

        pub fn le_sf(a: F_UINT, b: F_UINT) i32 {
            if (isnan_sf(a) or isnan_sf(b)) {
                return 0;
            }
            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: u32 = @intCast(b >> (F_SIZE - 1));
            if (a_sign != b_sign) {
                return @intFromBool(a_sign != 0 or @as(F_UINT, (a | b) << 1) == 0);
            } else {
                if (a_sign != 0) {
                    return @intFromBool(a >= b);
                } else {
                    return @intFromBool(a <= b);
                }
            }
        }

        pub fn lt_sf(a: F_UINT, b: F_UINT) i32 {
            if (isnan_sf(a) or isnan_sf(b)) {
                return 0;
            }
            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: u32 = @intCast(b >> (F_SIZE - 1));
            if (a_sign != b_sign) {
                return @intFromBool(a_sign != 0 and @as(F_UINT, (a | b) << 1) != 0);
            } else {
                if (a_sign != 0) {
                    return @intFromBool(a > b);
                } else {
                    return @intFromBool(a < b);
                }
            }
        }

        pub fn cmp_sf(a: F_UINT, b: F_UINT) i32 {
            if (isnan_sf(a) or isnan_sf(b)) {
                return 2;
            }
            const a_sign: i32 = @intCast(a >> (F_SIZE - 1));
            const b_sign: i32 = @intCast(b >> (F_SIZE - 1));
            if (a_sign != b_sign) {
                if (@as(F_UINT, (a | b) << 1) != 0)
                    return 1 - 2 * a_sign
                else
                    return 0;
            } else {
                if (a < b)
                    return 2 * a_sign - 1
                else if (a > b)
                    return 1 - 2 * a_sign
                else
                    return 0;
            }
        }

        pub fn fmod_sf(a: F_UINT, b: F_UINT) F_UINT {
            const a_abs = a & ~SIGN_MASK;
            const b_abs = b & ~SIGN_MASK;
            if (b_abs == 0 or
                a_abs >= (@as(F_UINT, EXP_MASK) << MANT_SIZE) or
                b_abs > (@as(F_UINT, EXP_MASK) << MANT_SIZE))
            {
                return F_QNAN;
            }
            if (a_abs < b_abs) {
                return a;
            } else if (a_abs == b_abs) {
                return a & SIGN_MASK;
            }

            const a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            var a_exp: i32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var b_exp: i32 = @intCast((b >> MANT_SIZE) & EXP_MASK);
            var a_mant = a & MANT_MASK;
            var b_mant = b & MANT_MASK;

            if (a_exp == 0) {
                a_mant = normalize_subnormal_sf(&a_exp, a_mant);
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            if (b_exp == 0) {
                b_mant = normalize_subnormal_sf(&b_exp, b_mant);
            } else {
                b_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            var n = a_exp - b_exp;
            if (a_mant >= b_mant)
                a_mant -= b_mant;
            while (n != 0) {
                a_mant <<= 1;
                if (a_mant >= b_mant)
                    a_mant -= b_mant;
                n -= 1;
            }
            return normalize_sf(a_sign, b_exp, a_mant << RND_SIZE, RM_RNE);
        }

        fn internal_cvt_sf_i(comptime ICVT_SIZE: u32, a: F_UINT, rm: c_int, is_unsigned: bool) std.meta.Int(.signed, ICVT_SIZE) {
            const ICVT_UINT = std.meta.Int(.unsigned, ICVT_SIZE);
            const ICVT_INT = std.meta.Int(.signed, ICVT_SIZE);
            var a_sign: u32 = @intCast(a >> (F_SIZE - 1));
            var a_exp: i32 = @intCast((a >> MANT_SIZE) & EXP_MASK);
            var a_mant = a & MANT_MASK;
            if (a_exp == EXP_MASK and a_mant != 0)
                a_sign = 0;
            if (a_exp == 0) {
                a_exp = 1;
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            a_mant <<= RND_SIZE;
            a_exp = a_exp - @as(i32, @intCast(EXP_MASK / 2)) - @as(i32, @intCast(MANT_SIZE));

            const r_max: ICVT_UINT = if (is_unsigned)
                @as(ICVT_UINT, a_sign) -% 1
            else
                (@as(ICVT_UINT, 1) << (ICVT_SIZE - 1)) - @as(ICVT_UINT, a_sign ^ 1);

            var r: ICVT_UINT = undefined;
            if (a_exp >= 0) {
                if (a_exp <= (@as(i32, ICVT_SIZE - 1) - @as(i32, @intCast(MANT_SIZE)))) {
                    r = @as(ICVT_UINT, @intCast(a_mant >> RND_SIZE)) << @intCast(a_exp);
                    if (r > r_max)
                        return @bitCast(r_max);
                } else {
                    return @bitCast(r_max);
                }
            } else {
                a_mant = rshift_rnd(a_mant, -a_exp);
                var addend: u32 = undefined;
                switch (rm) {
                    RM_RNE, RM_RMM => addend = (1 << (RND_SIZE - 1)),
                    RM_RTZ => addend = 0,
                    else => {
                        if ((a_sign ^ @as(u32, @intCast(rm & 1))) != 0)
                            addend = (1 << RND_SIZE) - 1
                        else
                            addend = 0;
                    },
                }
                const rnd_bits = a_mant & ((@as(F_UINT, 1) << RND_SIZE) - 1);
                a_mant = (a_mant + addend) >> RND_SIZE;
                if (rm == RM_RNE and rnd_bits == (@as(F_UINT, 1) << (RND_SIZE - 1)))
                    a_mant &= ~@as(F_UINT, 1);
                if (a_mant > r_max)
                    return @bitCast(r_max);
                r = @intCast(a_mant);
            }
            if (a_sign != 0)
                r = 0 -% r;
            return @as(ICVT_INT, @bitCast(r));
        }

        pub fn cvt_sf_i32(a: F_UINT, rm: c_int) i32 {
            return internal_cvt_sf_i(32, a, rm, false);
        }

        pub fn cvt_sf_i64(a: F_UINT, rm: c_int) i64 {
            return internal_cvt_sf_i(64, a, rm, false);
        }

        pub fn cvt_sf_u32(a: F_UINT, rm: c_int) u32 {
            return @bitCast(internal_cvt_sf_i(32, a, rm, true));
        }

        fn internal_cvt_i_sf(comptime ICVT_SIZE: u32, a_in: std.meta.Int(.signed, ICVT_SIZE), rm: c_int, is_unsigned: bool) F_UINT {
            const ICVT_UINT = std.meta.Int(.unsigned, ICVT_SIZE);
            var a_sign: u32 = undefined;
            var r: ICVT_UINT = undefined;
            if (!is_unsigned and a_in < 0) {
                a_sign = 1;
                r = 0 -% @as(ICVT_UINT, @bitCast(a_in));
            } else {
                a_sign = 0;
                r = @bitCast(a_in);
            }
            var a_exp: i32 = @as(i32, @intCast(EXP_MASK / 2)) + @as(i32, F_SIZE) - 2;
            const l: i32 = @as(i32, ICVT_SIZE) - @as(i32, @intCast(@clz(r))) - @as(i32, F_SIZE - 1);
            if (l > 0) {
                const mask = r & ((@as(ICVT_UINT, 1) << @intCast(l)) - 1);
                r = (r >> @intCast(l)) | @intFromBool((r & mask) != 0);
                a_exp += l;
            }
            const a_mant: F_UINT = @intCast(r);
            return normalize_sf(a_sign, a_exp, a_mant, rm);
        }

        pub fn cvt_i32_sf(a: i32, rm: c_int) F_UINT {
            return internal_cvt_i_sf(32, a, rm, false);
        }

        pub fn cvt_i64_sf(a: i64, rm: c_int) F_UINT {
            return internal_cvt_i_sf(64, a, rm, false);
        }

        pub fn cvt_u32_sf(a: u32, rm: c_int) F_UINT {
            return internal_cvt_i_sf(32, @bitCast(a), rm, true);
        }
    };
}

pub const sf32 = SoftFP(32);
pub const sf64 = SoftFP(64);

pub fn cvt_sf32_sf64(a: u32) u64 {
    var a_sign: u32 = undefined;
    var a_exp: i32 = undefined;
    var a_mant: u64 = sf32.unpack_sf(&a_sign, &a_exp, a);
    if (a_exp == 0xff) {
        if (a_mant != 0) {
            return sf64.F_QNAN;
        } else {
            return sf64.pack_sf(a_sign, sf64.EXP_MASK, 0);
        }
    }
    if (a_exp == 0) {
        if (a_mant == 0)
            return sf64.pack_sf(a_sign, 0, 0);
        a_mant = sf32.normalize_subnormal_sf(&a_exp, @intCast(a_mant));
    }
    a_exp = a_exp - 0x7f + @as(i32, @intCast(sf64.EXP_MASK / 2));
    a_mant <<= (sf64.MANT_SIZE - 23);
    return sf64.pack_sf(a_sign, @intCast(a_exp), a_mant);
}

pub fn cvt_sf64_sf32(a: u64, rm: c_int) u32 {
    var a_sign: u32 = undefined;
    var a_exp: i32 = undefined;
    var a_mant = sf64.unpack_sf(&a_sign, &a_exp, a);
    if (a_exp == sf64.EXP_MASK) {
        if (a_mant != 0) {
            return sf32.F_QNAN;
        } else {
            return sf32.pack_sf(a_sign, 0xff, 0);
        }
    }
    if (a_exp == 0) {
        if (a_mant == 0)
            return sf32.pack_sf(a_sign, 0, 0);
        // Match C: return value of normalize_subnormal_sf is discarded.
        _ = sf64.normalize_subnormal_sf(&a_exp, a_mant);
    } else {
        a_mant |= @as(u64, 1) << sf64.MANT_SIZE;
    }
    a_exp = a_exp - @as(i32, @intCast(sf64.EXP_MASK / 2)) + 0x7f;
    a_mant = sf64.rshift_rnd(a_mant, @as(i32, @intCast(sf64.MANT_SIZE)) - (32 - 2));
    return sf32.normalize_sf(a_sign, a_exp, @intCast(a_mant), rm);
}

pub export fn libm_cvt_sf64_i32(a: u64, rm: c_int) i32 {
    return sf64.cvt_sf_i32(a, rm);
}

pub export fn libm_fmod_sf64(a: u64, b: u64) u64 {
    return sf64.fmod_sf(a, b);
}

pub export fn libm_mul_u64(plow: *u64, a: u64, b: u64) u64 {
    return sf64.mul_u(plow, a, b);
}
