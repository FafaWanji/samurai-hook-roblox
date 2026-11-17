// Copies the web build's art and audio into roblox/upload/, ready for Studio's bulk import.
// Sprite strips wider than Roblox's 1024 px limit are repacked into grids (cols per Assets.luau).
// Run from the repo root: node roblox/tools/make-upload.mjs
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';

const OUT = 'roblox/upload';
const A = 'public/assets';
mkdirSync(`${OUT}/images`, { recursive: true });
mkdirSync(`${OUT}/audio`, { recursive: true });

// sprite id -> [source png, frames, cols]; cols must match roblox/src/shared/Assets.luau
const sheets = {
  samuraiIdle: ['samurai/idle.png', 8, 4],
  samuraiWalk: ['samurai/walk.png', 8, 4],
  samuraiQuick: ['samurai/quick.png', 6, 3],
  samuraiHeavy: ['samurai/heavy.png', 6, 3],
  samuraiBlock: ['samurai/block.png', 1, 1],
  samuraiHurt: ['samurai/hurt.png', 4, 4],
  samuraiJump: ['samurai/jump.png', 2, 2],
  samuraiFall: ['samurai/fall.png', 2, 2],
  samuraiCrouch: ['samurai/crouch.png', 8, 4],
  nigiri: ['props/nigiri.png', 1, 1],
};
for (const f of ['sardine', 'mackerel', 'piranha', 'eel', 'pufferfish', 'swordfish', 'anglerfish', 'shark', 'squid']) {
  sheets[`fish.${f}`] = [`fish/${f}.png`, 1, 1];
}

for (const [id, [src, frames, cols]] of Object.entries(sheets)) {
  const img = PNG.sync.read(readFileSync(`${A}/${src}`));
  const fw = img.width / frames;
  const fh = img.height;
  const rows = Math.ceil(frames / cols);
  const out = new PNG({ width: fw * cols, height: fh * rows });
  for (let n = 0; n < frames; n++) {
    PNG.bitblt(img, out, n * fw, 0, fw, fh, (n % cols) * fw, Math.floor(n / cols) * fh);
  }
  if (out.width > 1024 || out.height > 1024) throw new Error(`${id} is ${out.width}x${out.height}, over 1024`);
  writeFileSync(`${OUT}/images/${id}.png`, PNG.sync.write(out));
}

// Generated textures for the anglerfish fight: GUIs cannot cut holes or draw radial gradients.
// darkHole: near-black with a soft round hole (clear inside 45% of the radius, fading to 95% dark at the edge).
// glow: white, fading out from the centre; tinted in game.
function radial(size, pixel) {
  const out = new PNG({ width: size, height: size });
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2) / (size / 2);
      const [r, g, b, a] = pixel(d);
      const i = (y * size + x) * 4;
      out.data[i] = r; out.data[i + 1] = g; out.data[i + 2] = b; out.data[i + 3] = Math.round(a * 255);
    }
  }
  return PNG.sync.write(out);
}
writeFileSync(`${OUT}/images/darkHole.png`, radial(256, (d) => [2, 0, 8, 0.95 * Math.min(1, Math.max(0, (d - 0.45) / 0.55))]));
writeFileSync(`${OUT}/images/glow.png`, radial(128, (d) => [255, 255, 255, Math.max(0, 1 - d) ** 2]));

// The boat: the web build's code-drawn wasen (buildHull in src/core/assets.ts), rendered to a PNG.
// 280x110 hull plus 8 px padding = 296x126, prow facing right. The lantern is drawn live in game.
writeFileSync(`${OUT}/images/boat.png`, buildHullPng(280, 110));

function buildHullPng(w, h) {
  const pad = 8;
  const img = new PNG({ width: w + pad * 2, height: h + pad * 2 });
  const ox = w / 2 + pad, oy = h / 2 + pad;
  const parse = (c) => {
    const m = c.match(/^rgba\((\d+),(\d+),(\d+),([\d.]+)\)$/);
    if (m) return [+m[1], +m[2], +m[3], +m[4]];
    return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16), 1];
  };
  const cell = (x, y, col, cw = P, ch = P) => {
    const [r, g, b, a] = parse(col);
    for (let yy = Math.round(y + oy); yy < Math.round(y + oy + ch); yy++) {
      for (let xx = Math.round(x + ox); xx < Math.round(x + ox + cw); xx++) {
        if (xx < 0 || yy < 0 || xx >= img.width || yy >= img.height) continue;
        const i = (yy * img.width + xx) * 4;
        const da = img.data[i + 3] / 255;
        const oa = a + da * (1 - a);
        if (oa <= 0) continue;
        img.data[i] = Math.round((r * a + img.data[i] * da * (1 - a)) / oa);
        img.data[i + 1] = Math.round((g * a + img.data[i + 1] * da * (1 - a)) / oa);
        img.data[i + 2] = Math.round((b * a + img.data[i + 2] * da * (1 - a)) / oa);
        img.data[i + 3] = Math.round(oa * 255);
      }
    }
  };
  // ---- from here on: buildHull, unchanged apart from `g`/`cell` ----
  const BOAT_GEOM = { gunwaleFromBottom: 40, prowRise: 32, sternInset: 10 };
  const P = 2;
  const WOOD = {
    outline: '#1a0a05', seam: '#2a1408', dark: '#3a1d0e', rib: '#4a2612',
    planks: ['#7a4a26', '#6b3f20', '#74462a', '#5e3820'],
    grain: '#4e2c14', light: '#9a6238', weathered: '#7d6a5a', wet: '#33291f',
    cap: '#8a4e28', capLight: '#c07a44', patch: '#a3703f', tar: '#2e2620',
    rope: '#d9c08a', ropeDark: '#8f7448', bamboo: '#c8a860', bambooDark: '#7f6430', nail: '#120804',
  };
  const hash2 = (a, b) => {
    let n = (a * 374761393 + b * 668265263) | 0;
    n = Math.imul(n ^ (n >>> 13), 1274126177);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  };
  const hw = w / 2;
  const keel = h / 2 - 2;
  const gun = h / 2 - BOAT_GEOM.gunwaleFromBottom;
  const tipTop = gun - BOAT_GEOM.prowRise;
  const xs = -hw + BOAT_GEOM.sternInset;
  const xb = hw * 0.3;
  const top = (x) => (x >= xb ? gun - BOAT_GEOM.prowRise * Math.pow((x - xb) / (hw - xb), 2) : gun - 4 * Math.pow(Math.max(0, 1 - (x - xs) / 40), 2));
  const bottom = (x) => {
    let b = keel - 10 * Math.pow(Math.max(0, 1 - (x - xs) / 44), 2);
    if (x > 0) b = keel - (keel - (tipTop + 8)) * Math.pow(x / hw, 1.8);
    return Math.max(b, top(x) + 6);
  };
  const snap = (v) => Math.round(v / P) * P;
  const x0 = snap(xs);
  const x1 = snap(hw - 2);
  const PLANKS = 4;
  for (let x = x0 - P; x <= x1 + P; x += P) {
    const xc = Math.min(x1, Math.max(x0, x));
    cell(x, snap(top(xc)) - P, WOOD.outline, P, snap(bottom(xc)) - snap(top(xc)) + 3 * P);
  }
  for (let x = x0; x <= x1; x += P) {
    const t = snap(top(x));
    const b = snap(bottom(x));
    const span = Math.max(P, b - t);
    for (let y = t; y <= b; y += P) {
      const f = (y - t) / span;
      const pi = Math.min(PLANKS - 1, Math.floor(f * PLANKS));
      const plankTop = t + Math.round((pi * span) / PLANKS / P) * P;
      const row = (y - plankTop) / P;
      let col = WOOD.planks[pi];
      const gx = Math.floor((x + pi * 23) / 12);
      if (hash2(gx, y) < 0.22) col = WOOD.grain;
      if (hash2(Math.floor(x / 20), pi * 31 + 7) < 0.18 && hash2(x, y) < 0.5) col = WOOD.weathered;
      if (row === 1) col = WOOD.light;
      if (f > 0.78) col = hash2(x, y + 3) < 0.3 ? WOOD.dark : WOOD.wet;
      if (row === 0 && pi > 0) col = WOOD.seam;
      cell(x, y, col);
    }
  }
  for (let x = snap(xs + 26); x < hw - 30; x += 36) {
    const t = snap(top(x));
    const b = snap(bottom(x));
    cell(x, t, WOOD.rib, P, b - t);
    for (let pi = 0; pi < PLANKS; pi++) {
      const ny = snap(t + ((pi + 0.55) * (b - t)) / PLANKS);
      cell(x, ny, WOOD.nail);
      cell(x, ny - P, WOOD.capLight, P / 2, P / 2);
    }
  }
  const patch = (px, pw, pi, fillCol) => {
    const t = snap(top(px));
    const span = snap(bottom(px)) - t;
    const py = t + snap((pi * span) / PLANKS) + P;
    const ph = snap(span / PLANKS) - P;
    cell(px - P, py - P, WOOD.outline, pw + 2 * P, ph + 2 * P);
    cell(px, py, fillCol, pw, ph);
    cell(px, py, 'rgba(255,230,180,0.25)', pw, P);
    for (const [nx, ny] of [[px, py], [px + pw - P, py], [px, py + ph - P], [px + pw - P, py + ph - P]]) cell(nx, ny, WOOD.nail);
  };
  patch(snap(-hw * 0.42), 26, 1, WOOD.patch);
  patch(snap(hw * 0.2), 14, 2, WOOD.tar);
  for (let y = snap(top(x0)); y <= snap(bottom(x0)); y += P) cell(x0, y, WOOD.dark, P * 2);
  for (let x = x0; x <= x1; x += P) {
    const t = snap(top(x));
    cell(x, t - P, WOOD.outline);
    cell(x, t, WOOD.capLight);
    cell(x, t + P, WOOD.cap);
    cell(x, t + 2 * P, WOOD.seam);
  }
  const tipY = snap(top(x1));
  cell(x1 - P, tipY - 10, WOOD.outline, 3 * P, 12);
  cell(x1, tipY - 8, WOOD.cap, P, 8);
  const rx = snap(xs + 10);
  const ry = snap(top(xs + 10));
  const coil = [5, 8, 9, 9];
  coil.forEach((n, i) => {
    const yy = ry - (coil.length - i) * P;
    const xx = rx + Math.round((9 - n) / 2) * P;
    cell(xx - P, yy - (i === 0 ? P : 0), WOOD.outline, (n + 2) * P, P + (i === 0 ? P : 0));
    for (let k = 0; k < n; k++) cell(xx + k * P, yy, (k + i) % 3 === 0 ? WOOD.ropeDark : WOOD.rope);
  });
  cell(rx + 9 * P, ry - 2 * P, WOOD.outline, P, 4 * P);
  cell(rx + 9 * P, ry - P, WOOD.rope, P, 2 * P);
  const bx = snap(xs + 54);
  const by = snap(top(xs + 54)) + 2 * P;
  cell(bx + 3 * P, by - 2 * P, WOOD.ropeDark, P, 3 * P);
  const bw = [4, 6, 7, 7, 7, 6, 5];
  bw.forEach((n, i) => {
    const xx = bx + Math.round((7 - n) / 2) * P;
    cell(xx - P, by + i * P, WOOD.outline, (n + 2) * P, P);
    for (let k = 0; k < n; k++) cell(xx + k * P, by + i * P, (k + i) % 2 ? WOOD.bambooDark : WOOD.bamboo);
  });
  cell(bx, by + 7 * P, WOOD.outline, 7 * P, P);
  const lx = snap(hw - 44);
  const lt = snap(top(lx));
  cell(lx - P, -h / 2 + 2, WOOD.outline, 3 * P, lt - (-h / 2 + 2));
  cell(lx, -h / 2 + 2, WOOD.cap, P, lt - (-h / 2 + 2));
  cell(lx - P, -h / 2 + 2, WOOD.outline, 9 * P, 2 * P);
  cell(lx, -h / 2 + 2, WOOD.cap, 7 * P, P);
  return PNG.sync.write(img);
}

// Roblox takes .ogg, .mp3 and .wav. Names match the keys in Assets.luau.
const audio = {
  uiMove: 'sfx/ui_move.ogg', uiConfirm: 'sfx/ui_confirm.ogg', splash: 'sfx/splash.ogg', gong: 'sfx/gong.ogg',
  slash: 'sfx/slash.ogg', heavy: 'sfx/heavy.ogg', hit: 'sfx/hit.ogg', slip: 'sfx/slip.wav', tell: 'sfx/tell.ogg',
  block: 'sfx/block.ogg', dash: 'sfx/dash.wav', ko: 'sfx/ko.ogg', coin: 'sfx/coin.wav', buy: 'sfx/buy.ogg',
  'music-ocean': 'music/ocean.mp3', 'music-fight': 'music/fight.ogg',
  'voice-fight': 'voice/alba-fx-fight.wav', 'voice-win': 'voice/win.ogg', 'voice-perfect': 'voice/perfect.ogg',
  'voice-timeout': 'voice/timeout.ogg', 'voice-ko': 'voice/ko.ogg', 'voice-round': 'voice/round.ogg',
};
for (let i = 1; i <= 5; i++) audio[`voice-round${i}`] = `voice/round${i}.ogg`;
for (const [name, src] of Object.entries(audio)) {
  if (!existsSync(`${A}/${src}`)) throw new Error(`missing ${src}`);
  copyFileSync(`${A}/${src}`, `${OUT}/audio/${name}${src.slice(src.lastIndexOf('.'))}`);
}
console.log(`wrote ${Object.keys(sheets).length} images and ${Object.keys(audio).length} sounds to ${OUT}/`);
