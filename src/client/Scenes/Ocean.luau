-- The ocean (src/scenes/ocean.ts): drop the hook, steer past cheap fish, hook a good one.
-- Same rules and numbers as the web build; the art is simplified (gradients and shapes).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local Draw = require(script.Parent.Parent.Draw)
local Hud = require(script.Parent.Parent.Hud)
local Settings = require(script.Parent.Parent.Settings)

local ocean = Manifest.ocean
local L = ocean.layout
local DEEP_STOPS = { { 0, { 92, 74, 148 } }, { 30, { 50, 46, 116 } }, { 80, { 24, 22, 72 } }, { 150, { 7, 5, 24 } } }

-- Pixel pine island and torii gate, in 2 px "pixels" (src/ui/backdrop.ts): { x, y, w, h }.
local PINE = {
	{ -16, -3, 32, 3 }, { -12, -5, 22, 2 }, { -8, -7, 13, 2 }, -- rock
	{ -2, -12, 2, 5 }, { -1, -16, 2, 4 }, { 0, -20, 2, 4 }, -- trunk
	{ -8, -14, 9, 2 }, { -6, -15, 5, 1 }, { -2, -19, 12, 2 }, { 0, -20, 7, 1 }, { -3, -23, 9, 2 }, { -1, -24, 5, 1 }, -- canopies
}
local PINE_RIM = { { -8, -7, 13, 1 }, { -2, -20, 7, 1 }, { -1, -24, 5, 1 } }
local TORII = {
	{ -9, -22, 3, 22 }, { 6, -22, 3, 22 }, -- pillars
	{ -12, -17, 24, 2 }, -- tie beam
	{ -13, -24, 26, 3 }, -- top beam
	{ -15, -26, 4, 2 }, { 11, -26, 4, 2 }, -- upturned ends
	{ -1, -21, 2, 4 }, -- centre strut
}

-- The water colours as one fixed gradient from the surface (0 m) to the last stop.
local WATER_SEQ = (function()
	local last = DEEP_STOPS[#DEEP_STOPS][1]
	local keys = {}
	for _, s in DEEP_STOPS do
		table.insert(keys, ColorSequenceKeypoint.new(s[1] / last, Color3.fromRGB(s[2][1], s[2][2], s[2][3])))
	end
	return ColorSequence.new(keys)
end)()

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function waterColour(depthM: number): string
	local d = math.max(0, depthM)
	local i = 1
	while i < #DEEP_STOPS - 1 and d > DEEP_STOPS[i + 1][1] do
		i += 1
	end
	local d0, c0 = DEEP_STOPS[i][1], DEEP_STOPS[i][2]
	local d1, c1 = DEEP_STOPS[i + 1][1], DEEP_STOPS[i + 1][2]
	local t = math.clamp((d - d0) / (d1 - d0), 0, 1)
	return string.format("#%02x%02x%02x", math.floor(lerp(c0[1], c1[1], t) + 0.5), math.floor(lerp(c0[2], c1[2], t) + 0.5), math.floor(lerp(c0[3], c1[3], t) + 0.5))
end

return function(g, _params)
	local W, H = 960, 540
	local PLAY_H = H - 30
	local surfaceY = ocean.surfaceY
	local ppm = ocean.pxPerMetre
	local rodX = L.boatX + L.rodDx

	local mode = "idle"
	local settings = Settings.new(g, { x = 12, y = H - 30 - 30, panel = "above" })
	local hx = rodX
	local hy = surfaceY + L.hookIdleDy
	local camY = 0
	local boatBob = 0
	local swimmers = {}
	local spawned = {}
	local bubbles = {}

	local function limitY()
		return surfaceY + g.state.maxDepth() * ppm
	end
	local function depthOf(worldY)
		return (worldY - surfaceY) / ppm
	end
	local function sy(worldY)
		return worldY - camY
	end
	local function spriteW(f)
		local d = Manifest.sprites[f.def.sprite]
		return if d then d.w else 64
	end

	for _ = 1, L.bubbleCount do
		table.insert(bubbles, { x = math.random() * W, wy = math.random() * H, speed = 20 + math.random() * 30, r = 1.5 + math.random() * 2.5 })
	end

	local function swimSpeed(f)
		return f.def.swimSpeed * (1 + (math.random() * 2 - 1) * L.fishSpeedVariation)
	end

	local function spawnChunk(c: number)
		local top = surfaceY + L.fishTopM * ppm + c * H
		local bottom = math.min(top + H, limitY() + L.fishBeyondPx)
		if bottom <= top then
			return
		end
		local count = math.max(1, math.floor(ocean.fishPerScreen * ((bottom - top) / H) + 0.5))
		local used = {}
		for _ = 1, count do
			for _ = 1, 6 do
				local y = lerp(top, bottom, math.random())
				local clash = false
				for _, u in used do
					if math.abs(u - y) < L.fishMinGapPx then
						clash = true
					end
				end
				if clash then
					continue
				end
				local f = g.state.pickFish(depthOf(y))
				if not f then
					continue
				end
				table.insert(used, y)
				table.insert(swimmers, {
					fish = f, x = math.random() * W, baseY = y, dir = if math.random() < 0.5 then 1 else -1,
					speed = swimSpeed(f), phase = math.random() * math.pi * 2,
				})
				break
			end
		end
	end

	local function ensureChunks()
		local first = math.floor((camY - surfaceY - L.fishTopM * ppm) / H) - 1
		local last = math.floor((camY + H - surfaceY - L.fishTopM * ppm) / H) + 1
		for c = math.max(0, first), last do
			if not spawned[c] then
				spawned[c] = true
				spawnChunk(c)
			end
		end
	end

	local function fishY(s)
		return s.baseY + math.sin(g.time * 1.5 + s.phase) * L.fishBobPx
	end

	local function updateFish(dt)
		for _, s in swimmers do
			s.x += s.dir * s.speed * dt
			local half = spriteW(s.fish) / 2 + L.fishWrapMargin
			if (s.dir == 1 and s.x > W + half) or (s.dir == -1 and s.x < -half) then
				s.x = if s.dir == 1 then -half else W + half
				local again = g.state.pickFish(depthOf(s.baseY))
				if again then
					s.fish = again
					s.speed = swimSpeed(again)
				end
			end
		end
	end

	local function checkHook(): boolean
		local lim = limitY()
		for _, s in swimmers do
			if s.baseY > lim then
				continue
			end
			local reach = ocean.hook.radius + (spriteW(s.fish) / 2) * ocean.catchRadiusScale
			local dx, dy = s.x - hx, fishY(s) - hy
			if dx * dx + dy * dy <= reach * reach then
				g.audio.play("hooked")
				-- Re-make the fish so it follows the current hard-mode setting.
				g.go("cutscene", { fish = g.state.makeFish(s.fish.def.id, s.fish.tier) })
				return true
			end
		end
		return false
	end

	local function updateBubbles(dt)
		for _, b in bubbles do
			b.wy -= b.speed * dt
			local s = b.wy - camY
			if s < -10 then
				b.wy += H + 20
				b.x = math.random() * W
			elseif s > H + 10 then
				b.wy -= H + 20
				b.x = math.random() * W
			end
		end
	end

	local scene = {}

	function scene.enter()
		g.audio.music("ocean")
		ensureChunks()
	end

	function scene.update(dt)
		local input = g.input
		boatBob = math.sin(g.time * 1.6) * L.boatBobPx
		if mode == "idle" and settings.update(dt) then
			updateFish(dt)
			updateBubbles(dt)
			return
		end
		if mode == "idle" then
			if input.pressed("confirm") or input.pressed("down") or input.tapped() or input.clicked() then
				g.audio.play("splash")
				mode = "sinking"
			elseif input.pressed("shop") then
				g.go("shop", nil)
				return
			end
		else
			local h = ocean.hook
			local step = if input.dragging()
				then math.clamp(input.dragDX(), -h.touchSteerMaxSpeed * dt, h.touchSteerMaxSpeed * dt)
				else input.moveX() * h.steerSpeed * dt
			hx = math.clamp(hx + step, L.hookSteerMargin, W - L.hookSteerMargin)
			local my = input.moveY()
			if mode == "sinking" then
				if input.pressed("confirm") or input.pressed("up") then
					mode = "reeling"
				else
					local v = if my > 0 then lerp(h.sinkSpeed, h.fastSinkSpeed, my) else lerp(h.sinkSpeed, h.brakeSpeed, -my)
					hy += v * dt
					if hy >= limitY() then
						hy = limitY()
						mode = "reeling"
					end
				end
			else
				hy -= h.reelSpeed * dt
				if hy <= surfaceY + L.hookIdleDy then
					hy = surfaceY + L.hookIdleDy
					hx = rodX
					mode = "idle"
				end
			end
			updateFish(dt)
			if checkHook() then
				return
			end
		end
		if mode == "idle" then
			updateFish(dt)
		end
		local target = math.max(0, hy - L.hookAnchorY)
		camY += (target - camY) * math.min(1, dt * L.cameraLerp)
		updateBubbles(dt)
		ensureChunks()
	end

	local function drawGauge(lim)
		local maxM = g.state.maxDepth()
		local viewTopM, viewBotM = depthOf(camY), depthOf(camY + PLAY_H)
		local hookM = math.max(0, depthOf(hy))
		local gx = L.gaugeX
		Draw.rect(gx - 2, 0, W - gx + 2, PLAY_H, "#241538")
		Draw.rect(gx - 2, 0, 2, PLAY_H, "#1a0a0a")
		local labels = {}
		for idx, def in Manifest.fish do
			local lane = (idx - 1) % L.gaugeLanes
			local colour = Manifest.sprites[def.sprite].color
			local k = 0
			while true do
				local a = def.depthMin + k * Manifest.tiers.depth
				local b = def.depthMax + k * Manifest.tiers.depth
				k += 1
				if a > maxM then
					break
				end
				if b < viewTopM or a > viewBotM then
					continue
				end
				local y0 = math.max(0, sy(surfaceY + a * ppm))
				local y1 = math.min(PLAY_H, sy(surfaceY + b * ppm))
				local x = gx + 2 + lane * L.gaugeLaneW
				Draw.rect(x - 1, y0 - 1, L.gaugeLaneW + 1, y1 - y0 + 2, "#1a0a0a")
				Draw.rect(x, y0, L.gaugeLaneW - 1, y1 - y0, colour)
				table.insert(labels, { string.upper(def.name), math.clamp((y0 + y1) / 2, 8, PLAY_H - 8), colour })
			end
		end
		local limS = sy(lim)
		if limS < PLAY_H then
			Draw.rect(gx - 2, math.max(0, limS), W - gx + 2, PLAY_H - math.max(0, limS), "#000000", 0.55)
		end
		local tickX = gx + 2 + L.gaugeLanes * L.gaugeLaneW + 2
		local m = math.max(0, math.ceil(viewTopM / 10) * 10)
		while m <= viewBotM do
			local y = sy(surfaceY + m * ppm)
			if y >= 0 and y <= PLAY_H then
				Draw.rect(tickX - 3, y, 4, 2, "#fff0dc", 0.9)
				Draw.text(tostring(m), tickX + 3, y + 1, { size = 11, align = "left" })
			end
			m += 10
		end
		if limS > -10 and limS < PLAY_H + 10 then
			Draw.rect(gx - 2, limS - 1, W - gx + 2, 2, "#ff6b6b")
			Draw.text(`MAX {maxM}`, W - 3, limS - 9, { size = 11, align = "right", color = "#ff7b6b" })
		end
		local hs = sy(hy)
		Draw.rect(gx - 2, hs - 1, W - gx + 2, 2, "#ffffff")
		for _, l in labels do
			Draw.text(l[1], gx - 6, l[2], { size = 11, align = "right", color = l[3] })
		end
		local py = math.clamp(hs, 12, PLAY_H - 12)
		Draw.text("◀", gx - 6, py, { size = 12, align = "right" })
		Draw.text(string.format("%.1f M", hookM), gx - 18, py, { size = 17, align = "right" })
	end

	function scene.render()
		local t = g.time
		local waterY = sy(surfaceY)
		local camDepth = math.max(0, depthOf(camY))

		-- Sunset sky and far sea.
		Draw.layer("sky")
		if waterY > 0 then
			local horizon = waterY - L.seaBand
			Draw.grad(0, 0, W, horizon, "#3a1850", "#f08a4a")
			Draw.circle(L.sunX, horizon - 8, L.sunR, "#ffcf6a")
			Draw.circle(L.sunX, horizon - 8, L.sunR * 0.8, "#ffe9a8")
			Draw.grad(0, horizon, W, waterY - horizon + 8, "#6a3a7a", "#5c4a94")
			for i = 0, 3 do
				local gy = horizon + 6 + i * 7
				Draw.rect(L.sunX - 40 + math.sin(t * 2 + i) * 6, gy, 80 - i * 12, 2, "#ffd6a0", 0.6 - i * 0.12)
			end
			-- Pine island and torii on the horizon (drawPineIsland / drawTorii in src/ui/backdrop.ts).
			local function px(cx, cy, w, h, color, alpha)
				Draw.rect(L.islandX + cx * 2, horizon + cy * 2, w * 2, h * 2, color, alpha)
			end
			for _, r in PINE do
				px(r[1], r[2], r[3], r[4], "#2a1440")
			end
			for _, r in PINE_RIM do
				px(r[1], r[2], r[3], r[4], "#ffaa78", 0.25)
			end
			local k = 24 / 26
			for _, r in TORII do
				Draw.rect(744 + r[1] * k, horizon + r[2] * k, math.max(1, r[3] * k), math.max(1, r[4] * k), "#7a2638")
			end
			Draw.rect(744 - 13 * k, horizon - 24 * k, 26 * k, k, "#ffbe82", 0.35)
		end

		-- Water body: one tall strip from the surface down to the last colour stop, with fixed colours, that
		-- just moves with the camera (changing a gradient's colours every frame made it blink). Solid below.
		Draw.layer("water")
		local topY = math.max(0, waterY)
		local stripH = DEEP_STOPS[#DEEP_STOPS][1] * ppm
		Draw.gradSeq(0, waterY, W, stripH, WATER_SEQ, "water")
		Draw.rect(0, waterY + stripH - 1, W, math.max(0, H - (waterY + stripH) + 1), waterColour(DEEP_STOPS[#DEEP_STOPS][1]))

		-- Light shafts near the surface.
		Draw.layer("rays")
		local rayStrength = math.clamp(1 - (camDepth + (H / ppm) * 0.3) / 40, 0, 1) * 0.14
		if rayStrength > 0.005 then
			for i = 0, 5 do
				local bx = i * 170 + 60 + math.sin(t * 0.4 + i * 1.7) * 30
				Draw.line(bx + 20, topY, bx - 165, H, 50, "#ffb46e", rayStrength * 1.5)
			end
		end

		Draw.layer("bubbles")
		for _, b in bubbles do
			local y = b.wy - camY
			if y >= waterY + 4 then
				Draw.circle(b.x + math.sin(t * 2 + b.wy * 0.05) * 3, y, b.r, "#e6d2ff", 0.4, "#e6d2ff")
			end
		end

		-- Boat with the resting samurai, the rod, the line and the hook.
		Draw.layer("boat")
		-- Same geometry as src/scenes/ocean.ts: the 280x110 hull (image padded to 296x126), prow to the left,
		-- the samurai at the stern with his legs below the gunwale, hidden by the hull drawn over him.
		local boatX = L.boatX - 80
		local HULL_H, GUNWALE_FROM_BOTTOM = 110, 40
		local boatCY = surfaceY + 8 - HULL_H / 2 + 2 + boatBob
		local gunwaleY = boatCY + HULL_H / 2 - GUNWALE_FROM_BOTTOM
		local sit = Manifest.sprites.samuraiSit
		local k = sit.w / 190
		local samX = boatX + 72
		local samCY = gunwaleY + 12 - sit.h / 2
		local handX, handY = samX + 6 * k, samCY + 13 * k
		local rodTipY = sy(surfaceY + L.rodDy + boatBob)
		if sy(boatCY) > -160 and sy(boatCY) < H + 120 then
			Draw.sprite("samuraiSit", samX, sy(samCY), { time = t })
			Draw.sprite("boat", boatX, sy(boatCY), { flipX = true })
			-- Paper lantern at the prow, flickering (drawWasen in src/core/assets.ts; mirrored, prow left).
			local lanX, lanY = boatX - 108, sy(boatCY) - 47
			local flick = 0.85 + 0.15 * math.sin(t * 9) * math.sin(t * 5.3)
			local lx = lanX + math.floor(math.sin(t * 1.6) + 0.5) * 2
			Draw.image("glow", lanX, lanY + 14, 80, 80, 0.45 * flick, "#ffaa50")
			Draw.rect(lx - 1, lanY, 2, 4, "#1a0a05")
			for i, n in { 3, 5, 6, 6, 6, 6, 5, 3 } do
				local yy = lanY + (i + 1) * 2
				Draw.rect(lx - (n / 2 + 1) * 2, yy, (n + 2) * 2, 2, "#1a0a05")
				local band = i == 1 or i == 8
				local c = if band then "#1a0a05"
					elseif i % 2 == 0 then string.format("#%02x%02x28", math.floor(225 * flick), math.floor(64 * flick))
					else string.format("#%02x%02x32", math.floor(240 * flick), math.floor(90 * flick))
				Draw.rect(lx - n, yy, n * 2, 2, c)
			end
			Draw.rect(lx - 4, lanY + 8, 2, 6, "#ffe196", 0.7 * flick)
			-- Bamboo rod from his hands, bowing slightly (drawRod in src/scenes/ocean.ts).
			local x0, y0, x1, y1 = handX, sy(handY), rodX, rodTipY
			local cx, cy = (x0 + x1) / 2, math.min(y0, y1) - 6
			local function at(u)
				return (1 - u) ^ 2 * x0 + 2 * (1 - u) * u * cx + u * u * x1, (1 - u) ^ 2 * y0 + 2 * (1 - u) * u * cy + u * u * y1
			end
			for pass = 0, 1 do
				for i = 0, 11 do
					local ax, ay = at(i / 12)
					local bx, by = at((i + 1) / 12)
					local thick = 4 - (i / 12) * 2.8
					if pass == 0 then
						Draw.line(ax, ay, bx, by, thick + 2, "#1a0a05")
					else
						Draw.line(ax, ay, bx, by, thick, if i % 3 == 2 then "#8a6a30" else "#d8b868")
					end
				end
			end
		end
		Draw.line(rodX, rodTipY, hx, sy(hy) - 12, 1.5, "#ffebd2", 0.8)
		Draw.sprite("hook", hx, sy(hy))

		Draw.layer("fish")
		local lim = limitY()
		for _, s in swimmers do
			local y = sy(fishY(s))
			if y < -80 or y > H + 80 then
				continue
			end
			local dim = s.baseY > lim
			local alpha = if dim then L.unreachableAlpha else 1
			Draw.sprite(s.fish.def.sprite, s.x, y, { flipX = s.dir == -1, time = t, alpha = alpha })
			if s.fish.tier > 0 then
				Draw.text(s.fish.name, s.x, y - Manifest.sprites[s.fish.def.sprite].h / 2 - 10, { size = 15, color = "#ffdd22", alpha = alpha })
			end
		end

		-- Front wave strip
		Draw.layer("wave")
		if waterY > -20 and waterY < H then
			Draw.rect(0, waterY - 2, W, 20, "#46388c", 0.55)
			Draw.rect(0, waterY - 3, W, 2, "#ffd6aa", 0.75)
		end

		-- Max depth limit
		Draw.layer("limit")
		local limScreen = sy(lim)
		if limScreen > -20 and limScreen < H then
			for x = 0, L.gaugeX - 18, 24 do
				Draw.rect(x, limScreen - 1, 14, 2, "#ff6b6b")
			end
			Draw.text(`MAX DEPTH {g.state.maxDepth()} M — BUY A LONGER LINE`, 16, limScreen - 14, { size = 18, align = "left", color = "#ff7b6b" })
		end

		Draw.layer("gauge")
		drawGauge(lim)
		Draw.layer("hud")
		Draw.text(Manifest.text.title, 16, 30, { size = 34, align = "left" })
		Draw.text(`{g.state.gold()} RYO`, 16, 64, { size = 22, align = "left", color = "#ffdd22" })
		if mode == "idle" then
			settings.render()
		end

		local prompts = if mode == "idle"
			then { { action = "confirm", label = "DROP HOOK" }, { action = "shop", label = "SHOP" }, { action = "settings", label = "SETTINGS" } }
			elseif mode == "sinking" then { { action = "move", label = "STEER" }, { action = "confirm", label = "REEL IN" } }
			else { { action = "move", label = "STEER" } }
		Hud.prompts(g.input, prompts)
		if g.input.device() == "touch" then
			local hint = if mode == "idle" then "TOUCH THE WATER TO DROP YOUR HOOK" elseif mode == "sinking" then "DRAG TO STEER  ·  CONFIRM TO REEL IN" else "DRAG TO STEER"
			Draw.text(hint, W / 2, H - 50, { size = 20 })
		end
	end

	return scene
end
