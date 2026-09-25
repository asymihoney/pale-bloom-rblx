-- Server authority for movement.
--
-- Roblox gives each client physics ownership of its own character, so the server
-- can't stop a client from moving fast. What it can do is check the result:
-- sample each character's horizontal position, compare it with the fastest
-- legitimate speed (SprintSpeed, plus approved dashes), and pull the character
-- back if movement stays unexplained.
--
-- Unexplained distance builds up as "debt". Any later sample that moves less than
-- allowed pays some back, and approved dashes add credit that pays it off. This
-- handles network jitter and dash remotes that arrive after the position data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementConfig = require(Shared:WaitForChild("MovementConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Validation = MovementConfig.Validation
local IS_STUDIO = RunService:IsStudio()

type PlayerState = {
	sprinting: boolean,
	lastDashAt: number,
	dashCredit: number,
	dashCreditExpiresAt: number,
	debt: number,
	debtSince: number?,
	lastPosition: Vector3?,
	lastValidCFrame: CFrame?,
	lastCheckAt: number,
}

local MovementService = {}

local states: { [Player]: PlayerState } = {}

local function newState(): PlayerState
	return {
		sprinting = false,
		lastDashAt = -math.huge,
		dashCredit = 0,
		dashCreditExpiresAt = 0,
		debt = 0,
		debtSince = nil,
		lastPosition = nil,
		lastValidCFrame = nil,
		lastCheckAt = os.clock(),
	}
end

local function getAliveHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

-- Call after the server moves a character on purpose (teleports, knockback, etc.),
-- so the speed check doesn't count that movement against the player.
function MovementService.ResetTracking(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.lastPosition = nil
	state.debt = 0
	state.debtSince = nil
end

function MovementService.IsSprinting(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.sprinting
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	state.sprinting = false
	state.lastDashAt = -math.huge
	state.dashCredit = 0
	MovementService.ResetTracking(player)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = MovementConfig.WalkSpeed
	humanoid.JumpHeight = MovementConfig.JumpHeight
	character:SetAttribute("Sprinting", false)
end

local function onSetSprinting(player: Player, isSprinting: unknown)
	local state = states[player]
	if not state or typeof(isSprinting) ~= "boolean" then
		return
	end
	state.sprinting = isSprinting
	if player.Character then
		player.Character:SetAttribute("Sprinting", isSprinting)
	end
end

local function onRequestDash(player: Player, direction: unknown)
	local state = states[player]
	if not state or typeof(direction) ~= "Vector3" then
		return
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	local magnitude = flat.Magnitude
	-- magnitude ~= magnitude rejects NaN
	if magnitude ~= magnitude or magnitude < 0.5 or magnitude > 1.5 then
		return
	end

	local humanoid = getAliveHumanoid(player)
	if not humanoid or humanoid.SeatPart then
		return
	end

	local now = os.clock()
	if now - state.lastDashAt < MovementConfig.DashCooldown - Validation.CooldownLeeway then
		if IS_STUDIO then
			warn(`[MovementService] Rejected dash from {player.Name}: on cooldown`)
		end
		return
	end

	state.lastDashAt = now
	state.dashCredit = MovementConfig.DashSpeed * MovementConfig.DashDuration
	state.dashCreditExpiresAt = now + Validation.DashCreditLifetime
end

local function checkPlayer(player: Player, state: PlayerState, now: number)
	local dt = now - state.lastCheckAt
	state.lastCheckAt = now

	local humanoid, root = getAliveHumanoid(player)
	if not humanoid or not root or humanoid.SeatPart then
		MovementService.ResetTracking(player)
		return
	end

	local position = root.Position
	local lastPosition = state.lastPosition
	state.lastPosition = position
	if not lastPosition then
		state.lastValidCFrame = root.CFrame
		return
	end

	if now > state.dashCreditExpiresAt then
		state.dashCredit = 0
	end

	local delta = position - lastPosition
	local moved = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local allowed = MovementConfig.SprintSpeed * Validation.SpeedTolerance * dt + Validation.FlatAllowance

	-- Movement under the limit pays down debt, but debt never goes below zero.
	state.debt = math.max(0, state.debt + moved - allowed)

	local paid = math.min(state.debt, state.dashCredit)
	state.debt -= paid
	state.dashCredit -= paid

	if state.debt <= 0 then
		state.debtSince = nil
		state.lastValidCFrame = root.CFrame
		return
	end

	state.debtSince = state.debtSince or now
	if now - (state.debtSince :: number) < Validation.DebtGrace then
		return
	end

	warn(`[MovementService] {player.Name} moved {string.format("%.1f", state.debt)} studs more than allowed`)

	if Validation.Enforce and state.lastValidCFrame and player.Character then
		player.Character:PivotTo(state.lastValidCFrame)
		root.AssemblyLinearVelocity = Vector3.zero
		state.lastPosition = state.lastValidCFrame.Position
	end
	state.debt = 0
	state.debtSince = nil
end

local function onPlayerAdded(player: Player)
	states[player] = newState()
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function MovementService.Start()
	Remotes.SetSprinting.OnServerEvent:Connect(onSetSprinting)
	Remotes.RequestDash.OnServerEvent:Connect(onRequestDash)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, state in states do
			if now - state.lastCheckAt >= Validation.CheckInterval then
				checkPlayer(player, state, now)
			end
		end
	end)
end

return MovementService
