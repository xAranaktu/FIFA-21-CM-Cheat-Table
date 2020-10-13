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


    self.addr_list = nil
    self.fnSaveCfg = nil
    self.new_cfg = {}
    self.has_unsaved_changes = false
    self.selection_idx = 0

    self.fill_timer = nil
    self.form_components_description = nil

    return o;
end

function thisFormManager:get_components_description()
    local components_description = {
        PlayerIDEdit = {}
    }

    return components_description
end

function thisFormManager:onShow(sender)
    self.logger:debug(string.format("onShow: %s", self.name))

    -- Show Loading panel
    self.frm.FindPlayerByID.Visible = false
    self.frm.SearchPlayerByID.Visible = false
    self.frm.WhileLoadingPanel.Visible = true

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

    -- Hide Loading Panel and show components
    self.frm.PlayerInfoTab.Color = "0x001D1618"
    self.frm.PlayerInfoPanel.Visible = true
    self.frm.WhileLoadingPanel.Visible = false
end

function thisFormManager:fill_form(record_addr, playerid)
    if self.form_components_description == nil then
        self.form_components_description = self:get_components_description()
    end


    for i=0, self.frm.ComponentCount-1 do
        local component = self.frm.Component[i]
        if component == nil then
            goto continue
        end

        local component_name = component.Name
        local comp_desc = self.form_components_description[component_name]
        if comp_desc == nil then
            goto continue
        end

        local component_class = component.ClassName

        ::continue::
    end

end

function thisFormManager:assign_current_form_events()
    self:assign_events()

    self.frm.OnShow = function(sender)
        self:onShow(sender)
    end

end

function thisFormManager:setup(params)
    self.cfg = params.cfg
    self.logger = params.logger
    self.frm = params.frm_obj
    self.name = params.name

    self.logger:info(string.format("Setup Form Manager: %s", self.name))

    self:assign_current_form_events()
end


return thisFormManager;