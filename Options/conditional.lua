local _, addon = ...

local L = LibStub("AceLocale-3.0"):GetLocale("RotationMaster")

local AceGUI = LibStub("AceGUI-3.0")

local error, pairs = error, pairs
local ceil, min = math.ceil, math.min

-- From utils
local cleanArray, deepcopy, HideOnEscape = addon.cleanArray, addon.deepcopy, addon.HideOnEscape

--------------------------------
-- Common code
-------------------------------

local evaluateArray, evaluateSingle, printArray, printSingle, validateArray, validateSingle, usefulArray, usefulSingle

evaluateArray = function(operation, array, conditions, cache, start)
    if array ~= nil then
        for _, entry in pairs(array) do
            if entry ~= nil and entry.type ~= nil then
                local rv
                if entry.type == "AND" or entry.type == "OR" then
                    rv = evaluateArray(entry.type, entry.value, conditions, cache, start);
                else
                    rv = evaluateSingle(entry, conditions, cache, start)
                end

                if operation == "AND" and not rv then
                    return false
                elseif operation == "OR" and rv then
                    return true
                end
            end
        end
    end

    if operation == "AND" then
        return true
    elseif operation == "OR" then
        return false
    else
        error("Array evaluation with an operation other than AND or OR")
        return false
    end
end

evaluateSingle = function(value, conditions, cache, start)
    if value == nil or value.type == nil then
        return true
    end

    if value.type == "AND" or value.type == "OR" then
        return evaluateArray(value.type, value.value, conditions, cache, start)
    elseif value.type == "NOT" then
        return not evaluateSingle(value.value, conditions, cache, start)
    elseif conditions[value.type] ~= nil then
        local rv = false
        -- condition is FALSE if the condition is INVALID.
        if conditions[value.type].valid(addon.currentSpec, value) then
            rv = conditions[value.type].evaluate(value, cache, start)
        end
        -- Extra protection so we don't evaluate the print realtime
        if addon.db.profile.verbose then
            addon:verbose("COND: %s = %s", conditions[value.type].print(addon.currentSpec, value), (rv and "true" or "false"))
        end
        return rv
    else
        error("Unrecognized condition for evaluation")
        return false
    end
end

printArray = function(operation, array, conditions, spec)
    if array == nil then
        return ""
    end

    local rv = "("
    local first = true

    for _, entry in pairs(array) do
        if entry ~= nil and entry.type ~= nil then
            if first then
                first = false
            else
                rv = rv .. " " .. operation .. " "
            end

            if entry.type == "AND" or entry.type == "OR" then
                rv = rv .. printArray(entry.type, entry.value, conditions, spec)
            else
                rv = rv .. printSingle(entry, conditions, spec)
            end
        end
    end

    rv = rv .. ")"

    return rv
end

printSingle = function(value, conditions, spec)
    if value == nil or value.type == nil then
        return ""
    end

    if value.type == "AND" or value.type == "OR" then
        return  printArray(value.type, value.value, conditions, spec)
    elseif value.type == "NOT" then
        return "NOT " .. printSingle(value.value, conditions, spec)
    elseif conditions[value.type] ~= nil then
        return conditions[value.type].print(spec, value)
    else
        return L["<INVALID CONDITION>"]
    end
end

validateArray = function(_, array, conditions, spec)
    if array == nil then
        return true
    end

    for _, entry in pairs(array) do
        if entry ~= nil and entry.type ~= nil then
            local rv
            if entry.type == "AND" or entry.type == "OR" then
                rv = validateArray(entry.type, entry.value, conditions, spec)
            else
                rv = validateSingle(entry, conditions, spec)
            end
            if not rv then
                return false
            end
        end
    end

    return true
end

validateSingle = function(value, conditions, spec)
    if value == nil or value.type == nil then
        return true
    end

    if value.type == "AND" or value.type == "OR" then
        return validateArray(value.type, value.value, conditions, spec)
    elseif value.type == "NOT" then
        return validateSingle(value.value, conditions, spec)
    elseif conditions[value.type] ~= nil then
        return conditions[value.type].valid(spec, value)
    else
        return false
    end
end

usefulArray = function(_, array, conditions)
    if array == nil then
        return false
    end

    for _, entry in pairs(array) do
        if entry ~= nil and entry.type ~= nil then
            local rv
            if entry.type == "AND" or entry.type == "OR" then
                rv = usefulArray(entry.type, entry.value, conditions)
            else
                rv = usefulSingle(entry, conditions)
            end
            if rv then
                return true
            end
        end
    end

    return false
end

usefulSingle = function(value, conditions)
    if value == nil or value.type == nil then
        return false
    end

    if value.type == "AND" or value.type == "OR" then
        return usefulArray(value.type, value.value, conditions)
    elseif value.type == "NOT" then
        return usefulSingle(value.value, conditions)
    elseif conditions[value.type] ~= nil then
        return true
    else
        return false
    end
end

local function wrap(str, limit)
    limit = limit or 72
    local here = 1

    -- the "".. is there because :gsub returns multiple values
    return ""..str:gsub("(%s+)()(%S+)()",
        function(_, st, word, fi)
            if fi-here > limit then
                here = st
                return "\n"..word
            end
        end)
end

local function LayoutConditionTab(top, frame, funcs, value, selected, conditions, groups, group)
    local selectedIcon

    local function layoutIcon(icon, desc, selected, onclick)
        local description = AceGUI:Create("InteractiveLabel")
        local text = wrap(desc, 15)
        if not string.match(text, "\n") then
            text = text .. "\n"
        end
        description:SetImage(icon)
        description:SetImageSize(36, 36)
        description:SetText(text)
        description:SetJustifyH("center")
        description:SetWidth(100)
        description:SetUserData("cell", { alignV = "top", alignH = "left" })
        description:SetCallback("OnClick", function (widget)
            onclick(widget)
            top:Hide()
        end)

        if selected then
            selectedIcon = description
        end

        return description
    end

    if (group == nil) then
        local deleteicon = layoutIcon("Interface\\Icons\\Trade_Engineering", DELETE, false, function()
            if selected == "NOT" and value.value ~= nil then
                local subvalue = value.value
                cleanArray(value, { "type" })
                for k,v in pairs(subvalue) do
                    value[k] = v
                end
            else
                cleanArray(value, { "type" })
                value.type = nil
            end
        end)
        frame:AddChild(deleteicon)

        local andicon = layoutIcon("Interface\\Icons\\Spell_ChargePositive", L["AND"], selected == "AND", function()
            local subvalue
            if selected ~= "AND" and selected ~= "OR" then
                if value ~= nil and value.type ~= nil then
                    subvalue = { deepcopy(value) }
                end
                cleanArray(value, { "type" })
            end
            value.type = "AND"
            if subvalue ~= nil then
                value.value = subvalue
            end
        end)
        frame:AddChild(andicon)

        local oricon = layoutIcon("Interface\\Icons\\Spell_ChargeNegative", L["OR"], selected == "OR", function()
            local subvalue
            if selected ~= "AND" and selected ~= "OR" then
                if value ~= nil and value.type ~= nil then
                    subvalue = { deepcopy(value) }
                end
                cleanArray(value, { "type" })
            end
            value.type = "OR"
            if subvalue ~= nil then
                value.value = subvalue
            end
        end)
        frame:AddChild(oricon)

        local noticon = layoutIcon("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent", L["NOT"], selected == "NOT", function()
            local subvalue
            if selected ~= "NOT" then
                if value ~= nil and value.type ~= nil then
                    subvalue = deepcopy(value)
                end
                cleanArray(value, { "type" })
            end
            value.type = "NOT"
            if subvalue ~= nil then
                value.value = subvalue
            elseif selected ~= "NOT" then
                value.value = { type = nil }
            end
        end)
        frame:AddChild(noticon)
    end

    for _, v in pairs(conditions) do
        if groups == nil or group == groups[v] then
            local icon, desc = funcs:describe(v)

            local action = layoutIcon(icon, desc, selected == v, function()
                if selected ~= v then
                    cleanArray(value, { "type" })
                end
                value.type = v
            end)
            frame:AddChild(action)
        end
    end

    return selectedIcon
end

local function ChangeConditionType(parent, _, ...)
    local top = parent:GetUserData("top")
    local value = parent:GetUserData("value")
    local spec = top:GetUserData("spec")
    local root = top:GetUserData("root")
    local funcs = top:GetUserData("funcs")

    -- Don't let the notifications happen, or the top screen destroy itself on hide.
    top:SetCallback("OnClose", function() end)
    top:Hide()

    local conditions, groups = funcs:list()
    local group_count = {}
    if (groups) then
        local grouped = 0
        for _, v in pairs(groups) do
            if group_count[v] == nil then
                group_count[v] = 1
            else
                group_count[v] = group_count[v] + 1
            end
            grouped = grouped + 1
        end
        group_count[L["Other"]] = #conditions - grouped
        local max_group = 0
        for _,v in pairs(group_count) do
            if v > max_group then
                max_group = v
            end
        end
        group_count = max_group
    else
        group_count = #conditions
    end

    local selected, selectedIcon
    if (value ~= nil and value.type ~= nil) then
        selected = value.type
    end

    local frame = AceGUI:Create("Window")
    --local frame = AceGUI:Create("Frame")
    frame:PauseLayout()
    frame:SetLayout("Fill")
    frame:SetTitle(L["Condition Type"])
    local DEFAULT_COLUMNS = 5
    local DEFAULT_ROWS = 5
    frame:SetWidth((groups and 70 or 50) + (DEFAULT_COLUMNS * 100))
    local rows = ceil((4 + group_count) / DEFAULT_COLUMNS)
    frame:SetHeight((groups and 90 or 46) + min(rows * 70, DEFAULT_ROWS * 70))
    frame:SetCallback("OnClose", function(widget)
        if selectedIcon then
            addon:HideGlow(selectedIcon.frame)
            --ActionButton_HideOverlayGlow(selectedIcon.frame)
        end
        AceGUI:Release(widget)
        addon.LayoutConditionFrame(top)
        top:SetStatusText(funcs:print(root, spec))
        top:Show()
    end)
    HideOnEscape(frame)

    if groups then
        local tab_select
        local tabs = {}
        local seen = {}
        for k, v in pairs(groups) do
            if seen[v] == nil then
                table.insert(tabs, {
                    value = v,
                    text = v
                })
                seen[v] = true
            end
            if selected == k then
                tab_select = v
            end
        end
        table.insert(tabs,
            {
                value = nil,
                text = L["Other"]
            })

        local group = AceGUI:Create("TabGroup")
        group:SetLayout("Fill")
        group:SetFullHeight(true)
        group:SetFullWidth(true)
        group:SetTabs(tabs)
        group:SetCallback("OnGroupSelected", function(_, _, val)
            group:ReleaseChildren()
            group:PauseLayout()
            if selectedIcon then
                addon:HideGlow(selectedIcon.frame)
            end

            local scrollwin = AceGUI:Create("ScrollFrame")
            scrollwin:SetFullHeight(true)
            scrollwin:SetFullWidth(true)
            scrollwin:SetLayout("Flow")

            selectedIcon = LayoutConditionTab(frame, scrollwin, funcs, value, selected, conditions, groups, val)

            group:AddChild(scrollwin)

            if selectedIcon then
                addon:ApplyCustomGlow({ type = "pixel" }, selectedIcon.frame, nil, { r = 0, g = 1, b = 0, a = 1 }, 0, 3)
                --ActionButton_ShowOverlayGlow(selectedIcon.frame)
            end

            addon:configure_frame(group)
            group:ResumeLayout()
            group:DoLayout()
        end)
        group:SelectTab(tab_select)
        frame:AddChild(group)
    else
        local scrollwin = AceGUI:Create("ScrollFrame")
        scrollwin:SetFullHeight(true)
        scrollwin:SetFullWidth(true)
        scrollwin:SetLayout("Flow")

        selectedIcon = LayoutConditionTab(frame, scrollwin, funcs, value, selected, conditions, groups, val)
        frame:AddChild(scrollwin)

        if selectedIcon then
            addon:ApplyCustomGlow({ type = "pixel" }, selectedIcon.frame, nil, { r = 0, g = 1, b = 0, a = 1 }, 0, 3)
            -- ActionButton_ShowOverlayGlow(selectedIcon.frame)
        end
    end

    addon:configure_frame(frame)
    frame:ResumeLayout()
    frame:DoLayout()
end

local function ActionGroup(parent, value, idx, array)
    local top = parent:GetUserData("top")
    local spec = top:GetUserData("spec")
    local funcs = top:GetUserData("funcs")

    local group = AceGUI:Create("InlineGroup")
    group:SetLayout("Table")
    group:SetFullWidth(true)
    group:SetUserData("top", top)

    if array then
        group:SetUserData("table", { columns = { 24, 44, 1 } })

        local movegroup = AceGUI:Create("SimpleGroup")
        movegroup:SetLayout("Table")
        movegroup:SetUserData("table", { columns = { 24 } })
        movegroup:SetHeight(68)
        movegroup:SetUserData("cell", { alignV = "middle" })
        group:AddChild(movegroup)

        local moveup = AceGUI:Create("InteractiveLabel")
        --moveup:SetUserData("cell", { alignV = "bottom" })
        if idx ~= nil and idx > 1 and value.type ~= nil then
            moveup:SetImage("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
            moveup:SetDisabled(false)
        else
            moveup:SetImage("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")
            moveup:SetDisabled(true)
        end
        moveup:SetImageSize(24, 24)
        moveup:SetCallback("OnClick", function()
            local tmp = array[idx-1]
            array[idx-1] = array[idx]
            array[idx] = tmp
            addon.LayoutConditionFrame(top)
        end)
        addon.AddTooltip(moveup, L["Move Up"])
        movegroup:AddChild(moveup)

        local movedown = AceGUI:Create("InteractiveLabel")
        --movedown:SetUserData("cell", { alignV = "top" })
        if idx ~= nil and idx < #array - 1 and value.type ~= nil then
            movedown:SetImage("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
            movedown:SetDisabled(false)
        else
            movedown:SetImage("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
            movedown:SetDisabled(true)
        end
        movedown:SetImageSize(24, 24)
        movedown:SetCallback("OnClick", function()
            local tmp = array[idx+1]
            array[idx+1] = array[idx]
            array[idx] = tmp
            addon.LayoutConditionFrame(top)
        end)
        addon.AddTooltip(movedown, L["Move Down"])
        movegroup:AddChild(movedown)
    else
        group:SetUserData("table", { columns = { 44, 1 } })
    end

    local actionicon = AceGUI:Create("Icon")
    actionicon:SetWidth(44)
    actionicon:SetImageSize(36, 36)
    actionicon:SetUserData("top", top)
    actionicon:SetUserData("value", value)
    actionicon:SetCallback("OnClick", ChangeConditionType)

    local description, helpfunc
    if (value == nil or value.type == nil) then
        actionicon:SetImage("Interface\\Icons\\Trade_Engineering")
        addon.AddTooltip(actionicon, L["Please Choose ..."])
    elseif (value.type == "AND") then
        actionicon:SetImage("Interface\\Icons\\Spell_ChargePositive")
        description = L["AND"]
        helpfunc = addon.layout_condition_and_help
    elseif (value.type == "OR") then
        actionicon:SetImage("Interface\\Icons\\Spell_ChargeNegative")
        description = L["OR"]
        helpfunc = addon.layout_condition_or_help
    elseif (value.type == "NOT") then
        actionicon:SetImage("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
        description = L["NOT"]
        helpfunc = addon.layout_condition_not_help
    else
        local icon
        icon, description, helpfunc = funcs:describe(value.type)
        if (icon == nil) then
            actionicon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
        else
            actionicon:SetImage(icon)
        end
    end

    group:AddChild(actionicon)

    if description then
        group:SetTitle(description)
        addon.AddTooltip(actionicon, description)
    end

    if (value ~= nil and value.type ~= nil) then
        local arraygroup = AceGUI:Create("SimpleGroup")
        arraygroup:SetFullWidth(true)
        arraygroup:SetLayout("Flow")
        arraygroup:SetUserData("top", top)

        if helpfunc and description then
            local addgroup = arraygroup
            local help = AceGUI:Create("Help")
            help:SetLayout(helpfunc)
            help:SetTitle(description)
            help:SetTooltip(description .. " " .. L["Help"])
            help:SetFrameSize(400, 300)
            addgroup:AddChild(help)
            local func = addgroup.LayoutFunc
            addgroup.LayoutFunc = function (content, children)
                func(content, children)
                help:SetPoint("TOPRIGHT", 8, 8)
            end
        end

        if (value.type == "AND" or value.type == "OR") then
            if (value.value == nil) then
                value.value = { { type = nil } }
            end

            local arraysz = #value.value
            if value.value[arraysz].type ~= nil then
                table.insert(value.value, { type = nil })
                arraysz = arraysz + 1
            end

            local i = 1
            while i <= arraysz do
                -- Clean out deleted items in the middle of the list.
                while i < arraysz and (value.value[i] == nil or value.value[i].type == nil) do
                    table.remove(value.value, i)
                    arraysz = arraysz - 1
                end

                ActionGroup(arraygroup, value.value[i], i, value.value)
                i = i + 1
            end

        elseif (value.type == "NOT") then
            ActionGroup(arraygroup, value.value)
        else
            funcs:widget(arraygroup, spec, value)
        end

        group:AddChild(arraygroup)
    end

    parent:AddChild(group)
end

addon.LayoutConditionFrame = function(frame)
    local root = frame:GetUserData("root")
    local funcs = frame:GetUserData("funcs")

    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        if funcs.close ~= nil then
            funcs.close()
        end
        addon:UpdateAutoSwitch()
        addon:SwitchRotation()
    end)

    frame:ReleaseChildren()
    frame:PauseLayout()

    local group = AceGUI:Create("ScrollFrame")

    group:SetLayout("Flow")
    group:SetUserData("top", frame)
    ActionGroup(group, root)
    frame:AddChild(group)

    addon:configure_frame(frame)
    frame:ResumeLayout()
    frame:DoLayout()
end

local function EditConditionCommon(index, spec, value, funcs)
    local frame = AceGUI:Create("Frame")

    if index > 0 then
        frame:SetTitle(string.format(L["Edit Condition #%d"], index))
    else
        frame:SetTitle(L["Edit Condition"])
    end
    frame:SetStatusText(funcs:print(value, spec))
    frame:SetUserData("index", index)
    frame:SetUserData("spec", spec)
    frame:SetUserData("root", value)
    frame:SetUserData("funcs", funcs)
    frame:SetLayout("Fill")

    addon.LayoutConditionFrame(frame)
    HideOnEscape(frame)
end

--------------------------------
--  Dealing with Conditionals
-------------------------------

local conditions = {}
local conditions_idx = 1
local condition_groups = {}

function addon:RegisterCondition(group, tag, array)
    array["order"] = conditions_idx
    conditions[tag] = array
    conditions_idx = conditions_idx + 1
    if group then
        condition_groups[tag] = group
    end
end

function addon:EditCondition(index, spec, value, callback)
    local funcs = {
        print = addon.printCondition,
        validate = addon.validateCondition,
        list = addon.listConditions,
        describe = addon.describeCondition,
        widget = addon.widgetCondition,
        close = callback,
    }

    EditConditionCommon(index, spec, value, funcs)
end

function addon:evaluateCondition(value)
    local cache = {}
    local start = GetTime()
    return evaluateSingle(value, conditions, cache, start)
end

function addon:printCondition(value, spec)
    return printSingle(value, conditions, spec)
end

function addon:validateCondition(value, spec)
    return validateSingle(value, conditions, spec)
end

function addon:usefulCondition(value)
    return usefulSingle(value, conditions)
end

function addon:listConditions()
    local rv = {}
    for k, _ in pairs(conditions) do
        table.insert(rv, k)
    end
    table.sort(rv, function (lhs, rhs)
        if (conditions[rhs] == nil or conditions[rhs].order == nil) then
            return lhs
        end
        if (conditions[lhs] == nil or conditions[lhs].order == nil) then
            return rhs
        end
        return conditions[lhs].order < conditions[rhs].order
    end)
    return rv, condition_groups
end

function addon:describeCondition(type)
    if (conditions[type] == nil) then
        return nil, nil
    end
    return conditions[type].icon, conditions[type].description, conditions[type].help
end

function addon:widgetCondition(parent, spec, value)
    if value ~= nil and value.type ~= nil and conditions[value.type] ~= nil and conditions[value.type].widget ~= nil then
        conditions[value.type].widget(parent, spec, value)
    end
end

--------------------------------
--  Dealing with Switch Conditionals
-------------------------------

local switchConditions = {}
local switchConditions_idx = 1

function addon:RegisterSwitchCondition(tag, array)
    array["order"] = switchConditions_idx
    switchConditions[tag] = array
    switchConditions_idx = switchConditions_idx + 1
end

function addon:EditSwitchCondition(spec, value, callback)
    local funcs = {
        print = addon.printSwitchCondition,
        validate = addon.validateSwitchCondition,
        list = addon.listSwitchConditions,
        describe = addon.describeSwitchCondition,
        widget = addon.widgetSwitchCondition,
        close = callback,
    }

    EditConditionCommon(0, spec, value, funcs)
end

function addon:evaluateSwitchCondition(value)
    local cache = {}
    local start = GetTime()
    return evaluateSingle(value, switchConditions, cache, start)
end

function addon:printSwitchCondition(value, spec)
    return printSingle(value, switchConditions, spec)
end

function addon:validateSwitchCondition(value, spec)
    return validateSingle(value, switchConditions, spec)
end

function addon:usefulSwitchCondition(value)
    return usefulSingle(value, switchConditions)
end

function addon:listSwitchConditions()
    local rv = {}
    for k, _ in pairs(switchConditions) do
        table.insert(rv, k)
    end
    table.sort(rv, function (lhs, rhs)
        if (switchConditions[rhs] == nil or switchConditions[rhs].order == nil) then
            return lhs
        end
        if (switchConditions[lhs] == nil or switchConditions[lhs].order == nil) then
            return rhs
        end
        return switchConditions[lhs].order < switchConditions[rhs].order
    end)
    return rv, nil
end

function addon:describeSwitchCondition(type)
    if (switchConditions[type] == nil) then
        return nil, nil
    end
    return switchConditions[type].icon, switchConditions[type].description, switchConditions[type].help
end

function addon:widgetSwitchCondition(parent, spec, value)
    if value ~= nil and value.type ~= nil and switchConditions[value.type] ~= nil and switchConditions[value.type].widget ~= nil then
        switchConditions[value.type].widget(parent, spec, value)
    end
end
