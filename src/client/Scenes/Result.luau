-- After the fight (src/scenes/result.ts): sushi and gold on a win, the fish swims off on a loss.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local Draw = require(script.Parent.Parent.Draw)
local Hud = require(script.Parent.Parent.Hud)

local R = Manifest.result
local T = Manifest.text
local GRAVITY, GROUND, START_Y = 1800, 290, -100
local INK, PAPER, VERMILION = "#1a0a0a", "#f4ead2", "#d9381e"

local function nigiriY(t: number): number
	local dt = math.max(0, t - R.dropAt)
	local fall = math.sqrt(((GROUND - START_Y) * 2) / GRAVITY)
	if dt < fall then
		return START_Y + 0.5 * GRAVITY * dt * dt
	end
	local tt = dt - fall
	return GROUND - math.abs(math.sin(tt * 9)) * 70 * math.exp(-tt * 3)
end

return function(g, params)
	local fish, outcome, goldEarned = params.fish, params.outcome, params.goldEarned
	local t = 0
	local left, coined = false, false
	local total = g.state.gold()
	local before = total - goldEarned
	local W = 960

	local function leave()
		if not left then
			left = true
			g.go("ocean", nil)
		end
	end

	local scene = {}
	function scene.enter()
		if outcome == "win" then
			g.audio.play("ko")
			g.audio.announce(if params.perfect then "perfect" else "win")
		else
			g.audio.play("lose")
			g.audio.announce(if outcome == "timeout" then "timeout" else "ko")
		end
	end

	function scene.update(dt)
		t += dt
		if outcome == "win" and not coined and t >= R.goldAt then
			coined = true
			g.audio.play("coin")
		end
		if (t > R.lock and (g.input.pressed("confirm") or g.input.clicked())) or t >= R.auto then
			leave()
		end
	end

	function scene.render()
		if outcome == "win" then
			Draw.grad(0, 0, W, 540, "#4a1d5c", "#f07a3a")
			Draw.circle(W / 2, 300, 200, "#ffe6b0", 0.35)
			Draw.circle(W / 2, 300, 150, VERMILION)
			Hud.slam(T.win.banner, W / 2, 90, t, 110, "#ff3b2f")
			if params.perfect then
				Hud.slam(T.win.perfect, W / 2, 170, t - 0.4, 54)
			end
			Draw.box(W / 2 - 130, 384, 260, 26, "#2a0a0a", { radius = 6, stroke = "#c8a040", strokeW = 2 })
			Draw.sprite("nigiri", W / 2, nigiriY(t) + 40, { scale = 2.5 })
			if t >= R.goldAt then
				local k = math.min(1, (t - R.goldAt) / R.countTime)
				Draw.box(W / 2 - 220, 418, 440, 60, PAPER, { radius = 4, stroke = INK, strokeW = 3 })
				Draw.text(Manifest.fill(T.win.sold, { gold = math.floor(goldEarned * k + 0.5) }), W / 2, 436, { size = 22, color = INK, outline = PAPER })
				Draw.text(Manifest.fill(T.shop.gold, { gold = math.floor(before + goldEarned * k + 0.5) }), W / 2, 462, { size = 18, color = VERMILION, outline = PAPER })
			end
		else
			Draw.grad(0, 0, W, 452, "#2a1a4a", "#a04a5a")
			Draw.rect(0, 452, W, 88, "#4a2a12")
			local banner = if outcome == "timeout" then T.timeout.banner else T.ko.banner
			local sub = if outcome == "timeout" then T.timeout.sub else Manifest.fill(T.ko.sub, { fish = fish.name })
			local k = math.min(1, t / 0.22)
			Draw.box(W / 2 - 300, 40, 600, 150 * k, PAPER, { radius = 4, stroke = INK, strokeW = 4 })
			if k >= 1 then
				Hud.slam(banner, W / 2, 95, t - 0.22, if outcome == "timeout" then 90 else 64, if outcome == "timeout" then "#ffdd22" else "#ff3b2f")
				Draw.text(sub, W / 2, 160, { size = 22, color = INK, outline = PAPER })
			end
			if outcome == "timeout" then
				Draw.sprite("samuraiIdle", 300, 472 - 173 * 1.6 / 2, { scale = 1.6, time = t })
				Draw.sprite(fish.def.sprite, 600 + math.max(0, t - 0.5) ^ 2 * 450, 360 - t * 10, { scale = 1.6, time = t * 3 })
			else
				Draw.sprite("samuraiHurt", 300, 410, { scale = 1.6, rotation = math.pi / 2 })
				Draw.sprite(fish.def.sprite, 560 + t * 40, 330 + math.sin(t * 2) * 8, { flipX = true, scale = 1.8, time = t })
			end
		end
		Hud.prompts(g.input, { { action = "confirm", label = "CONTINUE" } })
	end

	return scene
end
