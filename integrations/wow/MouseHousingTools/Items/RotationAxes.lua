local _, MHT = ...
local RotationAxes = {}
MHT.RotationAxes = RotationAxes

-- Defaults confirmed in game.
RotationAxes.DEFAULT = { x = { axis = "y", sign = -1 }, y = { axis = "x", sign = 1 }, z = { axis = "z", sign = 1 } }
