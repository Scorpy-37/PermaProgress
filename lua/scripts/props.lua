if SERVER then
	SPP = SPP or {}

	local class_blacklist = { 
        "player", 
        "beam", 
        "predicted_viewmodel", 
        "gmod_hands", 
        "money_printer",
        "weed_plant",
        "weed_seed",
        "weed_box",
        "darkrp_tip_jar",
        "weed_npc"
    } -- what not to save

    function SPP.WriteEntitiesToFile(filename)
        local allEnts = {}

        for _, ent in ipairs(ents.GetAll()) do
            if
                not IsValid(ent) or
                ent:CreatedByMap() or
                ent:GetModel() == nil or
                ent:GetOwner():IsPlayer() or
                ent.spp_entityOwner == nil
            then
                continue
            end

            if ent.spp_entityOwner[1] == "NONE" then
                continue
            end

            for i,v in ipairs(class_blacklist) do
                if ent:GetClass() == v then
                    continue
                end
            end

            table.insert(allEnts, ent)
        end

        table.insert(allEnts, game.GetWorld())

        if not file.IsDir(SPP.directory, "DATA") then
            file.CreateDir(SPP.directory)
        end

        local outputFile = SPP.directory .. "/" .. filename .. SPP.defaultext

        local data = duplicator.CopyEnts(allEnts)
        local serializedJson = util.TableToJSON(data)

        file.Write(outputFile, serializedJson)

        SPP.Log("Saved current world state to " .. outputFile)

        if SPP.doNotifs:GetInt() == 1 then
            for _,ply in ipairs(player.GetAll()) do
                ply:SendLua([[ notification.AddLegacy("[PermaProgress] Saved world state to file", NOTIFY_GENERIC, 3) surface.PlaySound("ambient/water/drip1.wav") ]])
            end
        end
    end
    function SPP.ReadEntitiesFromFile(filename)
        local inputFile = SPP.directory .. "/" .. filename .. SPP.defaultext

        if file.Exists(inputFile, "DATA") then
            game.CleanUpMap("all")

            timer.Simple(1, function()
                local serializedJson = file.Read(inputFile, "DATA")

                serializedJson = serializedJson:reverse()
                local startchar = string.find(serializedJson, '')
                if (startchar ~= nil) then
                    serializedJson = string.sub(serializedJson, startchar)
                end
                serializedJson = serializedJson:reverse()

                local data = util.JSONToTable(serializedJson)

                local world = game.GetWorld()
                function world:CheckLimit(arg) -- Create a fake CheckLimit function to avoid errors when pasting constraints
                    return true
                end
                function world:HasLimit(arg) -- Also a fake HasLimit function
                    return false
                end

                duplicator.Paste(world, data.Entities, data.Constraints)

                SPP.Log("Loaded world state from " .. inputFile)

                if SPP.doNotifs:GetInt() == 1 then
                    for _,ply in ipairs(player.GetAll()) do
                        ply:SendLua([[ notification.AddLegacy("[PermaProgress] Loaded world state from file", NOTIFY_GENERIC, 3) surface.PlaySound("ambient/water/drip1.wav") ]])
                    end
                end

                timer.Simple(1, function()
                    SPP.AssignOwners()
                end)
            end)
        else
            SPP.Log("Couldn't find world state file at " .. inputFile)
        end
    end

    return SPP
end