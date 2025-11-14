local StringBuilder = {}
StringBuilder.__index = StringBuilder

export type Class = typeof(setmetatable({} :: {
    _stack: number,
    _buffer: string,
    
    _dirty: boolean,
    _splitCache: { string },
}, StringBuilder))

local function new(): Class
    return setmetatable({
        _stack = 0,
        _buffer = "",

        _dirty = false,
        _splitCache = {},
    }, StringBuilder)
end

function StringBuilder.Write(self: Class, fmt: string?, ...: any)
    if not fmt then
        return
    end

    local argCount = select("#", ...)

    local content = if argCount > 0
        then fmt:format(...)
        else fmt

    if #content == 0 then
        return
    end
    
    self._buffer ..= content
    self._dirty = true
end

function StringBuilder.WriteLine(self: Class, fmt: string?, ...: any)
    if not fmt then
        self._buffer ..= "\n"
        return
    end

    local argCount = select("#", ...)

    local line = if argCount > 0
        then fmt:format(...)
        else fmt
    
    if #line == 0 then
        self._buffer ..= "\n"
        return
    end
    
    local stack = string.rep(" ", self._stack * 4)
    self._buffer ..= `{stack}{line}\n`

    if self._stack > 0 then
        self._buffer ..= string.rep(" ", self._stack * 4)
    end

    self._dirty = true
end

function StringBuilder.OpenStack(self: Class)
    self._stack += 1
    self._buffer ..= string.rep(" ", 4)
end

function StringBuilder.CloseStack(self: Class)
    self._stack = math.max(0, self._stack - 1)
    self._buffer = self._buffer:sub(1, -5) -- Remove the last 4 spaces
end

function StringBuilder.GetContent(self: Class): string
    return self._buffer
end

function StringBuilder.GetLines(self: Class): { string }
    if self._dirty then
        self._splitCache = self._buffer:split("\n")
        self._dirty = false
    end

    return self._splitCache
end

function StringBuilder.GetLineCount(self: Class): number
    return #self:GetLines()
end

function StringBuilder.GetLine(self: Class, index: number): string
    return self:GetLines()[index] or ""
end

function StringBuilder.Clear(self: Class)
    self._stack = 0
    self._buffer = ""

    self._splitCache = {}
    self._dirty = false
end

return table.freeze({
    new = new,
})