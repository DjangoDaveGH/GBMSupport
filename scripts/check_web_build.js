// Firebase Hosting predeploy guard (see firebase.json). The SPA rewrite
// serves index.html for any missing file, so an incomplete build/web
// deploys "successfully" but the app hangs on the loading screen (it gets
// HTML where it expects assets/FontManifest.json). Refuse to deploy then.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'build', 'web');
const required = [
  'index.html',
  'main.dart.js',
  'flutter_bootstrap.js',
  'flutter_service_worker.js',
  'firebase-messaging-sw.js',
  'manifest.json',
  'version.json',
  'favicon.png',
  'splash_logo.png',
  'assets/FontManifest.json',
  'assets/AssetManifest.bin.json',
  'icons/Icon-192.png',
];
const missing = required.filter((f) => {
  try {
    return fs.statSync(path.join(root, f)).size === 0;
  } catch (_) {
    return true;
  }
});
if (missing.length) {
  console.error('build/web is incomplete, refusing to deploy. Missing:');
  for (const f of missing) console.error('  - ' + f);
  console.error('Rebuild with: flutter build web --release');
  process.exit(1);
}
console.log('build/web check passed (' + required.length + ' files).');
