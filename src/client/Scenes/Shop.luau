-- The harbour shop (src/scenes/shop.ts): three endless upgrade tracks on signboards.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local Draw = require(script.Parent.Parent.Draw)
local Hud = require(script.Parent.Parent.Hud)
local Settings = require(script.Parent.Parent.Settings)

local T = Manifest.text
local LOCK = 0.2
local BOARD_W, BOARD_H, BOARD_GAP, BOARD_X0, BOARD_Y = 196, 240, 26, 270, 132
local EMBLEM = { damage = "刀", depth = "糸", gold = "名" }
local INK, PAPER, VERMILION, GOLD = "#1a0a0a", "#f4ead2", "#d9381e", "#ffdd22"

local function boardX(i: number): number
	return BOARD_X0 + (i - 1) * (BOARD_W + BOARD_GAP)
end

local function wrap(text: string, maxW: number, size: number): { string }
	local lines, cur = {}, ""
	for _, word in string.split(text, " ") do
		local try = if cur == "" then word else cur .. " " .. word
		if Hud.textW(try, size) > maxW and cur ~= "" then
			table.insert(lines, cur)
			cur = word
		else
			cur = try
		end
	end
	if cur ~= "" then
		table.insert(lines, cur)
	end
	return lines
end

return function(g, _params)
	local t = 0
	local sel = 1
	local flash, flashRow = 0, 0
	local broke, brokeRow = 0, 1
	local lifted = { 0, 0, 0 }
	local settings = Settings.new(g, { x = 12, y = 12, panel = "below" })
	local scene = {}

	function scene.enter()
		g.audio.music("ocean")
	end

	function scene.update(dt)
		t += dt
		flash = math.max(0, flash - dt)
		broke = math.max(0, broke - dt)
		for i = 1, 3 do
			lifted[i] += ((if i == sel then 1 else 0) - lifted[i]) * math.min(1, dt * 14)
		end
		if t < LOCK then
			return
		end
		if settings.update(dt) then
			return
		end
		local rows = g.state.upgrades()
		local inp = g.input
		if inp.pressed("left") then
			sel = (sel - 2 + #rows) % #rows + 1
			g.audio.play("uiMove")
		end
		if inp.pressed("right") then
			sel = sel % #rows + 1
			g.audio.play("uiMove")
		end
		local c = inp.clicked()
		local hit = 0
		if c then
			for i = 1, #rows do
				if c.X >= boardX(i) and c.X <= boardX(i) + BOARD_W and c.Y >= BOARD_Y and c.Y <= BOARD_Y + BOARD_H then
					hit = i
				end
			end
		end
		if hit > 0 and hit ~= sel then
			sel = hit
			g.audio.play("uiMove")
		elseif inp.pressed("confirm") or hit == sel then
			if g.state.buy(rows[sel].id) then
				g.audio.play("buy")
				flash, flashRow = 0.5, sel
			else
				g.audio.play("uiDeny")
				broke, brokeRow = 1.2, sel
			end
		end
		if inp.pressed("shop") then
			g.go("ocean", nil)
		end
	end

	function scene.render()
		local W = 960
		-- Dusk harbour, the stall and its curtain.
		Draw.grad(0, 0, W, 330, "#3a1850", "#e0705a")
		Draw.grad(0, 330, W, 150, "#5c4a94", "#241a4a")
		Draw.rect(0, 480, W, 60, "#4a2a12")
		Draw.rect(236, 0, W - 236, 46, "#2a160a")
		for i = 0, 6 do
			Draw.rect(236 + i * 104, 46, 100, 64, if i % 2 == 0 then "#1f2456" else "#26306a")
		end
		Draw.text(T.shop.title, 236 + (W - 236) / 2, 78, { size = 26, color = PAPER })
		Draw.rect(236, 120, W - 236, 8, "#2a160a")
		Draw.rect(236, 432, W - 236, 48, "#6a3e1e")
		Draw.sprite("samuraiIdle", 122, 506 - 173 * 1.25 / 2, { scale = 1.25, time = g.time })

		local rows = g.state.upgrades()
		for i, r in rows do
			local x = boardX(i)
			local y = BOARD_Y - lifted[i] * 10
			local on = i == sel
			Draw.line(x + 30, 120, x + 30, y, 2, INK)
			Draw.line(x + BOARD_W - 30, 120, x + BOARD_W - 30, y, 2, INK)
			Draw.box(x, y, BOARD_W, BOARD_H, if on then "#c89858" else "#a8784a", { radius = 6, stroke = if on then GOLD else INK, strokeW = if on then 4 else 3 })
			if flash > 0 and flashRow == i then
				Draw.box(x, y, BOARD_W, BOARD_H, "#ffffff", { alpha = flash, radius = 6 })
			end
			Draw.text(EMBLEM[r.id], x + BOARD_W / 2, y + 36, { size = 40, color = VERMILION, outline = PAPER })
			Draw.text(r.label, x + BOARD_W / 2, y + 74, { size = 22, color = PAPER })
			Draw.text(`LV {r.level}`, x + BOARD_W / 2, y + 98, { size = 16, color = GOLD })
			for li, l in wrap(r.name, BOARD_W - 20, 15) do
				Draw.text(l, x + BOARD_W / 2, y + 116 + li * 18, { size = 15, color = INK, outline = "#e8d0a0" })
			end
			Draw.text(r.effect, x + BOARD_W / 2, y + 186, { size = 12, color = PAPER })
			Draw.box(x + 28, y + 202, BOARD_W - 56, 28, if r.affordable then "#2a6a2a" else "#5a1010", { radius = 4 })
			Draw.text(`{r.cost} RYO`, x + BOARD_W / 2, y + 216, { size = 17, color = if r.affordable then "#ffffff" else "#ffb0a0" })
			if broke > 0 and brokeRow == i then
				Draw.text(T.shop.broke, x + BOARD_W / 2, y - 18, { size = 20, color = "#ff3b2f", alpha = math.min(1, broke) })
			end
		end
		Draw.box(W - 200, 8, 188, 34, "#0c0a18", { alpha = 0.8, radius = 6, stroke = GOLD, strokeW = 2 })
		Draw.text(Manifest.fill(T.shop.gold, { gold = g.state.gold() }), W - 106, 25, { size = 20, color = GOLD })
		settings.render()
		Hud.prompts(g.input, {
			{ action = "move", label = "CHOOSE", keys = "horizontal" },
			{ action = "confirm", label = "BUY" },
			{ action = "shop", label = "LEAVE" },
			{ action = "settings", label = "SETTINGS" },
		})
	end

	return scene
end
