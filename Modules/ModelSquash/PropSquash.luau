-- Derived from:
-- https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_dom_lua/src/EncodedValue.lua

--!strict
local Shared = script.Parent.Parent

local Squash = require(Shared.Squash)
local ArraySquash = require(Shared.ArraySquash)

local Accumulated = ArraySquash.Accumulated
local Interleaved = ArraySquash.Interleaved

local AccI32 = Accumulated.I32

type Cursor = Squash.Cursor
type SerDes<T...> = Squash.SerDes<T...>

local Singulars: {
    [string]: SerDes<any>,
}

local Arrays: {
    [string]: SerDes<{ any }>,
}

local compress: (cursor: Cursor, propertyType: string, value: any) -> boolean
local decompress: (cursor: Cursor, ty: string) -> (boolean, any)

local compressArray: (cursor: Cursor, propType: string, values: {any}) -> boolean
local decompressArray: (cursor: Cursor, propType: string) -> (boolean, any)

local U8 = Squash.u8()
local U16 = Squash.u16()
local U32 = Squash.u32()
local F32 = Squash.f32()
local VLQ = Squash.vlq()
local BOOL = Squash.boolean()
local STRING = Squash.string()
local CFRAME = Squash.CFrame(F32)

local TypeEnum = table.freeze({
    Attributes = 1,
    Axes = 2,
    Bool = 3,
    BrickColor = 4,
    CFrame = 5,
    Color3 = 6,
    Color3uint8 = 7,
    ColorSequence = 8,
    Content = 9,
    ContentId = 10,
    EnumItem = 11,
    Faces = 12,
    Float32 = 13,
    Float64 = 14,
    Font = 15,
    Int32 = 16,
    Int64 = 17,
    NumberSequence = 18,
    PhysicalProperties = 19,
    Ray = 20,
    Rect = 21,
    Region3int16 = 22,
    String = 23,
    UDim = 24,
    UDim2 = 25,
    Tags = 26,
    Vector2 = 27,
    NumberRange = 28,
    Vector3 = 29,
    Vector3int16 = 30,
    OptionalCFrame = 31,
    Ref = 32,
})

local TypeIds = {} :: {
    [number]: string
}

for name, id in pairs(TypeEnum) do
    TypeIds[id] = name
end

--- Disambiguates Roblox/Luau types
--- into the type names used here.
local TypeAliases = table.freeze({
    -- Luau types
    boolean = "Bool",
    number = "Float64",
    string = "String",

    -- Roblox Engine Types
    bool = "Bool",
    int = "Int32",
    int64 = "Int64",
    float = "Float32",
    double = "Float64",

    OptionalCoordinateFrame = "OptionalCFrame",
    CoordinateFrame = "CFrame",

    RefType = "Ref",
    Rect2D = "Rect",
    Enum = "EnumItem",
})

Singulars = {
    Attributes = {
        des = function(cursor)
            local output = {}
            local numAttributes = VLQ.des(cursor)

            for i = 1, numAttributes do
                local key = STRING.des(cursor)
                local valueTypeId = U16.des(cursor)

                local valueType = TypeIds[valueTypeId]
                local ok, result = decompress(cursor, valueType)

                if ok then
                    output[key] = result
                else
                    local warning = ("ModelSquash - Could not decode attribute value of type %q: %s"):format(
                        typeof(result),
                        tostring(result)
                    )

                    warn(warning)
                end
            end

            return output
        end,

        ser = function (cursor, roblox)
            local numAttributes = 0

            for key in roblox do
                if key ~= "__msref" then
                    numAttributes += 1
                end
            end

            for key, value in roblox do
                if key == "__msref" then
                    continue
                end

                local valueType = typeof(value)
                valueType = SystemTypes[valueType] or valueType 

                if TypeEnum[valueType] then
                    compress(cursor, valueType, value)
                    U16.ser(cursor, TypeEnum[valueType])
                    STRING.ser(cursor, key)
                end
            end

            VLQ.ser(cursor, numAttributes)
        end,
    },

    Axes = Squash.Axes(),
    BrickColor = Squash.BrickColor(),

    Bool = BOOL,
    CFrame = CFRAME,
    Color3 = Squash.Color3(),

    Color3uint8 = {
        des = function (cursor)
            local r = U8.des(cursor)
            local g = U8.des(cursor)
            local b = U8.des(cursor)

            return Color3.fromRGB(r, g, b)
        end,

        ser = function (cursor, roblox: Color3)
            local r = math.clamp(math.round(roblox.R * 255), 0, 255)
            local g = math.clamp(math.round(roblox.G * 255), 0, 255)
            local b = math.clamp(math.round(roblox.B * 255), 0, 255)

            U8.ser(cursor, b)
            U8.ser(cursor, g)
            U8.ser(cursor, r)
        end,
    },

    ColorSequence = Squash.ColorSequence(),

    Content = {
        des = function (cursor)
            local sourceType = Squash.EnumItem(Enum.ContentSourceType).des(cursor)

            if sourceType == Enum.ContentSourceType.Uri then
                local uri = STRING.des(cursor)
                return Content.fromUri(uri)
            elseif sourceType ~= Enum.ContentSourceType.None then
                warn("Deserializing Content of SourceType", sourceType.Name, "is not supported!")
            end

            return Content.none
        end,

        ser = function (cursor, roblox: Content)
            local sourceType = roblox.SourceType

            if sourceType == Enum.ContentSourceType.Uri then
                STRING.ser(cursor, roblox.Uri or "")
            elseif sourceType ~= Enum.ContentSourceType.None then
                warn("Serializing Content of SourceType", tostring(sourceType), "is not supported!")
            end

            Squash.EnumItem(Enum.ContentSourceType).ser(cursor, sourceType)
        end,
    },

    ContentId = STRING,

    EnumItem = {
        des = function (cursor)
            local enumType = STRING.des(cursor)
            local value = U32.des(cursor)

            local enum: Enum = (Enum :: any)[enumType]
            return enum:FromValue(value)
        end,

        ser = function (cursor, roblox: EnumItem)
            U32.ser(cursor, roblox.Value)
            STRING.ser(cursor, tostring(roblox.EnumType))
        end,
    },

    Faces = Squash.Faces(),
    Float32 = F32,

    Float64 = Squash.f64(),
    Font = Squash.Font(),

    Int32 = Squash.i32(),
    Int64 = Squash.i64(),

    NumberSequence = Squash.NumberSequence(F32),
    NumberRange = Squash.NumberRange(F32),

    OptionalCFrame = {
        des = function (cursor): CFrame?
            local isPresent = BOOL.des(cursor)

            if isPresent then
                return CFRAME.des(cursor)
            end

            return nil
        end,

        ser = function (cursor, roblox)
            if roblox ~= nil then
                CFRAME.ser(cursor, roblox)
            end

            BOOL.ser(cursor, roblox ~= nil)
        end,
    },

    PhysicalProperties = Squash.opt(Squash.PhysicalProperties()),
    Ray = Squash.Ray(F32),
    Rect = Squash.Rect(F32),

    Region3int16 = Squash.Region3int16(),
    String = STRING,
    UDim = Squash.UDim(F32),
    UDim2 = Squash.UDim2(F32),

    Ref = {
        des = VLQ.des,

        ser = function (cursor, roblox: Instance?)
            if roblox then
                local refId = roblox:GetAttribute("__msref")

                if type(refId) == "number" then
                    VLQ.ser(cursor, refId)
                    return
                end
            end

            VLQ.ser(cursor, 0)
        end,
    },

    Tags = {
        ser = function (cursor, roblox)
            for i = #roblox, 1, -1 do
                local tag = roblox[i]
                STRING.ser(cursor, tag)
            end

            VLQ.ser(cursor, #roblox)
        end,

        des = function (cursor)
            local numTags = VLQ.des(cursor)
            local tags = table.create(numTags, "")

            for i = 1, numTags do
                local tag = STRING.des(cursor)
                tags[i] = tag
            end

            return tags
        end,
    },

    Vector2 = Squash.Vector2(F32),
    Vector3 = Squash.Vector3(F32),

    Vector3int16 = Squash.Vector3int16(),
}

Arrays = {
    Bool = Squash.array(BOOL),

    BrickColor = Interleaved.BrickColor,
    Color3 = Interleaved.Color3,

    Float32 = Interleaved.F32,
    Int32 = Interleaved.I32,

    EnumItem = {
        ser = function (cursor, roblox: {EnumItem})
            local values = {}
            
            for i = 1, #roblox do
                local enumItem = roblox[i]
                values[i] = enumItem.Value
            end

            local name = tostring(roblox[1].EnumType)
            Interleaved.I32.ser(cursor, values)
            STRING.ser(cursor, name)
        end,

        des = function (cursor)
            local name = STRING.des(cursor)
            local enumType: Enum = (Enum :: any)[name]
            
            local values = Interleaved.I32.des(cursor)
            local items = {}
            
            for i = 1, #values do
                local value = values[i]
                items[i] = enumType:FromValue(value)
            end

            return items
        end,
    },

    UDim = Interleaved.UDim,
    UDim2 = Interleaved.UDim2,
    Rect = Interleaved.Rect,

    Ref = {
        des = AccI32.des,

        ser = function (cursor, roblox: {Instance?})
            local objectIds = {}

            for i = 1, #roblox do
                local inst = roblox[i]
                local id = 0

                if inst then
                    local refId = inst:GetAttribute("__msref")

                    if type(refId) == "number" then
                        id = refId
                    end
                end

                objectIds[i] = id
            end

            AccI32.ser(cursor, objectIds)
        end,
    },

    String = {
        ser = function (cursor, roblox: {string})
            local ids = {}
            local strings = {}
            local stringMap = {}

            for i, str in ipairs(roblox) do
                if stringMap[str] == nil then
                    local id = #strings + 1
                    strings[id] = str
                    stringMap[str] = id
                end

                local id = stringMap[str]
                ids[i] = id
            end

            for i = #ids, 1, -1 do
                local id = ids[i]
                VLQ.ser(cursor, id)
            end

            VLQ.ser(cursor, #ids)

            for i = #strings, 1, -1 do
                local str = strings[i]
                STRING.ser(cursor, str)
            end
            
            VLQ.ser(cursor, #strings)
        end,

        des = function (cursor)
            local numStrings = VLQ.des(cursor)
            local strings = table.create(numStrings, "")

            for i = 1, numStrings do
                local str = STRING.des(cursor)
                strings[i] = str
            end

            local numIds = VLQ.des(cursor)
            local allStrings = table.create(numIds, "")

            for i = 1, numIds do
                local id = VLQ.des(cursor)
                allStrings[i] = strings[id]
            end

            return allStrings
        end,
    },

    Vector2 = Interleaved.Vector2,
    Vector3 = Interleaved.Vector3,
}

decompress = function (cursor: Cursor, ty: string)
    local singular = Singulars[ty]

    if singular then
        return true, singular.des(cursor)
    end

    return false, ("ModelSquash - Missing decoder for property type %q"):format(ty)
end

decompressArray = function (cursor, ty)
    local arrayImpl = Arrays[ty]

    if arrayImpl then
        return true, arrayImpl.des(cursor)
    end

    local singular = Singulars[ty]

    if singular ~= nil then
        local array = Squash.array(singular)
        return true, array.des(cursor)
    end

    return false, "Couldn't decode values: " .. tostring(ty)
end

compress = function (cursor: Cursor, propertyType: string, value: any)
    local singular = Singulars[propertyType]

    if singular then
        singular.ser(cursor, value)
        return true
    end

    return false, ("ModelSquash - Missing encoder for property type %q"):format(propertyType)
end

compressArray = function (cursor, propertyType, rbxValues)
    assert(propertyType ~= nil, "ModelSquash - Property type descriptor is required")
    local isDefined = Singulars[propertyType] ~= nil or Arrays[propertyType] ~= nil

    if not isDefined then
        local alias = TypeAliases[propertyType]
        propertyType = alias or propertyType
    end

    local arrayImpl = Arrays[propertyType]

    if arrayImpl then
        arrayImpl.ser(cursor, rbxValues)
        return true
    end

    local singular = Singulars[propertyType]

    if singular then
        local array = Squash.array(singular)
        array.ser(cursor, rbxValues)
        return true
    end

    return false, ("ModelSquash - Missing encoder for property type %q"):format(propertyType)
end

return table.freeze({
    TypeAliases = TypeAliases,
    TypeEnum = TypeEnum,
    TypeIds = TypeIds,

    DecompressArray = decompressArray,
    CompressArray = compressArray,

    Decompress = decompress,
    Compress = compress,
})