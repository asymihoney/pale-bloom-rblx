-- Hold-to-sprint. Eases WalkSpeed toward its target instead of snapping, and
-- tells the server when sprinting starts or stops.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementConfig = require(Shared:WaitForChild("MovementConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MIN_MOVE_INPUT = 0.1

local Sprint = {}
Sprint.__index = Sprint

function Sprint.new(context)
	local self = setmetatable({
		humanoid = context.humanoid :: Humanoid,
		held = false,
		active = false,
	}, Sprint)
	self.humanoid.WalkSpeed = MovementConfig.WalkSpeed
	return self
end

function Sprint:SetHeld(held: boolean)
	self.held = held
end

function Sprint:IsActive(): boolean
	return self.active
end

function Sprint:Update(dt: number)
	local humanoid: Humanoid = self.humanoid

	-- Only counts as sprinting while actually moving, so the server's state
	-- (and anything that reads it later, like stamina) stays accurate.
	local active = self.held and humanoid.MoveDirection.Magnitude > MIN_MOVE_INPUT
	if active ~= self.active then
		self.active = active
		Remotes.SetSprinting:FireServer(active)
	end

	local target = if active then MovementConfig.SprintSpeed else MovementConfig.WalkSpeed
	local speed = humanoid.WalkSpeed
	local rate = if target > speed then MovementConfig.SprintAccelRate else MovementConfig.SprintDecelRate
	speed += (target - speed) * (1 - math.exp(-rate * dt))
	if math.abs(target - speed) < 0.05 then
		speed = target
	end
	humanoid.WalkSpeed = speed
end

function Sprint:Destroy()
	if self.active then
		self.active = false
		Remotes.SetSprinting:FireServer(false)
	end
end

return Sprint
