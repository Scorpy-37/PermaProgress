if SERVER then
    SPP = SPP or {}

    util.AddNetworkString("PermaProgress")
    
    duplicator.RegisterEntityModifier("spp_entityOwner", function(ply, ent, data)
        if not IsValid(ent) then return end
        ent.spp_entityOwner = data
    end)

    local cmdprefix = "spp_"

    local autosaveTime = CreateConVar(cmdprefix.."autosavetime", "300", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Time between PermaProgress autosaves (in seconds)")
    local safeAutoLoad = CreateConVar(cmdprefix.."safeautoload", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should check for props in the map before auto loading the saved world state")
    SPP.doNotifs = CreateConVar(cmdprefix.."sendnotifs", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should send on-screen notifications for when it loads or saves the world state")
    local doSaveProps = CreateConVar(cmdprefix.."saveprops", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should save and load placed props")
    local doSavePlayers = CreateConVar(cmdprefix.."saveplayers", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Whether PermaProgress should save and load player data")

    SPP.prefix = "[PermaProgress]: "
    SPP.directory = "permaprogress"
    SPP.defaultext = ".json"

    local isSaveWorld = false

    function SPP.Log(msg)
        print(SPP.prefix .. msg)
    end

    concommand.Add(cmdprefix.."save", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            return
        end
        SPP.WriteEntitiesToFile(game.GetMap())
        SPP.SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        isSaveWorld = false
    end, nil, "Manually saves the world")
    concommand.Add(cmdprefix.."load", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            return
        end
        SPP.ReadEntitiesFromFile(game.GetMap())
        SPP.ReadAllPlayerData(game.GetMap() .. "_players")
        isSaveWorld = false
    end, nil, "Manually loads the world from save file")

    hook.Add("PlayerDisconnected", "SavePlayerDataOnDisconnect", function(ply)
        SPP.SavePlayerData(ply)
    end)

    hook.Add("Initialize", "StartAutosaveTimer", function()
        timer.Create("AutosaveTimer", autosaveTime:GetInt(), 0, function()
            if doSaveProps:GetInt() == 0 then
                return
            end

            if isSaveWorld then
                return
            end
            SPP.Log("Autosaving...")

            SPP.WriteEntitiesToFile(game.GetMap())
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

            SPP.SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        end)
    end)
    hook.Add("InitPostEntity", "LoadAllOnStart", function()
        timer.Simple(0, function()
            if doSaveProps:GetInt() == 1 then
                for _, ent in ipairs(ents.GetAll()) do
                    if not ent:CreatedByMap() and ent:GetClass() == "prop_physics" then
                        isSaveWorld = true
                        break
                    end
                end

                if isSaveWorld and safeAutoLoad:GetInt() == 1 then
                    SPP.Log("----- IMPORTANT -----")
                    SPP.Log("Detected save load from main menu, to avoid loading the saved world state on top of a save the PermaProgress auto-load has been skipped.")
                    SPP.Log("If you believe this is a mistake use "..SPP.cmdprefix.."load to load the previous world state manually.")
                    SPP.Log("If you would like to disable this check, do '"..SPP.cmdprefix.."safeautoload 0'.")
                    SPP.Log("----- IMPORTANT -----")

                    if SPP.doNotifs:GetInt() == 1 then
                        timer.Simple(2, function()
                            for _,ply in ipairs(player.GetAll()) do
                                ply:SendLua([[ notification.AddLegacy("PermaProgress skipped auto-load, check console for more info", NOTIFY_ERROR, 7) surface.PlaySound("ambient/water/drip1.wav") ]])
                            end
                        end)
                    end

                    return
                end

                SPP.ReadEntitiesFromFile(game.GetMap())
                SPP.AssignOwners()
            end
            if doSavePlayers:GetInt() == 1 then
                SPP.Log("Loading players...")
                SPP.ReadAllPlayerData(game.GetMap() .. "_players")

                for plr in pairs(SPP.players) do
                    SPP.playerIsLoaded[plr] = false
                end
                timer.Simple(0, function()
                    SPP.playersLoaded = true
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
        SPP.Log("Saving world state before shutdown...")
        SPP.WriteEntitiesToFile(game.GetMap())
        -- SaveAndWriteAllPlayerData(game.GetMap() .. "_players")
        -- Don't save player data in Shutdown, players will just show up as "_1_" and loading will fail
    end)

    hook.Add("PlayerInitialSpawn", "AssignOwnerToProps", function(player)
        timer.Simple(1, function()
            SPP.AssignOwners()
        end)
        if doSavePlayers:GetInt() == 0 then
            return
        end
        if isSaveWorld then
            return
        end
        timer.Simple(0, function()
            local loaded = SPP.LoadPlayerData(player)
            if not playersLoaded then
                loaded = false
            end
            timer.Create("Load"..player:SteamID().."Data", 1, 0, function()
                if loaded or isSaveWorld then
                    timer.Simple(1, function()
                        SPP.SavePlayerData(player)
                    end)
                    timer.Remove("Load"..player:SteamID().."Data")
                else
                    loaded = SPP.LoadPlayerData(player)
                    if not SPP.playersLoaded then
                        loaded = false
                    end
                end
            end)
        end)
    end)

    hook.Add("OnEntityCreated", "AssignEntityOwner", function(ent)
        timer.Simple(0, function()
            SPP.AssignEntityOwner(ent)
        end)
    end)

    hook.Add("EntityDuplicatorCopy", "SaveOwnershipData", function(ent, info)
        if IsValid(ent) and ent.spp_entityOwner then
            duplicator.StoreEntityModifier(ent, "spp_entityOwner", ent.spp_entityOwner)
        end
    end)
end