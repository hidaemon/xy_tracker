local addonName, addon = ...

local Trade = {}
addon.Trade = Trade

local buttonConfig = {
    {text = "-1", action = "minus", amount = 1, message = "扣1分"},
    {text = "-2", action = "minus", amount = 2, message = "扣2分"},
    {text = "-3", action = "minus", amount = 3, message = "扣3分"},
    {text = "-4", action = "minus", amount = 4, message = "扣4分"},
    {text = "达成", action = "finish", message = "许愿达成"},
}

local tradeFrame
local buttonFrame
local buttons = {}
local dkpText
local wishText
local pendingAction
local updateInfo
local selectedAmount
local selectedFinish = false

local function makeMovable(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
end

local function registerEventSafe(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

local function targetName()
    return UnitName("NPC") or UnitName("npc") or ""
end

local function trackedTradeTarget()
    local name = targetName()
    if name == "" then return nil, nil end
    return name, addon:FindRecord(name)
end

local function capturePlayerTradeItems()
    local items = {}
    if type(GetTradePlayerItemInfo) ~= "function" then return items end
    local i
    for i = 1, 7 do
        local itemName, texture, quantity = GetTradePlayerItemInfo(i)
        if itemName then
            local link
            if type(GetTradePlayerItemLink) == "function" then
                link = GetTradePlayerItemLink(i)
            end
            local itemID = link and tonumber(string.match(link, "item:(%d+)")) or nil
            table.insert(items, {
                name = itemName,
                link = link,
                itemID = itemID,
                count = quantity or 1,
            })
        end
    end
    return items
end

local function hasPlayerTradeItems(items)
    return items and #items > 0
end

local function updateButtonSelection()
    local i
    for i = 1, #buttons do
        local button = buttons[i]
        local config = button.config
        local selected = false
        if config.action == "minus" then
            selected = selectedAmount == config.amount
        elseif config.action == "finish" then
            selected = selectedFinish
        end
        if button.SetButtonState then
            button:SetButtonState(selected and "PUSHED" or "NORMAL")
        end
        button.selected = selected
    end
end

local function stageAction(record)
    pendingAction = {
        player = record.name,
        amount = selectedAmount or 0,
        finish = selectedFinish,
        wish = record.xy,
        accepted = false,
        items = {},
    }
    if pendingAction.amount > 0 or pendingAction.finish then
        addon:Print("已记录对【" .. record.name .. "】的交易操作；交易成功且管理员交出物品后执行。")
    end
end

local function saveDkpTrade(action)
    XyTradeHistory = XyTradeHistory or {}
    table.insert(XyTradeHistory, 1, {
        time = date("%m-%d %H:%M:%S"),
        player = action.player,
        method = "DKP",
        dkp = action.amount,
        items = action.items or {},
    })
    while #XyTradeHistory > 200 do
        table.remove(XyTradeHistory)
    end
end

local function commitAction()
    local action = pendingAction
    pendingAction = nil
    if not action or not action.accepted then return end
    if not hasPlayerTradeItems(action.items) then
        addon:Print("管理员未交出物品，本次交易未记录 DKP 或许愿达成。")
        return
    end
    local record = addon:FindRecord(action.player)
    if not record then return end

    local success = true
    if action.amount and action.amount > 0 then
        success = addon:MinusDKP(record.name, action.amount, true)
        if success then
            saveDkpTrade(action)
            addon:NotifyTradeDKP(record.name, action.amount, record, action.items)
        end
    end
    if success and action.finish then
        addon:MarkFinished(record.name, 1)
    end
    updateInfo()
end

local function whisper(message, target)
    if target and target ~= "" then SendChatMessage(message, "WHISPER", nil, target) end
end

updateInfo = function()
    if not dkpText or not wishText then return end
    local name = targetName()
    local record = addon:FindRecord(name)
    dkpText:SetText("DKP: " .. (record and record.dkp or 0))
    wishText:SetText("许愿: " .. (record and record.xy or addon.unwished))
end

local function createButtons()
    local name, record = trackedTradeTarget()
    if not Trade.enabled or not Trade.operator or not name or not record then
        if buttonFrame then buttonFrame:Hide() end
        return
    end
    if buttonFrame then
        updateInfo()
        updateButtonSelection()
        buttonFrame:Show()
        local i
        for i = 1, #buttons do buttons[i]:Show() end
        return
    end
    if not TradeFrame then return end

    buttonFrame = CreateFrame("Frame", "XyTradeButtonFrame", UIParent, "BackdropTemplate")
    buttonFrame:SetWidth(160)
    buttonFrame:SetHeight(190)
    buttonFrame:SetFrameStrata("DIALOG")
    buttonFrame:SetPoint("LEFT", TradeFrame, "RIGHT", 4, 0)
    buttonFrame:SetClampedToScreen(true)
    makeMovable(buttonFrame)
    if buttonFrame.SetBackdrop then
        buttonFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3},
        })
    end

    local title = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", buttonFrame, "TOP", 0, -6)
    title:SetText("装备交易分配")
    title:SetTextColor(1, 0.82, 0)
    dkpText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dkpText:SetPoint("TOPLEFT", buttonFrame, "TOPLEFT", 8, -26)
    dkpText:SetWidth(144)
    dkpText:SetHeight(16)
    dkpText:SetJustifyH("LEFT")
    wishText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wishText:SetPoint("TOPLEFT", buttonFrame, "TOPLEFT", 8, -42)
    wishText:SetWidth(144)
    wishText:SetHeight(16)
    wishText:SetJustifyH("LEFT")

    local i
    for i = 1, #buttonConfig do
        local config = buttonConfig[i]
        local button = CreateFrame("Button", "XyTradeButton" .. i, buttonFrame, "UIPanelButtonTemplate")
        button.config = config
        button:SetWidth(128)
        button:SetHeight(24)
        button:SetPoint("TOP", buttonFrame, "TOP", 0, -62 - ((i - 1) * 25))
        button:SetText(config.text)
        if config.action == "finish" then
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(16)
            icon:SetHeight(16)
            icon:SetPoint("LEFT", button, "LEFT", 7, 0)
            icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            button.finishIcon = icon
            local label = button:GetFontString()
            if label then
                label:ClearAllPoints()
                label:SetPoint("CENTER", button, "CENTER", 8, 0)
                label:SetTextColor(0.20, 1, 0.20)
            end
        end
        button:SetScript("OnClick", function()
            local name = targetName()
            if name == "" then return end
            local record = addon:FindRecord(name)
            if not record then
                addon:Print("交易对象【" .. name .. "】不在当前团队许愿列表中。")
                return
            end
            if config.action == "minus" then
                selectedAmount = config.amount
            elseif config.action == "finish" then
                selectedFinish = not selectedFinish
            end
            updateButtonSelection()
            stageAction(record)
            updateInfo()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.message)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(buttons, button)
    end
    updateButtonSelection()
    updateInfo()
end

local function hideButtons()
    if buttonFrame then buttonFrame:Hide() end
    local i
    for i = 1, #buttons do buttons[i]:Hide() end
end

local function sendTradeSummary()
    local name = targetName()
    if name == "" then return end
    local items = {}
    local i
    for i = 1, 7 do
        local itemName, texture, quantity = GetTradeTargetItemInfo(i)
        if itemName then
            if quantity and quantity > 1 then itemName = itemName .. "x" .. quantity end
            table.insert(items, itemName)
        end
    end
    if #items > 0 then
        whisper("收到 " .. name .. " 的交易物品：" .. table.concat(items, "、"), name)
    end
end

function Trade:UpdatePermissions()
    self.operator = addon:IsOperator()
    if TradeFrame and TradeFrame:IsVisible() then
        local _, record = trackedTradeTarget()
        if self.operator and record then createButtons() else hideButtons() end
    end
end

function Trade:Initialize()
    if self.initialized then return end
    self.initialized = true
    self.enabled = true
    tradeFrame = CreateFrame("Frame", "XyTradeEventFrame")
    registerEventSafe(tradeFrame, "TRADE_SHOW")
    registerEventSafe(tradeFrame, "TRADE_CLOSED")
    registerEventSafe(tradeFrame, "TRADE_ACCEPT_UPDATE")
    registerEventSafe(tradeFrame, "RAID_ROSTER_UPDATE")
    registerEventSafe(tradeFrame, "GROUP_ROSTER_UPDATE")
    registerEventSafe(tradeFrame, "PARTY_LEADER_CHANGED")
    tradeFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "TRADE_SHOW" then
            pendingAction = nil
            selectedAmount = nil
            selectedFinish = false
            updateButtonSelection()
            self:UpdatePermissions()
            createButtons()
        elseif event == "TRADE_CLOSED" then
            commitAction()
            selectedAmount = nil
            selectedFinish = false
            updateButtonSelection()
            hideButtons()
        elseif event == "TRADE_ACCEPT_UPDATE" then
            local playerAccepted, targetAccepted = ...
            if playerAccepted == 1 and targetAccepted == 1 then
                if pendingAction and not pendingAction.accepted then
                    pendingAction.items = capturePlayerTradeItems()
                    pendingAction.accepted = true
                end
                sendTradeSummary()
            end
        else
            self:UpdatePermissions()
        end
    end)
end

function Trade:GetConfig()
    return buttonConfig
end

return addon
