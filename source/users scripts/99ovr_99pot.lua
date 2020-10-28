--- HOW TO USE:
--- https://i.imgur.com/xZMqzTc.gifv
--- 1. Open Cheat table as usuall and enter your career.
--- 2. In Cheat Engine click on "Memory View" button.
--- 3. Press "CTRL + L" to open lua engine
--- 4. Then press "CTRL + O" and open this script
--- 5. Click on 'Execute' button to execute script and wait for 'done' message box.

--- AUTHOR: ARANAKTU

--- It may take a few mins. Cheat Engine will stop responding and it's normal behaviour. Wait until you get 'Done' message.


-- This script will change:
-- Potential to 99
-- Ovr to 99
-- All Attributess to 99

local game_db_manager = gCTManager.game_db_manager
local memory_manager = gCTManager.memory_manager

local fields_to_change = {
    "potential",
    "overallrating",
    
    "gkdiving",
    "gkhandling",
    "gkkicking",
    "gkpositioning",
    "gkreflexes",
    "crossing",
    "finishing",
    "headingaccuracy",
    "shortpassing",
    "volleys",
    "marking",
    "standingtackle",
    "slidingtackle",
    "dribbling",
    "curve",
    "freekickaccuracy",
    "longpassing",
    "ballcontrol",
    "shotpower",
    "jumping",
    "stamina",
    "strength",
    "longshots",
    "acceleration",
    "sprintspeed",
    "agility",
    "reactions",
    "balance",
    "aggression",
    "composure",
    "interceptions",
    "positioning",
    "vision",
    "penalties"
}
local pgs_ptr = memory_manager:read_multilevel_pointer(
    readPointer("pScriptsBase"),
    {0x0, 0x518, 0x0, 0x20, 0xb0}
)

local pgs_start = nil
local pgs_end = nil

if pgs_ptr then
    -- Start list = 0x5b0
    -- end list = 0x5b8
    pgs_start = readPointer(pgs_ptr + 0x5b0)
    pgs_end = readPointer(pgs_ptr + 0x5b8)
end

function get_players_in_player_growth_system()
    local _max = 55
    local result = {}

    if not pgs_ptr then return result end

    if (not pgs_start) or (not pgs_end) then
        return result
    end

    local current_addr = pgs_start
    for i=1, _max do
        if current_addr >= pgs_end then
            return result
        end

        local pid = readInteger(current_addr + PLAYERGROWTHSYSTEM_STRUCT["pid"])
        result[pid] = current_addr
        
        current_addr = current_addr + PLAYERGROWTHSYSTEM_STRUCT["size"]
    end
    return result
end

local pgs = get_players_in_player_growth_system()


function update_cached_field(playerid, field_name, new_value)
    local current_addr = pgs[playerid]
    if not current_addr then
        return
    end

    -- Overwrite cached xp in developement plans
    local field_offset_map = {
        "acceleration",
        "sprintspeed",
        "agility",
        "balance",
        "jumping",
        "stamina",
        "strength",
        "reactions",
        "aggression",
        "composure",
        "interceptions",
        "positioning",
        "vision",
        "ballcontrol",
        "crossing",
        "dribbling",
        "finishing",
        "freekickaccuracy",
        "headingaccuracy",
        "longpassing",
        "shortpassing",
        "marking",
        "shotpower",
        "longshots",
        "standingtackle",
        "slidingtackle",
        "volleys",
        "curve",
        "penalties",
        "gkdiving",
        "gkhandling",
        "gkkicking",
        "gkreflexes",
        "gkpositioning",
        "attackingworkrate",
        "defensiveworkrate",
        "weakfootabilitytypecode",
        "skillmoves"
    }

    local idx = 0
    for i=1, #field_offset_map do
        if field_name == field_offset_map[i] then
            idx = i
            break
        end
    end

    if idx <= 0 then return end

    if new_value < 1 then
        new_value = 1
    else
        if field_name == "attackingworkrate" or field_name == "defensiveworkrate" then
            if new_value > 3 then
                new_value = 3
            end
        elseif field_name == "weakfootabilitytypecode" or field_name == "skillmoves" then
            if new_value > 5 then
                new_value = 5
            end
        end
    end

    local xp_points_to_apply = 1000
    if field_name == "attackingworkrate" or field_name == "defensiveworkrate" then
        local xp_to_wr = {
            5000,    -- medium
            100,    -- low
            10000   -- high
        }
        xp_points_to_apply = xp_to_wr[new_value]
    elseif field_name == "weakfootabilitytypecode" or field_name == "skillmoves" then
        local xp_to_star = {
            100,
            2500,
            5000,
            7500,
            10000
        }
        xp_points_to_apply = xp_to_star[new_value]
    else
        -- Add xp at: 14524d50c

        -- Add xp at: 145434DFC
        -- Xp points needed for attribute
        local xp_to_attribute = {
            1000,
            2101,
            3202,
            4305,
            5410,
            6518,
            7628,
            8742,
            9860,
            10983,
            12110,
            13243,
            14382,
            15528,
            16680,
            17840,
            19008,
            20185,
            21370,
            22565,
            23770,
            24986,
            26212,
            27450,
            28700,
            29963,
            31238,
            32527,
            33830,
            35148,
            36480,
            37828,
            39192,
            40573,
            41970,
            43385,
            44818,
            46270,
            47740,
            49230,
            50740,
            52271,
            53822,
            55395,
            56990,
            58608,
            60248,
            61912,
            63600,
            65313,
            67050,
            68813,
            70602,
            72418,
            74260,
            76130,
            78028,
            79955,
            81910,
            83895,
            85910,
            87956,
            90032,
            92140,
            94280,
            96453,
            98658,
            100897,
            103170,
            105478,
            107820,
            110198,
            112612,
            115063,
            117550,
            120075,
            122638,
            125240,
            127880,
            130560,
            133280,
            136041,
            138842,
            141685,
            144570,
            147498,
            150468,
            153482,
            156540,
            159643,
            162790,
            165983,
            169222,
            172508,
            175840,
            179220,
            182648,
            186125,
            189650
        }
        xp_points_to_apply = xp_to_attribute[new_value]
    end

    local write_to = current_addr+(4*idx)

    writeInteger(write_to, xp_points_to_apply)
end

local first_record = game_db_manager.tables["players"]["first_record"]
local record_size = game_db_manager.tables["players"]["record_size"]
local written_records = game_db_manager.tables["players"]["written_records"]

local row = 0
local current_addr = first_record
local last_byte = 0
local is_record_valid = true

local new_value = 99
while true do
    if row >= written_records then
        break
    end
    current_addr = first_record + (record_size*row)
    last_byte = readBytes(current_addr+record_size-1, 1, true)[1]
    is_record_valid = not (bAnd(last_byte, 128) > 0)
    if is_record_valid then
        local playerid = game_db_manager:get_table_record_field_value(current_addr, "players", "playerid")
        if playerid > 0 then
            for _, fld in ipairs(fields_to_change) do
                game_db_manager:set_table_record_field_value(current_addr, "players", fld, new_value)
                update_cached_field(playerid, fld, new_value)
            end
        end
    end
    row = row + 1
end

showMessage("Done")
