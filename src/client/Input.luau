-- Keyboard, mouse, gamepad and touch, read once per fixed step (like src/input/input.ts).
-- Esc belongs to the Roblox menu, so pause / settings is Tab or P.
local UserInputService = game:GetService("UserInputService")

local Input = {}

local K = Enum.KeyCode
local BINDINGS = {
	left = { K.A, K.Left },
	right = { K.D, K.Right },
	up = { K.W, K.Up },
	down = { K.S, K.Down },
	confirm = { K.Space, K.Return },
	quick = { K.J },
	heavy = { K.K },
	defend = { K.L, K.LeftShift },
	shop = { K.E },
	settings = { K.Tab, K.P },
}
local MOUSE = { quick = Enum.UserInputType.MouseButton1, heavy = Enum.UserInputType.MouseButton2 }
local PAD = {
	left = { K.DPadLeft },
	right = { K.DPadRight },
	up = { K.DPadUp },
	down = { K.DPadDown },
	confirm = { K.ButtonA },
	quick = { K.ButtonX },
	heavy = { K.ButtonY },
	defend = { K.ButtonB, K.ButtonR1 },
	shop = { K.ButtonY },
	settings = { K.ButtonSelect },
}
local KEY_GLYPH = {
	left = "A", right = "D", up = "W", down = "S", confirm = "SPACE", quick = "J", heavy = "K",
	defend = "L", shop = "E", settings = "TAB",
}
local PAD_GLYPH = {
	left = "←", right = "→", up = "↑", down = "↓", confirm = "A", quick = "X", heavy = "Y",
	defend = "B", shop = "Y", settings = "SEL",
}
local TOUCH_GLYPH = {
	left = "◀", right = "▶", up = "▲", down = "▼", confirm = "OK", quick = "QUICK", heavy = "HEAVY",
	defend = "BLOCK", shop = "SHOP", settings = "MENU",
}
local ACTIONS = { "left", "right", "up", "down", "confirm", "quick", "heavy", "defend", "shop", "settings" }
local DEADZONE = 0.25

local function deadzone(v: number): number
	local a = math.abs(v)
	if a < DEADZONE then
		return 0
	end
	return math.sign(v) * math.min(1, (a - DEADZONE) / (1 - DEADZONE))
end

function Input.new(screen: Frame)
	local self = {}
	local device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "touch" else "keyboard"
	local held: { [string]: boolean } = {}
	local prev: { [string]: boolean } = {}
	local latched: { [string]: boolean } = {} -- went down since the last step (catches taps shorter than a step)
	local pressedNow: { [string]: boolean } = {}
	local touchHeld: { [string]: boolean } = {} -- on-screen buttons
	local pendingClick: Vector2? = nil
	local click: Vector2? = nil
	local pendingTap, tap = false, false
	local dragDelta, dragDX = 0, 0
	local dragTouch: InputObject? = nil
	local dragLast: Vector3? = nil
	local promptHits = {}
	local stick = Vector2.zero
	local injected: { [string]: boolean } = {}

	local function toGame(pos: Vector3 | Vector2): Vector2
		local ap, as = screen.AbsolutePosition, screen.AbsoluteSize
		return Vector2.new((pos.X - ap.X) / as.X * 960, (pos.Y - ap.Y) / as.Y * 540)
	end

	local function actionsForKey(code: Enum.KeyCode, map)
		local out = {}
		for a, codes in map do
			for _, c in codes do
				if c == code then
					table.insert(out, a)
				end
			end
		end
		return out
	end

	--- A click or tap: on a prompt-bar item it presses that action, else it is reported by clicked().
	local function pointerDown(p: Vector2, isTouch: boolean)
		for _, hit in promptHits do
			if p.X >= hit.x0 and p.X <= hit.x1 and p.Y >= hit.y0 and p.Y <= hit.y1 then
				latched[hit.action] = true
				return true
			end
		end
		pendingClick = p
		if isTouch then
			pendingTap = true
		end
		return false
	end

	UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if processed then
			return
		end
		local t = io.UserInputType
		if t == Enum.UserInputType.Keyboard then
			device = "keyboard"
			for _, a in actionsForKey(io.KeyCode, BINDINGS) do
				latched[a] = true
			end
		elseif t == Enum.UserInputType.Gamepad1 then
			device = "gamepad"
			for _, a in actionsForKey(io.KeyCode, PAD) do
				latched[a] = true
			end
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
			device = "keyboard"
			local onPrompt = t == Enum.UserInputType.MouseButton1 and pointerDown(toGame(io.Position), false)
			if not onPrompt then
				for a, m in MOUSE do
					if m == t then
						latched[a] = true
					end
				end
			end
		elseif t == Enum.UserInputType.Touch then
			device = "touch"
			if not pointerDown(toGame(io.Position), true) and not dragTouch then
				dragTouch = io
				dragLast = io.Position
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Gamepad1 and io.KeyCode == K.Thumbstick1 then
			stick = Vector2.new(io.Position.X, io.Position.Y)
			if stick.Magnitude > 0.5 then
				device = "gamepad"
			end
		elseif io == dragTouch and dragLast then
			local a, b = toGame(dragLast), toGame(io.Position)
			dragDelta += b.X - a.X
			dragLast = io.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		if io == dragTouch then
			dragTouch = nil
			dragLast = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(touchHeld)
		dragTouch = nil
	end)

	local function mouseDown(a: string): boolean
		local m = MOUSE[a]
		return m ~= nil and UserInputService:IsMouseButtonPressed(m)
	end

	function self.update()
		for _, a in ACTIONS do
			local down = touchHeld[a] == true or mouseDown(a)
			if not down then
				for _, c in BINDINGS[a] do
					if UserInputService:IsKeyDown(c) then
						down = true
						break
					end
				end
			end
			if not down then
				for _, c in PAD[a] do
					if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, c) then
						down = true
						break
					end
				end
			end
			prev[a] = held[a]
			held[a] = down
			pressedNow[a] = (down and not prev[a]) or latched[a] == true or injected[a] == true
		end
		table.clear(latched)
		table.clear(injected)
		click, pendingClick = pendingClick, nil
		tap, pendingTap = pendingTap, false
		dragDX, dragDelta = dragDelta, 0
	end

	function self.held(a: string): boolean
		return held[a] == true
	end
	function self.pressed(a: string): boolean
		return pressedNow[a] == true
	end
	function self.anyPressed(): boolean
		for _, a in ACTIONS do
			if pressedNow[a] then
				return true
			end
		end
		return false
	end
	function self.moveX(): number
		local k = (if held.right then 1 else 0) - (if held.left then 1 else 0)
		if k ~= 0 then
			return k
		end
		return deadzone(stick.X)
	end
	function self.moveY(): number
		local k = (if held.down then 1 else 0) - (if held.up then 1 else 0)
		if k ~= 0 then
			return k
		end
		return deadzone(-stick.Y)
	end
	function self.device(): string
		return device
	end
	function self.glyph(a: string): string
		if device == "gamepad" then
			return PAD_GLYPH[a]
		elseif device == "touch" then
			return TOUCH_GLYPH[a]
		end
		return KEY_GLYPH[a]
	end
	function self.clicked(): Vector2?
		return click
	end
	function self.tapped(): boolean
		return tap
	end
	function self.dragging(): boolean
		return dragTouch ~= nil
	end
	function self.dragDX(): number
		return dragDX
	end
	function self.press(a: string)
		injected[a] = true
	end
	function self.setPromptHits(hits)
		promptHits = hits
	end
	--- On-screen touch buttons (TouchButtons.luau) hold actions through this.
	function self.setTouchHeld(a: string, down: boolean)
		device = "touch"
		if down and not touchHeld[a] then
			latched[a] = true
		end
		touchHeld[a] = down or nil
	end
	return self
end

return Input
