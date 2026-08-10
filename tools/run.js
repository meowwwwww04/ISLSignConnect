const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

console.log('Running SignConnect Keypoint Generator...');
try {
  const out = execSync('python3 tools/setup_dataset.py', { encoding: 'utf-8' });
  console.log(out);
} catch (err) {
  console.error('Execution note:', err.message);
  if (err.stdout) console.log(err.stdout);
  if (err.stderr) console.error(err.stderr);
}
