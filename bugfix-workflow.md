### TASK: Single-Failure Segfault Resolution Loop

This repo is a port of Micro QuickJS from C to Zig. Documentation of the port is in handoff.md. That should give you a general overview of the project without reading every file.

You are tasked with fixing EXACTLY ONE segfault or runtime crash at a time from our test262 test suite. Right now I'm not worried about being in compliance with the JS standard. I'm only worried about the engine seg faulting or crashing, incorrect runtime results that are not a seg fault or crash is fine for now.

#### STRICT OPERATIONAL RULES:
2. DO NOT rewrite large subsystems. Modify only the logic necessary to fix the specific crash.
3. CONTEXT MINIMIZATION: Read only the stack trace, the failing test file, and the immediate Zig code responsible for the crash. Do not search or index the whole codebase.
4. STOP AT THE FIRST FIX: Once you fix ONE segfault and verify that the test runs (or fails gracefully with a JS error instead of a segfault), STOP IMMEDIATELY and ask for my review.

#### WORKFLOW STEPS (Follow Sequentially):
1. **RUN TEST:** Execute the test262 harness command. Do NOT wait for all tests to run, stop once any one test fails with a segfault or crash. The harness command is run from the zig-mquickjs/test262 (zig-mquickjs is the project root) directory. You do not need to install anything.
Your PATH in your terminal doesn't match mine, but the commands are available at
```
zig: /home/vexcess/zig-x86_64-linux/zig
node: /home/vexcess/.nvm/versions/node/v24.12.0/bin/node
test262-harness: /home/vexcess/.nvm/versions/node/v24.12.0/bin/test262-harness
```
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