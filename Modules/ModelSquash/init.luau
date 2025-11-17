local Shared = script.Parent
local Squash = require(Shared.Squash)

local ApiDump = require(Shared.ApiDump)
local PropSquash = require(script.PropSquash)
local ArraySquash = require(Shared.ArraySquash)

local Accumulated = ArraySquash.Accumulated
local AccI32 = Accumulated.I32

local STRING = Squash.string()
local VLQ = Squash.vlq()

type Cursor = Squash.Cursor
type ApiDump = ApiDump.ApiDump
type TypeCategory = ApiDump.TypeCategory

type INST = {
    Index: number,
    ObjectIds: { number },
}

type PROP = {
    Name: string,
    ClassIndex: number,
    TypeIndex: number,
    Values: { any },
}

local propSetters = {} :: {
    [string]: (Instance, any) -> ()
}

propSetters.Tags = function (inst, tags)
    for i, tag in tags do
        inst:AddTag(tag)
    end
end

propSetters.Attributes = function (inst, attributes)
    for name, value in attributes do
        inst:SetAttribute(name, value)
    end
end

local function serialize(root: Instance): buffer
    local cursor = Squash.cursor()
    local apiDumpGet = ApiDump.Get()

    if not apiDumpGet.Success then
        error("ModelSquash - API Dump source not set or failed to load!")
    end

    local instances: { Instance } = root:GetDescendants()
    table.insert(instances, 1, root) -- Include the root instance

    -- Collect classes and assign ref IDs
    local refMap = {}
    local classNames = {}

    local classMap = {} :: {
        [string]: INST
    }

    for i, inst in instances do
        local className = inst.ClassName

        local classInfo = classMap[className] or (function ()
            local index = #classNames + 1
            classNames[index] = className

            classMap[className] = {
                Index = index,
                ObjectIds = {},
            }

            return classMap[className]
        end)()

        refMap[inst] = i
        inst:SetAttribute("__msref", i)

        table.insert(classInfo.ObjectIds, i)
    end

    -- Collect properties
    local apiDump = apiDumpGet.ApiDump
    local props = {}

    for i, className in ipairs(classNames) do
        local members = ApiDump.GetMembersOfClass(apiDump, className)
        local defaults = ApiDump.GetDefaultValues(apiDump, className)

        if not defaults then
            continue
        end

        local class = classMap[className]
        local objectIds = class.ObjectIds

        for name, default in defaults do
            local member = members[name]

            if member.MemberType ~= "Property" then
                continue
            end

            local tags = ApiDump.GetTags(member)

            if tags.ReadOnly or tags.Deprecated or tags.NotReplicated then
                continue
            end

            if member.Security.Write ~= "None" then
                continue
            end

            local valueType = member.ValueType
            local category = valueType.Category

            local typeName = 
                if category == "Class" then
                    "Ref"
                elseif category == "Enum" then
                    "EnumItem"
                else
                    valueType.Name

            local typeIndex = PropSquash.TypeEnum[typeName]

            if typeIndex == nil then
                local systemType = PropSquash.SystemTypes[typeName]

                if systemType then
                    typeName = systemType
                    typeIndex = PropSquash.TypeEnum[typeName]
                else
                    continue
                end
            end

            local prop = {
                Name = name,
                ClassIndex = i,
                TypeIndex = typeIndex,
                Values = {},
            }

            for i, objectId in ipairs(objectIds) do
                local instance = instances[objectId]

                local success, robloxValue = pcall(function ()
                    return (instance :: any)[name]
                end)

                if not success then
                    warn("ModelSquash - Could not get property value:", className, name, robloxValue)
                    robloxValue = default
                end

                table.insert(prop.Values, robloxValue)
            end

            table.insert(props, prop)
        end

        -- Manually collect tags and attributes
        local attributeMap = {}
        local tagMap = {}

        for i, objectId in objectIds do
            local object = instances[objectId]
            local attributes = object:GetAttributes()
            local tags = object:GetTags()

            if #tags > 0 then
                tagMap[objectId] = tags
            end

            if next(attributes) then
                attributeMap[objectId] = attributes
            end
        end

        local collections = {
            Tags = tagMap,
            Attributes = attributeMap
        }

        for key: string, map: any in pairs(collections) do
            if not next(map) then
                continue
            end

            local prop = {
                Name = key,
                ClassIndex = i,
                TypeIndex = PropSquash.TypeEnum[key],
                Values = {},
            }

            for i, objectId in ipairs(class.ObjectIds) do
                prop.Values[i] = map[objectId] or {}
            end

            table.insert(props, prop)
        end
    end

    -- ~~~~~~~~~~~~~~~~~~  BEGIN SERIALIZATION  ~~~~~~~~~~~~~~~~~~
    -- (Squash is weird and requires us to write things in reverse)

    --------------------------
    -- 4: Instance Hierarchy
    --------------------------

    local parentIds = {}

    for i, inst in instances do
        local inst = instances[i]
        local parent = inst.Parent
        parentIds[i] = parent and refMap[parent] or 0
    end

    AccI32.ser(cursor, parentIds)

    --------------------------
    -- 3: Properties
    --------------------------

    for i = #props, 1, -1 do
        local prop = props[i]
        local values = prop.Values
        local typeName = PropSquash.TypeIds[prop.TypeIndex]

        -- 3e: Property Values
        PropSquash.CompressArray(cursor, typeName, values)

        -- 3d: Property Type
        VLQ.ser(cursor, prop.TypeIndex)  

        -- 3c: Class Index
        VLQ.ser(cursor, prop.ClassIndex)

        -- 3b: Property Name
        STRING.ser(cursor, prop.Name)
    end

    -- 3a: Property Count
    VLQ.ser(cursor, #props)

    --------------------------
    -- 2: Class Names
    --------------------------

    for i = #classNames, 1, -1 do
        local className = classNames[i]
        local class = classMap[className]

        -- 2d: Object Ids
        AccI32.ser(cursor, class.ObjectIds)

        -- 2c: Class Index
        VLQ.ser(cursor, class.Index)

        -- 2b: Class Name
        STRING.ser(cursor, className)
    end

    -- 2a: Class Count
    VLQ.ser(cursor, #classNames)

    --------------------------
    -- 1: Header
    --------------------------

    -- 1b: Version
    VLQ.ser(cursor, 1)

    -- 1a: Magic
    STRING.ser(cursor, "RBXMSQSH")

    -- ~~~~~~~~ END SERIALIZATION ~~~~~~~~

    for i, object in instances do
        object:SetAttribute("__msref", nil)
    end

    return Squash.tobuffer(cursor)
end

local function deserialize(buf: buffer): Instance
    local cursor = Squash.frombuffer(buf)

    local magic = STRING.des(cursor)
    assert(magic == "RBXMSQSH", "ModelSquash - Provided buffer is not a valid ModelSquash buffer!")

    local version = VLQ.des(cursor)

    if version ~= 1 then
        error("ModelSquash - Unsupported format version! (Expected 1)")
    end

    -- Deserialize classes
    local objects = {}
    local classMap = {}
    local numClasses = VLQ.des(cursor)

    for i = 1, numClasses do
        local className = STRING.des(cursor)
        local classIndex = VLQ.des(cursor)
        local objIds = AccI32.des(cursor)

        for i, id in objIds do
            objects[id] = Instance.new(className)
        end

        classMap[classIndex] = {
            Name = className,
            ObjectIds = objIds,
        }
    end

    -- Deserialize properties
    local numProps = VLQ.des(cursor)

    for i = 1, numProps do
        local propName = STRING.des(cursor)
        local classIndex = VLQ.des(cursor)
        local typeIndex = VLQ.des(cursor)

        local typeName = PropSquash.TypeIds[typeIndex]
        local classInfo = classMap[classIndex]
        local objectIds = classInfo.ObjectIds

        local setter = propSetters[propName]
        local ok, result = PropSquash.DecompressArray(cursor, typeName)
        local values = ok and result or {}

        for j, objectId in ipairs(objectIds) do
            local inst = objects[objectId]
            local value = values[j]

            if typeName == "Ref" then
                value = objects[value]
            end

            if setter then
                setter(inst, value)
            else
                local success = pcall(function ()
                    (inst :: any)[propName] = value
                end)

                if not success then
                    warn("ModelSquash - Could not set property value:", classInfo.Name, propName, value)
                end
            end
        end
    end

    -- Deserialize hierarchy
    local parentIds = AccI32.des(cursor)

    for i, object in ipairs(objects) do
        local parentRef = parentIds[i]

        if parentRef > 0 then
            object.Parent = objects[parentRef]
        end
    end

    -- Return the root object
    return objects[1]
end

return table.freeze({
    ser = serialize,
    des = deserialize,

    Serialize = serialize,
    Deserialize = deserialize,

    SetApiDumpCacheSource = ApiDump.SetCacheSource,
})