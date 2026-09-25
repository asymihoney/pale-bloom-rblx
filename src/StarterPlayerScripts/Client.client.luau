local Controllers = script.Parent:WaitForChild("Controllers")

require(Controllers:WaitForChild("CameraController")).Start()
require(Controllers:WaitForChild("MovementController")).Start()
