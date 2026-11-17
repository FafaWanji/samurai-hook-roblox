--!strict
-- Roblox copy of src/manifest.ts: tuning, fish, upgrades and text.
-- Keep the numbers in step with src/manifest.ts (tests/sim.spec.luau checks the fight against the web build).
-- Asset IDs live in Assets.luau, not here.

local M = {}

M.fish = {
	{
		id = "sardine", name = "Iwashi", title = "SARDINE · WHITE BELT", category = "slippery", sprite = "fish.sardine",
		depthMin = 5, depthMax = 25, hp = 40, timer = 25, gold = 5, swimSpeed = 70, size = 32,
		move = { speed = 150, keepAway = 120, restless = 0.3 },
		slip = { recovery = 3.0, dart = 180 },
		gimmick = "none",
		taunts = { "I AM ONE OF MILLIONS!", "YOU CANNOT CAN ME!", "SMALL FISH. BIG DREAMS." },
	},
	{
		id = "mackerel", name = "Saba", title = "MACKEREL · 3RD DAN", category = "slippery", sprite = "fish.mackerel",
		depthMin = 15, depthMax = 40, hp = 70, timer = 31, gold = 12, swimSpeed = 95, size = 40,
		move = { speed = 200, keepAway = 140, restless = 0.5 },
		slip = { recovery = 2.0, dart = 240 },
		gimmick = "none",
		taunts = { "HOLY ME!", "YOUR BLADE IS DULL. LIKE YOUR BAIT.", "CATCH THIS? UNLIKELY!" },
	},
	{
		id = "piranha", name = "Pirania", title = "PIRANHA · THE NIBBLER", category = "biter", sprite = "fish.piranha",
		depthMin = 30, depthMax = 55, hp = 90, timer = 31, gold = 25, swimSpeed = 120, size = 38,
		move = { speed = 260, keepAway = 110, restless = 0.8 },
		slip = { recovery = 1.8, dart = 200 },
		attack = { damage = 6, tell = 0.3, cooldown = 1.1, reach = 150 },
		gimmick = "none",
		taunts = { "NOM. NOM. NOM.", "I SKIPPED LUNCH FOR THIS!", "DEATH BY A THOUSAND NIBBLES!" },
	},
	{
		id = "eel", name = "Unagi", title = "EEL · GRAND SLIPMASTER", category = "slippery", sprite = "fish.eel",
		depthMin = 40, depthMax = 70, hp = 80, timer = 38, gold = 40, swimSpeed = 110, size = 42,
		move = { speed = 280, keepAway = 130, restless = 0.7 },
		slip = { recovery = 0.9, dart = 320 },
		special = { kind = "shot", damage = 8, tell = 0.6, cooldown = 3.2, speed = 380, pattern = { "low" } },
		gimmick = "none",
		taunts = { "SHOCKING, ISN'T IT?", "TOO SLIPPERY FOR YOU, OLD MAN!", "EEL BE BACK." },
	},
	{
		id = "pufferfish", name = "Fugu", title = "PUFFERFISH · THE ROUND ONE", category = "slippery", sprite = "fish.pufferfish",
		depthMin = 55, depthMax = 90, hp = 160, timer = 38, gold = 70, swimSpeed = 60, size = 44,
		move = { speed = 140, keepAway = 120, restless = 0.3 },
		slip = { recovery = 2.2, dart = 160 },
		special = { kind = "shot", damage = 8, tell = 0.6, cooldown = 4, speed = 400, pattern = { "high", "high" }, gap = 0.35 },
		poison = { dps = 3, duration = 4 },
		gimmick = "puff",
		taunts = { "DO NOT TOUCH. SERIOUSLY.", "I AM INFLATING MY EGO!", "ONE BITE AND YOU DIE. OF ME." },
	},
	{
		id = "swordfish", name = "Kajiki", title = "SWORDFISH · RIVAL DUELLIST", category = "biter", sprite = "fish.swordfish",
		depthMin = 75, depthMax = 110, hp = 200, timer = 38, gold = 120, swimSpeed = 150, size = 40,
		move = { speed = 230, keepAway = 220, restless = 0.5 },
		slip = { recovery = 1.6, dart = 260 },
		attack = { damage = 15, tell = 0.5, cooldown = 1.8, reach = 280 },
		special = { kind = "charge", damage = 20, tell = 0.8, cooldown = 3.5, speed = 950 },
		gimmick = "none",
		taunts = { "EN GARDE!", "MY SWORD IS ATTACHED. IS YOURS?", "I WAS BORN ARMED!" },
	},
	{
		id = "anglerfish", name = "Anko", title = "ANGLERFISH · LIGHTS OUT", category = "slippery", sprite = "fish.anglerfish",
		depthMin = 95, depthMax = 130, hp = 260, timer = 50, gold = 200, swimSpeed = 55, size = 44,
		move = { speed = 170, keepAway = 150, restless = 0.5 },
		slip = { recovery = 1.6, dart = 240 },
		gimmick = "dark",
		taunts = { "COME TOWARD THE LIGHT.", "I HAVE SEEN THINGS. DARK THINGS.", "WHO TURNED OFF THE OCEAN?" },
	},
	{
		id = "shark", name = "Hojiro", title = "GREAT WHITE · FINAL-ISH BOSS", category = "biter", sprite = "fish.shark",
		depthMin = 115, depthMax = 150, hp = 400, timer = 50, gold = 350, swimSpeed = 90, size = 56,
		move = { speed = 150, keepAway = 200, restless = 0.4 },
		slip = { recovery = 2.4, dart = 200 },
		attack = { damage = 35, tell = 0.9, cooldown = 2.6, reach = 260 },
		special = { kind = "shot", damage = 15, tell = 0.7, cooldown = 5, speed = 450, pattern = { "low" } },
		gimmick = "none",
		taunts = { "WE'RE GONNA NEED A BIGGER SAMURAI.", "I SMELL HONOUR. AND LUNCH.", "DUN DUN. DUN DUN." },
	},
	{
		id = "squid", name = "Daioika", title = "GIANT SQUID · EIGHT-ARMED STYLE", category = "slippery", sprite = "fish.squid",
		depthMin = 140, depthMax = 170, hp = 480, timer = 50, gold = 600, swimSpeed = 50, size = 60,
		move = { speed = 190, keepAway = 170, restless = 0.6 },
		slip = { recovery = 1.5, dart = 280 },
		special = { kind = "shot", damage = 10, tell = 0.7, cooldown = 4.5, speed = 420, pattern = { "high", "low", "high" }, gap = 0.5 },
		gimmick = "ink",
		taunts = { "TECHNICALLY NOT A FISH!", "INK ABOUT YOUR LIFE CHOICES.", "I AM ARMED. EIGHT TIMES." },
	},
}

M.hardMode = { hpMult = 1.5, damageMult = 1.5, contactDamage = 5, contactCooldown = 1 }

M.tiers = { depth = 170, hpMult = 2.2, goldMult = 2.5, prefixes = { "", "ELDER", "SENSEI", "SHOGUN", "YOKAI", "KAMI" } }

M.samurai = { maxHp = 100, quickDamage = 6, heavyDamage = 18 }

M.fight = {
	arena = { left = 60, right = 900, floorY = 440 },
	samurai = {
		walkSpeed = 260,
		touchWalkScale = 1.5,
		bodyRadius = 30,
		quick = { startup = 0.06, active = 0.08, recovery = 0.14, reach = 185 },
		heavy = { startup = 0.45, active = 0.1, recovery = 0.3, reach = 215 },
		blockReduction = 0.65,
		dash = { distance = 170, duration = 0.18, iframes = 0.22, cooldown = 0.5, crouchMinX = 0.65 },
		hurtStun = 0.25,
		hurtKnockback = 240,
		blockPush = 120,
		buffer = 0.12,
		jump = { speed = 690, gravity = 1980, airSpeed = 220 },
		standHeight = 120,
		crouchHeight = 60,
	},
	fish = {
		slipDuration = 0.3,
		slipArc = 50,
		overArc = 170,
		hitHeight = 150,
		hitStun = 0.12,
		hitPush = 180,
		lungeDuration = 0.2,
		lungeRecovery = 0.8,
		crossCooldown = 1.2,
		puff = { every = 4.5, duration = 1.6, knockback = 260, stun = 0.5 },
		ink = { every = 6, duration = 3 },
		darkRadius = 150,
		contactReach = 6,
		special = {
			minDist = 120,
			aimDist = 260,
			clearScale = 1.3,
			chargeRecovery = 1.4,
			shootRecovery = 0.3,
			lungeDelay = 0.8,
			projectile = { low = { y = 18, r = 18 }, high = { y = 112, r = 14 } },
		},
	},
	hitStop = 0.06,
	introDelay = 1.0,
}

M.ocean = {
	startDepth = 135,
	pxPerMetre = 14,
	surfaceY = 150,
	hook = { sinkSpeed = 150, fastSinkSpeed = 300, brakeSpeed = 60, reelSpeed = 260, steerSpeed = 260, radius = 12, touchSteerMaxSpeed = 1200 },
	fishPerScreen = 8,
	catchRadiusScale = 0.8,
	layout = {
		fishTopM = 3, fishBeyondPx = 200, fishMinGapPx = 40, fishSpeedVariation = 0.2, fishBobPx = 5,
		fishWrapMargin = 30, unreachableAlpha = 0.35, hookAnchorY = 255, cameraLerp = 8, hookSteerMargin = 16,
		boatX = 380, boatBobPx = 3, rodDx = 100, rodDy = -84, hookIdleDy = -22, bubbleCount = 22,
		gaugeX = 898, gaugeLaneW = 10, gaugeLanes = 3, sunX = 660, sunR = 46, seaBand = 36, islandX = 64,
	},
}

M.cutscene = { duration = 2.5, inputLock = 0.2, slide = 0.45 }
M.result = { lock = 0.5, auto = 5, goldAt = 1.2, countTime = 0.8, dropAt = 0.3 }
M.demoStart = { gold = 1500, levels = { damage = 4, depth = 6, gold = 2 } }

M.upgrades = {
	{
		id = "damage", label = "BLADE", baseCost = 20, growth = 1.5, perLevel = 0.25,
		names = {
			"Rusty Katana", "Slightly Less Rusty Katana", "Katana (Washed)", "Sharp Katana",
			"Very Sharp Katana", "Katana of Mild Peril", "Fishbane", "Fishbane II: The Refishening",
			"Legendary Sashimi Knife", "Blade of a Thousand Fillets",
		},
	},
	{
		id = "depth", label = "LINE", baseCost = 30, growth = 1.45, perLevel = 15,
		names = {
			"Old String", "Longer String", "Actual Fishing Line", "Rope", "Long Rope",
			"Suspiciously Long Rope", "Anchor Chain", "Abyssal Cable", "The Bottomless Line",
		},
	},
	{
		id = "gold", label = "REPUTATION", baseCost = 40, growth = 1.6, perLevel = 0.15,
		names = {
			"Unknown Angler", "Local Nuisance", "Market Regular", "Sushi Supplier",
			"Feared By Fishmongers", "Sashimi Tycoon", "Shogun's Fishmonger", "Legend of the Seven Seas",
		},
	},
}

-- Sprite draw sizes (game px) and placeholder colours; images come from Assets.luau.
M.sprites = {
	samuraiIdle = { w = 456, h = 173, frames = 8, fps = 8, color = "#c0392b" },
	samuraiWalk = { w = 456, h = 173, frames = 8, fps = 12, color = "#c0392b" },
	samuraiQuick = { w = 456, h = 173, frames = 6, fps = 18, color = "#e74c3c", label = "SLASH" },
	samuraiHeavy = { w = 456, h = 173, frames = 6, fps = 10, color = "#f39c12", label = "HEAVY" },
	samuraiBlock = { w = 456, h = 173, frames = 1, fps = 8, color = "#7f8c8d", label = "BLOCK" },
	samuraiHurt = { w = 456, h = 173, frames = 4, fps = 12, color = "#ffffff", label = "OW" },
	samuraiJump = { w = 456, h = 173, frames = 2, fps = 10, color = "#c0392b", label = "JUMP" },
	samuraiFall = { w = 456, h = 173, frames = 2, fps = 10, color = "#c0392b", label = "FALL" },
	samuraiCrouch = { w = 456, h = 173, frames = 8, fps = 8, color = "#c0392b", label = "DUCK" },
	samuraiSit = { w = 266, h = 101, frames = 8, fps = 4, color = "#c0392b", sheet = "samuraiIdle" },
	-- 280x110 hull drawn with 8 px padding (roblox/tools/make-upload.mjs), so the image is 296x126.
	boat = { w = 296, h = 126, frames = 1, fps = 8, color = "#7a4a26" },
	hook = { w = 20, h = 28, frames = 1, fps = 8, color = "#dfe6e9" },
	nigiri = { w = 72, h = 48, frames = 1, fps = 8, color = "#ff8c5a" },
	["fish.sardine"] = { w = 56, h = 32, frames = 1, fps = 8, color = "#b8c6d1", label = "SARDINE", facing = "left" },
	["fish.mackerel"] = { w = 78, h = 42, frames = 1, fps = 8, color = "#4f8fba", label = "MACKEREL", facing = "left" },
	["fish.piranha"] = { w = 70, h = 60, frames = 1, fps = 8, color = "#d35454", label = "PIRANHA", facing = "left" },
	["fish.eel"] = { w = 144, h = 40, frames = 1, fps = 8, color = "#6b8e23", label = "EEL", facing = "left" },
	["fish.pufferfish"] = { w = 81, h = 69, frames = 1, fps = 8, color = "#e6c34a", label = "PUFFER", facing = "right" },
	["fish.swordfish"] = { w = 150, h = 56, frames = 1, fps = 8, color = "#5d6d9e", label = "SWORDFISH", facing = "left" },
	["fish.anglerfish"] = { w = 110, h = 88, frames = 1, fps = 8, color = "#5b3a6b", label = "ANGLER", facing = "left" },
	["fish.shark"] = { w = 188, h = 60, frames = 1, fps = 8, color = "#7d8a97", label = "SHARK", facing = "left" },
	["fish.squid"] = { w = 140, h = 118, frames = 1, fps = 8, color = "#c0567a", label = "SQUID", facing = "left" },
}

M.text = {
	title = "SAMURAI HOOK",
	cutscene = { round = "ROUND {round}!", versus = "SAMURAI  VS  {fish}", fight = "FIGHT!" },
	samuraiLines = {
		"A WORTHY OPPONENT.", "DRAW YOUR FINS.", "TODAY, ONE OF US BECOMES SUSHI.",
		"I HAVE TRAINED 40 YEARS FOR THIS SARDINE.", "HONOUR DEMANDS A FILLET.",
	},
	slip = { "SLIPPED!", "TOO SLIPPERY!", "WHIFF!", "NOPE!" },
	hit = { "HIT!", "SLICE!", "FILLET!" },
	heavyHit = { "KATANA SMASH!", "DISHONOUR CUTTER!", "MEGA FILLET!" },
	block = "BLOCKED!",
	bounce = "BOING!",
	dodged = "DODGED!",
	puff = "PUFF!",
	samurai = { label = "SAMURAI", safeSub = "CANNOT BE HARMED BY THIS FISH" },
	win = { banner = "K.O.!", perfect = "PERFECT!", sold = "SOLD TO SUSHI-YA: {gold} RYO" },
	timeout = { banner = "TIME!", sub = "IT WAS... TOO SLIPPERY." },
	ko = { banner = "YOU GOT BITTEN.", sub = "{fish} SWIMS AWAY, UNDEFEATED." },
	shop = { title = "MINATO DOJO SHOP", broke = "NOT ENOUGH RYO", gold = "{gold} RYO" },
	-- Shown from the settings panel. The two CC-BY lines are required by their licences (see CREDITS.md).
	credits = {
		"Pufferfish by TeamAlpha, OpenGameArt (CC-BY 3.0)",
		"\"Fight\" announcer voice by Alba MacKenna (CC-BY 4.0)",
		"",
		"Samurai: Martial Hero by LuizMelo (CC0)",
		"Fish: Fish DB32 by ARoachIFoundOnMyPillow (CC0)",
		"Squid by Shozuki (CC0)",
		"Announcer: Kenney Voiceover Pack Fighter (CC0)",
		"Sound effects: StarNinjas, artisticdude, rubberduck,",
		"Luke.RUSTLTD, Kenney (all CC0)",
		"Music: Wolfgang_ (8-Bit Battle Loop), Kistol (Hot Springs Town) (CC0)",
	},
}

--- "{round}" style templates, like fill() in src/ui/hud.ts.
function M.fill(template: string, vars: { [string]: any }): string
	return (string.gsub(template, "{(%w+)}", function(k)
		local v = vars[k]
		return if v ~= nil then tostring(v) else nil
	end))
end

return M
