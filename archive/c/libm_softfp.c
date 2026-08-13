/*
 * SoftFP bridge for libm Zig port
 *
 * Copyright (c) 2024 Fabrice Bellard
 */
#define NDEBUG
#include <stdint.h>
#include <assert.h>
#include "cutils.h"
#include "libm_softfp.h"

typedef enum {
    RM_RNE,
    RM_RTZ,
    RM_RDN,
    RM_RUP,
    RM_RMM,
    RM_RMMUP,
} RoundingModeEnum;

#define F_STATIC static __maybe_unused
#define F_USE_FFLAGS 0

#define F_SIZE 32
#define F_NORMALIZE_ONLY
#include "softfp_template.h"

#define F_SIZE 64
#include "softfp_template.h"

int32_t libm_cvt_sf64_i32(uint64_t a, libm_rm_t rm)
{
    return cvt_sf64_i32(a, (RoundingModeEnum)rm);
}

uint64_t libm_fmod_sf64(uint64_t a, uint64_t b)
{
    return fmod_sf64(a, b);
}

uint64_t libm_mul_u64(uint64_t *plow, uint64_t a, uint64_t b)
{
    return mul_u64(plow, a, b);
}
