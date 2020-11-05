require 'lua/consts';
require 'lua/helpers';

local FormManager = {}

function FormManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    self.cfg = nil
    self.logger = nil
    self.game_db_manager = nil
    self.memory_manager = nil

    self.resize = nil
    self.frm = nil
    self.name = ""

    return o;
end

function FormManager:safe_load_picture_from_ss(comp, ss)
    if type(ss) == "userdata" then
        comp.LoadFromStream(ss)
        return true
    end

    return false
end

function FormManager:load_img(path, url)
    self.logger:info(string.format(
        "load_img: %s, %s", path, url
    ))
    local img = nil
    local cache_dir = self.dirs["CACHE"]
    
    local f=io.open(cache_dir .. path, "rb")
    local err = nil
    if f ~= nil then
        -- load from cache_dir
        img = f:read("*a")
        io.close(f)
    else
        -- load from internet and save in cache_dir
        local int=getInternet()
        img=int.getURL(url)
        int.destroy()
        -- If file is not a png file
        if img == nil or string.sub(img, 2, 4) ~= 'PNG' then
            return false
        end
        f, err=io.open(cache_dir .. path, "w+b")
        if f then
            f:write(img)
            io.close(f)
        else
            self.logger:info('Error opening img file: ' .. cache_dir .. path)
            if err then
                self.logger:info('Error - ' .. err)
            end
        end
    end
    return createStringStream(img)
end

function FormManager:load_crest(teamid, addr)
    local can_get_record = false

    if addr and self.game_db_manager then
        can_get_record = true
    end

    if not teamid and can_get_record then
        teamid = self.game_db_manager:get_table_record_field_value(addr, "teamplayerlinks", "teamid")
    end

    if not teamid then
        return self:load_img('crest/notfound.png', URL_LINKS["CDN"] .. '/img/assets/common/crest/notfound.png')
    end

    local fpath = string.format('crest/l%d.png', teamid)
    local url = string.format('%s/img/assets/%d/%s',
        URL_LINKS["CDN"],
        FIFA,
        string.format('crest/dark/l%d.png', teamid)
    )
    local img_ss = self:load_img(fpath, url)
    if not img_ss then return self:load_img('crest/notfound.png', URL_LINKS["CDN"] .. '/img/assets/common/crest/notfound.png') end
    
    return img_ss
end

function FormManager:load_headshot(playerid, addr, skintonecode, headtypecode, haircolorcode)
    local can_get_record = false

    if addr and self.game_db_manager then
        can_get_record = true
    end

    if not playerid and can_get_record then
        playerid = self.game_db_manager:get_table_record_field_value(addr, "players", "playerid")
    end

    if not playerid then
        return self:load_img('heads/notfound.png', URL_LINKS["CDN"] .. '/img/assets/common/heads/notfound.png')
    end

    local fpath = nil
    local iplayerid = tonumber(playerid)

    if iplayerid < 280000 then
        -- heads
        fpath = string.format('heads/p%d.png', playerid)
    else
        -- youthheads
        if skintonecode == nil then
            if can_get_record then
                skintonecode = self.game_db_manager:get_table_record_field_value(addr, "players", "skintonecode")
            else
                skintonecode = 0
            end
        end

        if headtypecode == nil then
            if can_get_record then
                headtypecode = self.game_db_manager:get_table_record_field_value(addr, "players", "headtypecode")
            else
                headtypecode = 0
            end
        end

        if haircolorcode == nil then
            if can_get_record then
                haircolorcode = self.game_db_manager:get_table_record_field_value(addr, "players", "haircolorcode")
            else
                haircolorcode = 0
            end
        end
        
        fpath = string.format('youthheads/p%d%04d%02d.png', skintonecode, headtypecode, haircolorcode)
    end
    
    local url = string.format('%s/img/assets/%d/%s', URL_LINKS["CDN"], FIFA, fpath)
    local img_ss = self:load_img(fpath, url)
    
    -- If file is not a png file use notfound.png
    if not img_ss then return self:load_img('heads/notfound.png', URL_LINKS["CDN"] .. '/img/assets/common/heads/notfound.png') end
    
    return img_ss
end

function FormManager:is_manager_career(addr)
    if not addr then
        self.logger:warning("is_manager_career, no addr")
        return 0
    end
    local playertype = self.game_db_manager:get_table_record_field_value(addr, "career_users", "playertype")
    self.logger:debug(string.format("playertype: %d, %s", playertype, type(playertype)))
    local result = playertype == -1
    return result
end

function FormManager:get_user_clubteamid(addr)
    if not addr then
        self.logger:warning("get_user_clubteamid, no addr")
        return 0
    end
    local clubteamid = self.game_db_manager:get_table_record_field_value(addr, "career_users", "clubteamid")
    self.logger:debug(string.format("clubteamid: %d, %s", clubteamid, type(clubteamid)))
    return clubteamid
end

function FormManager:set_cfg(new_cfg)
    self.cfg = new_cfg
end

function FormManager:style_form()
    self.frm.BorderStyle = bsNone
    self.frm.AlphaBlend = true
    self.frm.AlphaBlendValue = self.cfg.gui.opacity or 255
end

function FormManager:ResizerMouseDown(sender, button, x, y)
    self.resizer = {
        allow_resize = true,
        w = sender.Owner.Width,
        h = sender.Owner.Height,
        mx = x,
        my = y
    }
end

function FormManager:ResizerMouseMove(sender, x, y)
    if (not self.resizer) then return end
    if self.resizer['allow_resize'] then
        self.resizer['w'] = x - self.resizer['mx'] + sender.Owner.Width
        self.resizer['h'] = y - self.resizer['my'] + sender.Owner.Height
    end
end
function FormManager:ResizerMouseUp(sender, button, x, y)
    if (not self.resizer) then return end
    self.resizer['allow_resize'] = false
    sender.Owner.Width = self.resizer['w']
    sender.Owner.Height = self.resizer['h']
end

function FormManager:doPaint(sender, bgcolor)
    local btn_txt = sender.Hint
    sender.Canvas.Brush.Color = bgcolor
    sender.Canvas.fillRect(0, 0, sender.Width, sender.Height)
    sender.Canvas.Font.Color = 0xC0C0C0
    sender.Canvas.Font.Size = 12

    -- Text Center
    local text_x = sender.Width//2 - sender.Canvas.getTextWidth(btn_txt)//2
    local text_y = sender.Height//2 - sender.Canvas.getTextHeight(btn_txt)//2
    sender.Canvas.textOut(text_x, text_y, btn_txt)
end

-- Paint button
function FormManager:onPaintButton(sender)
    self:doPaint(sender, 0x3f3134)
end

-- Button hover effect
function FormManager:onBtnMouseEnter(sender)
    self:doPaint(sender, 0x5c474c)
end
function FormManager:onBtnMouseLeave(sender)
    self:doPaint(sender, 0x3f3134)
end

function FormManager:OnWindowCloseClick(sender)
    self.frm.close()
end

function FormManager:OnWindowMinimizeClick(sender)
    self.frm.WindowState = "wsMinimized" 
end

function FormManager:TopPanelOnMouseDown(sender, button, x, y)
    self.frm.dragNow()
end

function FormManager:AlwaysOnTopClick(sender)
    if sender.Owner.FormStyle == "fsNormal" then
        sender.Owner.AlwaysOnTop.Visible = false
        sender.Owner.AlwaysOnTopOn.Visible = true
        sender.Owner.FormStyle = "fsSystemStayOnTop"
    else
        sender.Owner.AlwaysOnTop.Visible = true
        sender.Owner.AlwaysOnTopOn.Visible = false
        sender.Owner.FormStyle = "fsNormal"
    end
end


function FormManager:assign_events()
    self.frm.Resizer.OnMouseDown = function(sender, button, x, y)
        self:ResizerMouseDown(sender, button, x, y)
    end

    self.frm.Resizer.OnMouseMove = function(sender, x, y)
        self:ResizerMouseMove(sender, x, y)
    end

    self.frm.Resizer.OnMouseUp = function(sender, button, x, y)
        self:ResizerMouseUp(sender, button, x, y)
    end

    self.frm.AlwaysOnTop.OnClick = function(sender)
        self:AlwaysOnTopClick(sender)
    end

    self.frm.AlwaysOnTopOn.OnClick = function(sender)
        self:AlwaysOnTopClick(sender)
    end

    self.frm.Exit.OnClick = function(sender)
        self:OnWindowCloseClick(sender)
    end

    self.frm.Minimize.OnClick = function(sender)
        self:OnWindowMinimizeClick(sender)
    end

    self.frm.TopPanel.OnMouseDown = function(sender, button, x, y)
        self:TopPanelOnMouseDown(sender, button, x, y)
    end
end

return FormManager;
