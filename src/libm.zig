//
// Tiny Math Library
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

//
// ====================================================
// Copyright (C) 2004 by Sun Microsystems, Inc. All rights reserved.
//
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice 
// is preserved.
// ====================================================
//

// USE_TAN_SHORTCUT - use less code for tan() but currently less precise

// TODO:
// - smaller scalbn implementation ?
// - add all ES6 math functions

// tc32: 
//    - base: size libm+libgcc: 21368
//    - size libm+libgcc: 11832
// 
//    x86:
//    - size libm softfp: 18510
//    - size libm hardfp: 10051
// 
//    TODO:
//    - unify i32 bit and i64 bit conversions
//    - unify comparisons operations

const std = @import("std");
const math = std.math;

const cutils = @import("./cutils.zig");
const softfp_template = @import("./softfp_template.zig");

pub const RoundingModeEnum = enum(u3) {
    RNE = 0, // Round to Nearest, ties to Even
    RTZ = 1, // Round towards Zero
    RDN = 2, // Round Down (must be even)
    RUP = 3, // Round Up (must be odd) 
    RMM = 4, // Round to Nearest, ties to Max Magnitude
    RMMUP = 5, // only for rint_sf64(): round to nearest, ties to +inf (must be odd)
};

pub const FFLAG = struct {
    pub const INVALID_OP: u8 = 1 << 4;
    pub const DIVIDE_ZERO: u8 = 1 << 3;
    pub const OVERFLOW: u8 = 1 << 2;
    pub const UNDERFLOW: u8 = 1 << 1;
    pub const INEXACT: u8 = 1 << 0;
};

pub const SoftFPMinMaxTypeEnum = enum(u2) {
    FMINMAX_PROP = 0, // min(1, qNaN/sNaN) -> qNaN
    FMINMAX_IEEE754_2008 = 1, // min(1, qNaN) -> 1, min(1, sNaN) -> qNaN
    FMINMAX_IEEE754_201X = 2, // min(1, qNaN/sNaN) -> 1
};

const sfloat32 = u32;
const sfloat64 = u64;

const F_USE_FFLAGS = 0;

const F_SIZE = 32;
const F_NORMALIZE_ONLY = true;
const include = comptime softfp_template.template(
   F_SIZE,  F_USE_FFLAGS, F_NORMALIZE_ONLY
);

const F_SIZE = 64;
const include = comptime softfp_template.template(
   F_SIZE,  F_USE_FFLAGS, F_NORMALIZE_ONLY
);


int32_t js_lrint(double a)
{
    return cvt_sf64_i32(float64_as_uint64(a), RM_RNE);
}

double js_fmod(double a, double b)
{
    return uint64_as_float64(fmod_sf64(float64_as_uint64(a), float64_as_uint64(b)));
}

// supported rounding modes: RM_UP, RM_DN, RM_RTZ, RM_RMMUP, RM_RMM
static double rint_sf64(double a, RoundingModeEnum rm)
{
    uint64_t u = float64_as_uint64(a);
    uint64_t frac_mask, one, m, addend;
    int e;
    unsigned int s;

    e = ((u >> 52) & 0x7ff) - 0x3ff;
    s = u >> 63;
    if (e < 0) {
        m = u & (((uint64_t)1 << 52) - 1);
        if (e == -0x3ff && m == 0) {
            /* zero: nothing to do */
        } else {
            /* abs(a) < 1 */
            s = u >> 63;
            one = (uint64_t)0x3ff << 52;
            u = 0;
            switch(rm) {
            case RM_RUP:
            case RM_RDN:
                if (s ^ (rm & 1))
                    u = one;
                break;
            default:
            case RM_RMM:
            case RM_RMMUP:
                if (e == -1 && (m != 0 || (m == 0 && (!s || rm == RM_RMM))))
                    u = one;
                break;
            case RM_RTZ:
                break;
            }
            u |= (uint64_t)s << 63;
        }
    } else if (e < 52) {
        one = (uint64_t)1 << (52 - e);
        frac_mask = one - 1;
        addend = 0;
        switch(rm) {
        case RM_RMMUP:
            addend = (one >> 1) - s;
            break;
        default:
        case RM_RMM:
            addend = (one >> 1);
            break;
        case RM_RTZ:
            break;
        case RM_RUP:
        case RM_RDN:
            if (s ^ (rm & 1))
                addend = one - 1;
            break;
        }
        u += addend;
        u &= ~frac_mask; /* truncate to an integer */
    }
    /* otherwise: abs(a) >= 2^52, or NaN, +/-Infinity: no change */
    return uint64_as_float64(u);
}

double js_floor(double x)
{
    return rint_sf64(x, RM_RDN);
}

double js_ceil(double x)
{
    return rint_sf64(x, RM_RUP);
}

double js_trunc(double x)
{
    return rint_sf64(x, RM_RTZ);
}

double js_round_inf(double x)
{
    return rint_sf64(x, RM_RMMUP);
}

double js_fabs(double x)
{
    uint64_t a = float64_as_uint64(x);
    return uint64_as_float64(a & 0x7fffffffffffffff);
}

double js_scalbn(double x, int n);
double js_floor(double x);
double js_ceil(double x);
double js_trunc(double x);
double js_round_inf(double a);
double js_fabs(double x);
double js_sqrt(double x);
int32_t js_lrint(double a);
double js_fmod(double x, double y);
double js_sin(double x);
double js_cos(double x);
double js_tan(double x);
double js_acos(double x);
double js_asin(double x);
double js_atan(double x);
double js_atan2(double y, double x);
double js_exp(double x);
double js_log(double x);
double js_log2(double x);
double js_log10(double x);
double js_pow(double x, double y);
/* exported only for tests */
int js_rem_pio2(double x, double *y);
