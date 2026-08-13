//
// SoftFP Library
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

const libm = @import("./libm.zig");
const RoundingModeEnum = libm.RoundingModeEnum;
const FFLAG = libm.FFLAG;

const softfp_template = @import("./softfp_template.zig");

inline fn template(
    comptime F_SIZE: comptime_int,
    comptime ICVT_SIZE: comptime_int,
    comptime ICVT_UINT: type,
    comptime ICVT_INT: type,
    comptime FFLAGS_PARAM: void,
    comptime F_UINT: type,
    comptime MANT_SIZE: comptime_int,
    comptime EXP_MASK: comptime_int,
    comptime MANT_MASK: comptime_int,
    comptime RND_SIZE: comptime_int,
) struct {
    // pfflags arg is "optional" when FFLAGS_PARAM is not defined
    internal_cvt_sf__F_SIZE___i__ICVT_SIZE__: fn(a: F_UINT, rm: RoundingModeEnum, is_unsigned: bool, pfflags: ?*u32) ICVT_INT,
    cvt_sf__F_SIZE___i__ICVT_SIZE__: fn(a: F_UINT, rm: RoundingModeEnum, pfflags: ?*u32) ICVT_INT,
    cvt_sf__F_SIZE___u__ICVT_SIZE__: fn(a: F_UINT, rm: RoundingModeEnum, pfflags: ?*u32) ICVT_UINT,
    internal_cvt_i__ICVT_SIZE___sf__F_SIZE__: fn(a: ICVT_INT, rm: RoundingModeEnum, is_unsigned: bool, pfflags: ?*u32) F_UINT,
    cvt_i__ICVT_SIZE___sf__F_SIZE__: fn(a: ICVT_INT, rm: RoundingModeEnum, pfflags: ?*u32) F_UINT
} {
    // overflow:
    //     #if F_USE_FFLAGS
    //         *pfflags |= FFLAG_INVALID_OP;
    //     #endif            
    //         return r_max;

    return struct {
        fn internal_cvt_sf__F_SIZE___i__ICVT_SIZE__(
            a: F_UINT, rm: RoundingModeEnum, is_unsigned: bool, pfflags: ?*u32
        ) ICVT_INT {
            var a_sign: u32 = a >> (F_SIZE - 1);
            var a_exp: i32 = (a >> MANT_SIZE) & EXP_MASK;
            var a_mant: F_UINT = a & MANT_MASK;
            if (a_exp == EXP_MASK and a_mant != 0)
                a_sign = 0; // NaN is like +infinity
            if (a_exp == 0) {
                a_exp = 1;
            } else {
                a_mant |= @as(F_UINT, 1) << MANT_SIZE;
            }
            a_mant <<= RND_SIZE;
            a_exp = a_exp - (EXP_MASK / 2) - MANT_SIZE;

            var r_max: ICVT_UINT = undefined;
            if (is_unsigned) {
                r_max = @as(ICVT_UINT, a_sign) - 1;
            } else {
                r_max = (@as(ICVT_UINT, 1) << (ICVT_SIZE - 1)) - @as(ICVT_UINT, a_sign ^ 1);
            }

            var r: ICVT_UINT = undefined;
            if (a_exp >= 0) {
                if (a_exp <= (ICVT_SIZE - 1 - MANT_SIZE)) {
                    r = (ICVT_UINT)(a_mant >> RND_SIZE) << a_exp;
                    if (r > r_max) {
                        if (libm.F_USE_FFLAGS) {
                            pfflags.* |= FFLAG.INVALID_OP;
                        }
                        return r_max;
                    }
                } else {
                    if (libm.F_USE_FFLAGS) {
                        pfflags.* |= FFLAG.INVALID_OP;
                    }
                    return r_max;
                }
            } else {
                var addend: u32 = undefined;

                a_mant = softfp_template.template_rshift_rnd(F_SIZE, F_UINT)(a_mant, -a_exp);

                switch (rm) {
                    .RM_RNE, .RM_RMM => {
                        addend = (1 << (RND_SIZE - 1));
                    },
                    .RM_RTZ => {
                        addend = 0;
                    },
                    // .RM_RDN, .RM_RUP, else =>
                    else => {
                        if (a_sign ^ (rm & 1)) {
                            addend = (1 << RND_SIZE) - 1;
                        } else {
                            addend = 0;
                        }
                    }
                }
                
                const rnd_bits: u32 = a_mant & ((1 << RND_SIZE ) - 1);
                a_mant = (a_mant + addend) >> RND_SIZE;
                // half way: select even result
                if (rm == RoundingModeEnum.RM_RNE and rnd_bits == (1 << (RND_SIZE - 1)))
                    a_mant &= ~1;
                if (a_mant > r_max) {
                    if (libm.F_USE_FFLAGS) {
                        pfflags.* |= FFLAG.INVALID_OP;
                    }
                    return r_max;
                }
                r = a_mant;
                if (libm.F_USE_FFLAGS) {
                    if (rnd_bits != 0) {
                        pfflags.* |= FFLAG.INEXACT;
                    }
                }      
            }

            if (a_sign) {
                r = -r;
            }

            return r;
        }

        fn cvt_sf__F_SIZE___i__ICVT_SIZE__(a: F_UINT, rm: RoundingModeEnum, pfflags: ?*u32) ICVT_INT {
            return internal_cvt_sf__F_SIZE___i__ICVT_SIZE__(
                a, rm, false, if (FFLAGS_PARAM) pfflags else null
            );
        }

        fn cvt_sf__F_SIZE___u__ICVT_SIZE__(a: F_UINT, rm: RoundingModeEnum, pfflags: ?*u32) ICVT_UINT {
            return internal_cvt_sf__F_SIZE___i__ICVT_SIZE__(
                a, rm, true, if (FFLAGS_PARAM) pfflags else null
            );
        }

        // conversions between float and integers
        fn internal_cvt_i__ICVT_SIZE___sf__F_SIZE__(a: ICVT_INT, rm: RoundingModeEnum, is_unsigned: bool, pfflags: ?*u32) F_UINT {
            var a_sign: u32 = undefined;
            var r: ICVT_UINT = undefined;

            if (!is_unsigned and a < 0) {
                a_sign = 1;
                r = -@as(ICVT_UINT, a);
            } else {
                a_sign = 0;
                r = a;
            }

            var a_exp: i32 = (EXP_MASK / 2) + F_SIZE - 2;
            // need to reduce range before generic float normalization
            var l: i32 = ICVT_SIZE - glue(clz, ICVT_SIZE)(r) - (F_SIZE - 1);
            var mask: ICVT_UINT = undefined;

            if (l > 0) {
                mask = r & ((@as(ICVT_UINT, 1) << l) - 1);
                r = (r >> l) | ((r & mask) != 0);
                a_exp += l;
            }

            const a_mant: F_UINT = r;
            return normalize_sf(a_sign, a_exp, a_mant, rm, if (FFLAGS_PARAM) pfflags else null);
        }

        fn cvt_i__ICVT_SIZE___sf__F_SIZE__(a: ICVT_INT, rm: RoundingModeEnum, pfflags: ?*u32) F_UINT {
            return internal_cvt_i__ICVT_SIZE___sf__F_SIZE__(a, rm, false, if (FFLAGS_PARAM) pfflags else null);
        }

        fn cvt_u__ICVT_SIZE___sf__F_SIZE__(a: ICVT_UINT, rm: RoundingModeEnum, pfflags: ?*u32) F_UINT {
            return internal_cvt_i__ICVT_SIZE___sf__F_SIZE__(a, rm, true, if (FFLAGS_PARAM) pfflags else null);
        }
    };
}

// #undef ICVT_SIZE
// #undef ICVT_INT
// #undef ICVT_UINT
