/*
 * SoftFP bridge for libm Zig port
 *
 * Copyright (c) 2024 Fabrice Bellard
 */
#ifndef LIBM_SOFTFP_H
#define LIBM_SOFTFP_H

#include <stdint.h>

typedef enum {
    LIBM_RM_RNE,
    LIBM_RM_RTZ,
    LIBM_RM_RDN,
    LIBM_RM_RUP,
    LIBM_RM_RMM,
    LIBM_RM_RMMUP,
} libm_rm_t;

int32_t libm_cvt_sf64_i32(uint64_t a, libm_rm_t rm);
uint64_t libm_fmod_sf64(uint64_t a, uint64_t b);
uint64_t libm_mul_u64(uint64_t *plow, uint64_t a, uint64_t b);

#endif /* LIBM_SOFTFP_H */
