-- Zompa game SDK v1. This module also runs in desktop LÖVE for development.
local sdk = {version = 1}
local slots = "zompado-saves"

local function savePath(slot)
    assert(type(slot) == "string" and #slot <= 32 and slot:match("^[a-z0-9][a-z0-9_-]*$"),
        "Use a save slot name with 1 to 32 lowercase letters, digits, underscores, or hyphens.")
    return slots .. "/" .. slot
end

-- The game owns serialization. Keep saved data small and version the format.
function sdk.save(slot, data)
    local path = savePath(slot)
    assert(type(data) == "string" and #data <= 262144, "Save data must fit in 256 KiB.")
    if not love.filesystem.createDirectory(slots) then
        return false, "Could not create the save directory."
    end
    return love.filesystem.write(path, data)
end

function sdk.load(slot)
    local path = savePath(slot)
    if not love.filesystem.getInfo(path, "file") then return nil end
    return love.filesystem.read(path, 262144)
end

function sdk.audio()
    local gains = {music = 1, effects = 1}
    local hostGains = {music = 1, effects = 1}
    local hostSettings, elapsed = nil, 0
    local sources = setmetatable({}, {__mode = "k"})
    local muted = false
    local mixer = {}

    local function apply(source, settings)
        source:setVolume(muted and 0 or gains[settings.bus] * hostGains[settings.bus] * settings.volume)
    end

    function mixer:update(dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        local file = io.open("/zompado/audio", "r")
        if not file then return end
        local settings = file:read(8)
        file:close()
        if not settings or settings == hostSettings then return end
        local music, effects = settings:match("^(%d%d?%d?):(%d%d?%d?)$")
        if not music or tonumber(music) > 100 or tonumber(effects) > 100 then return end
        hostSettings = settings
        hostGains.music, hostGains.effects = tonumber(music) / 100, tonumber(effects) / 100
        for source, sourceSettings in pairs(sources) do apply(source, sourceSettings) end
    end

    function mixer:register(source, bus)
        self:update(0.2)
        assert(gains[bus] ~= nil, "Choose the music or effects bus.")
        assert(not sources[source], "This source is already registered.")
        sources[source] = {bus = bus, volume = source:getVolume()}
        apply(source, sources[source])
        return source
    end

    function mixer:setGain(bus, gain)
        assert(gains[bus] ~= nil, "Choose the music or effects bus.")
        assert(type(gain) == "number" and gain >= 0 and gain <= 1, "Gain must be between 0 and 1.")
        gains[bus] = gain
        for source, settings in pairs(sources) do
            if settings.bus == bus then apply(source, settings) end
        end
    end

    function mixer:setMuted(value)
        muted = not not value
        for source, settings in pairs(sources) do apply(source, settings) end
    end

    return mixer
end

return sdk
