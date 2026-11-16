local _, MHT = ...
local CopyString = {}
MHT.CopyString = CopyString
local Plan, Rotation = MHT.Plan, MHT.Rotation
local finite = MHT.Util.Finite

CopyString.GAME, CopyString.VERSION = "wow", 1

local DAMAGED = "The copy string is incomplete or damaged."
local COLORS = { any = true, same = true, none = true }

local function number(text)
    local value = tonumber(text)
    if finite(value) then return value end
end

local function triple(text)
    local a, b, c = (text or ""):match("^([^,]+),([^,]+),([^,]+)$")
    a, b, c = number(a), number(b), number(c)
    if a and b and c then return a, b, c end
end

local function decode(packed)
    local ok, text = pcall(function()
        return C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(packed), Enum.CompressionMethod.Zlib)
    end)
    if ok and type(text) == "string" then return text end
end

function CopyString.Unpack(text)
    if type(text) ~= "string" or not text:find("%S") then return nil, "Paste a copy string." end
    text = text:match("^%s*(.-)%s*$")
    local packed = text:match("^mouse:(.*)$")
    if packed then text = decode(packed) end
    local game, version, body = (text or ""):match("^(%a+):(%d+)%s*/(.*)$")
    if not game then return nil, DAMAGED end
    if game ~= CopyString.GAME then return nil, "This copy string is for another game (" .. game .. ")." end
    if tonumber(version) > CopyString.VERSION then return nil, "This copy string needs a newer version of the addon." end
    return body
end

local function readInstance(entry)
    local tokens = {}
    for token in entry:gmatch("%S+") do tokens[#tokens + 1] = token end
    local x, y, z = triple(tokens[1])
    if not x then return nil end
    local instance = { x = x, y = y, z = z, turn = { x = 0, y = 0, z = 0 }, scale = 1, color = "same" }
    for i = 2, #tokens do
        local token, tag = tokens[i], tokens[i]:sub(1, 1)
        if COLORS[token] then
            instance.color = token
        elseif tag == "r" then
            local a, b, c = triple(token:sub(2))
            if not a then return nil end
            instance.turn = { x = a, y = b, z = c }
        elseif tag == "s" then
            instance.scale = number(token:sub(2))
            if not instance.scale then return nil end
        else
            return nil
        end
    end
    return instance
end

-- The item ID and its instances.
function CopyString.Parse(body)
    local item, list = body:match("^%s*id=(%d+):(.*)$")
    if not item then return nil, DAMAGED end
    local model = { item = tonumber(item), instances = {} }
    for entry in (list .. ";"):gmatch("([^;]*);") do
        if entry:find("%S") then
            local instance = readInstance(entry)
            if not instance then return nil, DAMAGED end
            model.instances[#model.instances + 1] = instance
        end
    end
    return model
end

function CopyString.Read(text)
    local body, reason = CopyString.Unpack(text)
    if not body then return nil, reason end
    return CopyString.Parse(body)
end

-- Items without a logged size are previewed and built with the default tile.
function CopyString.Plan(model)
    local Profiles = MHT.ItemProfiles
    local decorID = model.item
    local dimensions = Profiles.Dimensions(decorID)
    if not dimensions then
        decorID = Profiles.DEFAULT_DECOR_ID
        dimensions = Profiles.Dimensions(decorID)
    end
    local items = {}
    for i, entry in ipairs(model.instances) do
        local turn = entry.turn
        items[i] = Plan.Placement(entry.x, entry.y, entry.z,
            Rotation.FromPitchRollYaw(turn.x, turn.y, turn.z), entry.scale)
        items[i].color = entry.color
    end
    local plan = Plan.New(items, dimensions)
    plan.requires = decorID
    plan.source = Plan.Placement(0, 0, 0, Rotation.Identity(), 1)
    return plan
end
