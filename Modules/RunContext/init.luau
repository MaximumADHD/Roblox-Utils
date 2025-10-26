--!strict

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local isEdit = false
local isServer = RunService:IsServer()
local isClient = RunService:IsClient()
local isStudio = RunService:IsStudio()

local isOnline = game.JobId ~= ""
local isRCC = isOnline and isServer

pcall(function ()
    isEdit = RunService:IsEdit()
end)

export type Label = | "Edit" | "Server" | "Client"

return table.freeze({
    -- The identity of the current run context.
    Identity = (if isEdit then "Edit" elseif isServer then "Server" else "Client") :: Label,

    --- Is this running on a dedicated Roblox server? (RCC = Roblox Cloud Compute)
    IsRCC = isRCC,

    --- Is the current run an edit session?
    IsEdit = isEdit,

    --- Is the current run a test session in Studio?
    IsTestRun = isStudio and not isEdit,

    --- Is this running from a server context?
    IsServer = isServer,

    --- Is this running from a client context?
    IsClient = isClient,

    --- Is this running in Roblox Studio?
    IsStudio = isStudio,

    --- Is there a dedicated server instance associated with this session (i.e. we are a dedicated server or a client connected to one)?
    IsOnline = isOnline,

    --- Is the current device using a ten-foot interface (e.g. console)?
    IsTenFoot = GuiService:IsTenFootInterface(),

    --- Is the current device a touch-enabled device (e.g. mobile)?
    IsTouch = UserInputService.TouchEnabled,

    --- Is the current device a VR device?
    IsVR = VRService.VREnabled,
})