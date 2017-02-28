local class = require "andross.middleclass"
local androssMath = require "andross.math"

local Pose = class("Pose")

-- default values for animation channels
channelDefaults = {
    scaleX = 1.0,
    scaleY = 1.0,
}

function Pose:initialize()
    self.values = {}
end

function Pose:setPoseValue(type, name, channel, value)
    if not self.values[type] then
        self.values[type] = {}
    end

    if not self.values[type][name] then
        self.values[type][name] = setmetatable({}, {__index = channelDefaults})
    end

    self.values[type][name][channel] = value
end

function Pose:getPoseValue(type, name, channel)
    if not self.values[type] or not self.values[type][name] then
        return channelDefaults[channel]
    end

    local ret = self.values[type][name][channel]
    if ret == nil then
        return channelDefaults[channel]
    else
        return ret
    end
end

-- not order dependent!
-- poseA, weightA, poseB, weightB, poseC, weightC, ...
function Pose.static:mix(...)
    local ret = Pose()
    local args = {...}
    for i = 1, #args, 2 do
        local pose, weight = args[i], args[i+1]

        for typeName, objType in pairs(pose.values) do
            for objName, obj in pairs(objType) do
                for channelName, channelValue in pairs(obj) do
                    -- if you need other default values for your custom animated channels, see top
                    local value = ret:getPoseValue(typeName, objName, channelName) or 0

                    -- this seems weird too
                    if channelDefaults[channelName] then
                        value = value + (channelValue - channelDefaults[channelName]) * weight
                    else
                        value = value + channelValue * weight
                    end

                    ret:setPoseValue(typeName, objName, channelName, value)

                    if channelName == "angle" then -- so ugly
                        local angleDirX, angleDirY = math.cos(channelValue), math.sin(channelValue)
                        ret.values[typeName][objName]["angleDirX"] = (ret.values[typeName][objName]["angleDirX"] or 0) + angleDirX * weight
                        ret.values[typeName][objName]["angleDirY"] = (ret.values[typeName][objName]["angleDirY"] or 0) + angleDirY * weight
                        ret.values[typeName][objName]["angleWeightSum"] = (ret.values[typeName][objName]["angleWeightSum"] or 0) + weight
                    end
                end
            end
        end

        -- turn the direction into angles again after summing
        for typeName, objType in pairs(ret.values) do
            for objName, obj in pairs(objType) do
                for channelName, channelValue in pairs(obj) do
                    if channelName == "angle" then
                        -- We multiply by the weight sum, so that if we only have one angle with weight 0.1, we don't get the full direction
                        -- also if we have any number of angles at any weight > 0, we get their average.
                        -- conceptually I understand this as atan2(sum[math.sin(angle_i)], sum[math.cos(angle_i)]) being the weighted average
                        -- already divided by the weight sum, and we multiply it again, to only get the weighted sum
                        ret:setPoseValue(typeName, objName, channelName,
                                math.atan2(ret.values[typeName][objName]["angleDirY"],
                                           ret.values[typeName][objName]["angleDirX"]) * ret.values[typeName][objName]["angleWeightSum"])
                    end
                end
            end
        end
    end

    return ret
end

-- order dependent!
-- alpha = 1 => "other" is fully "opaque" (full overwrite)
-- TODO: Test this!
function Pose.static:overlay(pose, other, alpha)
    local ret = Pose()
    -- set to source pose
    for typeName, objType in pairs(pose.values) do
        for objName, obj in pairs(objType) do
            for channelName, channelValue in pairs(obj) do
                ret:setPoseValue(typeName, objName, channelName,
                                 pose:getPoseValue(typeName, objName, channelName))
            end
        end
    end

    -- overwrite with other
    for typeName, objType in pairs(other.values) do
        for objName, obj in pairs(objType) do
            for channelName, channelValue in pairs(obj) do
                local value = ret:getPoseValue(typeName, objName, channelName)
                if value then -- blend
                    value = value + (channelValue - value) * alpha
                    if channelName == "angle" then
                        value = androssMath.lerpAngles(value, channelValue, alpha)
                    end
                else
                    value = channelValue
                end
                ret:setPoseValue(typeName, objName, channelName, value)
            end
        end
    end

    return ret
end

function Pose:apply(skeleton)
    if self.values.bones then
        for boneName, bone in pairs(self.values.bones) do
            for channelName, channelValue in pairs(bone) do
                skeleton.bones[boneName][channelName] = channelValue
            end
        end
    end
end

return Pose