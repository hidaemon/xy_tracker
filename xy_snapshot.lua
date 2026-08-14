local addonName, addon = ...
addon = addon or xy or NewXYTrack

-- 新协议全量同步模块：只编排第三方库，不实现自有压缩、编码或分片算法。
-- LibSerialize -> LibDeflate -> Chomp；Chomp 内部使用 ChatThrottleLib 节流并分片。
local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
local Chomp = LibStub and LibStub:GetLibrary("Chomp", true)

local Snapshot = {}
addon.Snapshot = Snapshot
Snapshot.prefix = addon.snapshotPrefix or "XYTRK2S"
Snapshot.sequence = 0
Snapshot.available = LibSerialize and LibDeflate and Chomp and true or false

local function numeric(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function buildRecord(record)
    record = addon:NormalizeRecord(record)
    return {
        name = record.name,
        class = record.class,
        xy = record.xy,
        dkp = record.dkp,
        finish = record.finish,
    }
end

function Snapshot:BuildData()
    local records = {}
    local i
    for i = 1, #XyArray do
        records[i] = buildRecord(XyArray[i])
    end
    return {
        protocol = addon.protocolVersion or 3,
        defaultDKP = numeric(DefaultDKP, 4),
        running = addon.running and 1 or 0,
        records = records,
    }
end

function Snapshot:Encode(data)
    if not self.available then return nil end
    local serialized = LibSerialize:Serialize(data)
    if not serialized then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then return nil end
    return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

function Snapshot:Decode(encoded)
    if not self.available or type(encoded) ~= "string" then return nil end
    local compressed = LibDeflate:DecodeForWoWAddonChannel(encoded)
    if not compressed then return nil end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local success, data = LibSerialize:Deserialize(serialized)
    if not success or type(data) ~= "table" then return nil end
    return data
end

function Snapshot:Validate(data)
    if type(data) ~= "table" or numeric(data.protocol, 0) < (addon.protocolVersion or 3) or
       type(data.records) ~= "table" then
        return nil
    end

    local records = {}
    local i
    for i = 1, #data.records do
        local source = data.records[i]
        if type(source) ~= "table" or type(source.name) ~= "string" or source.name == "" then
            return nil
        end
        records[i] = addon:NormalizeRecord({
            name = source.name,
            class = source.class,
            xy = source.xy,
            dkp = source.dkp,
            finish = source.finish,
        })
    end
    return records, numeric(data.defaultDKP, DefaultDKP), numeric(data.running, 0) == 1
end

function Snapshot:Send(target)
    if addon.isLoggingOut then return false end
    if not self.available then
        addon:Print("新协议依赖库未加载，无法发送全量许愿表。")
        return false
    end

    self.sequence = self.sequence + 1
    local encoded = self:Encode(self:BuildData())
    if not encoded then
        addon:Print("许愿表序列化或压缩失败，未发送全量同步。")
        return false
    end

    local channel = target and "WHISPER" or "RAID"
    local ok, result = pcall(Chomp.SmartAddonMessage, self.prefix, encoded,
        channel, target, {
            serialize = false,
            binaryBlob = true,
            priority = "LOW",
            queue = "XYTRK2-SNAPSHOT",
        })
    if not ok then
        addon:Print("Chomp 全量同步发送失败：" .. tostring(result))
        return false
    end
    return result ~= false
end

function Snapshot:ReceiveEncoded(data, sender)
    if addon.isLoggingOut then return false end
    if not addon:IsAuthoritySender(sender) then return false end
    local decoded = self:Decode(data)
    local records, defaultDKP, running = self:Validate(decoded)
    if not records then
        addon:Print("新协议全量同步校验失败，已忽略本次数据。")
        return false
    end

    DefaultDKP = defaultDKP
    addon.running = running
    XyInProgress = running
    XyArray = records
    addon.records = XyArray
    if addon.UI then addon.UI:Update() end
    return true
end

if Snapshot.available and not Chomp.IsAddonPrefixRegistered(Snapshot.prefix) then
    Chomp.RegisterAddonPrefix(Snapshot.prefix, function(_, data, _, sender)
        return Snapshot:ReceiveEncoded(data, sender)
    end, {
        fullMsgOnly = true,
        validTypes = {string = true},
    })
end
