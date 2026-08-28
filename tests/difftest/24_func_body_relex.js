// Host JS_DumpMemory via mqjs -d. Zig re-lexed the first token of every
// function body (unconditional js_parse_seek_token after `{`), leaving
// extra non-unique "var"/"return" strings vs C (debug-notes.md fix 20).
function f() {
    var x = 1;
    return x;
}
function g() {
    return 2;
}
print(f() + g());
print("DONE 24_func_body_relex.js");
