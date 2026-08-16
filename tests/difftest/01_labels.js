// Labeled break/continue under GC pressure (label intern identity)
var log = [];
function churn(n) {
    var a = [];
    for (var i = 0; i < n; i++) a[i] = "churn-" + n + "-" + i;
    return a.length;
}

outer:
for (var i = 0; i < 60; i++) {
    churn(30);
    inner:
    for (var j = 0; j < 60; j++) {
        churn(10);
        if (j === 5) continue inner;
        if (j === 10) continue outer;
        if (i === 40 && j === 3) break outer;
        if (j > 12) break inner;
        log.push(i * 1000 + j);
    }
}
print("labels len=" + log.length);
print("labels sum=" + log.reduce(function (a, b) { return a + b; }, 0));

// deeply nested labels with same name reused in sibling scopes
function nested() {
    var total = 0;
    for (var k = 0; k < 20; k++) {
        lbl: for (var m = 0; m < 20; m++) {
            churn(5);
            if (m === 7) continue lbl;
            if (m === 9) break lbl;
            total += m;
        }
        lbl2: while (true) {
            churn(5);
            total += 1;
            break lbl2;
        }
    }
    return total;
}
print("nested=" + nested());

print("DONE 01_labels.js");
