const builtin = @import("builtin");

const is_wasm = builtin.cpu.arch == .wasm32 and builtin.os.tag == .freestanding;

pub fn longjmp(env: *anyopaque, val: c_int) noreturn {
    if (is_wasm) {
        wasmThrowLongjmp();
    } else {
        nativeLongjmp(env, val);
    }
}

/// libc `setjmp`. Call this **directly** from the function that handles the
/// second return (`JS_Parse2`). A Zig wrapper is not inlined in Debug, so
/// `longjmp` would resume in a dead frame (ReleaseFast/Safe hid this).
pub extern fn setjmp(env: *anyopaque) c_int;

pub fn invokeParse(state_ptr: *anyopaque, eval_flags: c_int) c_int {
    if (is_wasm) {
        return wasmInvokeParse(state_ptr, @intCast(eval_flags));
    }
    return 0;
}

fn nativeLongjmp(env: *anyopaque, val: c_int) noreturn {
    const libc = struct {
        extern fn longjmp(e: *anyopaque, v: c_int) noreturn;
    };
    libc.longjmp(env, val);
}

fn wasmThrowLongjmp() noreturn {
    const host = struct {
        extern "env" fn throw_longjmp() void;
    };
    host.throw_longjmp();
    unreachable;
}

fn wasmInvokeParse(state_ptr: *anyopaque, eval_flags: i32) c_int {
    const host = struct {
        extern "env" fn invoke_parse(ptr: *anyopaque, flags: i32) i32;
    };
    return host.invoke_parse(state_ptr, eval_flags);
}
