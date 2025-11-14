local Shared = script.Parent
local Squash = require(Shared.Squash)

local ApiDump = require(Shared.ApiDump)
local PropSquash = require(script.PropSquash)

local STRING = Squash.string()
local VLQ = Squash.vlq()

type Cursor = Squash.Cursor
type ApiDump = ApiDump.ApiDump
type TypeCategory = ApiDump.TypeCategory

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

local function serAccumulated(cursor: Cursor, arr: {number})
    local lastNum = 0
    local diffs = table.create(#arr, 0)

    for i = 1, #arr do
        local diff = arr[i] - lastNum
        lastNum = arr[i]
        diffs[i] = diff
    end

    for i = #arr, 1, -1 do
        VLQ.ser(cursor, diffs[i])
    end

    VLQ.ser(cursor, #arr)
end

local function desAccumulated(cursor: Cursor): {number}
    local count = VLQ.des(cursor)
    local at = VLQ.des(cursor)

    local arr = table.create(count)
    arr[1] = at

    for i = 2, count do
        local diff = VLQ.des(cursor)
        at += diff

        table.insert(arr, at)
    end

    return arr
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
    local classMap = {} :: {
        [string]: {
            Index: number,
            ObjectIds: {number},
        }
    }

    local refMap = {}
    local classNames = {}

    for i, inst in ipairs(instances) do
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
        table.insert(classMap[className].ObjectIds, i)
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

            name = name:sub(1, 1):upper() .. name:sub(2)

            if member.Security.Write ~= "None" then
                continue
            end

            local typeName = member.ValueType.Name
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

            for i, objectId in class.ObjectIds do
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

    for i = #instances, 1, -1 do
        local inst = instances[i]
        local parent = inst.Parent
        local parentRef = parent and refMap[parent] or 0

        -- 4a: Parent Index
        VLQ.ser(cursor, parentRef)
    end

    --------------------------
    -- 3: Properties
    --------------------------

    for i = #props, 1, -1 do
        local prop = props[i]
        local values = prop.Values
        local typeName = PropSquash.TypeIds[prop.TypeIndex]

        local classIndex = prop.ClassIndex
        local className = classNames[classIndex]

        local class = classMap[className]
        local objectIds = class.ObjectIds

        -- 3e: Property Values
        for j = #objectIds, 1, -1 do
            local value = values[j]
            PropSquash.Compress(cursor, typeName, value)
        end

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
        serAccumulated(cursor, class.ObjectIds)
        
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

local function deserializeV1(apiDump: ApiDump, cursor: Cursor): Instance
    -- Deserialize classes
    local objects = {}
    local numClasses = VLQ.des(cursor)

    local classMap = {} :: {
        [number]: {
            Name: string,
            ObjectIds: {number},
        }
    }

    for i = 1, numClasses do
        local className = STRING.des(cursor)
        local classIndex = VLQ.des(cursor)
        local objectIds = desAccumulated(cursor)

        for i, objectId in ipairs(objectIds) do
            objects[objectId] = Instance.new(className)
        end

        classMap[classIndex] = {
            Name = className,
            ObjectIds = objectIds,
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

        for j, objectId in objectIds do
            local object = objects[objectId];
            local ok, result = PropSquash.Decompress(cursor, typeName)

            if ok then
                local setter = propSetters[propName]

                if setter then
                    setter(object, result)
                else
                    (object :: any)[propName] = result
                end
            end
        end
    end

    -- Deserialize hierarchy
    for i, object in ipairs(objects) do
        local parentRef = VLQ.des(cursor)

        if parentRef ~= 0 then
            object.Parent = objects[parentRef]
        end
    end

    -- Return the root object
    return objects[1]
end

local function deserialize(buf: buffer): Instance
    local cursor = Squash.frombuffer(buf)
    local apiDumpGet = ApiDump.Get()

    if not apiDumpGet.Success then
        error("ModelSquash - API Dump source not set or failed to load!")
    end

    local magic = STRING.des(cursor)
    assert(magic == "RBXMSQSH", "ModelSquash - Provided buffer is not a valid ModelSquash buffer!")

    local apiDump = apiDumpGet.ApiDump
    local version = VLQ.des(cursor)

    if version == 1 then
        return deserializeV1(apiDump, cursor)
    end

    -- Currently only version 1 is supported
    error("ModelSquash - Unsupported ModelSquash version: " .. tostring(version))
end

return table.freeze({
    ser = serialize,
    des = deserialize,

    Serialize = serialize,
    Deserialize = deserialize,
    SetApiDumpCacheSource = ApiDump.SetCacheSource,
})