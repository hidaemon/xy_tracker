local addonName, addon = ...
-- 从 .toc 的 ## Version 读取版本号，避免与 TOC 声明不一致；读取失败时回退。
local xy_version = type(GetAddOnMetadata) == "function"
    and GetAddOnMetadata(addonName, "Version") or "4.0.0"
local WINDOW_TITLE = "乘风破浪-许愿插件（重制版）"

local UI = {}
addon.UI = UI

-- 主窗口高度为700，列表区域可同时显示约21行。
local ROW_COUNT = 21
local ROLL_ROW_COUNT = 40
local ROW_HEIGHT = 25
local SORT_STATE = {}
local TAB_WIDTH = 48
local TAB_HEIGHT = 78
local TAB_GAP = 6
local HISTORY_FRAME_WIDTH = 730
local HISTORY_LEFT_WIDTH = 200
local HISTORY_RIGHT_OFFSET = 220
local RESET_HISTORY_ROW_COUNT = 100
local HISTORY_ROW_WIDTH = HISTORY_FRAME_WIDTH - HISTORY_RIGHT_OFFSET - 60

local function makePanel(name, parent, width, height)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:EnableMouse(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 16,
            insets = {left = 5, right = 5, top = 5, bottom = 5},
        })
        frame:SetBackdropColor(0, 0, 0, 0.90)
        frame:SetBackdropBorderColor(0.72, 0.60, 0.18, 1)
    end
    return frame
end

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

local function makeButton(name, parent, text, width, height)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

local function makeLabel(parent, name, width, height)
    local text = parent:CreateFontString(name, "OVERLAY", "GameFontNormalSmall")
    text:SetWidth(width)
    text:SetHeight(height)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    return text
end

local function colorFromString(color)
    if not color or #color ~= 8 then return 1, 1, 1 end
    return tonumber(string.sub(color, 3, 4), 16) / 255,
        tonumber(string.sub(color, 5, 6), 16) / 255,
        tonumber(string.sub(color, 7, 8), 16) / 255
end

function UI:Create()
    if self.frame then return end
    self.rows = {}
    self.wishElements = {}
    self.rollRows = {}
    self.historyRows = {}
    self.operator = false

    local frame = makePanel("XyTrackerFrame", UIParent, 460, 700)
    self.frame = frame
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    frame:Hide()

    local title = makeLabel(frame, "XyTrackerFrameTitle", 420, 24)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    title:SetText(WINDOW_TITLE)
    title:SetTextColor(1, 0.82, 0)
    self.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        frame:Hide()
        if self.aboutFrame then self.aboutFrame:Hide() end
    end)

    local about = makeButton("XyTrackerFrameAbout", frame, "?", 22, 22)
    about:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -7)
    about:SetScript("OnClick", function() self:ToggleAbout() end)
    self.aboutButton = about

    self:CreateTabs(frame)
    self:CreateControlButtons(frame)
    self:CreateHeaders(frame)
    self:CreateList(frame)
    self:CreateStatus(frame)
    self:CreateRollPage(frame)
    self:CreateHistoryPage(frame)
    self:CreatePopups()
    self:CreateMinimapButton()
    self:Update()
end

function UI:CreateTabs(parent)
    local tabs = {
        {key = "wish", text = "许\n愿", title = "许愿"},
        {key = "roll", text = "R\no\nl\nl", title = "Roll"},
        {key = "history", text = "历\n史\n许\n愿", title = "历史许愿"},
    }
    self.tabs = {}
    local i
    for i = 1, #tabs do
        local data = tabs[i]
        local button = CreateFrame("Button", "XyTrackerTab" .. data.key, parent, "BackdropTemplate")
        button:SetWidth(TAB_WIDTH)
        button:SetHeight(TAB_HEIGHT)
        -- Tab在窗口外侧，右边缘贴住窗口左边框。
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", -TAB_WIDTH, -90 - ((i - 1) * (TAB_HEIGHT + TAB_GAP)))
        button:EnableMouse(true)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        label:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        label:SetText(data.text)
        button.label = label
        button.tabKey = data.key
        button.tabTitle = data.title
        button:SetScript("OnClick", function()
            self:SelectTab(data.key)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tabTitle)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.tabs[data.key] = button
    end
    self:SelectTab("wish")
end

function UI:SelectTab(tabKey)
    if not self.tabs or not self.tabs[tabKey] then return end
    self.activeTab = tabKey
    for key, button in pairs(self.tabs) do
        if key == tabKey then
            button:SetBackdropColor(0.24, 0.18, 0.02, 0.95)
            button:SetBackdropBorderColor(0.80, 0.62, 0.08, 1)
            button.label:SetTextColor(1, 0.82, 0)
        else
            button:SetBackdropColor(0.08, 0.08, 0.08, 0.90)
            button:SetBackdropBorderColor(0.38, 0.38, 0.38, 1)
            button.label:SetTextColor(0.62, 0.62, 0.62)
        end
    end
    self:SetTabSize(tabKey)
    self:UpdatePageVisibility()
    if self.frame and (self.rollPage or self.historyPage) then self:Update() end
end

function UI:SetTabSize(tabKey)
    if not self.frame then return end
    local compact = tabKey == "roll"
    if compact then
        self.frame:SetWidth(260)
        self.frame:SetHeight(380)
        self.title:SetWidth(220)
        self.title:SetText("Roll Tracker")
        if self.version then self.version:Hide() end
    elseif tabKey == "history" then
        self.frame:SetWidth(HISTORY_FRAME_WIDTH)
        self.frame:SetHeight(700)
        self.title:SetWidth(HISTORY_FRAME_WIDTH - 40)
        self.title:SetText(WINDOW_TITLE)
        if self.version then self.version:Show() end
    else
        self.frame:SetWidth(460)
        self.frame:SetHeight(700)
        self.title:SetWidth(420)
        self.title:SetText(WINDOW_TITLE)
        if self.version then self.version:Show() end
    end
    if self.rollPage then self:LayoutRollPage(compact) end
end

function UI:RegisterWishElement(element)
    if element then table.insert(self.wishElements, element) end
end

function UI:UpdatePageVisibility()
    local wishVisible = self.activeTab == "wish"
    local i
    for i = 1, #self.wishElements do
        if wishVisible then
            self.wishElements[i]:Show()
        else
            self.wishElements[i]:Hide()
        end
    end
    if self.rollPage then
        if self.activeTab == "roll" then self.rollPage:Show() else self.rollPage:Hide() end
    end
    if self.historyPage then
        if self.activeTab == "history" then self.historyPage:Show() else self.historyPage:Hide() end
    end
end

function UI:CreateControlButtons(parent)
    local controls = {
        {"Start", "开始", 59, 1, function() addon:StartWish() end},
        {"Stop", "停止", 59, 1, function() addon:StopWish() end},
        {"Reset", "重置", 59, 1, function() addon:ResetRoster() end},
        {"Default", "初始化DKP", 120, 2, function() self:ShowDefaultPopup() end},
        {"Export", "导出许愿", 100, 2, function() self:ShowExport() end},
        {"Announce", "通报许愿", 100, 2, function() addon:AnnounceMissing() end},
    }
    self.controlButtons = {}
    local lastRow1
    local lastRow2
    local i
    for i = 1, #controls do
        local data = controls[i]
        local button = makeButton("XyTrackerFrame" .. data[1], parent, data[2], data[3], 17)
        if data[4] == 1 then
            if not lastRow1 then
                button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -38)
            else
                button:SetPoint("RIGHT", lastRow1, "LEFT", -2, 0)
            end
            lastRow1 = button
        else
            if not lastRow2 then
                button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -60)
            else
                button:SetPoint("RIGHT", lastRow2, "LEFT", -2, 0)
            end
            lastRow2 = button
        end
        button:SetScript("OnClick", data[5])
        self.controlButtons[data[1]] = button
        self:RegisterWishElement(button)
    end

    local refresh = makeButton("XyTrackerFrameRefresh", parent, "刷新", 59, 17)
    refresh:SetPoint("TOP", parent, "TOP", 0, -38)
    refresh:SetScript("OnClick", function() addon:Refresh() end)
    self.controlButtons.Refresh = refresh
    self:RegisterWishElement(refresh)

    local test = makeButton("XyTrackerFrameTest", parent, "测试25条", 100, 17)
    test:SetPoint("TOPLEFT", parent, "TOPLEFT", 92, -38)
    test:SetScript("OnClick", function() addon:CreateTestData() end)
    self.controlButtons.Test = test
    self:RegisterWishElement(test)
end

function UI:CreateHeaders(parent)
    local headers = {
        {"name", "角色名", 100},
        {"class", "职业", 60},
        {"xy", "许愿", 135},
        {"dkp", "分数", 40},
        {"option", "操作", 48},
        {"finish", "达成", 48},
    }
    local x = 8
    local i
    self.headers = {}
    for i = 1, #headers do
        local data = headers[i]
        local button = CreateFrame("Button", "XyHeader" .. data[1], parent, "BackdropTemplate")
        button:SetWidth(data[3])
        button:SetHeight(28)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -90)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        button:SetBackdropColor(0.03, 0.03, 0.03, 0.90)
        button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        if data[1] ~= "option" then
            button:SetScript("OnClick", function() self:Sort(data[1]) end)
        end
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", button, "LEFT", 8, 0)
        text:SetFont("Fonts\\ARKai_T.ttf", 11, "OUTLINE")
        text:SetText(data[2])
        text:SetTextColor(0.95, 0.95, 0.95)
        button.headerText = text
        button:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.08, 0.13, 0.18, 0.95)
            self:SetBackdropBorderColor(0.45, 0.60, 0.72, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.03, 0.03, 0.03, 0.90)
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            self.headerText:ClearAllPoints()
            self.headerText:SetPoint("LEFT", self, "LEFT", 8, 0)
        end)
        button:SetScript("OnMouseDown", function(self)
            self:SetBackdropColor(0.02, 0.08, 0.12, 1)
            self:SetBackdropBorderColor(0.70, 0.78, 0.85, 1)
            self.headerText:ClearAllPoints()
            self.headerText:SetPoint("LEFT", self, "LEFT", 9, -1)
        end)
        button:SetScript("OnMouseUp", function(self)
            self.headerText:ClearAllPoints()
            self.headerText:SetPoint("LEFT", self, "LEFT", 8, 0)
            if self:IsMouseOver() then
                self:SetBackdropColor(0.08, 0.13, 0.18, 0.95)
                self:SetBackdropBorderColor(0.45, 0.60, 0.72, 1)
            else
                self:SetBackdropColor(0.03, 0.03, 0.03, 0.90)
                self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            end
        end)
        self.headers[data[1]] = button
        self:RegisterWishElement(button)
        x = x + data[3] + 2
    end
end

function UI:CreateList(parent)
    local scroll = CreateFrame("ScrollFrame", "XyListScrollFrame", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, -118)
    -- 21行 × 25px = 525px，使滚动条下箭头与最后一行底部对齐。
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 57)
    self.scroll = scroll
    self:RegisterWishElement(scroll)

    local i
    for i = 1, ROW_COUNT do
        local row = CreateFrame("Frame", "XyFrameListButton" .. i, scroll)
        row:SetWidth(421)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 5, -((i - 1) * ROW_HEIGHT))

        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
        background:SetAllPoints(row)
        row.background = background
        row.isHovered = false

        local name = makeLabel(row, "XyRow" .. i .. "Name", 95, 20)
        name:SetPoint("LEFT", row, "LEFT", 4, 0)
        local class = makeLabel(row, "XyRow" .. i .. "Class", 50, 20)
        class:SetPoint("LEFT", name, "RIGHT", 5, 0)
        local wish = makeLabel(row, "XyRow" .. i .. "Wish", 135, 20)
        wish:SetPoint("LEFT", class, "RIGHT", 5, 0)
        local dkp = makeLabel(row, "XyRow" .. i .. "DKP", 30, 20)
        dkp:SetPoint("LEFT", wish, "RIGHT", 5, 0)
        dkp:SetJustifyH("CENTER")
        name:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        class:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        wish:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        dkp:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        name:SetTextColor(1, 0.82, 0)
        wish:SetTextColor(0.71, 0.28, 0.96)

        local plus = makeButton("XyRow" .. i .. "Plus", row, "+", 16, 16)
        plus:SetPoint("LEFT", self.headers.option, "LEFT", 4, 0)
        plus:SetPoint("TOP", row, "TOP", 0, -4)
        plus:SetScript("OnClick", function()
            local record = self.rows[i].record
            if record then self:ShowDKPPopup("add", record.name) end
        end)
        local minus = makeButton("XyRow" .. i .. "Minus", row, "-", 16, 16)
        minus:SetPoint("LEFT", plus, "RIGHT", 0, 0)
        minus:SetScript("OnClick", function()
            local record = self.rows[i].record
            if record then self:ShowDKPPopup("minus", record.name) end
        end)

        local finish = CreateFrame("CheckButton", "XyRow" .. i .. "Finish", row, "UICheckButtonTemplate")
        finish:SetWidth(32)
        finish:SetHeight(32)
        finish:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        finish:SetScript("OnClick", function(button)
            local record = self.rows[i].record
            if record then addon:MarkFinished(record.name, button:GetChecked() and 1 or 0) end
        end)

        row.nameText = name
        row.classText = class
        row.wishText = wish
        row.dkpText = dkp
        row.finishButton = finish
        row.plusButton = plus
        row.minusButton = minus
        row:SetScript("OnEnter", function()
            row.isHovered = true
            row.background:SetVertexColor(0.25, 0.20, 0.05, 0.90)
            local record = self.rows[i].record
            if record and record.xy ~= addon.unwished then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:SetText(record.xy)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            row.isHovered = false
            row.background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
            GameTooltip:Hide()
        end)
        row:Hide()
        self.rows[i] = {
            frame = row,
            record = nil,
            nameText = name,
            classText = class,
            wishText = wish,
            dkpText = dkp,
            finishButton = finish,
            plusButton = plus,
            minusButton = minus,
        }
    end

    scroll:SetScript("OnVerticalScroll", function(frame, offset)
        FauxScrollFrame_OnVerticalScroll(frame, offset, ROW_HEIGHT, function() self:Update() end)
    end)
end

function UI:CreateStatus(parent)
    local status = makeLabel(parent, "XyTrackerFrameStatusText", 300, 20)
    status:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
    status:SetTextColor(1, 0.82, 0)
    self.status = status
    self:RegisterWishElement(status)
    local protocol = makeLabel(parent, "XyTrackerFrameProtocolText", 72, 20)
    protocol:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -132, 10)
    protocol:SetJustifyH("CENTER")
    self.protocolStatus = protocol
    self:RegisterWishElement(protocol)
    local version = makeLabel(parent, "XyTrackerFrameVersionText", 120, 20)
    version:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
    version:SetJustifyH("RIGHT")
    version:SetText("Version:" .. xy_version)
    version:SetTextColor(1, 0.82, 0)
    self.version = version
end

function UI:UpdateProtocolStatus()
    if not self.protocolStatus then return end
    if addon.protocolMode == "new" and addon.protocolConfirmed then
        self.protocolStatus:SetText("新协议")
        self.protocolStatus:SetTextColor(0.20, 1, 0.20)
    else
        self.protocolStatus:SetText("老协议")
        self.protocolStatus:SetTextColor(1, 0.15, 0.10)
    end
end

function UI:CreateRollPage(parent)
    local page = CreateFrame("Frame", "XyRollPage", parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -34)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 34)
    page:Hide()
    self.rollPage = page

    local roll = makeButton("XyRollStartButton", page, "开始", 64, 33)
    roll:SetPoint("TOPLEFT", page, "TOPLEFT", 2, 0)
    roll:SetScript("OnClick", function() addon:StartRollTracking() end)
    self.rollStartButton = roll

    local stop = makeButton("XyRollStopButton", page, "倒计时通报", 105, 33)
    stop:SetPoint("LEFT", roll, "RIGHT", 5, 0)
    stop:SetScript("OnClick", function() addon:StopRollTracking() end)
    self.rollStopButton = stop

    local clear = makeButton("XyRollClearButton", page, "清空", 64, 33)
    clear:SetPoint("LEFT", stop, "RIGHT", 5, 0)
    clear:SetScript("OnClick", function() addon:ClearRollData() end)
    self.rollClearButton = clear

    local hint = makeLabel(page, nil, 330, 20)
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -22)
    hint:SetText("Roll点跟踪器")
    hint:SetTextColor(0.75, 0.75, 0.75)
    hint:Hide()

    local notify = CreateFrame("CheckButton", "XyRollRepeatCheckButton", page, "UICheckButtonTemplate")
    notify:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
    notify:SetScale(0.8)
    notify.text:SetText("重复Roll通知")
    notify:SetChecked(addon.rollRepeat)
    notify:SetScript("OnClick", function(button)
        addon.rollRepeat = button:GetChecked() and true or false
        XyRollSettings = XyRollSettings or {}
        XyRollSettings.repeatRoll = addon.rollRepeat and 1 or 0
    end)
    self.rollRepeatCheck = notify

    local dropdown = CreateFrame("Frame", "XyRollChannelDropdown", page, "UIDropDownMenuTemplate")
    dropdown:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 8)
    dropdown:SetScale(0.8)
    UIDropDownMenu_SetWidth(dropdown, 100)
    local function dropdownOnClick(button)
        addon.rollChannelID = button:GetID()
        XyRollSettings = XyRollSettings or {}
        XyRollSettings.channelID = addon.rollChannelID
        UIDropDownMenu_SetSelectedID(dropdown, addon.rollChannelID)
        UIDropDownMenu_SetText(dropdown, button:GetText())
    end
    local function dropdownInitialize()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "队伍"
        info.func = dropdownOnClick
        info.checked = addon.rollChannelID == 1
        UIDropDownMenu_AddButton(info)
        info = UIDropDownMenu_CreateInfo()
        info.text = "团队"
        info.func = dropdownOnClick
        info.checked = addon.rollChannelID == 2
        UIDropDownMenu_AddButton(info)
    end
    UIDropDownMenu_Initialize(dropdown, dropdownInitialize)
    UIDropDownMenu_SetSelectedID(dropdown, addon.rollChannelID or 2)
    UIDropDownMenu_SetText(dropdown, addon.rollChannelID == 1 and "队伍" or "团队")
    self.rollDropdown = dropdown

    local headers = {
        {"玩家", 280, 8}, {"Roll点", 70, 330},
    }
    self.rollHeaderLabels = {}
    local i
    for i = 1, #headers do
        local label = makeLabel(page, nil, headers[i][2], 24)
        label:SetPoint("TOPLEFT", page, "TOPLEFT", headers[i][3], -42)
        label:SetHeight(28)
        label:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        label:SetText(headers[i][1])
        label:SetTextColor(1, 0.82, 0)
        self.rollHeaderLabels[i] = label
    end

    local scroll = CreateFrame("ScrollFrame", "XyRollScrollFrame", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -66)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 34)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(405)
    scrollChild:SetHeight(ROLL_ROW_COUNT * ROW_HEIGHT)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnVerticalScroll", function(frame, offset)
        self:UpdateRollPage()
    end)
    self.rollScroll = scroll
    self.rollScrollChild = scrollChild

    self.rollRows = {}
    for i = 1, ROLL_ROW_COUNT do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(405)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
        background:SetAllPoints(row)

        local player = makeLabel(row, nil, 280, 20)
        player:SetPoint("LEFT", row, "LEFT", 0, 0)
        local value = makeLabel(row, nil, 70, 20)
        value:SetPoint("LEFT", player, "RIGHT", 12, 0)
        value:SetJustifyH("CENTER")
        player:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        value:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        player:SetTextColor(0.30, 1, 0.30)
        value:SetTextColor(1, 0.82, 0)
        player:SetWidth(280)
        row.playerText = player
        row.valueText = value
        row:Hide()
        self.rollRows[i] = row
    end

    local empty = makeLabel(page, nil, 400, 24)
    empty:SetText("尚未开始 Roll 或暂无结果")
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -70)
    empty:SetTextColor(0.75, 0.75, 0.75)
    self.rollEmpty = empty

    local highest = makeLabel(page, nil, 190, 20)
    highest:SetPoint("BOTTOM", parent, "BOTTOM", 0, 35)
    highest:SetJustifyH("CENTER")
    highest:SetTextColor(1, 0.82, 0)
    self.rollHighestText = highest
end

function UI:LayoutRollPage(compact)
    if not self.rollPage then return end
    local rowWidth = compact and 200 or 405
    local playerWidth = compact and 105 or 280
    local headerValueX = compact and 125 or 330
    local i
    self.rollScroll:ClearAllPoints()
    self.rollScroll:SetPoint("TOPLEFT", self.rollPage, "TOPLEFT", 8, -66)
    self.rollScroll:SetPoint("BOTTOMRIGHT", self.rollPage, "BOTTOMRIGHT", -28, 34)
    if self.rollHeaderLabels then
        self.rollHeaderLabels[1]:SetWidth(playerWidth)
        self.rollHeaderLabels[1]:ClearAllPoints()
        self.rollHeaderLabels[1]:SetPoint("TOPLEFT", self.rollPage, "TOPLEFT", 8, -42)
        self.rollHeaderLabels[2]:SetWidth(70)
        self.rollHeaderLabels[2]:ClearAllPoints()
        self.rollHeaderLabels[2]:SetPoint("TOPLEFT", self.rollPage, "TOPLEFT", headerValueX, -42)
    end
    for i = 1, #self.rollRows do
        self.rollRows[i]:SetWidth(rowWidth)
        self.rollRows[i].playerText:SetWidth(playerWidth)
        self.rollRows[i].valueText:ClearAllPoints()
        self.rollRows[i].valueText:SetPoint("LEFT", self.rollRows[i].playerText, "RIGHT", 12, 0)
        self.rollRows[i].valueText:SetWidth(70)
    end
    self.rollScrollChild:SetWidth(rowWidth)
    self.rollEmpty:SetWidth(compact and 220 or 400)
    self.rollHighestText:SetWidth(compact and 220 or 400)
end

function UI:CreateHistoryPage(parent)
    local page = CreateFrame("Frame", "XyHistoryPage", parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -34)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 34)
    page:Hide()
    self.historyPage = page

    local clear = makeButton("XyHistoryClearButton", page, "清空历史", 84, 20)
    clear:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, 0)
    clear:SetScript("OnClick", function() addon:ClearWishHistory() end)
    self.historyClearButton = clear

    local export = makeButton("XyHistoryExportButton", page, "导出许愿表", 100, 20)
    export:SetPoint("RIGHT", clear, "LEFT", -4, 0)
    export:SetScript("OnClick", function() self:ShowHistoryExport() end)
    self.historyExportButton = export

    local hint = makeLabel(page, nil, 300, 20)
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", HISTORY_RIGHT_OFFSET, 0)
    hint:SetText("请选择左侧重置时间，查看重置前保存的许愿内容")
    hint:SetTextColor(0.75, 0.75, 0.75)
    self.historyHint = hint

    local resetTitle = makeLabel(page, nil, HISTORY_LEFT_WIDTH, 24)
    resetTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -42)
    resetTitle:SetText("重置日期")
    resetTitle:SetTextColor(1, 1, 1)

    local delete = makeButton("XyHistoryDeleteButton", page, "删除记录", 64, 20)
    delete:SetPoint("TOPLEFT", page, "TOPLEFT", HISTORY_LEFT_WIDTH - 68, -42)
    delete:SetScript("OnClick", function() self:DeleteSelectedResetHistory() end)
    self.historyDeleteButton = delete

    local resetScroll = CreateFrame("ScrollFrame", "XyResetHistoryScrollFrame", page, "UIPanelScrollFrameTemplate")
    resetScroll:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -66)
    resetScroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", 8 + HISTORY_LEFT_WIDTH, 34)
    local resetScrollChild = CreateFrame("Frame", nil, resetScroll)
    resetScrollChild:SetWidth(HISTORY_LEFT_WIDTH - 20)
    resetScrollChild:SetHeight(RESET_HISTORY_ROW_COUNT * ROW_HEIGHT)
    resetScroll:SetScrollChild(resetScrollChild)
    self.resetHistoryScroll = resetScroll
    self.resetHistoryScrollChild = resetScrollChild
    self.resetHistoryRows = {}
    local i
    for i = 1, RESET_HISTORY_ROW_COUNT do
        local row = CreateFrame("Button", nil, resetScrollChild)
        row:SetWidth(HISTORY_LEFT_WIDTH - 10)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", resetScrollChild, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:EnableMouse(true)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
        background:SetAllPoints(row)
        row.background = background
        local text = makeLabel(row, nil, HISTORY_LEFT_WIDTH - 20, 20)
        text:SetPoint("LEFT", row, "LEFT", 6, 0)
        text:SetFont("Fonts\\ARKai_T.ttf", 13, "OUTLINE")
        text:SetTextColor(1, 0.82, 0)
        row.timeText = text
        row:SetScript("OnClick", function()
            if row.historyIndex then self:SelectResetHistory(row.historyIndex) end
        end)
        row:Hide()
        self.resetHistoryRows[i] = row
    end

    local resetEmpty = makeLabel(page, nil, HISTORY_LEFT_WIDTH - 10, 24)
    resetEmpty:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -70)
    resetEmpty:SetText("暂无重置记录")
    resetEmpty:SetTextColor(0.75, 0.75, 0.75)
    self.resetHistoryEmpty = resetEmpty

    local headers = {
        {"角色名", 100, 17}, {"职业", 70, 122},
        {"许愿内容", 180, 197}, {"状态", 60, 382},
    }
    for i = 1, #headers do
        local label = makeLabel(page, nil, headers[i][2], 24)
        label:SetPoint("TOPLEFT", page, "TOPLEFT", HISTORY_RIGHT_OFFSET + headers[i][3], -42)
        label:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        label:SetText(headers[i][1])
        label:SetTextColor(1, 1, 1)
    end

    local scroll = CreateFrame("ScrollFrame", "XyHistoryScrollFrame", page, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", HISTORY_RIGHT_OFFSET + 8, -66)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 34)
    scroll:SetScript("OnVerticalScroll", function(frame, offset)
        FauxScrollFrame_OnVerticalScroll(frame, offset, ROW_HEIGHT, function() self:UpdateHistoryPage() end)
    end)
    self.historyScroll = scroll

    self.historyRows = {}
    for i = 1, ROW_COUNT do
        local row = CreateFrame("Frame", nil, scroll)
        row:SetWidth(HISTORY_ROW_WIDTH)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 5, -((i - 1) * ROW_HEIGHT))
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Buttons\\WHITE8X8")
        background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
        background:SetAllPoints(row)

        local name = makeLabel(row, nil, 100, 20)
        name:SetPoint("LEFT", row, "LEFT", 4, 0)
        local class = makeLabel(row, nil, 70, 20)
        class:SetPoint("LEFT", name, "RIGHT", 5, 0)
        local wish = makeLabel(row, nil, 180, 20)
        wish:SetPoint("LEFT", class, "RIGHT", 5, 0)
        local state = makeLabel(row, nil, 60, 20)
        state:SetPoint("LEFT", wish, "RIGHT", 5, 0)
        name:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        class:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        wish:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
        state:SetFont("Fonts\\ARKai_T.ttf", 12, "OUTLINE")
        name:SetTextColor(1, 0.82, 0)
        wish:SetTextColor(0.71, 0.28, 0.96)
        row.nameText = name
        row.classText = class
        row.wishText = wish
        row.stateText = state
        row:Hide()
        self.historyRows[i] = row
    end

    local empty = makeLabel(page, nil, 400, 24)
    empty:SetPoint("TOPLEFT", page, "TOPLEFT", HISTORY_RIGHT_OFFSET + 8, -70)
    empty:SetText("暂无历史许愿记录")
    empty:SetTextColor(0.75, 0.75, 0.75)
    self.historyEmpty = empty
end

function UI:UpdateRollPage()
    if not self.rollPage then return end
    local results = addon.rollResults or {}
    local teamAvailable = addon:IsRollTeamAvailable()
    self.rollScrollChild:SetHeight(math.max(#results, 1) * ROW_HEIGHT)
    self.rollStartButton:SetEnabled(teamAvailable and not addon.rollTracking and not addon.rollCountingDown)
    self.rollStopButton:SetEnabled(teamAvailable and addon.rollTracking and not addon.rollCountingDown)
    self.rollRepeatCheck:SetEnabled(teamAvailable)
    local maxRoll = 0
    local maxPlayers = {}
    local i
    for i = 1, #results do
        if results[i].roll > maxRoll then
            maxRoll = results[i].roll
            maxPlayers = {results[i].player}
        elseif results[i].roll == maxRoll then
            table.insert(maxPlayers, results[i].player)
        end
    end
    for i = 1, ROLL_ROW_COUNT do
        local row = self.rollRows[i]
        local data = results[i]
        if data then
            row:Show()
            row.playerText:SetText(data.player)
            row.valueText:SetText(data.roll)
        else
            row:Hide()
        end
    end
    if #results == 0 then self.rollEmpty:Show() else self.rollEmpty:Hide() end
    if maxRoll > 0 then
        self.rollHighestText:SetText((#maxPlayers > 1 and "当前并列最高: " or "当前最高: ") .. table.concat(maxPlayers, ", ") .. " - " .. maxRoll)
    else
        self.rollHighestText:SetText("")
    end
end

function UI:SelectResetHistory(index)
    local history = XyResetHistory or {}
    if not history[index] then return end
    self.historySelectedIndex = index
    self:UpdateHistoryPage()
end

function UI:DeleteSelectedResetHistory()
    local index = self.historySelectedIndex
    if not index or not XyResetHistory or not XyResetHistory[index] then
        addon:Print("请先选择要删除的重置日期。")
        return
    end
    self.historyPendingDeleteIndex = index
    self:ShowHistoryDeleteConfirm()
end

function UI:UpdateHistoryPage()
    if not self.historyPage then return end
    local resetHistory = XyResetHistory or {}
    local i

    if #resetHistory > 0 then
        if not self.historySelectedIndex or not resetHistory[self.historySelectedIndex] then
            self.historySelectedIndex = 1
        end
    else
        self.historySelectedIndex = nil
    end

    if self.historyDeleteButton then
        self.historyDeleteButton:SetEnabled(self.historySelectedIndex ~= nil and
            resetHistory[self.historySelectedIndex] ~= nil)
    end

    self.resetHistoryScrollChild:SetHeight(math.max(#resetHistory, 1) * ROW_HEIGHT)
    for i = 1, RESET_HISTORY_ROW_COUNT do
        local row = self.resetHistoryRows[i]
        local data = resetHistory[i]
        if data then
            row:Show()
            row.historyIndex = i
            row.timeText:SetText(data.time or "")
            if i == self.historySelectedIndex then
                row.background:SetVertexColor(0.25, 0.20, 0.05, 0.90)
            else
                row.background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
            end
        else
            row.historyIndex = nil
            row:Hide()
        end
    end
    if #resetHistory == 0 then self.resetHistoryEmpty:Show() else self.resetHistoryEmpty:Hide() end

    local history
    local selected = self.historySelectedIndex and resetHistory[self.historySelectedIndex]
    if selected then
        history = selected.records or {}
        self.historyHint:SetText("重置时间: " .. selected.time .. "（保存 " .. #history .. " 条记录）")
    else
        history = XyWishHistory or {}
        self.historyHint:SetText("每次提交许愿都会保留一条历史记录")
    end

    FauxScrollFrame_Update(self.historyScroll, #history, ROW_COUNT, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(self.historyScroll)
    for i = 1, ROW_COUNT do
        local row = self.historyRows[i]
        local data = history[offset + i]
        if data then
            row:Show()
            row.nameText:SetText(data.name or "")
            local class = data.class or ""
            row.classText:SetText(class)
            local r, g, b = colorFromString(addon:ClassColor(class))
            row.classText:SetTextColor(r, g, b)
            row.wishText:SetText(data.xy or addon.unwished)
            row.stateText:SetText(data.finish == 1 and "已达成" or "未达成")
            row.stateText:SetTextColor(data.finish == 1 and 0.30 or 0.75, data.finish == 1 and 1 or 0.75, 0.30)
        else
            row:Hide()
        end
    end
    if #history == 0 then self.historyEmpty:Show() else self.historyEmpty:Hide() end
end

function UI:CreateRelogPrompt()
    if self.relogPromptFrame then return end

    -- 不写入 StaticPopupDialogs。该全局表会被暴雪游戏菜单和安全回调共享，
    -- 插件写入后可能使小退按钮的 callback() 变成 tainted，从而触发
    -- ADDON_ACTION_FORBIDDEN。这里使用插件自己的普通 Frame。
    local frame = makePanel("XyRelogClearPromptFrame", UIParent, 360, 150)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    makeMovable(frame)
    frame:Hide()

    local title = makeLabel(frame, nil, 300, 24)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetText("退出确认")
    title:SetTextColor(1, 0.82, 0)

    local message = makeLabel(frame, nil, 320, 42)
    message:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -46)
    message:SetText("检测到你刚刚退出过游戏。是否清空本地许愿内容？")
    message:SetTextColor(1, 1, 1)
    message:SetJustifyV("TOP")

    local clear = makeButton("XyRelogClearPromptAccept", frame, "清空许愿", 104, 24)
    clear:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 38, 16)
    clear:SetScript("OnClick", function()
        frame:Hide()
        addon:ClearLocalWishes()
        addon:Print("本地许愿内容已清空，角色和 DKP 数据已保留。")
        addon:FinishRelogPrompt()
    end)

    local keepPrompt = function()
        frame:Hide()
        addon:Print("已保留本地许愿数据。")
        addon:FinishRelogPrompt()
    end
    local keep = makeButton("XyRelogClearPromptCancel", frame, "保留数据", 104, 24)
    keep:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -38, 16)
    keep:SetScript("OnClick", keepPrompt)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", keepPrompt)

    self.relogPromptFrame = frame
end

function UI:ShowRelogPrompt()
    if not self.relogPromptFrame then self:CreateRelogPrompt() end
    if not self.relogPromptFrame then return false end
    self.relogPromptFrame:Show()
    return true
end

function UI:CreateHistoryDeleteConfirm()
    if self.historyDeleteConfirmFrame then return end

    local frame = makePanel("XyHistoryDeleteConfirmFrame", UIParent, 340, 140)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    makeMovable(frame)
    frame:Hide()

    local title = makeLabel(frame, nil, 280, 24)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetText("删除历史记录")
    title:SetTextColor(1, 0.82, 0)

    local message = makeLabel(frame, nil, 300, 36)
    message:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -46)
    message:SetText("确定删除当前选中的重置许愿记录吗？此操作不可恢复。")
    message:SetTextColor(1, 1, 1)
    message:SetJustifyV("TOP")

    local deleteHistory = function()
        local index = self.historyPendingDeleteIndex
        self.historyPendingDeleteIndex = nil
        frame:Hide()
        addon:DeleteResetHistory(index)
    end
    local delete = makeButton("XyHistoryDeleteConfirmAccept", frame, "删除", 82, 24)
    delete:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 52, 16)
    delete:SetScript("OnClick", deleteHistory)

    local cancelHistory = function()
        self.historyPendingDeleteIndex = nil
        frame:Hide()
    end
    local cancel = makeButton("XyHistoryDeleteConfirmCancel", frame, "取消", 82, 24)
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -52, 16)
    cancel:SetScript("OnClick", cancelHistory)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", cancelHistory)

    self.historyDeleteConfirmFrame = frame
end

function UI:ShowHistoryDeleteConfirm()
    if not self.historyDeleteConfirmFrame then self:CreateHistoryDeleteConfirm() end
    if self.historyDeleteConfirmFrame then self.historyDeleteConfirmFrame:Show() end
end

function UI:CreatePopups()
    self:CreateRelogPrompt()
    self:CreateHistoryDeleteConfirm()
    self:CreateDKPPopup("add", "XyAddDkpFrame", "增加 DKP")
    self:CreateDKPPopup("minus", "XyMinusDkpFrame", "扣除 DKP")

    local frame = makePanel("XyDefaultDkpFrame", UIParent, 230, 150)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    makeMovable(frame)
    frame:Hide()
    local title = makeLabel(frame, nil, 190, 24)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetText("设置初始化 DKP")
    local edit = CreateFrame("EditBox", "XyDefaultDkpEdit", frame, "InputBoxTemplate")
    edit:SetWidth(100)
    edit:SetHeight(24)
    edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)
    edit:SetNumeric(true)
    edit:SetAutoFocus(false)
    local ok = makeButton("XyDefaultDkpOK", frame, "确定", 72, 22)
    ok:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    ok:SetScript("OnClick", function()
        addon:SetDefaultDKP(edit:GetNumber())
        frame:Hide()
    end)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    self.defaultFrame = frame

    local export = makePanel("XyExportFrame", UIParent, 520, 420)
    export:SetPoint("CENTER")
    export:SetFrameStrata("DIALOG")
    makeMovable(export)
    export:Hide()
    local exportEdit = CreateFrame("EditBox", "XyExportEdit", export, "InputBoxTemplate")
    exportEdit:SetWidth(490)
    exportEdit:SetHeight(360)
    exportEdit:SetPoint("TOPLEFT", export, "TOPLEFT", 15, -15)
    exportEdit:SetMultiLine(true)
    exportEdit:SetAutoFocus(false)
    exportEdit:SetFontObject("ChatFontNormal")
    local exportClose = CreateFrame("Button", nil, export, "UIPanelCloseButton")
    exportClose:SetPoint("TOPRIGHT", export, "TOPRIGHT", -2, -2)
    self.exportFrame = export
    self.exportEdit = exportEdit

    local historyExport = makePanel("XyHistoryExportFrame", UIParent, 560, 470)
    historyExport:SetPoint("CENTER")
    historyExport:SetFrameStrata("DIALOG")
    makeMovable(historyExport)
    historyExport:Hide()
    local historyTitle = makeLabel(historyExport, nil, 430, 24)
    historyTitle:SetPoint("TOPLEFT", historyExport, "TOPLEFT", 15, -12)
    historyTitle:SetText("导出历史许愿表")
    historyTitle:SetTextColor(1, 0.82, 0)
    local historyEdit = CreateFrame("EditBox", "XyHistoryExportEdit", historyExport, "InputBoxTemplate")
    historyEdit:SetWidth(530)
    historyEdit:SetHeight(390)
    historyEdit:SetPoint("TOPLEFT", historyExport, "TOPLEFT", 15, -42)
    historyEdit:SetMultiLine(true)
    historyEdit:SetAutoFocus(false)
    historyEdit:SetFontObject("ChatFontNormal")
    local historyClose = CreateFrame("Button", nil, historyExport, "UIPanelCloseButton")
    historyClose:SetPoint("TOPRIGHT", historyExport, "TOPRIGHT", -2, -2)
    historyExport:SetScript("OnHide", function() historyEdit:ClearFocus() end)
    self.historyExportFrame = historyExport
    self.historyExportEdit = historyEdit

    local about = makePanel("XyAboutFrame", UIParent, 280, 300)
    about:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 0, 0)
    about:SetFrameStrata("HIGH")
    about:SetClampedToScreen(true)
    about:SetMovable(true)
    about:RegisterForDrag("LeftButton")
    about:SetScript("OnDragStart", function()
        self.frame:StartMoving()
    end)
    about:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
    end)
    about:Hide()
    local aboutTitle = makeLabel(about, "XyAboutTitle", 240, 24)
    aboutTitle:SetPoint("TOPLEFT", about, "TOPLEFT", 10, -10)
    aboutTitle:SetText("感 谢：")
    aboutTitle:SetTextColor(1, 0.82, 0)
    local aboutText = about:CreateFontString("XyAboutText", "OVERLAY", "GameFontNormalSmall")
    aboutText:SetWidth(250)
    aboutText:SetHeight(255)
    aboutText:SetPoint("TOPLEFT", about, "TOPLEFT", 10, -30)
    aboutText:SetFont("Fonts\\ARKai_T.ttf", 14, "OUTLINE")
    aboutText:SetTextColor(1, 0.49, 0.04)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetJustifyV("TOP")
    aboutText:SetText([[
|cffABD473B站-老胡聊聊天|r
|cffABD473B站-Wow无道暴君(乌龟服)|r
|CffF58CBA铁血二 - 乘风破浪的姐姐们工会(CN)|r
|cffFFFFFF铁血二 - 叶子姐姐(会长)|r
铁血二 - 为了丨部落
铁血二 - 冰淇淋姐姐
铁血二 - 一条明
铁血二 - 沃特儿發
铁血二 - Autobots
铁血二 - 围裙爸爸
铁血二 - 南通车贩子
author:达蒙
    ]])
    local aboutClose = CreateFrame("Button", nil, about, "UIPanelCloseButton")
    aboutClose:SetPoint("TOPRIGHT", about, "TOPRIGHT", -2, -2)
    self.aboutFrame = about
end

function UI:CreateDKPPopup(mode, name, titleText)
    local frame = makePanel(name, UIParent, 220, 145)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    makeMovable(frame)
    frame:Hide()
    local title = makeLabel(frame, nil, 180, 22)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetText(titleText)
    local member = makeLabel(frame, nil, 180, 20)
    member:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    local edit = CreateFrame("EditBox", name .. "Point", frame, "InputBoxTemplate")
    edit:SetWidth(90)
    edit:SetHeight(24)
    edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68)
    edit:SetNumeric(true)
    edit:SetAutoFocus(false)
    local ok = makeButton(name .. "OK", frame, "确定", 72, 22)
    ok:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    local submit = function()
        local amount = edit:GetNumber()
        if mode == "add" then addon:AddDKP(frame.memberName, amount) else addon:MinusDKP(frame.memberName, amount) end
        frame:Hide()
    end
    ok:SetScript("OnClick", submit)
    edit:SetScript("OnEnterPressed", submit)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.memberText = member
    frame.edit = edit
    self[mode .. "Frame"] = frame
end

function UI:ShowDKPPopup(mode, name)
    local frame = self[mode .. "Frame"]
    if not frame or not self.operator then return end
    frame.memberName = name
    frame.memberText:SetText("玩家：" .. name)
    frame.edit:SetText("")
    frame:Show()
    frame.edit:SetFocus()
end

function UI:ShowDefaultPopup()
    if not self.operator then return end
    self.defaultFrame:Show()
    _G["XyDefaultDkpEdit"]:SetText(tostring(DefaultDKP))
    _G["XyDefaultDkpEdit"]:SetFocus()
end

function UI:ShowExport()
    if not self.exportFrame then return end
    self.exportEdit:SetText(addon:ExportData())
    self.exportFrame:Show()
end

function UI:ShowHistoryExport()
    if not self.historyExportFrame or not self.historyExportEdit then return end
    local index = self.historySelectedIndex
    if not index or not XyResetHistory or not XyResetHistory[index] then
        addon:Print("请先选择左侧的重置日期。")
        return
    end
    local text = addon:ExportHistoryData(index)
    self.historyExportEdit:SetText(text)
    self.historyExportFrame:Show()
    self.historyExportEdit:SetFocus()
    self.historyExportEdit:HighlightText()
end

function UI:ToggleAbout()
    if self.aboutFrame:IsVisible() then self.aboutFrame:Hide() else self.aboutFrame:Show() end
end

function UI:UpdateMinimapButtonPosition()
    if not self.minimapButton or not Minimap then return end
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then return end
    local angle = tonumber(XyMinimapAngle) or 0
    local radius = (Minimap:GetWidth() or 140) * 0.5 + 6
    local radians = math.rad(angle)
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(radians) * radius, math.sin(radians) * radius)
end

function UI:CreateMinimapButton()
    local button = CreateFrame("Button", "XyButtonFrame", Minimap)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetFrameStrata("LOW")
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_01")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.dragMoved = false
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        XyMinimapAngle = self.dragAngle or XyMinimapAngle or 0
        self.suppressClick = self.dragMoved
        self:ClearAllPoints()
        UI:UpdateMinimapButtonPosition()
    end)
    button:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        if not cursorX or not cursorY or not centerX or not centerY then return end
        cursorX, cursorY = cursorX / scale, cursorY / scale
        local dx, dy = cursorX - centerX, cursorY - centerY
        if math.abs(dx) + math.abs(dy) > 4 then self.dragMoved = true end
        self.dragAngle = math.deg(math.atan2(dy, dx))
        UI:UpdateMinimapButtonPosition()
    end)
    button:SetScript("OnClick", function(self)
        if self.suppressClick then
            self.suppressClick = false
            return
        end
        UI:Toggle()
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText("开启/关闭许愿监视")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsVisible() then
        self.frame:Hide()
        if self.aboutFrame then self.aboutFrame:Hide() end
    else
        if addon.BeginProtocolNegotiation then addon:BeginProtocolNegotiation() end
        self.frame:Show()
        self:Update()
    end
end

function UI:UpdatePermissions(isOperator)
    self.operator = isOperator and true or false
    if not self.controlButtons then return end
    local wishVisible = self.activeTab == "wish"
    local i
    for _, button in pairs(self.controlButtons) do
        if self.operator and wishVisible then button:Show() else button:Hide() end
    end
    if self.controlButtons.Refresh then
        if wishVisible then self.controlButtons.Refresh:Show() else self.controlButtons.Refresh:Hide() end
    end
    if self.controlButtons.Test then
        if wishVisible then self.controlButtons.Test:Show() else self.controlButtons.Test:Hide() end
    end
    for i = 1, #self.rows do
        if self.operator and wishVisible then
            self.rows[i].plusButton:Show()
            self.rows[i].minusButton:Show()
        else
            self.rows[i].plusButton:Hide()
            self.rows[i].minusButton:Hide()
        end
        self.rows[i].finishButton:SetEnabled(self.operator)
    end
end

function UI:Sort(field)
    local order = SORT_STATE[field] or "asc"
    SORT_STATE[field] = order == "asc" and "desc" or "asc"
    table.sort(XyArray, function(left, right)
        local a, b = left[field], right[field]
        if field == "dkp" or field == "finish" then
            a, b = tonumber(a) or 0, tonumber(b) or 0
        else
            a, b = tostring(a or ""), tostring(b or "")
        end
        if order == "asc" then return a < b else return a > b end
    end)
    self:Update()
end

function UI:Update()
    if not self.frame then return end
    self:UpdateProtocolStatus()
    local total = #XyArray
    local wished = 0
    local i
    for i = 1, total do
        if XyArray[i].xy ~= addon.unwished then wished = wished + 1 end
    end
    if self.activeTab == "roll" then
        self.title:SetWidth(220)
        self.title:SetText("Roll Tracker")
    else
        self.title:SetWidth(420)
        self.title:SetText(WINDOW_TITLE)
    end
    local memberCount = IsInRaid() and GetNumGroupMembers() or 1
    if wished == 0 then
        self.status:SetText("当前共:" .. memberCount .. "人，无人许愿")
    else
        self.status:SetText("当前共:" .. memberCount .. "人，已许愿人数: " .. wished)
    end

    FauxScrollFrame_Update(self.scroll, total, ROW_COUNT, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(self.scroll)
    for i = 1, ROW_COUNT do
        local rowData = self.rows[i]
        local index = offset + i
        local record = XyArray[index]
        rowData.record = record
        if record then
            rowData.frame:Show()
            if rowData.frame.isHovered then
                rowData.frame.background:SetVertexColor(0.25, 0.20, 0.05, 0.90)
            else
                rowData.frame.background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
            end
            rowData.nameText:SetText(record.name)
            rowData.classText:SetText(record.class)
            local r, g, b = colorFromString(addon:ClassColor(record.class))
            rowData.classText:SetTextColor(r, g, b)
            rowData.wishText:SetText(record.xy)
            rowData.dkpText:SetText(record.dkp)
            rowData.finishButton:SetChecked(record.finish == 1)
            if self.operator then
                rowData.plusButton:Show()
                rowData.minusButton:Show()
            else
                rowData.plusButton:Hide()
                rowData.minusButton:Hide()
            end
            rowData.finishButton:SetEnabled(self.operator)
        else
            rowData.frame.isHovered = false
            rowData.frame.background:SetVertexColor(0.08, 0.08, 0.08, 0.75)
            rowData.frame:Hide()
        end
    end
    self:UpdateRollPage()
    self:UpdateHistoryPage()
    self:UpdatePageVisibility()
end

return addon
