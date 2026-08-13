# Deprecated: use `zig build -Doptimize=ReleaseFast` instead.
# This Makefile delegates common targets to the Zig build system.
# The legacy C-only rules below are broken (removed .c files) and kept for reference.

ZIG ?= zig
ZIG_BUILD=$(ZIG) build -Doptimize=ReleaseFast

.PHONY: all test microbench octane example mqjs clean legacy

all: mqjs example

mqjs example:
	$(ZIG_BUILD) $(@)

test:
	$(ZIG_BUILD) test

microbench:
	$(ZIG_BUILD) microbench

octane:
	$(ZIG_BUILD) octane

clean:
	rm -rf zig-out zig-cache .zig-cache
	rm -f *.o *.d *~ tests/*.o tests/*.d tests/*~ test_builtin.bin \
		mqjs_stdlib mqjs_stdlib.h mquickjs_build_atoms mquickjs_atom.h \
		mqjs_example example_stdlib example_stdlib.h dtoa_test libm_test rempio2_test

# --- Legacy C build (broken; do not use) ---

#CONFIG_PROFILE=y
#CONFIG_X86_32=y
#CONFIG_ARM32=y
#CONFIG_WIN32=y
#CONFIG_SOFTFLOAT=y
#CONFIG_ASAN=y
#CONFIG_GPROF=y
CONFIG_SMALL=y
# consider warnings as errors (for development)
#CONFIG_WERROR=y

ifdef CONFIG_ARM32
CROSS_PREFIX=arm-linux-gnu-
endif

ifdef CONFIG_WIN32
  ifdef CONFIG_X86_32
    CROSS_PREFIX?=i686-w64-mingw32-
  else
    CROSS_PREFIX?=x86_64-w64-mingw32-
  endif
  EXE=.exe
else
  CROSS_PREFIX?=
  EXE=
endif

HOST_CC=gcc
CC=$(CROSS_PREFIX)gcc
CFLAGS=-Wall -g -MMD -D_GNU_SOURCE -fno-math-errno -fno-trapping-math
HOST_CFLAGS=-Wall -g -MMD -D_GNU_SOURCE -fno-math-errno -fno-trapping-math
ifdef CONFIG_WERROR
CFLAGS+=-Werror
HOST_CFLAGS+=-Werror
endif
ifdef CONFIG_ARM32
CFLAGS+=-mthumb
endif
ifdef CONFIG_SMALL
CFLAGS+=-Os
else
CFLAGS+=-O2
endif
ifdef CONFIG_SOFTFLOAT
CFLAGS+=-msoft-float
CFLAGS+=-DUSE_SOFTFLOAT
endif
HOST_CFLAGS+=-O2
LDFLAGS=-g
HOST_LDFLAGS=-g

legacy:
	$(error The legacy C Makefile build is broken. Use: zig build -Doptimize=ReleaseFast)
