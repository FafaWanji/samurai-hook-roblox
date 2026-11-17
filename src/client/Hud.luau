-- Fight-game HUD pieces and the prompt bar (src/ui/hud.ts and src/input/prompts.ts).
local TextService = game:GetService("TextService")
local Draw = require(script.Parent.Draw)

local Hud = {}
local W = 960
local BAND_Y, BAND_H = 510, 30
local ITEM_GAP, GLYPH_GAP = 22, 6

local widthCache = {}
local function textW(str: string, size: number): number
	local key = str .. "|" .. size
	local w = widthCache[key]
	if not w then
		w = TextService:GetTextSize(str, size, Enum.Font.LuckiestGuy, Vector2.new(10000, 1000)).X
		widthCache[key] = w
	end
	return w
end
Hud.textW = textW

--- Text that slams in from 3x size, then shakes briefly.
function Hud.slam(str: string, x: number, y: number, t: number, size: number?, color: string?, alpha: number?)
	if t < 0 then
		return
	end
	local k = math.min(1, t / 0.15)
	local ease = 1 - (1 - k) ^ 3
	local scale = 3 - 2 * ease
	local shake = if k < 1 then 0 else math.max(0, 1 - (t - 0.15) / 0.25) * 4
	local dx = if shake > 0 then math.sin(t * 90) * shake else 0
	local dy = if shake > 0 then math.cos(t * 70) * shake else 0
	Draw.text(str, x + dx, y + dy, { size = (size or 72) * scale, color = color or "#ffdd22", alpha = math.min(1, k * 2) * (alpha or 1) })
end

function Hud.healthBar(x: number, y: number, w: number, h: number, frac: number, label: string, sub: string?, alignLeft: boolean, color: string?)
	local f = math.clamp(frac, 0, 1)
	Draw.rect(x - 4, y - 4, w + 8, h + 8, "#ffffff")
	Draw.rect(x - 2, y - 2, w + 4, h + 4, "#1a0a0a")
	Draw.rect(x, y, w, h, "#5a1010")
	local c = color or (if f > 0.3 then "#ffd21f" else "#ff3b2f")
	local fw = w * f
	local fx = if alignLeft then x else x + w - fw
	Draw.rect(fx, y, fw, h, c)
	Draw.rect(fx, y, fw, h * 0.35, "#ffffff", 0.35)
	local tx = if alignLeft then x else x + w
	local align = if alignLeft then "left" else "right"
	Draw.text(label, tx, y + h + 20, { size = 22, align = align })
	if sub then
		Draw.text(sub, tx, y + h + 42, { size = 14, align = align, color = "#ffdd22" })
	end
end

function Hud.timer(x: number, y: number, seconds: number)
	local s = math.max(0, math.ceil(seconds))
	local low = seconds <= 5
	local pulse = if low then 1 + 0.1 * math.abs(math.sin(seconds * math.pi * 2)) else 1
	Draw.text(tostring(s), x, y, { size = 56 * pulse, color = if low then "#ff3b2f" else "#ffffff" })
end

function Hud.panel(x: number, y: number, w: number, h: number)
	Draw.box(x, y, w, h, "#0c0a18", { alpha = 0.88, radius = 10, stroke = "#ffdd22", strokeW = 4 })
end

--- The prompt bar along the bottom. Each item but "move" is clickable / tappable.
--- prompts: { { action = "confirm" | "move" | ..., label = "DROP HOOK" } }
function Hud.prompts(input, prompts)
	Draw.layer("prompts")
	Draw.rect(0, BAND_Y, W, BAND_H, "#080a10", 0.62)
	local items = {}
	local total = 0
	for _, p in prompts do
		local glyph = if p.action == "move"
			then (if input.device() == "gamepad" then "STICK" elseif input.device() == "touch" then "DRAG" elseif p.keys == "horizontal" then "A D" else "W A S D")
			else input.glyph(p.action)
		local gw = textW(glyph, 14) + 12
		local lw = textW(p.label, 15)
		table.insert(items, { p = p, glyph = glyph, gw = gw, lw = lw, w = gw + GLYPH_GAP + lw })
		total += gw + GLYPH_GAP + lw
	end
	total += ITEM_GAP * math.max(0, #items - 1)
	local x = math.floor(W / 2 - total / 2)
	local hits = {}
	for _, it in items do
		if it.p.action ~= "move" then
			table.insert(hits, { x0 = x - ITEM_GAP / 2, x1 = x + it.w + ITEM_GAP / 2, y0 = BAND_Y, y1 = BAND_Y + BAND_H, action = it.p.action })
		end
		Draw.box(x, BAND_Y + 5, it.gw, 20, "#e8e4da", { radius = 4, stroke = "#1a1a1a", strokeW = 1.5 })
		Draw.text(it.glyph, x + it.gw / 2, BAND_Y + 15, { size = 14, color = "#1a1a1a", outline = "#e8e4da" })
		Draw.text(it.p.label, x + it.gw + GLYPH_GAP, BAND_Y + 16, { size = 15, align = "left", color = "#f4f1ea" })
		x += it.w + ITEM_GAP
	end
	input.setPromptHits(hits)
end

local function pick<T>(a: { T }): T
	return a[math.random(1, #a)]
end
Hud.pick = pick

return Hud
