DEFAULT_PROC_NAME = "FIFA21.exe"

URL_LINKS = {
    PATREON = "https://www.patreon.com/xAranaktu",
    DISCORD = "https://discord.gg/va9EtdB",
    VERSION = "https://raw.githubusercontent.com/xAranaktu/FIFA-21-CM-Cheat-Table/master/VERSION"
}

CT_MEMORY_RECORDS = {
    GUI_SCRIPT = 15
}

AOB_PATTERNS = {
    DisablePGM = "85 C0 0F 95 85 60 05 00 00",

    ScreenID = '48 8D 35 ?? ?? ?? ?? 48 0F 45 35 ?? ?? ?? ?? 49 8B FF',
    DatabaseRead = '48 ?? ?? 4C 03 46 30 E8',
    DatabaseBasePtr = "4C 0F 44 35 ?? ?? ?? ?? 41 8B 4E 08",

    AgreeTransferRequest = "44 8B E8 48 8B 89 98 01 00 00",
    AltTab = "48 83 ec 48 48 83 3d ?? ?? ?? ?? ?? 74"
}

DEFAULT_CFG = {
    flags = {
        debug_mode = false,
        deactive_on_close = false,
        hide_ce_scanner = false,
        check_for_update = true,
        only_check_for_free_update = false,
        cache_players_data = false,
        hide_players_potential = false
    },
    directories = {
    },
    game =
    {
        name = DEFAULT_PROC_NAME,
        name_trial = "FIFA21_TRIAL.exe"
    },
    gui = {
        opacity = 255
    },
    auto_activate = {
        18,      -- Scripts
        214      -- FIFA Database Tables
    },
    hotkeys = {
        sync_with_game = 'VK_F5',
        search_player_by_id = 'VK_RETURN'
    },
    theme = {
        default = 'dark',
        current = 'dark'
    },
    language = {
        default = 'en_US',
        current = 'en_US'
    },
    other = {
        ignore_update = "21.1.0.0"
    }
}

DB_TABLE_STRUCT_OFFSETS = {
    first_record = 0x30,                -- 8 bytes
    shortname = 0x40,                   -- 4 bytes
    record_size = 0x44,                 -- 4 bytes
    bit_records_count = 0x48,           -- 4 bytes
    compressed_str_len = 0x50,          -- 4 bytes
    total_records = 0x78,               -- 2 bytes
    total_records2 = 0x7A,              -- 2 bytes
    written_records = 0x7C,             -- 2 bytes
    canceled_records = 0x7E,            -- 2 bytes
    fieldcount = 0x82                   -- 1 bytes
}


DB_TABLES_META = {
    players = {

    }
}

-- All available forms
FORMS = {
    MainWindowForm, SettingsForm, PlayersEditorForm
}