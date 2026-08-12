local addonName, addon = ...
addon = addon or {}

-- 公共命名空间。所有文件都通过同一个 addon 表协作。
xy = addon
NewXYTrack = addon

local PREFIX = "XYTRK2"
local SNAPSHOT_PREFIX = "XYTRK2S"
local PROTOCOL_VERSION = 3
local UNWISHED = "---未许愿---"
-- 小型控制消息保留安全余量；全量数据由 Chomp 内部负责分片。
local QUEUE_DELAY = 1.00
local MAX_MESSAGE_LENGTH = 240
local PROTOCOL_NEGOTIATION_TIMEOUT = 1.50

-- 69110 客户端使用 C_ChatInfo；部分 TBC 客户端使用旧版全局函数。
-- 运行时选择实际存在的 API，避免在初始化阶段直接调用 nil。
local registerAddonMessagePrefix = RegisterAddonMessagePrefix
local sendAddonMessage = SendAddonMessage
local sendChatMessage = SendChatMessage
if type(registerAddonMessagePrefix) ~= "function" and C_ChatInfo then
    registerAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix
end
if type(sendAddonMessage) ~= "function" and C_ChatInfo then
    sendAddonMessage = C_ChatInfo.SendAddonMessage
end
if type(sendChatMessage) ~= "function" and C_ChatInfo then
    sendChatMessage = C_ChatInfo.SendChatMessage
end

addon.name = addonName
addon.prefix = PREFIX
addon.snapshotPrefix = SNAPSHOT_PREFIX
addon.protocolVersion = PROTOCOL_VERSION
addon.AceComm = LibStub and LibStub:GetLibrary("AceComm-3.0", true)
addon.unwished = UNWISHED
addon.records = {}
addon.txQueue = {}
addon.txElapsed = 0
addon.running = false
addon.rollData = {}
addon.rollResults = {}
addon.rollTracking = false
addon.rollCountingDown = false
addon.rollCountdown = 0
addon.rollCountdownElapsed = 0
addon.rollFinalDelay = 0
addon.rollFinalText = nil
addon.rollMessageQueue = {}
addon.rollMessageElapsed = 0
addon.rollRepeat = false
addon.rollChannelID = 2
addon.isInitialized = false
addon.authorityName = nil
addon.receivingSession = nil
addon.receivingCount = 0
addon.receivingIndex = 0
addon.receivingSeen = {}
addon.receivingReceived = 0
addon.protocolMode = "new"
addon.protocolConfirmed = false
addon.protocolNegotiating = false
addon.protocolNewSeen = false
addon.protocolElapsed = 0
addon.lastRemoteResetToken = nil

local function trim(value)
    if value == nil then return "" end
    value = tostring(value)
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function shortName(name)
    name = trim(name)
    local dash = string.find(name, "-", 1, true)
    if dash then
        return string.sub(name, 1, dash - 1)
    end
    return name
end

local function sameName(left, right)
    return string.lower(shortName(left)) == string.lower(shortName(right))
end

local function numeric(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function escapeField(value)
    value = tostring(value or "")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, "|", "\\p")
    value = string.gsub(value, "\r", "\\r")
    value = string.gsub(value, "\n", "\\n")
    return value
end

local function unescapeField(value)
    local result = {}
    local escaped = false
    local i
    for i = 1, #value do
        local char = string.sub(value, i, i)
        if escaped then
            if char == "p" then
                table.insert(result, "|")
            elseif char == "n" then
                table.insert(result, "\n")
            elseif char == "r" then
                table.insert(result, "\r")
            else
                table.insert(result, char)
            end
            escaped = false
        elseif char == "\\" then
            escaped = true
        else
            table.insert(result, char)
        end
    end
    if escaped then table.insert(result, "\\") end
    return table.concat(result)
end

local function splitPacket(message)
    local fields = {}
    local buffer = {}
    local escaped = false
    local i
    for i = 1, #message do
        local char = string.sub(message, i, i)
        if escaped then
            table.insert(buffer, "\\")
            table.insert(buffer, char)
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "|" then
            table.insert(fields, unescapeField(table.concat(buffer)))
            buffer = {}
        else
            table.insert(buffer, char)
        end
    end
    if escaped then table.insert(buffer, "\\") end
    table.insert(fields, unescapeField(table.concat(buffer)))
    return fields
end

local function packet(command, ...)
    local fields = {command}
    local values = {...}
    local i
    for i = 1, #values do
        table.insert(fields, escapeField(values[i]))
    end
    return table.concat(fields, "|")
end

-- 压缩快照模块使用该协议编码器；其他新协议仍由本文件维护。
addon.MakePacket = packet
addon.SplitPacket = splitPacket

local function teamChannel()
    local raid = type(IsInRaid) == "function" and IsInRaid()
    if not raid and type(GetNumRaidMembers) == "function" then
        raid = (tonumber(GetNumRaidMembers()) or 0) > 0
    end
    if raid then return "RAID" end

    local group = type(IsInGroup) == "function" and IsInGroup()
    if not group and type(GetNumPartyMembers) == "function" then
        group = (tonumber(GetNumPartyMembers()) or 0) > 0
    end
    if not group and type(GetNumSubgroupMembers) == "function" then
        group = (tonumber(GetNumSubgroupMembers()) or 0) > 0
    end
    if group then return "PARTY" end
    return nil
end

local function registerEventSafe(frame, event)
    -- 69110 不提供 PARTY_MEMBERS_CHANGED；不同客户端的团队事件名称不同。
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

local function playerName()
    return shortName(UnitName("player"))
end

function addon:Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00aaff[许愿监视]|r " .. tostring(message))
    else
        print("[许愿监视] " .. tostring(message))
    end
end

function addon:ClassColor(class)
    local colors = {
        ["战士"] = "ffc79c6e", ["萨满祭司"] = "ff0070de", ["萨满"] = "ff0070de",
        ["德鲁伊"] = "ffff7d0a", ["潜行者"] = "fffff569", ["盗贼"] = "fffff569",
        ["法师"] = "ff69ccf0", ["圣骑士"] = "fff58cba", ["牧师"] = "ffffffff",
        ["术士"] = "ff9482c9", ["猎人"] = "ffabd473",
        ["WARRIOR"] = "ffc79c6e", ["SHAMAN"] = "ff0070de", ["DRUID"] = "ffff7d0a",
        ["ROGUE"] = "fffff569", ["MAGE"] = "ff69ccf0", ["PALADIN"] = "fff58cba",
        ["PRIEST"] = "ffffffff", ["WARLOCK"] = "ff9482c9", ["HUNTER"] = "ffabd473",
    }
    return colors[class] or "ffffffff"
end

function addon:NormalizeRecord(record)
    record = record or {}
    record.name = trim(record.name)
    record.class = trim(record.class)
    record.dkp = numeric(record.dkp, numeric(DefaultDKP, 4))
    record.xy = trim(record.xy)
    if record.xy == "" then record.xy = UNWISHED end
    record.finish = numeric(record.finish, 0) == 1 and 1 or 0
    return record
end

function addon:NormalizeDatabase()
    XyArray = XyArray or {}
    XyWishHistory = XyWishHistory or {}
    XyResetHistory = XyResetHistory or {}
    XyRollSettings = XyRollSettings or {}
    XyTradeHistory = XyTradeHistory or {}
    XyForceNewProtocol = numeric(XyForceNewProtocol, 0)
    XyMinimapAngle = numeric(XyMinimapAngle, 0)
    DefaultDKP = numeric(DefaultDKP, 4)
    XyOnlyMode = numeric(XyOnlyMode, 1)
    self.rollRepeat = XyRollSettings.repeatRoll == 1
    self.rollChannelID = numeric(XyRollSettings.channelID, 2)
    self.protocolMode = "new"
    self.protocolConfirmed = XyForceNewProtocol == 1
    local clean = {}
    local seen = {}
    local i
    for i = 1, #XyArray do
        local record = self:NormalizeRecord(XyArray[i])
        if record.name ~= "" then
            local key = string.lower(shortName(record.name))
            if not seen[key] then
                seen[key] = true
                table.insert(clean, record)
            end
        end
    end
    XyArray = clean
    self.records = XyArray

    local history = {}
    for i = 1, #XyWishHistory do
        local entry = XyWishHistory[i] or {}
        entry.name = shortName(entry.name)
        entry.class = trim(entry.class)
        entry.xy = trim(entry.xy)
        entry.time = trim(entry.time)
        entry.finish = numeric(entry.finish, 0) == 1 and 1 or 0
        if entry.name ~= "" and entry.xy ~= "" then
            table.insert(history, entry)
        end
    end
    XyWishHistory = history

    local resetHistory = {}
    for i = 1, #XyResetHistory do
        local snapshot = XyResetHistory[i] or {}
        local records = {}
        local source = snapshot.records or snapshot.wishes or {}
        for j = 1, #source do
            local record = self:NormalizeRecord({
                name = source[j] and source[j].name,
                class = source[j] and source[j].class,
                xy = source[j] and source[j].xy,
                dkp = source[j] and source[j].dkp,
                finish = source[j] and source[j].finish,
            })
            if record.name ~= "" then
                table.insert(records, record)
            end
        end
        snapshot.time = trim(snapshot.time)
        if snapshot.time ~= "" then
            snapshot.records = records
            snapshot.wishes = nil
            table.insert(resetHistory, snapshot)
        end
    end
    XyResetHistory = resetHistory
end

function addon:FindRecord(name)
    name = shortName(name)
    local i
    for i = 1, #XyArray do
        if XyArray[i] and sameName(XyArray[i].name, name) then
            return XyArray[i], i
        end
    end
    return nil
end

function addon:UpsertRecord(data)
    local record = self:NormalizeRecord(data)
    if record.name == "" then return nil end
    local existing = self:FindRecord(record.name)
    if existing then
        existing.name = record.name
        existing.class = record.class ~= "" and record.class or existing.class
        existing.xy = record.xy
        existing.dkp = record.dkp
        existing.finish = record.finish
        return existing
    end
    table.insert(XyArray, record)
    return record
end

function addon:CreateRecord(name, class)
    local record = self:FindRecord(name)
    if record then return record end
    record = self:NormalizeRecord({
        name = shortName(name),
        class = class or "未知职业",
        dkp = DefaultDKP,
        xy = UNWISHED,
        finish = 0,
    })
    table.insert(XyArray, record)
    return record
end

-- 仅用于界面和分页测试。使用真实记录字段，不发送任何团队通讯。
function addon:CreateTestData()
    local classes = {
        "战士", "圣骑士", "猎人", "盗贼", "牧师",
        "萨满祭司", "法师", "术士", "德鲁伊",
    }
    local i
    for i = 1, 25 do
        local wished = i % 5 ~= 0
        self:UpsertRecord({
            name = string.format("测试角色%02d", i),
            class = classes[((i - 1) % #classes) + 1],
            xy = wished and string.format("测试许愿%02d", i) or UNWISHED,
            dkp = 4 + ((i - 1) % 9) * 5,
            finish = wished and (i % 7 == 0 and 1 or 0) or 0,
        })
    end
    self.records = XyArray
    if self.UI and self.UI.Update then self.UI:Update() end
    self:Print("已添加25条测试记录（不会发送通讯）")
end

function addon:AddWishHistory(record)
    if not record then return end
    XyWishHistory = XyWishHistory or {}
    table.insert(XyWishHistory, 1, {
        name = record.name,
        class = record.class,
        xy = record.xy,
        time = date("%m-%d %H:%M"),
        finish = 0,
    })
    while #XyWishHistory > 200 do
        table.remove(XyWishHistory)
    end
end

function addon:SaveResetSnapshot()
    XyResetHistory = XyResetHistory or {}
    local snapshot = {
        time = date("%m-%d %H"),
        records = {},
    }
    local i
    for i = 1, #XyArray do
        local source = XyArray[i]
        local record = self:NormalizeRecord({
            name = source and source.name,
            class = source and source.class,
            xy = source and source.xy,
            dkp = source and source.dkp,
            finish = source and source.finish,
        })
        if record.name ~= "" then
            table.insert(snapshot.records, record)
        end
    end
    table.insert(XyResetHistory, 1, snapshot)
    while #XyResetHistory > 100 do
        table.remove(XyResetHistory)
    end
    return snapshot
end

function addon:ClearWishHistory()
    XyWishHistory = {}
    XyResetHistory = {}
    if self.UI then self.UI.historySelectedIndex = nil end
    if self.UI then self.UI:Update() end
    self:Print("历史许愿和重置记录已清空")
end

function addon:RollCurrentWishes()
    return self:StartRollTracking()
end

function addon:IsRollTeamAvailable()
    return teamChannel() ~= nil
end

function addon:StopRollWhenSolo()
    if self:IsRollTeamAvailable() then return false end
    if self.rollTracking or self.rollCountingDown or #self.rollMessageQueue > 0 then
        self.rollData = {}
        self.rollResults = {}
        self.rollMessageQueue = {}
        self.rollMessageElapsed = 0
        self.rollTracking = false
        self.rollCountingDown = false
        self.rollCountdown = 0
        self.rollCountdownElapsed = 0
        self.rollFinalDelay = 0
        self.rollFinalText = nil
        self:UpdateRollPage()
        self:Print("已离开队伍或团队，本轮 Roll 功能已停止。")
        return true
    end
    return false
end

function addon:GetRollChatType()
    local selectedID = self.rollChannelID or 2
    if self.UI and self.UI.rollDropdown and UIDropDownMenu_GetSelectedID then
        selectedID = UIDropDownMenu_GetSelectedID(self.UI.rollDropdown) or selectedID
    end
    if selectedID == 1 then
        if IsInGroup() then return "PARTY" end
        return "SAY"
    end
    if IsInRaid() then
        local leader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player")
        local assistant = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player")
        if leader or assistant then return "RAID_WARNING" end
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return "SAY"
end

function addon:RollAnnounce(text)
    if not text or text == "" then return false end
    if not self:IsRollTeamAvailable() then return false end
    if type(sendChatMessage) ~= "function" then
        if not self.chatUnavailableWarned then
            self:Print("当前客户端没有可用的聊天发送 API，Roll 通报已跳过。")
            self.chatUnavailableWarned = true
        end
        return false
    end
    local ok = pcall(sendChatMessage, text, self:GetRollChatType())
    if not ok and not self.chatUnavailableWarned then
        self:Print("当前状态无法发送 Roll 通报，已跳过本条消息。")
        self.chatUnavailableWarned = true
    end
    return ok
end

function addon:QueueRollAnnounce(text)
    if text and text ~= "" then
        table.insert(self.rollMessageQueue, text)
    end
end

function addon:ProcessRollMessageQueue(elapsed)
    if #self.rollMessageQueue == 0 then return end
    self.rollMessageElapsed = self.rollMessageElapsed + elapsed
    if self.rollMessageElapsed < 0.35 then return end
    self.rollMessageElapsed = 0
    self:RollAnnounce(table.remove(self.rollMessageQueue, 1))
end

function addon:GetSortedRolls()
    local sorted = {}
    local player, roll
    for player, roll in pairs(self.rollData) do
        table.insert(sorted, {player = player, roll = roll})
    end
    table.sort(sorted, function(left, right)
        if left.roll ~= right.roll then return left.roll > right.roll end
        return left.player < right.player
    end)
    return sorted
end

function addon:UpdateRollPage()
    self.rollResults = self:GetSortedRolls()
    if self.UI then self.UI:UpdateRollPage() end
end

function addon:StartRollTracking()
    if not self:IsRollTeamAvailable() then
        self:Print("Roll 功能需要先加入队伍或团队。")
        return false
    end
    if self.rollCountingDown then
        self:Print("倒计时通报进行中，请稍候再开始新一轮 Roll。")
        return false
    end
    self.rollData = {}
    self.rollResults = {}
    self.rollMessageQueue = {}
    self.rollMessageElapsed = 0
    self.rollTracking = true
    self.rollFinalDelay = 0
    self.rollFinalText = nil
    self:UpdateRollPage()
    self:RollAnnounce("----- 开始Roll点 -----")
    self:RollAnnounce("--- 请勿重复Roll点 ---")
    return true
end

function addon:ClearRollData()
    self.rollData = {}
    self.rollResults = {}
    self.rollMessageQueue = {}
    self.rollMessageElapsed = 0
    self.rollTracking = false
    self.rollCountingDown = false
    self.rollFinalDelay = 0
    self.rollFinalText = nil
    self:UpdateRollPage()
end

function addon:StopRollTracking()
    if not self:IsRollTeamAvailable() then
        self:Print("Roll 功能需要先加入队伍或团队。")
        return false
    end
    if not self.rollTracking or self.rollCountingDown then return false end
    self.rollCountingDown = true
    self.rollCountdown = 6
    self.rollCountdownElapsed = 0
    self:UpdateRollPage()
    self:RollAnnounce("倒计时: >6<")
    return true
end

function addon:FinishRollTracking()
    local sorted = self:GetSortedRolls()
    local maxRoll = 0
    local maxPlayers = {}
    local i
    for i = 1, #sorted do
        if sorted[i].roll > maxRoll then
            maxRoll = sorted[i].roll
            maxPlayers = {sorted[i].player}
        elseif sorted[i].roll == maxRoll and maxRoll > 0 then
            table.insert(maxPlayers, sorted[i].player)
        end
    end

    if #sorted > 0 then
        for i = 1, #sorted do
            self:QueueRollAnnounce(string.format("%d.%s:%d", i, sorted[i].player, sorted[i].roll))
        end
        local names = table.concat(maxPlayers, ", ")
        if #maxPlayers == 1 then
            self.rollFinalText = string.format("当前最高分: %s - %d", names, maxRoll)
        else
            self.rollFinalText = string.format("当前并列最高分: %s - %d", names, maxRoll)
        end
        self.rollFinalDelay = 1
    else
        self:RollAnnounce("本次 Roll 点没有记录到任何结果。")
    end

    self.rollCountingDown = false
    self.rollTracking = false
    self:UpdateRollPage()
end

function addon:UpdateRollCountdown(elapsed)
    if not self:IsRollTeamAvailable() then
        self:StopRollWhenSolo()
        return
    end
    if self.rollFinalDelay > 0 and #self.rollMessageQueue == 0 then
        self.rollFinalDelay = self.rollFinalDelay - elapsed
        if self.rollFinalDelay <= 0 then
            self.rollFinalDelay = 0
            self:RollAnnounce(self.rollFinalText)
            self.rollFinalText = nil
        end
    end
    if not self.rollCountingDown then return end
    self.rollCountdownElapsed = self.rollCountdownElapsed + elapsed
    while self.rollCountdownElapsed >= 1 do
        self.rollCountdownElapsed = self.rollCountdownElapsed - 1
        self.rollCountdown = self.rollCountdown - 1
        if self.rollCountdown > 0 then
            self:RollAnnounce(">" .. self.rollCountdown .. "<")
        else
            self:FinishRollTracking()
            break
        end
    end
end

function addon:ProcessRollSystemMessage(message)
    if not self.rollTracking or not self:IsRollTeamAvailable() then return end
    local player, roll, minRoll, maxRoll = string.match(message or "", "^(.+)掷出(%d+)（(%d+)-(%d+)）")
    if not player then
        player, roll, minRoll, maxRoll = string.match(message or "", "^(.+)掷出(%d+)%((%d+)%-(%d+)%)")
    end
    if not player or minRoll ~= "1" or maxRoll ~= "100" then return end
    player = shortName(player)
    roll = tonumber(roll)
    if not self.rollData[player] then
        self.rollData[player] = roll
        self:UpdateRollPage()
    elseif self.rollRepeat then
        if type(sendChatMessage) == "function" then
            pcall(sendChatMessage, player .. " 你已经Roll过点了！", "WHISPER", nil, player)
        end
    end
end

function addon:GetAuthorityName()
    if not IsInGroup() then return playerName() end

    if IsInRaid() then
        if type(GetPartyAssignment) == "function" then
            local i
            for i = 1, GetNumGroupMembers() do
                local unit = "raid" .. i
                if GetPartyAssignment("MAINASSIST", unit) then
                    return shortName(UnitName(unit))
                end
            end
        end

        -- 无法查询主助理时，回退到团队领袖 rank=2。
        local i
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 then return shortName(name) end
        end
        return nil
    end

    if type(UnitIsPartyLeader) == "function" and UnitIsPartyLeader("player") then
        return playerName()
    end
    if type(IsPartyLeader) == "function" and IsPartyLeader() then
        return playerName()
    end
    return nil
end

function addon:IsOperator()
    if not IsInGroup() then return true end
    local authority = self:GetAuthorityName()
    if authority then return sameName(authority, playerName()) end
    if IsInRaid() and type(UnitIsRaidOfficer) == "function" then
        return UnitIsRaidOfficer("player")
    end
    if IsInRaid() and type(IsRaidOfficer) == "function" then
        return IsRaidOfficer()
    end
    if type(UnitIsPartyLeader) == "function" then
        return UnitIsPartyLeader("player")
    end
    return type(IsPartyLeader) == "function" and IsPartyLeader() or false
end

function addon:IsAuthoritySender(sender)
    local authority = self:GetAuthorityName()
    if authority then return sameName(authority, sender) end
    return false
end

function addon:RefreshAuthority()
    self.authorityName = self:GetAuthorityName()
    IsLeader = self:IsOperator()
    if self.UI and self.UI.UpdatePermissions then
        self.UI:UpdatePermissions(self:IsOperator())
    end
end

function addon:RefreshRoster(preserve)
    local old = {}
    local i
    if preserve then
        for i = 1, #XyArray do
            local record = self:NormalizeRecord(XyArray[i])
            old[string.lower(shortName(record.name))] = record
        end
    end

    local result = {}
    local added = {}
    local function addMember(name, class)
        if not name or name == "" then return end
        local key = string.lower(shortName(name))
        if added[key] then return end
        added[key] = true
        local oldRecord = old[key]
        local record = oldRecord or self:NormalizeRecord({
            name = name, class = class or "未知职业", dkp = DefaultDKP,
            xy = UNWISHED, finish = 0,
        })
        record.name = shortName(name)
        if class and class ~= "" then record.class = class end
        table.insert(result, record)
    end

    local raidCount = 0
    if type(GetNumRaidMembers) == "function" then
        raidCount = tonumber(GetNumRaidMembers()) or 0
    end
    local inRaid = type(IsInRaid) == "function" and IsInRaid() or false
    if raidCount > 0 then inRaid = true end

    local partyCount = 0
    if type(GetNumPartyMembers) == "function" then
        partyCount = tonumber(GetNumPartyMembers()) or 0
    elseif type(GetNumSubgroupMembers) == "function" then
        partyCount = tonumber(GetNumSubgroupMembers()) or 0
    end
    local inGroup = type(IsInGroup) == "function" and IsInGroup() or false
    if partyCount > 0 then inGroup = true end

    local player = UnitName("player")
    local playerClass = type(UnitClass) == "function" and select(1, UnitClass("player")) or nil
    addMember(player, playerClass)

    if inRaid then
        local count = raidCount
        if count == 0 and type(GetNumGroupMembers) == "function" then
            count = tonumber(GetNumGroupMembers()) or 0
        end
        local limit = count > 0 and count or 40
        for i = 1, limit do
            local unit = "raid" .. i
            local name
            local class
            if type(GetRaidRosterInfo) == "function" then
                name = select(1, GetRaidRosterInfo(i))
                class = select(5, GetRaidRosterInfo(i))
            end
            if not name then name = UnitName(unit) end
            if not class and type(UnitClass) == "function" then
                class = select(1, UnitClass(unit))
            end
            addMember(name, class)
        end
    else
        -- 普通小队以及部分旧客户端直接使用 player/party 单位。
        for i = 1, 4 do
            local unit = "party" .. i
            local name = UnitName(unit)
            local class = type(UnitClass) == "function" and select(1, UnitClass(unit)) or nil
            addMember(name, class)
        end
    end

    -- 如果客户端没有正确报告团队状态，再无条件探测 raid 单位作为最后兜底。
    if #result <= 1 and not inRaid then
        for i = 1, 40 do
            local unit = "raid" .. i
            local name = UnitName(unit)
            local class = type(UnitClass) == "function" and select(1, UnitClass(unit)) or nil
            addMember(name, class)
        end
    end

    -- 团队接口刚建立时可能暂时返回空名单，避免一次刷新把已有列表清空。
    if #result == 0 and #XyArray > 0 then
        for i = 1, #XyArray do table.insert(result, XyArray[i]) end
    end

    local changed = #result ~= #XyArray
    if not changed then
        for i = 1, #result do
            if not XyArray[i] or not sameName(result[i].name, XyArray[i].name) then
                changed = true
                break
            end
        end
    end
    XyArray = result
    self.records = XyArray
    if self.UI then self.UI:Update() end
    return changed
end

function addon:ClearLocalWishes()
    local i
    for i = 1, #XyArray do
        local record = self:NormalizeRecord(XyArray[i])
        record.xy = UNWISHED
        record.finish = 0
        XyArray[i] = record
    end
    self.records = XyArray
end

function addon:SetProtocolMode(mode)
    if mode ~= "new" and mode ~= "legacy" then return false end
    self.protocolMode = mode
    self.protocolConfirmed = mode == "new"
    self.protocolNegotiating = false
    self.protocolNewSeen = mode == "new"
    self.protocolElapsed = 0
    if self.UI and self.UI.UpdateProtocolStatus then
        self.UI:UpdateProtocolStatus()
    end
    return true
end

function addon:BeginProtocolNegotiation()
    if XyForceNewProtocol == 1 then
        self:SetProtocolMode("new")
        self:RequestSnapshot()
        return
    end
    if self.protocolNegotiating then return end
    self.protocolMode = "new"
    self.protocolConfirmed = false
    self.protocolNegotiating = true
    self.protocolNewSeen = false
    self.protocolElapsed = 0
    if self.UI and self.UI.UpdateProtocolStatus then
        self.UI:UpdateProtocolStatus()
    end

    if self:IsOperator() then
        self:QueuePacket(packet("CAPS_REQ", PROTOCOL_VERSION, SNAPSHOT_PREFIX), "RAID")
    else
        self:RequestSnapshot()
    end
end

function addon:UpdateProtocolNegotiation(elapsed)
    if not self.protocolNegotiating then return end
    if self.protocolNewSeen then
        self:SetProtocolMode("new")
        return
    end
    self.protocolElapsed = self.protocolElapsed + elapsed
    if self.protocolElapsed < PROTOCOL_NEGOTIATION_TIMEOUT then return end

    self:SetProtocolMode("legacy")
    if self.Legacy then
        self.Legacy:RequestSnapshot()
        if self:IsOperator() then self.Legacy:SendSnapshot() end
    end
end

function addon:QueueAddonMessage(prefix, message, channel, target)
    if not message then
        return false
    end

    -- 新协议小消息交给 AceComm；它使用 ChatThrottleLib 并自动处理协议分片。
    if prefix == PREFIX then
        if not self.AceComm then
            self:Print("AceComm-3.0 未加载，无法发送新协议消息。")
            return false
        end
        if #message > MAX_MESSAGE_LENGTH then
            self:Print("新协议控制消息超过 240 字节，已拒绝发送。")
            return false
        end
        local ok = pcall(self.AceComm.SendCommMessage, self.AceComm, PREFIX,
            message, channel or "RAID", target, "NORMAL")
        return ok
    end

    -- 老协议单独保留原始队列，方便未来整体删除兼容模块。
    if #message > MAX_MESSAGE_LENGTH then
        self:Print("同步消息过长，已忽略。请缩短物品名称或许愿内容。")
        return false
    end
    table.insert(self.txQueue, {
        prefix = prefix,
        message = message,
        channel = channel,
        target = target,
    })
    return true
end

function addon:QueuePacket(message, channel, target)
    if not message then return false end
    return self:QueueAddonMessage(PREFIX, message, channel, target)
end

function addon:QueueRecord(record, session)
    if self.protocolMode == "legacy" and self.Legacy then
        return self.Legacy:SendRecord(record)
    end
    record = self:NormalizeRecord(record)
    return self:QueuePacket(packet("REC", session or 0, record.name, record.class,
        record.xy, record.dkp, record.finish), "RAID")
end

function addon:SendSnapshot(target)
    if not self:IsOperator() then return false end
    if self.protocolMode == "legacy" and self.Legacy then
        return self.Legacy:SendSnapshot(target)
    end
    if not self.Snapshot then
        self:Print("压缩同步模块未加载，无法发送全量许愿表。")
        return false
    end
    return self.Snapshot:Send(target)
end

function addon:BroadcastState()
    if self.protocolMode == "legacy" then return true end
    if self:IsOperator() then
        self:QueuePacket(packet("STATE", self.running and 1 or 0, DefaultDKP), "RAID")
    end
end

function addon:BroadcastRecord(record)
    if self.protocolMode == "legacy" and self.Legacy then
        return self.Legacy:SendRecord(record)
    end
    if self:IsOperator() then self:QueueRecord(record, 0) end
end

function addon:ProcessPacket(message, sender)
    local fields = splitPacket(message or "")
    local command = fields[1]
    if command == "CAPS_REQ" then
        if not self:IsAuthoritySender(sender) then return end
        local version = numeric(fields[2], 0)
        local snapshotPrefix = fields[3] or ""
        local compatible = version >= PROTOCOL_VERSION and snapshotPrefix == SNAPSHOT_PREFIX and
            self.AceComm and self.Snapshot and self.Snapshot.available
        self:SetProtocolMode(compatible and "new" or "legacy")
        if sender then
            self:QueuePacket(packet("CAPS_ACK", compatible and PROTOCOL_VERSION or 0,
                compatible and SNAPSHOT_PREFIX or ""), "WHISPER", sender)
        end
        return
    elseif command == "CAPS_ACK" then
        if self:IsOperator() or self:IsAuthoritySender(sender) then
            local version = numeric(fields[2], 0)
            local snapshotPrefix = fields[3] or ""
            if version >= PROTOCOL_VERSION and snapshotPrefix == SNAPSHOT_PREFIX and
               self.AceComm and self.Snapshot and self.Snapshot.available then
                self:SetProtocolMode("new")
            else
                self:SetProtocolMode("legacy")
                if self:IsOperator() and self.Legacy and sender then
                    self.Legacy:SendSnapshot(sender)
                end
            end
        end
        return
    elseif command == "HELLO" then
        if not self:IsOperator() then return end
        local compatible = self.AceComm and self.Snapshot and self.Snapshot.available
        self:SetProtocolMode(compatible and "new" or "legacy")
        if self:IsOperator() and sender then
            self:QueuePacket(packet("CAPS_ACK", compatible and PROTOCOL_VERSION or 0,
                compatible and SNAPSHOT_PREFIX or ""), "WHISPER", sender)
            if compatible then self:SendSnapshot(sender) end
        end
        return
    elseif command == "RESET" or command == "STATE" or
           command == "BEGIN" or command == "REC" or command == "END" then
        if not self:IsAuthoritySender(sender) then return end
        self:SetProtocolMode("new")
    end

    if not self:IsAuthoritySender(sender) then return end

    if command == "RESET" then
        local resetToken = fields[2] or ""
        if resetToken ~= "" and resetToken == self.lastRemoteResetToken then return end
        self.lastRemoteResetToken = resetToken
        self:SaveResetSnapshot()
    elseif command == "STATE" then
        self.running = numeric(fields[2], 0) == 1
        XyInProgress = self.running
        DefaultDKP = numeric(fields[3], DefaultDKP)
        if self.UI then self.UI:Update() end
    elseif command == "BEGIN" then
        self.receivingSession = numeric(fields[2], 0)
        self.receivingCount = numeric(fields[3], 0)
        DefaultDKP = numeric(fields[4], DefaultDKP)
        self.running = numeric(fields[5], 0) == 1
        XyInProgress = self.running
        XyArray = {}
        self.records = XyArray
        self.receivingSeen = {}
        self.receivingReceived = 0
    elseif command == "REC" then
        local session = numeric(fields[2], 0)
        if session == 0 or session == self.receivingSession then
            local index = numeric(fields[3], 0)
            local offset = session == 0 and 3 or 4
            local data = {
                name = fields[offset], class = fields[offset + 1], xy = fields[offset + 2],
                dkp = fields[offset + 3], finish = fields[offset + 4],
            }
            if session == 0 then
                self:UpsertRecord(data)
            else
                if index > 0 and not self.receivingSeen[index] then
                    self.receivingSeen[index] = true
                    self.receivingReceived = self.receivingReceived + 1
                end
                self.receivingIndex = math.max(self.receivingIndex, index)
                self:UpsertRecord(data)
            end
        end
    elseif command == "END" then
        local session = numeric(fields[2], 0)
        if session == self.receivingSession then
            local expected = self.receivingCount
            local received = self.receivingReceived
            self.receivingSession = nil
            self.receivingCount = 0
            self.receivingIndex = 0
            self.receivingSeen = {}
            self.receivingReceived = 0
            if received < expected then
                self:Print("新协议同步不完整（" .. received .. "/" .. expected .. "），正在请求补发。")
                self:RequestSnapshot()
            end
        end
    end
    if self.UI then self.UI:Update() end
end

function addon:RequestSnapshot()
    if self.protocolMode == "legacy" and self.Legacy then
        return self.Legacy:RequestSnapshot()
    end
    local authority = self:GetAuthorityName()
    if authority and not sameName(authority, playerName()) then
        self:QueuePacket(packet("HELLO", 1), "RAID")
    end
end

function addon:SendTeam(message)
    if type(sendChatMessage) ~= "function" then return false end
    local channel = teamChannel()
    if not channel then
        self:Print("当前不在团队或小队，公告未发送。")
        return false
    end
    local ok = pcall(sendChatMessage, message, channel)
    return ok
end

function addon:NotifyChange(name, amount, record)
    local text
    if amount > 0 then
        text = "通知：玩家【" .. name .. "】增加【" .. amount .. "】分，剩余【" .. record.dkp .. "】分"
    else
        text = "通知：玩家【" .. name .. "】扣除【" .. math.abs(amount) .. "】分，剩余【" .. record.dkp .. "】分"
    end
    if type(sendChatMessage) == "function" then
        pcall(sendChatMessage, text, "WHISPER", nil, name)
    end
    self:SendTeam(text)
end

function addon:NotifyTradeDKP(name, amount, record, items)
    local names = {}
    local i
    for i = 1, #(items or {}) do
        local item = items[i]
        local itemName = item and (item.name or item.link)
        if itemName and itemName ~= "" then
            local count = tonumber(item.count) or 1
            if count > 1 then itemName = itemName .. "x" .. count end
            table.insert(names, itemName)
        end
    end
    if #names == 0 then table.insert(names, "未记录装备") end
    local text = "通知：玩家【" .. name .. "】获得装备【" .. table.concat(names, "、") ..
        "】，总计扣除【" .. math.abs(amount or 0) .. "】分，剩余【" .. record.dkp .. "】分"
    if type(sendChatMessage) == "function" then
        pcall(sendChatMessage, text, "WHISPER", nil, name)
    end
    self:SendTeam(text)
end

function addon:SetDKP(name, amount, silent)
    if not self:IsOperator() then return false end
    amount = numeric(amount, 0)
    if amount == 0 then return false end
    local record = self:FindRecord(name)
    if not record then return false end
    record.dkp = numeric(record.dkp, DefaultDKP) + amount
    self:BroadcastRecord(record)
    if self.UI then self.UI:Update() end
    if not silent then self:NotifyChange(record.name, amount, record) end
    return true
end

function addon:AddDKP(name, amount)
    return self:SetDKP(name, math.abs(numeric(amount, 0)))
end

function addon:MinusDKP(name, amount, silent)
    return self:SetDKP(name, -math.abs(numeric(amount, 0)), silent)
end

function addon:MarkFinished(name, value)
    if not self:IsOperator() then return false end
    local record = self:FindRecord(name)
    if not record then return false end
    record.finish = numeric(value, 0) == 1 and 1 or 0
    if XyWishHistory then
        local i
        for i = 1, #XyWishHistory do
            if sameName(XyWishHistory[i].name, record.name) and
               XyWishHistory[i].xy == record.xy then
                XyWishHistory[i].finish = record.finish
                break
            end
        end
    end
    self:BroadcastRecord(record)
    local message
    if record.finish == 1 then
        message = "恭喜：玩家【" .. record.name .. "】的许愿【" .. record.xy .. "】已达成，剩余【" .. record.dkp .. "】分"
    else
        message = "通知：玩家【" .. record.name .. "】的许愿达成状态已取消"
    end
    if type(sendChatMessage) == "function" then
        pcall(sendChatMessage, message, "WHISPER", nil, record.name)
    end
    self:SendTeam(message)
    if self.UI then self.UI:Update() end
    return true
end

function addon:SetDefaultDKP(value)
    if not self:IsOperator() then return false end
    value = numeric(value, nil)
    if not value or value < 0 then return false end
    DefaultDKP = value
    local i
    for i = 1, #XyArray do XyArray[i].dkp = value end
    if self.protocolMode == "legacy" and self.Legacy then
        self.Legacy:SendInitDKP(value)
    end
    self:BroadcastState()
    self:SendSnapshot()
    self:SendTeam("通知：当前默认DKP为每人" .. value .. "分，分数已初始化")
    if self.UI then self.UI:Update() end
    return true
end

function addon:ResetRoster()
    if not self:IsOperator() then return false end
    self:SaveResetSnapshot()
    local resetToken = date("%Y%m%d%H%M%S")
    self:RefreshRoster(false)
    local i
    for i = 1, #XyArray do
        XyArray[i].dkp = DefaultDKP
        XyArray[i].xy = UNWISHED
        XyArray[i].finish = 0
    end
    self.running = false
    XyInProgress = false
    if self.protocolMode == "legacy" and self.Legacy then
        self.Legacy:SendReset(DefaultDKP)
    elseif self.protocolMode ~= "legacy" then
        self:QueuePacket(packet("RESET", resetToken, DefaultDKP), "RAID")
    end
    self:BroadcastState()
    self:SendSnapshot()
    self:SendTeam("许愿列表已重置，当前默认DKP为" .. DefaultDKP .. "分")
    if self.UI then self.UI:Update() end
    return true
end

function addon:StartWish()
    if not self:IsOperator() then return false end
    self.running = true
    XyInProgress = true
    self:BroadcastState()
    self:SendSnapshot()
    self:SendTeam("开始许愿，请在团队频道输入【XY 许愿装备】")
    if self.UI then self.UI:Update() end
    return true
end

function addon:StopWish()
    if not self:IsOperator() then return false end
    self.running = false
    XyInProgress = false
    self:BroadcastState()
    self:SendTeam("许愿结束，后续许愿无效")
    if self.UI then self.UI:Update() end
    return true
end

function addon:ExtractItemName(text)
    text = trim(text)
    if text == "" or text == UNWISHED then return nil end
    local bracket = string.match(text, "%[(.-)%]")
    if bracket and bracket ~= "" then return trim(bracket) end
    return text
end

function addon:ExtractItemID(text)
    local itemID = string.match(tostring(text or ""), "item:(%d+)")
    return itemID
end

function addon:NormalizeItemName(text)
    text = tostring(text or "")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|H.-|h", "")
    text = self:ExtractItemName(text) or ""
    text = string.gsub(text, "%s*%(%d+%)%s*$", "")
    text = string.gsub(text, "%s+", "")
    return string.lower(trim(text))
end

function addon:IsSameItem(wishText, itemName, itemLink)
    local wishID = self:ExtractItemID(wishText)
    local itemID = self:ExtractItemID(itemLink)
    if wishID and itemID then return wishID == itemID end
    local left = self:NormalizeItemName(wishText)
    local right = self:NormalizeItemName(itemName)
    return left ~= "" and right ~= "" and left == right
end

function addon:OnWish(name, wish)
    if not self:IsOperator() or not self.running then return false end
    name = shortName(name)
    wish = trim(wish)
    if name == "" or wish == "" then return false end
    local record = self:CreateRecord(name, "未知职业")
    if IsInRaid() then
        local i
        for i = 1, GetNumGroupMembers() do
            local rosterName, _, _, _, class = GetRaidRosterInfo(i)
            if rosterName and sameName(rosterName, name) then
                record.class = class or record.class
                break
            end
        end
    end
    record.xy = wish
    record.finish = 0
    self:AddWishHistory(record)
    self:BroadcastRecord(record)
    if self.UI then self.UI:Update() end
    return true
end

function addon:ParseWishMessage(message, sender)
    if not self.running or not self:IsOperator() then return end
    local first, rest = string.match(message or "", "^%s*(%S+)%s*(.-)%s*$")
    if not first then return end
    local command = string.lower(first)
    if command == "xy" and rest ~= "" then
        self:OnWish(shortName(sender), rest)
    elseif command == "txy" then
        local target, wish = string.match(rest, "^(%S+)%s+(.+)$")
        if target and wish then self:OnWish(target, wish) end
    elseif XyOnlyMode == 0 and string.find(message, "|Hitem:", 1, true) then
        self:OnWish(shortName(sender), message)
    end
end

function addon:QueryWish(name)
    local record = self:FindRecord(name)
    local wish = record and record.xy or UNWISHED
    local dkp = record and record.dkp or DefaultDKP
    self:SendTeam("查询许愿：玩家【" .. shortName(name) .. "】许愿【" .. wish .. "】，剩余DKP【" .. dkp .. "】分")
end

function addon:ExportData()
    local lines = {}
    local i
    for i = 1, #XyArray do
        local record = self:NormalizeRecord(XyArray[i])
        table.insert(lines, string.format("%s,%s,%s,当前剩余:[%d]分,[%s]",
            record.name, record.class, record.xy, record.dkp,
            record.finish == 1 and "已经达成" or "未达成"))
    end
    return table.concat(lines, "\n")
end

function addon:ExportHistoryData(index)
    local snapshot = XyResetHistory and XyResetHistory[index]
    if not snapshot then return "" end
    local lines = {
        "重置时间：" .. tostring(snapshot.time or ""),
        "角色名,职业,许愿内容,当前剩余,状态",
    }
    local records = snapshot.records or {}
    local i
    for i = 1, #records do
        local record = self:NormalizeRecord(records[i])
        table.insert(lines, string.format("%s,%s,%s,当前剩余:[%d]分,[%s]",
            record.name, record.class, record.xy, record.dkp,
            record.finish == 1 and "已经达成" or "未达成"))
    end
    return table.concat(lines, "\n")
end

function addon:Refresh()
    local inTeam = teamChannel() ~= nil
    local joinedTeam = inTeam and not self.wasInTeam
    if joinedTeam then self:ClearLocalWishes() end
    self.wasInTeam = inTeam
    local changed = self:RefreshRoster(true)
    if self:IsOperator() and (changed or joinedTeam) then self:SendSnapshot() end
    self:RefreshAuthority()
    if self.UI then self.UI:Update() end
end

-- 旧版本公开函数兼容层：保留常用宏和外部模块调用方式，内部统一走新实现。
function addon:getXyInfo(name)
    return self:FindRecord(name)
end

function getXyInfo(name)
    return addon:FindRecord(name)
end

function addon:MinusDKP_test(name, amount)
    return self:MinusDKP(name, amount)
end

function addon:XyFinish(name, value)
    return self:MarkFinished(name, value)
end

function addon:XyQuery(name, amount)
    if amount and numeric(amount, 0) ~= 0 then
        return self:SetDKP(name, amount)
    end
    self:QueryWish(name)
    return true
end

function addon:SendXYMessage(record)
    self:BroadcastRecord(record)
end

function addon:SyncXy()
    return self:SendSnapshot()
end

function addon:initAllDKP(value)
    return self:SetDefaultDKP(value)
end

function addon:NEWDefaultDKP()
    if self.UI and self.UI.defaultFrame then
        return self:SetDefaultDKP(_G["XyDefaultDkpEdit"]:GetNumber())
    end
    return false
end

function addon:OnStartButtonClick() return self:StartWish() end
function addon:OnStopButtonClick() return self:StopWish() end
function addon:OnClearButtonClick() return self:ResetRoster() end
function addon:OnRefreshButtonClick() return self:Refresh() end
function addon:OnAnnounceButtonClick() return self:AnnounceMissing() end
function addon:OnExportButtonClick() if self.UI then return self.UI:ShowExport() end end
function addon:OnAboutButtonClick() if self.UI then return self.UI:ToggleAbout() end end

function addon:OnUpdate(elapsed)
    self.txElapsed = self.txElapsed + elapsed
    if self.txElapsed >= QUEUE_DELAY and #self.txQueue > 0 then
        self.txElapsed = 0
        local item = table.remove(self.txQueue, 1)
        if item and type(sendAddonMessage) == "function" then
            sendAddonMessage(item.prefix or PREFIX, item.message, item.channel, item.target)
        end
    end
    self:UpdateProtocolNegotiation(elapsed)
    self:ProcessRollMessageQueue(elapsed)
    self:UpdateRollCountdown(elapsed)
end

function addon:Initialize()
    if self.isInitialized then return end
    self.isInitialized = true
    self:NormalizeDatabase()
    if type(registerAddonMessagePrefix) ~= "function" then
        self:Print("当前客户端没有可用的插件通讯注册 API，通讯功能已停用。")
    else
        pcall(registerAddonMessagePrefix, PREFIX)
    end
    if self.Legacy then self.Legacy:RegisterPrefixes() end

    if self.AceComm then
        self.AceComm:RegisterComm(PREFIX, function(prefix, message, channel, sender)
            self:ProcessPacket(message, sender)
        end)
    else
        self:Print("AceComm-3.0 未加载，新协议通讯不可用。")
    end

    local eventFrame = CreateFrame("Frame", "NewXYTrackEventFrame")
    self.eventFrame = eventFrame
    registerEventSafe(eventFrame, "PLAYER_LOGIN")
    registerEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")
    registerEventSafe(eventFrame, "RAID_ROSTER_UPDATE")
    registerEventSafe(eventFrame, "GROUP_ROSTER_UPDATE")
    registerEventSafe(eventFrame, "PARTY_LEADER_CHANGED")
    registerEventSafe(eventFrame, "CHAT_MSG_RAID")
    registerEventSafe(eventFrame, "CHAT_MSG_RAID_LEADER")
    registerEventSafe(eventFrame, "CHAT_MSG_RAID_WARNING")
    registerEventSafe(eventFrame, "CHAT_MSG_PARTY")
    registerEventSafe(eventFrame, "CHAT_MSG_SYSTEM")
    registerEventSafe(eventFrame, "CHAT_MSG_ADDON")
    eventFrame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, channel, sender = ...
            if self.Legacy and self.Legacy:IsPrefix(prefix) then
                self.Legacy:Process(prefix, message, sender)
            end
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or
               event == "CHAT_MSG_RAID_WARNING" or event == "CHAT_MSG_PARTY" then
            local message, sender = ...
            self:ParseWishMessage(message, sender)
        elseif event == "CHAT_MSG_SYSTEM" then
            local message = ...
            self:ProcessRollSystemMessage(message)
        elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" or
               event == "PARTY_LEADER_CHANGED" then
            self:StopRollWhenSolo()
            self:Refresh()
        elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            self:Refresh()
            self:BeginProtocolNegotiation()
        end
    end)

    if self.UI then self.UI:Create() end
    if self.Trade then self.Trade:Initialize() end
    self.wasInTeam = teamChannel() ~= nil
    self:Refresh()
    self:RegisterSlashCommands()
    self:HookTooltips()
end

function addon:RegisterSlashCommands()
    SLASH_NEWXYTRACK1 = "/xyt"
    SLASH_NEWXYTRACK2 = "/xytrack"
    SlashCmdList["NEWXYTRACK"] = function(message)
        local command, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
        command = string.lower(command or "")
        if command == "start" then
            self:StartWish()
        elseif command == "stop" then
            self:StopWish()
        elseif command == "reset" then
            self:ResetRoster()
        elseif command == "refresh" then
            self:Refresh()
        elseif command == "announce" then
            self:AnnounceMissing()
        elseif command == "export" then
            if self.UI then self.UI:ShowExport() end
        elseif command == "show" then
            local i
            for i = 1, #XyArray do
                local r = XyArray[i]
                self:Print(r.name .. " | " .. r.xy .. " | DKP " .. r.dkp .. " | " .. (r.finish == 1 and "达成" or "未达成"))
            end
        elseif command == "mode" then
            XyOnlyMode = XyOnlyMode == 1 and 0 or 1
            self:Print("物品链接直贴模式：" .. (XyOnlyMode == 0 and "开启" or "关闭"))
        elseif command == "protocol" then
            rest = string.lower(rest or "")
            if rest == "on" or rest == "new" or rest == "force" then
                XyForceNewProtocol = 1
                self:SetProtocolMode("new")
                self:Print("已强制使用新协议，跳过协议协商。")
            elseif rest == "off" or rest == "auto" then
                XyForceNewProtocol = 0
                self:Print("已开启自动协议协商：优先新协议，失败后使用老协议。")
                self:BeginProtocolNegotiation()
            else
                self:Print("协议模式：" .. (XyForceNewProtocol == 1 and "强制新协议" or "自动协商"))
            end
        elseif command == "clean" then
            if self:IsOperator() then
                XyArray = {}
                self.records = XyArray
                if self.UI then self.UI:Update() end
                self:SendSnapshot()
            end
        elseif command == "query" and rest ~= "" then
            self:QueryWish(rest)
        else
            if self.UI then self.UI:Toggle() end
        end
    end
end

function addon:AnnounceMissing()
    if not self:IsOperator() then return end
    local missing = {}
    local i
    for i = 1, #XyArray do
        if XyArray[i].xy == UNWISHED then table.insert(missing, XyArray[i].name) end
    end
    if #missing == 0 then
        self:SendTeam("通知：所有玩家已许愿！")
    else
        self:SendTeam("通知：以下玩家未许愿：【" .. table.concat(missing, "，") .. "】")
    end
end

function addon:AnnounceItemWishers(itemText, itemLink)
    local itemName = self:ExtractItemName(itemText or "")
    if not itemName and itemLink then itemName = self:ExtractItemName(itemLink) end
    if not itemName then return false end

    local matches = {}
    local i
    for i = 1, #XyArray do
        local record = self:NormalizeRecord(XyArray[i])
        if self:IsSameItem(record.xy, itemName, itemLink) then
            table.insert(matches, record.name .. "（" .. record.dkp .. "）")
        end
    end
    if #matches == 0 then
        self:Print("装备【" .. itemName .. "】没有团员许愿。")
        return false
    end

    self:SendTeam("通知：装备【" .. itemName .. "】的许愿玩家（" .. #matches ..
        "人）：" .. table.concat(matches, "、"))
    return true
end

function addon:HookTooltips()
    local lastChatItemKey
    local lastChatItemTime = 0
    local function handleChatItem(link, text, button)
        if (button ~= "RightButton" and button ~= "BUTTON2") or not IsShiftKeyDown() then return end
        if type(link) ~= "string" or not string.find(link, "item:", 1, true) then return end
        local key = link .. "|" .. tostring(text or "")
        local now = type(GetTime) == "function" and GetTime() or 0
        if key == lastChatItemKey and now - lastChatItemTime < 0.25 then return end
        lastChatItemKey = key
        lastChatItemTime = now
        addon:AnnounceItemWishers(text, link)
    end

    local function appendWishMembers(tooltip)
        if not tooltip or not tooltip.GetItem then return end
        local itemLabel, link = tooltip:GetItem()
        local itemName = addon:ExtractItemName(itemLabel or "")
        if not itemName and link then
            itemName = addon:ExtractItemName(link)
        end
        if not itemName and link and type(GetItemInfo) == "function" then
            itemName = addon:ExtractItemName(GetItemInfo(link) or "")
        end
        if not itemName then return end

        local matches = {}
        local i
        for i = 1, #XyArray do
            local record = addon:NormalizeRecord(XyArray[i])
            if addon:IsSameItem(record.xy, itemName, link) then
                table.insert(matches, record)
            end
        end
        if #matches == 0 then return end

        local memberTexts = {}
        for i = 1, #matches do
            local record = matches[i]
            local coloredName = "|c" .. addon:ClassColor(record.class) ..
                record.name .. "|r"
            table.insert(memberTexts, coloredName .. "（" .. record.dkp .. "）")
        end
        tooltip:AddLine("|cff00ff00许愿玩家（" .. #matches .. "人）：|r" ..
            table.concat(memberTexts, "、"), 1, 1, 0)
    end

    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", appendWishMembers)
    end
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        ItemRefTooltip:HookScript("OnTooltipSetItem", appendWishMembers)
    end

    if type(hooksecurefunction) == "function" then
        hooksecurefunction("SetItemRef", function(link, text, button, chatFrame)
            handleChatItem(link, text, button)
        end)
    end

    local i
    local chatCount = NUM_CHAT_WINDOWS or 10
    for i = 1, chatCount do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.HookScript and not chatFrame.xyWishHooked then
            chatFrame.xyWishHooked = true
            chatFrame:HookScript("OnHyperlinkClick", function(_, link, text, button)
                handleChatItem(link, text, button)
            end)
        end
    end
    if type(hooksecurefunction) == "function" and type(ChatFrame_OnHyperlinkShow) == "function" then
        hooksecurefunction("ChatFrame_OnHyperlinkShow", function(_, link, text, button)
            handleChatItem(link, text, button)
        end)
    end
end

local bootstrap = CreateFrame("Frame", "NewXYTrackBootstrapFrame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(_, event, loadedName)
    if event == "ADDON_LOADED" and loadedName == addonName then
        addon:Initialize()
    end
end)

return addon
