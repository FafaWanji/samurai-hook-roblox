-- Versus screen before a fight (src/scenes/cutscene.ts). 2.5 s, any button skips.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook")
local Manifest = require(Shared:WaitForChild("Manifest"))
local Draw = require(script.Parent.Parent.Draw)
local Hud = require(script.Parent.Parent.Hud)

local C = Manifest.cutscene
local T = Manifest.text
local INK, PAPER, VERMILION = "#1a0a0a", "#f4ead2", "#d9381e"

local function bubble(line: string, x: number, y: number, w: number, appear: number)
	local k = math.clamp(appear / 0.18, 0, 1)
	if k <= 0 then
		return
	end
	local ease = 1 - (1 - k) ^ 3
	local bw = w * (0.15 + 0.85 * ease)
	Draw.box(x - bw / 2, y - 32, bw, 64, PAPER, { radius = 8, stroke = INK, strokeW = 3 })
	if k < 1 then
		return
	end
	if Hud.textW(line, 16) > w - 28 then
		local words = string.split(line, " ")
		local half = math.ceil(#words / 2)
		Draw.text(table.concat(words, " ", 1, half), x, y - 10, { size = 16, color = INK, outline = PAPER })
		Draw.text(table.concat(words, " ", half + 1), x, y + 12, { size = 16, color = INK, outline = PAPER })
	else
		Draw.text(line, x, y, { size = 16, color = INK, outline = PAPER })
	end
end

return function(g, params)
	local fish = params.fish
	local t = 0
	local done = false
	local round = 0
	local taunt, line = "...", ""
	local scene = {}

	function scene.enter()
		round = g.state.nextRound()
		g.audio.play("gong")
		g.audio.announce("round", round)
		g.audio.music("fight")
		if #fish.def.taunts > 0 then
			taunt = Hud.pick(fish.def.taunts)
		end
		line = Hud.pick(T.samuraiLines)
	end

	function scene.update(dt)
		t += dt
		if done then
			return
		end
		if t >= C.duration or (t > C.inputLock and (g.input.anyPressed() or g.input.clicked())) then
			done = true
			g.go("fight", { fish = fish })
		end
	end

	function scene.render()
		local W, H = 960, 540
		-- Samurai side: sunset with a rising sun. Fish side: the deep sea.
		Draw.grad(0, 0, W, H, "#4a1d5c", "#f07a3a")
		Draw.circle(230, 330, 150, "#ffcf7a", 0.35)
		Draw.circle(230, 330, 120, VERMILION)
		Draw.grad(W * 0.5, 0, W * 0.5, H, "#2a2a6a", "#070d26")
		for i = 0, 13 do
			local bx = 520 + (i * 97) % 420
			local by = H - (t * (30 + (i % 4) * 12) + i * 61) % (H + 40)
			Draw.circle(bx + math.sin(t * 2 + i) * 6, by, 2 + i % 3, "#bedcff", 0.5)
		end
		Draw.line(W * 0.5, -20, W * 0.5, H + 20, 44, INK)
		Draw.line(W * 0.5 - 10, -20, W * 0.5 - 10, H + 20, 6, PAPER)
		Draw.text("対", W / 2, 250, { size = 260, color = PAPER, outline = PAPER, alpha = 0.16 })
		-- nobori banners
		Draw.rect(0, 0, 46, H, VERMILION)
		Draw.rect(W - 46, 0, 46, H, "#1f2456")
		Draw.text("侍\n道", 23, 230, { size = 34, color = PAPER })
		Draw.text("魚", W - 23, 230, { size = 34, color = PAPER })

		local k = math.min(1, t / C.slide)
		local ease = 1 - (1 - k) ^ 3
		Draw.sprite("samuraiIdle", -150 + 380 * ease, 350, { scale = 2, time = t })
		Draw.sprite(fish.def.sprite, W + 200 - 420 * ease, 350, { flipX = true, scale = 2.2, time = t })

		Hud.slam(Manifest.fill(T.cutscene.round, { round = round }), W / 2, 70, t - 0.1, 84)
		if t > 0.6 then
			local p = math.min(1, (t - 0.6) / 0.12)
			Draw.rect(150, 160, 660 * p, 70, INK, 0.88)
		end
		Hud.slam(Manifest.fill(T.cutscene.versus, { fish = fish.name }), W / 2, 190, t - 0.6, 50, "#ffffff")
		if t > 0.9 then
			Draw.text(fish.def.title, W / 2, 246, { size = 28, color = "#ffdd22" })
		end
		if t > 1.2 then
			bubble(line, 236, 304, 300, t - 1.2)
			bubble(taunt, 724, 304, 300, t - 1.2)
		end
		Hud.prompts(g.input, { { action = "confirm", label = "SKIP" } })
	end

	return scene
end
