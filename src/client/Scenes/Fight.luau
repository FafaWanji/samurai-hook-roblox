-- The duel (src/scenes/fight.ts): a thin layer over Sim.luau. Feeds input in, draws the state,
-- turns sim events into sound, popups and shake. No fight rules live here.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local Sim = require(Shared:WaitForChild("Sim"))
local Draw = require(script.Parent.Parent.Draw)
local Hud = require(script.Parent.Parent.Hud)

local F = Manifest.fight
local T = Manifest.text
-- Hit shake (fx.ts). Was switched off while hunting the flicker, which turned out to be Draw's pooling.
local SCREEN_SHAKE = true
local OVER_HOLD = 1.2
local FIGHT_BANNER_TIME = 0.9
local SHAKE = { hit = 6, heavyHit = 16, bitten = 11, bounce = 9, blocked = 4, win = 22, puff = 5 }
local HP_LAG_DELAY, HP_LAG_SPEED = 0.35, 0.9
local BAR = { w = 360, h = 22, y = 22, margin = 26 }
local FISH_DRAW_SIZE = 1.55
local PUFF_SCALE = 1.6
local TILT = { roam = 1.1, slip = 0.45, vulnerable = 0.55, tell = 1.35, attack = 0.12, stunned = 0.8, puffed = 0.2, aim = 1.35, charge = 0.05, shoot = 0.9 }
local SAM_SPRITE = {
	idle = "samuraiIdle", walk = "samuraiWalk", dash = "samuraiWalk", quick = "samuraiQuick", heavy = "samuraiHeavy",
	block = "samuraiBlock", hurt = "samuraiHurt", crouch = "samuraiCrouch", jump = "samuraiJump",
}
local PROMPTS = {
	{ action = "move", label = "MOVE / JUMP / DUCK" },
	{ action = "quick", label = "QUICK" },
	{ action = "heavy", label = "HEAVY" },
	{ action = "defend", label = "BLOCK / +DIR DASH" },
	{ action = "settings", label = "PAUSE" },
}
local PAUSED_PROMPTS = { { action = "settings", label = "RESUME" }, { action = "confirm", label = "RESUME" } }

return function(g, params)
	local fish = params.fish
	local sim = Sim.create(fish, g.state.samurai())
	local state = sim.state
	local W, H = 960, 540
	local floorY = F.arena.floorY
	local fishColor = Manifest.sprites[fish.def.sprite].color
	local biter = (fish.def.attack ~= nil) or (fish.def.special ~= nil) or (fish.def.contactDamage ~= nil)
	local spriteDef = Manifest.sprites[fish.def.sprite]
	local baseScale = (FISH_DRAW_SIZE * fish.def.size * 2) / math.max(spriteDef.w, spriteDef.h)

	local t, fightT, overT = 0, -1, -1
	local left, paused = false, false
	local lag = { sam = 1, fish = 1, samHold = 0, fishHold = 0 }
	local look = { wt = 0, rt = 0, fishVx = 0, fishTilt = TILT.roam, puff = 0, samAirY = 0, rising = true }
	local lastFishX = state.fish.x
	local fx = { shake = 0, shakeT = 0, white = 0, red = 0, popups = {}, rings = {} }

	local function popup(str, x, y, size, color)
		table.insert(fx.popups, { str = str, x = x, y = y, size = size, color = color, age = 0, life = 0.9 })
	end
	local function ring(x, y, r, color)
		table.insert(fx.rings, { x = x, y = y, r = r, color = color, age = 0, life = 0.25 })
	end
	local function shake(v)
		fx.shake = math.max(fx.shake, v)
	end

	local function onEvent(e)
		local dmg = if e.damage then math.max(1, math.floor(e.damage + 0.5)) else 0
		local k = e.type
		if k == "fightStart" then
			fightT = 0
			g.audio.play("gong")
			g.audio.announce("fight")
		elseif k == "quick" then
			g.audio.play("slash")
		elseif k == "heavyStart" then
			g.audio.play("uiMove")
		elseif k == "heavySwing" then
			g.audio.play("heavy")
			shake(3)
		elseif k == "hit" then
			g.audio.play("hit")
			popup(Hud.pick(T.hit), e.x, e.y - 50, 36, "#ffffff")
			popup(`-{dmg}`, e.x + 34, e.y - 10, 26, "#ffdd22")
			ring(e.x, e.y, 46, "#ffffff")
			shake(SHAKE.hit)
		elseif k == "heavyHit" then
			g.audio.play("hit")
			popup(Hud.pick(T.heavyHit), e.x, e.y - 70, 54, "#ff9a1a")
			popup(`-{dmg}`, e.x + 40, e.y - 16, 38, "#ffdd22")
			ring(e.x, e.y, 90, "#ffb020")
			shake(SHAKE.heavyHit)
			fx.white = 1
		elseif k == "slip" then
			g.audio.play("slip")
			popup(Hud.pick(T.slip), e.x, e.y - 50, 36, "#8ff4ff")
		elseif k == "tell" or k == "aim" then
			g.audio.play("tell")
		elseif k == "charge" then
			g.audio.play("dash")
			shake(SHAKE.blocked)
		elseif k == "shoot" then
			g.audio.play("slip")
		elseif k == "jump" or k == "dash" then
			g.audio.play("dash")
		elseif k == "bitten" then
			g.audio.play("bite")
			popup(`-{dmg}`, e.x, e.y - 80, 34, "#ff4a3a")
			ring(e.x, e.y - 10, 50, "#ff3a2a")
			shake(SHAKE.bitten)
			fx.red = 1
			lag.samHold = HP_LAG_DELAY
		elseif k == "blocked" then
			g.audio.play("block")
			popup(T.block, e.x, e.y - 90, 30, "#9fd8ff")
			ring(e.x + state.samurai.facing * 40, e.y, 34, "#8fd0ff")
			shake(SHAKE.blocked)
			lag.samHold = HP_LAG_DELAY
		elseif k == "dodged" then
			popup(T.dodged, e.x, e.y - 90, 30, "#5ad8ff")
		elseif k == "poison" then
			popup("POISONED!", e.x, e.y - 120, 30, "#7dff5a")
		elseif k == "bounce" then
			g.audio.play("block")
			popup(T.bounce, e.x, e.y - 60, 44, "#ffe14a")
			shake(SHAKE.bounce)
		elseif k == "puff" then
			g.audio.play("splash")
			popup(T.puff, e.x, e.y - 80, 32, "#ffe14a")
			shake(SHAKE.puff)
		elseif k == "ink" then
			g.audio.play("splash")
		elseif k == "win" then
			shake(SHAKE.win)
			fx.white = math.max(fx.white, 0.8)
		end
	end

	local function worldUpdate(dt)
		local f = state.fish
		look.wt += dt
		local vx = if dt > 0 then (f.x - lastFishX) / dt else 0
		lastFishX = f.x
		look.fishVx += (vx - look.fishVx) * math.min(1, dt * 12)
		look.fishTilt += (TILT[f.mode] - look.fishTilt) * math.min(1, dt * 10)
		look.puff += ((if f.mode == "puffed" then 1 else 0) - look.puff) * math.min(1, dt * 12)
	end

	local function updateLag(dt)
		local samF = state.samurai.hp / state.samurai.maxHp
		local fishF = state.fish.hp / state.fish.maxHp
		lag.samHold -= dt
		lag.fishHold -= dt
		if lag.samHold <= 0 then
			lag.sam = math.max(samF, lag.sam - HP_LAG_SPEED * dt)
		end
		if lag.fishHold <= 0 then
			lag.fish = math.max(fishF, lag.fish - HP_LAG_SPEED * dt)
		end
		lag.sam = math.max(lag.sam, samF)
		lag.fish = math.max(lag.fish, fishF)
	end

	local function updateFx(dt)
		-- Same decay as src/scenes/fight/fx.ts (SHAKE_DECAY 7).
		fx.shake = math.max(0, fx.shake - fx.shake * 7 * dt - 4 * dt)
		fx.white = math.max(0, fx.white - dt * 5)
		fx.red = math.max(0, fx.red - dt * 2.5)
		fx.shakeT += dt
		for _, list in { fx.popups, fx.rings } do
			for i = #list, 1, -1 do
				list[i].age += dt
				if list[i].age >= list[i].life then
					table.remove(list, i)
				end
			end
		end
	end

	local function finish()
		if left then
			return
		end
		left = true
		local outcome = state.outcome or "timeout"
		if outcome == "win" then
			local gold = g.state.sell(fish)
			g.go("result", { fish = fish, outcome = "win", goldEarned = gold, perfect = state.samurai.misses == 0 })
		else
			g.go("result", { fish = fish, outcome = outcome, goldEarned = 0 })
		end
	end

	local function fishPose()
		local f = state.fish
		local scale = baseScale * (1 + (PUFF_SCALE - 1) * look.puff)
		local tilt = if fish.def.sprite == "fish.squid" then 0 else look.fishTilt
		local hw, hh = spriteDef.w * scale / 2, spriteDef.h * scale / 2
		local ext = math.abs(hw * math.sin(tilt)) + math.abs(hh * math.cos(tilt))
		local lift = math.max(0, ext - fish.def.size)
		local cy = floorY - fish.def.size - f.y - lift
		local lean = math.clamp(look.fishVx * 0.0011, -0.4, 0.4)
		local wobble = math.sin(look.wt * 7) * 0.07
		if f.mode == "vulnerable" then
			wobble = math.sin(look.wt * 2.6) * 0.28
		elseif f.mode == "stunned" then
			wobble = math.sin(look.wt * 70) * 0.08
		end
		return { cx = f.x, cy = cy, scale = scale, rot = -f.facing * tilt + lean + wobble, ext = ext, hw = hw, hh = hh }
	end

	local function shadow(x, w, height)
		local k = math.max(0.35, 1 - height / 260)
		Draw.box(x - w * k, floorY - 6, w * 2 * k, 12, "#000000", { alpha = 0.35 * k, radius = 6 })
	end

	local function drawSamurai()
		Draw.layer("samurai")
		local s = state.samurai
		if s.y <= 0 then
			look.rising = true
		elseif s.y ~= look.samAirY then
			look.rising = s.y > look.samAirY
		end
		look.samAirY = s.y
		local id = if s.move == "jump" and not look.rising then "samuraiFall" else SAM_SPRITE[s.move]
		local rot, sx, sy, dy = 0, 1, 1, 0
		if s.move == "idle" then
			sy = 1 + 0.018 * math.sin(look.wt * 3)
		elseif s.move == "walk" then
			dy = -math.abs(math.sin(look.wt * 11)) * 4
			rot = s.facing * 0.04
		elseif s.move == "dash" then
			rot, sx, sy = s.facing * 0.22, 1.12, 0.92
		elseif s.move == "block" then
			sx, sy = 1.03, 0.95
		elseif s.move == "hurt" then
			rot = -s.facing * 0.25
		end
		shadow(s.x, 34, s.y)
		local alpha = 1
		if s.invulnerable then
			alpha = if math.floor(look.rt * 30) % 2 == 1 then 0.3 else 0.85
		end
		local animTime = if s.move == "quick" or s.move == "heavy" or s.move == "hurt" then s.moveTime else look.wt
		local h = 173 * sy
		Draw.sprite(id, s.x, floorY + dy - s.y - h / 2, { flipX = s.facing == -1, time = animTime, alpha = alpha, rotation = rot, sx = sx, sy = sy })
		-- Heavy wind-up glow and the slash arc while a strike is live.
		if s.move == "heavy" and s.stage == "startup" then
			Draw.circle(s.x, floorY - 80 - s.y, 30 + 30 * (s.moveTime / F.samurai.heavy.startup), "#ffb020", 0.25)
		end
		-- Slash trail (drawSlash in src/scenes/fight/fighters.ts): a crescent that thickens toward the blade,
		-- sweeping from SLASH_FROM to SLASH_TO during the active frames and fading out over TRAIL_FADE.
		Draw.layer("trail")
		if s.move == "quick" or s.move == "heavy" then
			local heavy = s.move == "heavy"
			local cfg = if heavy then F.samurai.heavy else F.samurai.quick
			local tt = s.moveTime - cfg.startup
			local fade = if tt <= cfg.active then 1 else 1 - (tt - cfg.active) / 0.12
			if tt >= 0 and fade > 0 then
				local radius = if heavy then 200 else 165
				local thick = if heavy then 54 else 30
				local color = if heavy then "#ff9a1a" else "#9ff0ff"
				local core = if heavy then "#fff3b0" else "#ffffff"
				local sweep = math.min(1, tt / cfg.active)
				local tail = -1.6
				local head = tail + (0.85 - tail) * (0.15 + 0.85 * sweep)
				local cx, cy = s.x + s.facing * 12, floorY - 80
				local N = 18
				local function at(u: number, r: number)
					local a = tail + (head - tail) * u
					local ax = if s.facing == 1 then a else math.pi - a
					return cx + math.cos(ax) * r, cy + math.sin(ax) * r
				end
				for i = 0, N - 1 do
					local u0, u1 = i / N, (i + 1) / N
					-- Stop at the deck: below it the sweep flashed over the ground on every slash.
					local _, endY = at(u1, radius)
					if endY > floorY - 4 then
						break
					end
					local th = thick * ((u0 + u1) / 2) ^ 0.7
					if th >= 1 then
						local x0, y0 = at(u0 - 0.01, radius - th / 2)
						local x1, y1 = at(u1 + 0.01, radius - th / 2)
						-- Opaque while it swings: see-through strips overlap and leave flickering stripes.
						Draw.line(x0, y0, x1, y1, th, color, fade)
					end
					local ox0, oy0 = at(u0, radius)
					local ox1, oy1 = at(u1 + 0.01, radius)
					Draw.line(ox0, oy0, ox1, oy1, if heavy then 6 else 4, core, fade)
				end
			end
		end
	end

	local function drawFish()
		Draw.layer("fish")
		local f = state.fish
		local def = fish.def
		local pose = fishPose()
		shadow(f.x, def.size * 1.2 * (1 + look.puff * 0.5), f.y)
		if f.mode == "tell" and def.attack then
			local reach = def.attack.reach
			local x0 = if f.facing == 1 then f.x else f.x - reach
			Draw.rect(x0, floorY - 2, reach, 8, "#ff1e1e", 0.18 + 0.25 * f.tellProgress * (0.5 + 0.5 * math.sin(look.rt * 30)))
		end
		if f.mode == "aim" and def.special then
			local a = 0.3 + 0.35 * f.tellProgress * (0.5 + 0.5 * math.sin(look.rt * 30))
			local dir = if state.samurai.x >= f.x then 1 else -1
			local x0 = if dir == 1 then f.x else F.arena.left
			local w = if dir == 1 then F.arena.right - f.x else f.x - F.arena.left
			if def.special.kind == "charge" then
				Draw.rect(x0, floorY - 50, w, 50, "#ff1e1e", a * 0.6)
			else
				local first = (def.special.pattern or { "high" })[1]
				local P = F.fish.special.projectile[first]
				Draw.rect(x0, floorY - P.y - P.r, w, P.r * 2, if first == "low" then "#5ad8ff" else "#ff5ad8", a * 0.6)
			end
		end
		local mode = f.mode
		local sx, sy = 1, 1
		if mode == "attack" then
			sx, sy = 1.35, 0.78
		end
		Draw.sprite(def.sprite, pose.cx, pose.cy, { flipX = f.facing == -1, scale = pose.scale, rotation = pose.rot, time = look.wt, sx = sx, sy = sy })
		if mode == "puffed" then
			Draw.circle(pose.cx, pose.cy, pose.hw * 0.9, "#ffe14a", 0.25)
		end
	end

	local function drawMarks()
		local f = state.fish
		local pose = fishPose()
		if f.mode == "vulnerable" and f.vulnTotal > 0 then
			local frac = f.vulnLeft / f.vulnTotal
			local y = pose.cy - pose.ext - 24
			-- Dizzy stars circling over its head (the game font has no star glyph).
			for k = 0, 2 do
				local a = look.rt * 5 + k * math.pi * 2 / 3
				Draw.circle(pose.cx + math.cos(a) * 22, y - 14 + math.sin(a) * 6, 4, "#ffe14a")
			end
			Draw.rect(pose.cx - 30, y, 60, 6, "#1a0a0a")
			Draw.rect(pose.cx - 30, y, 60 * frac, 6, "#8ff4ff")
		end
		if f.mode == "tell" then
			local size = 34 + 58 * f.tellProgress
			local c = if math.floor(look.rt * 16) % 2 == 1 then "#ff2a1a" else "#ffdd22"
			Draw.text("!", pose.cx, pose.cy - pose.ext - 24 - size * 0.35, { size = size, color = c })
		end
		if f.mode == "aim" and fish.def.special then
			local sp = fish.def.special
			local words = {}
			if sp.kind == "charge" then
				words = { "JUMP!" }
			else
				for _, h in sp.pattern or { "high" } do
					table.insert(words, if h == "low" then "JUMP!" else "DUCK!")
				end
			end
			local c = if math.floor(look.rt * 16) % 2 == 1 then "#ffffff" else "#ffdd22"
			Draw.text(table.concat(words, " "), pose.cx, pose.cy - pose.ext - 30, { size = 26 + 14 * f.tellProgress, color = c })
		end
	end

	local function drawProjectiles()
		for _, p in state.projectiles do
			local y = floorY - p.y
			if p.height == "low" then
				local back = -math.sign(p.vx)
				Draw.rect(math.min(p.x, p.x + back * p.r * 3), floorY - p.r * 2, p.r * 3, p.r * 2, "#8ff4ff", 0.35)
				Draw.line(p.x, floorY, p.x, floorY - p.r * 2 * (0.6 + 0.4 * math.abs(math.sin(look.rt * 40))), 4, "#8ff4ff")
			else
				Draw.circle(p.x, y, p.r * 1.4, "#ff5ad8", 0.3)
				Draw.circle(p.x, y, p.r, if fish.def.gimmick == "ink" then "#1a0a2a" else "#ffe0f4")
			end
		end
	end

	--- Anglerfish: dark everywhere except a soft circle of light around the samurai, and the fish's own lure.
	--- GUIs cannot cut holes, so the hole is a texture (darkHole, made by make-upload.mjs) framed by four dark rects.
	--- The lure is a glow texture on top: the only thing that shows where the fish is in the dark.
	local DARK = 0.95
	local DARK_COLOR = "#020008"
	local function drawDarkness()
		local s = state.samurai
		local pose = fishPose()
		local f = state.fish
		local samX, samY = s.x, floorY - 64 - s.y
		local R = F.fish.darkRadius
		local x0, x1, y0, y1 = samX - R, samX + R, samY - R, samY + R
		local L, T, Rt, B = -60, -60, W + 60, H + 60 -- past the edges, so screen shake never shows a gap
		-- Each rect overlaps the hole image by 1 px, so no seam shows at fractional screen scales.
		-- Two layers: 95% dark twice is 99.75% dark, so the stage no longer shows through.
		for _ = 1, 2 do
			Draw.rect(L, T, Rt - L, y0 - T + 1, DARK_COLOR, DARK)
			Draw.rect(L, y1 - 1, Rt - L, B - y1 + 1, DARK_COLOR, DARK)
			Draw.rect(L, y0, x0 - L + 1, y1 - y0, DARK_COLOR, DARK)
			Draw.rect(x1 - 1, y0, Rt - x1 + 1, y1 - y0, DARK_COLOR, DARK)
			Draw.image("darkHole", samX, samY, 2 * R, 2 * R) -- until Roblox approves it, the hole is square
		end
		-- The lure: its bulb lights up the fish around it.
		local ax, ay = f.facing * 40 * pose.scale, -27 * pose.scale
		local c, sn = math.cos(pose.rot), math.sin(pose.rot)
		local lx = pose.cx + ax * c - ay * sn
		local ly = pose.cy + ax * sn + ay * c
		local flick = 0.9 + 0.06 * math.sin(look.rt * 11) + 0.04 * math.sin(look.rt * 23.7)
		if not Draw.image("glow", lx, ly, 120 * flick, 120 * flick, 0.6 * flick, "#ffc85a") then
			Draw.circle(lx, ly, 40 * flick, "#ffc85a", 0.25)
		end
		Draw.circle(lx, ly, 5, "#fbf236")
	end

	local scene = {}

	local menuConn = nil
	function scene.enter()
		g.audio.music("fight")
		g.setTouchFight(true)
		-- Esc opens the Roblox menu: pause the fight with it, so the timer does not run on.
		if g.menuOpened then
			menuConn = g.menuOpened:Connect(function()
				if state.phase ~= "over" and not paused then
					paused = true
					g.audio.pauseMusic(true)
				end
			end)
		end
	end
	function scene.exit()
		g.setTouchFight(false)
		if menuConn then
			menuConn:Disconnect()
		end
	end

	function scene.update(dt)
		if state.phase ~= "over" then
			if g.input.pressed("settings") or (paused and (g.input.pressed("confirm") or g.input.clicked())) then
				paused = not paused
				g.audio.pauseMusic(paused)
				g.audio.play("uiMove")
			end
			if paused then
				look.rt += dt
				return
			end
		end
		t += dt
		look.rt += dt
		updateFx(dt)
		if fightT >= 0 then
			fightT += dt
		end
		updateLag(dt)
		if state.phase == "over" then
			overT += dt
			look.wt += dt * 0.25
			if overT >= OVER_HOLD then
				finish()
			end
			return
		end
		local inp = g.input
		local input = {
			moveX = inp.moveX(),
			quick = inp.pressed("quick"),
			heavy = inp.pressed("heavy"),
			defendHeld = inp.held("defend"),
			defendPressed = inp.pressed("defend"),
			jump = inp.pressed("up") or inp.pressed("confirm"),
			crouch = inp.held("down"),
			walkScale = 1,
		}
		local frozen = state.hitStop > 0
		local fishHpBefore = state.fish.hp
		local events = sim.step(dt, input)
		if state.fish.hp < fishHpBefore then
			lag.fishHold = HP_LAG_DELAY
		end
		if not frozen then
			worldUpdate(dt)
		end
		for _, e in events do
			onEvent(e)
		end
		if state.outcome ~= nil then
			overT = 0
		end
	end

	function scene.render()
		-- A smooth wobble (fx.ts shakeOffset), not a random jump every frame: random read as flicker.
		local sh = if SCREEN_SHAKE then fx.shake else 0
		Draw.setOffset(math.sin(fx.shakeT * 83) * sh, math.cos(fx.shakeT * 67) * sh * 0.7)
		-- Stage: dusk sky, sea, the boat deck.
		Draw.layer("stage")
		Draw.grad(-48, -48, W + 96, floorY - 140 + 48, "#2a1450", "#c4506a")
		Draw.circle(700, floorY - 150, 60, "#ffb35a", 0.9)
		Draw.grad(-48, floorY - 140, W + 96, 140, "#5c3a7a", "#2a1e5a")
		for i = 0, 4 do
			Draw.rect(-48, floorY - 120 + i * 24 + math.sin(t + i) * 3, W + 96, 2, "#ffd6aa", 0.15)
		end
		Draw.rect(-48, floorY, W + 96, H - floorY + 48, "#6a3e1e")
		Draw.rect(-48, floorY, W + 96, 6, "#a8703a")
		for x = 0, W, 80 do
			Draw.rect(x, floorY + 6, 2, H - floorY, "#4a2a12")
		end

		if state.fish.y > 60 then
			drawSamurai()
			drawFish()
		else
			drawFish()
			drawSamurai()
		end
		Draw.layer("rings")
		for _, r in fx.rings do
			local k = r.age / r.life
			Draw.circle(r.x, r.y, r.r * (0.4 + 0.6 * k), r.color, 0.6 * (1 - k))
		end
		Draw.layer("dark")
		if state.effects.dark then
			drawDarkness()
		end
		Draw.layer("ink")
		if state.effects.inkLeft > 0 then
			local a = math.min(1, state.effects.inkLeft / 0.6) * 0.85
			for i = 0, 5 do
				Draw.circle(F.arena.left + 80 + i * 150, 220 + math.sin(i * 2.3) * 80, 90 + (i % 3) * 20, "#0a0614", a)
			end
		end
		Draw.layer("projectiles")
		drawProjectiles()
		Draw.layer("marks")
		drawMarks()
		Draw.layer("popups")
		for _, p in fx.popups do
			local k = p.age / p.life
			local scale = if p.age < 0.08 then 1.6 - 0.6 * p.age / 0.08 else 1
			Draw.text(p.str, p.x, p.y - 40 * k, { size = p.size * scale, color = p.color, alpha = if k > 0.7 then (1 - k) / 0.3 else 1, world = true })
		end
		Draw.setOffset(0, 0)

		Draw.layer("flash")
		if fx.white > 0 then
			Draw.rect(0, 0, W, H, "#ffffff", fx.white * 0.55)
		end
		if fx.red > 0 then
			Draw.rect(0, 0, W, H, "#ff1e1e", fx.red * 0.3)
		end

		-- HUD
		Draw.layer("hud")
		local s, f = state.samurai, state.fish
		local lx, rx = BAR.margin, W - BAR.margin - BAR.w
		local samF = if biter then s.hp / s.maxHp else 1
		Hud.healthBar(lx, BAR.y, BAR.w, BAR.h, samF, T.samurai.label, if biter then nil else T.samurai.safeSub, true, if biter then nil else "#7fd0ff")
		if biter and lag.sam > samF + 0.001 then
			Draw.rect(lx + BAR.w * samF, BAR.y, BAR.w * (lag.sam - samF), BAR.h, "#ffffff", 0.85)
		end
		local fishF = f.hp / f.maxHp
		Hud.healthBar(rx, BAR.y, BAR.w, BAR.h, fishF, fish.name, fish.def.title, false)
		if lag.fish > fishF + 0.001 then
			Draw.rect(rx + BAR.w - BAR.w * lag.fish, BAR.y, BAR.w * (lag.fish - fishF), BAR.h, "#ffffff", 0.85)
		end
		if s.poisonLeft > 0 then
			Draw.text("POISON", lx, BAR.y + BAR.h + 42, { size = 14, align = "left", color = "#7dff5a" })
		end
		Hud.timer(W / 2, 46, state.timeLeft)
		Draw.text(`ROUND {g.state.round()}`, W / 2, 88, { size = 18, color = "#ffdd22" })

		-- Banners
		Draw.layer("banners")
		local cy = 210
		if state.phase == "intro" then
			Hud.slam(Manifest.fill(T.cutscene.round, { round = g.state.round() }), W / 2, cy, t, 84)
		end
		if fightT >= 0 and fightT < FIGHT_BANNER_TIME and state.phase ~= "over" then
			local a = if fightT > FIGHT_BANNER_TIME - 0.2 then (FIGHT_BANNER_TIME - fightT) / 0.2 else 1
			Hud.slam(T.cutscene.fight, W / 2, cy, fightT, 110, "#ff3b2f", a)
		end
		if state.phase == "over" and overT >= 0 then
			if state.outcome == "win" then
				Hud.slam(T.win.banner, W / 2, cy, overT, 120, "#ff3b2f")
			elseif state.outcome == "timeout" then
				Hud.slam(T.timeout.banner, W / 2, cy, overT, 120, "#ffdd22")
			else
				Hud.slam(T.ko.banner, W / 2, cy, overT, 80, "#ff3b2f")
			end
		end
		Draw.layer("pause")
		if paused then
			Draw.rect(0, 0, W, H, "#080614", 0.6)
			Draw.text("PAUSED", W / 2, 220, { size = 84, color = "#ffdd22" })
		end
		Hud.prompts(g.input, if paused then PAUSED_PROMPTS else PROMPTS)
	end

	return scene
end
