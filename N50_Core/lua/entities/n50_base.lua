AddCSLuaFile()

ENT.Base 			= "base_nextbot"
ENT.Spawnable		= true
ENT.WeaponToUse = table.Random({"AR","AR"})

function ENT:Initialize()

	self:SetModel( "models/pm/moviesf/operator3b.mdl" )
	
	self.LoseTargetDist	= 2000	-- How far the enemy has to be before we lose them
	self.SearchRadius 	= 1000	-- How far to search for enemies
	self:N50_GiveWeapon(self.WeaponToUse)
	self.move_ang = Angle()
	self.OBBVec1, self.OBBVec2 = self:GetCollisionBounds() 
	vec1, vec2 = self:GetCollisionBounds()

--	self:SetCollisionBoundsWS( vec1, vec2 + Vector(0,-16,64))
	self:SetHealth(self.NPCHealth)
	self.NextGrenade = CurTime() + math.random(10,14)

end

ENT.WalkSpeed = 60
ENT.RunSpeed = 120

ENT.SearchRange = 6000
ENT.NextScan = CurTime()
ENT.NextStuck = 0
ENT.AutomaticFrameAdvance = true 
ENT.NPCHealth = 90

ENT.RagdollFreezeTime = 4

function ENT:N50_SearchEnemy()
	if SERVER then  
		if self.NextScan <= CurTime() then 
			self.NextScan = CurTime() + 1
		if GetConVar("ai_ignoreplayers"):GetInt() == 1 then return end
		for k,v in ipairs(player.GetAll()) do 
			if self:N50_CanSee(v) then 
				if self:N50_TargetAlvie(v) then 
					self:N50_OnEnemy()
					self:N50_SetEnemy(v)
				end
			end 
		end 
		end
	end
end 

function ENT:N50_CanSee(ent) 
    if IsValid(ent) and self:Visible(ent) and self:N50_EnemyCheck(ent) and self:N50_VisiableAngle(ent)then return true else return false end
end 
ENT.IsN50Bot = true 
function ENT:N50_VisiableAngle(ent)
    local directionAngCos = math.cos(math.pi / 16)
	local aimVector = self:GetForward()*self.SearchRange
	local entVector = ent:GetPos() - self:GetPos() 
	local angCos = aimVector:Dot(entVector) / entVector:Length()
	if angCos >= directionAngCos then return true else return false end
end 

ENT.NextAlert = CurTime()

function ENT:N50_AlertNearbyUnits(attacker)
	if self.NextAlert <= CurTime() then 
		self.NextAlert = CurTime() + 10
		for k,v in pairs(ents.FindInSphere(self:GetPos(), 512)) do 
			if v.IsN50Bot == true then 
				if v.Enemy == nil then 
					if self:Visible(v) then 
						v:N50_SetEnemy(attacker)
						v.Weapon.Delay = CurTime() + math.random(1,3)
					end  
				end 
			end 
		end 
	end
end 

function ENT:N50_EnemyCheck(ent)
	if self:GetRangeTo( ent:GetPos() ) >= self.SearchRange then return false else return true end
end 

function ENT:N50_TargetAlvie(ent)
	if not IsValid(ent) then return end
	if ent:IsPlayer() then 
		if ent:Health() >= 1 then return true else return false end 
	end 
end

function ENT:N50_SetEnemy(ent)
	self.Enemy = ent
end 

function ENT:N50_GetEnemy()
	return self.Enemy
end

function ENT:N50_HaveEnemy()
	if self:N50_GetEnemy() != nil then return true else return false end
end 

function ENT:RunBehaviour()
	while(true) do 
		self:N50_SearchEnemy()
		if self:N50_HaveEnemy() then 
			self:N50_PickTactics()
	  	else 
	  		self:N50_IdleActivity()
		end 
		coroutine.yield()
	end
end

function ENT:N50_ChaseEnemy()
	local options = options or {}
	local path = Path( "Follow" )
	path:SetMinLookAheadDistance( options.lookahead or 300 )
	path:SetGoalTolerance( options.tolerance or 20 )
	path:Compute( self, self:N50_GetEnemy():GetPos() )		-- Compute the path towards the enemy's position

	if ( !path:IsValid() ) then return "failed" end

	while ( path:IsValid() and self:N50_HaveEnemy() ) do
			
		if ( path:GetAge() > 0.1 ) then					-- Since we are following the player we have to constantly remake the path
			path:Compute(self, self:N50_GetEnemy():GetPos())-- Compute the path towards the enemy's position again
		end
		path:Update( self )								-- This function moves the bot along the path
		self:N50_BodyMoveYaw()
		self:N50_ObstacleDetection()	
		if self:N50_CanSee(self:N50_GetEnemy()) then 
			self:N50_BodyMoveYaw() 
			self:N50_Shot(self:N50_GetEnemy():GetPos())
		else 
			self.Weapon.Delay = CurTime() + 1
		end 

		if ( options.draw ) then path:Draw() end
		if ( self.loco:IsStuck() ) then
			self:HandleStuck()
			return "stuck"
		end

		coroutine.yield()

	end

	return "ok"
end 

function ENT:N50_MoveToPos( pos, ignore )
	local ignore = ignore or false 
	local path = Path( "Follow" )
	path:SetMinLookAheadDistance( 300 )
	path:SetGoalTolerance( 20 )
	path:Compute( self, pos )

	if ( !path:IsValid() ) then return "failed" end

	while ( path:IsValid() ) do
		path:Update( self )
		self:N50_BodyMoveYaw()
		self:N50_SearchEnemy()
		self:N50_ObstacleDetection()
		self:N50_HandleStuck(path)
		if ignore == false then 
			if self:N50_HaveEnemy() then 
				return "ok"
			end 
		end

		if ignore == true then 
			if self:N50_HaveEnemy() then 
				if self:N50_CanSee(self:N50_GetEnemy()) then 
					self:N50_BodyMoveYaw()
					self:N50_Aim(self:N50_GetEnemy():GetPos())
					self:N50_Shot(self:N50_GetEnemy():GetPos())
				end
			end 
		end

		if ( self.loco:IsStuck() ) then
			self:HandleStuck()
			return "stuck"
		end



		coroutine.yield()
	end
	return "ok"
end

function ENT:N50_HandleStuck(path)
	if self.loco:GetVelocity():Length() <= 2 then 
		--self.NextStuck = self.NextStuck + 1
		print(self.NextStuck)
	end

	if self.NextStuck >= 10 then 
	--	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS )
		self.loco:SetVelocity( self.loco:GetVelocity() + VectorRand() * 2 )
		self.NextStuck = 0
		return path:Invalidate()
	end 
end 

function ENT:N50_IdleActivity()
	self:N50_SetupActivity("walk")
	self:N50_MoveToPos(self:GetPos() + Vector( math.Rand( -1, 1 ), math.Rand( -1, 1 ), 0 ) * 512 )
end 

function ENT:N50_SetupActivity(task,force)
	force = force or false
	if force == false then 
		if self:N50_GetTask() == task then return end
	end
	local f = ACTIVITY_TABLE[tostring(task)]
	if f then f(self) end 
end 

function ENT:N50_SetTask(task)
	self.Task = task 
end 

function ENT:N50_GetTask(task)
	return self.Task
end

function ENT:BodyUpdate()
	self:BodyMoveXY()
	self:N50_BodyMoveYaw()
	self:FrameAdvance()
end

function ENT:N50_PickTactics()
	local a = table.Random({"CHASE","STRAFE"})
	TASK_TABLE[a](self)
end 


ENT.WalkActivity = ACT_HL2MP_WALK_AR2
ENT.RunActivity = ACT_HL2MP_RUN_AR2
ENT.GrenadeActivity = ACT_HL2MP_IDLE_GRENADE

AVALIABLE_ACTIVITY_TABLE = {
	"walk","run",
}

ACTIVITY_TABLE = {
	["walk"] = function(self)
		self:StartActivity(self.WalkActivity)
		self.loco:SetDesiredSpeed(self.WalkSpeed)
		self:N50_SetTask("walk")

	end,
	["run"] = function(self)
		self:StartActivity(self.RunActivity)
		self.loco:SetDesiredSpeed(self.RunSpeed)
		self:N50_SetTask("run")
	end,
	["grenade"] = function(self)
		self:StartActivity(self.GrenadeActivity)
		self.loco:SetDesiredSpeed(self.WalkSpeed)
		self:N50_SetTask("grenade")
	end,
}

TASK_TABLE = {
	["CHASE"] = function(self)
		self:N50_SetupActivity("run")
		self.loco:FaceTowards(self:N50_GetEnemy():GetPos())
		self:N50_MoveToPos(self:N50_GetEnemy():GetPos(),true)
	end,
	["STRAFE"] = function(self) 
		self.loco:FaceTowards(self:N50_GetEnemy():GetPos())
		self:N50_SetupActivity("run")
		self.loco:FaceTowards(self:N50_GetEnemy():GetPos())
		self:N50_MoveToPos(self:GetPos() + self:GetRight() * math.random(-512,512),true)
	end, 
}

WEAPON_TABLE = {
	["AR"] = {
		Model = "models/arachnit/insurgency_sandstorm/weapons/assault_rifles/m4a1.mdl",
		Damage = 22,
		Num = 1,
		Tracer = "tracer_green",
		Magazine = 30,
		A_Reload = "reload_smg1",
		ROF = 850,
		BaseSpread = Vector(0.03,0.03,0),
		TracerEvery = 3,
		FireSound = "weapons/tfa_eft/m4a1/m4_fp.wav",
		ReloadSound = "boomsticks/misc/full_reload_m4.wav",
		ReloadTime = 3,
		OffsetPosition = Vector(2,-3,1), -- forward -- up -- right
		MagModel = "models/arachnit/insurgency_sandstorm/weapons/assault_rifles/m4a1_magazine.mdl",
		["OnReload"] = function(self,weapon)
			weapon:SetBodygroup(10, 3)
			self:N50_DropMagazine()
			timer.Simple(1.5,function()
				if IsValid(weapon) then 
					weapon:SetBodygroup(10, 0)
				end
			end) 
		end,
	},
	["MP5"] = {
		Model = "models/arachnit/insurgency_sandstorm/weapons/sub_machine_guns/mp5a5.mdl",
		Damage = 12,
		Num = 1,
		Tracer = "tracer_green",
		Magazine = 30,
		A_Reload = "reload_smg1",
		ROF = 850,
		BaseSpread = Vector(0.032,0.032,0),
		TracerEvery = 3,
		FireSound = "boomsticks/mp5/fire.wav",
		ReloadSound = "boomsticks/misc/full_reload_m4.wav",
		ReloadTime = 3,
		OffsetPosition = Vector(0.5,-2,1),
		MagModel = "models/arachnit/insurgency_sandstorm/weapons/sub_machine_guns/mp5a5_magazine.mdl",
		["OnReload"] = function(self,weapon)
			weapon:SetBodygroup(5,3)
			self:N50_DropMagazine()
			timer.Simple(1.5,function()
				if IsValid(weapon) then 
					weapon:SetBodygroup(5, 0)
				end
			end) 
		end,
	}
}



function ENT:Think()
	if SERVER then
		if self:N50_HaveEnemy() then 
			if not self:N50_GetEnemy():Alive() then 
				self:N50_SetEnemy(nil)
				self:N50_OnEnemyDeath()
			end 
		end 

	--if IsValid(self.DynamicMuzzle) then 
	--	if self.DynamicMuzzle.LifeTime < CurTime() then 
	--		self.DynamicMuzzle:Remove()
	--	end 
	--end 

	end 
end 

function ENT:N50_RemoveWeapon()
	if SERVER then
		if self:N50_HaveWeapon() then  
			self.Weapon:Remove()
		end
	end 
end 

function ENT:N50_OnEnemyDeath()
end 

ENT.GrenadeMinDistance = 512
ENT.GrenadeMaxDistance = 1024

function ENT:N50_GrenadeTo(pos)
	if self.NextGrenade >= CurTime() then return end
	local dist = self:GetPos():Distance(pos)
	if dist > self.GrenadeMaxDistance or dist < self.GrenadeMinDistance then return end
	self.NextGrenade = self.NextGrenade + math.random(30,160)
	local weapon = self.Weapon.Name
	local mag = self.Weapon.Magazine
	self:N50_RemoveWeapon()

	self:NB_PlayGestureSequenceAndWait("holster_ar",0.30,0.29)
	local boner = self:LookupBone("ValveBiped.Bip01_R_Hand")
	local bone_pos = self:GetBonePosition(boner)
	if bone_pos == self:GetPos() then
		bone_pos = self:GetBoneMatrix(boner):GetTranslation()
	end

	self.NadeMDL = ents.Create("prop_dynamic")
	self.NadeMDL:SetModel( "models/weapons/w_eq_fraggrenade_thrown.mdl" )
	self.NadeMDL:SetPos( bone_pos )
	self.NadeMDL:SetAngles( Angle(0,90,90) )
	self.NadeMDL:SetParent( self )
	self.NadeMDL:Fire("setparentattachment", "Anim_Attachment_RH", 0.01 )
	self:N50_SetupActivity("grenade",true)
	self:NB_PlayGestureSequenceAndWait("draw_grenade",0.30,0.30)
	self:EmitSound("boomsticks/misc/rgd_pin.wav")
	self.HoldingLiveGrenade = true
	self:N50_SetupActivity("grenade",true)
	self:EmitSound("boomsticks/misc/rgd_throw.wav")
	self:N50_Aim(pos)
	self.loco:FaceTowards(pos)
	self:NB_PlayGestureSequenceAndWait("range_grenade",0.5,0.30)
	self:N50_Aim(pos)
	self.loco:FaceTowards(pos)
	local ThrowVel = (pos+self:OBBCenter() - self:GetPos()) 
	local gent = ents.Create("n40_grenade") 
	gent:SetPos(bone_pos) 
	gent:Spawn()
	local phys = gent:GetPhysicsObject() 
		if IsValid(phys) then
			phys:Wake()
			phys:AddAngleVelocity(Vector(math.Rand(500,500),math.Rand(500,500),math.Rand(500,500)))
			phys:SetVelocity(ThrowVel)
			self.HoldingLiveGrenade = false
		end
	self.NadeMDL:Remove()
	self:N50_SetupActivity("run",true)
--	self:N50_SetupActivity("grenade",true)
	self:N50_GiveWeapon(weapon)
	self:NB_PlayGestureSequenceAndWait("draw_ar",0.30,0)
	self:N50_SetupActivity("run",true)
end

function N50_GetWeaponData(name)
	return WEAPON_TABLE[tostring(name)]
end 
 
ENT.ShouldDropMags = true 

function ENT:N50_DropMagazine()
	if self.ShouldDropMags then 
		local a = ents.Create("prop_physics")
		a:SetModel(self.Weapon.MagModel)
		a:SetPos(self.Weapon:GetBonePosition( self.Weapon:LookupBone("b_wpn_mag")))
		a:Spawn()
		a:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	end 
end 

function ENT:N50_GiveWeapon(weapon)

	if SERVER then 

		if IsValid(self.Weapon) then self.Weapon:Remove() end 

		local att = "anim_attachment_RH"
	
		local shootpos = self:GetAttachment(self:LookupAttachment(att))
		
		local wep = ents.Create("prop_dynamic")
		wep:SetModel(N50_GetWeaponData(weapon).Model)
		wep:SetOwner(self)
		wep:SetPos(shootpos.Pos)
		wep:Spawn()
		wep:SetSolid(SOLID_NONE)
		wep:SetAngles(self:GetForward():Angle())

		timer.Simple(0.1,function()
			local hand  = self:GetAttachment( self:LookupAttachment(att) )
			local pos = self:GetAttachment( self:LookupAttachment(att)).Pos
	
			local m = Matrix() 
			m:SetAngles(self:GetAttachment( self:LookupAttachment(att)).Ang)
			local vec = N50_GetWeaponData(weapon).OffsetPosition
			wep:SetPos(pos + m:GetForward()*vec.x +  m:GetUp()*vec.y +  m:GetRight()*vec.z)
	
			wep:SetAngles(self:GetAttachment( self:LookupAttachment(att)).Ang)
			wep:SetParent(self,att)
			wep:Fire("SetParentAttachmentMaintainOffset", att)
		end)

		self.Weapon = wep
		self.Weapon.Name = weapon
		self.Weapon.Model = N50_GetWeaponData(self.Weapon.Name).Model
		self.Weapon.Damage = N50_GetWeaponData(self.Weapon.Name).Damage
		self.Weapon.Num = N50_GetWeaponData(self.Weapon.Name).Num
		self.Weapon.Tracer = N50_GetWeaponData(self.Weapon.Name).Tracer
		self.Weapon.Magazine = N50_GetWeaponData(self.Weapon.Name).Magazine
		self.Weapon.A_Reload = N50_GetWeaponData(self.Weapon.Name).A_Reload
		self.Weapon.ROF = N50_GetWeaponData(self.Weapon.Name).ROF
		self.Weapon.BaseSpread = N50_GetWeaponData(self.Weapon.Name).BaseSpread
		self.Weapon.TracerEvery = N50_GetWeaponData(self.Weapon.Name).TracerEvery
		self.Weapon.Delay = CurTime()
		self.Weapon.ReloadSound = CreateSound( self, N50_GetWeaponData(self.Weapon.Name).ReloadSound )
		self.Weapon.FireSound = N50_GetWeaponData(self.Weapon.Name).FireSound
		self.Weapon.ReloadTime = N50_GetWeaponData(self.Weapon.Name).ReloadTime
		self.Weapon.MagModel = N50_GetWeaponData(self.Weapon.Name).MagModel

		--self:AddFlashlight()
	end

end 


--function ENT:N50_ChangeWeaponTo()
--	self:NB_PlayGestureSequenceAndWait("holster_ar",0.5)
--	self:N50_GiveWeapon("MP5")
--end

function ENT:AddFlashlight()
--	local shootpos = self:GetAttachment(self:LookupAttachment("anim_attachment_LH"))
--
--	local flashlight = ents.Create("prop_dynamic")
--	flashlight:SetPos(self.Weapon:GetPos())
--	flashlight:SetModel("models/arachnit/insurgency_sandstorm/weapons/attachments/attachment_flashlights.mdl")
--	flashlight:SetParent(self.Weapon)
--	flashlight:Spawn()
--	flashlight:SetPos(self.Weapon:GetForward()*12 + self.Weapon:GetUp()*-5)
--
--	local wep = ents.Create("bd_lamp")
--	wep:SetPos(self.Weapon:GetPos())
--
--	wep:SetModel(Model("models/arachnit/insurgency_sandstorm/weapons/attachments/attachment_flashlights.mdl"))
--	wep:SetParent(flashlight)
--	wep:Spawn()
--	wep:SetPos(flashlight:GetPos() - wep:GetUp() * -10)
--	wep:SetFlashlightTexture("effects/flashlight/soft")
--	wep:SetColor(Color(255, 255, 255))
--	wep:SetDistance(512)
--	wep:SetBrightness(1)
--	wep:SetLightFOV(80)
--	wep:Switch(true)
--	wep:SetModelScale(1, 0)
--	wep:SetSolid(SOLID_NONE)
--
--	self.Flashlight = wep
end

function ENT:N50_HaveWeapon()
	if IsValid(self.Weapon) then return true else return false end
end 

ENT.ShouldReloadNextTime = false

function ENT:N50_OnReload()
	local f = N50_GetWeaponData(self.Weapon.Name)["OnReload"]
	if f then f(self,self.Weapon) end
end 

function ENT:N50_Shot(pos)
	self:N50_GrenadeTo(pos)
	if not self:N50_HaveWeapon() then return end
	if self.Weapon.Delay > CurTime() then return end 

	if self.Weapon.Magazine <= 0 and self.ShouldReloadNextTime == false then 
		self.ShouldReloadNextTime = true 
		self:EmitSound("vox/trigger_empty.wav", 100, 100, 1, CHAN_AUTO)
		self.Weapon.Delay = CurTime() + 1
		return
	end 	

	if self.Weapon.Magazine <= 0 and self.ShouldReloadNextTime == true then 
		self.ShouldReloadNextTime = false
		self:N50_OnReload()
		return self:N50_Reload()
	end 	

	if self:N50_HaveEnemy() then 
		pos = pos + self:N50_GetEnemy():OBBCenter()
	end 

	self.Weapon.Muzzle = self.Weapon:GetBonePosition( self.Weapon:LookupBone("b_attachment_barrel_root"))
	self.Weapon.Muzzle = self.Weapon.Muzzle + self.Weapon:GetForward()*8
	local distance = self:GetPos():DistToSqr(pos)
	local ang = (pos - self.Weapon.Muzzle):Angle()

	self.loco:FaceTowards(pos)
	self:N50_Aim(pos)

	self.DynamicDelay = math.random(0,0.2)

	local bullet = {}

	bullet.Num 	= self.Weapon.Num
	bullet.Dir 	= ang:Forward()
	bullet.Src 	= self.Weapon.Muzzle
	bullet.Spread 	= self.Weapon.BaseSpread + Vector(math.random())
	bullet.Tracer	= self.Weapon.TracerEvery
	bullet.TracerName = self.Weapon.Tracer
	bullet.Force	= self.Weapon.Damage 
	bullet.Damage	= -1--self.Weapon.Damage
	bullet.AmmoType = "ar2"

	self:EmitSound(self.Weapon.FireSound, math.random(95,105), 100, 1, CHAN_WEAPON)
	self:AddGestureSequence( self:GetSequenceActivity( self:LookupSequence("gesture_shoot_ar2"),false))
	self:FireBullets( bullet, true )
	self:N50_FireEffects()
	--self:AddGesture( self:GetSequenceActivity( self:LookupSequence("gesture_shoot_ar2"),false))

	self.Weapon.Magazine = self.Weapon.Magazine - self.Weapon.Num 

	self.Weapon.Delay = CurTime() + 60 / self.Weapon.ROF + self.DynamicDelay
end 

function ENT:N50_Reload()
	if not self.Weapon.IsReloading then
		self.Weapon.ReloadSound:Play()

		---self:EmitSound("boomsticks/misc/full_reload_m4.wav", math.random(95,105), 100, 1, CHAN_ITEM)
		self.Weapon.Delay = self.Weapon.Delay + self.Weapon.ReloadTime
		self.Weapon.IsReloading = true
		local activity = self:GetActivity()

		self:NB_PlayGestureSequence( "reload_ar2", 0.5 , 1 )

		self.Weapon.Magazine = N50_GetWeaponData(self.Weapon.Name).Magazine
		self.Weapon.IsReloading = false
		self:StartActivity(activity)
	end
end 




function ENT:NB_PlayGestureSequence( name, speed , delay )
	local speed = speed or 1
	local delay = delay or 0
	local sequencestring = self:LookupSequence( name )
	local len = self:AddGestureSequence( sequencestring, true )

	self:ResetSequenceInfo()
	self:SetCycle( 0 )
	self:SetPlaybackRate( speed )
	self:SetLayerPlaybackRate( len, speed )
	--coroutine.wait( len + delay / speed )
end

function ENT:NB_PlayGestureSequenceAndWait( name, speed , delay )
	local speed = speed or 1
	local delay = delay or 0
	local sequencestring = self:LookupSequence( name )
	local len = self:AddGestureSequence( sequencestring, true )

	self:ResetSequenceInfo()
	self:SetCycle( 0 )
	self:SetPlaybackRate( speed )
	self:SetLayerPlaybackRate( len, speed )
	coroutine.wait( len + delay / speed )
end

function ENT:N50_FireEffects()
	if not IsFirstTimePredicted() then return end
	self.Weapon.Muzzle = self.Weapon:GetBonePosition( self.Weapon:LookupBone("b_attachment_barrel_root"))
	self.Weapon.Muzzle = self.Weapon.Muzzle + self.Weapon:GetForward()*8
	ParticleEffect( "muzzleflash_ar2_npc", self.Weapon.Muzzle, self.Weapon:GetAngles() )
	--local light = ents.Create("light_dynamic")
	--light:Spawn()
	--light:Activate()
	--light:SetKeyValue("distance", 256) 
	--light:SetKeyValue("brightness", 5)
	--light:SetKeyValue("brightness", 5)
	--light:SetKeyValue("_light", "255 192 64") 
	--light:Fire("TurnOn")
	--light:SetPos(self.Weapon:GetPos())
	--light:SetParent(self.Weapon)
	--light.LifeTime = CurTime() + 0.25
	--self.DynamicMuzzle = light 
	--timer.Simple(0.1,function() light:Remove() end)
end 


function ENT:N50_BodyMoveYaw() -- Иди нахуй https://github.com/raubana/robustsnextbot/blob/master/lua/entities/base_robustsnextbot/sv_animation.lua
	local my_ang = self:GetAngles()
	local my_vel = self.loco:GetGroundMotionVector()

	if my_vel:IsZero() then return end
	
	local move_ang = my_vel:Angle()
	local ang_dif = move_ang - my_ang
	ang_dif:Normalize()
	
	self.move_ang = LerpAngle( 0.1, ang_dif, self.move_ang )
	
	self:SetPoseParameter( "move_yaw", self.move_ang.yaw )

	if self:N50_HaveEnemy() then 
		if self:N50_CanSee(self:N50_GetEnemy()) then 
			self:N50_Aim(self:N50_GetEnemy():GetPos() )
			self.loco:FaceTowards(self:N50_GetEnemy():GetPos())
		end
	end 


end

function ENT:N50_Aim(vec)
--	if not IsValid(vec) then return end
	local y,p=self:N50_GetYawPitch(vec)
	if y == false then
		return false
	end
	self:SetPoseParameter("aim_yaw",y)
	self:SetPoseParameter("aim_pitch",p)
	return true
end

function ENT:N50_GetYawPitch(vec)
	local yawAng=vec-self:EyePos()
	local yawAng=self:WorldToLocal(self:GetPos()+yawAng):Angle()

	local pAng=vec-self:LocalToWorld((yawAng:Forward()*8)+Vector(0,0,0))
	local pAng=self:WorldToLocal(self:GetPos()+pAng):Angle()

	local y=yawAng.y
	local p=pAng.p

	if y>=180 then y=y-360 end
	if p>=180 then p=p-360 end
	if y<-60 || y>60 then return false end
	if p<-81.2 || p>50 then return false end
	return y,p
end


ENT.NextObstacleCheck = CurTime()


function ENT:N50_ObstacleDetection()

	if self.NextObstacleCheck <= CurTime() then 
		local ent = self
		local mins = Vector(-4,-16,-32)
		local maxs = Vector(16,16,16)
		local startpos = ent:GetPos()+ent:OBBCenter()
		local dir = ent:GetForward()
		local len = 16

		local BodyCheck = util.TraceHull( {
			start = startpos,
			endpos = startpos + dir * len,
			maxs = maxs,
			mins = mins,
			filter = ent
		})

			debugoverlay.Box( ent:GetPos()+ent:OBBCenter()+self:GetForward()*16, Vector(-4,-16,-32), Vector(4,16,16), 0.1, Color( 255, 255, 255 ) )
			if IsValid(BodyCheck.Entity) then 
			local f = OBSTACLE_TABLE[tostring(BodyCheck.Entity:GetClass())]
			if f then 
				f(self,BodyCheck)
			end 
		end
	end 

end 


OBSTACLE_TABLE = {
	["prop_physics"] = function(self,ob)
		if IsValid(ob.Entity) and ob.Entity:OBBMaxs().z <= 160 then
			self:N50_HitObject(ob)
		end
	return end,
	["prop_door_rotating"] = function(self,ob)
		if IsValid(ob.Entity) then
			self:N50_OpenDoor(ob)
		end
	return end,
}

function ENT:N50_OnEnemy()
	if not self:N50_HaveEnemy() then 
		self:EmitSound("vox/contact_0"..math.random(1,7)..".wav", math.random(95,105), 100, 1, CHAN_VOICE)
		self.Weapon.Delay = CurTime() + 2
	end 
end 

function ENT:N50_OpenDoor(ob)
	local past_activity = self:GetActivity()
	--self.loco:Approach(ob.Entity:GetPos(),1)
	--self:N50_Aim(ob.Entity:GetPos())
	timer.Simple(1,function()
		ob.Entity:SetSolid(SOLID_NONE) 
		ob.Entity:Fire("Open")
		timer.Simple(6,function()
			ob.Entity:SetSolid(SOLID_VPHYSICS) 
		end)
	end)
	--self:PlaySequenceAndWait(self:LookupSequence("Open_door_away"),1)
	self:StartActivity(past_activity)
end 

function ENT:N50_HitObject(ob)
	local phys = ob.Entity:GetPhysicsObject()
	local mass = phys:GetMass()
	local past_activity = self:GetActivity()

	timer.Simple(0.5,function()
		phys:ApplyForceOffset( self:GetForward()*mass*256, phys:GetPos())
		ob.Entity:EmitSound("misc/debris_wood1.wav")
		ob.Entity:TakeDamage( 100, self, self )
	end)
	self:NB_PlayGestureSequenceAndWait("melee_smg",0.5,0.25)
	self:StartActivity(past_activity)
end

function ENT:OnKilled(dmginfo)
	self:Remove()
	self:N50_BecomeRagdoll(dmginfo)
	self:EmitSound("vox/death_0"..math.random(1,7)..".wav", math.random(95,105), 100, 1, CHAN_ITEM)
	if self.HoldingLiveGrenade == true then 
		local boner = self:LookupBone("ValveBiped.Bip01_R_Hand")
		local bone_pos = self:GetBonePosition(boner)
		if bone_pos == self:GetPos() then
			bone_pos = self:GetBoneMatrix(boner):GetTranslation()
		end
		local gent = ents.Create("n40_grenade") 
		gent:SetPos(bone_pos) 
		gent:Spawn()	
	end 
	if IsValid(self.Weapon.ReloadSound) and self.Weapon.ReloadSound:IsPlaying() then 
		self.Weapon.ReloadSound:Stop()
	end 
end 



FLINCH_TABLE = {
	"flinch_phys_01",
	"flinch_phys_02",
	"flinch_head_01",
	"flinch_head_02",
	"flinch_stomach_01",
	"flinch_stomach_02",
}

ENT.NextHitSound = CurTime()

ENT.HitBoxToHitGroup = {
	[0] = HITGROUP_HEAD,
	[16] = HITGROUP_CHEST,
	[15] = HITGROUP_STOMACH,
	[5] = HITGROUP_RIGHTARM,
	[2] = HITGROUP_LEFTARM,
	[12] = HITGROUP_RIGHTLEG,
	[8] = HITGROUP_LEFTLEG
}

function ENT:OnInjured(dmginfo)
	self:N50_AlertNearbyUnits(dmginfo:GetAttacker())
	self.Weapon.Delay = CurTime() + 1
	if not self:N50_HaveEnemy() and dmginfo:GetAttacker():IsPlayer() then 
	--	self:N50_SetEnemy(dmginfo:GetAttacker())
	end 
	if self:Health() <= 50 then 
		self.WalkActivity = 2321
		self.RunActivity = 2321
		self.WalkSpeed = 40
		self.RunSpeed = 40
		self:N50_SetupActivity("walk",true)
	end
	self:N50_Aim(dmginfo:GetAttacker():GetPos())
	self:NB_PlayGestureSequence( table.Random(FLINCH_TABLE), 0.5 , 1 )
	if self.NextHitSound <= CurTime() then 
		self:EmitSound("vox/hit_0"..math.random(1,7)..".wav", math.random(95,105), 100, 1, CHAN_ITEM)
		self.NextHitSound = CurTime() + 1
	end


	local pos = dmginfo:GetDamagePosition()
	local hitgroup = 0

	local dist_to_hitgroups = {}
	for hitbox,hitgroup in pairs(self.HitBoxToHitGroup) do
		local bone = self:GetHitBoxBone(hitbox, 0)
		if bone then
			local bonepos, boneang = self:GetBonePosition(bone)
			table.insert(dist_to_hitgroups, {bonename = self:GetBoneName(bone), hitgroup = hitgroup, dist = pos:Distance(bonepos)})
		end
	end 

	table.SortByMember(dist_to_hitgroups, "dist", true)
	hitgroup = dist_to_hitgroups[1].hitgroup

	if hitgroup == 0 then 
		dmginfo:ScaleDamage(3)
	end 	
end

function ENT:N50_BecomeRagdoll(dmginfo)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return nil end
	rag:SetPos(self:GetPos())
	rag:SetModel(self:GetModel())
	rag:SetAngles(self:GetAngles())
	rag:Spawn()	
	rag:Activate()
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	local num = rag:GetPhysicsObjectCount()-1
	local v = self:GetVelocity()
	if dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_SLASH) then
		v = v * 1
	end
	for i=0, num do
		local bone = rag:GetPhysicsObjectNum(i)
		if IsValid(bone) then
			local bp, ba = self:GetBonePosition(rag:TranslatePhysBoneToBone(i))
			if bp and ba then
				bone:SetPos(bp)
				bone:SetAngles(ba)
			end
			bone:SetVelocity(v*1) 
		end
	end
	
 	local head = rag:GetPhysicsObjectNum(math.random(6,7))
 	head:ApplyForceOffset( Vector(math.random(0,256), math.random(0,256), math.random(0,256)), self:GetPos() + Vector( math.Rand( -1, 1 ), math.Rand( -1, 1 ), 0 ) * 512)

 	if self:N50_HaveWeapon() then 
 		local weapon = ents.Create("prop_physics")
 		weapon:SetModel(N50_GetWeaponData(self.Weapon.Name).Model)
 		weapon:SetPos(self.Weapon:GetPos())
 		weapon:Spawn()
 		weapon:SetCollisionGroup(COLLISION_GROUP_DEBRIS )
 	end

	timer.Simple(self.RagdollFreezeTime,function()
 		if not IsValid(rag) then return end
 		for i=0, num do
			local bone = rag:GetPhysicsObjectNum(i)
			bone:EnableMotion(false)
		end
 	end)

end 

list.Set( "NPC", "simple_nextbot", {
	Name = "Simple bot",
	Class = "simple_nextbot",
	Category = "Nextbot"
})
