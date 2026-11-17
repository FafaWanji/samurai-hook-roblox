-- Immediate-mode drawing on a 960x540 GUI "canvas", so the scenes can be written like the web build's
-- canvas code. Each frame: begin(), draw calls in paint order, finish(). GuiObjects are pooled and reused;
-- whatever was not drawn this frame is hidden.
local Manifest = require(game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook"):WaitForChild("Manifest"))
local Assets = require(game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook"):WaitForChild("Assets"))

local W, H = 960, 540
local FONT = Enum.Font.LuckiestGuy
local MAX_TEXT = 100

local Draw = {}
Draw.W, Draw.H = W, H

local screen: Frame
local pools = {}
local z = 0
local ox, oy = 0, 0
local globalAlpha = 1
local screenScale = 1 -- screen pixels per game pixel

local colorCache: { [string]: Color3 } = {}
local function col(hex: string): Color3
	local c = colorCache[hex]
	if not c then
		c = Color3.fromHex(hex)
		colorCache[hex] = c
	end
	return c
end
Draw.color = col

-- Roblox applies a GuiObject's new colour at once but its new size and position a frame later. So an
-- object that just started being drawn (new, or idle last frame) would flash once with its old shape in
-- its new colour. Such objects are "primed": set up but kept hidden for one frame, shown from the next.
local frameNo = 0
local gradKey: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local gradSeqs: { [string]: ColorSequence } = {}
local primed: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
-- Layers keep busy parts of a scene (popups, trails, fish...) in their own objects, so a change in how
-- many of one thing are drawn does not hand the next thing's objects around (another one-frame flash).
local layer: string? = nil

local creators: { [string]: () -> GuiObject } = {}
local function makePool(name: string, create: () -> GuiObject)
	creators[name] = create
	pools[name] = { list = {}, used = 0, create = create }
end

local function take(name: string): any
	local full = if layer then name .. "#" .. layer else name
	local p = pools[full]
	if not p then
		p = { list = {}, used = 0, create = creators[name] }
		pools[full] = p
	end
	p.used += 1
	local obj = p.list[p.used]
	if not obj then
		obj = p.create()
		obj.Visible = false
		obj.Parent = screen
		p.list[p.used] = obj
	end
	if not obj.Visible then
		if primed[obj] == frameNo - 1 then
			obj.Visible = true
		else
			primed[obj] = frameNo
		end
	end
	z += 1
	obj.ZIndex = z
	return obj
end

--- Puts the following draws in their own objects (see `layer` above); nil = the shared default.
function Draw.layer(name: string?)
	layer = name
end

--- Throws away every pooled object. Called on a scene change, so nothing carries over between scenes.
function Draw.reset()
	for _, p in pools do
		for _, o in p.list do
			o:Destroy()
		end
		table.clear(p.list)
		p.used = 0
	end
	gradKey = setmetatable({}, { __mode = "k" })
end

--- Creates the ScreenGui. Returns the 960x540 frame (for converting screen clicks to game px).
function Draw.init(parent: Instance): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "SamuraiHook"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.Parent = parent

	local back = Instance.new("Frame")
	back.Name = "Letterbox"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BorderSizePixel = 0
	back.Parent = gui

	-- The game itself sits in the area Roblox's own buttons (top-left menu, chat) leave free, so they
	-- never cover the title or the health bars. The black letterbox above still fills the whole screen.
	local canvasGui = Instance.new("ScreenGui")
	canvasGui.Name = "SamuraiHookCanvas"
	canvasGui.ResetOnSpawn = false
	canvasGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	canvasGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	canvasGui.DisplayOrder = 1
	canvasGui.Parent = parent
	local safe = Instance.new("Frame")
	safe.Name = "SafeArea"
	safe.Size = UDim2.fromScale(1, 1)
	safe.BackgroundTransparency = 1
	safe.Parent = canvasGui

	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Size = UDim2.fromOffset(W, H)
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.BackgroundColor3 = col("#1c0f3a")
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.Parent = safe
	local scale = Instance.new("UIScale")
	scale.Parent = screen
	local function fit()
		local size = safe.AbsoluteSize
		scale.Scale = math.max(0.05, math.min(size.X / W, size.Y / H))
		screenScale = scale.Scale
	end
	safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	makePool("rect", function()
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		return f
	end)
	makePool("line", function()
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		return f
	end)
	makePool("grad", function()
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Parent = f
		return f
	end)
	makePool("text", function()
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.XY
		t.Size = UDim2.fromOffset(0, 0)
		t.Font = FONT
		t.TextWrapped = false
		local s = Instance.new("UIStroke")
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = t
		local u = Instance.new("UIScale") -- TextSize stops at 100: bigger text is scaled up
		u.Parent = t
		return t
	end)
	return screen
end

function Draw.begin()
	frameNo += 1
	z = 0
	ox, oy = 0, 0
	globalAlpha = 1
	layer = nil
	for _, p in pools do
		p.used = 0
	end
end

function Draw.finish()
	for _, p in pools do
		for i = p.used + 1, #p.list do
			local o = p.list[i]
			if o.Visible then
				o.Visible = false
			end
		end
	end
end

--- World offset for screen shake (applies to every later draw until begin() or setOffset(0, 0)).
function Draw.setOffset(x: number, y: number)
	-- Whole screen pixels only: Roblox snaps edges to pixels, so a fractional shake made thin lines
	-- (the deck planks) jump between 1 and 2 pixels wide and flicker.
	ox = math.floor(x * screenScale + 0.5) / screenScale
	oy = math.floor(y * screenScale + 0.5) / screenScale
end
function Draw.setAlpha(a: number)
	globalAlpha = a
end

local function tr(a: number?): number
	return 1 - math.clamp((a or 1) * globalAlpha, 0, 1)
end

function Draw.rect(x: number, y: number, w: number, h: number, color: string, alpha: number?)
	if w <= 0 or h <= 0 then
		return
	end
	local f = take("rect")
	f.AnchorPoint = Vector2.zero
	f.Rotation = 0
	f.Position = UDim2.fromOffset(x + ox, y + oy)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = col(color)
	f.BackgroundTransparency = tr(alpha)
end

--- Vertical gradient from `top` to `bottom` colour.
function Draw.grad(x: number, y: number, w: number, h: number, top: string, bottom: string, alpha: number?)
	if w <= 0 or h <= 0 then
		return
	end
	local key = top .. "|" .. bottom
	local seq = gradSeqs[key]
	if not seq then
		seq = ColorSequence.new(col(top), col(bottom))
		gradSeqs[key] = seq
	end
	Draw.gradSeq(x, y, w, h, seq, key, alpha)
end

--- Vertical gradient with any colour stops. `key` names the colours: the UIGradient is only touched when
--- it changes, because Roblox sometimes skips drawing a gradient for a frame after its colours change.
function Draw.gradSeq(x: number, y: number, w: number, h: number, seq: ColorSequence, key: string, alpha: number?)
	if w <= 0 or h <= 0 then
		return
	end
	local f = take("grad")
	f.Position = UDim2.fromOffset(x + ox, y + oy)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundTransparency = tr(alpha)
	if gradKey[f] ~= key then
		gradKey[f] = key
		f.UIGradient.Color = seq
	end
end

--- A pooled Frame whose UICorner and UIStroke never change: Roblox applies changes to those a frame
--- late, so reusing one object for different shapes made it blink. One pool per corner/outline style.
local function takeRound(corner: UDim, stroke: string?, strokeW: number): Frame
	local key = `round|{corner.Scale}|{corner.Offset}|{stroke or "-"}|{strokeW}`
	if not pools[key] then
		makePool(key, function()
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			local c = Instance.new("UICorner")
			c.CornerRadius = corner
			c.Parent = f
			if stroke then
				local s = Instance.new("UIStroke")
				s.Color = col(stroke)
				s.Thickness = strokeW
				s.Parent = f
			end
			return f
		end)
	end
	return take(key)
end

local function roundShape(cx: number, cy: number, w: number, h: number, color: string, corner: UDim, alpha: number?, stroke: string?, strokeW: number, rotation: number?, fillAlpha: number?)
	local f = takeRound(corner, stroke, strokeW)
	f.Position = UDim2.fromOffset(cx + ox, cy + oy)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = math.deg(rotation or 0)
	f.BackgroundColor3 = col(color)
	f.BackgroundTransparency = tr(if fillAlpha ~= nil then fillAlpha else alpha)
	if stroke then
		local s = f:FindFirstChildOfClass("UIStroke")
		local t = tr(alpha)
		if s.Transparency ~= t then
			s.Transparency = t
		end
	end
end

--- Rounded box, optional outline.
function Draw.box(x: number, y: number, w: number, h: number, color: string, opts: { alpha: number?, radius: number?, stroke: string?, strokeW: number?, rotation: number? }?)
	local o = opts or {}
	local r = o.radius or 6
	-- Few distinct styles, so few pools: fully rounded = pill, else radius in 2 px steps.
	local corner = if r >= math.min(w, h) / 2 then UDim.new(0.5, 0) else UDim.new(0, math.floor(r / 2 + 0.5) * 2)
	local strokeW = if o.stroke then math.floor((o.strokeW or 2) * 2 + 0.5) / 2 else 0
	roundShape(x + w / 2, y + h / 2, w, h, color, corner, o.alpha, o.stroke, strokeW, o.rotation)
end

--- Filled circle, or a ring when `stroke` is given.
function Draw.circle(cx: number, cy: number, r: number, color: string, alpha: number?, stroke: string?)
	local round = UDim.new(0.5, 0)
	if stroke then
		roundShape(cx, cy, r * 2, r * 2, "#000000", round, alpha, stroke, 1.5, nil, 0)
	else
		roundShape(cx, cy, r * 2, r * 2, color, round, alpha, nil, 0)
	end
end

function Draw.line(x0: number, y0: number, x1: number, y1: number, thick: number, color: string, alpha: number?)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.01 then
		return
	end
	-- Own pool: lines come and go (the slash trail), and sharing objects with Draw.rect made the boxes
	-- drawn after them (the anglerfish darkness) swap objects mid-fight and blink.
	local f = take("line")
	f.Position = UDim2.fromOffset((x0 + x1) / 2 + ox, (y0 + y1) / 2 + oy)
	f.Size = UDim2.fromOffset(len, thick)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BackgroundColor3 = col(color)
	f.BackgroundTransparency = tr(alpha)
end

export type TextOpts = { size: number?, color: string?, outline: string?, align: string?, alpha: number?, rotation: number?, world: boolean? }

--- Outlined text, vertically centred on y (like drawOutlinedText in src/ui/hud.ts).
function Draw.text(str: string, x: number, y: number, opts: TextOpts?)
	local o = opts or {}
	local size = o.size or 32
	local t = take("text")
	local align = o.align or "center"
	local ax = if align == "left" then 0 elseif align == "right" then 1 else 0.5
	t.AnchorPoint = Vector2.new(ax, 0.5)
	local sx, sy = if o.world then ox else 0, if o.world then oy else 0
	t.Position = UDim2.fromOffset(x + sx, y + sy)
	t.Text = str
	local px = math.max(1, math.floor(size + 0.5))
	t.TextSize = math.min(px, MAX_TEXT)
	t.UIScale.Scale = math.max(1, px / MAX_TEXT)
	t.TextColor3 = col(o.color or "#ffffff")
	t.TextTransparency = tr(o.alpha)
	t.Rotation = math.deg(o.rotation or 0)
	local s = t.UIStroke
	s.Color = col(o.outline or "#1a0a0a")
	s.Thickness = math.max(1.5, math.min(px, MAX_TEXT) / 10)
	s.Transparency = tr(o.alpha)
end

--- A pooled ImageLabel that always shows the same image: one pool per image ID. Switching a label's
--- Image shows it blank for a frame, so a shared pool flickered whenever the draw order changed.
local function takeImage(id: string, pixelated: boolean): ImageLabel
	local key = "image|" .. id .. (if pixelated then "|px" else "")
	if not pools[key] then
		makePool(key, function()
			local i = Instance.new("ImageLabel")
			i.BackgroundTransparency = 1
			i.AnchorPoint = Vector2.new(0.5, 0.5)
			i.ResampleMode = if pixelated then Enum.ResamplerMode.Pixelated else Enum.ResamplerMode.Default
			i.Image = id
			return i
		end)
	end
	return take(key)
end

--- A whole uploaded image (Assets.sprites key) centred on (cx, cy). Returns false when it has no ID yet.
function Draw.image(key: string, cx: number, cy: number, w: number, h: number, alpha: number?, tint: string?): boolean
	local id = Assets.image(key)
	if id == "" then
		return false
	end
	local img = takeImage(id, false)
	img.Position = UDim2.fromOffset(cx + ox, cy + oy)
	img.Size = UDim2.fromOffset(w, h)
	img.Rotation = 0
	img.ImageTransparency = tr(alpha)
	img.ImageColor3 = col(tint or "#ffffff")
	img.ImageRectOffset = Vector2.zero
	img.ImageRectSize = Vector2.zero
	return true
end

export type SpriteOpts = { flipX: boolean?, scale: number?, alpha: number?, rotation: number?, time: number?, sx: number?, sy: number? }

--- A sprite centred on (x, y): the uploaded image, or a placeholder shape when Assets has no ID for it.
function Draw.sprite(id: string, x: number, y: number, opts: SpriteOpts?)
	local o = opts or {}
	local def = Manifest.sprites[id]
	if not def then
		return
	end
	local scale = o.scale or 1
	local w, h = def.w * scale * (o.sx or 1), def.h * scale * (o.sy or 1)
	local sheet = def.sheet or id
	local asset = Assets.sprites[sheet]
	local imageId = Assets.image(sheet)
	local rot = o.rotation or 0
	if asset and imageId ~= "" then
		local img = takeImage(imageId, true)
		img.Position = UDim2.fromOffset(x + ox, y + oy)
		img.Size = UDim2.fromOffset(w, h)
		img.Rotation = math.deg(rot)
		img.ImageTransparency = tr(o.alpha)
		local frame = math.floor((o.time or 0) * def.fps) % def.frames
		local cx, cy = frame % asset.cols, math.floor(frame / asset.cols)
		local mirror = (o.flipX == true) ~= (def.facing == "left")
		if mirror then
			img.ImageRectOffset = Vector2.new((cx + 1) * asset.frameW, cy * asset.frameH)
			img.ImageRectSize = Vector2.new(-asset.frameW, asset.frameH)
		else
			img.ImageRectOffset = Vector2.new(cx * asset.frameW, cy * asset.frameH)
			img.ImageRectSize = Vector2.new(asset.frameW, asset.frameH)
		end
		return
	end
	-- Placeholders, roughly the web build's (src/core/assets.ts).
	local face = if o.flipX then -1 else 1
	if id == "boat" then
		Draw.box(x - w / 2, y - h * 0.05, w, h * 0.45, "#5a3418", { alpha = o.alpha, radius = 18, stroke = "#1a0a05", strokeW = 3 })
		Draw.rect(x - w / 2 + 10, y - h * 0.08, w - 20, 8, "#7a4a26", o.alpha)
		return
	elseif id == "hook" then
		Draw.line(x, y - h / 2, x, y + h * 0.25, 3, def.color, o.alpha)
		Draw.line(x, y + h * 0.25, x + 8, y + h * 0.1, 3, def.color, o.alpha)
		return
	elseif string.sub(id, 1, 7) == "samurai" then
		-- Body box at the sprite's real figure size (the art is mostly empty space for the sword sweep).
		local bw, bh = 54 * scale * (o.sx or 1), h * 0.8
		Draw.box(x - bw / 2, y - bh / 2 + h * 0.1, bw, bh, def.color, { alpha = o.alpha, radius = 10, stroke = "#1a0a0a", strokeW = 3, rotation = rot })
		Draw.box(x - bw * 0.35 + face * bw * 0.15, y - bh / 2 + h * 0.1 + 6, bw * 0.7, 10, "#1a0a0a", { alpha = o.alpha, radius = 3 })
		if def.label then
			Draw.text(def.label, x, y - bh / 2, { size = 14 * scale, alpha = o.alpha, world = true })
		end
		return
	end
	Draw.box(x - w / 2, y - h / 2, w, h, def.color, { alpha = o.alpha, radius = math.min(w, h) / 2, stroke = "#1a0a0a", strokeW = 2, rotation = rot })
	-- eye at the head end
	local ex = x + face * w * 0.3 * math.cos(rot)
	local ey = y + face * w * 0.3 * math.sin(rot) - h * 0.1
	Draw.circle(ex, ey, math.max(2, h * 0.09), "#1a0a0a", o.alpha)
end

return Draw
