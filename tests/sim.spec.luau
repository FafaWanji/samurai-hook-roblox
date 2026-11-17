-- Replays fights recorded from the TypeScript sim (roblox/tools/dump-traces.ts) through the Luau port
-- and stops at the first step that differs. Run from the repo root:
--   npx vite-node roblox/tools/dump-traces.ts
--   lune run roblox/tests/sim.spec.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

-- Loads the shared ModuleScripts the way Roblox would: `require(script.Parent.X)`.
local SHARED = "roblox/src/shared/"
local loaded = {}
local function load(name: string)
	if loaded[name] then
		return loaded[name]
	end
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __module = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = parent },
		require = function(m)
			return load(m.__module)
		end,
	}, { __index = _G })
	local fn = luau.load(fs.readFile(SHARED .. name .. ".luau"), { debugName = name, environment = env })
	loaded[name] = fn()
	return loaded[name]
end

local Sim = load("Sim")
local State = load("State")

local data = serde.decode("json", fs.readFile("roblox/tests/fixtures/traces.json"))
local TOL = 1e-4
local failures = 0

local function near(a, b)
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= TOL * math.max(1, math.abs(b))
	end
	return a == b
end

local function compareArr(label, got, want, where)
	for k = 1, #want do
		if not near(got[k], want[k]) then
			error(string.format("%s: %s[%d] got %s want %s", where, label, k, tostring(got[k]), tostring(want[k])), 0)
		end
	end
end

local function r6(v)
	return v
end

for n, tr in data.traces do
	local where = `#{n} {tr.fish} hard={tr.hard} tier={tr.tier} bot={tr.bot}`
	local ok, err = pcall(function()
		local gs = State.new(nil)
		gs.setHardMode(tr.hard)
		local inst = gs.makeFish(tr.fish, tr.tier)
		assert(inst.name == tr.inst.name, `{where}: name {inst.name} ~= {tr.inst.name}`)
		assert(inst.maxHp == tr.inst.maxHp, `{where}: maxHp {inst.maxHp} ~= {tr.inst.maxHp}`)
		assert(inst.gold == tr.inst.gold, `{where}: gold {inst.gold} ~= {tr.inst.gold}`)
		local ri = 0
		local sim = Sim.create(inst, tr.stats, function()
			ri += 1
			local v = tr.rng[ri]
			if v == nil then
				error(`{where}: Luau sim asked for more random numbers than TS ({ri})`, 0)
			end
			return v
		end)
		for si, st in tr.steps do
			local at = `{where} step {si}`
			local ev = sim.step(1 / 60, st.i)
			if #ev ~= #st.e then
				local names = {}
				for _, e in ev do
					table.insert(names, e.type)
				end
				local wantNames = {}
				for _, e in st.e do
					table.insert(wantNames, e[1])
				end
				error(`{at}: events [{table.concat(names, ",")}] want [{table.concat(wantNames, ",")}]`, 0)
			end
			for k, e in ev do
				compareArr("event", { e.type, e.x, e.y, if e.damage == nil then nil else e.damage }, st.e[k], at)
			end
			local s, f, g = sim.state.samurai, sim.state.fish, sim.state
			compareArr("samurai", { s.x, s.y, s.hp, s.move, s.stage or "", s.facing, s.hits, s.misses, s.poisonLeft }, st.s, at)
			compareArr("fish", { f.x, f.y, f.hp, f.mode, f.slipReady, f.vulnLeft, f.facing, f.tellProgress }, st.f, at)
			compareArr("game", { g.phase, g.outcome or "", g.timeLeft, #g.projectiles, g.effects.inkLeft }, st.g, at)
		end
		assert(ri == #tr.rng, `{where}: used {ri} random numbers, TS used {#tr.rng}`)
	end)
	if not ok then
		failures += 1
		print("FAIL " .. tostring(err))
	end
end
local _ = r6

-- State: upgrade rows, selling, derived stats.
do
	local gs = State.new(nil)
	gs.loadPreset({ gold = 100000, levels = { damage = 3, depth = 9, gold = 11 } })
	local rows = gs.upgrades()
	for k, want in data.state.upgrades do
		local got = rows[k]
		for _, key in { "id", "label", "level", "cost", "affordable", "name", "effect" } do
			if got[key] ~= want[key] then
				failures += 1
				print(`FAIL state upgrade {k} {key}: got {got[key]} want {want[key]}`)
			end
		end
	end
	local sold = gs.sell(gs.makeFish("shark", 2))
	if sold ~= data.state.sold then
		failures += 1
		print(`FAIL state sold {sold} want {data.state.sold}`)
	end
	if gs.maxDepth() ~= data.state.maxDepth then
		failures += 1
		print(`FAIL state maxDepth {gs.maxDepth()} want {data.state.maxDepth}`)
	end
	-- sanitize refuses broken saves
	local bad = State.sanitize({ gold = -5, round = 0 / 0, levels = { damage = math.huge, depth = "x" }, hard = "yes" })
	assert(bad.gold == 0 and bad.round == 0 and bad.levels.damage == 0 and bad.levels.depth == 0 and bad.hard == false, "sanitize")
end

local steps = 0
for _, tr in data.traces do
	steps += #tr.steps
end
print(`{#data.traces} fights, {steps} steps compared, {failures} failures`)
if failures > 0 then
	error("sim.spec failed", 0)
end
