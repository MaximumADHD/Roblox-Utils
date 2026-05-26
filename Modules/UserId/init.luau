local Shared = script.Parent
local RunContext = require(Shared.RunContext)

local StudioService = if RunContext.IsStudio
    then game:GetService("StudioService")
    else nil

local Players = game:GetService("Players")

--- Returns a player's `UserId`, and a `boolean` indicating whether it is a mocked value or not.
--- If `noMock` is `true`, any mocked results will be discarded.
---
--- In **Edit Mode**:
--- * Will return the numerical value of the `"MockUserId"` attribute on `StudioService` if it exists
--- * Otherwise it will return the current player's `UserId`.
---
--- In **Studio** with a `Player` (**Server**/**Client**):
--- * Will return the numerical value of the `"MockUserId"` attribute on the `Player` if it exists.
--- * If the player's `UserId` is less than 0 (indicating a test session),
---    * It will return the player's `CharacterAppearanceId` if greater than 0.
--- * All else failing, the negative `UserId` is returned as is.
---
--- In a **live session** (**Server**/**Client**):
--- * The player's `UserId` is returned.
--- * `player` is assumed to be the `LocalPlayer` on the **client** if not provided.
--- * Will throw an error on the **server** if no `Player` is provided.
local function getUserId(target: (Player | number)?, noMock: boolean?): (number, boolean)
    local player: Player? = if typeof(target) == "number"
        then Players:GetPlayerByUserId(target)
        else target
    
    if RunContext.IsEdit and StudioService then
        local mock = tonumber(StudioService:GetAttribute("MockUserId"))

        if noMock then
            return StudioService:GetUserId(), false
        else
            return mock or StudioService:GetUserId(), (mock ~= nil)
        end
    elseif RunContext.IsClient then
        player = Players.LocalPlayer
    end

    assert(player, "Player must be provided on the server")

    if RunContext.IsStudio and not noMock then
        local mock = tonumber(player:GetAttribute("MockUserId"))

        if mock then
            return mock, true
        end
    end

    local userId = player.UserId

    if userId < 0 and not noMock then
        local appearanceId = player.CharacterAppearanceId

        if appearanceId > 0 then
            return appearanceId, true
        end
    end

    return userId, false
end

return table.freeze({
    Get = getUserId,
})