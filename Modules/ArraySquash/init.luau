local Shared = script.Parent
local Squash = require(Shared.Squash)

local VLQ = Squash.vlq()
local F32 = Squash.f32()
local I32 = Squash.i32()
local U32 = Squash.u32()
local U8 = Squash.u8()

type Cursor = Squash.Cursor
type SerDes<T...> = Squash.SerDes<T...>

--------------------------------------------
-- SerDes (Interleaved)
--------------------------------------------

local function createSerInterleaved(sizeof: number, raw: boolean, ser: (cursor: Cursor, values: {number}, i: number) -> ())
    return function (cursor: Cursor, values: { number })
        local count = #values
        local interleaves = {}

        for i = 1, sizeof do
            interleaves[i] = {}
        end

        for i, value in values do
            ser(cursor, values, i)

            for j = 1, sizeof do
                interleaves[j][i] = U8.des(cursor)
            end
        end

        for j = sizeof, 1, -1 do
            local interleave = interleaves[j]

            for i = count, 1, -1 do
                U8.ser(cursor, interleave[i])
            end
        end

        if raw then
            return
        end

        VLQ.ser(cursor, count)
    end
end

local function createDesInterleaved(sizeof: number, des: (cursor: Cursor, values: {number}, i: number) -> number)
    return function (cursor: Cursor): { number }
        local interleaves = {}
        local count = VLQ.des(cursor)

        for i = 1, sizeof do
            interleaves[i] = {}
        end

        for i = 1, sizeof do
            local interleave = interleaves[i]

            for j = 1, count do
                interleave[j] = U8.des(cursor)
            end
        end

        local values = {}

        for i = 1, count do
            for j = sizeof, 1, -1 do
                local interleave = interleaves[j]
                U8.ser(cursor, interleave[i])
            end

            values[i] = des(cursor, values, i)
        end

        return values
    end
end

--------------------------------------------
-- F32
--------------------------------------------

local function compressF32(cursor: Cursor, values: { number }, i: number)
    -- Read the value from the array.
    local value = values[i]

    -- Write the float onto the stack.
    F32.ser(cursor, value)

    -- Read the float back as u32 for bit manipulation.
    local bits = U32.des(cursor)

    -- Shift the sign bit to the front for better compression.
    bits = bit32.bor(bit32.lshift(bits, 1), bit32.rshift(bits, 31))

    -- Push it back onto the stack.
    U32.ser(cursor, bits)
end

local function decompressF32(cursor: Cursor, values: { number }, i: number): number
    -- Read the bits from the stack.
    local bits = U32.des(cursor)

    -- Shift the sign bit back to its original position.
    bits = bit32.bor(bit32.rshift(bits, 1), bit32.lshift(bit32.band(bits, 1), 31))

    -- Push the bits onto the stack.
    U32.ser(cursor, bits)

    -- Read it as a float.
    return F32.des(cursor)
end

local desInterleaved_F32 = createDesInterleaved(4, decompressF32)
local serInterleaved_F32 = createSerInterleaved(4, false, compressF32)
local serInterleavedRaw_F32 = createSerInterleaved(4, true, compressF32)

--------------------------------------------
-- I32
--------------------------------------------

local function compressI32(cursor: Cursor, values: { number }, i: number)
    local value = values[i]
    
    I32.ser(cursor, value)
    value = I32.des(cursor)

    local sign = value < 0 and 1 or 0
    value = math.abs(value)
    value = bit32.lshift(value, 1)
    value += sign

    U32.ser(cursor, value)
end

local function decompressI32(cursor: Cursor, values: { number }, i: number): number
    local value = U32.des(cursor)
    local sign = value % 2 > 0 and -1 or 1
    
    value = bit32.rshift(value, 1)
    value *= sign
    
    return value
end

local desInterleaved_I32 = createDesInterleaved(4, decompressI32)
local serInterleaved_I32 = createSerInterleaved(4, false, compressI32)
local serInterleavedRaw_I32 = createSerInterleaved(4, true, compressI32)

--------------------------------------------
-- Vector2
--------------------------------------------

local function serInterleavedRaw_Vector2(cursor: Cursor, values: { Vector2 }, raw: boolean?)
    local xs, ys = {}, {}

    for i, value in values do
        xs[i] = value.X
        ys[i] = value.Y
    end

    serInterleavedRaw_F32(cursor, ys)
    serInterleavedRaw_F32(cursor, xs)

    if not raw then
        VLQ.ser(cursor, #values)
    end
end

local function serInterleaved_Vector2(cursor: Cursor, values: { Vector2 })
    serInterleavedRaw_Vector2(cursor, values, false)
end

local function desInterleaved_Vector2(cursor: Cursor): { Vector2 }
    local count = VLQ.des(cursor)
    local xy = {}

    for i = 1, 2 do
        VLQ.ser(cursor, count)
        xy[i] = desInterleaved_F32(cursor)
    end

    local xs, ys = unpack(xy)
    local values = {}

    for i = 1, count do
        values[i] = Vector2.new(xs[i], ys[i])
    end

    return values
end

--------------------------------------------
-- Vector3
--------------------------------------------

local function serInterleaved_Vector3(cursor: Cursor, values: { Vector3 })
    local xs, ys, zs = {}, {}, {}

    for i, value in values do
        xs[i] = value.X
        ys[i] = value.Y
        zs[i] = value.Z
    end

    serInterleavedRaw_F32(cursor, zs)
    serInterleavedRaw_F32(cursor, ys)
    serInterleavedRaw_F32(cursor, xs)

    VLQ.ser(cursor, #values)
end

local desInterleaved_Vector3 = function (cursor: Cursor): { Vector3 }
    local count = VLQ.des(cursor)
    local xyz = {}

    for i = 1, 3 do
        VLQ.ser(cursor, count)
        xyz[i] = desInterleaved_F32(cursor)
    end

    local xs, ys, zs = unpack(xyz)
    local values = {}

    for i = 1, count do
        values[i] = Vector3.new(xs[i], ys[i], zs[i])
    end

    return values
end

--------------------------------------------
-- Color3
--------------------------------------------

local serInterleaved_Color3 = function (cursor: Cursor, values: { Color3 })
    local rs, gs, bs = {}, {}, {}

    for i, value in values do
        rs[i] = value.R
        gs[i] = value.G
        bs[i] = value.B
    end

    serInterleavedRaw_F32(cursor, bs)
    serInterleavedRaw_F32(cursor, gs)
    serInterleavedRaw_F32(cursor, rs)

    VLQ.ser(cursor, #values)
end

local desInterleaved_Color3 = function (cursor: Cursor): { Color3 }
    -- Read count.
    local count = VLQ.des(cursor)
    local rgb = {}

    for i = 1, 3 do
        -- Push count for each channel.
        VLQ.ser(cursor, count)

        -- Read channel.
        rgb[i] = desInterleaved_F32(cursor)
    end

    -- Unpack channels.
    local r, g, b = unpack(rgb)

    -- Build values.
    local values = {}

    for i = 1, count do
        values[i] = Color3.new(r[i], g[i], b[i])
    end

    return values
end

--------------------------------------------
-- BrickColor
--------------------------------------------

local serInterleaved_BrickColor = function (cursor: Cursor, values: { BrickColor })
    local ids = {}

    for i, value in values do
        ids[i] = value.Number
    end

    serInterleaved_I32(cursor, ids)
end

local desInterleaved_BrickColor = function (cursor: Cursor): { BrickColor }
    local ids = desInterleaved_I32(cursor)
    local values = {}

    for i, id in ids do
        values[i] = BrickColor.new(id)
    end

    return values
end

--------------------------------------------
-- UDim
--------------------------------------------

local function serInterleavedRaw_UDim(cursor: Cursor, values: { UDim }, raw: boolean)
    local scales, offsets = {}, {}

    for i, value in values do
        scales[i] = value.Scale
        offsets[i] = value.Offset
    end

    serInterleavedRaw_I32(cursor, offsets)
    serInterleavedRaw_F32(cursor, scales)

    if not raw then
        VLQ.ser(cursor, #values)
    end
end

local serInterleaved_UDim = function (cursor: Cursor, values: { UDim })
    serInterleavedRaw_UDim(cursor, values, false)
end

local desInterleaved_UDim = function (cursor: Cursor): { UDim }
    -- Read count.
    local count = VLQ.des(cursor)

    -- Push count for scales.
    VLQ.ser(cursor, count)

    -- Read scales.
    local scales = desInterleaved_F32(cursor)

    -- Push count for offsets.
    VLQ.ser(cursor, count)

    -- Read offsets.
    local offsets = desInterleaved_I32(cursor)

    -- Build values.
    local values = {}

    for i = 1, count do
        values[i] = UDim.new(scales[i], offsets[i])
    end

    return values
end

--------------------------------------------
-- UDim2
--------------------------------------------

local function serInterleaved_UDim2(cursor: Cursor, values: { UDim2 })
    local x, y = {}, {}

    for i, value in values do
        x[i] = value.X
        y[i] = value.Y
    end

    serInterleavedRaw_UDim(cursor, y, true)
    serInterleavedRaw_UDim(cursor, x, true)
    VLQ.ser(cursor, #values)
end

local function desInterleaved_UDim2(cursor: Cursor): { UDim2 }
    local count = VLQ.des(cursor)
    local dims = {}

    for i = 1, 2 do
        VLQ.ser(cursor, count)
        dims[i] = desInterleaved_UDim(cursor)
    end

    local x, y = unpack(dims)
    local values = {}

    for i = 1, count do
        values[i] = UDim2.new(x[i], y[i])
    end

    return values
end

--------------------------------------------
-- Rect
--------------------------------------------

local function serInterleaved_Rect(cursor: Cursor, values: { Rect })
    local mins, maxs = {}, {}

    for i, value in values do
        mins[i] = value.Min
        maxs[i] = value.Max
    end

    serInterleavedRaw_Vector2(cursor, maxs, true)
    serInterleavedRaw_Vector2(cursor, mins, true)
    VLQ.ser(cursor, #values)
end

local function desInterleaved_Rect(cursor: Cursor): { Rect }
    local count = VLQ.des(cursor)
    local aabbs = {}

    for i = 1, 2 do
        VLQ.ser(cursor, count)
        aabbs[i] = desInterleaved_Vector2(cursor)
    end

    local mins, maxs = unpack(aabbs)
    local values = {}

    for i = 1, count do
        values[i] = Rect.new(mins[i], maxs[i])
    end

    return values
end

--------------------------------------------
-- SerDes (Accumulated)
--------------------------------------------

local function createSerAccumulated(ser: (cursor: Cursor, values: {number}) -> ())
    return function (cursor: Cursor, values: { number })
        local prev = 0
        local accumulated = {}

        for i, value in values do
            local delta = value - prev
            accumulated[i] = delta
            prev = value
        end

        ser(cursor, accumulated)
    end
end

local function createDesAccumulated(des: (cursor: Cursor) -> { number })
    return function (cursor: Cursor): { number }
        local accumulated = des(cursor)
        local values = {}
        local prev = 0

        for i, delta in accumulated do
            local value = prev + delta
            values[i] = value
            prev = value
        end

        return values
    end
end

--------------------------------------------
-- F32 (Accumulated)
--------------------------------------------

local serAccumulated_F32 = createSerAccumulated(serInterleaved_F32)
local desAccumulated_F32 = createDesAccumulated(desInterleaved_F32)

--------------------------------------------
-- I32 (Accumulated)
--------------------------------------------

local serAccumulated_I32 = createSerAccumulated(serInterleaved_I32)
local desAccumulated_I32 = createDesAccumulated(desInterleaved_I32)

--------------------------------------------

return table.freeze({
    Interleaved = table.freeze({
        F32 = table.freeze({
            ser = serInterleaved_F32,
            des = desInterleaved_F32,
        }),

        I32 = table.freeze({
            ser = serInterleaved_I32,
            des = desInterleaved_I32,
        }),

        BrickColor = table.freeze({
            ser = serInterleaved_BrickColor,
            des = desInterleaved_BrickColor,
        }),

        Color3 = table.freeze({
            ser = serInterleaved_Color3,
            des = desInterleaved_Color3,
        }),

        Rect = table.freeze({
            ser = serInterleaved_Rect,
            des = desInterleaved_Rect,
        }),

        Vector2 = table.freeze({
            ser = serInterleaved_Vector2,
            des = desInterleaved_Vector2,
        }),

        Vector3 = table.freeze({
            ser = serInterleaved_Vector3,
            des = desInterleaved_Vector3,
        }),

        UDim = table.freeze({
            ser = serInterleaved_UDim,
            des = desInterleaved_UDim,
        }),

        UDim2 = table.freeze({
            ser = serInterleaved_UDim2,
            des = desInterleaved_UDim2,
        }),
    }),

    Accumulated = table.freeze({
        F32 = table.freeze({
            ser = serAccumulated_F32,
            des = desAccumulated_F32,
        }),

        I32 = table.freeze({
            ser = serAccumulated_I32,
            des = desAccumulated_I32,
        }),
    }),
})