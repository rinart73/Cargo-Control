if onServer() then
    local entity = Entity()
    if not entity.aiOwned and (entity.isShip or entity.isStation) then
        entity:addScriptOnce("cargocontrol.lua")
    end
end