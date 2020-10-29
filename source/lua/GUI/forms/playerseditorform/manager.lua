require 'lua/consts';
require 'lua/helpers';

local FormManager = require 'lua/imports/FormManager';

local thisFormManager = FormManager:new()

function thisFormManager:new(o)
    o = o or FormManager:new(o)
    setmetatable(o, self)
    self.__index = self
    
    self.dirs = nil
    self.cfg = nil
    self.new_cfg = nil
    self.logger = nil

    self.frm = nil
    self.name = ""

    self.game_db_manager = nil
    self.memory_manager = nil

    self.addr_list = nil
    self.fnSaveCfg = nil
    self.new_cfg = {}
    self.has_unsaved_changes = false
    self.selection_idx = 0

    self.fill_timer = nil
    self.form_components_description = nil
    self.current_addrs = {}
    self.tab_panel_map = {}

    self.change_list = {}

    return o;
end

function thisFormManager:find_player_club_team_record(playerid)
    if type(playerid) == 'string' then
        playerid = tonumber(playerid)
    end

    -- - 78, International
    -- - 2136, International Women
    -- - 76, Rest of World
    -- - 383, Create Player League
    local invalid_leagues = {
        76, 78, 2136, 383
    }

    local arr_flds = {
        {
            name = "playerid",
            expr = "eq",
            values = {playerid}
        }
    }

    local addr = self.game_db_manager:find_record_addr(
        "teamplayerlinks", arr_flds
    )

    if #addr <= 0 then
        self.logger:warning(string.format("No teams for playerid: %d", playerid))
        return 0
    end

    local fnIsLeagueValid = function(invalid_leagues, leagueid)
        for j=1, #invalid_leagues do
            local invalid_leagueid = invalid_leagues[j]
            if invalid_leagueid == leagueid then return false end
        end
        return true
    end

    for i=1, #addr do
        local found_addr = addr[i]
        local teamid = self.game_db_manager:get_table_record_field_value(found_addr, "teamplayerlinks", "teamid")
        local arr_flds_2 = {
            {
                name = "teamid",
                expr = "eq",
                values = {teamid}
            }
        }
        local found_addr2 = self.game_db_manager:find_record_addr(
            "leagueteamlinks", arr_flds_2, 1
        )[1]
        local leagueid = self.game_db_manager:get_table_record_field_value(found_addr2, "leagueteamlinks", "leagueid")
        if fnIsLeagueValid(invalid_leagues, leagueid) then
            self.logger:debug(string.format("found: %X, teamid: %d, leagueid: %d", found_addr, teamid, leagueid))
            writeQword("pTeamplayerlinksTableCurrentRecord", found_addr)
            return found_addr
        end 
    end

    self.logger:warning(string.format("No club teams for playerid: %d", playerid))
    return 0
end

function thisFormManager:find_player_by_id(playerid)
    if type(playerid) == 'string' then
        playerid = tonumber(playerid)
    end

    local arr_flds = {
        {
            name = "playerid",
            expr = "eq",
            values = {playerid}
        }
    }

    local addr = self.game_db_manager:find_record_addr(
        "players", arr_flds, 1 
    )
    for i=1, #addr do
        self.logger:debug(string.format("found: %X", addr[i]))
    end

    writeQword("pPlayersTableCurrentRecord", addr[1])

    return #addr > 0
end

function thisFormManager:update_total_stats()
    local sum = 0
    local attr_panel = self.frm.AttributesPanel
    for i = 0, attr_panel.ControlCount-1 do
        for j=0, attr_panel.Control[i].ControlCount-1 do
            local comp = attr_panel.Control[i].Control[j]
            if comp.ClassName == 'TCEEdit' then
                sum = sum + tonumber(comp.Text)
            end
        end
    end

    if sum > 3366 then
        sum = 3366
    elseif sum < 0 then
        sum = 0
    end

    self.frm.TotalStatsValueLabel.Caption = string.format(
        "%d / 3366", sum
    )
    self.frm.TotalStatsValueBar.Position = sum
end

function thisFormManager:recalculate_ovr(update_ovr_edit)
    local preferred_position_id = self.frm.PreferredPosition1CB.ItemIndex
    if preferred_position_id == 1 then return end -- ignore SW

    -- top 3 values will be put in "Best At"
    local unique_ovrs = {}
    local top_ovrs = {}

    local calculated_ovrs = {}
    for posid, attributes in pairs(OVR_FORMULA) do
        local sum = 0
        for attr, perc in pairs(attributes) do
            local attr_val = tonumber(self.frm[attr].Text)
            if attr_val == nil then
                return
            end
            sum = sum + (attr_val * perc)
        end
        sum = math.round(sum)
        unique_ovrs[sum] = sum

        calculated_ovrs[posid] = sum
    end
    if update_ovr_edit then
        self.frm.OverallEdit.Text = calculated_ovrs[string.format("%d", preferred_position_id)] + tonumber(self.frm.ModifierEdit.Text)
    end
    self.change_list["OverallEdit"] = self.frm.OverallEdit.Text

    for k,v in pairs(unique_ovrs) do
        table.insert(top_ovrs, k)
    end

    table.sort(top_ovrs, function(a,b) return a>b end)

    -- Fill "Best At"
    local position_names = {
        ['1'] = {
            short = {},
            long = {},
            showhint = false
        },
        ['2'] = {
            short = {},
            long = {},
            showhint = false
        },
        ['3'] = {
            short = {},
            long = {},
            showhint = false
        }
    }
    -- remove useless pos
    local not_show = {
        4,6,9,11,13,15,17,19
    }
    for posid, ovr in pairs(calculated_ovrs) do
        for i = 1, #not_show do
            if tonumber(posid) == not_show[i] then
                goto continue
            end
        end
        for i = 1, 3 do
            if ovr == top_ovrs[i] then
                if #position_names[string.format("%d", i)]['short'] <= 2 then
                    table.insert(position_names[string.format("%d", i)]['short'], self.frm.PreferredPosition1CB.Items[tonumber(posid)])
                elseif #position_names[string.format("%d", i)]['short'] == 3 then
                    table.insert(position_names[string.format("%d", i)]['short'], '...')
                    position_names[string.format("%d", i)]['showhint'] = true
                end
                table.insert(position_names[string.format("%d", i)]['long'], self.frm.PreferredPosition1CB.Items[tonumber(posid)])
            end
        end
        ::continue::
    end

    for i = 1, 3 do
        if top_ovrs[i] then
            self.frm[string.format("BestPositionLabel%d", i)].Caption = string.format("- %s: %d ovr", table.concat(position_names[string.format("%d", i)]['short'], '/'), top_ovrs[i])
            if position_names[string.format("%d", i)]['showhint'] then
                self.frm[string.format("BestPositionLabel%d", i)].Hint = string.format("- %s: %d ovr", table.concat(position_names[string.format("%d", i)]['long'], '/'), top_ovrs[i])
                self.frm[string.format("BestPositionLabel%d", i)].ShowHint = true
            else
                self.frm[string.format("BestPositionLabel%d", i)].ShowHint = false
            end
        else
            self.frm[string.format("BestPositionLabel%d", i)].Caption = '-'
            self.frm[string.format("BestPositionLabel%d", i)].ShowHint = false
        end
    end

    self:update_total_stats()
end

function thisFormManager:roll_random_attributes(components)
    self.has_unsaved_changes = true
    for i=1, #components do
        -- tmp disable onchange event
        local onchange_event = self.frm[components[i]].OnChange
        self.frm[components[i]].OnChange = nil
        self.frm[components[i]].Text = math.random(ATTRIBUTE_BOUNDS['min'], ATTRIBUTE_BOUNDS['max'])
        self.frm[components[i]].OnChange = onchange_event

        self.change_list[components[i]] = self.frm[components[i]].Text 
    end
    self:update_trackbar(self.frm[components[1]])
    self:recalculate_ovr(true)
    
end

function thisFormManager:update_cached_field(playerid, field_name, new_value)
    self.logger:info(string.format(
        "update_cached_field (%s) for playerid: %d. new_val = %d", 
        field_name, playerid, new_value
    ))
    local pgs_ptr = self.memory_manager:read_multilevel_pointer(
        readPointer("pScriptsBase"),
        {0x0, 0x518, 0x0, 0x20, 0xb0}
    )
    -- Start list = 0x5b0
    -- end list = 0x5b8

    
    if not pgs_ptr then
        self.logger:info("No PlayerGrowthSystem pointer")
        return
    end
    local _start = readPointer(pgs_ptr + 0x5b0)
    local _end = readPointer(pgs_ptr + 0x5b8)
    if (not _start) or (not _end) then
        self.logger:info("No PlayerGrowthSystem start or end")
        return
    end
    local _max = 55

    local current_addr = _start
    local player_found = false
    for i=1, _max do
        -- self.logger:debug(string.format(
        --     "PlayerGrowthSystem Current - 0x%X, End - 0x%X",
        --     current_addr, _end
        -- ))
        if current_addr >= _end then
            -- no player to edit
            return
        end

        local pid = readInteger(current_addr + PLAYERGROWTHSYSTEM_STRUCT["pid"])
        if pid == playerid then
            player_found = true
            break
        end
        
        current_addr = current_addr + PLAYERGROWTHSYSTEM_STRUCT["size"]
    end

    if not player_found then return end

    self.logger:info(string.format(
        "Found PlayerGrowthSystem for: %d at 0x%X",
        playerid, current_addr
    ))

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
    self.logger:debug(string.format("update_cached_field: %s", field_name))

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
    self.logger:debug(string.format(
        "XP: %d write to: 0x%X",
        xp_points_to_apply, write_to
    ))

    writeInteger(write_to, xp_points_to_apply)
end

function thisFormManager:get_components_description()
    local fnCommonOnChange = function(sender)
        -- self.logger:debug(string.format("thisFormManager: %s", sender.Name))
        self.has_unsaved_changes = true
        self.change_list[sender.Name] = sender.Text or sender.ItemIndex
    end

    local fnOnChangeAttribute = function(sender)
        if sender.Text == '' then return end
        self.has_unsaved_changes = true

        local new_val = tonumber(sender.Text)
        if new_val == nil then
            -- only numbers
            new_val = math.random(ATTRIBUTE_BOUNDS['min'],ATTRIBUTE_BOUNDS['max'])
        elseif new_val > ATTRIBUTE_BOUNDS['max'] then
            new_val = ATTRIBUTE_BOUNDS['max']
        elseif new_val < ATTRIBUTE_BOUNDS['min'] then
            new_val = ATTRIBUTE_BOUNDS['min']
        end
        sender.Text = new_val

        self:update_trackbar(sender)
        self:recalculate_ovr(true)

        self.change_list[sender.Name] = sender.Text
    end

    local fnOnChangeTrait = function(sender)
        self.has_unsaved_changes = true
        self.change_list[sender.Name] = sender.State >= 1
    end

    local fnCommonDBValGetter = function(addrs, table_name, field_name, raw)
        local addr = addrs[table_name]
        return self.game_db_manager:get_table_record_field_value(addr, table_name, field_name, raw)
    end

    local AttributesTrackBarOnChange = function(sender)
        local comp_desc = self.form_components_description[sender.Name]

        local new_val = sender.Position

        local lbl = self.frm[comp_desc['components_inheriting_value'][1]]
        local diff = new_val - tonumber(lbl.Caption)
        if comp_desc['depends_on'] then
            for i=1, #comp_desc['depends_on'] do
                local new_attr_val = tonumber(self.frm[comp_desc['depends_on'][i]].Text) + diff
                if new_attr_val > ATTRIBUTE_BOUNDS['max'] then
                    new_attr_val = ATTRIBUTE_BOUNDS['max']
                elseif new_attr_val < ATTRIBUTE_BOUNDS['min'] then
                    new_attr_val = ATTRIBUTE_BOUNDS['min']
                end
                -- save onchange event function
                local onchange_event = self.frm[comp_desc['depends_on'][i]].OnChange
                -- tmp disable onchange event
                self.frm[comp_desc['depends_on'][i]].OnChange = nil
                -- update value
                self.frm[comp_desc['depends_on'][i]].Text = new_attr_val
                self.change_list[comp_desc['depends_on'][i]] = new_attr_val

                -- restore onchange event
                self.frm[comp_desc['depends_on'][i]].OnChange = onchange_event
            end
        end

        lbl.Caption = new_val
        sender.SelEnd = new_val
        self:recalculate_ovr(true)
    end

    local fnTraitCheckbox = function(addrs, comp_desc)
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]

        local addr = addrs[table_name]

        local traitbitfield = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name)
        
        local is_set = bAnd(bShr(traitbitfield, comp_desc["trait_bit"]), 1)

        return is_set
    end

    local fnSaveTrait = function(addrs, comp_name, comp_desc)
        local component = self.frm[comp_name]
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]

        local addr = addrs[table_name]
        

        local traitbitfield = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name)
        local is_set = component.State >= 1

        if is_set then
            traitbitfield = bOr(traitbitfield, bShl(1, comp_desc["trait_bit"]))
            self.logger:debug(string.format("v is set: %d", traitbitfield))
        else
            traitbitfield = bAnd(traitbitfield, bNot(bShl(1, comp_desc["trait_bit"])))
            self.logger:debug(string.format("v not: %d", traitbitfield))
        end
        self.logger:debug(string.format("Save Trait: %d", traitbitfield))

        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, traitbitfield)
    end

    local fnDBValDaysToDate = function(addrs, table_name, field_name, raw)
        local addr = addrs[table_name]
        local days = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name, raw)
        local date = days_to_date(days)
        local result = string.format(
            "%02d/%02d/%04d", 
            date["day"], date["month"], date["year"]
        )
        return result
    end

    local fnSaveCommonCB = function(addrs, comp_name, comp_desc)
        local component = self.frm[comp_name]
        local cb_rec_id = comp_desc["cb_id"]
        local new_value = 0
        if cb_rec_id then
            local dropdown = getAddressList().getMemoryRecordByID(cb_rec_id)
            local dropdown_items = dropdown.DropDownList
            local dropdown_selected_value = dropdown.Value
        
            for j = 0, dropdown_items.Count-1 do
                local val, desc = string.match(dropdown_items[j], "(%d+): '(.+)'")
                if component.Items[component.ItemIndex] == desc then
                    new_value = tonumber(val)
                    break
                end
            end
        else 
            new_value = component.ItemIndex
        end

        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]
        local raw = comp_desc["db_field"]["raw_val"]

        local addr = addrs[table_name]

        local log_msg = string.format(
            "%X, %s - %s = %d",
            addr, table_name, field_name, new_value
        )
        self.logger:debug(log_msg)
        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, new_value, raw)

        if comp_desc["db_field"]["is_in_dev_plan"] then
            self:update_cached_field(tonumber(self.frm.PlayerIDEdit.Text), field_name, new_value + 1)
        end
        
    end

    local fnSaveJoinTeamDate = function(addrs, comp_name, comp_desc)
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]
        local addr = addrs[table_name]

        local new_value = 157195 -- 03/03/2013
        local d, m, y = string.match(self.frm[comp_name].Text, "(%d+)/(%d+)/(%d+)")
        if (not d) or (not m) or (not y) then
            self.logger:error(string.format(
                "Invalid date format in %s component: %s doesn't match DD/MM/YYYY pattern",
                comp_name, self.frm[comp_name].Text)
            )
        else
            new_value = date_to_days({
                day=tonumber(d),
                month=tonumber(m),
                year=tonumber(y)
            })
        end

        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, new_value, raw)
    end

    

    local fnSaveCommon = function(addrs, comp_name, comp_desc)
        if comp_desc["not_editable"] then return end

        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]

        local addr = addrs[table_name]

        local new_value = tonumber(self.frm[comp_name].Text)
        local log_msg = string.format(
            "%X, %s - %s = %d",
            addr, table_name, field_name, new_value
        )
        self.logger:debug(log_msg)
        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, new_value)
    end

    local fnSaveAttributeChange = function(addrs, comp_name, comp_desc)
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]

        local addr = addrs[table_name]

        local new_value = tonumber(self.frm[comp_name].Text)
        local log_msg = string.format(
            "%X, %s - %s = %d",
            addr, table_name, field_name, new_value
        )
        self.logger:debug(log_msg)
        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, new_value)
        self:update_cached_field(tonumber(self.frm.PlayerIDEdit.Text), field_name, new_value)
    end

    local fnGetPlayerAge = function(addrs, table_name, field_name, raw)
        local addr = addrs[table_name]
        local bdatedays = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name, raw)
        local bdate = days_to_date(bdatedays)

        self.logger:debug(
            string.format(
                "Player Birthdate: %02d/%02d/%04d", 
                bdate["day"], bdate["month"], bdate["year"]
            )
        )

        local int_current_date = self.game_db_manager:get_table_record_field_value(
            addrs["career_calendar"], "career_calendar", "currdate"
        )

        local current_date = {
            day = 1,
            month = 7,
            year = 2020
        }

        if int_current_date > 20080101 then
            local s_currentdate = tostring(int_current_date)
            current_date = {
                day = tonumber(string.sub(s_currentdate, 7, 8)),
                month = tonumber(string.sub(s_currentdate, 5, 6)),
                year = tonumber(string.sub(s_currentdate, 1, 4)),
            }
        end

        self.logger:debug(
            string.format(
                "Current Date: %02d/%02d/%04d", 
                current_date["day"], current_date["month"], current_date["year"]
            )
        )
        return calculate_age(current_date, bdate)
    end

    local fnSavePlayerAge = function(addrs, comp_name, comp_desc)
        
        local new_age = tonumber(self.frm[comp_name].Text)
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]
        local current_age = fnGetPlayerAge(addrs, table_name, field_name)
        local addr = addrs[table_name]

        if new_age == current_age then return end
        local bdatedays = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name, raw)

        bdatedays = bdatedays + ((current_age - new_age) * 366)

        self.game_db_manager:set_table_record_field_value(addr, table_name, field_name, bdatedays)
    end

    local fnFillCommonCB = function(sender, current_value, cb_rec_id)
        local has_items = sender.Items.Count > 0

        if type(tonumber) ~= "string" then
            current_value = tostring(current_value)
        end

        sender.Hint = ""

        local dropdown = getAddressList().getMemoryRecordByID(cb_rec_id)
        local dropdown_items = dropdown.DropDownList
        for j = 0, dropdown_items.Count-1 do
            local val, desc = string.match(dropdown_items[j], "(%d+): '(.+)'")
            -- self.logger:debug(string.format("val: %d (%s)", val, type(val)))
            if not has_items then
                -- Fill combobox in GUI with values from memory record dropdown
                sender.items.add(desc)
            end

            if current_value == val then
                -- self.logger:debug(string.format("Nationality: %d", current_value))
                sender.Hint = desc
                sender.ItemIndex = j

                if has_items then return end
            end
        end
    end
    local components_description = {
        PlayerIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "playerid"
            },
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            },
            not_editable = true
        },
        OverallEdit = {
            db_field = {
                table_name = "players",
                field_name = "overallrating"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PotentialEdit = {
            db_field = {
                table_name = "players",
                field_name = "potential"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AgeEdit = {
            db_field = {
                table_name = "players",
                field_name = "birthdate"
            },
            valGetter = fnGetPlayerAge,
            OnSaveChanges = fnSavePlayerAge,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FirstNameIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "firstnameid"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LastNameIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "lastnameid"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        CommonNameIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "commonnameid"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        JerseyNameIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "playerjerseynameid"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKSaveTypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "gksavetype"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKKickStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkkickstyle"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ContractValidUntilEdit = {
            db_field = {
                table_name = "players",
                field_name = "contractvaliduntil"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PlayerJoinTeamDateEdit = {
            db_field = {
                table_name = "players",
                field_name = "playerjointeamdate"
            },
            valGetter = fnDBValDaysToDate,
            OnSaveChanges = fnSaveJoinTeamDate,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        JerseyNumberEdit = {
            db_field = {
                table_name = "teamplayerlinks",
                field_name = "jerseynumber"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        NationalityCB = {
            db_field = {
                table_name = "players",
                field_name = "nationality"
            },
            cb_id = CT_MEMORY_RECORDS["PLAYERS_NATIONALITY"],
            cbFiller = fnFillCommonCB,
            OnSaveChanges = fnSaveCommonCB,
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PreferredPosition1CB = {
            db_field = {
                table_name = "players",
                field_name = "preferredposition1"
            },
            cb_id = CT_MEMORY_RECORDS["PLAYERS_PRIMARY_POS"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PreferredPosition2CB = {
            db_field = {
                table_name = "players",
                field_name = "preferredposition2",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["PLAYERS_SECONDARY_POS"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PreferredPosition3CB = {
            db_field = {
                table_name = "players",
                field_name = "preferredposition3",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["PLAYERS_SECONDARY_POS"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PreferredPosition4CB = {
            db_field = {
                table_name = "players",
                field_name = "preferredposition4",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["PLAYERS_SECONDARY_POS"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        IsRetiringCB = {
            db_field = {
                table_name = "players",
                field_name = "isretiring",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["NO_YES_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GenderCB = {
            db_field = {
                table_name = "players",
                field_name = "gender",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["GENDER_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AttackingWorkRateCB = {
            db_field = {
                table_name = "players",
                field_name = "attackingworkrate",
                raw_val = true,
                is_in_dev_plan = true
            },
            cb_id = CT_MEMORY_RECORDS["WR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        DefensiveWorkRateCB = {
            db_field = {
                table_name = "players",
                field_name = "defensiveworkrate",
                raw_val = true,
                is_in_dev_plan = true
            },
            cb_id = CT_MEMORY_RECORDS["WR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SkillMovesCB = {
            db_field = {
                table_name = "players",
                field_name = "skillmoves",
                raw_val = true,
                is_in_dev_plan = true
            },
            cb_id = CT_MEMORY_RECORDS["FIVE_STARS_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        WeakFootCB = {
            db_field = {
                table_name = "players",
                field_name = "weakfootabilitytypecode",
                raw_val = true,
                is_in_dev_plan = true
            },
            cb_id = CT_MEMORY_RECORDS["FIVE_STARS_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        InternationalReputationCB = {
            db_field = {
                table_name = "players",
                field_name = "internationalrep",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["FIVE_STARS_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PreferredFootCB = {
            db_field = {
                table_name = "players",
                field_name = "preferredfoot",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["PREFERREDFOOT_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        
        AttackTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Attack',
            components_inheriting_value = {
                "AttackValueLabel",
            },
            depends_on = {
                "CrossingEdit", "FinishingEdit", "HeadingAccuracyEdit",
                "ShortPassingEdit", "VolleysEdit"
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },
        -- Attributes
        CrossingEdit = {
            db_field = {
                table_name = "players",
                field_name = "crossing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        FinishingEdit = {
            db_field = {
                table_name = "players",
                field_name = "finishing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        HeadingAccuracyEdit = {
            db_field = {
                table_name = "players",
                field_name = "headingaccuracy"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        ShortPassingEdit = {
            db_field = {
                table_name = "players",
                field_name = "shortpassing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        VolleysEdit = {
            db_field = {
                table_name = "players",
                field_name = "volleys"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        DefendingTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Defending',
            components_inheriting_value = {
                "DefendingValueLabel",
            },
            depends_on = {
                "MarkingEdit", "StandingTackleEdit", "SlidingTackleEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        MarkingEdit = {
            db_field = {
                table_name = "players",
                field_name = "marking"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        StandingTackleEdit = {
            db_field = {
                table_name = "players",
                field_name = "standingtackle"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        SlidingTackleEdit = {
            db_field = {
                table_name = "players",
                field_name = "slidingtackle"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        SkillTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Skill',
            components_inheriting_value = {
                "SkillValueLabel",
            },
            depends_on = {
                "DribblingEdit", "CurveEdit", "FreeKickAccuracyEdit",
                "LongPassingEdit", "BallControlEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        DribblingEdit = {
            db_field = {
                table_name = "players",
                field_name = "dribbling"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        CurveEdit = {
            db_field = {
                table_name = "players",
                field_name = "curve"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        FreeKickAccuracyEdit = {
            db_field = {
                table_name = "players",
                field_name = "freekickaccuracy"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        LongPassingEdit = {
            db_field = {
                table_name = "players",
                field_name = "longpassing"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        BallControlEdit = {
            db_field = {
                table_name = "players",
                field_name = "ballcontrol"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        GoalkeeperTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Goalkeeper',
            components_inheriting_value = {
                "GoalkeeperValueLabel",
            },
            depends_on = {
                "GKDivingEdit", "GKHandlingEdit", "GKKickingEdit",
                "GKPositioningEdit", "GKReflexEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        GKDivingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkdiving"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        GKHandlingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkhandling"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        GKKickingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkkicking"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        GKPositioningEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkpositioning"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        GKReflexEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkreflexes"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        PowerTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Power',
            components_inheriting_value = {
                "PowerValueLabel",
            },
            depends_on = {
                "ShotPowerEdit", "JumpingEdit", "StaminaEdit",
                "StrengthEdit", "LongShotsEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        ShotPowerEdit = {
            db_field = {
                table_name = "players",
                field_name = "shotpower"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        JumpingEdit = {
            db_field = {
                table_name = "players",
                field_name = "jumping"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        StaminaEdit = {
            db_field = {
                table_name = "players",
                field_name = "stamina"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        StrengthEdit = {
            db_field = {
                table_name = "players",
                field_name = "strength"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        LongShotsEdit = {
            db_field = {
                table_name = "players",
                field_name = "longshots"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        MovementTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Movement',
            components_inheriting_value = {
                "MovementValueLabel",
            },
            depends_on = {
                "AccelerationEdit", "SprintSpeedEdit", "AgilityEdit",
                "ReactionsEdit", "BalanceEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        AccelerationEdit = {
            db_field = {
                table_name = "players",
                field_name = "acceleration"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        SprintSpeedEdit = {
            db_field = {
                table_name = "players",
                field_name = "sprintspeed"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        AgilityEdit = {
            db_field = {
                table_name = "players",
                field_name = "agility"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        ReactionsEdit = {
            db_field = {
                table_name = "players",
                field_name = "reactions"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        BalanceEdit = {
            db_field = {
                table_name = "players",
                field_name = "balance"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        MentalityTrackBar = {
            valGetter = AttributesTrackBarVal,
            group = 'Mentality',
            components_inheriting_value = {
                "MentalityValueLabel",
            },
            depends_on = {
                "AggressionEdit", "ComposureEdit", "InterceptionsEdit",
                "AttackPositioningEdit", "VisionEdit", "PenaltiesEdit",
            },
            events = {
                OnChange = AttributesTrackBarOnChange,
            }
        },

        AggressionEdit = {
            db_field = {
                table_name = "players",
                field_name = "aggression"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        ComposureEdit = {
            db_field = {
                table_name = "players",
                field_name = "composure"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        InterceptionsEdit = {
            db_field = {
                table_name = "players",
                field_name = "interceptions"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        AttackPositioningEdit = {
            db_field = {
                table_name = "players",
                field_name = "positioning"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        VisionEdit = {
            db_field = {
                table_name = "players",
                field_name = "vision"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },
        PenaltiesEdit = {
            db_field = {
                table_name = "players",
                field_name = "penalties"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveAttributeChange,
            events = {
                OnChange = fnOnChangeAttribute
            }
        },

        LongThrowInCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 0,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        PowerFreeKickCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 1,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        InjuryProneCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 2,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        SolidPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 3,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        LeadershipCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 6,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        EarlyCrosserCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 7,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        FinesseShotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 8,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        FlairCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 9,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        SpeedDribblerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 12,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        GKLongthrowCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 14,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        PowerheaderCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 15,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        GiantthrowinCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 16,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        OutsitefootshotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 17,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        SwervePassCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 18,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        SecondWindCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 19,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        FlairPassesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 20,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        BicycleKicksCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 21,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        GKFlatKickCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 22,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        OneClubPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 23,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        TeamPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 24,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        RushesOutOfGoalCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 27,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        CautiousWithCrossesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 28,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        ComesForCrossessCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 29,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },

        SaveswithFeetCB = {
            db_field = {
                table_name = "players",
                field_name = "trait2"
            },
            trait_bit = 1,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        SetPlaySpecialistCB = {
            db_field = {
                table_name = "players",
                field_name = "trait2"
            },
            trait_bit = 2,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        DivesIntoTacklesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 4,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        LongPasserCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 10,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        LongShotTakerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 11,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        PlaymakerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 13,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        ChipShotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 25,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },
        TechnicalDribblerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 26,
            valGetter = fnTraitCheckbox,
            OnSaveChanges = fnSaveTrait,
            events = {
                OnChange = fnOnChangeTrait
            }
        },

        -- Appearance
        HeightEdit = {
            db_field = {
                table_name = "players",
                field_name = "height"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        WeightEdit = {
            db_field = {
                table_name = "players",
                field_name = "weight"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        BodyTypeCB = {
            db_field = {
                table_name = "players",
                field_name = "bodytypecode",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["BODYTYPE_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HeadTypeCodeCB = {
            db_field = {
                table_name = "players",
                field_name = "headtypecode",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["HEADTYPE_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HairColorCB = {
            db_field = {
                table_name = "players",
                field_name = "haircolorcode",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["HAIRCOLOR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HairTypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "hairtypecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HairStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "hairstylecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FacialHairTypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "facialhairtypecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FacialHairColorEdit = {
            db_field = {
                table_name = "players",
                field_name = "facialhaircolorcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SideburnsEdit = {
            db_field = {
                table_name = "players",
                field_name = "sideburnscode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        EyebrowEdit = {
            db_field = {
                table_name = "players",
                field_name = "eyebrowcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        EyeColorEdit = {
            db_field = {
                table_name = "players",
                field_name = "eyecolorcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SkinTypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "skintypecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SkinColorCB =  {
            db_field = {
                table_name = "players",
                field_name = "skintonecode",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["SKINCOLOR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooHeadEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattoohead"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooFrontEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattoofront"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooBackEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattooback"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooRightArmEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattoorightarm"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooLeftArmEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattooleftarm"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooRightLegEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattoorightleg"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TattooLeftLegEdit = {
            db_field = {
                table_name = "players",
                field_name = "tattooleftleg"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HasHighQualityHeadCB = {
            db_field = {
                table_name = "players",
                field_name = "hashighqualityhead",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["NO_YES_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommonCB,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HeadAssetIDEdit = {
            db_field = {
                table_name = "players",
                field_name = "headassetid"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HeadVariationEdit = {
            db_field = {
                table_name = "players",
                field_name = "headvariation"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HeadClassCodeEdit = {
            db_field = {
                table_name = "players",
                field_name = "headclasscode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        JerseyStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "jerseystylecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        JerseyFitEdit = {
            db_field = {
                table_name = "players",
                field_name = "jerseyfit"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        jerseysleevelengthEdit = {
            db_field = {
                table_name = "players",
                field_name = "jerseysleevelengthcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        hasseasonaljerseyEdit = {
            db_field = {
                table_name = "players",
                field_name = "hasseasonaljersey"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        shortstyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "shortstyle"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        socklengthEdit = {
            db_field = {
                table_name = "players",
                field_name = "socklengthcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        GKGloveTypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkglovetypecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        shoetypeEdit = {
            db_field = {
                table_name = "players",
                field_name = "shoetypecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        shoedesignEdit = {
            db_field = {
                table_name = "players",
                field_name = "shoedesigncode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        shoecolorEdit1 = {
            db_field = {
                table_name = "players",
                field_name = "shoecolorcode1"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        shoecolorEdit2 = {
            db_field = {
                table_name = "players",
                field_name = "shoecolorcode2"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryEdit1 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycode1"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryColourEdit1 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycolourcode1"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryEdit2 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycode2"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryColourEdit2 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycolourcode2"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryEdit3 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycode3"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryColourEdit3 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycolourcode3"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryEdit4 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycode4"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AccessoryColourEdit4 = {
            db_field = {
                table_name = "players",
                field_name = "accessorycolourcode4"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        runningcodeEdit1 = {
            db_field = {
                table_name = "players",
                field_name = "runningcode1"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        runningcodeEdit2 = {
            db_field = {
                table_name = "players",
                field_name = "runningcode2"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FinishingCodeEdit1 = {
            db_field = {
                table_name = "players",
                field_name = "finishingcode1"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FinishingCodeEdit2 = {
            db_field = {
                table_name = "players",
                field_name = "finishingcode2"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AnimFreeKickStartPosEdit = {
            db_field = {
                table_name = "players",
                field_name = "animfreekickstartposcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AnimPenaltiesStartPosEdit = {
            db_field = {
                table_name = "players",
                field_name = "animpenaltiesstartposcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AnimPenaltiesKickStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "animpenaltieskickstylecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AnimPenaltiesMotionStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "animpenaltiesmotionstylecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AnimPenaltiesApproachEdit = {
            db_field = {
                table_name = "players",
                field_name = "animpenaltiesapproachcode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FacePoserPresetEdit = {
            db_field = {
                table_name = "players",
                field_name = "faceposerpreset"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        EmotionEdit = {
            db_field = {
                table_name = "players",
                field_name = "emotion"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SkillMoveslikelihoodEdit = {
            db_field = {
                table_name = "players",
                field_name = "skillmoveslikelihood"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ModifierEdit = {
            db_field = {
                table_name = "players",
                field_name = "modifier"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        IsCustomizedEdit = {
            db_field = {
                table_name = "players",
                field_name = "iscustomized"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        UserCanEditNameEdit = {
            db_field = {
                table_name = "players",
                field_name = "usercaneditname"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        RunStyleEdit = {
            db_field = {
                table_name = "players",
                field_name = "runstylecode"
            },
            valGetter = fnCommonDBValGetter,
            OnSaveChanges = fnSaveCommon,
            events = {
                OnChange = fnCommonOnChange
            }
        }
    }

    return components_description
end

function thisFormManager:TabClick(sender)
    if self.frm[self.tab_panel_map[sender.Name]].Visible then return end

    for key,value in pairs(self.tab_panel_map) do
        if key == sender.Name then
            sender.Color = '0x001D1618'
            self.frm[value].Visible = true
        else
            self.frm[key].Color = '0x003F2F34'
            self.frm[value].Visible = false
        end
    end

end

function thisFormManager:TabMouseEnter(sender)
    if self.frm[self.tab_panel_map[sender.Name]].Visible then return end

    sender.Color = '0x00271D20'
end

function thisFormManager:TabMouseLeave(sender)
    if self.frm[self.tab_panel_map[sender.Name]].Visible then return end

    sender.Color = '0x003F2F34'
end

function thisFormManager:onShow(sender)
    self.logger:debug(string.format("onShow: %s", self.name))

    -- Show Loading panel
    self.frm.FindPlayerByID.Visible = false
    self.frm.SearchPlayerByID.Visible = false
    self.frm.WhileLoadingPanel.Visible = true

    -- Not READY!
    self.frm.PlayerInfoGroup8.Visible = false
    self.frm.PlayerInfoGroup9.Visible = false
    self.frm.PlayerInfoGroup6.Visible = false
    self.frm.SquadRoleLabel.Visible = false
    self.frm.SquadRoleCB.Visible = false
    self.frm.WageLabel.Visible = false
    self.frm.WageEdit.Visible = false
    self.frm.PlayerCloneTab.Visible = false


    local onShow_delayed_wrapper = function()
        self:onShow_delayed()
    end

    self.fill_timer = createTimer(nil)

    -- Load Data
    timer_onTimer(self.fill_timer, onShow_delayed_wrapper)
    timer_setInterval(self.fill_timer, 1000)
    timer_setEnabled(self.fill_timer, true)
end

function thisFormManager:onShow_delayed()
    -- Disable Timer
    timer_setEnabled(self.fill_timer, false)
    self.fill_timer = nil

    self.current_addrs = {}
    self.current_addrs["players"] = readPointer("pPlayersTableCurrentRecord")
    self.current_addrs["teamplayerlinks"] = readPointer("pTeamplayerlinksTableCurrentRecord")
    self.current_addrs["career_calendar"] = readPointer("pCareerCalendarTableCurrentRecord")

    self:fill_form(self.current_addrs)
    self:recalculate_ovr(true)
    -- Hide Loading Panel and show components
    self.frm.PlayerInfoTab.Color = "0x001D1618"
    self.frm.PlayerInfoPanel.Visible = true
    self.frm.WhileLoadingPanel.Visible = false
    self.frm.FindPlayerByID.Visible = true
    self.frm.SearchPlayerByID.Visible = true
end

function thisFormManager:attributes_trackbar_val(args)
    local component_name = args['component_name']
    local comp_desc = self.form_components_description[component_name]

    local sum_attr = 0
    local items = 0
    if comp_desc['depends_on'] then
        for i=1, #comp_desc['depends_on'] do
            items = items + 1
            if self.frm[comp_desc['depends_on'][i]].Text == '' then
                local r = self.form_components_description[comp_desc['depends_on'][i]]
                self.frm[comp_desc['depends_on'][i]].Text = r["valGetter"](
                    self.current_addrs,
                    r["db_field"]["table_name"],
                    r["db_field"]["field_name"],
                    r["db_field"]["raw_val"]
                )
            end
            sum_attr = sum_attr + tonumber(self.frm[comp_desc['depends_on'][i]].Text)
        end
    end

    local result = math.ceil(sum_attr/items)
    if result > ATTRIBUTE_BOUNDS['max'] then
        result = ATTRIBUTE_BOUNDS['max']
    elseif result < ATTRIBUTE_BOUNDS['min'] then
        result = ATTRIBUTE_BOUNDS['min']
    end

    return result
end

function thisFormManager:update_trackbar(sender)
    self.logger:debug(string.format("update_trackbar: %s", sender.Name))
    local trackBarName = string.format("%sTrackBar", self.form_components_description[sender.Name]['group'])
    local valueLabelName = string.format("%sValueLabel", self.form_components_description[sender.Name]['group'])

    -- recalculate ovr of group of attrs
    local onchange_func = self.frm[trackBarName].OnChange
    self.frm[trackBarName].OnChange = nil

    local calc = self:attributes_trackbar_val({
        component_name = trackBarName,
    })

    self.frm[trackBarName].Position = calc
    self.frm[trackBarName].SelEnd = calc
    self.frm[valueLabelName].Caption = calc

    self.frm[trackBarName].OnChange = onchange_func

end

function thisFormManager:fill_form(addrs, playerid)
    local record_addr = addrs["players"]

    if record_addr == nil and playerid == nil then
        self.logger:error(
            string.format("Can't Fill %s form. Player record address or playerid is required", self.name)
        )
    end

    self.logger:debug(string.format("fill_form: %s", self.name))
    if self.form_components_description == nil then
        self.form_components_description = self:get_components_description()
    end


    for i=0, self.frm.ComponentCount-1 do
        local component = self.frm.Component[i]
        if component == nil then
            goto continue
        end

        local component_name = component.Name
        -- self.logger:debug(component.Name)
        local comp_desc = self.form_components_description[component_name]
        if comp_desc == nil then
            goto continue
        end

        local component_class = component.ClassName

        component.OnChange = nil
        if component_class == 'TCEEdit' then
            if comp_desc["valGetter"] then
                component.Text = comp_desc["valGetter"](
                    addrs,
                    comp_desc["db_field"]["table_name"],
                    comp_desc["db_field"]["field_name"],
                    comp_desc["db_field"]["raw_val"]
                )
            else
                component.Text = "TODO SET VALUE!"
            end
        elseif component_class == 'TCETrackBar' then
            --
        elseif component_class == 'TCEComboBox' then
            if comp_desc["valGetter"] and comp_desc["cbFiller"] then
                local current_field_val = comp_desc["valGetter"](
                    addrs,
                    comp_desc["db_field"]["table_name"],
                    comp_desc["db_field"]["field_name"],
                    comp_desc["db_field"]["raw_val"]
                )
                comp_desc["cbFiller"](
                    component,
                    current_field_val,
                    comp_desc["cb_id"]
                )
            else
                component.ItemIndex = 0
            end
        elseif component_class == 'TCECheckBox' then
            component.State = comp_desc["valGetter"](addrs, comp_desc)
        end
        if comp_desc['events'] then
            for key, value in pairs(comp_desc['events']) do
                component[key] = value
            end
        end

        ::continue::
    end

    self.logger:debug("Update trackbars")
    local trackbars = {
        'AttackTrackBar',
        'DefendingTrackBar',
        'SkillTrackBar',
        'GoalkeeperTrackBar',
        'PowerTrackBar',
        'MovementTrackBar',
        'MentalityTrackBar',
    }
    for i=1, #trackbars do
        self:update_trackbar(self.frm[trackbars[i]])
    end

    self.has_unsaved_changes = false
end

function thisFormManager:onApplyChangesBtnClick()
    self.logger:info("Apply Changes")

    self.logger:debug("Iterate change_list")
    for key, value in pairs(self.change_list) do
        
        local comp_desc = self.form_components_description[key]
        local component = self.frm[key]
        local component_class = component.ClassName

        self.logger:debug(string.format(
            "Edited comp: %s (%s), val: %s",
            key, component_class, value
        ))
        if component_class == 'TCEEdit' then
            if comp_desc["OnSaveChanges"] then
                comp_desc["OnSaveChanges"](
                    self.current_addrs, key, comp_desc
                )
            end
        elseif component_class == 'TCECheckBox' then
            if comp_desc["OnSaveChanges"] then
                comp_desc["OnSaveChanges"](
                    self.current_addrs, key, comp_desc
                )
            end
        elseif component_class == 'TCEComboBox' then
            if comp_desc["OnSaveChanges"] then
                comp_desc["OnSaveChanges"](
                    self.current_addrs, key, comp_desc
                )
            end
        end
    end

    self.has_unsaved_changes = false
    self.change_list = {}
    local msg = string.format("Player with ID %s has been edited", self.frm.PlayerIDEdit.Text)
    showMessage(msg)
    self.logger:info(msg)
end

function thisFormManager:check_if_has_unsaved_changes()
    if self.has_unsaved_changes then
        if messageDialog("You have some unsaved changes in player editor\nDo you want to apply them?", mtInformation, mbYes,mbNo) == mrYes then
            self:onApplyChangesBtnClick()
        else
            self.has_unsaved_changes = false
            self.change_list = {}
        end
    end
end

function thisFormManager:assign_current_form_events()
    self:assign_events()

    local fnTabClick = function(sender)
        self:TabClick(sender)
    end

    local fnTabMouseEnter= function(sender)
        self:TabMouseEnter(sender)
    end

    local fnTabMouseLeave = function(sender)
        self:TabMouseLeave(sender)
    end

    self.frm.OnShow = function(sender)
        self:onShow(sender)
    end

    self.frm.FindPlayerByID.OnClick = function(sender)
        sender.Text = ''
    end
    self.frm.SearchPlayerByID.OnClick = function(sender)
        local playerid = tonumber(self.frm.FindPlayerByID.Text)
        if playerid == nil then return end

        self:check_if_has_unsaved_changes()

        local player_found = self:find_player_by_id(playerid)
        if player_found then
            self:find_player_club_team_record(playerid)
            self.frm.FindPlayerByID.Text = playerid
            self:recalculate_ovr()
            self:onShow()
        else 
            self.logger:error(string.format("Not found any player with ID: %d.", playerid))
        end
    end
    self.frm.PlayerEditorSettings.OnClick = function(sender)
        SettingsForm.show()
    end

    self.frm.SyncImage.OnClick = function(sender)
        if not self.current_addrs["players"] then return end
        self:check_if_has_unsaved_changes()

        --local addr = readPointer("pPlayersTableCurrentRecord")
        --if self.current_addrs["players"] == addr then return end

        self:onShow()
    end

    self.frm.RandomAttackAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "CrossingEdit", "FinishingEdit", "HeadingAccuracyEdit",
            "ShortPassingEdit", "VolleysEdit"
        })
    end
    self.frm.RandomDefendingAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "MarkingEdit", "StandingTackleEdit", "SlidingTackleEdit",
        })
    end
    self.frm.RandomSkillAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "DribblingEdit", "CurveEdit", "FreeKickAccuracyEdit",
            "LongPassingEdit", "BallControlEdit",
        })
    end
    self.frm.RandomGKAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "GKDivingEdit", "GKHandlingEdit", "GKKickingEdit",
            "GKPositioningEdit", "GKReflexEdit",
        })
    end
    self.frm.RandomPowerAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "ShotPowerEdit", "JumpingEdit", "StaminaEdit",
            "StrengthEdit", "LongShotsEdit",
        })
    end
    self.frm.RandomMovementAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "AccelerationEdit", "SprintSpeedEdit", "AgilityEdit",
            "ReactionsEdit", "BalanceEdit",
        })
    end
    self.frm.RandomMentalityAttr.OnClick = function(sender)
        self:roll_random_attributes({
            "AggressionEdit", "ComposureEdit", "InterceptionsEdit",
            "AttackPositioningEdit", "VisionEdit", "PenaltiesEdit",
        })
    end
    
    self.frm.PlayerInfoTab.OnClick = fnTabClick
    self.frm.PlayerInfoTab.OnMouseEnter = fnTabMouseEnter
    self.frm.PlayerInfoTab.OnMouseLeave = fnTabMouseLeave

    self.frm.AttributesTab.OnClick = fnTabClick
    self.frm.AttributesTab.OnMouseEnter = fnTabMouseEnter
    self.frm.AttributesTab.OnMouseLeave = fnTabMouseLeave

    self.frm.TraitsTab.OnClick = fnTabClick
    self.frm.TraitsTab.OnMouseEnter = fnTabMouseEnter
    self.frm.TraitsTab.OnMouseLeave = fnTabMouseLeave

    self.frm.AppearanceTab.OnClick = fnTabClick
    self.frm.AppearanceTab.OnMouseEnter = fnTabMouseEnter
    self.frm.AppearanceTab.OnMouseLeave = fnTabMouseLeave

    self.frm.AccessoriesTab.OnClick = fnTabClick
    self.frm.AccessoriesTab.OnMouseEnter = fnTabMouseEnter
    self.frm.AccessoriesTab.OnMouseLeave = fnTabMouseLeave

    self.frm.OtherTab.OnClick = fnTabClick
    self.frm.OtherTab.OnMouseEnter = fnTabMouseEnter
    self.frm.OtherTab.OnMouseLeave = fnTabMouseLeave

    self.frm.PlayerCloneTab.OnClick = fnTabClick
    self.frm.PlayerCloneTab.OnMouseEnter = fnTabMouseEnter
    self.frm.PlayerCloneTab.OnMouseLeave = fnTabMouseLeave

    self.frm.ApplyChangesBtn.OnClick = function(sender)
        self:onApplyChangesBtnClick()
    end

    self.frm.ApplyChangesBtn.OnMouseEnter = function(sender)
        self:onBtnMouseEnter(sender)
    end

    self.frm.ApplyChangesBtn.OnMouseLeave = function(sender)
        self:onBtnMouseLeave(sender)
    end

    self.frm.ApplyChangesBtn.OnPaint = function(sender)
        self:onPaintButton(sender)
    end

end

function thisFormManager:setup(params)
    self.cfg = params.cfg
    self.logger = params.logger
    self.frm = params.frm_obj
    self.name = params.name

    self.logger:info(string.format("Setup Form Manager: %s", self.name))

    self.tab_panel_map = {
        PlayerInfoTab = "PlayerInfoPanel",
        AttributesTab = "AttributesPanel",
        TraitsTab = "TraitsPanel",
        AppearanceTab = "AppearancePanel",
        AccessoriesTab = "AccessoriesPanel",
        OtherTab = "OtherPanel",
        PlayerCloneTab = "PlayerClonePanel"
    }
    PlayersEditorForm.FindPlayerByID.Text = 'Find player by ID...'
    self.change_list = {}

    self:assign_current_form_events()
end


return thisFormManager;