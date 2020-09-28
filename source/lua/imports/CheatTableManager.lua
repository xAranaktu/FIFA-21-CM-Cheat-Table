require 'lua/consts';
require 'lua/helpers';

local LIP = require 'lua/requirements/LIP';

local Logger = require 'lua/imports/logger';
local MemoryManager = require 'lua/imports/MemoryManager';

local mainFormManager = require 'lua/GUI/forms/mainform/manager';
local settingsFormManager = require 'lua/GUI/forms/settingsform/manager';

local TableManager = {}

function TableManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.logger = Logger:new()

    local save_offsets_callback = function(offsets)
       self:save_offsets(offsets)
    end
    
    self.memory_manager = MemoryManager:new(nil, self.logger, save_offsets_callback)

    self.FIFA_year = 21
    self.game_name = "FIFA 21"

    self.addr_list = getAddressList()

    self.proc_name = ""

    self.dirs = {}
    self.fifa_player_names = {}
    self.cached_players = {}
    self.form_managers = {}
    self.cfg = {}
    self.offsets = {}
    self.ptrs = {}

    self.no_internet = false
    self.show_ce = true

    --timers
    self.auto_attach_timer = nil

    return o;
end

function TableManager:get_frm_mgr(key)
    return self.form_managers[key]
end

function TableManager:get_frm(key)
    return self:get_frm_mgr(key).frm
end

function TableManager:execute_cmd(cmd)
    self.logger:info(string.format('execute cmd -  %s', cmd))
    local p = assert(io.popen(cmd))
    local result = p:read("*all")
    p:close()
    if result then
        self.logger:info(string.format('execute cmd result -  %s', result))
    end
end

function TableManager:delete_directory(dir)
    self:execute_cmd(string.format('rmdir /s /q "%s"', dir))
end

function TableManager:create_dirs()
    local d_dir = string.gsub(self.dirs["DATA"], "/","\\")
    local fifa_sett_dir = string.gsub(self.dirs["CACHE"], "/","\\")
    local cmds = {
        "mkdir " .. '"' .. d_dir .. '"',
        "ECHO A | xcopy cache " .. '"' .. fifa_sett_dir .. '" /E /i',
    }
    for i=1, #cmds do
        self:execute_cmd(cmds[i])
    end

end

function TableManager:get_ct_ver()
    local ver = string.gsub(self.addr_list.getMemoryRecordByID(0).Description, 'v', '')
    return ver
end

function TableManager:check_for_ct_update()
    local new_version_is_available = false
    local r = getInternet()
    local version = r.getURL(URL_LINKS.VERSION)
    r.destroy()

    if version == nil then
        self.no_internet = true
        self.logger:warning("CT Update check failed. No internet?")
        return false
    end

    local patrons_version = version:sub(1,8)
    if (not patrons_version) then return false end

    local free_version = version:sub(9,17)
    if (not free_version) then return false end

    self.logger:info(string.format(
        "Patrons ver -  %s, free ver - %s", patrons_version, free_version
    ))

    local ipatronsver, _ = string.gsub(
        patrons_version, '%.', ''
    )
    ipatronsver = tonumber(ipatronsver)
    if (not ipatronsver) then return false end

    local ifreever, _ = string.gsub(
        free_version, '%.', ''
    )
    ifreever = tonumber(ifreever)
    if (not ifreever) then return false end

    local current_ver = self:get_ct_ver()
    local icurver, _ = string.gsub(
        current_ver, '%.', ''
    )
    icurver = tonumber(icurver)
    if (not icurver) then return false end

    if self.cfg.flags.only_check_for_free_update then
        if self.cfg.other.ignore_update == free_version then
            return false
        end
        if ifreever > icurver then
            LATEST_VER = free_version
            self:get_frm("main_form").LabelLatestLEVer.Caption = string.format(
                "(Latest: %s)", LATEST_VER
            )
            self:get_frm("main_form").LabelLatestLEVer.Visible = true
            return true
        end
    else
        if (ifreever > icurver) or (ipatronsver > icurver) then
            if self.cfg.other.ignore_update == patrons_version then
                return false
            end
            LATEST_VER = patrons_version
            self:get_frm("main_form").LabelLatestLEVer.Caption = string.format(
                "(Latest: %s)", LATEST_VER
            )
            self:get_frm("main_form").LabelLatestLEVer.Visible = true
            return true
        end
    end

end

function TableManager:version_check()
    local ce_version = getCEVersion()
    self.logger:info(string.format('Cheat engine version: %f', ce_version))

    if (ce_version ~= 6.81) then
        self.logger:warning(
            string.format('Recommended Cheat Engine version for this cheat table is 6.81\nCheat Engine %f may not work as expected', ce_version),
            true
        )
    end
    self:get_frm("main_form").LabelCEVer.Caption = ce_version

    local ct_ver = self:get_ct_ver()
    self.logger:info(string.format('Cheat Table version: %s', ct_ver))
    self:get_frm("main_form").LabelLEVer.Caption = ct_ver
end

function TableManager:get_forms_map()
    return {
        main_form = {
            mgr = mainFormManager,
            frm = MainWindowForm
        },
        settings_form = {
            mgr = settingsFormManager,
            frm = SettingsForm
        },
    }
end

function TableManager:setup_forms()
    local forms_map = self:get_forms_map()

    settingsFormManager.dirs = deepcopy(self.dirs)
    settingsFormManager.fnSaveCfg = function(cfg)
        self:save_cfg(cfg)
    end


    for k, v in pairs(forms_map) do
        self.form_managers[k] = v.mgr
        v.mgr:setup({
            name=k,
            frm_obj=v.frm,
            logger=self.logger
        })
    end



end

function TableManager:style_forms()
    local forms_map = self:get_forms_map()

    for k, v in pairs(forms_map) do
        self:get_frm_mgr(k):style_form()
    end
end

function TableManager:initialize()
    self.logger:info("================================")
    self.logger:info("=========== INITIALIZE =========")
    self.logger:info("================================")
    if (not cheatEngineIs64Bit()) then
        local critical_error = "Run 64-bit version of cheat engine (cheatengine-x86_64.exe)"
        self.logger:critical(critical_error)
        assert(false, critical_error)
    end

    -- DEFAULT GLOBALS, better leave it as is
    local env_homedrive = os.getenv('HOMEDRIVE')
    local env_systemdrive = os.getenv('SystemDrive')
    local env_username = os.getenv('USERNAME')

    if env_homedrive then
        self.logger:info("os.getenv('HOMEDRIVE') " .. env_homedrive)
    else
        self.logger:info('No HOMEDRIVE env var')
    end
    if env_systemdrive then
        self.logger:info("os.getenv('SystemDrive') " .. env_systemdrive)
    else
        self.logger:info('No SystemDrive env var')
    end
    self.dirs["HOMEDRIVE"] = env_homedrive or env_systemdrive or 'C:'
    self.logger:info(string.format("HOMEDRIVE: %s", self.dirs["HOMEDRIVE"]))

    self.dirs["FIFA_SETTINGS"] = string.format(
        "%s/Users/%s/Documents/FIFA %s/",
        self.dirs["HOMEDRIVE"], env_username, self.FIFA_year
    );

    self.dirs["DATA"] = self.dirs["FIFA_SETTINGS"] .. 'Cheat Table/data/';
    self.dirs["CACHE"] = self.dirs["FIFA_SETTINGS"] .. 'Cheat Table/cache/';

    self.dirs["CONFIG_FILE"] = self.dirs["DATA"] .. 'config.ini';
    self.dirs["OFFSETS_FILE"] = self.dirs["DATA"] .. 'offsets.ini';

    self:setup_forms()

end

function TableManager:hide_mem_scanner()
    local main_form = getMainForm()

    -- local min_h = 378 -- default one

    main_form.Panel5.Constraints.MinHeight = 65
    main_form.Panel5.Height = 65


    -- Works for Cheat Engine 6.8.1
    local comps = {
        "Label6", "foundcountlabel", "sbOpenProcess", "lblcompareToSavedScan",
        "ScanText", "lblScanType", "lblValueType", "SpeedButton2", "btnNewScan",
        "gbScanOptions", "Panel2", "Panel3", "Panel6", "Panel7", "Panel8",
        "btnNextScan", "ScanType", "VarType", "ProgressBar", "UndoScan",
        "scanvalue", "btnFirst", "btnNext", "LogoPanel", "pnlScanValueOptions",
        "Panel9", "Panel10", "Foundlist3", "SpeedButton3", "UndoScan"
    }

    for i=1, #comps do
        if main_form[comps[i]] then
            main_form[comps[i]].Visible = false
        end
    end
end

function TableManager:deactive_all(record)
    for i=0, record.Count-1 do
        if record[i].Active then record[i].Active = false end
        if record.Child[i].Count > 0 then
            deactive_all(record.Child[i])
        end
    end
end

function TableManager:can_autoactivate(script_id)
    local not_allowed_to_aa = {
        2998  -- "Generate new report" script, it's internal call and will cause crash when activated in Main Menu
    }

    for i=1, #not_allowed_to_aa do
        if not_allowed_to_aa[i] == script_id then
            return false
        end
    end
    return true
end

function TableManager:init_ptrs()
    self.logger:info("TODO init_ptrs")
end

function TableManager:autoactivate_scripts()
    local always_activate = {
        0
    }

    for i=1, #always_activate do
        local script_id = always_activate[i]
        local script_record = self.addr_list.getMemoryRecordByID(script_id)
        self.logger:info(string.format('Activating %s (%d)', script_record.Description, script_id))
        script_record.Active = true
    end

    for i=1, #self.cfg.auto_activate do
        local script_id = self.cfg.auto_activate[i]
        if self:can_autoactivate(script_id) then
            local script_record = self.addr_list.getMemoryRecordByID(script_id)
            if script_record then
                self.logger:info(string.format('Activating %s (%d)', script_record.Description, script_id))
                if not script_record.Active then
                    script_record.Active = true
                end
            end
        end
    end
end

function TableManager:file_exists(name)
    local f, err = io.open(name,"r")
    if f then
        io.close(f)
        sleep(250)
        return true
    else
        self.logger:warning(
            string.format("file_exists (%s) error %s", name, err or "")
        )
        return false
    end
end

function TableManager:save_cfg(cfg)
    if cfg == nil then 
        cfg = self.cfg 
    end

    if cfg == nil then return end

    self.logger:info(string.format(
        "Saving Config to %s", self.dirs["CONFIG_FILE"]
    ))
    LIP.save(self.dirs["CONFIG_FILE"], cfg);

end

function TableManager:save_offsets(offsets)
    if not offsets.offsets then
        offsets = {
            offsets = offsets
        }
    end

    self.logger:info(string.format(
        "Saving Offsets to %s", self.dirs["OFFSETS_FILE"]
    ))

    LIP.save(self.dirs["OFFSETS_FILE"], offsets);
end

function TableManager:load_offsets()
    if self:file_exists(self.dirs["OFFSETS_FILE"]) then
        self.logger:info(string.format(
            'Loading OFFSETS_DATA from %s', self.dirs["OFFSETS_FILE"]
        ))
        local offsets = LIP.load(self.dirs["OFFSETS_FILE"])
        return offsets;
    else
        self.logger:info(string.format(
            'Offsets file not found at %s - loading default data', self.dirs["OFFSETS_FILE"]
        ))
        local data =
        {
            offsets =
            {
                AltTab = nil,
            },
        };
        LIP.save(self.dirs["OFFSETS_FILE"], data);
        return data
    end
end

function TableManager:load_config()
    if self:file_exists("config.ini") then
        -- Use files from cwd
        self.dirs["CACHE"] = "cache/"
        self.dirs["OFFSETS_FILE"] = "offsets.ini"
        self.dirs["CONFIG_FILE"] = "config.ini"
    elseif not self:file_exists(self.dirs["CONFIG_FILE"]) then
        local data = DEFAULT_CFG
        data.directories.cache_dir = self.dirs["CACHE"]
        self:create_dirs()
        local status, err = pcall(LIP.save, self.dirs["CONFIG_FILE"], data)
        self.logger:info(string.format(
            'cfg file not found at %s - loading default data', self.dirs["CONFIG_FILE"])
        )
        if not status then
            self.logger:error(
                string.format('LIP.SAVE FAILED for %s with err: %s', self.dirs["CONFIG_FILE"], err)
            )
            self.dirs["CACHE"] = "cache/"
            self.dirs["OFFSETS_FILE"] = "offsets.ini"
            self.dirs["CONFIG_FILE"] = "config.ini"
            data.directories.cache_dir = self.dirs["CACHE"]
            local status, err = pcall(LIP.save, self.dirs["CONFIG_FILE"], data)
        end
    end

    if self:file_exists(self.dirs["CONFIG_FILE"]) then
        self.logger:info(
            string.format('Loading CFG_DATA from %s', self.dirs["CONFIG_FILE"])
        )
        local cfg = LIP.load(self.dirs["CONFIG_FILE"]);

        return cfg
    else
        return DEFAULT_CFG
    end
end



function TableManager:get_screen_id()
    local ptr = self.ptrs["screen_id"]

    return readString(readPointer(ptr))
end

function TableManager:log_screen_id()
    local screen_id = self:get_screen_id()

    if not screen_id then
        self.logger:info("Current Screen: nil")
    else
        self.logger:info(string.format("Current Screen: %s", screen_id))
    end
end

function TableManager:on_attach_to_process()
    local main_frm_mgr = self:get_frm_mgr("main_form")
    main_frm_mgr:update_status("Attached to the game process.")

    if self.cfg.flags.check_for_update then
        self:check_for_ct_update()
    end

    self.ptrs["screen_id"] = self.memory_manager:get_validated_resolved_ptr("ScreenID", 4)
    self:log_screen_id()

    self.logger:info("Waiting for valid screen")
    while self:get_screen_id() == nil do
        showMessage('You are not in main menu in game. Enter there and close this window')
        sleep(1500)
    end
    self:log_screen_id()

    self:save_cfg()
    self:autoactivate_scripts()
    self:init_ptrs()

    self:style_forms()

    main_frm_mgr:remove_loading_panel()
    main_frm_mgr:load_images()

    getMainForm().Visible = true

    local success_msg = "Ready to use."
    self.logger:info(success_msg)
    main_frm_mgr:update_status(success_msg)
    showMessage(success_msg)
end

function TableManager:auto_attach_to_process()
    local proc_name = self.cfg.game.name
    local trial_name = self.cfg.game.name_trial

    if getProcessIDFromProcessName(proc_name) ~= nil then
        openProcess(proc_name)
    elseif getProcessIDFromProcessName(trial_name) ~= nil then
        openProcess(trial_name)
    else
        return
    end

    local attached_to = getOpenedProcessName()
    local pid = getOpenedProcessID()
    if pid > 0 and attached_to ~= nil then
        timer_setEnabled(self.auto_attach_timer, false)
        self.logger:info(string.format(
            "Attached to %s", attached_to
        ))
        self.proc_name = attached_to

        self.memory_manager:set_proc(self.proc_name)
        self.memory_manager:set_offsets(self.offsets)
        self:on_attach_to_process()
    end
end

function TableManager:start()
    if getOpenedProcessID() ~= 0 then
        local critical_error = "Restart required, getOpenedProcessID() ~= 0. Dont open process in Cheat Engine. Cheat Table will do it automatically if you allow for lua code execution."
        self.logger:critical(critical_error)
        assert(false, critical_error)
    end

    self.cfg = self:load_config()
    self.offsets = self:load_offsets()

    local forms_map = self:get_forms_map()

    for k, v in pairs(forms_map) do
        self:get_frm_mgr(k):set_cfg(self.cfg)
    end

    if self.cfg.flags.hide_ce_scanner then
        self:hide_mem_scanner()
    end

    self:get_frm_mgr("main_form"):update_status(string.format("Waiting for %s...", self.game_name))

    -- show GUI
    self.addr_list.getMemoryRecordByID(CT_MEMORY_RECORDS['GUI_SCRIPT']).Active = true

    self:version_check()

    local timer_callback = function()
        self:auto_attach_to_process()
    end

    self.logger:info("Searching for game process")

    self.auto_attach_timer = createTimer(nil)
    -- Without timer our GUI will not be displayed
    timer_onTimer(self.auto_attach_timer, timer_callback)
    timer_setInterval(self.auto_attach_timer, 2000)
    timer_setEnabled(self.auto_attach_timer, true)
end

return TableManager;