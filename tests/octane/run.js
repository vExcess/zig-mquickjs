// Copyright 2014 the V8 project authors. All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

var load_script, base_dir, args;

if (typeof __loadScript == "function")
    load_script = __loadScript;
else
    load_script = load;

if (typeof scriptArgs != "undefined")
    args = scriptArgs;
else
    args = arguments;

var base_dir = args[0];

var p = base_dir.lastIndexOf("/");
if (p >= 0)
    base_dir = base_dir.slice(0, p + 1);
else
    base_dir = "";
var read = function() { }; /* for zlib */

load_script(base_dir + 'base.js');

var files = [
    'richards.js',
    'deltablue.js',
    'crypto.js',
    'raytrace.js',
    'earley-boyer.js',
    'regexp.js',
    'splay.js',
    'navier-stokes.js',
    'pdfjs.js',
    'mandreel.js',
    'gbemu-part1.js',
    'gbemu-part2.js',
    'code-load.js',
    'box2d.js',
    'zlib.js',
    'zlib-data.js',
    'typescript.js',
    'typescript-input.js',
    'typescript-compiler.js',
];

for(var idx = 0; idx < files.length; idx++) {
    if (args.length <= 1 ||
        args[1].toLowerCase() == files[idx].slice(0, args[1].length)) {
        load_script(base_dir + files[idx]);
    }
}

var success = true;

function PrintResult(name, result) {
  print(name + ': ' + result);
}


function PrintError(name, error) {
  print(name + ":", error);
  success = false;
}


function PrintScore(score) {
  if (success) {
    print('----');
    print('Score (version ' + BenchmarkSuite.version + '): ' + score);
  }
}


BenchmarkSuite.config.doWarmup = undefined;
BenchmarkSuite.config.doDeterministic = undefined;

BenchmarkSuite.RunSuites({ NotifyResult: PrintResult,
                           NotifyError: PrintError,
                           NotifyScore: PrintScore });
