-- Derived from:
-- https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_dom_lua/src/EncodedValue.lua

--!strict
local Shared = script.Parent.Parent
local Squash = require(Shared.Squash)

type Cursor = Squash.Cursor

local Types: {
    [string]: {
        des: (Cursor) -> any,
        ser: (Cursor, any) -> (),
    }
}

local compress: (cursor: Cursor, propType: string, value: any) -> boolean
local decompress: (cursor: Cursor, propType: string) -> (boolean, any)

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
})

local TypeIds = {} :: {
    [number]: string
}

for name, id in pairs(TypeEnum) do
    TypeIds[id] = name
end

--- Disambiguates Roblox/Luau types
--- into the type names used here.
local SystemTypes = table.freeze({
    int = "Int32",
    int64 = "Int64",
    float = "Float32",
    double = "Float64",
    string = "String",
    number = "Float64",
    boolean = "Bool",
    bool = "Bool",
})

Types = {
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
    Bool = Squash.boolean(),
    BrickColor = Squash.BrickColor(),

    CFrame = CFRAME,
    Color3 = Squash.Color3(),

    Color3uint8 = {
        des = function (cursor)
            local r = U8.des(cursor)
            local g = U8.des(cursor)
            local b = U8.des(cursor)

            return Color3.fromRGB(r, g, b)
        end,

        ser = function (cursor, roblox)
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

    Region3int16 = Squash.Region3int16(),
    String = STRING,
    UDim = Squash.UDim(F32),
    UDim2 = Squash.UDim2(F32),

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

decompress = function (cursor, ty)
    local typeImpl = Types[ty]

    if typeImpl == nil then
        return false, "Couldn't decode value " .. tostring(ty)
    end

    return true, typeImpl.des(cursor)
end

compress = function (cursor, propertyType, rbxValue)
    assert(propertyType ~= nil, "ModelSquash - Property type descriptor is required")
    local typeImpl = Types[propertyType]
    
    if typeImpl == nil then
        local systemType = SystemTypes[propertyType]
        typeImpl = Types[systemType]
        
        if typeImpl == nil then
            return false, ("ModelSquash - Missing encoder for property type %q"):format(propertyType)
        else
            propertyType = systemType
        end
    end

    typeImpl.ser(cursor, rbxValue)
    return true
end

return table.freeze({
    SystemTypes = SystemTypes,
    Decompress = decompress,
    Compress = compress,
    
    TypeEnum = TypeEnum,
    TypeIds = TypeIds,
})