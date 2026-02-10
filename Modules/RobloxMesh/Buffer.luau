local Buffer = {}
Buffer.__index = Buffer

export type Class = typeof(setmetatable({} :: {
    _buf: buffer,
    _pos: number,

    _bitsValue: number,
    _bitsLength: number,
}, Buffer))

export type LowHigh = {
    Low: number,
    High: number,
}

function Buffer.new(buf: buffer, pos: number?): Class
    if pos then
        local len = buffer.len(buf)
        assert(pos >= 0 and pos <= len, "Position out of bounds!")
    end

    return setmetatable({
        _buf = buf,
        _pos = pos or 0,

        _bitsValue = 0,
        _bitsLength = 0,
    }, Buffer)
end

local function checkRead(self: Class, size: number)
    local len = buffer.len(self._buf)
    assert(self._pos + size <= len, "Attempt to read beyond buffer length!")
end

function Buffer.GetLength(self: Class): number
    return buffer.len(self._buf)
end

function Buffer.GetPosition(self: Class): number
    return self._pos
end

function Buffer.GetBuffer(self: Class): buffer
    return self._buf
end

function Buffer.SetPosition(self: Class, pos: number)
    local len = buffer.len(self._buf)
    assert(pos >= 0 and pos <= len, "Position out of bounds!")

    self._pos = pos
end

function Buffer.Skip(self: Class, size: number)
    checkRead(self, size)
    self._pos += size
end

function Buffer.ReadInt8(self: Class): number
    checkRead(self, 1)

    local value = buffer.readi8(self._buf, self._pos)
    self._pos += 1
    
    return value
end

function Buffer.ReadUInt8(self: Class): number
    checkRead(self, 1)

    local value = buffer.readu8(self._buf, self._pos)
    self._pos += 1
    
    return value
end

function Buffer.ReadInt16(self: Class): number
    checkRead(self, 2)

    local value = buffer.readi16(self._buf, self._pos)
    self._pos += 2
    
    return value
end

function Buffer.ReadUInt16(self: Class): number
    checkRead(self, 2)

    local value = buffer.readu16(self._buf, self._pos)
    self._pos += 2
    
    return value
end

function Buffer.ReadInt32(self: Class): number
    checkRead(self, 4)

    local value = buffer.readi32(self._buf, self._pos)
    self._pos += 4
    
    return value
end

function Buffer.ReadUInt32(self: Class): number
    checkRead(self, 4)

    local value = buffer.readu32(self._buf, self._pos)
    self._pos += 4
    
    return value
end

function Buffer.ReadInt64(self: Class): LowHigh
    checkRead(self, 8)

    local low = buffer.readu32(self._buf, self._pos)
    local high = buffer.readi32(self._buf, self._pos + 4)
    self._pos += 8

    return {
        Low = low,
        High = high,
    }
end

function Buffer.ReadUInt64(self: Class): LowHigh
    checkRead(self, 8)

    local low = buffer.readu32(self._buf, self._pos)
    local high = buffer.readu32(self._buf, self._pos + 4)
    self._pos += 8

    return {
        Low = low,
        High = high,
    }
end

function Buffer.ReadFloat32(self: Class): number
    checkRead(self, 4)

    local value = buffer.readf32(self._buf, self._pos)
    self._pos += 4
    
    return value
end

function Buffer.ReadFloat64(self: Class): number
    checkRead(self, 8)

    local value = buffer.readf64(self._buf, self._pos)
    self._pos += 8
    
    return value
end

function Buffer.ReadVarInt(self: Class): number
    local result = 0
    local shift = 0

    while true do
        local inByte = self:ReadUInt8()
        result = bit32.bor(result, bit32.lshift(bit32.band(inByte, 0x7F), shift))

        if not bit32.btest(inByte, 0x80) then
            break
        end

        shift += 7
    end

    return result
end

function Buffer.ReadBytes(self: Class, size: number): { number }
    local bytes = table.create(size, 0)
    checkRead(self, size)

    for i = 0, size - 1 do
        bytes[i + 1] = self:ReadUInt8()
    end

    return bytes
end

function Buffer.ReadString(self: Class, length: number?): string
    local str = ""

    while true do
        local char = self:ReadUInt8()

        if length == nil then
            if char == 0 then
                break
            end

            str ..= string.char(char)
        else
            str ..= string.char(char)
            
            if #str >= length then
                break
            end
        end
    end

    return str
end

function Buffer.ReadVector2(self: Class): Vector2
    local x = self:ReadFloat32()
    local y = self:ReadFloat32()
    return Vector2.new(x, y)
end

function Buffer.ReadVector3(self: Class): Vector3
    local x = self:ReadFloat32()
    local y = self:ReadFloat32()
    local z = self:ReadFloat32()
    return Vector3.new(x, y, z)
end


function Buffer.FlushBits(self: Class)
    self._bitsValue = 0
    self._bitsLength = 0
end

function Buffer.ReadBits(self: Class, n: number)
	local bitsValue = self._bitsValue
	local bitsLength = self._bitsLength

	while bitsLength < n do
		local byte = self:ReadUInt8()
		
		for i = 0, 7 do
			bitsValue = bit32.bor(bit32.lshift(bitsValue, 1), bit32.band(bit32.rshift(byte, i), 1))
		end
		
		bitsLength += 8
	end
	
	local value = 0
	
	for bit = 0, n - 1 do
		bitsLength -= 1
		value = bit32.bor(value, bit32.lshift(bit32.band(bit32.rshift(bitsValue, bitsLength), 1), bit))
	end

	self._bitsValue = bitsValue
	self._bitsLength = bitsLength
	
	return value
end

return Buffer