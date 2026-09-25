-- Client movement: binds input, builds the ability modules for each character,
-- and updates them every frame. Every ability takes effect locally right away;
-- the server hears about it through Remotes and checks the result
-- (see MovementService).
--
-- To add an ability: create a module with .new(context), :Update(dt), and
-- :Destroy(), build it in onCharacterAdded, and bind its input in Start.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MovementConfig"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

local Sprint = require(script:WaitForChild("Sprint"))
local JumpBuffer = require(script:WaitForChild("JumpBuffer"))
local Dash = require(script:WaitForChild("Dash"))

local player = Players.LocalPlayer

local MovementController = {}

local sprintHeld = false
local current: {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	sprint: any,
	jumpBuffer: any,
	dash: any,
	connections: { RBXScriptConnection },
}? = nil

local function cleanup()
	if not current then
		return
	end
	local old = current
	current = nil
	for _, connection in old.connections do
		connection:Disconnect()
	end
	old.sprint:Destroy()
	old.jumpBuffer:Destroy()
	old.dash:Destroy()
	CameraController.ClearFovOffsets()
end

local function onCharacterAdded(character: Model)
	cleanup()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character then
		return -- respawned again while we were waiting
	end

	local context = {
		character = character,
		humanoid = humanoid,
		root = root,
		camera = CameraController,
	}

	local sprint = Sprint.new(context)
	sprint:SetHeld(sprintHeld)

	current = {
		character = character,
		humanoid = humanoid,
		root = root,
		sprint = sprint,
		jumpBuffer = JumpBuffer.new(context),
		dash = Dash.new(context),
		connections = {
			humanoid.Died:Connect(cleanup),
		},
	}
end

local function onSprintAction(_: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		sprintHeld = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		sprintHeld = false
	end
	if current then
		current.sprint:SetHeld(sprintHeld)
	end
	return Enum.ContextActionResult.Sink
end

local function onDashAction(_: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin and current then
		current.dash:TryDash()
	end
	return Enum.ContextActionResult.Sink
end

local function update(dt: number)
	if not current then
		return
	end
	current.sprint:Update(dt)
	current.dash:Update(dt)

	-- Sprint FOV follows actual ground speed, so holding Shift while standing
	-- still (or running into a wall) doesn't widen the view.
	local velocity = current.root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local sprintAlpha = math.clamp(
		(horizontalSpeed - MovementConfig.WalkSpeed) / (MovementConfig.SprintSpeed - MovementConfig.WalkSpeed),
		0,
		1
	)
	CameraController.SetFovOffset("Sprint", sprintAlpha * MovementConfig.Camera.SprintFovOffset)
end

function MovementController.Start()
	ContextActionService:BindAction("Sprint", onSprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Sprint")
	ContextActionService:BindAction("Dash", onDashAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Dash", "Dash")

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(cleanup)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	RunService.Heartbeat:Connect(update)
end

return MovementController
