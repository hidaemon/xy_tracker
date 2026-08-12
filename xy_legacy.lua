local addonName, addon = ...
addon = addon or xy or NewXYTrack

-- 老协议全部隔离在本文件中，后续删除兼容功能时只需移除本文件及 TOC 条目。
local Legacy = {}
addon.Legacy = Legacy

Legacy.prefix = "XY_COMMAND"
Legacy.initPrefix = "XY_INITDKP"
Legacy.resetPrefix = "XY_RESET"
Legacy.syncPrefix = "XY_SYNC"
Legacy.changeDkpPrefix = "XY_COMMAND_CHDKP"
Legacy.prefixes = {
    Legacy.prefix,
    Legacy.initPrefix,
    Legacy.resetPrefix,
    Legacy.syncPrefix,
    Legacy.changeDkpPrefix,
}

local registerPrefix = RegisterAddonMessagePrefix
if type(registerPrefix) ~= "function" and C_ChatInfo then
    registerPrefix = C_ChatInfo.RegisterAddonMessagePrefix
end

local function parseRecord(message)
    local fields = {}
    for field in string.gmatch(message or "", "([^,]+)") do
        local key, value = string.match(field, "^([^=]+)=(.*)$")
        if key then fields[key] = value end
    end
    if not fields.p or fields.p == "" then return nil end
    return {
        name = fields.p,
        class = fields.c or "未知职业",
        xy = fields.x or addon.unwished,
        dkp = tonumber(fields.s) or DefaultDKP,
        finish = tonumber(fields.f) or 0,
    }
end

function Legacy:RegisterPrefixes()
    if type(registerPrefix) ~= "function" then return false end
    local i
    for i = 1, #self.prefixes do
        pcall(registerPrefix, self.prefixes[i])
    end
    return true
end

function Legacy:IsPrefix(prefix)
    local i
    for i = 1, #self.prefixes do
        if prefix == self.prefixes[i] then return true end
    end
    return false
end

function Legacy:Queue(prefix, message, channel, target)
    return addon:QueueAddonMessage(prefix, message, channel or "RAID", target)
end

function Legacy:RecordMessage(record)
    record = addon:NormalizeRecord(record)
    return string.format("p=%s,c=%s,x=%s,s=%d,f=%d",
        record.name, record.class, record.xy, record.dkp, record.finish)
end

function Legacy:SendRecord(record, target)
    local channel = target and "WHISPER" or "RAID"
    return self:Queue(self.prefix, self:RecordMessage(record), channel, target)
end

function Legacy:SendSnapshot(target)
    if not addon:IsOperator() then return false end
    local i
    for i = 1, #XyArray do
        self:SendRecord(XyArray[i], target)
    end
    return true
end

function Legacy:SendInitDKP(value)
    return self:Queue(self.initPrefix, "d=" .. tostring(value), "RAID")
end

function Legacy:SendReset(value)
    return self:Queue(self.resetPrefix, tostring(value), "RAID")
end

function Legacy:RequestSnapshot()
    -- 老协议没有 HELLO/请求响应机制，只能等待管理者下一次广播。
    addon:Print("已切换老协议，等待管理者下一次同步数据。")
    return false
end

function Legacy:ApplyRecord(data, sender)
    if not data or not addon:IsAuthoritySender(sender) then return end
    addon:UpsertRecord(data)
    if addon.UI then addon.UI:Update() end
end

function Legacy:ApplyInitDKP(message, sender)
    if not addon:IsAuthoritySender(sender) then return end
    local value = tonumber(string.match(message or "", "d=(%d+)"))
    if not value then return end
    DefaultDKP = value
    local i
    for i = 1, #XyArray do XyArray[i].dkp = value end
    if addon.UI then addon.UI:Update() end
end

function Legacy:ApplyReset(message, sender)
    if not addon:IsAuthoritySender(sender) then return end
    addon:SaveResetSnapshot()
    DefaultDKP = tonumber(message) or DefaultDKP
    if addon.RefreshRoster then addon:RefreshRoster(false) end
    local i
    for i = 1, #XyArray do
        XyArray[i].dkp = DefaultDKP
        XyArray[i].xy = addon.unwished
        XyArray[i].finish = 0
    end
    addon.running = false
    XyInProgress = false
    if addon.UI then addon.UI:Update() end
end

function Legacy:Process(prefix, message, sender)
    if addon.protocolMode ~= "legacy" then return end
    if prefix == self.prefix then
        local record = parseRecord(message)
        if record then self:ApplyRecord(record, sender) end
    elseif prefix == self.syncPrefix then
        local part
        for part in string.gmatch(message or "", "([^;]+)") do
            local record = parseRecord(part)
            if record then self:ApplyRecord(record, sender) end
        end
    elseif prefix == self.initPrefix then
        self:ApplyInitDKP(message, sender)
    elseif prefix == self.resetPrefix then
        self:ApplyReset(message, sender)
    end
end
