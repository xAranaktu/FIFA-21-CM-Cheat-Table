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

    self.addr_list = nil
    self.fnSaveCfg = nil
    self.new_cfg = {}
    self.has_unsaved_changes = false
    self.selection_idx = 0

    self.fill_timer = nil
    self.form_components_description = nil
    self.current_addrs = {}
    self.tab_panel_map = {}

    return o;
end

function thisFormManager:get_components_description()
    local fnCommonOnChange = function(sender)
        self.has_unsaved_changes = true
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
                -- restore onchange event
                self.frm[comp_desc['depends_on'][i]].OnChange = onchange_event
            end
        end
    end

    local fnTraitCheckbox = function(addrs, comp_desc)
        local field_name = comp_desc["db_field"]["field_name"]
        local table_name = comp_desc["db_field"]["table_name"]

        local addr = addrs[table_name]

        local traitbitfield = self.game_db_manager:get_table_record_field_value(addr, table_name, field_name)
        
        local is_set = bAnd(bShr(traitbitfield, comp_desc["trait_bit"]), 1)

        return is_set
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

        bdate = os.time{
            year=bdate["year"],
            month=bdate["month"],
            day=bdate["day"]
        }

        current_date = os.time{
            year=current_date["year"],
            month=current_date["month"],
            day=current_date["day"]
        }

        return math.floor(os.difftime(current_date, bdate) / (24*60*60*365.25))
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
            }
        },
        OverallEdit = {
            db_field = {
                table_name = "players",
                field_name = "overallrating"
            },
            valGetter = fnCommonDBValGetter,
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
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AttackingWorkRateCB = {
            db_field = {
                table_name = "players",
                field_name = "attackingworkrate",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["WR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        DefensiveWorkRateCB = {
            db_field = {
                table_name = "players",
                field_name = "defensiveworkrate",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["WR_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SkillMovesCB = {
            db_field = {
                table_name = "players",
                field_name = "skillmoves",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["FIVE_STARS_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        WeakFootCB = {
            db_field = {
                table_name = "players",
                field_name = "weakfootabilitytypecode",
                raw_val = true
            },
            cb_id = CT_MEMORY_RECORDS["FIVE_STARS_CB"],
            cbFiller = fnFillCommonCB,
            valGetter = fnCommonDBValGetter,
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
            },
        },
        -- Attributes
        CrossingEdit = {
            db_field = {
                table_name = "players",
                field_name = "crossing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FinishingEdit = {
            db_field = {
                table_name = "players",
                field_name = "finishing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        HeadingAccuracyEdit = {
            db_field = {
                table_name = "players",
                field_name = "headingaccuracy"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ShortPassingEdit = {
            db_field = {
                table_name = "players",
                field_name = "shortpassing"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        VolleysEdit = {
            db_field = {
                table_name = "players",
                field_name = "volleys"
            },
            group = 'Attack',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        MarkingEdit = {
            db_field = {
                table_name = "players",
                field_name = "marking"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        StandingTackleEdit = {
            db_field = {
                table_name = "players",
                field_name = "standingtackle"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SlidingTackleEdit = {
            db_field = {
                table_name = "players",
                field_name = "slidingtackle"
            },
            group = 'Defending',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        DribblingEdit = {
            db_field = {
                table_name = "players",
                field_name = "dribbling"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        CurveEdit = {
            db_field = {
                table_name = "players",
                field_name = "curve"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FreeKickAccuracyEdit = {
            db_field = {
                table_name = "players",
                field_name = "freekickaccuracy"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LongPassingEdit = {
            db_field = {
                table_name = "players",
                field_name = "longpassing"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        BallControlEdit = {
            db_field = {
                table_name = "players",
                field_name = "ballcontrol"
            },
            group = 'Skill',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        GKDivingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkdiving"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKHandlingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkhandling"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKKickingEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkkicking"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKPositioningEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkpositioning"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKReflexEdit = {
            db_field = {
                table_name = "players",
                field_name = "gkreflexes"
            },
            group = 'Goalkeeper',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        ShotPowerEdit = {
            db_field = {
                table_name = "players",
                field_name = "shotpower"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        JumpingEdit = {
            db_field = {
                table_name = "players",
                field_name = "jumping"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        StaminaEdit = {
            db_field = {
                table_name = "players",
                field_name = "stamina"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        StrengthEdit = {
            db_field = {
                table_name = "players",
                field_name = "strength"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LongShotsEdit = {
            db_field = {
                table_name = "players",
                field_name = "longshots"
            },
            group = 'Power',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        AccelerationEdit = {
            db_field = {
                table_name = "players",
                field_name = "acceleration"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SprintSpeedEdit = {
            db_field = {
                table_name = "players",
                field_name = "sprintspeed"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AgilityEdit = {
            db_field = {
                table_name = "players",
                field_name = "agility"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ReactionsEdit = {
            db_field = {
                table_name = "players",
                field_name = "reactions"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        BalanceEdit = {
            db_field = {
                table_name = "players",
                field_name = "balance"
            },
            group = 'Movement',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        AggressionEdit = {
            db_field = {
                table_name = "players",
                field_name = "aggression"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ComposureEdit = {
            db_field = {
                table_name = "players",
                field_name = "composure"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        InterceptionsEdit = {
            db_field = {
                table_name = "players",
                field_name = "interceptions"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        AttackPositioningEdit = {
            db_field = {
                table_name = "players",
                field_name = "positioning"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        VisionEdit = {
            db_field = {
                table_name = "players",
                field_name = "vision"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PenaltiesEdit = {
            db_field = {
                table_name = "players",
                field_name = "penalties"
            },
            group = 'Mentality',
            valGetter = fnCommonDBValGetter,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        LongThrowInCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 0,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PowerFreeKickCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 1,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        InjuryProneCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 2,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SolidPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 3,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LeadershipCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 6,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        EarlyCrosserCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 7,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FinesseShotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 8,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FlairCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 9,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SpeedDribblerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 12,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKLongthrowCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 14,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PowerheaderCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 15,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GiantthrowinCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 16,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        OutsitefootshotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 17,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SwervePassCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 18,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SecondWindCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 19,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        FlairPassesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 20,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        BicycleKicksCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 21,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        GKFlatKickCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 22,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        OneClubPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 23,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TeamPlayerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 24,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        RushesOutOfGoalCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 27,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        CautiousWithCrossesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 28,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ComesForCrossessCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 29,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        SaveswithFeetCB = {
            db_field = {
                table_name = "players",
                field_name = "trait2"
            },
            trait_bit = 1,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        SetPlaySpecialistCB = {
            db_field = {
                table_name = "players",
                field_name = "trait2"
            },
            trait_bit = 2,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        DivesIntoTacklesCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 4,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LongPasserCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 10,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        LongShotTakerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 11,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        PlaymakerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 13,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        ChipShotCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 25,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },
        TechnicalDribblerCB = {
            db_field = {
                table_name = "players",
                field_name = "trait1"
            },
            trait_bit = 26,
            valGetter = fnTraitCheckbox,
            events = {
                OnChange = fnCommonOnChange
            }
        },

        -- Appearance
        HeightEdit = {
            db_field = {
                table_name = "players",
                field_name = "height"
            },
            valGetter = fnCommonDBValGetter,
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
            events = {
                OnChange = fnCommonOnChange
            }
        },
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

    -- Hide Loading Panel and show components
    self.frm.PlayerInfoTab.Color = "0x001D1618"
    self.frm.PlayerInfoPanel.Visible = true
    self.frm.WhileLoadingPanel.Visible = false
    self.frm.FindPlayerByID.Visible = true
    self.frm.SearchPlayerByID.Visible = true
end

function thisFormManager:update_trackbar(sender)
    local trackBarName = string.format("%sTrackBar", self.form_components_description[sender.Name]['group'])
    local valueLabelName = string.format("%sValueLabel", self.form_components_description[sender.Name]['group'])
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

        if component_class == 'TCEEdit' then
            component.OnChange = nil
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

            if comp_desc['events'] then
                for key, value in pairs(comp_desc['events']) do
                    component[key] = value
                end
            end
        elseif component_class == 'TCETrackBar' then
            if comp_desc['events'] then
                for key, value in pairs(comp_desc['events']) do
                    component[key] = value
                end
            end
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

        ::continue::
    end

    self.logger:info("Update trackbars")
    local trackbars = {
        'AttackTrackBar',
        -- 'DefendingTrackBar',
        -- 'SkillTrackBar',
        -- 'GoalkeeperTrackBar',
        -- 'PowerTrackBar',
        -- 'MovementTrackBar',
        -- 'MentalityTrackBar',
    }
    for i=1, #trackbars do
        self:update_trackbar(self.frm[trackbars[i]])
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

    end
    self.frm.SearchPlayerByID.OnClick = function(sender)
    end
    self.frm.PlayerEditorSettings.OnClick = function(sender)
        SettingsForm.show()
    end

    self.frm.SyncImage.OnClick = function(sender)
        if not self.current_addrs["players"] then return end

        local addr = readPointer("pPlayersTableCurrentRecord")
        if self.current_addrs["players"] == addr then return end

        self:onShow()
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

    self:assign_current_form_events()
end


return thisFormManager;