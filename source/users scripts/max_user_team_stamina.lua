--- HOW TO USE:
--- https://i.imgur.com/xZMqzTc.gifv
--- 1. Open Cheat table as usuall and enter your career.
--- 2. In Cheat Engine click on "Memory View" button.
--- 3. Press "CTRL + L" to open lua engine
--- 4. Then press "CTRL + O" and open this script
--- 5. Click on 'Execute' button to execute script and wait for 'done' message box.

--- AUTHOR: ARANAKTU

--- It may take a few mins. Cheat Engine will stop responding and it's normal behaviour. Wait until you get 'Done' message.

-- This script will refill stamina of all players in your team
gCTManager:init_ptrs()
local game_db_manager = gCTManager.game_db_manager
local memory_manager = gCTManager.memory_manager


function get_playerids_for_team(tid)
    local result = {}

    local first_record = game_db_manager.tables["teamplayerlinks"]["first_record"]
    local record_size = game_db_manager.tables["teamplayerlinks"]["record_size"]
    local written_records = game_db_manager.tables["teamplayerlinks"]["written_records"]

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
            local artificialkey = game_db_manager:get_table_record_field_value(current_addr, "teamplayerlinks", "artificialkey")
            if artificialkey > 0 then
                local rec_teamid = game_db_manager:get_table_record_field_value(current_addr, "teamplayerlinks", "teamid")
                if rec_teamid == tid then
                    local playerid = game_db_manager:get_table_record_field_value(current_addr, "teamplayerlinks", "playerid")
                    table.insert(result, playerid)
                end
            end
        end
        row = row + 1
    end

    return result
end

function get_fitness_addr(_start, _end, playerid)
    local current_addr = _start
    local player_found = false
    local _max = 2000
    for i=1, _max do
        if current_addr >= _end then
            -- no player to edit
            break
        end
        --self.logger:debug(string.format("Player Fitness current_addr: %X", current_addr))
        local pid = readInteger(current_addr + PLAYERFITESS_STRUCT["pid"])
        if pid == playerid then
            player_found = true
            break
        end
        current_addr = current_addr + PLAYERFITESS_STRUCT["size"]
    end

    if not player_found then
        return 0
    end
    return current_addr
end

function set_stamina(playerid, val, _start, _end)
    local addr = get_fitness_addr(_start, _end, playerid)
    if (addr <= 0) then return end

    writeBytes(addr + PLAYERFITESS_STRUCT["fitness"], val)
end

function can_edit_player(pids, pid)
    for i=1, #pids do
        if pid == pids[i] then return true end
    end
    return false
end

local fitness_manager_ptr = memory_manager:read_multilevel_pointer(
    readPointer("pCareerModeSmth"),
    {0x0, 0x10, 0x48, 0x30, 0x180+0x50}
)
local _fitnessstart = readPointer(fitness_manager_ptr + 0x19a0)
local _fitnessend = readPointer(fitness_manager_ptr + 0x19a8)
if (not _fitnessstart) or (not _fitnessend) then
    print("No Fitness start or end")
    return
end

local career_users_first_rec = readPointer("pUsersTableFirstRecord")

local userclubteamid = game_db_manager:get_table_record_field_value(career_users_first_rec, "career_users", "clubteamid")
local new_stamina = 100
local playerids_in_team = get_playerids_for_team(userclubteamid)

local first_record = game_db_manager.tables["players"]["first_record"]
local record_size = game_db_manager.tables["players"]["record_size"]
local written_records = game_db_manager.tables["players"]["written_records"]

local row = 0
local current_addr = first_record
local last_byte = 0
local is_record_valid = true

while true do
    if row >= written_records then
        break
    end
    current_addr = first_record + (record_size*row)
    last_byte = readBytes(current_addr+record_size-1, 1, true)[1]
    is_record_valid = not (bAnd(last_byte, 128) > 0)
    if is_record_valid then
        local playerid = game_db_manager:get_table_record_field_value(current_addr, "players", "playerid")
        if playerid > 0 and can_edit_player(playerids_in_team, playerid) then
            set_stamina(playerid, new_stamina, _fitnessstart, _fitnessend)
        end
    end
    row = row + 1
end

showMessage("Done")
