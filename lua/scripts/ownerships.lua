if SERVER then
    SPP = SPP or {}

    function SPP.SetOwner(entity, _owner)
        pcall(function()
            entity:CPPISetOwner(_owner)
            entity.owner = _owner
        end)
    end
    function SPP.AssignOwners()
        local didSetPlayer = false
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local owner = ent.spp_entityOwner

                if owner ~= nil then
                    owner = owner[1]

                    ply = SPP.SteamIDToPlayer(owner)
                    if ply ~= nil then
                        SPP.SetOwner(ent, ply)
                    end

                    didSetPlayer = true
                end
            end
        end
    end
    function SPP.AssignEntityOwner(ent)
        pcall(function()
            local owner = ent.DPPOwner or ent.DarkRP_Owner
            owner = owner:SteamID()
            duplicator.StoreEntityModifier(ent, "spp_entityOwner", { owner })
            ent.spp_entityOwner = { owner }
        end)
        pcall(function()
            local owner = ent:CPPIGetOwner():SteamID()
            duplicator.StoreEntityModifier(ent, "spp_entityOwner", { owner })
            ent.spp_entityOwner = { owner }
        end)
        
        if ent.spp_entityOwner == nil then
            if ent.CPPIGetOwner == nil then
                duplicator.StoreEntityModifier(ent, "spp_entityOwner", { "OWNERSHIPDISABLED" })
                ent.spp_entityOwner = { "OWNERSHIPDISABLED" }
            else
                duplicator.StoreEntityModifier(ent, "spp_entityOwner", { "NONE" })
                ent.spp_entityOwner = { "NONE" }
            end
        end
    end

    return SPP
end