-- Smoke test: plays every scene (ocean > cutscene > fight > result > shop, settings, all nine fish in both
-- modes) with Draw, Audio and Input mocked, so runtime errors in scene code show up without Studio.
-- Run from the repo root: lune run roblox/tests/scenes.spec.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ROOT = "roblox/src/"
local calls = { draw = 0, audio = 0 }

-- ---------- mocks ----------
local function counter(kind)
	return function()
		calls[kind] += 1
	end
end
-- Strict mocks: only names the real modules define, so a misspelled call fails here, not in Studio.
local function definedNames(file, pattern)
	local names = {}
	for name in string.gmatch(fs.readFile(file), pattern) do
		names[name] = true
	end
	return names
end
local function strictMock(file, pattern, base, kind)
	local names = definedNames(file, pattern)
	return setmetatable(base, {
		__index = function(_, k)
			if not names[k] then
				error(`{file} has no function {k}`, 2)
			end
			return counter(kind)
		end,
	})
end
local DrawMock = strictMock(ROOT .. "client/Draw.luau", "function Draw%.(%w+)", { W = 960, H = 540, color = function(h)
	return h
end }, "draw")
local AUDIO_FILE = ROOT .. "client/Audio.luau"
local TextService = {
	GetTextSize = function(_, str, size)
		return { X = #str * size * 0.6, Y = size }
	end,
}
local EnumMock = setmetatable({}, { __index = function(_, k)
	return setmetatable({}, { __index = function(_, v)
		return k .. "." .. v
	end })
end })
Vector2 = { new = function(x, y)
	return { X = x, Y = y }
end }

-- Virtual instance tree: nodes are paths; require(node) loads the matching file.
local overrides = { ["client/Draw"] = DrawMock }
local loaded = {}
local node
local requireNode
local function makeEnv(path)
	local parts = string.split(path, "/")
	table.remove(parts)
	local parentPath = table.concat(parts, "/")
	return setmetatable({
		script = node(path, parentPath),
		require = requireNode,
		Enum = EnumMock,
		Color3 = { fromRGB = function(r, g, b)
			return { r, g, b }
		end },
		ColorSequenceKeypoint = { new = function(t, c)
			return { t, c }
		end },
		ColorSequence = { new = function(...)
			return { ... }
		end },
		Vector2 = Vector2,
		game = {
			GetService = function(_, name)
				if name == "ReplicatedStorage" then
					return node("svc", "")
				elseif name == "TextService" then
					return TextService
				end
				error("unmocked service " .. name)
			end,
		},
	}, { __index = _G })
end
function node(path, parentPath)
	return setmetatable({ __path = path }, {
		__index = function(self, k)
			if k == "Parent" then
				local p = string.split(parentPath or "", "/")
				table.remove(p)
				return node(parentPath, table.concat(p, "/"))
			elseif k == "WaitForChild" then
				return function(_, n)
					return self[n]
				end
			end
			local child = if path == "svc" and k == "SamuraiHook" then "shared" else path .. "/" .. k
			return node(child, path)
		end,
	})
end
function requireNode(n)
	local path = rawget(n, "__path")
	if overrides[path] then
		return overrides[path]
	end
	if loaded[path] == nil then
		local file = ROOT .. path .. ".luau"
		local fn = luau.load(fs.readFile(file), { debugName = path, environment = makeEnv(path) })
		loaded[path] = fn()
	end
	return loaded[path]
end
local function req(path)
	return requireNode(node(path, ""))
end

local State = req("shared/State")
local Manifest = req("shared/Manifest")

-- Scripted input: the test sets what is held / pressed for the next step.
local function makeInput()
	local i = { heldSet = {}, pressSet = {}, mx = 0, my = 0, click = nil }
	function i.update() end
	function i.held(a)
		return i.heldSet[a] == true
	end
	function i.pressed(a)
		return i.pressSet[a] == true
	end
	function i.anyPressed()
		return next(i.pressSet) ~= nil
	end
	function i.moveX()
		return i.mx
	end
	function i.moveY()
		return i.my
	end
	function i.device()
		return "keyboard"
	end
	function i.glyph(a)
		return a
	end
	function i.clicked()
		return i.click
	end
	function i.tapped()
		return false
	end
	function i.dragging()
		return false
	end
	function i.dragDX()
		return 0
	end
	function i.setPromptHits() end
	return i
end

local function makeGame()
	local g = { width = 960, height = 540, time = 0, input = makeInput(), state = State.new(nil), sceneId = nil }
	g.audio = strictMock(AUDIO_FILE, "function self%.(%w+)", { musicVolume = 0.8, sfxVolume = 0.8 }, "audio")
	g.savePrefs = function() end
	g.setTouchFight = function() end
	local factories = {}
	for _, id in { "ocean", "cutscene", "fight", "result", "shop" } do
		local name = string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
		factories[id] = req("client/Scenes/" .. name)
	end
	function g.go(id, params)
		if g.scene and g.scene.exit then
			g.scene.exit()
		end
		g.sceneId = id
		g.scene = factories[id](g, params)
		if g.scene.enter then
			g.scene.enter()
		end
	end
	--- One fixed step plus a render, with `inp` = { press = {...}, hold = {...}, mx, my, click }.
	function g.step(inp)
		local i = g.input
		i.pressSet, i.heldSet = {}, {}
		for _, a in (inp and inp.press) or {} do
			i.pressSet[a] = true
		end
		for _, a in (inp and inp.hold) or {} do
			i.heldSet[a] = true
		end
		i.mx, i.my = (inp and inp.mx) or 0, (inp and inp.my) or 0
		i.click = inp and inp.click
		g.scene.update(1 / 60)
		g.time += 1 / 60
		g.scene.render()
	end
	return g
end

local function check(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local function runUntil(g, want, maxSteps, inputFn)
	for n = 1, maxSteps do
		if g.sceneId == want then
			return n
		end
		g.step(inputFn(n))
	end
	error(`never reached {want} (stuck in {g.sceneId})`, 2)
end

-- ---------- the loop ----------
math.randomseed(7)
local g = makeGame()
g.state.loadPreset(Manifest.demoStart)
g.go("ocean", nil)
for _ = 1, 30 do
	g.step(nil)
end
-- cast, steer side to side and sink fast until something bites (re-cast if the line comes back up)
runUntil(g, "cutscene", 60 * 120, function(n)
	return { press = if n % 90 == 1 then { "confirm" } else {}, mx = math.sin(n / 40), my = 1 }
end)
runUntil(g, "fight", 60 * 4, function()
	return nil
end)
-- mash: quick mostly, heavy sometimes, jump now and then
runUntil(g, "result", 60 * 60, function(n)
	local press = {}
	if n % 7 == 0 then
		table.insert(press, "quick")
	end
	if n % 23 == 0 then
		table.insert(press, "heavy")
	end
	if n % 61 == 0 then
		table.insert(press, "up")
	end
	return { press = press, mx = if n % 120 < 60 then 1 else -1, hold = if n % 50 < 5 then { "defend" } else {} }
end)
runUntil(g, "ocean", 60 * 7, function()
	return nil
end)
print("loop ocean > cutscene > fight > result > ocean ok")

-- pause in a fight
g.go("fight", { fish = g.state.makeFish("shark", 0) })
for n = 1, 200 do
	g.step({ press = if n == 100 or n == 150 then { "settings" } else {} })
end

-- shop: buy, move, fail to buy, mouse click a board, settings panel, leave
g.go("shop", nil)
local goldBefore = g.state.gold()
local inputs = {
	{ press = { "confirm" } }, { press = { "right" } }, { press = { "confirm" } }, { press = { "left" } },
	{ click = Vector2.new(300, 200) }, { click = Vector2.new(520, 200) }, { click = Vector2.new(520, 200) },
	{ press = { "settings" } }, { press = { "down" } }, { press = { "right" } }, { press = { "down" } },
	{ press = { "confirm" } }, { click = Vector2.new(100, 120) }, { press = { "settings" } },
}
for _ = 1, 20 do
	g.step(nil)
end
for _, inp in inputs do
	g.step(inp)
	g.step(nil)
end
check(g.state.gold() < goldBefore, "shop bought nothing")
check(g.state.hardMode(), "settings did not toggle hard mode")
g.step({ press = { "shop" } })
check(g.sceneId == "ocean", "shop did not leave")
print("shop and settings ok")

-- every fish, both modes, every outcome screen
for _, hard in { false, true } do
	g.state.setHardMode(hard)
	for _, def in Manifest.fish do
		for tier = 0, 1 do
			local f = g.state.makeFish(def.id, tier)
			g.go("cutscene", { fish = f })
			for _ = 1, 160 do
				g.step(nil)
			end
			check(g.sceneId == "fight", "cutscene did not move on for " .. def.id)
			for n = 1, 60 * 20 do
				g.step({ press = if n % 9 == 0 then { "quick" } elseif n % 31 == 0 then { "heavy" } else {}, mx = math.sin(n / 30), hold = if n % 40 < 8 then { "down" } else {} })
				if g.sceneId ~= "fight" then
					break
				end
			end
		end
		for _, outcome in { "win", "timeout", "ko" } do
			g.go("result", { fish = g.state.makeFish(def.id, 0), outcome = outcome, goldEarned = 10, perfect = true })
			for _ = 1, 100 do
				g.step(nil)
			end
		end
	end
end
print(`all fish fights and result screens ok ({calls.draw} draw calls, {calls.audio} sounds)`)

-- credits page: settings > CREDITS opens it, any button closes it, the panel stays open
g.go("ocean", nil)
for _ = 1, 5 do
	g.step(nil)
end
local creditsDraws = 0
for _, inp in { { press = { "settings" } }, { press = { "down" } }, { press = { "down" } }, { press = { "down" } }, { press = { "confirm" } } } do
	g.step(inp)
end
local before = calls.draw
g.step(nil)
creditsDraws = calls.draw - before
g.step({ press = { "quick" } }) -- closes the credits page
before = calls.draw
g.step(nil)
check(creditsDraws > calls.draw - before + #Manifest.text.credits, "credits page did not open")
g.step({ press = { "settings" } }) -- closes the panel
g.step({ press = { "confirm" } }) -- the ocean has its input back: casts
check(g.sceneId == "ocean", "credits test left the ocean")
print("credits page ok")
