--!native
--!strict

--- CrunchTable is a shallow typechecked wrapper around Squash that allows you to define 
--- a data layout without needing to worry about the underlying serdes functions. It also
--- provides a more user-friendly API for compressing and decompressing data.

local CrunchTable = {}
CrunchTable.__index = CrunchTable

local Shared = script.Parent
local Squash = require(Shared.Squash)

type Cursor = Squash.Cursor
type SerDes<T... = ...any> = Squash.SerDes<T...>

local I8 = Squash.i8()
local U8 = Squash.u8()
local I16 = Squash.i16()
local U16 = Squash.u16()
local I32 = Squash.i32()
local U32 = Squash.u32()
local F32 = Squash.f32()
local F64 = Squash.f64()
local VLQ = Squash.vlq()
local STR = Squash.string()
local CF = Squash.CFrame(F32)
local COLOR3 = Squash.Color3()
local VEC2 = Squash.Vector2(F32)
local VEC3 = Squash.Vector3(F32)
local BOOL = Squash.boolean() :: SerDes<boolean>

export type CrunchType = 
    | "u8"
    | "i8"
    | "u16"
    | "i16"
    | "u32"
    | "i32"
    | "f32"
    | "f64"
    | "vlq"
    | "boolean"
    | "string"
    | "Vector2"
    | "Vector3"
    | "CFrame"
    | "Color3"

type TypeMap = {
    u8: number,
    i8: number,
    u16: number,
    i16: number,
    u32: number,
    i32: number,
    f32: number,
    f64: number,
    vlq: number,
    CFrame: CFrame,
    Color3: Color3,
    string: string,
    boolean: boolean,
    Vector2: Vector2,
    Vector3: Vector3,
}

local writers: { [string]: SerDes } = {
    u8 = U8,
    i8 = I8,
    u16 = U16,
    i16 = I16,
    u32 = U32,
    i32 = I32,
    f32 = F32,
    f64 = F64,
    vlq = VLQ,
    CFrame = CF,
    string = STR,
    boolean = BOOL,
    Vector2 = VEC2,
    Vector3 = VEC3,
    Color3 = COLOR3,
}

type function Append(serialType: type, keyType: type, tagType: type)
    local serial = serialType:value()
    assert(type(serial) == "string", "Serial must be a string")

    local key = keyType:value()
    assert(type(key) == "string", "Key must be a string")
    assert(key:match("^[%w_]+$"), "Key can only contain alphanumeric characters and underscores")
    
    local tag = tagType:value()
    assert(type(tag) == "string", "Tag must be a string")
    assert(tag:match("^[%w_]+$"), "Tag can only contain alphanumeric characters and underscores")

    local current = {}
    
    for _, pair in serial:split("|") do
        local key, tag = unpack(pair:split("="))

        if key and tag then
            current[key] = tag
        end
    end

    if current[key] then
        print(`Key '{key}' was added to the layout more than once!`)
    end

    if #serial > 0 then
        serial ..= "|"
    end

    serial ..= `{key}={tag}`
    return types.singleton(serial)
end

type function Layout(serialType: type, typeMap: type): type
    local lookup = {}

    for keyType, rw in typeMap:properties() do
        local key = keyType:value()
        local read = rw.read

        assert(type(key) == "string", "Key must be a string")
        assert(key:match("^[%w_]+$"), "Key can only contain alphanumeric characters and underscores")
        
        if read then
            lookup[key] = read
        end
    end

    local serial = serialType:value()
    assert(type(serial) == "string", "Layout must be a string")
    
    local layout = {} :: {
        [type]: type
    }

    for _, pair in serial:split("|") do
        local key, tag = unpack(pair:split("="))

        if key and tag then
            local rawType = lookup[tag]

            if rawType then
                layout[types.singleton(key)] = rawType
            end
        end
    end

    return types.newtable(layout)
end

type function PackedTable(dataType: type, layoutType: type): type
    local ignoreMap = {}

    for keyType, rw in layoutType:properties() do
        local key = keyType:value()
        
        if type(key) == "string" then
            ignoreMap[key] = true
        end
    end

    local result = {} :: {
        [type]: {
            read: type?,
            write: type?,
        }
    }
    
    if dataType:is("table") then
        for keyType, rw in dataType:properties() do
            local key = keyType:value()

            if type(key) == "string" then
                if not ignoreMap[key] then
                    result[keyType] = rw
                end
            end
        end
    end

    local cursor = types.newtable(nil, {
        index = types.number,
        readresult = types.buffer,
        writeresult = types.buffer,
    })

    result[types.singleton("_b")] = {
        read = cursor,
        write = cursor,
    }

    return types.newtable(result)
end

type function UnpackedTable(dataType: type, layoutType: type): type
    local result = {} :: {
        [type]: {
            read: type?,
            write: type?,
        }
    }

    if dataType:is("table") then
        for keyType, rw in dataType:properties() do
            local key = keyType:value()

            if key == "_b" then
                continue
            end

            result[keyType] = rw
        end
    end

    for keyType, rw in layoutType:properties() do
        result[keyType] = rw
    end

    return types.newtable(result)
end

type CrunchTable<Serial = ""> = setmetatable<{
    _serial: Serial,
}, typeof(CrunchTable)>

type BinaryTable<Partial> = Partial & {
    _b: Cursor,
}

type _Layout<Serial = ""> = Layout<Serial, TypeMap>
export type Class = CrunchTable<"">

local function new(): Class
    return setmetatable({
        _serial = "",
    }, CrunchTable)
end

function CrunchTable.Field<Serial, Key, Type, Optional>(
    self: CrunchTable<Serial>,
    key: Key | "",
    type: CrunchType & (Type | "")
): CrunchTable<Append<Serial, Key, Type>>
    local serial = tostring(self._serial)
    assert(string.match(key, "^[%w_]+$"), "Key can only contain alphanumeric characters and underscores")
    assert(string.match(type, "^[%w_]+$"), "Type can only contain alphanumeric characters and underscores")

    if #serial > 0 then
        serial ..= "|"
    end
    
    serial ..= `{key}={type}`
    self._serial = serial

    return self
end

function CrunchTable.Compress<Serial, Data>(
    self: CrunchTable<Serial>,
    data: Data & _Layout<Serial>,
    cursor: Cursor?
): PackedTable<Data, _Layout<Serial>>
    local serial = tostring(self._serial)
    local rawData = data :: any

    local cursor = cursor or Squash.cursor()
    rawData._b = cursor

    for i, field in serial:split("|") do
        local key, tag = unpack(field:split("="))

        if key and tag then
            local value = rawData[key]
            local writer = writers[tag]

            if writer then
                writer.ser(cursor, value)
                rawData[key] = nil
            end
        end
    end

    return rawData
end

function CrunchTable.Decompress<Serial, Partial>(
    self: CrunchTable<Serial>,
    data: BinaryTable<Partial>
): UnpackedTable<Partial, _Layout<Serial>>
    local serial = tostring(self._serial)
    local rawData = data :: any

    local cursor: Cursor = rawData._b
    rawData._b = nil

    for i, field in serial:split("|") do
        local key, tag = unpack(field:split("="))

        if key and tag then
            local reader = writers[tag]

            if reader then
                rawData[key] = reader.des(cursor)
            end
        end
    end

    return rawData
end

return table.freeze({
    new = new,
})
