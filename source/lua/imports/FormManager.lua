require 'lua/consts';
require 'lua/helpers';

local FormManager = {}

function FormManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    self.cfg = nil
    self.logger = nil

    self.resize = nil
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
