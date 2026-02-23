local Draco = script.Parent
local RobloxMesh = Draco.Parent
local Buffer = require(RobloxMesh.Buffer)

local DEBUG = false
type Buffer = Buffer.Class

local debugStack = 0

local function nameof(sourceTable: { [string]: number }, value: number?): string
    if value == nil then
        return "nil"
    end

    for name, val in pairs(sourceTable) do
        if val == value then
            return `{value} ({name})`
        end
    end

    return `{value} (!!INVALID)`
end

local function incDebugStack()
    if DEBUG then
        debugStack += 1
    end
end

local function debugPrint(fmt: string, ...: any)
    if DEBUG then
        local indent = string.rep("..", debugStack)
        print(`[DRACO] {indent}{fmt:format(...)}`)
    end
end

local function decDebugStack()
    if DEBUG then
        debugStack -= 1
    end
end

local function debugBufferState(buf: Buffer)
    if not DEBUG then
        return
    end

    -- Save position before reading
    local pos = buf:GetPosition()
    local size = buf:GetLength()

    local startPos = math.max(0, pos - 16)
    local endPos = math.min(size, pos + 16)

    local length = endPos - startPos
    buf:SetPosition(startPos)

    local data = buf:ReadString(length)
    local at = 0
    
    data = data:gsub(".", function (char)
        local hex = string.format("%02X", char:byte())
        at += 1

        if at == (pos - startPos) then
            hex = `[{hex}] `
        else
            hex = `{hex} `
        end

        return hex
    end)

    -- Restore original position
    buf:SetPosition(pos)
    incDebugStack()

    debugPrint(`[Buffer State] | Pos: {pos}/{size} | Data {startPos}-{endPos}: {data}`)
    decDebugStack()
end

local function debugError(fmt: string, ...: any)
    error(`[DRACO] {fmt:format(...)}`, 2)
end

local function debugAssert<T>(value: T?, fmt: string, ...: any): T
    return assert(value, `[DRACO] {fmt:format(...)}`)
end

return table.freeze({
    NameOf = nameof,
    Print = debugPrint,
    Error = debugError,
    Assert = debugAssert,
    StackOpen = incDebugStack,
    StackClose = decDebugStack,
    PrintBufferState = debugBufferState,
})