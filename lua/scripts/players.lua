if SERVER then
	SPP = SPP or {}

    SPP.playersLoaded = false
    SPP.playerIsLoaded = {}
    SPP.players = {}

    function SPP.SteamIDToPlayer(steamid)
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID() == steamid then
                return ply
            end
        end
        return nil
    end

    function SPP.WriteAllPlayerData(filename)
        local data = util.TableToJSON(SPP.players, true)
        if not file.IsDir(SPP.directory, "DATA") then
            file.CreateDir(SPP.directory)
        end
        file.Write(SPP.directory .. "/" .. filename .. SPP.defaultext, data)
        --Log("Saved all player data to " .. SPP.directory .. "/" .. filename .. SPP.defaultext)
    end
    function SPP.SaveAndWriteAllPlayerData(filename)
        for _,plr in ipairs(player:GetAll()) do
            SPP.SavePlayerData(plr)
        end
        SPP.WriteAllPlayerData(filename)
    end
    function SPP.ReadAllPlayerData(filename)
        if not file.Exists(SPP.directory .. "/" .. filename .. SPP.defaultext, "DATA") then
            return
        end
        local serializedJson = file.Read(SPP.directory .. "/" .. filename .. SPP.defaultext, "DATA")
        local data = util.JSONToTable(serializedJson)

        SPP.players = data
    end

    function SPP.SavePlayerData(player)
        if not SPP.playersLoaded then
            return false
        end
        if SPP.playerIsLoaded[player:SteamID()] == false then
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
            SPP.players[player:SteamID()] = tbl
        end

        return true
    end
    function SPP.LoadPlayerData(player)
        if not SPP.playersLoaded then
            return false
        end

        data = SPP.players[player:SteamID()]
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

        SPP.playerIsLoaded[player:SteamID()] = true

        return true
    end

    return SPP
end