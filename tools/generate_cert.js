const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const keyPath = path.join(__dirname, '..', 'key.pem');
const certPath = path.join(__dirname, '..', 'cert.pem');

if (!fs.existsSync(keyPath) || !fs.existsSync(certPath)) {
  try {
    execSync(`openssl req -x509 -newkey rsa:2048 -keyout "${keyPath}" -out "${certPath}" -days 365 -nodes -subj "/CN=SignConnect"`, { stdio: 'ignore' });
    console.log("[SSL] Successfully generated self-signed HTTPS certificate!");
  } catch (e) {
    console.warn("[SSL] openssl notice:", e.message);
  }
}
