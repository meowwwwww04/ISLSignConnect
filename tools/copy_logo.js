const fs = require('fs');
const path = require('path');

const src = '/home/yume26/.gemini/antigravity-ide/brain/16ccde38-0c00-442c-8612-1b74afd6545a/media__1787319494868.jpg';
const destDir1 = '/home/yume26/Desktop/islProject/signconnect_app/assets/images';
const destDir2 = '/home/yume26/Desktop/islProject/signconnect_app/web/assets/images';

if (!fs.existsSync(src)) {
  console.warn("Source logo not found, skipping logo copy:", src);
  process.exit(0);
}

fs.mkdirSync(destDir1, { recursive: true });
fs.mkdirSync(destDir2, { recursive: true });

fs.copyFileSync(src, path.join(destDir1, 'app_logo.png'));
fs.copyFileSync(src, path.join(destDir2, 'app_logo.png'));

console.log("Successfully copied app_logo.png!");
