import fs from 'node:fs';
import path from 'node:path';

function analyzeFailures(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error(`Error: File not found at path: ${filePath}`);
    process.exit(1);
  }

  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split(/\r?\n/);

  const failureCounts = new Map();
  let totalFailures = 0;
  let currentFile = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    // Detect a FAIL line (e.g., "FAIL test/... (default)")
    if (line.startsWith('FAIL ')) {
      currentFile = line.slice(5);
      continue;
    }

    // Capture the immediate message line following a FAIL line
    if (currentFile && line.length > 0) {
      // Clean leading bullet points or spaces if present
      const reason = line.replace(/^[ \s]*[|\-•]?\s*/, '');

      failureCounts.set(reason, (failureCounts.get(reason) || 0) + 1);
      totalFailures++;

      // Reset state for the next entry
      currentFile = null;
    }
  }

  // Sort by count descending
  const sortedFailures = [...failureCounts.entries()].sort((a, b) => b[1] - a[1]);

  console.log(`\n=== Failure Reason Summary (Total FAILs: ${totalFailures}) ===\n`);
  
  if (sortedFailures.length === 0) {
    console.log('No failure reasons found.');
    return;
  }

  sortedFailures.forEach(([reason, count], index) => {
    const percentage = ((count / totalFailures) * 100).toFixed(1);
    console.log(`${index + 1}. [${count}x] (${percentage}%) ${reason}`);
  });
}

// Get filepath from CLI argument or default to 'test-results.txt'
const logFilePath = process.argv[2] || 'test-results.txt';
analyzeFailures(logFilePath);