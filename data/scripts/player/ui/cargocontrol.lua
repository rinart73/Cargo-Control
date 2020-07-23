package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")
include("faction")
include("stringutility")
include("goods")
local Azimuth = include("azimuthlib-basic")
local UICollection -- clientside
local UTF8 = include("azimuthlib-utf8")

-- namespace CargoControl
CargoControl = {}


local tab, nameBox, autoCheckBox, cycleCheckBox, frame, lister, rows, loadWindow, rulesetsListBox -- client UI
local ServerConfig, rowByEditBtn, rowByTypeBox, rowsActive, rulesets, goodIndexByName, goodsAll, goodsDangerous, goodsIllegal -- client
local Log, Config, data, rulesetByName -- server


if onClient() then


include("azimuthlib-uiproportionalsplitter")
UICollection = include("azimuthlib-uicollection")

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
    
    local hSplit = UIHorizontalProportionalSplitter(Rect(tab.size), 10, 0, {30, 20, 0.5})
    local vSplit = UIVerticalProportionalSplitter(hSplit[1], 10, 0, {0.8, 0.56, 0.56, 0.56, 0.56, 10, 30})
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
    local tooltipFrame = tab:createFrame(vSplit[7])
    rect = vSplit[7]
    local helpLabel = tab:createLabel(Rect(rect.lower + vec2(0, 5), rect.upper), "?", 16)
    helpLabel.centered = true
    helpLabel.tooltip = [[This tab allows to create sets of rules that will determine what to do with cargo once it's picked up.]]%_t

    local vSplit = UIVerticalProportionalSplitter(hSplit[2], 10, 0, {0.17, 0.08, 0.05})
    local rect = vSplit[2]
    cycleCheckBox = tab:createCheckBox(rect, "Apply every minute"%_t, "onCycleBoxChecked")
    cycleCheckBox.captionLeft = false
    cycleCheckBox.tooltip = [[Automatically apply this ruleset every minute (good for stations that produce waste).]]%_t
    local rect = vSplit[3]
    autoCheckBox = tab:createCheckBox(rect, "Filter loot"%_t, "onAutoBoxChecked")
    autoCheckBox.captionLeft = false
    autoCheckBox.tooltip = [[Automatically apply this ruleset when picking up goods.]]%_t

    frame = tab:createScrollFrame(hSplit[3])
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
    for i = 1, rowsActive - 1 do
        local row = rows[i]
        set.rules[i] = {
          action = row.action.selectedIndex,
          type = row.type.selectedIndex,
          good = goodIndexByName[row.good.selectedEntry] or 0
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

    invokeServerFunction("setVariable", "auto", value)
end

function CargoControl.onCycleBoxChecked(checkBox, value)
    loadWindow.visible = false

    invokeServerFunction("setVariable", "cycle", value)
end

function CargoControl.onRowTypeSelected(comboBox)
    local pos = rowByTypeBox[comboBox.index]
    local row = rows[pos]
    local oldType = row.data.lastType
    local newType = row.type.selectedIndex
    if oldType == newType then return end

    local goodsNames
    if newType == 3 then
        goodsNames = goodsDangerous
    elseif newType == 4 then
        goodsNames = goodsIllegal
    elseif (oldType == 3 or oldType == 4) and newType ~= 3 and newType ~= 4 then
        goodsNames = goodsAll
    end
    if goodsNames then
        local selectedEntry = row.good.selectedEntry
        row.good:clear()
        row.good:addEntry("All"%_t)
        local newIndex = 0
        for k, name in ipairs(goodsNames) do
            if name == selectedEntry then
                newIndex = k
            end
            row.good:addEntry(name)
        end
        row.good:setSelectedIndexNoCallback(newIndex)
        row.good.scrollPosition = newIndex
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
            local row
            for i = pos, rowsActive - 1 do
                row = rows[i]
                local rowNext = rows[i+1]
                row.action.selectedIndex = rowNext.action.selectedIndex
                row.type:setSelectedIndexNoCallback(rowNext.type.selectedIndex)
                CargoControl.onRowTypeSelected(row.type) -- update goods list
                row.good:setSelectedIndexNoCallback(rowNext.good.selectedIndex)
                row.good.scrollPosition = rowNext.good.selectedIndex
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
        for _, element in pairs(self) do
            element.visible = true
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
    --row.good = frame:createValueComboBox(vSplit[3], "")
    row.good = frame:createComboBox(vSplit[3], "")
    row.good:addEntry("All"%_t)
    for _, name in ipairs(goodsAll) do
        row.good:addEntry(name)
    end
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

function CargoControl.receiveRulesets(data, isLoaded)
    CargoControl.onClearRulesetBtn()
    if data then
        if not isLoaded then
            autoCheckBox:setCheckedNoCallback(data.auto)
            cycleCheckBox:setCheckedNoCallback(data.cycle)
        end
        nameBox.text = data.current.name or ""
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
                row.type:setSelectedIndexNoCallback(rule.type)
                CargoControl.onRowTypeSelected(row.type) -- update goods list

                -- not very fast but will do
                local newIndex = 0
                if rule.good ~= 0 then
                    local curType = row.type.selectedIndex
                    local goodsNames
                    if curType == 3 then
                        goodsNames = goodsDangerous
                    elseif curType == 4 then
                        goodsNames = goodsIllegal
                    else
                        goodsNames = goodsAll
                    end
                    local goodTbl = goodsArray[rule.good]
                    if goodTbl then
                        local goodName = goodTbl.name%_t
                        for k, name in ipairs(goodsNames) do
                            if name == goodName then
                                newIndex = k
                                break
                            end
                        end
                    end
                end
                row.good:setSelectedIndexNoCallback(newIndex)
                row.good.scrollPosition = newIndex
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
            Log:Error("sendRuleset - failed to get entity data: %i, %s", status, entityData)
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
    Log:Debug("saveRuleset: %s", set.rules)

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
        Log:Error("saveRuleset - failed to set entity data: %i", status)
    end
end
callable(CargoControl, "saveRuleset")

function CargoControl.forceRuleset()
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end

    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "forceRuleset", Player().index)
    if status ~= 0 then
        Log:Error("forceRuleset - failed to apply entity ruleset: %i", status)
    end
end
callable(CargoControl, "forceRuleset")

function CargoControl.setVariable(key, value)
    if not CargoControl.interactionPossible() then return end
    local entity = Player().craft
    if not entity.isShip and not entity.isStation then return end
    if key ~= "auto" and key ~= "cycle" then return end

    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "setData", {[key] = value and true or false})
    if status ~= 0 then
        Log:Error("setVariable - failed to set entity data: %i", status)
    end
end
callable(CargoControl, "setVariable")

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
    local newEntityData = {current = set}
    local status = entity:invokeFunction("data/scripts/entity/cargocontrol.lua", "setData", newEntityData)
    if status ~= 0 then
        Log:Error("loadRuleset - failed to set entity data: %i", status)
        return
    end
    invokeClientFunction(player, "receiveRulesets", newEntityData, true)
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