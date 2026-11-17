-- Save server. The server owns every player's progress (gold, upgrades, rounds): the client plays the
-- game locally and only asks for changes, which are checked here first. Saved in a DataStore;
-- without one (unpublished place, or API access off) progress lasts for the session only.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local State = require(Shared:WaitForChild("State"))

local STORE_NAME = "SamuraiHookSave_v1"
local AUTOSAVE_EVERY = 60
local MAX_ACTS_PER_SECOND = 20
-- A fight cannot be won faster than this after it starts (cutscene lock + "FIGHT!" intro + a hit).
local MIN_FIGHT_SECONDS = Manifest.cutscene.inputLock + Manifest.fight.introDelay + 0.5

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local loadFn = Instance.new("RemoteFunction")
loadFn.Name = "Load"
loadFn.Parent = remotes
local act = Instance.new("RemoteEvent")
act.Name = "Act"
act.Parent = remotes
remotes.Parent = Shared

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[SamuraiHook] DataStore unavailable, progress will not be saved:", result)
	end
end

type Session = {
	state: any,
	prefs: { music: number, sfx: number },
	loaded: boolean,
	canSave: boolean, -- false when loading failed: never overwrite a save we could not read
	dirty: boolean,
	roundAt: number, -- os.clock() of the last "round" (fight start)
	soldThisRound: boolean,
	acts: number,
	actWindow: number,
}
local sessions: { [Player]: Session } = {}

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function cleanPrefs(raw: any)
	local p = { music = 0.8, sfx = 0.8 }
	if type(raw) == "table" then
		for k in p do
			local v = raw[k]
			if type(v) == "number" and v == v then
				p[k] = math.clamp(v, 0, 1)
			end
		end
	end
	return p
end

local function withRetry(fn: () -> any, pause: number): (boolean, any)
	local ok, result
	for attempt = 1, 3 do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(pause * attempt)
		end
	end
	return false, result
end

-- shortcut: no session locking, so joining a second server within seconds of leaving one can save over
-- newer progress; upgrade to ProfileStore if the game gets trading, leaderboards or purchases.
local function save(player: Player)
	local s = sessions[player]
	if not s or not s.canSave or not s.dirty or not store then
		return
	end
	s.dirty = false
	local payload = { state = State.sanitize(s.state.data()), prefs = s.prefs, version = 1 }
	local ok, err = withRetry(function()
		return (store :: DataStore):UpdateAsync(keyFor(player), function()
			return payload
		end)
	end, 1)
	if not ok then
		s.dirty = true
		warn("[SamuraiHook] save failed for", player.Name, err)
	end
end

local function load(player: Player)
	local s: Session = {
		state = State.new(nil),
		prefs = cleanPrefs(nil),
		loaded = false,
		canSave = store ~= nil,
		dirty = false,
		roundAt = -math.huge,
		soldThisRound = true,
		acts = 0,
		actWindow = 0,
	}
	sessions[player] = s
	if store then
		local ok, raw = withRetry(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end, 0.25)
		if ok then
			if type(raw) == "table" then
				s.state = State.new(raw.state)
				s.prefs = cleanPrefs(raw.prefs)
			end
		else
			s.canSave = false
			warn("[SamuraiHook] could not load save for", player.Name, "- this session will not be saved:", raw)
		end
	end
	s.loaded = true
end

loadFn.OnServerInvoke = function(player: Player)
	local s = sessions[player]
	while s and not s.loaded do
		task.wait()
	end
	if not s then
		return nil
	end
	return { state = State.sanitize(s.state.data()), prefs = s.prefs, studio = RunService:IsStudio() }
end

local UPGRADE_IDS = { damage = true, depth = true, gold = true }
local function fishById(id: any)
	for _, f in Manifest.fish do
		if f.id == id then
			return f
		end
	end
	return nil
end

act.OnServerEvent:Connect(function(player: Player, op: any, a: any, b: any)
	local s = sessions[player]
	if not s or not s.loaded or type(op) ~= "string" then
		return
	end
	-- rate limit
	local now = os.clock()
	if now - s.actWindow >= 1 then
		s.actWindow = now
		s.acts = 0
	end
	s.acts += 1
	if s.acts > MAX_ACTS_PER_SECOND then
		return
	end

	local st = s.state
	if op == "buy" then
		if UPGRADE_IDS[a] and st.buy(a) then
			s.dirty = true
		end
	elseif op == "round" then
		st.nextRound()
		s.roundAt = now
		s.soldThisRound = false
		s.dirty = true
	elseif op == "sell" then
		-- One sale per fight, not sooner than a fight can be won, and only a fish the line can reach.
		local def = fishById(a)
		if not def or type(b) ~= "number" or b ~= math.floor(b) or b < 0 then
			return
		end
		if s.soldThisRound or now - s.roundAt < MIN_FIGHT_SECONDS then
			return
		end
		if def.depthMin + b * Manifest.tiers.depth > st.maxDepth() then
			return
		end
		s.soldThisRound = true
		st.sell(st.makeFish(def.id, b))
		s.dirty = true
	elseif op == "hard" then
		st.setHardMode(a == true)
		s.dirty = true
	elseif op == "prefs" then
		s.prefs = cleanPrefs({ music = a, sfx = b })
		s.dirty = true
	elseif op == "reset" then
		st.reset()
		s.dirty = true
	elseif op == "demo" and RunService:IsStudio() then
		st.loadPreset(Manifest.demoStart)
		s.dirty = true
	end
end)

-- Sprites uploaded as Decals: an ImageLabel needs the image inside the decal. Look it up once and publish
-- it as an attribute (Assets.image reads it). LoadAsset works for assets the place's owner owns.
local function resolveDecals()
	local InsertService = game:GetService("InsertService")
	local Assets = require(Shared:WaitForChild("Assets"))
	for key, s in Assets.sprites do
		if s.decal and s.id ~= "" then
			local ok, model = pcall(InsertService.LoadAsset, InsertService, tonumber(string.match(s.id, "%d+")))
			local decal = ok and model and model:FindFirstChildWhichIsA("Decal", true)
			if decal then
				Shared:SetAttribute("img_" .. key, decal.Texture)
				model:Destroy()
			else
				warn("[SamuraiHook] could not read the image in decal", key, s.id, if ok then "" else model)
			end
		end
	end
end
task.spawn(resolveDecals)

Players.PlayerAdded:Connect(load)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end
Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_EVERY)
		for player in sessions do
			task.spawn(save, player)
		end
	end
end)

-- Save everyone in parallel on shutdown (30 s limit).
game:BindToClose(function()
	local pending = 0
	for player in sessions do
		pending += 1
		task.spawn(function()
			save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
