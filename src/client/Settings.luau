-- Small settings panel (src/ui/settings.ts without the key-rebinding page): music, sfx, hard mode, credits.
-- update() returns true while the panel owns the input (open, or closed this step).
local Draw = require(script.Parent.Draw)
local Hud = require(script.Parent.Hud)

local Settings = {}

local Manifest = require(game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook"):WaitForChild("Manifest"))

local ROWS = { "MUSIC", "SFX", "HARD MODE", "CREDITS", "CLOSE" }
local TAB = { w = 92, h = 26 }
local PANEL = { w = 300, h = 214 }
local CREDITS = { x = 150, y = 70, w = 660, h = 380 }

local function inRect(p: Vector2?, x, y, w, h): boolean
	return p ~= nil and p.X >= x and p.X <= x + w and p.Y >= y and p.Y <= y + h
end

--- anchor = { x, y, panel = "above" | "below" }
function Settings.new(game, anchor)
	local self = {}
	local open = false
	local sel = 0
	local credits = false -- the credits page is showing (over the panel)
	local px = anchor.x
	local py = if anchor.panel == "above" then anchor.y - PANEL.h - 6 else anchor.y + TAB.h + 6

	local function changeVolume(i: number, dir: number)
		local a = game.audio
		local key = if i == 0 then "musicVolume" else "sfxVolume"
		a[key] = math.clamp(math.floor(a[key] * 10 + 0.5) / 10 + dir * 0.1, 0, 1)
		if i == 0 then
			a.applyMusicVolume()
		end
		a.play("uiMove")
		game.savePrefs()
	end

	local function activate(i: number, dir: number)
		if i <= 1 then
			changeVolume(i, dir)
		elseif i == 2 then
			game.state.setHardMode(not game.state.hardMode())
			game.audio.play(if game.state.hardMode() then "tell" else "uiMove")
		elseif i == 3 then
			credits = true
			game.audio.play("uiMove")
		else
			open = false
			game.audio.play("uiMove")
		end
	end

	function self.isOpen()
		return open
	end

	function self.update(_dt: number): boolean
		local inp = game.input
		local c = inp.clicked()
		if not open then
			if inp.pressed("settings") or inRect(c, anchor.x, anchor.y, TAB.w, TAB.h) then
				open = true
				sel = 0
				game.audio.play("uiMove")
				return true
			end
			return false
		end
		if credits then
			-- any button or click goes back to the panel
			if c or inp.anyPressed() then
				credits = false
				game.audio.play("uiMove")
			end
			return true
		end
		if inp.pressed("settings") or inp.pressed("defend") or inp.pressed("shop") then
			open = false
			game.audio.play("uiMove")
			return true
		end
		if c then
			if not inRect(c, px, py, PANEL.w, PANEL.h) then
				open = false
				game.audio.play("uiMove")
				return true
			end
			local i = math.floor((c.Y - py - 16) / 38)
			if i >= 0 and i < #ROWS then
				sel = i
				-- volume rows: left half lowers, right half raises
				activate(i, if c.X < px + PANEL.w * 0.62 then -1 else 1)
			end
			return true
		end
		if inp.pressed("up") then
			sel = (sel + #ROWS - 1) % #ROWS
			game.audio.play("uiMove")
		end
		if inp.pressed("down") then
			sel = (sel + 1) % #ROWS
			game.audio.play("uiMove")
		end
		if sel <= 1 then
			if inp.pressed("left") then
				changeVolume(sel, -1)
			elseif inp.pressed("right") then
				changeVolume(sel, 1)
			end
		elseif inp.pressed("confirm") or inp.pressed("left") or inp.pressed("right") then
			activate(sel, 1)
		end
		return true
	end

	function self.render()
		Draw.layer("settings")
		local hard = game.state.hardMode()
		Draw.box(anchor.x, anchor.y, TAB.w, TAB.h, "#0c0a18", { alpha = 0.8, radius = 6, stroke = if hard then "#ff3b2f" else "#ffdd22", strokeW = 2 })
		Draw.text(`⚙ {game.input.glyph("settings")}{if hard then " · HARD" else ""}`, anchor.x + 9, anchor.y + TAB.h / 2 + 1, { size = 13, align = "left" })
		if not open then
			return
		end
		Hud.panel(px, py, PANEL.w, PANEL.h)
		for i, name in ROWS do
			local y = py + 16 + (i - 1) * 38 + 19
			local on = sel == i - 1
			if on then
				Draw.rect(px + 8, y - 16, PANEL.w - 16, 32, "#ffdd22", 0.18)
			end
			Draw.text(name, px + 20, y, { size = 18, align = "left", color = if on then "#ffdd22" else "#ffffff" })
			local value = ""
			if i == 1 then
				value = `◀ {math.floor(game.audio.musicVolume * 10 + 0.5)} ▶`
			elseif i == 2 then
				value = `◀ {math.floor(game.audio.sfxVolume * 10 + 0.5)} ▶`
			elseif i == 3 then
				value = if hard then "ON" else "OFF"
			end
			Draw.text(value, px + PANEL.w - 20, y, { size = 18, align = "right", color = if i == 3 and hard then "#ff3b2f" else "#ffffff" })
		end
		if credits then
			local C = CREDITS
			Draw.rect(0, 0, 960, 540, "#080614", 0.6)
			Hud.panel(C.x, C.y, C.w, C.h)
			Draw.text("CREDITS", C.x + C.w / 2, C.y + 30, { size = 30, color = "#ffdd22" })
			for i, line in Manifest.text.credits do
				Draw.text(line, C.x + C.w / 2, C.y + 50 + i * 26, { size = 16 })
			end
			Draw.text("PRESS ANY BUTTON", C.x + C.w / 2, C.y + C.h - 22, { size = 14, color = "#ffdd22" })
		end
	end

	return self
end

return Settings
