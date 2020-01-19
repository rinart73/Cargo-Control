package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")
include("faction")
include("stringutility")
include("goods")
include("azimuthlib-uiproportionalsplitter")
local Azimuth = include("azimuthlib-basic")
local UICollection = include("azimuthlib-uicollection")
local UTF8 = include("azimuthlib-utf8")

-- namespace CargoControl
CargoControl = {}


local tab, nameBox, autoCheckBox, frame, lister, rows, loadWindow, rulesetsListBox -- client UI
local ServerConfig, rowByEditBtn, rowByTypeBox, rowsActive, rulesets, goodIndexByName, goodsAll, goodsDangerous, goodsIllegal -- client
local Log, Config, data, rulesetByName -- server


if onClient() then


rows = {}
rowByEditBtn = {}
rowByTypeBox = {}
rowsActive = 0
rulesets = {}

-- PREDEFINED --

function CargoControl.initialize()
    -- sort goods names
    goodIndexByName = {}
    goodsAll = {}
    goodsDangerous = {}
    goodsIllegal = {}
    local name
    for k, good in ipairs(goodsArray) do
        name = good.name%_t
        goodIndexByName[name] = k
        goodsAll[#goodsAll+1] = name
        if good.dangerous then
            goodsDangerous[#goodsDangerous+1] = name
        end
        if good.illegal then
            goodsIllegal[#goodsIllegal+1] = name
        end
    end
    table.sort(goodsAll, UTF8.compare)
    table.sort(goodsDangerous, UTF8.compare)
    table.sort(goodsIllegal, UTF8.compare)
    
    -- init UI
    tab = ShipWindow():createTab("Cargo Control"%_t, "data/textures/icons/cubes.png", "Cargo Control"%_t)
    tab.onShowFunction = "onShowTab"
    
    local hSplit = UIHorizontalProportionalSplitter(Rect(tab.size), 10, 0, {30, 0.5})
    local vSplit = UIVerticalProportionalSplitter(hSplit[1], 10, 0, {0.72, 0.48, 0.48, 0.48, 0.48, 0.4, 10, 30})
    nameBox = tab:createTextBox(vSplit[1], "")
    nameBox.maxCharacters = 40
    local saveBtn = tab:createButton(vSplit[2], "Save"%_t, "onSaveRulesetBtn")
    saveBtn.maxTextSize = 16
    local loadBtn = tab:createButton(vSplit[3], "Load"%_t, "onLoadRulesetBtn")
    loadBtn.maxTextSize = 16
    local clearBtn = tab:createButton(vSplit[4], "Clear"%_t, "onClearRulesetBtn")
    clearBtn.maxTextSize = 16
    local forceBtn = tab:createButton(vSplit[5], "Force"%_t, "onForceRulesetBtn")
    forceBtn.maxTextSize = 16
    forceBtn.tooltip = [[Apply this ruleset to goods that are currently stored in the cargo bay.]]%_t
    local rect = vSplit[6]
    autoCheckBox = tab:createCheckBox(Rect(rect.lower + vec2(0, 5), rect.upper), "Auto"%_t, "onAutoBoxChecked")
    autoCheckBox.captionLeft = false
    autoCheckBox.tooltip = [[Automatically apply this ruleset when picking up goods.]]%_t
    autoCheckBox:setCheckedNoCallback(true)
    local tooltipFrame = tab:createFrame(vSplit[8])
    rect = vSplit[8]
    local helpLabel = tab:createLabel(Rect(rect.lower + vec2(0, 5), rect.upper), "?", 16)
    helpLabel.centered = true
    helpLabel.tooltip = [[This tab allows to create sets of rules that will determine what to do with cargo once it's picked up.]]%_t

    frame = tab:createScrollFrame(hSplit[2])
    frame.scrollSpeed = 40
    lister = UIVerticalLister(Rect(frame.size), 10, 10)
    lister.marginRight = 30

    CargoControl.createRow()

    -- load ruleset window
    local res = getResolution()
    local size = vec2(400, 300)
    loadWindow = tab:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    loadWindow.visible = false
    loadWindow.caption = "Load ruleset"%_t
    loadWindow.showCloseButton = true
    loadWindow.moveable = true
    loadWindow.closeableWithEscape = true
    hSplit = UIHorizontalProportionalSplitter(Rect(loadWindow.size), 10, 10, {0.5, 30})
    rulesetsListBox = loadWindow:createListBox(hSplit[1])
    local splitter = UIVerticalSplitter(hSplit[2], 10, 0, 0.5)
    loadBtn = loadWindow:createButton(splitter.left, "Load"%_t, "onLoadWindowLoadBtn")
    local deleteBtn = loadWindow:createButton(splitter.right, "Delete"%_t, "onLoadWindowDeleteBtn")

    Player():registerCallback("onShipChanged", "onShipChanged")
    
    invokeServerFunction("sendSettings") -- request settings and rulesets
end

-- CALLBACKS --

function CargoControl.onShipChanged(playerIndex, craftId)
    if loadWindow then
        loadWindow.visible = false
    end
    if craftId then
        local entity = Entity(craftId)
        if entity and (entity.isShip or entity.isStation) then
            ShipWindow():activateTab(tab)
            return
        end
    end
    ShipWindow():deactivateTab(tab)
end

function CargoControl.onShowTab()
    loadWindow.visible = false

    invokeServerFunction("sendRuleset")
end

function CargoControl.onSaveRulesetBtn()
    loadWindow.visible = false

    if nameBox.text == "" then
        displayChatMessage("The ruleset should have a name."%_t, "", 1)
        return
    end
    local set = {
      name = nameBox.text,
      rules = {}
    }
    local row, goodValue
    for i = 1, rowsActive - 1 do
        row = rows[i]
        if row.type.selectedIndex == 3 then
            goodValue = row.dangerousGood.selectedValue
        elseif row.type.selectedIndex == 4 then
            goodValue = row.illegalGood.selectedValue
        else
            goodValue = row.good.selectedValue
        end
        set.rules[i] = {
          action = row.action.selectedIndex,
          type = row.type.selectedIndex,
          good = goodValue
        }
    end
    invokeServerFunction("saveRuleset", set)
end

function CargoControl.onLoadRulesetBtn()
    rulesetsListBox:clear()
    for k, name in ipairs(rulesets) do
        rulesetsListBox:addEntry(name, name)
    end
    loadWindow.visible = true
end

function CargoControl.onClearRulesetBtn()
    loadWindow.visible = false

    local row
    for i = rowsActive - 1, 1, -1 do
        row = rows[i]
        CargoControl.onRowEditBtn(row.edit) -- press 'x' on all active rows
    end
end

function CargoControl.onForceRulesetBtn()
    loadWindow.visible = false

    invokeServerFunction("forceRuleset")
end

function CargoControl.onAutoBoxChecked(checkBox, value)
    loadWindow.visible = false

    invokeServerFunction("setAuto", value)
end

function CargoControl.onRowTypeSelected(comboBox)
    local pos = rowByTypeBox[comboBox.index]
    local row = rows[pos]
    local oldType = row.data.lastType
    local newType = row.type.selectedIndex
    if oldType == newType then return end

    local goodValue
    if oldType == 3 then
        goodValue = row.dangerousGood.selectedValue
    elseif oldType == 4 then
        goodValue = row.illegalGood.selectedValue
    else
        goodValue = row.good.selectedValue
    end
    if newType == 3 then
        row.dangerousGood:setSelectedValueNoCallback(goodValue)
        if goodValue ~= row.dangerousGood.selectedValue then -- reset to 'all'
            row.dangerousGood:setSelectedValueNoCallback(0)
        end
        row.good.visible = false
        row.illegalGood.visible = false
        row.dangerousGood.visible = true
    elseif newType == 4 then
        row.illegalGood:setSelectedValueNoCallback(goodValue)
        if goodValue ~= row.illegalGood.selectedValue then -- reset to 'all'
            row.illegalGood:setSelectedValueNoCallback(0)
        end
        row.good.visible = false
        row.dangerousGood.visible = false
        row.illegalGood.visible = true
    elseif (oldType == 3 or oldType == 4) and newType ~= 3 and newType ~= 4 then
        row.good:setSelectedValueNoCallback(goodValue)
        if goodValue ~= row.good.selectedValue then -- reset to 'all'
            row.good:setSelectedValueNoCallback(0)
        end
        row.dangerousGood.visible = false
        row.illegalGood.visible = false
        row.good.visible = true
    end

    row.data.lastType = newType
end

function CargoControl.onRowEditBtn(button)
    local pos = rowByEditBtn[button.index]
    if button.caption == '+' then -- add
        local count = #rows
        if count == pos then -- create new ui row
            if count + 1 > ServerConfig.MaxRowsPerRuleset then
                displayChatMessage("Maximum amount of rules reached."%_t, "", 1)
            else
                rows[pos]:setLast(false)
                CargoControl.createRow()
            end
        else -- unhide existing ui row
            rows[pos]:setLast(false)
            local row = rows[pos+1]
            row:setLast(true)
            row:show()
            rowsActive = rowsActive + 1
        end
    else -- remove
        if rowsActive == pos + 1 then -- hide 'last' (this) row
            local row = rows[pos]
            row:setLast(true)
            row = rows[pos+1]
            row:setLast(false)
            row:hide()
        else -- shift rows one position up and hide the last row simulating deletion
            local row, rowNext, curType
            for i = pos, rowsActive - 1 do
                row = rows[i]
                rowNext = rows[i+1]
                row.action.selectedIndex = rowNext.action.selectedIndex
                curType = rowNext.type.selectedIndex 
                row.type.selectedIndex = curType
                if curType == 3 then
                    row.dangerousGood.selectedIndex = rowNext.dangerousGood.selectedIndex
                elseif curType == 4 then
                    row.illegalGood.selectedIndex = rowNext.illegalGood.selectedIndex
                else
                    row.good.selectedIndex = rowNext.good.selectedIndex
                end
            end
            row = rows[rowsActive - 1]
            row:setLast(true)
            row = rows[rowsActive]
            row:setLast(false)
            row:hide()
        end
        rowsActive = rowsActive - 1
    end
end

function CargoControl.onLoadWindowLoadBtn()
    if not rulesetsListBox.selectedValue then return end

    invokeServerFunction("loadRuleset", rulesetsListBox.selectedValue)
    loadWindow.visible = false
end

function CargoControl.onLoadWindowDeleteBtn()
    if not rulesetsListBox.selectedValue then return end

    invokeServerFunction("deleteRuleset", rulesetsListBox.selectedValue)
end

-- FUNCTIONS --

function UICollection.meta:setLast(state)
    if state then
        -- reset values
        self.action.selectedIndex = 0
        self.type.selectedIndex = 0
        self.good.selectedIndex = 0

        if self.edit.visible then
            for _, element in pairs(self) do
                if element ~= self.edit then
                    element.visible = false
                end
            end
        end
        self.edit.caption = '+'
    else
        self.edit.caption = 'x'
        self:show()
    end
end

function UICollection.meta:show()
    if self.edit.caption == '+' then
        self.edit.visible = true
    else
        local curType = self.type.selectedIndex
        for _, element in pairs(self) do
            if (curType == 3 and element ~= self.good and element ~= self.illegalGood)
              or (curType == 4 and element ~= self.good and element ~= self.dangerousGood)
              or (curType ~= 3 and curType ~= 4 and element ~= self.dangerousGood and element ~= self.illegalGood) then
                element.visible = true
            end
        end
    end
end

function CargoControl.createRow()
    local row = UICollection()
    local rect = lister:placeRight(vec2(lister.inner.width, 25))
    local vSplit = UIVerticalProportionalSplitter(rect, 10, 0, {0.4, 0.4, 0.8, 25})
    row.action = frame:createComboBox(vSplit[1], "")
    row.action:addEntry("Destroy"%_t)
    row.action:addEntry("Drop"%_t)
    row.type = frame:createComboBox(vSplit[2], "onRowTypeSelected")
    row.type:addEntry("All"%_t)
    row.type:addEntry("Suspicious"%_t)
    row.type:addEntry("Stolen"%_t)
    row.type:addEntry("Dangerous"%_t)
    row.type:addEntry("Illegal"%_t)

    -- horrible workarounds to deal with UI bugs (x3 ComboBox)
    row.good = frame:createValueComboBox(vSplit[3], "")
    row.dangerousGood = frame:createValueComboBox(vSplit[3], "")
    row.illegalGood = frame:createValueComboBox(vSplit[3], "")
    row.good:addEntry(0, "All"%_t)
    row.dangerousGood:addEntry(0, "All"%_t)
    row.illegalGood:addEntry(0, "All"%_t)
    for _, name in ipairs(goodsAll) do
        row.good:addEntry(goodIndexByName[name], name)
    end
    for _, name in ipairs(goodsDangerous) do
        row.dangerousGood:addEntry(goodIndexByName[name], name)
    end
    for _, name in ipairs(goodsIllegal) do
        row.illegalGood:addEntry(goodIndexByName[name], name)
    end
    --[[for k, good in ipairs(goodsArray) do
        row.good:addEntry(k, good.name%_t)
        if good.dangerous then
            row.dangerousGood:addEntry(k, good.name%_t)
        end
        if good.illegal then
            row.illegalGood:addEntry(k, good.name%_t)
        end
    end]]
    --
    row.edit = frame:createButton(vSplit[4], "x", "onRowEditBtn")
    row.edit.textSize = 15

    row.data = { lastType = 0, lastGood = 0 }
    row:setLast(true)

    local newIndex = #rows + 1
    rowByEditBtn[row.edit.index] = newIndex
    rowByTypeBox[row.type.index] = newIndex
    rows[newIndex] = row
    rowsActive = rowsActive + 1

    return row
end

-- CALLABLE --

function CargoControl.receiveSettings(serverConfig, rulesetNames)
    if serverConfig then
        ServerConfig = serverConfig
    end
    if rulesetNames then
        rulesets = rulesetNames
        -- update ui
        if loadWindow and loadWindow.visible then
            rulesetsListBox:clear()
            for k, name in ipairs(rulesets) do
                rulesetsListBox:addEntry(name, name)
            end
        end
    end
end

function CargoControl.receiveRulesets(data)
    CargoControl.onClearRulesetBtn()
    if data then
        autoCheckBox:setCheckedNoCallback(data.auto)
        if data.current.name then
            nameBox.text = data.current.name
        end
        if data.current.rules then
            -- create new rows
            local length = #data.current.rules
            local repeats = length - (#rows - 1)
            for i = 1, repeats do
                CargoControl.createRow()
            end
            -- show rows and fill them with data
            local row
            local rules = data.current.rules
            local rule
            for i = 1, length do
                row = rows[i]
                row:setLast(false)
                row:show()
                rule = rules[i]
                row.action.selectedIndex = rule.action
                row.type.selectedIndex = rule.type
                if rule.type == 3 then
                    row.dangerousGood.selectedValue = rule.good
                elseif rule.type == 4 then
                    row.illegalGood.selectedValue = rule.good
                else
                    row.good.selectedValue = rule.good
                end
            end
            row = rows[length + 1]
            row:setLast(true)
            row:show()
            rowsActive = length + 1
        end
    end
end


else -- onServer


data = { rulesets = {} }
rulesetByName = {}

-- PREDEFINED --

function CargoControl.initialize()
    local configOptions = {
      _version = { default = "1.0", comment = "Config version. Don't touch." },
      ConsoleLogLevel = { default = 2, min = 0, max = 4, format = "floor", comment = "0 - Disable, 1 - Errors, 2 - Warnings, 3 - Info, 4 - Debug." },
      FileLogLevel = { default = 2, min = 0, max = 4, format = "floor", comment = "0 - Disable, 1 - Errors, 2 - Warnings, 3 - Info, 4 - Debug." },
      MaxRowsPerRuleset = { default = 60, min = 0, format = "floor", comment = "How many rows can a ruleset have" },
      MaxRulesets = { default = 20, min = 0, format = "floor", comment = "How many rulesets can player have" }
    }
    local isModified
    Config, isModified = Azimuth.loadConfig("CargoControl", configOptions)
    if isModified then
        Azimuth.saveConfig("CargoControl", Config, configOptions)
    end
    Log = Azimuth.logs("CargoControl", Config.ConsoleLogLevel, Config.FileLogLevel)

    data, isModified = Azimuth.loadConfig("Rulesets_"..Player().index, { _version = { default = "1.0" }, rulesets = { default = {} } }, false, "CargoControl")
    if isModified then
        Azimuth.saveConfig("Rulesets_"..Player().index, data, nil, false, "CargoControl", true)
    end
    for k, set in ipairs(data.rulesets) do
        rulesetByName[set.name] = k
    end
end

-- CALLABLE --

function CargoControl.sendSettings()
    local names = {}
    for k, set in ipairs(data.rulesets) do
        names[k] = set.name
    end
    invokeClientFunction(Player(), "receiveSettings", {
      MaxRowsPerRuleset = Config.MaxRowsPerRuleset
    }, names)
end
callable(CargoControl, "sendSettings")

function CargoControl.sendRuleset()
    if not CargoControl.interactionPossible() then return end
    local player = Player()
    local entity = player.craft
    if not entity.isShip and not entity.isStation then
        invokeClientFunction(player, "receiveRulesets") -- tell client to deactivate buttons if we're in a drone
    else
        -- get data from current entity
        local status, entityData = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "getData", Config.MaxRowsPerRuleset, player.index)
        if status ~= 0 or not entityData then
            Log.Error("sendRuleset - failed to get entity data: %i, %s", status, entityData)
            invokeClientFunction(player, "receiveRulesets")
        else
            invokeClientFunction(player, "receiveRulesets", entityData)
        end
    end
end
callable(CargoControl, "sendRuleset")

function CargoControl.saveRuleset(set)
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end

    -- validation
    if not set or not set.rules or type(set.rules) ~= "table" then return end

    set.name = UTF8.getString(set.name, "New Ruleset", 1, 40)
    
    local setIndex = rulesetByName[set.name]
    if not setIndex and #data.rulesets == Config.MaxRulesets then
        Player():sendChatMessage("", ChatMessageType.Error, "Can't create new ruleset - reached the maximum amount of %1%."%_T, Config.MaxRulesets)
        return
    end

    local newRules = {}
    local goodsArrayLength = #goodsArray
    local rowCount = 1
    for k, row in ipairs(set.rules) do
        if type(row) == "table" then
            row.action = Azimuth.getInt(row.action, {0, 1})
            row.type = Azimuth.getInt(row.type, {0, 4})
            row.good = Azimuth.getInt(row.good, {0, goodsArrayLength})
            if row.action and row.type and row.good then
                newRules[rowCount] = {
                  action = row.action,
                  type = row.type,
                  good = row.good
                }
                if rowCount == Config.MaxRowsPerRuleset then
                    break
                end
                rowCount = rowCount + 1
            end
        end
    end
    set.rules = newRules
    Log.Debug("saveRuleset: %s", set.rules)

    -- save to rulesets
    if not setIndex then -- new set
        local newIndex = #data.rulesets + 1
        data.rulesets[newIndex] = set
        rulesetByName[set.name] = newIndex
        -- update client ruleset names
        local names = {}
        for k, set in ipairs(data.rulesets) do
            names[k] = set.name
        end
        invokeClientFunction(Player(), "receiveSettings", nil, names)
    else -- overwrite
        data.rulesets[setIndex] = set
    end
    Azimuth.saveConfig("Rulesets_"..Player().index, data, nil, false, "CargoControl", true)

    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "setData", {current = set})
    if status ~= 0 then
        Log.Error("saveRuleset - failed to set entity data: %i", status)
    end
end
callable(CargoControl, "saveRuleset")

function CargoControl.forceRuleset()
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end

    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "forceRuleset")
    if status ~= 0 then
        Log.Error("forceRuleset - failed to apply entity ruleset: %i", status)
    end
end
callable(CargoControl, "forceRuleset")

function CargoControl.setAuto(value)
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end

    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "setData", {auto = value and true or false})
    if status ~= 0 then
        Log.Error("setAuto - failed to set entity data: %i", status)
    end
end
callable(CargoControl, "setAuto")

function CargoControl.loadRuleset(name)
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end
    if not name then return end

    local index = rulesetByName[name]
    if not index then return end
    local set = data.rulesets[index]

    -- remove extra rows
    local player = Player()
    if set.rules then
        local length = #set.rules
        if length > Config.MaxRowsPerRuleset then
            for i = length, Config.MaxRowsPerRuleset + 1, -1 do
                set.rules[i] = nil
            end
            player:sendChatMessage("", ChatMessageType.Warning, "%1% rows were removed because they exceeded the limit of %2% rows per ruleset."%_T, length - Config.MaxRowsPerRuleset, Config.MaxRowsPerRuleset)
            -- resave
            Azimuth.saveConfig("Rulesets_"..player.index, data, nil, false, "CargoControl", true)
        end
    end
    local newEntityData = {auto = false, current = set}
    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "setData", newEntityData)
    if status ~= 0 then
        Log.Error("loadRuleset - failed to set entity data: %i", status)
        return
    end
    invokeClientFunction(player, "receiveRulesets", newEntityData)
end
callable(CargoControl, "loadRuleset")

function CargoControl.deleteRuleset(name)
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end
    if not name then return end

    local index = rulesetByName[name]
    if index then
        table.remove(data.rulesets, index)
        for k, set in ipairs(data.rulesets) do
            rulesetByName[set.name] = k
        end
        local names = {}
        for k, set in ipairs(data.rulesets) do
            names[k] = set.name
        end
        Azimuth.saveConfig("Rulesets_"..Player().index, data, nil, false, "CargoControl", true)
        invokeClientFunction(Player(), "receiveSettings", nil, names)
    end
end
callable(CargoControl, "deleteRuleset")

-- FUNCTIONS --

function CargoControl.interactionPossible()
    local player = Player()
    local entity = player.craft
    if entity == nil then return false end

    local requiredPermission = entity.isShip and AlliancePrivilege.ManageShips or AlliancePrivilege.ManageStations
    return checkEntityInteractionPermissions(entity, requiredPermission)
end


end