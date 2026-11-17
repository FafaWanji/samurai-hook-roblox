// Uploads roblox/upload/ (made by make-upload.mjs) to Roblox with the Open Cloud Assets API and writes the
// IDs to roblox/src/shared/AssetIds.luau, which Assets.luau reads. Rojo syncs that file into Studio.
//
// Needs two environment variables (the key is read here and never printed):
//   ROBLOX_API_KEY  - Open Cloud API key with the Assets API, Read + Write
//   ROBLOX_USER_ID  - your numeric Roblox user ID (the uploads belong to you)
// Run from the repo root:
//   node roblox/tools/upload-assets.mjs            upload whatever is not uploaded yet
//   node roblox/tools/upload-assets.mjs --dry-run  list what would be uploaded, call nothing
//   node roblox/tools/upload-assets.mjs --images   images only (audio has a monthly quota)
//
// Uploaded files are remembered in roblox/upload/uploaded.json (by content hash), so a rerun only sends
// new or changed files. Audio is sent most-important-first, because accounts without ID verification
// may upload only 10 sounds a month; when the quota runs out the script stops and keeps what it has.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const UPLOAD = 'roblox/upload';
const CACHE = `${UPLOAD}/uploaded.json`;
const OUT = 'roblox/src/shared/AssetIds.luau';
const API = process.env.ROBLOX_API_BASE ?? 'https://apis.roblox.com/assets/v1'; // override only for tests
const args = new Set(process.argv.slice(2));
const dryRun = args.has('--dry-run');
const imagesOnly = args.has('--images');

// Most important first: music, the fight's own sounds, then UI, then the announcer.
const AUDIO_ORDER = [
  'music-fight', 'music-ocean', 'hit', 'slash', 'heavy', 'gong', 'slip', 'block', 'dash', 'ko', 'coin', 'buy',
  'splash', 'uiMove', 'uiConfirm', 'tell', 'voice-fight', 'voice-win', 'voice-perfect', 'voice-ko', 'voice-timeout',
  'voice-round1', 'voice-round2', 'voice-round3', 'voice-round4', 'voice-round5', 'voice-round',
];
const MIME = { '.png': 'image/png', '.ogg': 'audio/ogg', '.mp3': 'audio/mpeg', '.wav': 'audio/wav' };

if (!existsSync(`${UPLOAD}/images`)) execFileSync(process.execPath, ['roblox/tools/make-upload.mjs'], { stdio: 'inherit' });

const files = [];
for (const f of readdirSync(`${UPLOAD}/images`)) files.push({ kind: 'image', name: f.replace(/\.png$/, ''), path: `${UPLOAD}/images/${f}`, ext: '.png' });
const audioFiles = readdirSync(`${UPLOAD}/audio`).map((f) => ({ kind: 'audio', name: f.slice(0, f.lastIndexOf('.')), path: `${UPLOAD}/audio/${f}`, ext: f.slice(f.lastIndexOf('.')) }));
audioFiles.sort((a, b) => rank(a.name) - rank(b.name));
if (!imagesOnly) files.push(...audioFiles);
function rank(n) { const i = AUDIO_ORDER.indexOf(n); return i < 0 ? 999 : i; }

const cache = existsSync(CACHE) ? JSON.parse(readFileSync(CACHE, 'utf8')) : {};
const hashOf = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const todo = files.filter((f) => cache[f.name]?.hash !== hashOf(f.path));

console.log(`${files.length - todo.length} already uploaded, ${todo.length} to upload`);
if (dryRun) {
  for (const f of todo) console.log(`  would upload ${f.kind} ${f.name}`);
  writeLuau();
  process.exit(0);
}

const key = process.env.ROBLOX_API_KEY;
const userId = process.env.ROBLOX_USER_ID;
if (todo.length && (!key || !/^\d+$/.test(userId ?? ''))) {
  console.error('Set ROBLOX_API_KEY (Open Cloud key, Assets Read + Write) and ROBLOX_USER_ID (digits) first. See roblox/README.md.');
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(url, init = {}) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, { ...init, headers: { ...(init.headers ?? {}), 'x-api-key': key } });
    if (res.status === 429 && attempt < 6) { await sleep(2000 * attempt); continue; }
    const text = await res.text();
    let body = null;
    try { body = JSON.parse(text); } catch { /* not JSON */ }
    return { ok: res.ok, status: res.status, body, text: text.slice(0, 400) };
  }
}

async function create(f, assetType) {
  const form = new FormData();
  form.append('request', JSON.stringify({
    assetType,
    displayName: `SamuraiHook ${f.name}`.slice(0, 50),
    description: 'Samurai Hook game asset',
    creationContext: { creator: { userId } },
  }));
  form.append('fileContent', new Blob([readFileSync(f.path)], { type: MIME[f.ext] }), `${f.name}${f.ext}`);
  return api(`${API}/assets`, { method: 'POST', body: form });
}

async function waitFor(opPath) {
  for (let i = 0; i < 90; i++) {
    const r = await api(`${API}/${opPath}`);
    if (!r.ok) throw new Error(`operation check failed (${r.status}): ${r.text}`);
    if (r.body?.done) {
      const resp = r.body.response;
      if (!resp?.assetId) throw new Error(`upload rejected: ${JSON.stringify(r.body.error ?? r.body).slice(0, 300)}`);
      return resp;
    }
    await sleep(2000);
  }
  throw new Error('timed out waiting for Roblox to process the upload');
}

let failed = 0;
for (const f of todo) {
  try {
    let r;
    if (f.kind === 'image') {
      // "Image" gives an ID ImageLabels can use directly; older API versions only take "Decal".
      r = await create(f, 'Image');
      if (!r.ok && r.status === 400) r = await create(f, 'Decal');
    } else {
      r = await create(f, 'Audio');
    }
    if (!r.ok || !r.body?.path) {
      if (f.kind === 'audio' && /quota|limit/i.test(r.text)) {
        console.error(`audio quota reached at ${f.name}; the rest stay silent. Run again next month (or after ID verification).`);
        break;
      }
      throw new Error(`HTTP ${r.status}: ${r.text}`);
    }
    const asset = await waitFor(r.body.path);
    const isDecal = /DECAL/i.test(asset.assetType ?? '');
    cache[f.name] = { hash: hashOf(f.path), kind: f.kind, id: String(asset.assetId), decal: isDecal };
    writeFileSync(CACHE, JSON.stringify(cache, null, 2));
    const mod = asset.moderationResult?.moderationState;
    console.log(`  ${f.name}: ${asset.assetId}${isDecal ? ' (decal)' : ''}${mod ? ` [${mod}]` : ''}`);
  } catch (e) {
    failed++;
    console.error(`  ${f.name}: FAILED ${e.message}`);
  }
}
writeLuau();
console.log(failed ? `${failed} failed; rerun to retry them.` : 'done');
process.exit(failed ? 1 : 0);

function writeLuau() {
  const entries = Object.entries(cache).sort(([a], [b]) => a.localeCompare(b));
  const lines = entries.map(([name, v]) =>
    `\t[${JSON.stringify(name)}] = { id = ${JSON.stringify(`rbxassetid://${v.id}`)}, decal = ${v.decal ? 'true' : 'false'} },`);
  writeFileSync(OUT, [
    '-- Generated by roblox/tools/upload-assets.mjs. Do not edit: rerun the script instead.',
    '-- Keys are file names in roblox/upload/. decal = true: the server turns it into an image ID at startup.',
    'return {',
    ...lines,
    '}',
    '',
  ].join('\n'));
  console.log(`wrote ${OUT} (${entries.length} assets)`);
}
