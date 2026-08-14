### TASK: Single-Failure Segfault Resolution Loop

This repo is a port of Micro QuickJS from C to Zig. Documentation of the port is in handoff.md. That should give you a general overview of the project without reading every file.

You are tasked with fixing EXACTLY ONE error at a time from our test262 test suite.

The current error is that microquickjs is such that Only global eval is supported so it cannot access to nor modify local variables:
```
    eval('1 + 2'); // forbidden
    (1, eval)('1 + 2'); // OK
```

When running the test manually it says that it doesn't support local eval. But for some reason the test harness reports it as an unexpected character in expression. Implementing eval to support local variables is too much work, but I don't want all the evals to fail. Make the eval() function just always run in global scope instead of throwing a error. This means some programs will run incorrectly, but I am ok with this. Figure out if that change fixes the "unexpected character in expression" error. If it doesn't figure out what's causing that error.
```
vexcess@vexcess-IdeaPad ~/S/W/z/test262 (main) [1]> test262-harness --host-type=qjs --host-path=../mqjs-test262.sh "test/language/arguments-object/10.5-7-b-1-s.js"
FAIL test/language/arguments-object/10.5-7-b-1-s.js (strict mode)
  Expected no error, got SyntaxError: unexpected character in expression

Ran 1 tests
0 passed
1 failed
vexcess@vexcess-IdeaPad ~/S/W/z/test262 (main)> ../mqjs-test262.sh test/language/arguments-object/10.5-7-b-1-s.js
SyntaxError: direct eval is not supported. Use (1,eval) instead for indirect
    at test/language/arguments-object/10.5-7-b-1-s.js:11:10
vexcess@vexcess-IdeaPad ~/S/W/z/test262 (main) [1]> 
```


#### STRICT OPERATIONAL RULES:
2. DO NOT rewrite large subsystems. Modify only the logic necessary to fix the error.
3. CONTEXT MINIMIZATION: Read only the stack trace, failing test file, immediate Zig code responsible for the error. Do not search or index the whole codebase.
4. STOP AT THE FIRST FIX: Once you fix ONE error and verify that the test runs (or fails gracefully with a JS error instead of a segfault), STOP IMMEDIATELY and ask for my review.

#### WORKFLOW STEPS (Follow Sequentially):
1. **RUN TEST:** Execute the test262 harness command. Do NOT wait for all tests to run, edit the command to run ONLY the relevant test. The harness command is run from the zig-mquickjs/test262 (zig-mquickjs is the project root) directory. You do not need to install anything.
Your PATH in your terminal doesn't match mine, but the commands are available so you must add them to your PATH. The mqjs binary does exist, no need to check for its existence. Install locations of commands:
```
zig: /home/vexcess/zig-x86_64-linux/zig
node: /home/vexcess/.nvm/versions/node/v24.12.0/bin/node
test262-harness: /home/vexcess/.nvm/versions/node/v24.12.0/bin/test262-harness
```
The command to run tests (change "test/language/**/*.js" to a specific test):
```
test262-harness \
  --host-type=qjs \
  --host-path=../mqjs-test262.sh \
  "test/language/**/*.js"
```
2. **LOCATE CRASH:** Identify the Zig stack trace, the crashing opcode, or the `panicked at` line number.
3. **DIAGNOSE:** Analyze *why* the segfault happened (e.g., null pointer dereference, slice out of bounds, wrong integer cast, C `void*` misuse, pointer misalignment, the test calling functions that haven't been implemented, etc).
4. **APPLY FIX:**
   - **Preferred:** Convert the local C-style pointer/memory math into idiomatic Zig (e.g., proper optional unwrapping `if (ptr) |p|`, bounds-checked slices `[]u8`, or Zig error handling) *only if it is safely contained*.
   - **Fallback:** If refactoring is risky or complex, update the literal C-style Zig code directly to fix the bug with minimal changes.
5. **VERIFY:** Re-run the test command. 
   - If it still segfaults, refactor or revert your changes or try a different targeted fix.
   - If it no longer segfaults (even if it outputs a JS evaluation error), **STOP**.
6. **REPORT & PAUSE:** Print a concise summary of the cause and fix, and wait for my explicit confirmation before proceeding to the next test: