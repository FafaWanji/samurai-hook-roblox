-- Roblox copy of src/fight/sim.ts, line for line. Pure and deterministic: no Instances, no audio.
-- The fight scene draws `state` and plays sounds for the returned events.
-- Coordinates: x in px on the 960-wide arena. Fish `y` is the height above the floor.
-- Event x, y are screen px (y already converted with arena.floorY).
-- tests/sim.spec.luau replays fights recorded from the TypeScript sim and compares every step.
local Manifest = require(script.Parent.Manifest)

local F = Manifest.fight
local hardMode = Manifest.hardMode

local Sim = {}

local function clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end
local function sign(v: number): number
	return if v < 0 then -1 else 1
end
local function smooth(p: number): number
	return p * p * (3 - 2 * p)
end

function Sim.create(inst, stats, rng: (() -> number)?)
	local random = rng or math.random
	local def = inst.def
	local A = F.arena
	local S = F.samurai
	local FF = F.fish
	local mid = (A.left + A.right) / 2
	local fishMinX = A.left + def.size
	local fishMaxX = A.right - def.size
	local samMinX = A.left + S.bodyRadius
	local samMaxX = A.right - S.bodyRadius
	local fishMidY = A.floorY - def.size
	local samMidY = A.floorY - 64

	local state = {
		phase = "intro",
		outcome = nil :: string?,
		timeLeft = def.timer,
		hitStop = 0,
		samurai = {
			x = mid - 160, facing = 1, y = 0, hp = stats.maxHp, maxHp = stats.maxHp,
			move = "idle", stage = nil :: string?, moveTime = 0, invulnerable = false, hits = 0, misses = 0, poisonLeft = 0,
		},
		fish = {
			x = mid + 160, y = 0, facing = -1, hp = inst.maxHp, maxHp = inst.maxHp,
			mode = "roam", modeTime = 0, slipReady = true, tellProgress = 0, vulnLeft = 0, vulnTotal = 0,
		},
		effects = { dark = def.gimmick == "dark", inkLeft = 0 },
		projectiles = {},
	}
	local s = state.samurai
	local f = state.fish

	-- hidden samurai state
	local introLeft = F.introDelay
	local buffered: { kind: string, life: number }? = nil
	local strikeResolved = false
	local dashDir = 1
	local dashCd = 0
	local iframes = 0
	local hurtLeft = 0
	local knockV = 0
	local knockLeft = 0
	local vy = 0
	local contactCd = 0

	-- hidden fish state
	local arc = nil
	local hop = nil
	local stunLeft = 0
	local fishKnockV = 0
	local pref = def.move.keepAway
	local weavePhase = random() * math.pi * 2
	local repoLeft = 0.5
	local crossCd = 0
	local attackCd = if def.attack then def.attack.cooldown else 0
	local lungeHit = false
	local sp = def.special
	local specialCd = if sp then sp.cooldown * 0.6 else 0
	local chargeDir = 1
	local chargeHit = false
	local chargeSide = 1
	local chargePassed = false
	local shotsFired = 0
	local clearHeight = def.size * FF.special.clearScale
	local puffTimer = 0
	local inkTimer = 0

	local events = {}
	local function emit(kind: string, x: number, y: number, damage: number?)
		table.insert(events, { type = kind, x = x, y = y, damage = damage })
	end
	local function fishScreenY()
		return fishMidY - f.y
	end

	local function setFishMode(m: string)
		f.mode = m
		f.modeTime = 0
		f.tellProgress = 0
		f.slipReady = m == "roam" or m == "puffed"
	end

	local function setMove(m: string)
		s.move = m
		s.moveTime = 0
		s.stage = if m == "quick" or m == "heavy" then "startup" else nil
	end

	local function faceFish()
		if math.abs(f.x - s.x) > 1 then
			s.facing = sign(f.x - s.x)
		end
	end

	local function endFight(outcome: string)
		state.outcome = outcome
		state.phase = "over"
		if outcome == "win" then
			emit("win", f.x, fishScreenY())
		elseif outcome == "ko" then
			emit("ko", s.x, samMidY)
		else
			emit("timeout", mid, A.floorY - 200)
		end
	end

	-- ---------- samurai ----------

	local function startStrike(kind: string)
		faceFish()
		setMove(kind)
		strikeResolved = false
		buffered = nil
		if kind == "quick" then
			emit("quick", s.x + s.facing * 40, samMidY)
		else
			emit("heavyStart", s.x, samMidY)
		end
	end

	local function hurtSamurai(stun: number, push: number)
		setMove("hurt")
		hurtLeft = stun
		knockV = push
		knockLeft = stun
	end

	local function bodyTop()
		return if s.move == "crouch" then S.crouchHeight else S.standHeight
	end

	local function poisonSamurai()
		if not def.poison then
			return
		end
		if s.poisonLeft <= 0 then
			emit("poison", s.x, samMidY - s.y)
		end
		s.poisonLeft = def.poison.duration
	end

	local function hitSamurai(dmg: number, fromX: number, guardable: boolean)
		local away = sign(s.x - fromX)
		if guardable and s.invulnerable then
			emit("dodged", s.x, samMidY)
		elseif guardable and s.move == "block" then
			local d = dmg * (1 - S.blockReduction)
			s.hp = math.max(0, s.hp - d)
			knockV = away * S.blockPush
			knockLeft = 0.15
			emit("blocked", s.x, samMidY, d)
		else
			s.hp = math.max(0, s.hp - dmg)
			hurtSamurai(S.hurtStun, away * S.hurtKnockback)
			buffered = nil
			emit("bitten", s.x, samMidY - s.y, dmg)
			poisonSamurai()
		end
		if s.hp <= 0 then
			endFight("ko")
		end
	end

	local function touchContact(dt: number)
		contactCd = math.max(0, contactCd - dt)
		if not def.contactDamage or def.contactDamage == 0 or contactCd > 0 then
			return
		end
		if f.mode == "attack" or f.mode == "charge" then
			return
		end
		local touchingX = math.abs(f.x - s.x) <= S.bodyRadius + def.size * 0.5 + FF.contactReach
		local touchingY = f.y < s.y + bodyTop() and f.y + def.size * 2 > s.y
		if not touchingX or not touchingY then
			return
		end
		contactCd = hardMode.contactCooldown
		hitSamurai(def.contactDamage, f.x, true)
	end

	local function strikeConnects(reach: number): boolean
		local dx = f.x - s.x
		if f.mode == "slip" then
			return false
		end
		if f.y > FF.hitHeight then
			return false
		end
		if dx * s.facing < -S.bodyRadius * 0.5 then
			return false
		end
		return math.abs(dx) <= reach + def.size * 0.5
	end

	local function startArc(toX: number, dur: number, h: number)
		arc = { fromX = f.x, toX = clamp(toX, fishMinX, fishMaxX), t = 0, dur = dur, h = h }
		hop = nil
	end

	local function startSlip()
		local away = sign(f.x - s.x)
		local target = f.x + away * def.slip.dart
		if target >= fishMinX and target <= fishMaxX then
			setFishMode("slip")
			startArc(target, FF.slipDuration, FF.slipArc)
		else
			local far = s.x - away * math.max(def.move.keepAway, def.slip.dart - math.abs(f.x - s.x))
			setFishMode("slip")
			startArc(far, FF.slipDuration * 1.3, FF.overArc)
		end
		f.slipReady = false
		emit("slip", f.x, fishScreenY())
	end

	local function resolveStrike(kind: string)
		strikeResolved = true
		if f.mode == "puffed" then
			local away = -sign(f.x - s.x)
			hurtSamurai(FF.puff.stun, away * FF.puff.knockback)
			emit("bounce", (s.x + f.x) / 2, fishScreenY())
			poisonSamurai()
			return
		end
		if f.slipReady then
			startSlip()
			return
		end
		local dmg = if kind == "quick" then stats.quickDamage else stats.heavyDamage
		f.hp = math.max(0, f.hp - dmg)
		s.hits += 1
		emit(if kind == "quick" then "hit" else "heavyHit", f.x, fishScreenY(), dmg)
		state.hitStop = F.hitStop
		if f.hp <= 0 then
			endFight("win")
			return
		end
		if sp and (f.mode == "aim" or f.mode == "charge" or f.mode == "shoot") then
			specialCd = sp.cooldown
		end
		local interrupted = f.mode == "tell" or f.mode == "attack" or f.mode == "aim" or f.mode == "charge" or f.mode == "shoot"
		if interrupted and f.vulnLeft < FF.lungeRecovery then
			f.vulnLeft = FF.lungeRecovery
			f.vulnTotal = FF.lungeRecovery
		end
		arc = nil
		hop = nil
		f.y = 0
		fishKnockV = sign(f.x - s.x) * FF.hitPush
		stunLeft = FF.hitStun
		setFishMode("stunned")
	end

	local function updateSamurai(dt: number, input)
		dashCd = math.max(0, dashCd - dt)
		iframes = math.max(0, iframes - dt)
		if buffered then
			buffered.life -= dt
			if buffered.life <= 0 then
				buffered = nil
			end
		end
		s.moveTime += dt

		if knockLeft > 0 then
			local step = math.min(dt, knockLeft)
			s.x += knockV * step
			knockV -= (knockV / knockLeft) * step
			knockLeft -= step
		end

		if s.y > 0 or vy > 0 then
			vy -= S.jump.gravity * dt
			s.y += vy * dt
			if s.y <= 0 then
				s.y = 0
				vy = 0
				if s.move == "jump" then
					setMove("idle")
				end
			end
		end

		local busy = s.move == "quick" or s.move == "heavy" or s.move == "dash" or s.move == "hurt" or s.move == "jump"
		if busy and (input.quick or input.heavy) then
			buffered = { kind = if input.heavy then "heavy" else "quick", life = S.buffer }
		end

		local mv = s.move
		if mv == "quick" or mv == "heavy" then
			local cfg = if mv == "quick" then S.quick else S.heavy
			local t = s.moveTime
			if t < cfg.startup then
				s.stage = "startup"
			elseif t < cfg.startup + cfg.active then
				if s.stage ~= "active" and mv == "heavy" then
					emit("heavySwing", s.x + s.facing * 60, samMidY)
				end
				s.stage = "active"
				if not strikeResolved and strikeConnects(cfg.reach) then
					resolveStrike(mv)
				end
			elseif t < cfg.startup + cfg.active + cfg.recovery then
				if s.stage == "active" and not strikeResolved then
					strikeResolved = true
					s.misses += 1
				end
				s.stage = "recovery"
			else
				if not strikeResolved then
					strikeResolved = true
					s.misses += 1
				end
				setMove("idle")
			end
		elseif mv == "dash" then
			s.x += dashDir * (S.dash.distance / S.dash.duration) * dt
			if s.moveTime >= S.dash.duration then
				setMove("idle")
			end
		elseif mv == "hurt" then
			hurtLeft -= dt
			if hurtLeft <= 0 then
				setMove(if s.y > 0 then "jump" else "idle")
			end
		elseif mv == "jump" then
			s.x += clamp(input.moveX, -1, 1) * S.jump.airSpeed * dt
		end

		if s.move == "idle" or s.move == "walk" or s.move == "block" or s.move == "crouch" then
			local dir = if math.abs(input.moveX) > 0.3 then sign(input.moveX) else 0
			local dashOk = dir ~= 0 and (not input.crouch or math.abs(input.moveX) > S.dash.crouchMinX)
			if input.defendPressed and dashOk and dashCd <= 0 then
				setMove("dash")
				dashDir = dir
				dashCd = S.dash.cooldown + S.dash.duration
				iframes = S.dash.iframes
				emit("dash", s.x, samMidY)
			elseif input.jump then
				setMove("jump")
				vy = S.jump.speed
				emit("jump", s.x, A.floorY)
			elseif input.quick or input.heavy then
				startStrike(if input.heavy then "heavy" else "quick")
			elseif buffered then
				startStrike(buffered.kind)
			elseif input.crouch then
				if s.move ~= "crouch" then
					setMove("crouch")
				end
				faceFish()
			elseif input.defendHeld and dir == 0 then
				if s.move ~= "block" then
					setMove("block")
				end
				faceFish()
			elseif math.abs(input.moveX) > 0.05 then
				if s.move ~= "walk" then
					setMove("walk")
				end
				local before = s.x
				s.x += clamp(input.moveX, -1, 1) * S.walkSpeed * (input.walkScale or 1) * dt
				local sep = S.bodyRadius + def.size * 0.5
				if f.y < FF.hitHeight and f.mode ~= "slip" and math.abs(before - f.x) >= sep - 0.01 and math.abs(s.x - f.x) < sep then
					s.x = f.x - sign(f.x - before) * sep
				end
				faceFish()
			else
				if s.move ~= "idle" then
					setMove("idle")
				end
				faceFish()
			end
		end

		s.x = clamp(s.x, samMinX, samMaxX)
		s.invulnerable = iframes > 0
	end

	-- ---------- fish ----------

	local function runArc(a, dt: number): boolean
		a.t = math.min(a.dur, a.t + dt)
		local p = a.t / a.dur
		f.x = a.fromX + (a.toX - a.fromX) * smooth(p)
		f.y = a.h * math.sin(math.pi * p)
		return a.t >= a.dur
	end

	local function lungeContact()
		if lungeHit then
			return
		end
		if math.abs(f.x - s.x) > S.bodyRadius + def.size * 0.6 then
			return
		end
		lungeHit = true
		if s.y > clearHeight then
			emit("dodged", s.x, samMidY - s.y)
			return
		end
		hitSamurai(def.attack.damage, f.x, true)
	end

	local function startSpecial()
		f.facing = sign(s.x - f.x)
		if sp.kind == "charge" then
			chargeDir = f.facing
			chargeSide = sign(f.x - s.x)
			chargeHit = false
			chargePassed = false
			setFishMode("charge")
			emit("charge", f.x, fishScreenY())
		else
			shotsFired = 0
			setFishMode("shoot")
		end
	end

	local function endSpecial(nextMode: string)
		specialCd = sp.cooldown
		attackCd = math.max(attackCd, FF.special.lungeDelay)
		if nextMode == "vulnerable" then
			f.vulnLeft = FF.special.chargeRecovery
			f.vulnTotal = FF.special.chargeRecovery
		end
		setFishMode(nextMode)
	end

	local function runCharge(dt: number)
		local to = if chargeDir > 0 then fishMaxX else fishMinX
		f.x += chargeDir * sp.speed * dt
		f.y = 0
		if not chargeHit and math.abs(f.x - s.x) < S.bodyRadius + def.size * 0.9 and s.y < clearHeight then
			chargeHit = true
			hitSamurai(sp.damage, f.x - chargeDir, false)
			if state.phase == "over" then
				return
			end
		end
		if not chargeHit and not chargePassed and sign(f.x - s.x) ~= chargeSide then
			chargePassed = true
			emit("dodged", s.x, samMidY - s.y)
		end
		if chargeDir * (f.x - to) >= 0 then
			f.x = to
			endSpecial("vulnerable")
		end
	end

	local function runShoot()
		local pattern = sp.pattern or { "high" }
		local gap = sp.gap or 0.3
		while shotsFired < #pattern and f.modeTime >= shotsFired * gap do
			shotsFired += 1
			local height = pattern[shotsFired]
			local P = FF.special.projectile[height]
			local dir = sign(s.x - f.x)
			f.facing = dir
			local x = f.x + dir * def.size
			table.insert(state.projectiles, {
				x = x, y = P.y, r = P.r, vx = dir * sp.speed, height = height, damage = sp.damage,
				side = sign(x - s.x), passed = false,
			})
			emit("shoot", x, A.floorY - P.y)
		end
		if shotsFired >= #pattern and f.modeTime >= (#pattern - 1) * gap + FF.special.shootRecovery then
			endSpecial("roam")
		end
	end

	local function updateProjectiles(dt: number)
		local list = state.projectiles
		for i = #list, 1, -1 do
			local p = list[i]
			p.x += p.vx * dt
			local overlapX = math.abs(p.x - s.x) < S.bodyRadius + p.r
			local overlapY = p.y - p.r < s.y + bodyTop() and p.y + p.r > s.y
			if overlapX and overlapY then
				table.remove(list, i)
				hitSamurai(p.damage, p.x - p.vx, false)
				if state.phase == "over" then
					return
				end
				continue
			end
			if not p.passed and sign(p.x - s.x) ~= p.side then
				p.passed = true
				emit("dodged", s.x, samMidY - s.y)
			end
			if p.x < A.left - 60 or p.x > A.right + 60 then
				table.remove(list, i)
			end
		end
	end

	local function roam(dt: number)
		local dx = f.x - s.x
		local side = if dx == 0 then (if f.x < mid then -1 else 1) else sign(dx)
		local restless = def.move.restless

		repoLeft -= dt
		if repoLeft <= 0 then
			repoLeft = (2.4 - 1.9 * restless) * (0.6 + 0.8 * random())
			pref = def.move.keepAway * (0.8 + 0.5 * random())
			if not hop and random() < 0.3 + 0.5 * restless then
				hop = { fromX = 0, toX = 0, t = 0, dur = 0.32, h = 18 + 26 * random() }
			end
		end
		weavePhase += dt * (1.5 + 3 * restless)
		local weave = math.sin(weavePhase) * 28 * (0.4 + restless)

		local room = if side > 0 then fishMaxX - f.x else f.x - fishMinX
		if crossCd <= 0 and room < 24 and math.abs(dx) < pref * 0.85 then
			local to = s.x - side * pref
			setFishMode("roam")
			startArc(to, math.max(0.45, math.abs(to - f.x) / (def.move.speed * 2.2)), FF.overArc)
			crossCd = FF.crossCooldown
			return
		end

		local desired = clamp(s.x + side * pref + weave, fishMinX, fishMaxX)
		local diff = desired - f.x
		local maxStep = def.move.speed * dt
		f.x += if math.abs(diff) <= maxStep then diff else sign(diff) * maxStep

		if hop then
			hop.t += dt
			local p = math.min(1, hop.t / hop.dur)
			f.y = hop.h * math.sin(math.pi * p)
			if p >= 1 then
				hop = nil
				f.y = 0
			end
		else
			f.y = 0
		end
	end

	local function updateFish(dt: number)
		f.modeTime += dt
		crossCd = math.max(0, crossCd - dt)
		if math.abs(f.x - s.x) > 1 and f.mode ~= "slip" and f.mode ~= "attack" and f.mode ~= "charge" then
			f.facing = sign(s.x - f.x)
		end

		if def.gimmick == "puff" and f.mode ~= "puffed" then
			puffTimer += dt
		end
		if def.gimmick == "ink" then
			inkTimer += dt
			if inkTimer >= FF.ink.every then
				inkTimer -= FF.ink.every
				state.effects.inkLeft = FF.ink.duration
				emit("ink", f.x, fishScreenY())
			end
		end
		if def.attack and f.mode == "roam" then
			attackCd -= dt
		end
		if sp and f.mode == "roam" then
			specialCd -= dt
		end

		local m = f.mode
		if m == "roam" then
			if arc then
				if runArc(arc, dt) then
					arc = nil
					f.y = 0
				end
			elseif def.gimmick == "puff" and puffTimer >= FF.puff.every then
				puffTimer = 0
				setFishMode("puffed")
				hop = nil
				f.y = 0
				emit("puff", f.x, fishScreenY())
			elseif sp and specialCd <= 0 and f.y < 4 and math.abs(f.x - s.x) >= FF.special.minDist then
				setFishMode("aim")
				hop = nil
				f.y = 0
				emit("aim", f.x, fishScreenY())
			elseif def.attack and attackCd <= 0 and math.abs(f.x - s.x) <= def.attack.reach and f.y < 4 then
				setFishMode("tell")
				hop = nil
				f.y = 0
				emit("tell", f.x, fishScreenY())
			else
				roam(dt)
			end
		elseif m == "puffed" then
			local side = sign(f.x - s.x)
			local desired = clamp(s.x + side * pref, fishMinX, fishMaxX)
			local diff = desired - f.x
			local maxStep = def.move.speed * 0.3 * dt
			f.x += if math.abs(diff) <= maxStep then diff else sign(diff) * maxStep
			if f.modeTime >= FF.puff.duration then
				setFishMode("roam")
				emit("unpuff", f.x, fishScreenY())
			end
		elseif m == "tell" then
			local atk = def.attack
			f.tellProgress = math.min(1, f.modeTime / atk.tell)
			if f.modeTime >= atk.tell then
				local dir = sign(s.x - f.x)
				f.facing = dir
				local travel = math.min(math.abs(s.x - f.x) - S.bodyRadius * 0.3, atk.reach * 1.15)
				setFishMode("attack")
				startArc(f.x + dir * math.max(0, travel), FF.lungeDuration, 14)
				lungeHit = false
				emit("attack", f.x, fishScreenY())
			end
		elseif m == "aim" then
			f.y = 0
			if math.abs(f.x - s.x) < FF.special.aimDist then
				f.x += sign(f.x - s.x) * def.move.speed * dt
			end
			f.tellProgress = math.min(1, f.modeTime / sp.tell)
			if f.modeTime >= sp.tell then
				startSpecial()
			end
		elseif m == "charge" then
			runCharge(dt)
		elseif m == "shoot" then
			runShoot()
		elseif m == "attack" then
			local done = if arc then runArc(arc, dt) else true
			lungeContact()
			if state.phase ~= "over" and done then
				arc = nil
				f.y = 0
				attackCd = def.attack.cooldown
				f.vulnLeft = FF.lungeRecovery
				f.vulnTotal = FF.lungeRecovery
				setFishMode("vulnerable")
			end
		elseif m == "slip" then
			if not arc or runArc(arc, dt) then
				arc = nil
				f.y = 0
				f.vulnLeft = def.slip.recovery
				f.vulnTotal = def.slip.recovery
				setFishMode("vulnerable")
			end
		elseif m == "stunned" then
			f.vulnLeft = math.max(0, f.vulnLeft - dt)
			if f.vulnLeft == 0 then
				f.vulnTotal = 0
			end
			stunLeft -= dt
			f.x += fishKnockV * dt
			fishKnockV *= math.max(0, 1 - 10 * dt)
			if stunLeft <= 0 then
				fishKnockV = 0
				setFishMode(if f.vulnLeft > 0 then "vulnerable" else "roam")
			end
		elseif m == "vulnerable" then
			f.vulnLeft -= dt
			local away = sign(f.x - s.x)
			f.x += away * def.move.speed * 0.25 * dt
			f.y = 0
			if f.vulnLeft <= 0 then
				f.vulnLeft = 0
				f.vulnTotal = 0
				repoLeft = 0
				setFishMode("roam")
			end
		end
		f.x = clamp(f.x, fishMinX, fishMaxX)
	end

	local function copyEvents()
		return table.clone(events)
	end

	local function step(dt: number, input)
		table.clear(events)
		if state.phase == "over" then
			return {}
		end

		if state.phase == "intro" then
			introLeft -= dt
			if introLeft <= 0 then
				state.phase = "fighting"
				emit("fightStart", mid, A.floorY - 200)
			end
			return copyEvents()
		end

		if state.hitStop > 0 then
			state.hitStop = math.max(0, state.hitStop - dt)
			return copyEvents()
		end

		if state.effects.inkLeft > 0 then
			state.effects.inkLeft = math.max(0, state.effects.inkLeft - dt)
		end

		updateSamurai(dt, input)
		if state.phase == "fighting" then
			updateFish(dt)
		end
		if state.phase == "fighting" then
			updateProjectiles(dt)
		end
		if state.phase == "fighting" then
			touchContact(dt)
		end
		if state.phase == "fighting" and s.poisonLeft > 0 then
			local tick = math.min(dt, s.poisonLeft)
			s.poisonLeft = math.max(0, s.poisonLeft - dt)
			s.hp = math.max(0, s.hp - def.poison.dps * tick)
			if s.hp <= 0 then
				endFight("ko")
			end
		end

		if state.phase == "fighting" then
			state.timeLeft = math.max(0, state.timeLeft - dt)
			if state.timeLeft <= 0 then
				endFight("timeout")
			end
		end
		return copyEvents()
	end

	return { state = state, step = step }
end

return Sim
