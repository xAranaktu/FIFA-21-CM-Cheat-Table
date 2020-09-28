require 'lua/consts';
require 'lua/helpers';

local FormManager = {}

function FormManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    self.cfg = nil
    self.logger = nil

    self.frm = nil
    self.name = ""

    return o;
end

function FormManager:set_cfg(new_cfg)
    self.cfg = new_cfg
end

function FormManager:style_form()
    self.frm.BorderStyle = bsNone
    self.frm.AlphaBlend = true
    self.frm.AlphaBlendValue = self.cfg.gui.opacity or 255
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
