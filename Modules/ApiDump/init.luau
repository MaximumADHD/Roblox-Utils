---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- API Dump Types
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

export type SecurityType =
    | "None"
    | "PluginSecurity"
    | "RobloxSecurity"
    | "LocalUserSecurity"
    | "RobloxScriptSecurity"
    | "NotAccessibleSecurity"

export type ThreadSafety =
    | "Safe"
    | "Unsafe"
    | "ReadSafe"

export type TypeCategory =
    | "Enum"
    | "Class"
    | "Group"
    | "DataType"
    | "Primitive"

export type Named = {
    Name: string,
}

export type TypeInfo = Named & {
    Category: TypeCategory,
}

export type Parameter = Named & {
    Type: TypeInfo,
}

type Descriptor = Named & {
    Tags: { string },
}

export type ClassDescriptor = Descriptor & {
    Superclass: string,
    MemoryCategory: string,
    Members: {MemberDescriptor},

    __memberCache: {
        [string]: MemberDescriptor
    }?,

    __defaultValues: {
        [string]: any
    }?
}

export type IMemberDescriptor<T> = Descriptor & {
    MemberType: T,
    ThreadSafety: ThreadSafety,
}

export type ISecurityCapabilities = { string } | {
    Read: { string },
}

export type PropertyDescriptor = IMemberDescriptor<"Property"> & {
    Category: string,
    ValueType: TypeInfo,
    Default: string,

    Capabilities: ISecurityCapabilities,

    Security: {
        Read: SecurityType,
        Write: SecurityType,
    },
    
    Serialization: {
        CanSave: boolean,
        CanLoad: boolean,
    },
}

export type EventDescriptor = IMemberDescriptor<"Event"> & {
    Parameters: { Parameter },
    Security: SecurityType,
}

export type FunctionDescriptor = IMemberDescriptor<"Function"> & {
    Parameters: { Parameter },
    ReturnType: TypeInfo,
    Security: SecurityType,
}

export type CallbackDescriptor = IMemberDescriptor<"Callback"> & {
    Parameters: { Parameter },
    ReturnType: TypeInfo,
    Security: SecurityType,
}

export type MemberDescriptor = 
    | EventDescriptor
    | PropertyDescriptor
    | FunctionDescriptor
    | CallbackDescriptor

export type EnumDescriptor = Descriptor & {
    Items: { EnumItemDescriptor },
}

export type EnumItemDescriptor = Descriptor & {
    Value: number,
    LegacyNames: { string }?,
}

export type TagMap = {
    NotCreatable: true?,
    NotReplicated: true?,
    ReadOnly: true?,
    CustomLuaState: true?,
    NotScriptable: true?,
    Hidden: true?,
    CanYield: true?,
    Deprecated: true?,
    Service: true?,
    Settings: true?,
    NotBrowsable: true?,
    WriteOnly: true?,
    SupportsStyling: true?,
}

export type ApiDump = {
    Classes: { ClassDescriptor },
    Enums: { EnumDescriptor },
    __classMap: ClassMap?,
}

type ClassMap = {
    [string]: ClassDescriptor
}

type IApiGet<Success, ApiDump> = {
    Success: Success,
    ApiDump: ApiDump,
}

export type ApiGet = 
    | IApiGet<true, ApiDump>
    | IApiGet<false, nil>

---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local HttpService = game:GetService("HttpService")

local baseUrl = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/"
local cacheApiGet: ApiGet? 

local cacheSource: (DataStore | Plugin | { [any]: any })? = (function ()
    if not shared.ApiDumpCache then
        shared.ApiDumpCache = {}
    end

    return shared.ApiDumpCache
end)()

local Capabilities = {} :: {
    [string]: SecurityCapabilities
}

for i, capability in Enum.SecurityCapability:GetEnumItems() do
    Capabilities[capability.Name] = SecurityCapabilities.new(capability)
end

local function getAsync(url: string)
    local success, result = pcall(function ()
        return HttpService:GetAsync(url, true)
    end)

    if not success then
        warn("Failed to call HttpService:GetAsync", url, "Error:", result)
        return false, "{}" -- Return an empty JSON object on failure
    end

    return true, result
end

local function getTags(object: Descriptor): TagMap
    local tags = {} :: {
        [string]: true?
    }

    if object.Tags ~= nil then
        for _, tag in pairs(object.Tags) do
            tags[tag] = true
        end
    end

    if object.Name == "Terrain" then
        tags.NotCreatable = nil
    end

    return tags
end

local function getApiDump(): ApiGet
    if cacheApiGet and cacheApiGet.Success then
        return cacheApiGet
    end
    
    local result: ApiGet
    local current = version()

    if cacheSource then
        local query: (any, string) -> any = 
            if type(cacheSource) == "table" then
                rawget
            elseif cacheSource:IsA("Plugin") then
                cacheSource.GetSetting
            else
                cacheSource.GetAsync
        
        local stored = query(cacheSource, "ApiDumpVersion")

        if stored and current == stored then
            local apiDump = query(cacheSource, "ApiDump")

            if apiDump then
                result = {
                    Success = true,
                    ApiDump = apiDump
                }
            end
        end
    end
    
    if result then
        cacheApiGet = result
        return result
    end

    local success, apiDumpJson = getAsync(baseUrl .. "Mini-API-Dump.json")
    local apiDump: ApiDump = success and HttpService:JSONDecode(apiDumpJson)

    if success then
        if cacheSource then
            local set: (any, string, any) -> () =
                if type(cacheSource) == "table" then
                    rawset
                elseif cacheSource:IsA("Plugin") then
                    cacheSource.SetSetting
                else
                    cacheSource.SetAsync
            
            set(cacheSource, "ApiDumpVersion", current)
            set(cacheSource, "ApiDump", apiDump)
        end

        result = {
            Success = true,
            ApiDump = apiDump
        }
    end

    if result then
        cacheApiGet = result
        return result
    end

    return {
        Success = false
    }
end

local function getClassMap(apiDump: ApiDump): ClassMap
    if apiDump.__classMap then
        return apiDump.__classMap
    end

    local classMap = {}
    apiDump.__classMap = classMap

    for i, class in ipairs(apiDump.Classes) do
        classMap[class.Name] = class
    end

    return classMap
end

local function getMembersOfClass(apiDump: ApiDump, className: string)
    local memberMap = {}
    local classes = getClassMap(apiDump)
    local class = classes[className]

    if not class then
        return memberMap
    end

    if class.__memberCache then
        return class.__memberCache
    end

    class.__memberCache = memberMap

    while class do
        for i, member in ipairs(class.Members) do
            memberMap[member.Name] = member
        end

        class = classes[class.Superclass]
    end

    return memberMap
end

local function getDefaultValues(apiDump: ApiDump, className: string): { [string]: any }?
    local class = getClassMap(apiDump)[className]
    local defaultValues = class and class.__defaultValues

    if defaultValues then
        return defaultValues
    end

    local members = getMembersOfClass(apiDump, className)
    
    local success, inst = pcall(function ()
        return Instance.new(className)
    end)

    if not success then
        return nil
    end

    local propMap = {}
    class.__defaultValues = propMap
    
    for name, member in pairs(members) do
        if member.MemberType ~= "Property" then
            continue
        end
        
        local success, value = pcall(function ()
            return (inst :: any)[name]
        end)

        if success then
            propMap[name] = if value ~= nil then value else "NULL"
        end
    end

    return propMap
end

local function setCacheSource(newCacheSource: typeof(cacheSource))
    cacheSource = newCacheSource
end

return table.freeze({
    Get = getApiDump,
    GetTags = getTags,
    GetClassMap = getClassMap,
    GetMembersOfClass = getMembersOfClass,
    GetDefaultValues = getDefaultValues,
    SetCacheSource = setCacheSource,
})