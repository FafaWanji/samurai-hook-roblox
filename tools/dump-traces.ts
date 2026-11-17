// Records fights from the TypeScript sim so tests/sim.spec.luau can replay them in the Luau port.
// Run from the repo root: npx vite-node roblox/tools/dump-traces.ts
// Writes roblox/tests/fixtures/traces.json (git-ignored, rebuilt on demand).
import { mkdirSync, writeFileSync } from 'node:fs';
import { createFight } from '../../src/fight/sim';
import { createGameState } from '../../src/game/state';
import { fish as fishDefs } from '../../src/manifest';
import type { FightInput } from '../../src/types';
import { DT, NONE, competentBot, mulberry32, statsAt } from '../../tests/fightBots';

/** Random button mashing with some persistence, so odd paths (dash, jump, buffer, block) get hit too. */
function chaosBot(seed: number) {
  const r = mulberry32(seed);
  let hold: FightInput = NONE;
  let left = 0;
  return (): FightInput => {
    if (--left <= 0) {
      left = 1 + Math.floor(r() * 20);
      hold = {
        moveX: r() < 0.6 ? (r() < 0.5 ? -1 : 1) * (r() < 0.7 ? 1 : r()) : 0,
        quick: false, heavy: false,
        defendHeld: r() < 0.25, defendPressed: false,
        jump: false, crouch: r() < 0.15,
      };
    }
    return {
      ...hold,
      quick: r() < 0.08, heavy: r() < 0.04, defendPressed: r() < 0.05, jump: r() < 0.03,
      walkScale: r() < 0.1 ? 1.5 : 1,
    };
  };
}

const round = (v: number) => Math.round(v * 1e6) / 1e6;

const traces: unknown[] = [];
for (const hard of [false, true]) {
  for (const def of fishDefs) {
    for (const [botName, tier, dmgLvl] of [['competent', 0, 2], ['chaos', 1, 0], ['competent', 0, 6]] as const) {
      const gs = createGameState(null);
      gs.hardMode = hard;
      const inst = gs.makeFish(def.id, tier);
      const stats = statsAt(dmgLvl);
      const seedRng = mulberry32(def.hp * 7 + tier * 13 + dmgLvl + (hard ? 1000 : 0));
      const rngLog: number[] = [];
      const sim = createFight(inst, stats, () => { const v = seedRng(); rngLog.push(v); return v; });
      const bot = botName === 'competent' ? competentBot() : chaosBot(def.hp + dmgLvl);
      const steps: unknown[] = [];
      const maxSteps = Math.ceil((inst.def.timer + 6) * 60);
      for (let i = 0; i < maxSteps && sim.state.phase !== 'over'; i++) {
        const inp = sim.state.phase === 'fighting' ? bot(sim.state, inst.def) : NONE;
        const ev = sim.step(DT, inp);
        const s = sim.state.samurai;
        const f = sim.state.fish;
        steps.push({
          i: inp,
          e: ev.map((e) => [e.type, round(e.x), round(e.y), e.damage === undefined ? null : round(e.damage)]),
          s: [round(s.x), round(s.y), round(s.hp), s.move, s.stage ?? '', s.facing, s.hits, s.misses, round(s.poisonLeft)],
          f: [round(f.x), round(f.y), round(f.hp), f.mode, f.slipReady, round(f.vulnLeft), f.facing, round(f.tellProgress)],
          g: [sim.state.phase, sim.state.outcome ?? '', round(sim.state.timeLeft), sim.state.projectiles.length, round(sim.state.effects.inkLeft)],
        });
      }
      traces.push({
        fish: def.id, hard, tier, stats, bot: botName,
        inst: { name: inst.name, maxHp: inst.maxHp, gold: inst.gold },
        rng: rngLog, steps,
      });
    }
  }
}

// State checks: upgrade rows and costs at a few levels.
const gs = createGameState(null);
gs.loadPreset({ gold: 100000, levels: { damage: 3, depth: 9, gold: 11 } });
const upgradesAt = gs.upgrades();
const sold = gs.sell(gs.makeFish('shark', 2));

mkdirSync('roblox/tests/fixtures', { recursive: true });
writeFileSync('roblox/tests/fixtures/traces.json', JSON.stringify({ traces, state: { upgrades: upgradesAt, sold, maxDepth: gs.maxDepth, samurai: gs.samurai } }));
console.log(`wrote ${traces.length} fights, ${traces.reduce((n, t) => n + (t as { steps: unknown[] }).steps.length, 0)} steps`);
