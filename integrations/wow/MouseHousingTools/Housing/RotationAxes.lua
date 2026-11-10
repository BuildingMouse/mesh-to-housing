local _, MHT = ...
local RotationAxes = {}
MHT.RotationAxes = RotationAxes

function RotationAxes.Validate(axes)
    local seen = {}
    for _, axis in ipairs({ "x", "y", "z" }) do
        local record = axes and axes[axis]
        if not record then return nil, "Test and answer for X, Y and Z before saving." end
        if not ({ x = true, y = true, z = true })[record.axis] or (record.sign ~= 1 and record.sign ~= -1) then
            return nil, "Choose an observed direction for each rotation axis."
        end
        if seen[record.axis] then return nil, "Two answers describe the same rotation axis. Check those tests again." end
        seen[record.axis] = true
    end
    return true
end

function RotationAxes.ForItem(decorID, measurements)
    local item = measurements and measurements[decorID]
    local axes = item and item.rotationAxes
    if RotationAxes.Validate(axes) then return MHT.Util.Copy(axes) end
end
