-- Sound effects, looping music and announcer clips from Assets.luau. Missing IDs stay silent.
-- No speech synthesis in Roblox: an announcer line without a clip is just not spoken (the text is on screen).
local SoundService = game:GetService("SoundService")
local Assets = require(game:GetService("ReplicatedStorage"):WaitForChild("SamuraiHook"):WaitForChild("Assets"))

local Audio = {}

function Audio.new()
	local self = { musicVolume = 0.8, sfxVolume = 0.8 }
	local folder = Instance.new("Folder")
	folder.Name = "SamuraiHookAudio"
	folder.Parent = SoundService

	local sfx: { [string]: Sound } = {}
	for name, def in Assets.sounds do
		if def.id ~= "" then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = def.id
			s.Parent = folder
			sfx[name] = s
		end
	end

	local musicSound = Instance.new("Sound")
	musicSound.Name = "Music"
	musicSound.Looped = true
	musicSound.Parent = folder
	local musicId: string? = nil

	local voiceSound = Instance.new("Sound")
	voiceSound.Name = "Announcer"
	voiceSound.Parent = folder

	function self.play(id: string)
		local s = sfx[id]
		if not s or self.sfxVolume <= 0 then
			return
		end
		s.Volume = Assets.sounds[id].volume * self.sfxVolume * 2
		SoundService:PlayLocalSound(s) -- one-shot, may overlap itself
	end

	function self.music(id: string?)
		if id == musicId then
			return
		end
		musicId = id
		local def = id and Assets.music[id]
		musicSound:Stop()
		if def and def.id ~= "" then
			musicSound.SoundId = def.id
			musicSound.TimePosition = 0
			self.applyMusicVolume()
			musicSound:Play()
		end
	end

	function self.applyMusicVolume()
		local def = musicId and Assets.music[musicId]
		musicSound.Volume = if def then def.volume * self.musicVolume * 2 else 0
	end

	function self.pauseMusic(paused: boolean)
		if paused then
			musicSound:Pause()
		elseif musicId and musicSound.SoundId ~= "" then
			musicSound:Resume()
		end
	end

	--- key: fight | win | perfect | timeout | ko | round (round N looks up roundN first).
	function self.announce(key: string, round: number?)
		local id = ""
		if key == "round" and round then
			id = Assets.voice["round" .. round] or ""
		end
		if id == "" then
			id = Assets.voice[key] or ""
		end
		if id == "" or self.sfxVolume <= 0 then
			return
		end
		voiceSound:Stop()
		voiceSound.SoundId = id
		voiceSound.Volume = self.sfxVolume * 2
		voiceSound:Play()
	end

	return self
end

return Audio
