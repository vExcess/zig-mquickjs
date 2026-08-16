const builtin = @import("builtin");
const std = @import("std");

pub fn abort() noreturn {
    if (builtin.os.tag == .freestanding) {
        @trap();
    } else {
        std.posix.abort();
    }
}
