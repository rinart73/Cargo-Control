package.path = package.path .. ";data/scripts/lib/?.lua"
include("goods")

-- namespace CargoControl
CargoControl = {}


local data, goodIndexByName -- server


if onServer() then


data = { current = {}, auto = false }

-- PREDEFINED --

function CargoControl.initialize()
    goodIndexByName = {}
    for index, good in ipairs(goodsArray) do
        goodIndexByName[good.name] = index
    end

    Entity():registerCallback("onCargoLootCollected", "onCargoLootCollected")
end

function CargoControl.secure()
    return data
end

function CargoControl.restore(_data)
    if _data and _data.current then
        data = _data
    end
end

-- CALLBACKS --

function CargoControl.onCargoLootCollected(collector, lootIndex, amount, good, owner)
    if data.auto and data.current.rules and #data.current.rules > 0 then
        local goodTypes = {"suspicious", "stolen", "dangerous", "illegal"}
        local goodIndex = goodIndexByName[good.name]
        for _, row in ipairs(data.current.rules) do
            if (row.type == 0 or good[goodTypes[row.type]]) and (row.good == 0 or row.good == goodIndex) then
                local entity = Entity()
                entity:removeCargo(good, amount)
                if row.action == 1 then
                    local dropPos = entity.translationf - entity.up * (entity.radius + entity:getBoostedValue(StatsBonuses.LootCollectionRange, 50)) -- radius + Loot collector range (500m by default?)
                    Sector():dropCargo(dropPos, nil, nil, good, -1, amount)
                end
                break
            end
        end
    end
end

-- FUNCTIONS --

function CargoControl.getData(maxRows, playerIndex)
    if maxRows and data.current.rules then
        local length = #data.current.rules
        if length > maxRows then -- remove extra rows
            for i = length, maxRows + 1, -1 do
                data.current.rules[i] = nil
            end
            if playerIndex then
                local player = Player(playerIndex)
                if player then
                    player:sendChatMessage("", ChatMessageType.Warning, "%1% rows were removed because they exceeded the limit of %2% rows per ruleset."%_T, length - maxRows, maxRows)
                end
            end
        end
    end
    return data
end

function CargoControl.setData(_data)
    for k, v in pairs(_data) do
        data[k] = v
    end
end

function CargoControl.forceRuleset()
    local entity = Entity()
    if not entity:hasComponent(ComponentType.CargoBay) then return end

    Player(callingPlayer):sendChatMessage("", ChatMessageType.Information, "Applying ruleset to currently stored goods."%_t)
    local cargos = {}
    local goodInfo, nameTyped, infos
    --[[ cargos = {
      ['acid_0'] = {
        {good = UsualAcid, amount = 3},
        {good = StolenAcid1, amount = 6}
      },
      ['acid_2'] = {
        {good = StolenAcid1, amount = 6}
      }
    } ]]
    -- sort entity cargo
    local goodTypes = {"suspicious", "stolen", "dangerous", "illegal"}
    for good, amount in pairs(entity:getCargos()) do
        goodInfo = {
          good = good,
          amount = amount
        }
        -- this good but any type
        nameTyped = good.name..'_0'
        if not cargos[nameTyped] then cargos[nameTyped] = {} end
        infos = cargos[nameTyped]
        infos[#infos+1] = goodInfo
        -- separate goods by type
        for goodInt, goodType in ipairs(goodTypes) do
            if good[goodType] then
                -- add to all goods of this type
                nameTyped = '*_'..goodInt
                if not cargos[nameTyped] then cargos[nameTyped] = {} end
                infos = cargos[nameTyped]
                infos[#infos+1] = goodInfo
                -- add to this goods of this type
                nameTyped = good.name..'_'..goodInt
                if not cargos[nameTyped] then cargos[nameTyped] = {} end
                infos = cargos[nameTyped]
                infos[#infos+1] = goodInfo
            end
        end
    end
    -- apply ruleset
    local entity = Entity()
    local dropPos = entity.translationf - entity.up * (entity.radius + entity:getBoostedValue(StatsBonuses.LootCollectionRange, 50)) -- radius + 500m
    local sector = Sector()
    local good
    for _, row in ipairs(data.current.rules) do
        if row.good == 0 then
            infos = cargos['*_'..row.type]
        else
            good = goodsArray[row.good]
            infos = cargos[good.name..'_'..row.type]
        end
        if infos then
            for k, info in pairs(infos) do
                if info.amount > 0 then
                    entity:removeCargo(info.good, info.amount)
                    if row.action == 1 then
                        sector:dropCargo(dropPos, nil, nil, info.good, -1, info.amount)
                    end
                    info.amount = 0
                end
            end
        end
    end
end


end