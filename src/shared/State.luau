-- Roblox copy of src/game/state.ts: gold, upgrade levels and everything derived from them.
-- `save` (optional) is called with the plain save table after every change.
local Manifest = require(script.Parent.Manifest)

local State = {}

local function jsRound(x: number): number
	return math.floor(x + 0.5)
end
State.jsRound = jsRound

local function fresh()
	return { gold = 0, round = 0, levels = { damage = 0, depth = 0, gold = 0 }, hard = false }
end

local function defOf(id: string)
	for _, u in Manifest.upgrades do
		if u.id == id then
			return u
		end
	end
	error("Unknown upgrade " .. id)
end

function State.upgradeCost(def, level: number): number
	return jsRound(def.baseCost * def.growth ^ level)
end

local function levelName(def, level: number): string
	local last = #def.names - 1
	if level <= last then
		return def.names[level + 1]
	end
	return `{def.names[last + 1]} +{level - last}`
end

local function finiteInt(v: any, fallback: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or v < 0 then
		return fallback
	end
	return math.floor(v)
end

--- Cleans a save that came from storage (or a client): unknown or broken fields fall back to fresh values.
function State.sanitize(raw: any)
	local d = fresh()
	if type(raw) ~= "table" then
		return d
	end
	d.gold = finiteInt(raw.gold, 0)
	d.round = finiteInt(raw.round, 0)
	d.hard = raw.hard == true
	if type(raw.levels) == "table" then
		for id in d.levels do
			d.levels[id] = finiteInt(raw.levels[id], 0)
		end
	end
	return d
end

local function shallowCopy(t)
	local c = {}
	for k, v in t do
		c[k] = v
	end
	return c
end

function State.new(saved: any?, save: ((any) -> ())?)
	local data = State.sanitize(saved)
	local function doSave()
		if save then
			save(data)
		end
	end

	local function damageMult(lvl: number?)
		return 1 + defOf("damage").perLevel * (lvl or data.levels.damage)
	end
	local function maxDepth(lvl: number?)
		return Manifest.ocean.startDepth + defOf("depth").perLevel * (lvl or data.levels.depth)
	end
	local function goldMult(lvl: number?)
		return 1 + defOf("gold").perLevel * (lvl or data.levels.gold)
	end

	local function effect(id: string, lvl: number): string
		if id == "damage" then
			return string.format("DAMAGE x%.2f > x%.2f", damageMult(lvl), damageMult(lvl + 1))
		elseif id == "depth" then
			return `DEPTH {maxDepth(lvl)} M > {maxDepth(lvl + 1)} M`
		end
		return string.format("RYO x%.2f > x%.2f", goldMult(lvl), goldMult(lvl + 1))
	end

	local self = {}

	function self.data()
		return data
	end
	function self.gold()
		return data.gold
	end
	function self.round()
		return data.round
	end
	function self.hardMode()
		return data.hard
	end
	function self.setHardMode(on: boolean)
		data.hard = on == true
		doSave()
	end
	function self.maxDepth()
		return maxDepth()
	end
	function self.samurai()
		return {
			maxHp = Manifest.samurai.maxHp,
			quickDamage = Manifest.samurai.quickDamage * damageMult(),
			heavyDamage = Manifest.samurai.heavyDamage * damageMult(),
		}
	end

	--- The one place hard mode is applied (as in makeFish in src/game/state.ts).
	function self.makeFish(fishId: string, tier: number)
		local d
		for _, f in Manifest.fish do
			if f.id == fishId then
				d = f
			end
		end
		if not d then
			error(`Unknown fish "{fishId}"`)
		end
		local t = math.max(0, math.floor(tier))
		local prefixes = Manifest.tiers.prefixes
		local prefix = if t == 0 then "" else (prefixes[t + 1] or `{prefixes[#prefixes]} x{t}`)
		local hm = Manifest.hardMode.damageMult
		local eff = shallowCopy(d)
		if data.hard then
			if d.attack then
				eff.attack = shallowCopy(d.attack)
				eff.attack.damage = d.attack.damage * hm
			end
			if d.special then
				eff.special = shallowCopy(d.special)
				eff.special.damage = d.special.damage * hm
			end
			eff.contactDamage = Manifest.hardMode.contactDamage
		else
			if d.category == "slippery" then
				eff.special = nil
			end
			eff.poison = nil
			eff.contactDamage = nil
		end
		local name = string.upper((string.gsub(`{prefix} {d.name}`, "^%s+", "")))
		return {
			def = eff,
			tier = t,
			name = name,
			maxHp = jsRound(d.hp * Manifest.tiers.hpMult ^ t * (if data.hard then Manifest.hardMode.hpMult else 1)),
			gold = jsRound(d.gold * Manifest.tiers.goldMult ^ t),
		}
	end

	function self.upgrades()
		local out = {}
		for _, u in Manifest.upgrades do
			local level = data.levels[u.id]
			local cost = State.upgradeCost(u, level)
			table.insert(out, {
				id = u.id, label = u.label, level = level, cost = cost, affordable = data.gold >= cost,
				name = levelName(u, level), effect = effect(u.id, level),
			})
		end
		return out
	end

	function self.buy(id: string): boolean
		local cost = State.upgradeCost(defOf(id), data.levels[id])
		if data.gold < cost then
			return false
		end
		data.gold -= cost
		data.levels[id] += 1
		doSave()
		return true
	end

	function self.pickFish(depth: number, rng: (() -> number)?)
		local r = rng or math.random
		local tier = math.floor(depth / Manifest.tiers.depth)
		local localDepth = depth - tier * Manifest.tiers.depth
		local options = {}
		for _, f in Manifest.fish do
			if localDepth >= f.depthMin and localDepth <= f.depthMax then
				table.insert(options, f)
			end
		end
		if #options == 0 then
			return nil
		end
		return self.makeFish(options[(math.floor(r() * #options) % #options) + 1].id, tier)
	end

	function self.nextRound(): number
		data.round += 1
		doSave()
		return data.round
	end

	function self.sell(f): number
		local earned = jsRound(f.gold * goldMult())
		data.gold += earned
		doSave()
		return earned
	end

	function self.reset()
		local hard = data.hard
		data = fresh()
		data.hard = hard
		doSave()
	end

	function self.loadPreset(preset)
		local hard = data.hard
		data = fresh()
		data.hard = hard
		data.gold = preset.gold
		data.levels = shallowCopy(preset.levels)
		doSave()
	end

	return self
end

return State
