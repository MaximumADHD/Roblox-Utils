--!native
--!strict

--- CrunchTable is a shallow typechecked wrapper around Squash that allows you to define 
--- a data layout without needing to worry about the underlying serdes functions. It also
--- provides a more user-friendly API for compressing and decompressing data. Squash is
--- better suited for more complex use cases.

local CrunchTable = {}
CrunchTable.__index = CrunchTable

local Shared = script.Parent
local Squash = require(Shared.Squash)

export type Cursor = Squash.Cursor
type SerDes<T... = ...any> = Squash.SerDes<T...>

local F32 = Squash.f32()
local BOOL = Squash.boolean() :: SerDes<boolean>

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
    NumberRange: NumberRange,
    None: nil,
}

local None: SerDes<any> = {
    ser = function (cursor: Cursor, value: any)
        return
    end,

    des = function (cursor: Cursor)
        return nil
    end,
}

local writers: { [string]: SerDes<any> } = {
    u8 = Squash.u8(),
    i8 = Squash.i8(),
    u16 = Squash.u16(),
    i16 = Squash.i16(),
    u32 = Squash.u32(),
    i32 = Squash.i32(),
    f64 = Squash.f64(),
    vlq = Squash.vlq(),

    string = Squash.string(),
    Color3 = Squash.Color3(),
    CFrame = Squash.CFrame(F32),
    Vector2 = Squash.Vector2(F32),
    Vector3 = Squash.Vector3(F32),
    NumberRange = Squash.NumberRange(F32),

    f32 = F32,
    None = None,
    boolean = BOOL,
}

local defaults: { [string]: any } = {
    u8 = 0,
    i8 = 0,
    u16 = 0,
    i16 = 0,
    u32 = 0,
    i32 = 0,
    f32 = 0,
    f64 = 0,
    vlq = 0,

    string = "",
    Color3 = Color3.new(),
    CFrame = CFrame.new(),
    Vector2 = Vector2.new(),
    Vector3 = Vector3.new(),
    NumberRange = NumberRange.new(0),

    None = nil,
    boolean = false,
}

local recordCache = {} :: {
    [any]: SerDes<any>
}

export type CrunchType = keyof<TypeMap>

type function Append(schemaType: type, keyType: type, tagType: type)
    local schema = schemaType:value()
    assert(type(schema) == "string", "Schema must be a string")

    local key = keyType:value()
    assert(type(key) == "string", "Key must be a string")
    assert(key:match("^[%w_]+%??$"), "Key can only contain alphanumeric characters and underscores")
    
    local tag = tagType:value()
    assert(type(tag) == "string", "Tag must be a string")
    assert(tag:match("^[%w_]+$"), "Tag can only contain alphanumeric characters and underscores")

    local current = {}
    
    for _, pair in schema:split("|") do
        local key, tag = unpack(pair:split("="))

        if key and tag then
            current[key] = tag
        end
    end

    if current[key] then
        print(`Key '{key}' was added to the layout more than once!`)
    end

    if #schema > 0 then
        schema ..= "|"
    end

    schema ..= `{key}={tag}`
    return types.singleton(schema)
end

type function _Layout(schemaType: type, typeMap: type): type
    if not schemaType:is("singleton") then
        return types.newtable({})
    end

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

    local schema = schemaType:value()
    assert(type(schema) == "string", "Layout must be a string")
    
    local layout = {} :: {
        [type]: type
    }

    for _, pair in schema:split("|") do
        local key, tag = unpack(pair:split("="))

        if key and tag then
            local optional = false

            if key:sub(-1) == "?" then
                optional = true
                key = key:sub(1, -2)
            end

            local rawType = lookup[tag]

            if rawType then
                if optional then
                    rawType = types.optional(rawType)
                end

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

type CrunchTable<Schema = ""> = setmetatable<{
    Schema: Schema,
}, typeof(CrunchTable)>

export type BinaryTable<Partial = any> = Partial & {
    _b: Cursor,
}

export type LazyTable = {
    [any]: any
}

type LayoutImpl<Schema = ""> = _Layout<Schema, TypeMap>
export type Layout<Schema = ""> = LayoutImpl<Schema>
export type Class = CrunchTable<"">

local function new(): Class
    return setmetatable({
        Schema = "",
    }, CrunchTable)
end

function CrunchTable.Field<Schema, Key, Type, Optional>(
    self: CrunchTable<Schema>,
    key: Key | "",
    type: CrunchType & (Type | "")
): CrunchTable<Append<Schema, Key, Type>>
    local serial = tostring(self.Schema)
    assert(string.match(key, "^[%w_]+%??$"), "Key can only contain alphanumeric characters and underscores")
    assert(string.match(type, "^[%w_]+$"), "Type can only contain alphanumeric characters and underscores")

    if #serial > 0 then
        serial ..= "|"
    end

    serial ..= `{key}={type}`
    self.Schema = serial

    return self
end

type SchemaField = {
    Key: string,
    Type: string,
    Optional: boolean,
}

local function parseSchema(rawSchema: string): { SchemaField }
    local fields = {} :: { SchemaField }

    for _, field in rawSchema:split("|") do
        local rawKey, typeId = unpack(field:split("="))

        if rawKey and typeId then
            local optional = false
            local key = rawKey

            if key:sub(-1) == "?" then
                optional = true
                key = key:sub(1, -2)
            end

            table.insert(fields, {
                Key = key,
                Type = typeId,
                Optional = optional,
            })
        end
    end

    return fields
end

local function getRecord<Schema>(schema: Schema): SerDes<Layout<Schema>>
    if recordCache[schema] then
        return recordCache[schema]
    end
    
    local fields: any = {}

    for i, field in parseSchema(schema) do
        local key = field.Key
        local typeId = field.Type
        local writer = writers[typeId]

        if writer then
            if field.Optional then
                writer = Squash.opt(writer)
            end

            fields[key] = writer
        end
    end

    local record = Squash.record(fields)
    recordCache[schema] = record

    return record
end

local function compressRaw<Schema>(
    schema: Schema,
    data: Layout<Schema>,
    cursor: Cursor?
): Cursor
    local cursor = cursor or Squash.cursor()

    local record = getRecord(schema)
    record.ser(cursor, data)

    return cursor
end

local function compress<Schema, Data>(
    schema: Schema,
    data: Data & Layout<Schema>
): PackedTable<Data, Layout<Schema>>
    local copy = table.clone(data)
    local rawData = copy :: any

    local rawSchema = tostring(schema)
    local fields = parseSchema(rawSchema)

    local cursor = Squash.cursor()
    rawData._b = cursor

    for i, field in fields do
        local key = field.Key
        rawData[key] = nil
    end

    compressRaw(schema, data, cursor)
    return rawData
end

local function decompressRaw<Schema>(
    schema: Schema,
    cursor: Cursor
): Layout<Schema>
    local record = getRecord(schema)
    return record.des(cursor)
end

local function decompress<Schema, Partial>(
    schema: (Schema | ""),
    data: BinaryTable<Partial>
): UnpackedTable<Partial, Layout<Schema>>
    local copy = table.clone(data) :: any
    local cursor: Cursor = copy._b

    local layout = decompressRaw(schema, cursor)
    copy._b = nil

    for key, value in pairs(layout) do
        copy[key] = value
    end

    return copy
end

local function describe<Schema>(schema: (Schema | "")): Layout<Schema>
    local dummy: any = {}
    
    for i, field in tostring(schema):split("|") do
        local key, tag = unpack(field:split("="))

        if key and tag then
            if key:sub(-1) == "?" then
                key = key:sub(1, -2)
            end

            dummy[key] = defaults[tag]
        end
    end

    return dummy
end

local function getKeys<Schema>(schema: (Schema | "")): { keyof<Layout<Schema>> }
    local keys: any = {}

    for i, field in tostring(schema):split("|") do
        local key, tag = unpack(field:split("="))

        if key and tag then
            if key:sub(-1) == "?" then
                key = key:sub(1, -2)
            end

            table.insert(keys, key)
        end
    end

    return keys
end

return table.freeze({
    new = new,

    GetKeys = getKeys,
    Describe = describe,
    ToSerDes = getRecord,

    Compress = compress,
    Decompress = decompress,

    CompressRaw = compressRaw,
    DecompressRaw = decompressRaw,

    CursorToBuffer = Squash.tobuffer,
    CursorFromBuffer = Squash.frombuffer,
})