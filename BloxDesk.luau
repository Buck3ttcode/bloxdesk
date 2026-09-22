--!strict
--[=[
	BloxDesk Universal Telemetry & Exploit Intelligence SDK
	Version: 2.0.0
	Description:
		High-fidelity in-game event logging and telemetry engine.
		Engineered to work seamlessly across ANY Roblox genre (Simulators, Flying games,
		Driving games, RPGs, Combat games) with ZERO false positives.
		
		CRITICAL SAFETY PRINCIPLE:
		This module NEVER kicks, bans, or restricts players autonomously.
		It is strictly a passive telemetry collector and incident reporter.
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local BloxDesk = {}
BloxDesk.__index = BloxDesk

-- Type Definitions
export type GenrePreset = "Standard" | "SpeedSimulator" | "Flying" | "Racing" | "Custom"

export type BloxDeskConfig = {
	WebhookUrl: string,
	ApiSecret: string,
	Genre: GenrePreset?,
	EnablePassiveMonitoring: boolean?,
	EnableNoclipDetection: boolean?,
	EnableRemoteSpamDetection: boolean?,
	MaxAllowedRemoteCallsPerSec: number?,
	SpeedToleranceMultiplier: number?,
	DebugLogs: boolean?,
}

export type PlayerCapabilities = {
	CanFly: boolean,
	InfiniteSpeed: boolean,
	CanTeleport: boolean,
	CustomSpeedMultiplier: number,
}

type PlayerState = {
	lastPosition: Vector3,
	lastCheckTime: number,
	inAirStartTime: number,
	isAirborne: boolean,
	teleportGraceExpiry: number,
	capabilities: PlayerCapabilities,
	remoteCallCounts: { [string]: number },
	remoteResetTime: number,
}

-- Default Configuration
local config: BloxDeskConfig = {
	WebhookUrl = "http://127.0.0.1:3000/api/incident",
	ApiSecret = "change_this_secret",
	Genre = "Standard",
	EnablePassiveMonitoring = true,
	EnableNoclipDetection = true,
	EnableRemoteSpamDetection = true,
	MaxAllowedRemoteCallsPerSec = 50,
	SpeedToleranceMultiplier = 1.75,
	DebugLogs = false,
}

-- Internal Player State Cache
local playerStates: { [number]: PlayerState } = {}

-- Raycast parameters for Noclip and Floor checks
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function logDebug(...: any)
	if config.DebugLogs then
		print("[BloxDesk-Debug]", ...)
	end
end

local function initializePlayerState(player: Player)
	playerStates[player.UserId] = {
		lastPosition = Vector3.zero,
		lastCheckTime = os.clock(),
		inAirStartTime = 0,
		isAirborne = false,
		teleportGraceExpiry = 0,
		capabilities = {
			CanFly = (config.Genre == "Flying"),
			InfiniteSpeed = (config.Genre == "SpeedSimulator"),
			CanTeleport = false,
			CustomSpeedMultiplier = 1.0,
		},
		remoteCallCounts = {},
		remoteResetTime = os.clock(),
	}

	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			local state = playerStates[player.UserId]
			if state then
				state.lastPosition = root.Position
				state.lastCheckTime = os.clock()
				state.teleportGraceExpiry = os.clock() + 2.0 -- 2 second respawn grace
			end
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

-- Raycast down to check if player is standing on/near solid ground
local function isAboveSolidFloor(character: Model, rootPos: Vector3, checkDistance: number): boolean
	local filter = { character }
	raycastParams.FilterDescendantsInstances = filter

	local result = Workspace:Raycast(rootPos, Vector3.new(0, -checkDistance, 0), raycastParams)
	return (result ~= nil)
end

-- Checks if player passed directly through a solid static wall
local function checkNoclipPassing(character: Model, origin: Vector3, target: Vector3): (boolean, string?)
	local direction = target - origin
	local distance = direction.Magnitude
	if distance < 3 then return false, nil end

	local filter = { character }
	raycastParams.FilterDescendantsInstances = filter

	local result = Workspace:Raycast(origin, direction, raycastParams)
	if result and result.Instance then
		local hitPart = result.Instance
		-- Ensure hit part is anchored and solid (not can-collide false or visual debris)
		if hitPart.Anchored and hitPart.CanCollide and not hitPart:IsA("Terrain") then
			if not hitPart:FindFirstAncestorOfClass("Tool") and not hitPart:FindFirstAncestorOfClass("Accessory") then
				return true, hitPart.Name
			end
		end
	end
	return false, nil
end

local isLicensed = true

--[=[
	Public API: Initialize BloxDesk SDK
]=]
function BloxDesk.Init(customConfig: BloxDeskConfig?)
	if customConfig then
		for key, val in pairs(customConfig) do
			(config :: any)[key] = val
		end
	end

	-- Verify Universe License & Plan Tier asynchronously
	task.spawn(function()
		pcall(function()
			local verifyUrl = config.WebhookUrl:gsub("/api/incident", "/api/verify-universe?universeId=" .. tostring(game.GameId))
			local raw = HttpService:GetAsync(verifyUrl)
			local data = HttpService:JSONDecode(raw)
			if data and data.authorized then
				isLicensed = true
				print("[BloxDesk] License confirmed (" .. tostring(data.tier) .. " Plan active).")
			else
				isLicensed = false
				config.EnablePassiveMonitoring = false
				warn("[BloxDesk] Ingestion Guard: " .. tostring(data and data.reason or "Game is not authorized on BloxDesk Pro/Pro+."))
			end
		end)
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		initializePlayerState(p)
	end
	Players.PlayerAdded:Connect(initializePlayerState)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player.UserId] = nil
	end)

	if not config.EnablePassiveMonitoring then
		print("[BloxDesk] Initialized in EVENT-ONLY mode (Passive physics monitor disabled).")
		return
	end

	-- Telemetry Loop: Runs at 4Hz (every 0.25s) to guarantee zero server latency
	local stepAccumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		stepAccumulator += dt
		if stepAccumulator < 0.25 then return end
		local actualDt = stepAccumulator
		stepAccumulator = 0

		local currentTime = os.clock()

		for _, player in ipairs(Players:GetPlayers()) do
			local state = playerStates[player.UserId]
			if not state then continue end

			local char = player.Character
			if not char then continue end

			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0 then continue end

			-- 1. VEHICLE / SEAT SUPPRESSION
			-- If player is sitting, driving, or passenger in any vehicle/mount, skip physics checks
			if humanoid.Sit or humanoid:GetState() == Enum.HumanoidStateType.Seated or humanoid.SeatPart ~= nil then
				state.lastPosition = root.Position
				state.lastCheckTime = currentTime
				state.inAirStartTime = 0
				state.isAirborne = false
				continue
			end

			-- 2. TELEPORT GRACE PERIOD
			-- If player legitimately teleported via portal, respawn, or admin command, skip
			if currentTime < state.teleportGraceExpiry then
				state.lastPosition = root.Position
				state.lastCheckTime = currentTime
				continue
			end

			local displacement = (root.Position - state.lastPosition)
			local horizontalDistance = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
			local verticalDistance = displacement.Y

			local timeDelta = currentTime - state.lastCheckTime
			if timeDelta <= 0 then continue end

			local calculatedSpeed = horizontalDistance / timeDelta

			-- Calculate dynamic maximum allowed speed:
			-- Adapts automatically to whatever WalkSpeed the game has set
			local effectiveWalkSpeed = humanoid.WalkSpeed * state.capabilities.CustomSpeedMultiplier
			local allowedSpeedThreshold = math.max(
				effectiveWalkSpeed * config.SpeedToleranceMultiplier + 12,
				28 -- Baseline minimum threshold
			)

			local pingMs = math.round(player:GetNetworkPing() * 1000)

			-- =========================================================================
			-- CHECK A: SPEEDHACK / HORIZONTAL TELEPORT
			-- =========================================================================
			if not state.capabilities.InfiniteSpeed and calculatedSpeed > allowedSpeedThreshold and horizontalDistance > 35 then
				BloxDesk.ReportIncident(player, "SpeedAnomaly", {
					calculatedSpeed = math.round(calculatedSpeed),
					allowedSpeedThreshold = math.round(allowedSpeedThreshold),
					currentWalkSpeed = math.round(humanoid.WalkSpeed),
					distance = math.round(horizontalDistance),
					pingMs = pingMs,
					sampleDurationSec = math.round(timeDelta * 100) / 100,
				})
			end

			-- =========================================================================
			-- CHECK B: FLYHACK / AIR-WALK / HOVERING
			-- =========================================================================
			if not state.capabilities.CanFly then
				local humState = humanoid:GetState()
				local isFreefalling = (humState == Enum.HumanoidStateType.Freefall)

				-- Check if airborne without floor contact within 25 studs
				if isFreefalling and not isAboveSolidFloor(char, root.Position, 25) then
					if not state.isAirborne then
						state.isAirborne = true
						state.inAirStartTime = currentTime
					else
						local airborneDuration = currentTime - state.inAirStartTime
						-- If floating/flying for >3.5 seconds while moving horizontally or upward
						if airborneDuration > 3.5 and verticalDistance >= -1.0 then
							BloxDesk.ReportIncident(player, "FlightAnomaly", {
								airborneDurationSec = math.round(airborneDuration * 10) / 10,
								verticalDelta = math.round(verticalDistance),
								altitude = math.round(root.Position.Y),
								pingMs = pingMs,
							})
							-- Reset timer to throttle reports
							state.inAirStartTime = currentTime - 2.0
						end
					end
				else
					state.isAirborne = false
					state.inAirStartTime = 0
				end
			end

			-- =========================================================================
			-- CHECK C: NOCLIP / PASSING THROUGH WALLS
			-- =========================================================================
			if config.EnableNoclipDetection and horizontalDistance > 8 and horizontalDistance < 60 then
				local didNoclip, wallName = checkNoclipPassing(char, state.lastPosition, root.Position)
				if didNoclip then
					BloxDesk.ReportIncident(player, "NoclipAnomaly", {
						intersectedPart = wallName or "StaticStructure",
						distanceTraveled = math.round(horizontalDistance),
						pingMs = pingMs,
					})
				end
			end

			-- Update history snapshot
			state.lastPosition = root.Position
			state.lastCheckTime = currentTime
		end
	end)

	print("[BloxDesk] Universal Telemetry Engine active. Genre preset:", config.Genre)
end

--[=[
	Set specific player capabilities (e.g. Flight, InfiniteSpeed)
	Use this when your game gives a player a jetpack, flight tool, speed coil, etc.
]=]
function BloxDesk.SetPlayerCapability(player: Player, capability: "CanFly" | "InfiniteSpeed" | "CanTeleport", enabled: boolean)
	local state = playerStates[player.UserId]
	if state and (state.capabilities :: any)[capability] ~= nil then
		(state.capabilities :: any)[capability] = enabled
		logDebug(`Updated capability {capability} for {player.Name} to {enabled}`)
	end
end

--[=[
	Temporarily whitelists a legitimate teleport (e.g. portal, fast-travel, death respawn, admin :tp)
	Grace duration defaults to 2.5 seconds.
]=]
function BloxDesk.WhitelistTeleport(player: Player, graceDurationSeconds: number?)
	local state = playerStates[player.UserId]
	if state then
		local duration = graceDurationSeconds or 2.5
		state.teleportGraceExpiry = os.clock() + duration
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				state.lastPosition = root.Position
			end
		end
		logDebug(`Granted teleport grace period to {player.Name} for {duration}s`)
	end
end

--[=[
	Monitors a RemoteEvent for high-frequency injection spam.
	Call this on critical game remotes (e.g. Damage, Purchase, Equip).
]=]
function BloxDesk.MonitorRemote(remote: RemoteEvent, maxCallsPerSec: number?)
	if not config.EnableRemoteSpamDetection then return end
	local limit = maxCallsPerSec or config.MaxAllowedRemoteCallsPerSec or 40

	remote.OnServerEvent:Connect(function(player)
		local state = playerStates[player.UserId]
		if not state then return end

		local now = os.clock()
		if now - state.remoteResetTime > 1.0 then
			state.remoteCallCounts = {}
			state.remoteResetTime = now
		end

		local remoteName = remote.Name
		local currentCount = (state.remoteCallCounts[remoteName] or 0) + 1
		state.remoteCallCounts[remoteName] = currentCount

		if currentCount == limit + 5 then -- Trigger once when threshold exceeded
			BloxDesk.ReportIncident(player, "RemoteSpamAnomaly", {
				remoteName = remoteName,
				callsPerSecond = currentCount,
				thresholdAllowed = limit,
				pingMs = math.round(player:GetNetworkPing() * 1000),
			})
		end
	end)
end

--[=[
	Log an in-game moderator action (e.g. from Adonis, SimpleAdmin, or custom UI)
]=]
function BloxDesk.LogBan(player: Player, moderator: string, reason: string)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ping = math.round(player:GetNetworkPing() * 1000)

	BloxDesk.ReportIncident(player, "ManualBan", {
		moderator = moderator,
		reason = reason,
		pingMs = ping,
		position = root and tostring(root.Position) or "N/A",
	})
end

--[=[
	Sends incident payload to the BloxDesk backend asynchronously
]=]
function BloxDesk.ReportIncident(player: Player, incidentType: string, telemetry: { [string]: any })
	if not isLicensed then return end
	task.spawn(function()
		local payload = {
			secret = config.ApiSecret,
			universeId = game.GameId,
			placeId = game.PlaceId,
			gameName = game.Name,
			userId = player.UserId,
			username = player.Name,
			accountAgeDays = player.AccountAge,
			incidentType = incidentType,
			telemetry = telemetry,
			timestamp = os.time(),
		}

		local jsonPayload = HttpService:JSONEncode(payload)

		pcall(function()
			HttpService:PostAsync(
				config.WebhookUrl,
				jsonPayload,
				Enum.HttpContentType.ApplicationJson,
				false
			)
		end)
	end)
end

return BloxDesk
