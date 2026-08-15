// Copyright 2013 the V8 project authors. All rights reserved.
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

new BenchmarkSuite('zlib', [152815148], [
  new Benchmark('zlib', false, true, 10,
    runZlib, undefined, tearDownZlib, null, 3)]);

// Generate 100kB pseudo-random bytes (compressed 25906 bytes) and
// compress/decompress them 60 times.
var zlibEval = eval;
function runZlib() {
  if (typeof Ya != "function") {
    InitializeZlibBenchmark();
  }
  Ya(["1"]);
}

function tearDownZlib() {
  $ = undefined;
  $a = undefined;
  Aa = undefined;
  Ab = undefined;
  Ba = undefined;
  Bb = undefined;
  C = undefined;
  Ca = undefined;
  Cb = undefined;
  D = undefined;
  Da = undefined;
  Db = undefined;
  Ea = undefined;
  Eb = undefined;
  F = undefined;
  Fa = undefined;
  Fb = undefined;
  G = undefined;
  Ga = undefined;
  Gb = undefined;
  Ha = undefined;
  Hb = undefined;
  I = undefined;
  Ia = undefined;
  Ib = undefined;
  J = undefined;
  Ja = undefined;
  Jb = undefined;
  Ka = undefined;
  Kb = undefined;
  L = undefined;
  La = undefined;
  Lb = undefined;
  Ma = undefined;
  Mb = undefined;
  Module = undefined;
  N = undefined;
  Na = undefined;
  Nb = undefined;
  O = undefined;
  Oa = undefined;
  Ob = undefined;
  P = undefined;
  Pa = undefined;
  Pb = undefined;
  Q = undefined;
  Qa = undefined;
  Qb = undefined;
  R = undefined;
  Ra = undefined;
  Rb = undefined;
  S = undefined;
  Sa = undefined;
  Sb = undefined;
  T = undefined;
  Ta = undefined;
  Tb = undefined;
  U = undefined;
  Ua = undefined;
  Ub = undefined;
  V = undefined;
  Va = undefined;
  Vb = undefined;
  W = undefined;
  Wa = undefined;
  Wb = undefined;
  X = undefined;
  Xa = undefined;
  Y = undefined;
  Ya = undefined;
  Z = undefined;
  Za = undefined;
  ab = undefined;
  ba = undefined;
  bb = undefined;
  ca = undefined;
  cb = undefined;
  da = undefined;
  db = undefined;
  ea = undefined;
  eb = undefined;
  fa = undefined;
  fb = undefined;
  ga = undefined;
  gb = undefined;
  ha = undefined;
  hb = undefined;
  ia = undefined;
  ib = undefined;
  j = undefined;
  ja = undefined;
  jb = undefined;
  k = undefined;
  ka = undefined;
  kb = undefined;
  la = undefined;
  lb = undefined;
  ma = undefined;
  mb = undefined;
  n = undefined;
  na = undefined;
  nb = undefined;
  oa = undefined;
  ob = undefined;
  pa = undefined;
  pb = undefined;
  qa = undefined;
  qb = undefined;
  r = undefined;
  ra = undefined;
  rb = undefined;
  sa = undefined;
  sb = undefined;
  t = undefined;
  ta = undefined;
  tb = undefined;
  u = undefined;
  ua = undefined;
  ub = undefined;
  v = undefined;
  va = undefined;
  vb = undefined;
  w = undefined;
  wa = undefined;
  wb = undefined;
  x = undefined;
  xa = undefined;
  xb = undefined;
  ya = undefined;
  yb = undefined;
  z = undefined;
  za = undefined;
  zb = undefined;
}
