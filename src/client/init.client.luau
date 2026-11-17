-- Samurai Hook client: boots the GUI canvas, runs the fixed 60 Hz loop and switches scenes (src/main.ts).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local State = require(Shared:WaitForChild("State"))
local Draw = require(script.Draw)
local Input = require(script.Input)
local Audio = require(script.Audio)
local TouchButtons = require(script.TouchButtons)

local STEP = 1 / 60
local player = Players.LocalPlayer

-- Full-screen 2D game: no backpack, chat, player list (Tab is the pause key) or gamepad UI cursor.
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false) then
			break
		end
		task.wait(0.5)
	end
end)
GuiService.AutoSelectGuiEnabled = false

local screen = Draw.init(player:WaitForChild("PlayerGui"))

-- Load every image up front, so no sprite shows blank the first time it is drawn.
task.spawn(function()
	local Assets = require(Shared:WaitForChild("Assets"))
	local ids = {}
	for key in Assets.sprites do
		local id = Assets.image(key)
		if id ~= "" then
			table.insert(ids, id)
		end
	end
	pcall(game:GetService("ContentProvider").PreloadAsync, game:GetService("ContentProvider"), ids)
end)
local input = Input.new(screen)
local audio = Audio.new()
local touch = if UserInputService.TouchEnabled then TouchButtons.new(screen, input) else nil

-- Progress lives on the server (src/server). The client keeps a copy for instant feedback and
-- sends every change to the server, which checks it and saves it.
local remotes = Shared:WaitForChild("Remotes", 15)
local act = remotes and remotes:WaitForChild("Act", 5)
local saved = nil
if remotes then
	local ok, result = pcall(function()
		return remotes:WaitForChild("Load"):InvokeServer()
	end)
	if ok then
		saved = result
	end
end
local isStudio = saved ~= nil and saved.studio == true
local function send(...)
	if act then
		act:FireServer(...)
	end
end

local localState = State.new(saved and saved.state)
if saved and saved.prefs then
	audio.musicVolume = saved.prefs.music
	audio.sfxVolume = saved.prefs.sfx
end

-- Same interface as State, plus the server call for every change.
local gs = setmetatable({}, { __index = localState })
function gs.buy(id)
	local ok = localState.buy(id)
	if ok then
		send("buy", id)
	end
	return ok
end
function gs.nextRound()
	send("round")
	return localState.nextRound()
end
function gs.sell(f)
	send("sell", f.def.id, f.tier)
	return localState.sell(f)
end
function gs.setHardMode(on)
	send("hard", on)
	localState.setHardMode(on)
end
function gs.reset()
	send("reset")
	localState.reset()
end

local Scenes = script.Scenes
local factories = {
	ocean = require(Scenes.Ocean),
	cutscene = require(Scenes.Cutscene),
	fight = require(Scenes.Fight),
	result = require(Scenes.Result),
	shop = require(Scenes.Shop),
}

local scene = nil
local g = { width = 960, height = 540, time = 0, input = input, audio = audio, state = gs, menuOpened = GuiService.MenuOpened }

function g.go(id: string, params)
	if scene and scene.exit then
		scene.exit()
	end
	Draw.reset() -- fresh objects for the new scene (see Draw.reset)
	scene = factories[id](g, params)
	if scene.enter then
		scene.enter()
	end
end
function g.savePrefs()
	send("prefs", audio.musicVolume, audio.sfxVolume)
end
function g.setTouchFight(on: boolean)
	if touch then
		touch.setVisible(on)
	end
end

-- Studio shortcuts: F2 = start with demo progress, F4 = wipe the save, 1-3 = result screens, 4 = next fish fight.
local devFish = 0
UserInputService.InputBegan:Connect(function(io, processed)
	if processed or not isStudio then
		return
	end
	if io.KeyCode == Enum.KeyCode.F2 then
		send("demo")
		localState.loadPreset(Manifest.demoStart)
		audio.play("buy")
		g.go("ocean", nil)
	elseif io.KeyCode == Enum.KeyCode.F4 then
		gs.reset()
		audio.play("uiDeny")
		g.go("ocean", nil)
	elseif io.KeyCode == Enum.KeyCode.One or io.KeyCode == Enum.KeyCode.Two or io.KeyCode == Enum.KeyCode.Three then
		-- Test screens: 1 win, 2 timeout, 3 K.O. result (no gold is paid out).
		local outcome = if io.KeyCode == Enum.KeyCode.One then "win" elseif io.KeyCode == Enum.KeyCode.Two then "timeout" else "ko"
		local f = localState.makeFish(Manifest.fish[math.random(1, #Manifest.fish)].id, 0)
		g.go("result", { fish = f, outcome = outcome, goldEarned = 0, perfect = outcome == "win" })
	elseif io.KeyCode == Enum.KeyCode.Four then
		-- Test fights: 4 starts a fight with the next fish in the roster.
		devFish = devFish % #Manifest.fish + 1
		g.go("fight", { fish = localState.makeFish(Manifest.fish[devFish].id, 0) })
	end
end)

g.go("ocean", nil)

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += math.min(0.1, dt)
	while acc >= STEP do
		input.update()
		if scene then
			scene.update(STEP)
		end
		g.time += STEP
		acc -= STEP
	end
	Draw.begin()
	if scene then
		scene.render()
	end
	Draw.finish()
end)
