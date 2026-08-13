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

const std = @import("std");
const softfp_template_icvt = @import("./softfp_template_icvt.zig");

/// Returns a structure containing floating-point parameters for a given bit-size.
pub fn FloatParams(comptime F_SIZE: u32) type {
    return struct {
        pub const F_UINT = std.meta.Int(.unsigned, F_SIZE);
        
        pub const F_ULONG = switch (F_SIZE) {
            32 => u64,
            64 => u128,
            128 => @compileError("F_ULONG for 128-bit float not defined"),
            else => @compileError("Unsupported F_SIZE"),
        };

        pub const MANT_SIZE: u32 = switch (F_SIZE) {
            32  => 23,
            64  => 52,
            128 => 112,
            else => @compileError("Unsupported F_SIZE"),
        };

        pub const EXP_SIZE: u32 = F_SIZE - MANT_SIZE - 1;

        // Logic for UHALF and ULONG (equivalent to C's #if ladder)
        pub const F_UHALF = switch (F_SIZE) {
            32 => void, // 32-bit doesn't define UHALF in your C code
            64 => u32,
            128 => u64,
            else => @compileError("Unsupported F_SIZE"),
        };        
    };
}

const template_internal_cvt_sfF_SIZE_i32 = softfp_template_icvt.template_internal_cvt_sfF_SIZE_iICVT_SIZE(32);
const template_internal_cvt_sfF_SIZE_i64 = softfp_template_icvt.template_internal_cvt_sfF_SIZE_iICVT_SIZE(64);

inline fn template_rshift_rnd(
    comptime F_SIZE: comptime_int,
    comptime F_UINT: type,
) fn(a: F_UINT, d: i32) F_UINT {
    return struct { fn func(a: F_UINT, d: i32) F_UINT {
        var mask: F_UINT = undefined;
        if (d != 0) {
            if (d >= F_SIZE) {
                a = (a != 0);
            } else {
                mask = (@as(F_UINT, 1) << d) - 1;
                a = (a >> d) | ((a & mask) != 0);
            }
        }
        return a;
    }}.func;
}

// #if F_SIZE == 32
// #define F_UINT uint32_t
// #define F_ULONG uint64_t
// #define MANT_SIZE 23
// #define EXP_SIZE 8
// #elif F_SIZE == 64
// #define F_UHALF uint32_t
// #define F_UINT uint64_t
// #ifdef HAVE_INT128
// #define F_ULONG uint128_t
// #endif
// #define MANT_SIZE 52
// #define EXP_SIZE 11
// #elif F_SIZE == 128
// #define F_UHALF uint64_t
// #define F_UINT uint128_t
// #define MANT_SIZE 112
// #define EXP_SIZE 15
// #else
// #error unsupported F_SIZE
// #endif

// #define EXP_MASK ((1 << EXP_SIZE) - 1)
// #define MANT_MASK (((F_UINT)1 << MANT_SIZE) - 1)
// #define SIGN_MASK ((F_UINT)1 << (F_SIZE - 1))
// #define IMANT_SIZE (F_SIZE - 2) /* internal mantissa size */
// #define RND_SIZE (IMANT_SIZE - MANT_SIZE)
// #define QNAN_MASK ((F_UINT)1 << (MANT_SIZE - 1))
// #define EXP_BIAS ((1 << (EXP_SIZE - 1)) - 1)

