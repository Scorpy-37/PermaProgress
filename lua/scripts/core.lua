if SERVER then
    duplicator.RegisterEntityModifier("spp_entityOwner", function(ply, ent, data)
        if not IsValid(ent) then return end
        ent.spp_entityOwner = data
    end)

    local cmdprefix = "spp_"

    local autosaveTime = CreateConVar(cmdprefix.."autosavetime", "300", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Time between PermaProgress autosaves (in seconds)")
    local safeAutoLoad = CreateConVar(cmdprefix.."safeautoload", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should check for props in the map before auto loading the saved world state")
    local doNotifs = CreateConVar(cmdprefix.."sendnotifs", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should send on-screen notifications for when it loads or saves the world state")
    local doSaveProps = CreateConVar(cmdprefix.."saveprops", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should save and load placed props")
    local doSavePlayers = CreateConVar(cmdprefix.."saveplayers", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should save and load player data")

    util.AddNetworkString("PermaProgress")

    local prefix = "[PermaProgress]: "
    local directory = "permaprogress"
    local defaultext = ".json"

    local isSaveWorld = false

    local playersLoaded = false
    local players = {}

    function Log(msg)
        print(prefix .. msg)
    end

    function SteamIDToPlayer(steamid)
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID() == steamid then
                return ply
            end
        end
        return nil
    end
    function SetOwner(entity, _owner)
        pcall(function()
            entity:CPPISetOwner(_owner)
            entity.owner = _owner
        end)
    end
    function AssignOwners()
        local didSetPlayer = false
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local owner = ent.spp_entityOwner

                if owner ~= nil then
                    owner = owner[1]

                    ply = SteamIDToPlayer(owner)
                    if ply ~= nil then
                        SetOwner(ent, ply)
                    end

                    didSetPlayer = true
                end
            end
        end
    end

    local class_blacklist = { "player", "beam", "predicted_viewmodel", "gmod_hands", "weed_plant" } -- what not to save
    function WriteEntitiesToFile(filename)
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

            for i,v in ipairs(class_blacklist) do
                if ent:GetClass() == v then
                    continue
                end
            end

            table.insert(allEnts, ent)
        end

        table.insert(allEnts, game.GetWorld())

        if not file.IsDir(directory, "DATA") then
            file.CreateDir(directory)
        end

        local outputFile = directory .. "/" .. filename .. defaultext

        local data = duplicator.CopyEnts(allEnts)
        local serializedJson = util.TableToJSON(data)

        file.Write(outputFile, serializedJson)

        Log("Saved current world state to " .. outputFile)

        if doNotifs:GetInt() == 1 then
            for _,ply in ipairs(player.GetAll()) do
                ply:SendLua([[ notification.AddLegacy("[PermaProgress] Saved world state to file", NOTIFY_GENERIC, 3) surface.PlaySound("ambient/water/drip1.wav") ]])
            end
        end
    end
    function ReadEntitiesFromFile(filename)
        local inputFile = directory .. "/" .. filename .. defaultext

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

                Log("Loaded world state from " .. inputFile)

                if doNotifs:GetInt() == 1 then
                    for _,ply in ipairs(player.GetAll()) do
                        ply:SendLua([[ notification.AddLegacy("[PermaProgress] Loaded world state from file", NOTIFY_GENERIC, 3) surface.PlaySound("ambient/water/drip1.wav") ]])
                    end
                end

                timer.Simple(1, function()
                    AssignOwners()
                end)
            end)
        else
            Log("Couldn't find world state file at " .. inputFile)
        end
    end

    local playerIsLoaded = {}

    function WriteAllPlayerData(filename)
        local data = util.TableToJSON(players, true)
        if not file.IsDir(directory, "DATA") then
            file.CreateDir(directory)
        end
        file.Write(directory .. "/" .. filename .. defaultext, data)
        --Log("Saved all player data to " .. directory .. "/" .. filename .. defaultext)
    end
    function SaveAndWriteAllPlayerData(filename)
        for _,plr in ipairs(player:GetAll()) do
            SavePlayerData(plr)
        end
        WriteAllPlayerData(filename)
    end
    function ReadAllPlayerData(filename)
        if not file.Exists(directory .. "/" .. filename .. defaultext, "DATA") then
            return
        end
        local serializedJson = file.Read(directory .. "/" .. filename .. defaultext, "DATA")
        local data = util.JSONToTable(serializedJson)

        players = data
    end

    function SavePlayerData(player)
        if not playersLoaded then
            return false
        end
        if playerIsLoaded[player:SteamID()] == false then
            return false
        end

        local tbl = {
            position = {
                x = player:GetPos().x,
                y = player:GetPos().y,
                z = player:GetPos().z
            },
            rotation = {
                pitch = player:EyeAngles().p, 
                yaw = player:EyeAngles().y, 
                roll = player:EyeAngles().r
            },
            health = player:Health(),
            armor = player:Armor(),
            weapons = {},
            active = "nil"
        }
        if player ~= nil and IsValid(player:GetActiveWeapon()) then
            tbl.active = player:GetActiveWeapon():GetClass()
        end

        for _, wep in ipairs(player:GetWeapons()) do
            table.insert(tbl.weapons, {
                class = wep:GetClass(),
                clip1 = wep:Clip1(),
                ammo1 = player:GetAmmoCount(wep:GetPrimaryAmmoType()),
                ammo2 = player:GetAmmoCount(wep:GetSecondaryAmmoType())
            })
        end

        local id = player:SteamID()
        if id ~= "_1_" then
            players[player:SteamID()] = tbl
        end

        return true
    end
    function LoadPlayerData(player)
        if not playersLoaded then
            return false
        end

        data = players[player:SteamID()]
        if data == nil then
            return true
        end

        player:SetPos(Vector(data.position.x, data.position.y, data.position.z))
        player:SetEyeAngles(Angle(data.rotation.pitch, data.rotation.yaw, data.rotation.roll))

        player:SetHealth(data.health or player:Health())
        player:SetArmor(data.armor or player:Armor())

        player:StripWeapons()

        if data.weapons then
            for _, wep in ipairs(data.weapons) do
                local given = player:Give(wep.class)
                if IsValid(given) then
                    given:SetClip1(wep.clip1 or 0)

                    local ammo1 = wep.ammo1 or 0
                    local ammo2 = wep.ammo2 or 0

                    player:GiveAmmo(ammo1, given:GetPrimaryAmmoType(), true)
                    player:GiveAmmo(ammo2, given:GetSecondaryAmmoType(), true)
                end
            end
        end
        if data.active ~= "nil" then
            player:SelectWeapon(data.active)
        end

        playerIsLoaded[player:SteamID()] = true

        return true
    end

    concommand.Add(cmdprefix.."save", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            return
        end
        WriteEntitiesToFile(game.GetMap())
        SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        isSaveWorld = false
    end, nil, "Manually saves the world")
    concommand.Add(cmdprefix.."load", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            return
        end
        ReadEntitiesFromFile(game.GetMap())
        ReadAllPlayerData(game.GetMap() .. "_players")
        isSaveWorld = false
    end, nil, "Manually loads the world from save file")
    concommand.Add(cmdprefix.."test", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            return
        end
        for _,v in ipairs(ents:GetAll()) do
            if not v:CreatedByMap() then
                Log(v.spp_entityOwner[1])
            end
        end
    end, nil, "Prints all prop owners")

    hook.Add("PlayerDisconnected", "SavePlayerDataOnDisconnect", function(ply)
        SavePlayerData(ply)
    end)

    hook.Add("Initialize", "StartAutosaveTimer", function()
        timer.Create("AutosaveTimer", autosaveTime:GetInt(), 0, function()
            if doSaveProps:GetInt() == 0 then
                return
            end

            if isSaveWorld then
                return
            end
            Log("Autosaving...")

            WriteEntitiesToFile(game.GetMap())
        end)
        timer.Create("PlayerAutosaveTimer", 1, 0, function()
            if doSaveProps:GetInt() == 0 then
                isSaveWorld = true
            end

            if doSavePlayers:GetInt() == 0 then
                return
            end

            if isSaveWorld then
                return
            end

            SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        end)
    end)
    hook.Add("InitPostEntity", "LoadAllOnStart", function()
        timer.Simple(1, function()
            if doSaveProps:GetInt() == 1 then
                for _, ent in ipairs(ents.GetAll()) do
                    if not ent:CreatedByMap() and ent:GetClass() == "prop_physics" then
                        isSaveWorld = true
                        break
                    end
                end

                if isSaveWorld and safeAutoLoad:GetInt() == 1 then
                    Log("----- IMPORTANT -----")
                    Log("Detected save load from main menu, to avoid loading the saved world state on top of a save the PermaProgress auto-load has been skipped.")
                    Log("If you believe this is a mistake use "..cmdprefix.."load to load the previous world state manually.")
                    Log("If you would like to disable this check, do '"..cmdprefix.."safeautoload 0'.")
                    Log("----- IMPORTANT -----")

                    if doNotifs:GetInt() == 1 then
                        timer.Simple(2, function()
                            for _,ply in ipairs(player.GetAll()) do
                                ply:SendLua([[ notification.AddLegacy("PermaProgress skipped auto-load, check console for more info", NOTIFY_ERROR, 7) surface.PlaySound("ambient/water/drip1.wav") ]])
                            end
                        end)
                    end

                    return
                end

                ReadEntitiesFromFile(game.GetMap())
                AssignOwners()
            end
            if doSavePlayers:GetInt() == 1 then
                Log("loading players...")
                ReadAllPlayerData(game.GetMap() .. "_players")

                for plr in pairs(players) do
                    playerIsLoaded[plr] = false
                end
                timer.Simple(1, function()
                    playersLoaded = true
                end)
            end
        end)
    end)
    hook.Add("ShutDown", "SaveAllOnQuit", function()
        if doSaveProps:GetInt() == 0 then
            return
        end

        if isSaveWorld then
            return
        end
        Log("Saving world state before shutdown...")
        WriteEntitiesToFile(game.GetMap())
        -- SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        -- Don't save player data in Shutdown, players will just show up as "_1_" and loading will fail
    end)

    hook.Add("PlayerInitialSpawn", "AssignOwnerToProps", function(player)
        timer.Simple(1, function()
            AssignOwners()
        end)
        if doSavePlayers:GetInt() == 0 then
            return
        end
        if isSaveWorld then
            return
        end
        timer.Simple(0, function()
            local loaded = LoadPlayerData(player)
            if not playersLoaded then
                loaded = false
            end
            timer.Create("Load"..player:SteamID().."Data", 1, 0, function()
                if loaded or isSaveWorld then
                    timer.Simple(1, function()
                        SavePlayerData(player)
                    end)
                    timer.Remove("Load"..player:SteamID().."Data")
                else
                    loaded = LoadPlayerData(player)
                    if not playersLoaded then
                        loaded = false
                    end
                end
            end)
        end)
    end)

    hook.Add("OnEntityCreated", "AssignEntityOwner", function(ent)
        timer.Simple(0, function()
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
                duplicator.StoreEntityModifier(ent, "spp_entityOwner", { "NONE" })
                ent.spp_entityOwner = { "NONE" }
            end
        end)
    end)

    hook.Add("EntityDuplicatorCopy", "SaveOwnershipData", function(ent, info)
        if IsValid(ent) and ent.spp_entityOwner then
            duplicator.StoreEntityModifier(ent, "spp_entityOwner", ent.spp_entityOwner)
        end
    end)
end