local Shared = script.Parent
local Squash = require(Shared.Squash)

local PropSquash = require(script.PropSquash)
local ArraySquash = require(Shared.ArraySquash)
local DeferredPatcher = require(script.DeferredPatcher)
local ReflectionService = game:GetService("ReflectionService")

local Filters = require(script.Filters) :: {
    [string]: { -- Class
        [string]: boolean -- [Property]: Allow/Ignore
    }
}

local Accumulated = ArraySquash.Accumulated
local AccI32 = Accumulated.I32

local STRING = Squash.string()
local VLQ = Squash.vlq()

type Cursor = Squash.Cursor

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
    [string]: {
        [string]: (Instance, any) -> ()
    }
}

local propCache = {} :: {
    [string]: { ReflectedProperty }
}

propSetters.Instance = {
    Tags = function (inst: Instance, tags: { string })
        for i, tag in tags do
            inst:AddTag(tag)
        end
    end,
    
    Attributes = function (inst: Instance, attributes: { [string]: any })
        for name, value in attributes do
            inst:SetAttribute(name, value)
        end
    end
}

propSetters.MeshPart = {
    MeshId = function (inst: MeshPart, value: string)
        local meshContent = Content.fromUri(value)
        DeferredPatcher.PatchMeshPart(inst, "MeshContent", meshContent)
    end,

    FluidFidelity = function (inst: MeshPart, value: Enum.FluidFidelity)
        DeferredPatcher.PatchMeshPart(inst, "FluidFidelity", value)
    end,

    RenderFidelity = function (inst: MeshPart, value: Enum.RenderFidelity)
        DeferredPatcher.PatchMeshPart(inst, "RenderFidelity", value)
    end,

    CollisionFidelity = function (inst: MeshPart, value: Enum.CollisionFidelity)
        DeferredPatcher.PatchMeshPart(inst, "CollisionFidelity", value)
    end,
}

local function getProperties(className: string): { ReflectedProperty }
    local props = propCache[className]

    if props == nil then
        props = ReflectionService:GetPropertiesOfClass(className)
        propCache[className] = props
    end

    return props
end

local function canSerialize(prop: ReflectedProperty)
    local name = prop.Name
    local owner = prop.Owner
    local override = owner and Filters[owner] and Filters[owner][name]

    if override ~= nil then
        return override
    end

    local display = prop.Display
    local permits = prop.Permits

    local serialize = permits.Write ~= nil
        and not (display and display.DeprecationMessage)
        and prop.Serialized

    return serialize
end

local function serialize(root: Instance): buffer
    local cursor = Squash.cursor()

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
    local props = {} :: {
        [number]: PROP
    }

    for classIndex, className in classNames do
        local class = classMap[className]
        local objectIds = class.ObjectIds

        for _, prop in getProperties(className) do
            if not canSerialize(prop) then
                continue
            end

            local name = prop.Name
            local propType = prop.Type

            local engineType = propType.EngineType
            local typeIndex = PropSquash.TypeEnum[engineType]

            if typeIndex == nil then
                local alias = PropSquash.TypeAliases[engineType]

                if alias then
                    typeIndex = PropSquash.TypeEnum[alias]
                end
            end

            if typeIndex == nil then
                continue
            end

            local prop = {
                Name = name,
                ClassIndex = classIndex,
                TypeIndex = typeIndex,
                Values = {},
            }

            for _, objectId in ipairs(objectIds) do
                local instance = instances[objectId]
                local value = (instance :: any)[name]
                table.insert(prop.Values, value)
            end

            table.insert(props, prop)
        end

        -- Manually collect tags and attributes
        local attributeMap = {}
        local tagMap = {}

        for _, objectId in ipairs(objectIds) do
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

        for key: string, map: any in collections :: any do
            if not next(map) then
                continue
            end

            local prop: PROP = {
                Name = key,
                ClassIndex = classIndex,
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
    local classMap = {} :: {{
        Name: string,
        ObjectIds: { number },
    }}

    local objects = {} :: { Instance }
    local numClasses = VLQ.des(cursor)

    for i = 1, numClasses do
        local className = STRING.des(cursor)
        local classIndex = VLQ.des(cursor)
        local objIds = AccI32.des(cursor)

        for i, id in objIds do
            local success, object = pcall(function ()
                return Instance.new(className)
            end)

            if success then
                objects[id] = object
            else
                warn("ModelSquash - Could not create instance of class:", className, "Error:", object)
            end
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

        local ok, result = PropSquash.DecompressArray(cursor, typeName)
        local values = ok and result or {}

        for j, objectId in ipairs(objectIds) do
            local inst = objects[objectId]
            local value = values[j]

            if not inst then
                warn("ModelSquash - Could not find instance for objectId:", objectId, "Class:", classInfo.Name)
                continue
            end

            if typeName == "Ref" then
                value = objects[value]
            end

            local setter

            for name, setters in propSetters do
                if inst:IsA(name) and setters[propName] then
                    setter = setters[propName]
                    break
                end
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

local function getTypeIndexFromEngineType(engineType: string): number?
    local typeIndex = PropSquash.TypeEnum[engineType]

    if typeIndex == nil then
        local alias = PropSquash.TypeAliases[engineType]

        if alias then
            typeIndex = PropSquash.TypeEnum[alias]
        end
    end

    return typeIndex
end

return table.freeze({
    ser = serialize,
    des = deserialize,

    Serialize = serialize,
    Deserialize = deserialize,

    GetTypeIndexFromEngineType = getTypeIndexFromEngineType,
})