--!strict
-- Custom swimming. The client owns its character, so velocity is driven locally for instant
-- response while the server only reads the position. Push forward to swim where the camera
-- looks (small pitch still swims level), Space rises, C/Ctrl/Q sinks, Shift dashes. Hold Space
-- at the surface to leap out; swim onto the beach to walk out.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)

local Swim = {}

local player = Players.LocalPlayer

-- Roblox's default R15 swim animations.
local SWIM_ANIMATION = "rbxassetid://507784897"
local SWIM_IDLE_ANIMATION = "rbxassetid://507785072"

local DISABLED_WHILE_SWIMMING = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Running,
}

Swim.active = false
local inputs = { up = false, down = false, dash = false }
local dashQueued = false

function Swim.setInput(key: string, pressed: boolean)
	if key == "dash" then
		if pressed and not inputs.dash then
			dashQueued = true
		end
		inputs.dash = pressed
	elseif key == "up" or key == "down" then
		(inputs :: any)[key] = pressed
	end
end

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + diff * t
end

function Swim.init(app: any)
	local character: Model? = nil
	local humanoid: Humanoid? = nil
	local root: BasePart? = nil
	local head: BasePart? = nil
	local attachment: Attachment? = nil
	local linear: LinearVelocity? = nil
	local align: AlignOrientation? = nil
	local bubbles: ParticleEmitter? = nil
	local tracks: { [string]: AnimationTrack } = {}
	local controls: any = nil
	local velocity = Vector3.zero
	local yaw, pitch = 0, 0
	local dashUntil, dashReadyAt = 0, 0
	local reenterAt = 0
	local surfaceHold = 0
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	-- Resolved once off the render loop so Heartbeat never yields waiting for the PlayerModule.
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 30)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(function()
				return (require :: any)(module):GetControls()
			end)
			if ok then
				controls = result
			end
		end
	end)

	local function floorDistance(position: Vector3, maxDistance: number): number?
		local exclude: { Instance } = {}
		if character then
			table.insert(exclude, character)
		end
		local clientFolder = Workspace:FindFirstChild("DeepDiveClient")
		if clientFolder then
			table.insert(exclude, clientFolder)
		end
		rayParams.FilterDescendantsInstances = exclude
		local hit = Workspace:Raycast(position, Vector3.new(0, -maxDistance, 0), rayParams)
		return if hit then position.Y - hit.Position.Y else nil
	end

	local function bind()
		local function handler(name: string)
			return function(_, state: Enum.UserInputState)
				local pressed = state == Enum.UserInputState.Begin
				if state == Enum.UserInputState.Begin or state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					Swim.setInput(name, pressed)
				end
				return Enum.ContextActionResult.Sink
			end
		end
		ContextActionService:BindActionAtPriority(
			"DeepDiveDown",
			handler("down"),
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.C,
			Enum.KeyCode.LeftControl,
			Enum.KeyCode.Q,
			Enum.KeyCode.ButtonL2
		)
		ContextActionService:BindActionAtPriority(
			"DeepDiveDash",
			handler("dash"),
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.ButtonR2
		)
	end

	local function unbind()
		ContextActionService:UnbindAction("DeepDiveDown")
		ContextActionService:UnbindAction("DeepDiveDash")
		inputs.down, inputs.dash, inputs.up = false, false, false
	end

	local function playTrack(name: string, speed: number)
		for key, track in tracks do
			if key == name then
				if not track.IsPlaying then
					track:Play(0.25)
				end
				track:AdjustSpeed(speed)
			elseif track.IsPlaying then
				track:Stop(0.25)
			end
		end
	end

	local function splash(position: Vector3, big: boolean)
		app.Sfx.play(if big then "Splash" else "SplashSmall")
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(1, 1, 1)
		part.Position = Vector3.new(position.X, Config.SurfaceY + 0.3, position.Z)
		part.Parent = Workspace
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
		emitter.LightEmission = 0.5
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(10, 18)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = 0
		emitter.Parent = part
		emitter:Emit(if big then 40 else 18)
		app.WorldFx.ring(Vector3.new(position.X, Config.SurfaceY + 0.15, position.Z), Color3.fromRGB(230, 250, 255), if big then 8 else 4.5, 0.7)
		task.delay(1.5, function()
			part:Destroy()
		end)
	end

	local function disable(standUp: boolean?)
		if not Swim.active then
			return
		end
		Swim.active = false
		unbind()
		for _, instance in { linear, align, attachment } :: { Instance? } do
			if instance then
				instance:Destroy()
			end
		end
		linear, align, attachment = nil, nil, nil
		for _, track in tracks do
			track:Stop(0.2)
		end
		if bubbles then
			bubbles.Enabled = false
		end
		app.Sfx.setSwimming(false)
		local h = humanoid
		if h then
			h.PlatformStand = false
			for _, stateType in DISABLED_WHILE_SWIMMING do
				h:SetStateEnabled(stateType, true)
			end
			if standUp then
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
		app.State.dive.swimming = false
	end

	local function enable()
		local h, r = humanoid, root
		if Swim.active or not h or not r or h.Health <= 0 or h.SeatPart then
			return
		end
		Swim.active = true
		for _, stateType in DISABLED_WHILE_SWIMMING do
			h:SetStateEnabled(stateType, false)
		end
		h.PlatformStand = true
		local a = Instance.new("Attachment")
		a.Name = "SwimAttachment"
		a.Parent = r
		local lv = Instance.new("LinearVelocity")
		lv.Name = "SwimVelocity"
		lv.Attachment0 = a
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
		lv.MaxForce = 80000
		lv.VectorVelocity = Vector3.zero
		lv.Parent = r
		local ao = Instance.new("AlignOrientation")
		ao.Name = "SwimOrientation"
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = a
		ao.MaxTorque = 1e6
		ao.Responsiveness = 16
		ao.Parent = r
		attachment, linear, align = a, lv, ao
		velocity = r.AssemblyLinearVelocity * Vector3.new(0.5, 0.35, 0.5)
		local _, currentYaw = r.CFrame:ToEulerAnglesYXZ()
		yaw = currentYaw
		pitch = 0
		ao.CFrame = CFrame.Angles(0, yaw, 0)
		if r.AssemblyLinearVelocity.Y < -10 then
			splash(r.Position, r.AssemblyLinearVelocity.Y < -30)
		end
		if bubbles then
			bubbles.Enabled = true
		end
		bind()
		app.State.dive.swimming = true
	end

	local function onCharacter(newCharacter: Model)
		disable()
		character = newCharacter
		humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
		root = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		head = newCharacter:WaitForChild("Head", 10) :: BasePart?
		table.clear(tracks)
		local h = humanoid
		if not h then
			return
		end
		-- Native swimming never runs: this controller owns all water movement.
		h:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		local animator = h:FindFirstChildOfClass("Animator") or h:WaitForChild("Animator", 5)
		if animator and animator:IsA("Animator") and h.RigType == Enum.HumanoidRigType.R15 then
			local animations: { [string]: string } = { swim = SWIM_ANIMATION, idle = SWIM_IDLE_ANIMATION }
			for key, id in animations do
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action
					track.Looped = true
					tracks[key] = track
				end
			end
		end
		if head then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "DiveBubbles"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(Color3.fromRGB(210, 245, 255))
			emitter.LightEmission = 0.4
			emitter.LightInfluence = 0.3
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.42) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			emitter.Lifetime = NumberRange.new(1.2, 2)
			emitter.Rate = 5
			emitter.Speed = NumberRange.new(3, 6)
			emitter.SpreadAngle = Vector2.new(15, 15)
			emitter.Acceleration = Vector3.new(0, 8, 0)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Enabled = false
			emitter.Parent = head
			bubbles = emitter
		end
		h.Died:Connect(function()
			disable()
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local r, h = root, humanoid
		local dive = app.State.dive
		if not r or not h or not r.Parent or h.Health <= 0 then
			dive.inWater = false
			dive.depth = 0
			return
		end
		local world = app.State.world
		local position = r.Position
		local depth = Config.SurfaceY - position.Y
		local over = Layout.overLagoon(world, position)
		dive.depth = if over then math.max(0, depth) else 0
		dive.inWater = over and depth > 0.4
		local now = os.clock()

		if not Swim.active then
			if over and now >= reenterAt then
				local falling = r.AssemblyLinearVelocity.Y < -12
				if depth >= Config.Swim.EnterDepth or (depth > 0.8 and falling) then
					enable()
				end
			end
			return
		end

		-- Exit: out of the lagoon, above the water, or floating over ground shallow enough to stand.
		if not over or depth < 0.3 then
			disable(false)
			return
		end
		if depth < Config.Swim.ExitDepth and not dive.blackout then
			local floor = floorDistance(position, 5)
			if floor and floor < 3.1 then
				disable(true)
				return
			end
		end

		local move = Vector3.zero
		local blocked = app.isUiBlocking() or dive.blackout or app.State.traveling
		if controls and not blocked then
			move = controls:GetMoveVector()
		end
		local camera = Workspace.CurrentCamera
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local rightVector = camera.CFrame.RightVector
		local right = Vector3.new(rightVector.X, 0, rightVector.Z)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
		-- Camera pitch inside the deadzone swims level; beyond it the swim direction tilts.
		local camPitch = math.asin(math.clamp(look.Y, -1, 1))
		local deadzone = math.rad(Config.Swim.PitchDeadzone)
		local effective = 0
		if math.abs(camPitch) > deadzone then
			effective = math.sign(camPitch) * (math.abs(camPitch) - deadzone) / (math.pi / 2 - deadzone) * (math.pi / 2)
		end
		local forward = flat * math.cos(effective) + Vector3.yAxis * math.sin(effective)
		local dir = forward * -move.Z + right * move.X
		local vertical = 0
		local wantsUp = not blocked and (h.Jump or inputs.up)
		if wantsUp then
			vertical += 1
		end
		if inputs.down and not blocked then
			vertical -= 1
		end
		dir += Vector3.yAxis * vertical * Config.Swim.VerticalFactor
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end

		local speed = app.State.swimSpeed()
		if dashQueued then
			dashQueued = false
			if now >= dashReadyAt and not blocked then
				dashUntil = now + Config.Swim.DashSeconds
				dashReadyAt = now + Config.Swim.DashCooldown
				app.Sfx.play("Dash")
				if bubbles then
					bubbles:Emit(14)
				end
			end
		end
		local dashing = now < dashUntil
		local target = dir * speed * (if dashing then Config.Swim.DashMultiplier else 1)
		if dashing and dir.Magnitude < 0.1 then
			target = r.CFrame.LookVector * speed * Config.Swim.DashMultiplier
		end
		if dive.blackout then
			target = Vector3.new(0, 1.5, 0)
		end

		-- Surface: float with the head above water; hold jump there to leap out.
		local floatY = Config.SurfaceY - Config.Swim.FloatOffset
		local atSurface = position.Y >= floatY - 0.35
		if atSurface and target.Y > 0 then
			target = Vector3.new(target.X, 0, target.Z)
		end
		if position.Y > floatY then
			target = Vector3.new(target.X, math.min(target.Y, (floatY - position.Y) * 6), target.Z)
		elseif vertical == 0 and move.Magnitude < 0.1 and depth < 4.5 then
			target += Vector3.new(0, 3, 0)
		end
		if atSurface and wantsUp then
			surfaceHold += dt
			if surfaceHold > 0.22 then
				surfaceHold = 0
				reenterAt = now + 0.7
				local carry = velocity * Vector3.new(0.7, 0, 0.7)
				disable(false)
				r.AssemblyLinearVelocity = carry + Vector3.new(0, Config.Swim.SurfaceJumpPower, 0)
				h:ChangeState(Enum.HumanoidStateType.Freefall)
				splash(position, false)
				return
			end
		else
			surfaceHold = 0
		end

		-- Keep inside the terraced lagoon walls (the beach inlet is open).
		local origin = Layout.origin(world)
		local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
		local info = Layout.info(world)
		local inInlet = math.abs(offset.X) <= 21 and offset.Z >= info.radius - 4
		local maxRadius = Layout.radiusAtDepth(world, depth)
		if not inInlet and offset.Magnitude > maxRadius then
			local outward = offset.Unit
			local outSpeed = target:Dot(outward)
			if outSpeed > 0 then
				target -= outward * outSpeed
			end
			target -= outward * math.min(12, (offset.Magnitude - maxRadius) * 4)
		end
		-- Do not grind into the floor.
		if target.Y < 0 then
			local floor = floorDistance(position, 3.5)
			if floor and floor < 3 then
				target = Vector3.new(target.X, math.max(0, (3 - floor) * 4), target.Z)
			end
		end

		local rate = if dashing then Config.Swim.DashAccel else Config.Swim.Accel
		velocity = velocity:Lerp(target, 1 - math.exp(-rate * dt))
		if linear then
			linear.VectorVelocity = velocity
		end

		-- Body: face the swim direction and lie flat while moving.
		local total = velocity.Magnitude
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if horizontal > 1.5 then
			yaw = lerpAngle(yaw, math.atan2(-velocity.X, -velocity.Z), math.clamp(dt * 7, 0, 1))
		elseif move.Magnitude > 0.1 then
			yaw = lerpAngle(yaw, math.atan2(-flat.X, -flat.Z), math.clamp(dt * 5, 0, 1))
		end
		local blend = math.clamp((total - 2) / 8, 0, 1)
		local elevation = if total > 0.5 then math.asin(math.clamp(velocity.Y / total, -1, 1)) else 0
		local pitchTarget = math.clamp((-math.pi / 2 + elevation) * blend, -math.rad(160), 0)
		if atSurface and horizontal < 6 then
			pitchTarget *= 0.35
		end
		pitch += (pitchTarget - pitch) * math.clamp(dt * 6, 0, 1)
		if align then
			align.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
		if total > 3 then
			playTrack("swim", math.clamp(total / 14, 0.6, 2.2))
		else
			playTrack("idle", 1)
		end
		app.Sfx.setSwimming(total > 3 and depth > 2.5, total / math.max(1, speed))
		if bubbles then
			bubbles.Rate = if dashing then 30 else 4 + total * 0.3
		end
	end)
end

return Swim
