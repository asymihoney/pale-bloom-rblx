-- Dash: a short horizontal burst in the direction you're moving, or facing if
-- there's no movement input. Runs locally right away, and the server is sent a
-- RequestDash so its speed check allows the extra distance.
--
-- A LinearVelocity in Plane mode drives the X and Z axes only, which leaves
-- gravity and jumping to act on Y as normal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementConfig = require(Shared:WaitForChild("MovementConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MIN_MOVE_INPUT = 0.1

local Dash = {}
Dash.__index = Dash

function Dash.new(context)
	return setmetatable({
		humanoid = context.humanoid :: Humanoid,
		root = context.root :: BasePart,
		camera = context.camera,
		lastDashAt = -math.huge,
		endsAt = 0,
		direction = Vector3.zero,
		attachment = nil :: Attachment?,
		velocity = nil :: LinearVelocity?,
	}, Dash)
end

function Dash:IsDashing(): boolean
	return self.velocity ~= nil
end

function Dash:_getDirection(): Vector3
	local move = self.humanoid.MoveDirection
	local flat = Vector3.new(move.X, 0, move.Z)
	if flat.Magnitude < MIN_MOVE_INPUT then
		local look = self.root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	return if flat.Magnitude > 0 then flat.Unit else Vector3.zAxis
end

function Dash:TryDash(): boolean
	local humanoid: Humanoid = self.humanoid
	if self:IsDashing() or humanoid.Health <= 0 or humanoid.SeatPart then
		return false
	end

	local now = os.clock()
	if now - self.lastDashAt < MovementConfig.DashCooldown then
		return false
	end

	local state = humanoid:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if airborne and not MovementConfig.AllowAirDash then
		return false
	end

	local direction = self:_getDirection()
	self.lastDashAt = now
	Remotes.RequestDash:FireServer(direction)
	self:_begin(direction, airborne)
	return true
end

function Dash:_begin(direction: Vector3, airborne: boolean)
	local root: BasePart = self.root

	if airborne and MovementConfig.AirDashCancelsFall then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, 0), v.Z)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * MovementConfig.DashSpeed
	velocity.MaxForce = math.huge
	velocity.Parent = root

	self.attachment = attachment
	self.velocity = velocity
	self.direction = direction
	self.endsAt = os.clock() + MovementConfig.DashDuration

	self.camera.SetFovOffset("Dash", MovementConfig.Camera.DashFovKick)
end

function Dash:_finish()
	if self.velocity then
		self.velocity:Destroy()
		self.velocity = nil
	end
	if self.attachment then
		self.attachment:Destroy()
		self.attachment = nil
	end
	self.camera.SetFovOffset("Dash", 0)
end

function Dash:Update(_dt: number)
	if not self:IsDashing() or os.clock() < self.endsAt then
		return
	end
	self:_finish()

	-- Come out of the dash at normal ground speed, so the humanoid doesn't
	-- skid down from 85 studs/s
	local root: BasePart = self.root
	local exitSpeed = self.humanoid.WalkSpeed
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(self.direction.X * exitSpeed, v.Y, self.direction.Z * exitSpeed)
end

function Dash:Destroy()
	self:_finish()
end

return Dash
