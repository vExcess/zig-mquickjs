//
// Micro QuickJS REPL
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
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
const posix = std.posix;
const ascii = std.ascii;
const cutils = @import("cutils_lib.zig");

const BOOL = cutils.BOOL;
const TRUE: BOOL = cutils.TRUE;
const FALSE: BOOL = cutils.FALSE;

const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("ctype.h");
    @cInclude("errno.h");
    @cInclude("sys/time.h");
    @cInclude("readline.h");
    @cInclude("readline_tty.h");
    @cInclude("mquickjs.h");
});

const stdlib_data = @import("mqjs_stdlib_data");

const MAX_TIMERS = 16;
const MAX_INCLUDES = 32;

const COLOR_NONE = 0;
const COLOR_WHITE = 8;
const COLOR_GREEN = 3;
const COLOR_CYAN = 7;
const COLOR_RED = 2;
const COLOR_BRIGHT_GREEN = 11;
const COLOR_BRIGHT_CYAN = 15;
const COLOR_BRIGHT_WHITE = 16;
const COLOR_BRIGHT_YELLOW = 12;
const COLOR_BRIGHT_MAGENTA = 14;
const COLOR_BRIGHT_RED = 10;

const STYLE_DEFAULT = COLOR_BRIGHT_GREEN;
const STYLE_COMMENT = COLOR_WHITE;
const STYLE_STRING = COLOR_BRIGHT_CYAN;
const STYLE_REGEX = COLOR_CYAN;
const STYLE_NUMBER = COLOR_GREEN;
const STYLE_KEYWORD = COLOR_BRIGHT_WHITE;
const STYLE_FUNCTION = COLOR_BRIGHT_YELLOW;
const STYLE_TYPE = COLOR_BRIGHT_MAGENTA;
const STYLE_IDENTIFIER = COLOR_BRIGHT_GREEN;
const STYLE_ERROR = COLOR_RED;
const STYLE_RESULT = COLOR_BRIGHT_WHITE;
const STYLE_ERROR_MSG = COLOR_BRIGHT_RED;

const js_keywords =
    "break|case|catch|continue|debugger|default|delete|do|" ++
    "else|finally|for|function|if|in|instanceof|new|" ++
    "return|switch|this|throw|try|typeof|while|with|" ++
    "class|const|enum|import|export|extends|super|" ++
    "implements|interface|let|package|private|protected|" ++
    "public|static|yield|" ++
    "undefined|null|true|false|Infinity|NaN|" ++
    "eval|arguments|" ++
    "await|";

const js_types = "void|var|";

const JSTimer = extern struct {
    allocated: BOOL,
    func: c.JSGCRef,
    timeout: i64,
};

var js_timer_list: [MAX_TIMERS]JSTimer = [_]JSTimer{.{ .allocated = FALSE, .func = .{ .val = 0, .prev = null }, .timeout = 0 }} ** MAX_TIMERS;
var js_log_err_flag: c_int = 0;

var readline_state: c.ReadlineState = undefined;
var readline_cmd_buf: [256]u8 = undefined;
var readline_kill_buf: [256]u8 = undefined;
var readline_history: [512]u8 = undefined;

fn throwTypeError(ctx: *c.JSContext, comptime msg: [:0]const u8) c.JSValue {
    return c.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn throwInternalError(ctx: *c.JSContext, comptime msg: [:0]const u8) c.JSValue {
    return c.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, msg);
}

fn getTimeMs() i64 {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        const ts = posix.clock_gettime(posix.CLOCK.MONOTONIC) catch unreachable;
        return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1_000_000);
    }
    var tv: c.struct_timeval = undefined;
    _ = c.gettimeofday(&tv, null);
    return @as(i64, @intCast(tv.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(tv.tv_usec)), 1000);
}

fn getDateMs() i64 {
    var tv: c.struct_timeval = undefined;
    _ = c.gettimeofday(&tv, null);
    return @as(i64, @intCast(tv.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(tv.tv_usec)), 1000);
}

fn loadFile(filename: [*:0]const u8, plen: ?*c_int) [*]u8 {
    const f = c.fopen(filename, "rb");
    if (f == null) {
        _ = c.perror(filename);
        std.process.exit(1);
    }
    _ = c.fseek(f, 0, c.SEEK_END);
    const buf_len: c_int = @intCast(c.ftell(f));
    _ = c.fseek(f, 0, c.SEEK_SET);
    const buf: [*]u8 = @ptrCast(c.malloc(@intCast(buf_len + 1)));
    if (c.fread(buf, 1, @intCast(buf_len), f) != @as(usize, @intCast(buf_len))) {
        _ = c.printf("not read %d bytes\n", buf_len);
        std.process.exit(1);
    }
    buf[@intCast(buf_len)] = 0;
    _ = c.fclose(f);
    if (plen) |p| p.* = buf_len;
    return buf;
}

fn jsLogFunc(opaque_ptr: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) callconv(.c) void {
    _ = opaque_ptr;
    const out = if (js_log_err_flag != 0) c.stderr else c.stdout;
    _ = c.fwrite(buf, 1, buf_len, out);
}

fn dumpError(ctx: *c.JSContext) void {
    const obj = c.JS_GetException(ctx);
    const use_color = posix.isatty(posix.STDERR_FILENO);
    if (use_color) {
        _ = c.fprintf(c.stderr, "%s", c.term_colors[@intCast(STYLE_ERROR_MSG)]);
    }
    js_log_err_flag += 1;
    c.JS_PrintValueF(ctx, obj, c.JS_DUMP_LONG);
    js_log_err_flag -= 1;
    if (use_color) {
        _ = c.fprintf(c.stderr, "%s\n", c.term_colors[@intCast(COLOR_NONE)]);
    } else {
        _ = c.fputc('\n', c.stderr);
    }
}

export fn js_print(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        if (i != 0)
            _ = c.putchar(' ');
        const v = argv[@intCast(i)];
        if (c.JS_IsString(ctx, v) != 0) {
            var buf: c.JSCStringBuf = undefined;
            var len: usize = undefined;
            const str = c.JS_ToCStringLen(ctx, &len, v, &buf);
            _ = c.fwrite(str, 1, len, c.stdout);
        } else {
            c.JS_PrintValueF(ctx, argv[@intCast(i)], c.JS_DUMP_LONG);
        }
    }
    _ = c.putchar('\n');
    return c.JS_UNDEFINED;
}

export fn js_gc(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    c.JS_GC(ctx);
    return c.JS_UNDEFINED;
}

export fn js_date_constructor(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    var arg_count = argc;
    arg_count &= ~c.FRAME_CF_CTOR;
    var val: f64 = undefined;
    if (arg_count == 0) {
        val = @floatFromInt(getDateMs());
    } else if (arg_count == 1 and c.JS_IsNumber(ctx, argv[0]) != 0) {
        if (c.JS_ToNumber(ctx, &val, argv[0]) != 0)
            return c.JS_EXCEPTION;
    } else {
        return throwTypeError(ctx, "unsupported Date() parameter");
    }
    return c.JS_NewDate(ctx, val);
}

export fn js_date_now(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_NewInt64(ctx, getDateMs());
}

export fn js_performance_now(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_NewInt64(ctx, getTimeMs());
}

export fn js_load(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    var buf_str: c.JSCStringBuf = undefined;
    const filename = c.JS_ToCString(ctx, argv[0], &buf_str) orelse return c.JS_EXCEPTION;
    var buf_len: c_int = undefined;
    const buf = loadFile(filename, &buf_len);
    const ret = c.JS_Eval(ctx, @ptrCast(buf), @intCast(buf_len), filename, 0);
    c.free(buf);
    return ret;
}

export fn js_setTimeout(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    if (c.JS_IsFunction(ctx, argv[0]) == 0)
        return throwTypeError(ctx, "not a function");
    var delay: c_int = undefined;
    if (c.JS_ToInt32(ctx, &delay, argv[1]) != 0)
        return c.JS_EXCEPTION;
    var i: usize = 0;
    while (i < MAX_TIMERS) : (i += 1) {
        const th = &js_timer_list[i];
        if (th.allocated == FALSE) {
            const pfunc = c.JS_AddGCRef(ctx, &th.func);
            pfunc.* = argv[0];
            th.timeout = getTimeMs() + delay;
            th.allocated = TRUE;
            return c.JS_NewInt32(ctx, @intCast(i));
        }
    }
    return throwInternalError(ctx, "too many timers");
}

export fn js_clearTimeout(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    var timer_id: c_int = undefined;
    if (c.JS_ToInt32(ctx, &timer_id, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (timer_id >= 0 and timer_id < MAX_TIMERS) {
        const th = &js_timer_list[@intCast(timer_id)];
        if (th.allocated != FALSE) {
            c.JS_DeleteGCRef(ctx, &th.func);
            th.allocated = FALSE;
        }
    }
    return c.JS_UNDEFINED;
}

fn runTimers(ctx: *c.JSContext) void {
    while (true) {
        var min_delay: i64 = 1000;
        const cur_time = getTimeMs();
        var has_timer = FALSE;
        var i: usize = 0;
        while (i < MAX_TIMERS) : (i += 1) {
            const th = &js_timer_list[i];
            if (th.allocated != FALSE) {
                has_timer = TRUE;
                const delay = th.timeout - cur_time;
                if (delay <= 0) {
                    if (c.JS_StackCheck(ctx, 2) != 0) {
                        dumpError(ctx);
                        std.process.exit(1);
                    }
                    c.JS_PushArg(ctx, th.func.val);
                    c.JS_PushArg(ctx, c.JS_NULL);
                    c.JS_DeleteGCRef(ctx, &th.func);
                    th.allocated = FALSE;
                    const ret = c.JS_Call(ctx, 0);
                    if (c.JS_IsException(ret) != 0) {
                        dumpError(ctx);
                        std.process.exit(1);
                    }
                    min_delay = 0;
                    break;
                } else if (delay < min_delay) {
                    min_delay = delay;
                }
            }
        }
        if (has_timer == FALSE)
            break;
        if (min_delay > 0) {
            const sec: u64 = @intCast(@divTrunc(min_delay, 1000));
            const nsec: u64 = @intCast(@mod(min_delay, 1000) * 1_000_000);
            posix.nanosleep(sec, nsec);
        }
    }
}

export fn readline_find_completion(cmdline: [*:0]const u8) void {
    _ = cmdline;
}

fn isWord(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= 'a' and ch <= 'z') or
        ch == '_' or ch == '$';
}

fn findKeyword(buf: [*]const u8, buf_len: usize, dict: [:0]const u8) bool {
    var p: usize = 0;
    while (p < dict.len) {
        const rest = dict[p..];
        if (std.mem.indexOfScalar(u8, rest, '|')) |pipe| {
            const len = pipe;
            if (len == buf_len and std.mem.eql(u8, rest[0..len], buf[0..buf_len]))
                return true;
            p += len + 1;
        } else break;
    }
    return false;
}

fn termGetColor(plen: [*c]c_int, buf: [*c]const u8, pos: c_int, buf_len: c_int) callconv(.c) c_int {
    const c_pos: usize = @intCast(pos);
    const c_buf_len: usize = @intCast(buf_len);
    if (c_pos >= c_buf_len)
        return STYLE_DEFAULT;
    const ch = buf[c_pos];
    var pos1: usize = undefined;
    var len: c_int = undefined;
    var color: c_int = undefined;

    if (ch == '"' or ch == '\'') {
        pos1 = c_pos + 1;
        while (pos1 < c_buf_len and buf[pos1] != ch) {
            if (buf[pos1] == '\\' and pos1 + 1 < c_buf_len)
                pos1 += 2
            else
                pos1 += 1;
        }
        if (pos1 < c_buf_len)
            pos1 += 1;
        len = @intCast(pos1 - c_pos);
        color = STYLE_STRING;
    } else if (ch == '/' and c_pos + 1 < c_buf_len and buf[c_pos + 1] == '*') {
        pos1 = c_pos + 2;
        while (pos1 < c_buf_len and !(buf[pos1] == '*' and pos1 + 1 < c_buf_len and buf[pos1 + 1] == '/')) {
            pos1 += 1;
        }
        if (pos1 < c_buf_len)
            pos1 += 2;
        len = @intCast(pos1 - c_pos);
        color = STYLE_COMMENT;
    } else if ((ch >= '0' and ch <= '9') or ch == '.') {
        pos1 = c_pos + 1;
        while (pos1 < c_buf_len and isWord(buf[pos1]))
            pos1 += 1;
        len = @intCast(pos1 - c_pos);
        color = STYLE_NUMBER;
    } else if (isWord(ch)) {
        pos1 = c_pos + 1;
        while (pos1 < c_buf_len and isWord(buf[pos1]))
            pos1 += 1;
        len = @intCast(pos1 - c_pos);
        if (findKeyword(buf + c_pos, pos1 - c_pos, js_keywords)) {
            color = STYLE_KEYWORD;
        } else {
            while (pos1 < c_buf_len and buf[pos1] == ' ')
                pos1 += 1;
            if (pos1 < c_buf_len and buf[pos1] == '(') {
                color = STYLE_FUNCTION;
            } else if (findKeyword(buf + c_pos, pos1 - c_pos, js_types)) {
                color = STYLE_TYPE;
            } else {
                color = STYLE_IDENTIFIER;
            }
        }
    } else {
        color = STYLE_DEFAULT;
        len = 1;
    }
    plen.* = len;
    return color;
}

fn jsInterruptHandler(ctx: ?*c.JSContext, opaque_ptr: ?*anyopaque) callconv(.c) c_int {
    _ = ctx;
    _ = opaque_ptr;
    return c.readline_is_interrupted();
}

fn evalBuf(ctx: *c.JSContext, eval_str: [*:0]const u8, filename: [*:0]const u8, is_repl: BOOL, parse_flags: c_int) c_int {
    var flags = parse_flags;
    if (is_repl != FALSE)
        flags |= c.JS_EVAL_RETVAL | c.JS_EVAL_REPL;
    var val = c.JS_Parse(ctx, eval_str, c.strlen(eval_str), filename, flags);
    if (c.JS_IsException(val) != 0) {
        dumpError(ctx);
        return 1;
    }

    val = c.JS_Run(ctx, val);
    if (c.JS_IsException(val) != 0) {
        dumpError(ctx);
        return 1;
    }
    if (is_repl != FALSE) {
        _ = c.printf("%s", c.term_colors[@intCast(STYLE_RESULT)]);
        c.JS_PrintValueF(ctx, val, c.JS_DUMP_LONG);
        _ = c.printf("%s\n", c.term_colors[@intCast(COLOR_NONE)]);
    }
    return 0;
}

fn evalFile(
    ctx: *c.JSContext,
    filename: [*:0]const u8,
    argc: c_int,
    argv: ?[*]const [*:0]const u8,
    parse_flags: c_int,
    allow_bytecode: BOOL,
) c_int {
    var buf_len: c_int = undefined;
    const buf = loadFile(filename, &buf_len);
    var val: c.JSValue = undefined;
    if (allow_bytecode != FALSE and c.JS_IsBytecode(buf, @intCast(buf_len)) != 0) {
        if (c.JS_RelocateBytecode(ctx, buf, @intCast(buf_len)) != 0) {
            _ = c.fprintf(c.stderr, "Could not relocate bytecode\n");
            std.process.exit(1);
        }
        val = c.JS_LoadBytecode(ctx, buf);
    } else {
        val = c.JS_Parse(ctx, @ptrCast(buf), @intCast(buf_len), filename, parse_flags);
    }
    if (c.JS_IsException(val) != 0) {
        dumpError(ctx);
        c.free(buf);
        return 1;
    }

    if (argc > 0) {
        var val_ref: c.JSGCRef = undefined;
        _ = c.JS_PushGCRef(ctx, &val_ref);
        val_ref.val = val;

        var arr_ref: c.JSGCRef = undefined;
        const arr = c.JS_NewArray(ctx, argc);
        _ = c.JS_PushGCRef(ctx, &arr_ref);
        arr_ref.val = arr;

        var i: c_int = 0;
        while (i < argc) : (i += 1) {
            _ = c.JS_SetPropertyUint32(ctx, arr_ref.val, @intCast(i), c.JS_NewString(ctx, argv.?[@intCast(i)]));
        }
        arr_ref.val = c.JS_PopGCRef(ctx, &arr_ref);

        const obj = c.JS_GetGlobalObject(ctx);
        _ = c.JS_SetPropertyStr(ctx, obj, "scriptArgs", arr_ref.val);

        val = c.JS_PopGCRef(ctx, &val_ref);
    }

    val = c.JS_Run(ctx, val);
    if (c.JS_IsException(val) != 0) {
        dumpError(ctx);
        c.free(buf);
        return 1;
    }
    c.free(buf);
    return 0;
}

const HdrBuf = extern union {
    hdr: c.JSBytecodeHeader,
    hdr32: c.JSBytecodeHeader32,
};

fn compileFile(
    filename: [*:0]const u8,
    outfilename: [*:0]const u8,
    mem_size: usize,
    dump_memory: c_int,
    parse_flags: c_int,
    force_32bit: BOOL,
) void {
    const mem_buf: [*]u8 = @ptrCast(c.malloc(mem_size));
    const ctx = c.JS_NewContext2(mem_buf, mem_size, @ptrCast(&stdlib_data.js_stdlib), TRUE).?;
    c.JS_SetLogFunc(ctx, jsLogFunc);

    const eval_str: [*]u8 = @ptrCast(loadFile(filename, null));
    const val = c.JS_Parse(ctx, @ptrCast(eval_str), c.strlen(@ptrCast(eval_str)), filename, parse_flags);
    c.free(eval_str);
    if (c.JS_IsException(val) != 0) {
        dumpError(ctx);
        c.JS_FreeContext(ctx);
        c.free(mem_buf);
        return;
    }

    var hdr_buf: HdrBuf = undefined;
    var hdr_len: c_int = undefined;
    var data_buf_ptr: [*c]const u8 = undefined;
    var data_len: u32 = undefined;

    if (@sizeOf(c.JSValue) == 8 and force_32bit != FALSE) {
        if (c.JS_PrepareBytecode64to32(ctx, &hdr_buf.hdr32, &data_buf_ptr, &data_len, val) != 0) {
            _ = c.fprintf(c.stderr, "Could not convert the bytecode from 64 to 32 bits\n");
            std.process.exit(1);
        }
        hdr_len = @sizeOf(c.JSBytecodeHeader32);
    } else {
        c.JS_PrepareBytecode(ctx, &hdr_buf.hdr, &data_buf_ptr, &data_len, val);
        if (dump_memory != 0)
            c.JS_DumpMemory(ctx, if (dump_memory >= 2) TRUE else FALSE);
        _ = c.JS_RelocateBytecode2(ctx, &hdr_buf.hdr, @constCast(data_buf_ptr), data_len, 0, FALSE);
        hdr_len = @sizeOf(c.JSBytecodeHeader);
    }

    const f = c.fopen(outfilename, "wb");
    if (f == null) {
        _ = c.perror(outfilename);
        std.process.exit(1);
    }
    _ = c.fwrite(@ptrCast(&hdr_buf), 1, @intCast(hdr_len), f);
    _ = c.fwrite(data_buf_ptr, 1, data_len, f);
    _ = c.fclose(f);

    c.JS_FreeContext(ctx);
    c.free(mem_buf);
}

fn replRun(ctx: *c.JSContext) void {
    const s = &readline_state;
    s.term_width = c.readline_tty_init();
    s.term_cmd_buf = @ptrCast(&readline_cmd_buf);
    s.term_kill_buf = @ptrCast(&readline_kill_buf);
    s.term_cmd_buf_size = @sizeOf(@TypeOf(readline_cmd_buf));
    s.term_history = @ptrCast(&readline_history);
    s.term_history_buf_size = @sizeOf(@TypeOf(readline_history));
    s.get_color = termGetColor;

    c.JS_SetInterruptHandler(ctx, jsInterruptHandler);

    while (true) {
        const cmd = c.readline_tty(s, "mqjs > ", FALSE);
        if (cmd == null)
            break;
        _ = evalBuf(ctx, cmd, "<cmdline>", TRUE, 0);
        runTimers(ctx);
    }
}

fn help() noreturn {
    _ = c.printf(
        \\MicroQuickJS
        \\usage: mqjs [options] [file [args]]
        \\-h  --help            list options
        \\-e  --eval EXPR       evaluate EXPR
        \\-i  --interactive     go to interactive mode
        \\-I  --include file    include an additional file
        \\-d  --dump            dump the memory usage stats
        \\    --memory-limit n  limit the memory usage to 'n' bytes
        \\--no-column           no column number in debug information
        \\-o FILE               save the bytecode to FILE
        \\-m32                  force 32 bit bytecode output (use with -o)
        \\-b  --allow-bytecode  allow bytecode in input file
        \\
    );
    std.process.exit(1);
}

pub fn main() u8 {
    stdlib_data.relocate();
    const allocator = std.heap.page_allocator;
    const argv = std.process.argsAlloc(allocator) catch return 1;
    defer std.process.argsFree(allocator, argv);
    var mem_size: usize = 16 << 20;
    var dump_memory: c_int = 0;
    var interactive: c_int = 0;
    var expr: ?[*:0]const u8 = null;
    var out_filename: ?[*:0]const u8 = null;
    var include_list: [MAX_INCLUDES]?[*:0]const u8 = [_]?[*:0]const u8{null} ** MAX_INCLUDES;
    var include_count: usize = 0;
    var parse_flags: c_int = 0;
    var force_32bit = FALSE;
    var allow_bytecode = FALSE;

    var optind: usize = 1;
    while (optind < argv.len and argv[optind].len > 0 and argv[optind][0] == '-') {
        var arg: []const u8 = argv[optind][1..];
        if (arg.len == 0)
            break;
        optind += 1;
        var longopt: []const u8 = "";
        if (arg[0] == '-') {
            longopt = arg[1..];
            arg = arg[arg.len..];
            if (longopt.len == 0)
                break;
        }
        opt_loop: while (arg.len > 0 or longopt.len > 0) {
            const opt: u8 = if (arg.len > 0) arg[0] else 0;
            if (arg.len > 0)
                arg = arg[1..];
            if (std.mem.eql(u8, longopt, "help") or opt == 'h' or opt == '?') {
                help();
            }
            if (std.mem.eql(u8, longopt, "eval") or opt == 'e') {
                if (arg.len > 0) {
                    expr = @ptrCast(arg.ptr);
                    break :opt_loop;
                }
                if (optind < argv.len) {
                    expr = argv[optind].ptr;
                    optind += 1;
                    break :opt_loop;
                }
                _ = c.fprintf(c.stderr, "missing expression for -e\n");
                return 2;
            }
            if (std.mem.eql(u8, longopt, "memory-limit")) {
                if (optind >= argv.len) {
                    _ = c.fprintf(c.stderr, "expecting memory limit");
                    return 1;
                }
                var end_ptr: [*c]u8 = undefined;
                var count = c.strtod(argv[optind].ptr, &end_ptr);
                optind += 1;
                const suffix = ascii.toLower(end_ptr[0]);
                switch (suffix) {
                    'g' => count *= 1024,
                    else => {},
                }
                switch (suffix) {
                    'g', 'm' => count *= 1024,
                    else => {},
                }
                switch (suffix) {
                    'g', 'm', 'k' => count *= 1024,
                    else => {},
                }
                mem_size = @intFromFloat(count);
                longopt = "";
                continue;
            }
            if (std.mem.eql(u8, longopt, "dump") or opt == 'd') {
                dump_memory += 1;
                longopt = "";
                continue;
            }
            if (std.mem.eql(u8, longopt, "interactive") or opt == 'i') {
                interactive += 1;
                longopt = "";
                continue;
            }
            if (opt == 'o') {
                if (arg.len > 0) {
                    out_filename = @ptrCast(arg.ptr);
                    break :opt_loop;
                }
                if (optind < argv.len) {
                    out_filename = argv[optind].ptr;
                    optind += 1;
                    break :opt_loop;
                }
                _ = c.fprintf(c.stderr, "missing filename for -o\n");
                return 2;
            }
            if (std.mem.eql(u8, longopt, "include") or opt == 'I') {
                if (optind >= argv.len) {
                    _ = c.fprintf(c.stderr, "expecting filename");
                    return 1;
                }
                if (include_count >= MAX_INCLUDES) {
                    _ = c.fprintf(c.stderr, "too many included files");
                    return 1;
                }
                include_list[include_count] = argv[optind].ptr;
                include_count += 1;
                optind += 1;
                longopt = "";
                continue;
            }
            if (std.mem.eql(u8, longopt, "no-column")) {
                parse_flags |= c.JS_EVAL_STRIP_COL;
                longopt = "";
                continue;
            }
            if (opt == 'm' and std.mem.eql(u8, arg, "32")) {
                force_32bit = TRUE;
                arg = arg[arg.len..];
                longopt = "";
                continue;
            }
            if (std.mem.eql(u8, longopt, "allow-bytecode") or opt == 'b') {
                allow_bytecode = TRUE;
                longopt = "";
                continue;
            }
            if (opt != 0) {
                _ = c.fprintf(c.stderr, "qjs: unknown option '-%c'\n", opt);
            } else {
                _ = c.fprintf(c.stderr, "qjs: unknown option '--%s'\n", @as([*:0]const u8, @ptrCast(longopt.ptr)));
            }
            help();
        }
    }

    if (out_filename) |out| {
        if (optind >= argv.len) {
            _ = c.fprintf(c.stderr, "expecting input filename\n");
            return 1;
        }
        compileFile(argv[optind].ptr, out, mem_size, dump_memory, parse_flags, force_32bit);
        return 0;
    }

    const mem_buf: [*]u8 = @ptrCast(c.malloc(mem_size));
    const ctx = c.JS_NewContext(mem_buf, mem_size, @ptrCast(&stdlib_data.js_stdlib)).?;
    c.JS_SetLogFunc(ctx, jsLogFunc);
    {
        var tv: c.struct_timeval = undefined;
        _ = c.gettimeofday(&tv, null);
        const seed: u64 = (@as(u64, @intCast(tv.tv_sec)) << 32) ^ @as(u64, @intCast(tv.tv_usec));
        c.JS_SetRandomSeed(ctx, seed);
    }

    var i: usize = 0;
    while (i < include_count) : (i += 1) {
        if (evalFile(ctx, include_list[i].?, 0, null, parse_flags, allow_bytecode) != 0) {
            c.JS_FreeContext(ctx);
            c.free(mem_buf);
            return 1;
        }
    }

    if (expr) |e| {
        if (evalBuf(ctx, e, "<cmdline>", FALSE, parse_flags | c.JS_EVAL_REPL) != 0) {
            c.JS_FreeContext(ctx);
            c.free(mem_buf);
            return 1;
        }
    } else if (optind >= argv.len) {
        interactive += 1;
    } else {
        const script_argv = argv[optind..];
        const script_argc: c_int = @intCast(script_argv.len);
        if (evalFile(ctx, script_argv[0].ptr, script_argc, @ptrCast(script_argv.ptr), parse_flags, allow_bytecode) != 0) {
            c.JS_FreeContext(ctx);
            c.free(mem_buf);
            return 1;
        }
    }

    if (interactive != 0) {
        replRun(ctx);
    } else {
        runTimers(ctx);
    }

    if (dump_memory != 0)
        c.JS_DumpMemory(ctx, if (dump_memory >= 2) TRUE else FALSE);

    c.JS_FreeContext(ctx);
    c.free(mem_buf);
    return 0;
}
