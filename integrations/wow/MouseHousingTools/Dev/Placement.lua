local _, MHT = ...
local Placement = MHT.Placement
local job = { movingLabel = " (test)..." }

function job.Reject(placement, selected)
    if placement.finished[selected.decorGUID] then return "That copy is finished. Click another copy." end
end

function job.Move(placement, edit, guid, done, onPhase)
    placement.motion:Apply(edit, placement.profile, guid, done, onPhase)
end

function job.Done() return "Test finished. Movement and rotation saved." end

function Placement:StartTest(edit, profile)
    if self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    if self.api:IsSelected() then
        return nil, "Deselect the item, press Start, then click it to test."
    end
    return self:StartSelecting({ items = { edit } }, profile, job, "Test armed. Click one item in Advanced mode.")
end
