-- Single source of truth for movement tuning. Read by both client (feel) and
-- server (validation), so any value changed here stays consistent on both sides.

local MovementConfig = {
	-- Ground speed (studs/s)
	WalkSpeed = 16,
	SprintSpeed = 26,

	-- Exponential approach rates for WalkSpeed changes (higher = snappier).
	-- At rate 8, ~95% of the change happens in ~0.37s.
	SprintAccelRate = 8,
	SprintDecelRate = 12,

	-- Jump
	JumpHeight = 7.2,
	JumpBufferWindow = 0.12, -- seconds before landing that a jump press still counts

	-- Dash
	DashSpeed = 85, -- horizontal studs/s while dashing
	DashDuration = 0.16, -- ~13.6 studs of travel at the values above
	DashCooldown = 1.25,
	AllowAirDash = true,
	AirDashCancelsFall = true, -- zero downward velocity when dashing in the air (brief "hang")

	Camera = {
		BaseFov = 70,
		SprintFovOffset = 6, -- scaled by how close you are to full sprint speed
		DashFovKick = 12,
		FovRiseRate = 25, -- fast in
		FovFallRate = 6, -- slow out
	},

	-- Server-side sanity checks
	Validation = {
		CheckInterval = 0.25, -- seconds between position samples
		SpeedTolerance = 1.25, -- multiplier on SprintSpeed before movement counts as excess
		FlatAllowance = 2, -- studs of free slack per sample (jitter, slopes)
		DebtGrace = 0.6, -- seconds excess can stay unexplained before correction
		DashCreditLifetime = 1.0, -- seconds an approved dash can explain excess movement
		CooldownLeeway = 0.15, -- latency slack on dash cooldown
		Enforce = true, -- false = warn only, never rubber-band
	},
}

return MovementConfig
