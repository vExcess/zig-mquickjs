echo "Running tests/test_builtin"
./zig-out/bin/mqjs tests/test_builtin.js

echo "Running tests/test_closure"
./zig-out/bin/mqjs tests/test_closure.js

echo "Running tests/test_language"
./zig-out/bin/mqjs tests/test_language.js

echo "Running tests/test_loop"
./zig-out/bin/mqjs tests/test_loop.js

echo "testing bytecode generation and loading"
./zig-out/bin/mqjs -o test_builtin.bin tests/test_builtin.js
./zig-out/bin/mqjs -b test_builtin.bin

echo "Running tests/test_rect"
./zig-out/bin/example tests/test_rect.js

echo "Running tests/mandelbrot"
./zig-out/bin/mqjs tests/mandelbrot.js

# echo "Running tests/microbench"
# ./zig-out/bin/mqjs tests/microbench.js 
