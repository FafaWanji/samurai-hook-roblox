-- On-screen fight buttons for phones and tablets (the prompt bar is tappable everywhere else).
-- Hold-able, so BLOCK can be held and BLOCK + ◀/▶ dashes like on a keyboard.
local Draw = require(script.Parent.Draw)

local TouchButtons = {}

local LAYOUT = {
	{ action = "left", label = "◀", x = 20, y = 400, w = 90, h = 90 },
	{ action = "right", label = "▶", x = 120, y = 400, w = 90, h = 90 },
	{ action = "up", label = "JUMP", x = 230, y = 420, w = 80, h = 70 },
	{ action = "down", label = "DUCK", x = 230, y = 340, w = 80, h = 70 },
	{ action = "defend", label = "BLOCK", x = 650, y = 420, w = 90, h = 70 },
	{ action = "quick", label = "QUICK", x = 750, y = 420, w = 90, h = 70 },
	{ action = "heavy", label = "HEAVY", x = 850, y = 400, w = 90, h = 90 },
}

function TouchButtons.new(screen: Frame, input)
	local self = {}
	local buttons = {}
	for _, b in LAYOUT do
		local btn = Instance.new("TextButton")
		btn.Name = "Touch_" .. b.action
		btn.Position = UDim2.fromOffset(b.x, b.y)
		btn.Size = UDim2.fromOffset(b.w, b.h)
		btn.BackgroundColor3 = Draw.color("#0c0a18")
		btn.BackgroundTransparency = 0.45
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.LuckiestGuy
		btn.TextSize = 20
		btn.Text = b.label
		btn.AutoButtonColor = false
		btn.Visible = false
		btn.ZIndex = 1000000
		btn.Selectable = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = Draw.color("#ffdd22")
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn
		btn.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				input.setTouchHeld(b.action, true)
				btn.BackgroundTransparency = 0.15
			end
		end)
		btn.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				input.setTouchHeld(b.action, false)
				btn.BackgroundTransparency = 0.45
			end
		end)
		btn.Parent = screen
		table.insert(buttons, { btn = btn, action = b.action })
	end

	function self.setVisible(on: boolean)
		for _, b in buttons do
			b.btn.Visible = on
			if not on then
				input.setTouchHeld(b.action, false)
				b.btn.BackgroundTransparency = 0.45
			end
		end
	end
	return self
end

return TouchButtons
