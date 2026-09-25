-- Jump buffering: a jump pressed in the air, just before landing, fires on landing.
-- The regular jump is still Roblox's own; this only catches presses that would
-- otherwise be lost. Holding jump already re-jumps by default, so this is for taps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MovementConfig"))

local JumpBuffer = {}
JumpBuffer.__index = JumpBuffer

function JumpBuffer.new(context)
	local self = setmetatable({
		humanoid = context.humanoid :: Humanoid,
		bufferedAt = -math.huge,
		connections = {},
	}, JumpBuffer)

	table.insert(
		self.connections,
		UserInputService.JumpRequest:Connect(function()
			self:_onJumpRequest()
		end)
	)
	table.insert(
		self.connections,
		self.humanoid.StateChanged:Connect(function(_, newState)
			self:_onStateChanged(newState)
		end)
	)

	return self
end

function JumpBuffer:_onJumpRequest()
	local state = self.humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		self.bufferedAt = os.clock()
	end
end

function JumpBuffer:_onStateChanged(newState: Enum.HumanoidStateType)
	if newState ~= Enum.HumanoidStateType.Landed then
		return
	end
	if os.clock() - self.bufferedAt > MovementConfig.JumpBufferWindow then
		return
	end
	self.bufferedAt = -math.huge

	local humanoid: Humanoid = self.humanoid
	if humanoid.Health > 0 and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

function JumpBuffer:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return JumpBuffer
