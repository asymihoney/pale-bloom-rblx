-- Layered FOV offsets. Each system sets its own named offset (for example
-- "Sprint" or "Dash"), and the camera eases toward the sum every frame.
-- Systems never tween the FOV directly, so they can't overwrite each other.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MovementConfig"))
local CameraConfig = MovementConfig.Camera

local CameraController = {}

local offsets: { [string]: number } = {}
local currentOffset = 0

function CameraController.SetFovOffset(layer: string, value: number)
	offsets[layer] = if value ~= 0 then value else nil
end

function CameraController.ClearFovOffsets()
	table.clear(offsets)
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local target = 0
	for _, value in offsets do
		target += value
	end

	local rate = if target > currentOffset then CameraConfig.FovRiseRate else CameraConfig.FovFallRate
	currentOffset += (target - currentOffset) * (1 - math.exp(-rate * dt))
	camera.FieldOfView = CameraConfig.BaseFov + currentOffset
end

function CameraController.Start()
	RunService:BindToRenderStep("PaleBloomFov", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
