local function index(key: string): string
    return `|{key:gsub("|", "\\|")}`
end

local function addLock(inst: Instance, lock: string, key: string)
    local list = tostring(inst:GetAttribute(lock) or "")
    key = index(key)

    if not list:find(key) then
        list ..= key
        inst:SetAttribute(lock, list)
    end
end

local function removeLock(inst: Instance, lock: string, key: string)
    local list = tostring(inst:GetAttribute(lock) or "")
    key = index(key)

    if list:find(key) then
        list = list:gsub(key, "")
        inst:SetAttribute(lock, list)
    end
end

local function hasLock(inst: Instance, lock: string, key: string?): boolean
    local list = tostring(inst:GetAttribute(lock) or "")

    if key then
        key = index(key)
        return list:find(key) ~= nil
    else
        return list ~= ""
    end
end

local function getLockChangedSignal(inst: Instance, lock: string)
    return inst:GetAttributeChangedSignal(lock)
end

return table.freeze({
    AddLock = addLock,
    HasLock = hasLock,
    RemoveLock = removeLock,
    GetLockChangedSignal = getLockChangedSignal,
})