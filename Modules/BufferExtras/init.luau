--!native
--!strict

--- Reads a 16-bit floating point number (half-precision) from a buffer at the given offset.
local function readf16(buf: buffer, offset: number): number
    local b0 = buffer.readu8(buf, offset)
    local b1 = buffer.readu8(buf, offset + 1)

    local sign = bit32.btest(b0, 128) and -1 or 1
    local exponent = bit32.rshift(bit32.band(b0, 127), 2)
    local mantissa = bit32.lshift(bit32.band(b0, 3), 8) + b1

    if exponent == 31 then --2^5-1
        if mantissa ~= 0 then
            return (0 / 0)
        else
            return math.huge * sign
        end
    elseif exponent == 0 then
        if mantissa == 0 then
            return 0
        else
            return math.ldexp(mantissa / 1024, -14) * sign
        end
    end

    return math.ldexp((mantissa / 1024) + 1, exponent - 15) * sign
end

--- Writes a 16-bit floating point number (half-precision) to a buffer at the given offset.
local function writef16(buf: buffer, offset: number, value: number)
    local mantissa, exponent
    local sign = value < 0

    value = math.abs(value)
    mantissa, exponent = math.frexp(value)

    if value == math.huge then
        if sign then
            buffer.writeu8(buf, offset, 0b_11111100)
        else
            buffer.writeu8(buf, offset, 0b_01111100)
        end

        buffer.writeu8(buf, offset + 1, 0b_00000000)
    elseif value ~= value or value == 0 then
        buffer.writeu16(buf, offset, 0)
    elseif exponent + 15 <= 1 then -- Bias for halfs is 15
        mantissa = math.floor(mantissa * 1024 + 0.5)

        if sign then
            buffer.writeu8(buf, offset, (128 + bit32.rshift(mantissa, 8))) -- Sign bit, 5 empty bits, 2 from mantissa
        else
            buffer.writeu8(buf, offset, (bit32.rshift(mantissa, 8)))
        end

        buffer.writeu8(buf, offset + 1, bit32.band(mantissa, 255)) -- Get last 8 bits from mantissa
    else
        mantissa = ((mantissa - 0.5) * 2048 + 0.5) // 1

        -- The bias for halfs is 15, 15-1 is 14
        if sign then
            buffer.writeu8(buf, offset, (128 + bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8)))
        else
            buffer.writeu8(buf, offset, (bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8)))
        end

        buffer.writeu8(buf, offset + 1, bit32.band(mantissa, 255))
    end
end

--- Reads a signed 53-bit integer from a buffer at the given offset.
--- * Note: Lua numbers are double-precision floats, so they can accurately represent integers up to 53 bits.
local function readi53(buf: buffer, offset: number): number
    local lo = buffer.readu32(buf, offset)
    local hi = buffer.readi32(buf, offset + 4)
    return (hi * 0x7FFFFFFF) + lo
end

--- Writes a signed 53-bit integer to a buffer at the given offset.
--- * Note: Lua numbers are double-precision floats, so they can accurately represent integers up to 53 bits.
local function writei53(buf: buffer, offset: number, value: number)
    local lo = value % 0x7FFFFFFF
    local hi = value // 0x7FFFFFFF

    buffer.writeu32(buf, offset, lo)
    buffer.writei32(buf, offset + 4, hi)
end

--- Reads an unsigned 53-bit integer from a buffer at the given offset.
--- * Note: Lua numbers are double-precision floats, so they can accurately represent integers up to 53 bits.
local function readu53(buf: buffer, offset: number): number
    local lo = buffer.readu32(buf, offset)
    local hi = buffer.readu32(buf, offset + 4)
    return (hi * 0x100000000) + lo
end

--- Writes an unsigned 53-bit integer to a buffer at the given offset.
--- * Note: Lua numbers are double-precision floats, so they can accurately represent integers up to 53 bits.
local function writeu53(buf: buffer, offset: number, value: number)
    local lo = value % 0x100000000
    local hi = value // 0x100000000

    buffer.writeu32(buf, offset, lo)
    buffer.writeu32(buf, offset + 4, hi)
end

--- Reads a variable-length integer from a buffer at the given offset.
--- Returns the integer and the new offset.
local function readVarInt(buf: buffer, offset: number): (number, number)
    local result = 0
    local shift = 0
    local byte

    repeat
        byte = buffer.readu8(buf, offset)
        result += bit32.lshift(bit32.band(byte, 127), shift)

        offset += 1
        shift += 7
    until bit32.btest(byte, 128)

    return result, offset
end

--- Writes a variable-length integer to a buffer at the given offset.
--- Returns the new offset.
local function writeVarInt(buf: buffer, offset: number, value: number): number
    repeat
        local byte = bit32.band(value, 127)
        value = bit32.rshift(value, 7)

        if value ~= 0 then
            byte = bit32.bor(byte, 128)
        end

        buffer.writeu8(buf, offset, byte)
        offset += 1
    until value == 0

    return offset
end

return table.freeze({
    ReadInt53 = readi53,
    WriteInt53 = writei53,

    ReadUInt53 = readu53,
    WriteUInt53 = writeu53,

    ReadFloat16 = readf16,
    WriteFloat16 = writef16,

    ReadVarInt = readVarInt,
    WriteVarInt = writeVarInt,
})