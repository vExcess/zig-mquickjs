let wasmInstance = null;
let wasmExports = null;
let wasmMemory = null;

function getExports() {
    if (!wasmExports) throw new Error("mquickjs WASM not loaded");
    return wasmExports;
}

function getMemory() {
    if (!wasmMemory) throw new Error("mquickjs WASM memory not available");
    return wasmMemory;
}

function readResult() {
    const exp = getExports();
    const len = exp.mqjs_result_len();
    if (len <= 0) return "";
    const ptr = exp.mqjs_result_ptr();
    const bytes = getMemory().buffer.slice(ptr, ptr + len);
    return new TextDecoder().decode(bytes);
}

function writeToMemory(text) {
    const exp = getExports();
    const memory = getMemory();
    const ptr = exp.mqjs_src_ptr();
    const maxLen = exp.mqjs_src_max_len();
    const encoded = new TextEncoder().encode(text);
    if (encoded.length > maxLen) {
        throw new Error(`source exceeds ${maxLen} byte limit`);
    }
    new Uint8Array(memory.buffer, ptr, encoded.length).set(encoded);
    return { ptr, len: encoded.length };
}

export async function loadMqjs(wasmUrl = "mqjs.wasm") {
    const imports = {
        env: {
            console_write(ptr, len) {
                const bytes = getMemory().buffer.slice(ptr, ptr + len);
                const text = new TextDecoder().decode(bytes);
                if (text.endsWith("\n")) {
                    console.log(text.slice(0, -1));
                } else if (text.length > 0) {
                    console.log(text);
                }
            },
            performance_now() {
                return performance.now();
            },
            // Emscripten-style SjLj: parser syntax errors throw Infinity to JS.
            throw_longjmp() {
                throw Infinity;
            },
            invoke_parse(statePtr, evalFlags) {
                const exp = getExports();
                try {
                    exp.mqjs_parse_after_setjmp(statePtr, evalFlags);
                    return 0;
                } catch (e) {
                    if (e !== e + 0) throw e;
                    return 1;
                }
            },
        },
    };

    const response = await fetch(wasmUrl);
    if (!response.ok) {
        throw new Error(`Failed to fetch ${wasmUrl}: ${response.status}`);
    }
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, imports);
    wasmInstance = result.instance;
    wasmExports = result.instance.exports;
    wasmMemory = wasmExports.memory;
    if (!wasmMemory) throw new Error("WASM module did not export memory");

    const rc = wasmExports.mqjs_init();
    if (rc !== 0) throw new Error(`mqjs_init failed with code ${rc}`);
    return wasmExports;
}

export function evalScript(source) {
    const exp = getExports();
    const { len } = writeToMemory(source);
    const rc = exp.mqjs_eval(len);
    const output = readResult();
    return { ok: rc === 0, code: rc, output };
}

export function freeMqjs() {
    if (wasmExports?.mqjs_free) wasmExports.mqjs_free();
    wasmInstance = null;
    wasmExports = null;
    wasmMemory = null;
}
