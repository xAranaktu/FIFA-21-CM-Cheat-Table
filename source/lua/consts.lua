URL_LINKS = {
    PATREON = "https://www.patreon.com/xAranaktu",
    DISCORD = "https://discord.gg/va9EtdB",
    VERSION = "https://raw.githubusercontent.com/xAranaktu/FIFA-21-CM-Cheat-Table/master/VERSION"
}

CT_MEMORY_RECORDS = {
    GUI_SCRIPT = 15
}

AOB_PATTERNS = {
    ScreenID = '4C 0F 45 3D ?? ?? ?? ?? 48 8B FE'
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
        name = "FIFA20.exe",
        name_trial = "FIFA20_TRIAL.exe"
    },
    gui = {
        opacity = 255
    },
    auto_activate = {
        0,      -- Scripts
        1      -- FIFA Database Tables
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