local FormManager = {}

function FormManager.init(frm, caption)
    FormManager.o = frm

    if (caption) then
        FormManager.o.Caption = caption
    end

    FormManager.assign_events()

    FormManager.o.LoadingPanel.Visible = true
    FormManager.o.LoadingPanel.Caption = "Loading data..."
end

function FormManager.TopPanelOnMouseDown(sender, button, x, y)
    FormManager.o.dragNow()
end

function FormManager.assign_events()
    FormManager.o.TopPanel.OnMouseDown = FormManager.TopPanelOnMouseDown
end

function FormManager.update_status(new_status)
    FormManager.o.LabelStatus.Caption = new_status
end

return FormManager;