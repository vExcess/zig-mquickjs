const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdarg.h");
});

pub fn term_printf(fmt: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    const c_ap: [*c]c.struct___va_list_tag_1 = @ptrCast(&ap);
    _ = c.vprintf(fmt, c_ap);
    @cVaEnd(&ap);
}

pub fn term_flush() void {
    _= c.fflush(c.stdout);
}