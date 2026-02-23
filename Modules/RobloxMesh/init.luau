--!strict
local AssetService = game:GetService("AssetService")
local ASSET_PROXY = "http://localhost:20326/asset?id=%i"

local RobloxMesh = {}
RobloxMesh.__index = RobloxMesh

export type Vertex = {
    Position: Vector3,
    Normal: Vector3,
    UV: Vector2,

    Tangent: {
        Vector: Vector3,
        Sign: number,
    }?,

    Color: {
        Tint: Color3,
        Alpha: number,
    },

    Weights: {
        [Bone]: number,
    },
}

type SkinSet = {
    Bones: { number },
    Weights: { number },
}

type Transform = {
    Position: Vector3,
    Rotation: Vector3,
}

type FacsPose = {
    [string]: Transform
}

type FacsPoses = {
    [string]: FacsPose
}

type TwoPoseCorrective = {
    Pose: number,
    IndexA: number,
    IndexB: number,
}

type ThreePoseCorrective = {
    Pose: number,
    IndexA: number,
    IndexB: number,
    IndexC: number,
}

type FacsData = {
    Poses: FacsPoses,
    BoneNames: { string },
    ControlNames: { string },
    TwoPoseCorrectives: { TwoPoseCorrective },
    ThreePoseCorrectives: { ThreePoseCorrective },
}

type Face = { number }
type LOD = { Face }

-- stylua: ignore
export type Class = typeof(setmetatable({} :: {
    LODs: { LOD },
    Bones: { Bone }?,
    Verts: { Vertex },
    FACS: FacsData?,
}, RobloxMesh))

--------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = script.Parent
local Draco = require(script.Draco)
local Buffer = require(script.Buffer)
local RunContext = require(Shared.RunContext)

local FACS_ACTION_MAP = {}

for i, item in Enum.FacsActionUnit:GetEnumItems() do
    FACS_ACTION_MAP[item.Name] = item
end

local FACS_SHORT_NAME_MAP = table.freeze({
    c_COR = "Corrugator",
    c_CR = "ChinRaiser",
    c_CRUL = "ChinRaiserUpperLip",
    c_ELD = "EyesLookDown",
    c_ELL = "EyesLookLeft",
    c_ELR = "EyesLookRight",
    c_ELU = "EyesLookUp",
    c_FN = "Funneler",
    c_FP = "FlatPucker",
    c_JD = "JawDrop",
    c_JL = "JawLeft",
    c_JR = "JawRight",
    c_LLS = "LowerLipSuck",
    c_LP = "LipPresser",
    c_LPT = "LipsTogether",
    c_ML = "MouthLeft",
    c_MR = "MouthRight",
    c_PK = "Pucker",
    c_TD = "TongueDown",
    c_TO = "TongueOut",
    c_TU = "TongueUp",
    c_ULS = "UpperLipSuck",

    l_BL = "LeftBrowLowerer",
    l_CHP = "LeftCheekPuff",
    l_CHR = "LeftCheekRaiser",
    l_DM = "LeftDimpler",
    l_EC = "LeftEyeClosed",
    l_EULR = "LeftEyeUpperLidRaiser",
    l_IBR = "LeftInnerBrowRaiser",
    l_LCD = "LeftLipCornerDown",
    l_LCP = "LeftLipCornerPuller",
    l_LLD = "LeftLowerLipDepressor",
    l_LS = "LeftLipStretcher",
    l_NW = "LeftNoseWrinkler",
    l_OBR = "LeftOuterBrowRaiser",
    l_ULR = "LeftUpperLipRaiser",

    r_BL = "RightBrowLowerer",
    r_CHP = "RightCheekPuff",
    r_CHR = "RightCheekRaiser",
    r_DM = "RightDimpler",
    r_EC = "RightEyeClosed",
    r_EULR = "RightEyeUpperLidRaiser",
    r_IBR = "RightInnerBrowRaiser",
    r_LCD = "RightLipCornerDown",
    r_LCP = "RightLipCornerPuller",
    r_LLD = "RightLowerLipDepressor",
    r_LS = "RightLipStretcher",
    r_NW = "RightNoseWrinkler",
    r_OBR = "RightOuterBrowRaiser",
    r_ULR = "RightUpperLipRaiser",
})

local DRACO_NORMAL_ID = 1
local DRACO_TANGENT_ID = 3

type Buffer = Buffer.Class

--------------------------------------------------------------------

local skip = Buffer.Skip
local readI8 = Buffer.ReadInt8
local readU8 = Buffer.ReadUInt8
local readI32 = Buffer.ReadInt32
local readU16 = Buffer.ReadUInt16
local readU32 = Buffer.ReadUInt32
local readF32 = Buffer.ReadFloat32
local readBytes = Buffer.ReadBytes
local readString = Buffer.ReadString
local readVector2 = Buffer.ReadVector2
local readVector3 = Buffer.ReadVector3

local function deepClone(t: any, instMap: { [Instance]: Instance }?): any
    local copy = table.clone(t)

    for key, value in pairs(copy) do
        if type(value) == "table" then
            copy[key] = deepClone(value, instMap)
        elseif typeof(value) == "Instance" and instMap then
            local clone = value:Clone()

            if clone then
                instMap[value] = clone
            end
        end
    end

    return copy
end

-- Reads an ASCII mesh (version 1.xx)
local function readAsciiMesh(file: string): Class
    local readLine = file:gmatch("[^\r\n]+")

    local header = assert(readLine())
    assert(header:sub(1, 8) == "version ", "Not a mesh file")

    local meshVersion = assert(tonumber(header:sub(9)), "Bad version header")
    assert(meshVersion >= 1 and meshVersion < 2, "mesh version not supported: " .. meshVersion)

    local numFaces = assert(tonumber(readLine()), "bad face count")
    local readXYZ = string.gmatch(assert(readLine()), "%[([^,]+),([^,]+),([^%]]+)%]")

    local xs, ys, zs
    local x, y, z

    local function nextVector3(): Vector3
        xs, ys, zs = readXYZ()

        x = tonumber(xs)
        y = tonumber(ys)
        z = tonumber(zs)

        return Vector3.new(x, y, z)
    end

    local function nextVector2(): Vector2
        xs, ys, zs = readXYZ()

        local u = tonumber(xs) or 0
        local v = tonumber(ys) or 0

        return Vector2.new(u, 1 - v)
    end

    local verts: { Vertex } = {}
    local faces: { { number } } = {}

    for i = 1, numFaces do
        for v = 1, 3 do
            local pos = nextVector3()
            local norm = nextVector3()
            local uv = nextVector2()

            if meshVersion < 1.01 then
                pos *= 0.5
            end

            table.insert(verts, {
                Position = pos,
                Normal = norm,
                UV = uv,

                Color = {
                    Tint = Color3.new(1, 1, 1),
                    Alpha = 1,
                },

                Weights = {},
            })
        end

        local c = i * 3
        local b = c - 1
        local a = b - 1

        local face = { a, b, c }
        table.insert(faces, face)
    end

    return setmetatable({
        LODs = { faces },
        Verts = verts,
    }, RobloxMesh)
end

-- Reads vertex data from the buffer for versions 2.xx to 6.xx
local function readVerts(buf: Buffer, numVerts: number, hasColor: boolean)
    local verts = {}

    for i = 1, numVerts do
        local vert: Vertex = {
            Weights = {},
            
            Color = {
                Tint = Color3.new(1, 1, 1),
                Alpha = 1,
            },

            Position = readVector3(buf),
            Normal = readVector3(buf),
            UV = readVector2(buf),
        }
        
        local tx = readI8(buf) / 127
        local ty = readI8(buf) / 127
        local tz = readI8(buf) / 127
        local ts = readI8(buf) / 127

        local tv = Vector3.new(tx, ty, tz)

        if tv.Magnitude ~= 0 and ts ~= 0 then
            vert.Tangent = {
                Sign = ts,
                Vector = tv,
            }
        end

        if hasColor then
            local r = readU8(buf)
            local g = readU8(buf)
            local b = readU8(buf)

            vert.Color = {
                Tint = Color3.fromRGB(r, g, b),
                Alpha = readU8(buf) / 255,
            }
        end

        verts[i] = vert
    end

    return verts
end

--- Reads face data from the buffer for versions 2.xx to 6.xx
local function readFaces(buf: Buffer, numFaces: number)
    local faces = {}

    for i = 1, numFaces do
        local face: Face = {
            1 + readU32(buf),
            1 + readU32(buf),
            1 + readU32(buf),
        }

        faces[i] = face
    end

    return faces
end

--- Reads the LOD offsets from the buffer, which indicate where each LOD's face data begins and ends.
local function readLodOffsets(buf: Buffer, numLodOffsets: number, numFaces: number)
    local lodOffsets = table.create(numLodOffsets)

    for i = 1, numLodOffsets do
        lodOffsets[i] = readU32(buf)
    end

    if numLodOffsets < 2 or lodOffsets[2] == 0 then
        lodOffsets = { 0, numFaces }
    end

    return lodOffsets
end

--- Reads the skinning data for each vertex, which indicates which bones affect each vertex and by how much.
local function readSkinning(buf: Buffer, count: number)
    local skinning = table.create(count)

    for i = 1, count do
        local bones = readBytes(buf, 4)
        local weights = readBytes(buf, 4)

        skinning[i] = {
            Bones = bones,
            Weights = weights,
        }
    end

    return skinning
end

--- Reads the subsets for each LOD, which indicate which vertices are influenced by which bones for each subset of the mesh.
local function readSubsets(buf: Buffer, verts: { Vertex }, bones: { Bone }, skinning: { SkinSet }, count: number)
    for i = 1, count do
        skip(buf, 4) -- u32 facesBegin
        skip(buf, 4) -- u32 facesLength

        local vertsBegin = readU32(buf)
        local vertsEnd = vertsBegin + readU32(buf)

        skip(buf, 4) -- u32 numBones
        local boneSubset = table.create(26, 0)

        for b = 1, 26 do
            boneSubset[b] = readU16(buf)
        end

        for v = vertsBegin, vertsEnd - 1 do
            local vert = verts[v + 1]
            local set = skinning[v + 1]

            for s = 1, 4 do
                local subsetIndex = 1 + set.Bones[s]
                local boneId = boneSubset[subsetIndex]

                if boneId == 0xFFFF then
                    -- empty slot
                    continue
                end

                local bone = bones[1 + boneId]
                local weight = set.Weights[s]

                if weight > 0 then
                    vert.Weights[bone] = weight
                end
            end
        end
    end
end

--- Reads the bone hierarchy from the buffer, including the transform for each bone and its parent-child relationships.
local function readBones(buf: Buffer, count: number): { Bone }
    local bones: { Bone } = table.create(count)

    for i = 1, count do
        local bone = Instance.new("Bone")
        local nameIndex = readI32(buf)
        local parentId = readU16(buf)

        skip(buf, 2) -- u16 lodParentId
        skip(buf, 4) -- f32 culling
        
        bone:SetAttribute("NameIndex", nameIndex)
        bone.Parent = bones[parentId + 1]
        bones[i] = bone

        local m1 = readVector3(buf)
        local m2 = readVector3(buf)
        local m3 = readVector3(buf)
        local m0 = readVector3(buf)

        -- stylua: ignore
        bone.WorldCFrame = CFrame.new(
            m0.X, m0.Y, m0.Z,
            m1.X, m1.Y, m1.Z,
            m2.X, m2.Y, m2.Z,
            m3.X, m3.Y, m3.Z
        )
    end

    return bones
end

--- Reads the bone names from the buffer and maps them to the corresponding Bone instances.
local function readBoneNames(buf: Buffer, bones: { Bone }, size: number)
    local boneNames = readString(buf, size)
    local boneMap = {}

    for i, bone in bones do
        local startAt = (tonumber(bone:GetAttribute("NameIndex")) or 0) + 1
        local endAt = boneNames:find("\0", startAt)

        if endAt then
            local name = boneNames:sub(startAt, endAt - 1)
            boneMap[name] = bone
            bone.Name = name
        end
    end

    return boneMap
end

--- Remaps the face arrays into groups based on the LOD offset ranges.
local function mapLodOffsets(faces: {{number}}, lodOffsets: { number })
    local numLodOffsets = #lodOffsets
    local lods = table.create(numLodOffsets - 1)

    for L = 1, numLodOffsets - 1 do
        local lodStart = lodOffsets[L]
        local lodEnd = lodOffsets[L + 1]
        local lod = table.create(lodEnd - lodStart)

        for i = lodStart + 1, lodEnd do
            local face = faces[i]
            table.insert(lod, face)
        end

        table.insert(lods, lod)
    end

    return lods
end

--- Reads the FACS data from the buffer, which includes the facial poses and how they relate to the bones in the mesh.
local function readFACS(buf: Buffer, boneMap: { [string]: Bone }): FacsData
    local sizeof_faceBoneBuffer = readU32(buf)
    local sizeof_faceControlBuffer = readU32(buf)
    skip(buf, 8) -- u64 sizeof_quantizedTransforms
    
    local numTwoPoseCorrectives = readU32(buf) / 4
    local numThreePoseCorrectives = readU32(buf) / 6

    local faceBoneBuffer = readString(buf, sizeof_faceBoneBuffer)
    local faceControlBuffer = readString(buf, sizeof_faceControlBuffer)

    local nameStart = 0
    local faceBoneNames = {}
    local faceControlNames = {}

    while true do
        local nameEnd = faceBoneBuffer:find("\0", nameStart)

        if nameEnd then
            local name = faceBoneBuffer:sub(nameStart, nameEnd - 1)
            table.insert(faceBoneNames, name)
            nameStart = nameEnd + 1
        else
            break
        end
    end

    nameStart = 0

    while true do
        local nameEnd = faceControlBuffer:find("\0", nameStart)

        if nameEnd then
            local name = faceControlBuffer:sub(nameStart, nameEnd - 1)
            name = FACS_SHORT_NAME_MAP[name] or name

            table.insert(faceControlNames, name)
            nameStart = nameEnd + 1
        else
            break
        end
    end

    local transform = table.create(6)

    for i = 1, 6 do
        local format = readU16(buf)
        local rows = readU32(buf)
        local cols = readU32(buf)

        local matrix = table.create(rows * cols)
        transform[i] = matrix

        if format == 1 then
            for i = 1, rows * cols do
                matrix[i] = readF32(buf)
            end
        elseif format == 2 then
            local min = readF32(buf)
            local max = readF32(buf)

            local range = math.abs(max - min)
            assert(range <= 65535)

            -- stylua: ignore
            local alpha = if range > 1e-4
                then range / 65535
                else 0

            for i = 1, rows * cols do
                local value = readU16(buf)
                matrix[i] = (value * alpha) + min
            end
        end
    end

    local numPoses = #faceControlNames + numTwoPoseCorrectives + numThreePoseCorrectives
    local poseNames = table.clone(faceControlNames)
    local poses = table.create(numPoses)

    local twoPoseCorrectives = table.create(numTwoPoseCorrectives)
    local threePoseCorrectives = table.create(numThreePoseCorrectives)

    for i = 1, numTwoPoseCorrectives do
        local nextIndex = #poseNames + 1

        local indexA = 1 + readU16(buf)
        local indexB = 1 + readU16(buf)

        table.insert(twoPoseCorrectives, {
            Pose = nextIndex,
            IndexA = indexA,
            IndexB = indexB,
        })

        local refA = faceControlNames[indexA]
        local refB = faceControlNames[indexB]

        table.insert(poseNames, `x2_{refA}_{refB}`)
    end

    for i = 1, numThreePoseCorrectives do
        local nextIndex = #poseNames + 1

        local indexA = 1 + readU16(buf)
        local indexB = 1 + readU16(buf)
        local indexC = 1 + readU16(buf)

        table.insert(threePoseCorrectives, {
            Pose = nextIndex,
            IndexA = indexA,
            IndexB = indexB,
            IndexC = indexC,
        })

        local refA = faceControlNames[indexA]
        local refB = faceControlNames[indexB]
        local refC = faceControlNames[indexC]

        table.insert(poseNames, `x3_{refA}_{refB}_{refC}`)
    end

    local posTblX, posTblY, posTblZ, 
          rotTblX, rotTblY, rotTblZ = unpack(transform)

    for row, boneName in faceBoneNames do
        local begin = ((row - 1) * numPoses)

        for col = 1, numPoses do
            local pose = poses[col] or {}
            local i = begin + col

            if begin == 0 then
                poses[col] = pose
            end

            local posX = posTblX[i]
            local posY = posTblY[i]
            local posZ = posTblZ[i]

            local rotX = rotTblX[i]
            local rotY = rotTblY[i]
            local rotZ = rotTblZ[i]
            
            pose[boneName] = {
                Position = Vector3.new(posX, posY, posZ),
                Rotation = Vector3.new(rotX, rotY, rotZ),
            }
        end
    end

    -- Map the poses to their names.
    local poseMap: FacsPoses = {}

    for i, name in poseNames do
        poseMap[name] = poses[i]
    end

    -- Mark bones used as virtual.
    for i, boneName in faceBoneNames do
        local bone = boneMap[boneName]

        if bone then
            bone:AddTag("Virtual")
        end
    end

    return {
        Poses = poseMap,
        BoneNames = faceBoneNames,
        ControlNames = faceControlNames,
        TwoPoseCorrectives = twoPoseCorrectives,
        ThreePoseCorrectives = threePoseCorrectives,
    }
end

--- Reads a binary mesh between versions 2.xx and 5.xx
local function readBinaryMesh(buf: Buffer, meshVersion: number): Class
    local numLODs = 0
    local numVerts = 0
    local numFaces = 0
    local numBones = 0
    local numSubsets = 0

    local hasColor = false
    local facsDataType = 0
    local boneNamesSize = 0

    skip(buf, 2) -- u16 headerSize

    if meshVersion >= 4 then
        local _lodType = readU16(buf)

        numVerts = readU32(buf)
        numFaces = readU32(buf)

        numLODs = readU16(buf)
        numBones = readU16(buf)

        boneNamesSize = readU32(buf)
        numSubsets = readU16(buf)

        skip(buf, 2) -- u8 numHighQualityLODs, padding

        if meshVersion >= 5 then
            facsDataType = readU32(buf)
            skip(buf, 4) -- u32 facsDataSize
        end

        hasColor = true
    else
        local vertSize = readU8(buf)
        skip(buf, 1) -- faceSize

        if meshVersion >= 3 then
            skip(buf, 2) -- lodOffsetSize
            numLODs = readU16(buf)
        end

        numVerts = readU32(buf)
        numFaces = readU32(buf)
        hasColor = (vertSize > 36)
    end

    local bones: { Bone } = table.create(numBones)
    local verts: { Vertex } = table.create(numVerts)

    local faces: {{ number }} = table.create(numFaces)
    local lodOffsets: { number } = table.create(numLODs)

    local skinning: { SkinSet } = {}

    -- Read Verts
    verts = readVerts(buf, numVerts, hasColor)

    -- Read Skinning
    if numBones > 0 then
        skinning = readSkinning(buf, numVerts)
    end

    -- Read Faces
    faces = readFaces(buf, numFaces)

    -- Read LOD offsets
    lodOffsets = readLodOffsets(buf, numLODs, numFaces)

    -- Read Bones
    if numBones > 0 then
        bones = readBones(buf, numBones)
    end

    -- Read Bone Names
    local boneMap = readBoneNames(buf, bones, boneNamesSize)

    -- Read Bone Subsets
    readSubsets(buf, verts, bones, skinning, numSubsets)

    -- Break faces up by LOD
    if #lodOffsets == 0 then
        lodOffsets = { 0, #faces }
    end

    local lods = mapLodOffsets(faces, lodOffsets)

    -- Read FACS data
    local facs = if facsDataType == 1
        then readFACS(buf, boneMap)
        else nil

    return setmetatable({
        FACS = facs,
        LODs = lods,
        Bones = bones,
        Verts = verts,
    }, RobloxMesh)
end

--- Reads a chunk mesh between versions 6.xx and 7.xx
local function readChunkMesh(buf: Buffer): Class
    local facs = {} :: FacsData
    local bones = {} :: { Bone }
    local verts = {} :: { Vertex }
    local faces = {} :: { { number } }
    local lodOffsets = {} :: { number }

    local boneMap = {} :: {
        [string]: Bone
    }

    while true do
        local pos = buf:GetPosition()

        if pos >= buf:GetLength() then
            break
        end

        local id = readString(buf, 8):gsub("\0", "")
        local format = readU32(buf)
        local size = readU32(buf)
        local handled = true
        
        if id == "COREMESH" then
            if format == 1 then
                local numVerts = readU32(buf)
                verts = readVerts(buf, numVerts, true)

                local numFaces = readU32(buf)
                faces = readFaces(buf, numFaces)
            elseif format == 2 then
                skip(buf, 4) -- u32 dracoBitstreamSize (redundant?)
                
                local dracoMesh = Draco.ReadStream(buf)
                local numPoints = dracoMesh.NumPoints

                -- Collect vertex data
                local uvs = table.create(numPoints)
                local norms = table.create(numPoints)
                local colors = table.create(numPoints)
                local points = table.create(numPoints)
                local tangents = table.create(numPoints)

                for x, y, z in dracoMesh:ComponentsOf("Position") do
                    local point = Vector3.new(x, y, z)
                    table.insert(points, point)
                end

                for u, v in dracoMesh:ComponentsOf("TexCoord") do
                    local uv = Vector2.new(u, v)
                    table.insert(uvs, uv)
                end

                for r, g, b, a in dracoMesh:ComponentsOf("Color") do
                    local color = Color3.fromRGB(r, g, b)

                    table.insert(colors, {
                        Tint = color,
                        Alpha = a,
                    })
                end

                for x, y, z in dracoMesh:ComponentsOf(DRACO_NORMAL_ID) do
                    local norm = Vector3.new(x, y, z)
                    table.insert(norms, norm)
                end

                for x, y, z, s in dracoMesh:ComponentsOf(DRACO_TANGENT_ID) do
                    local vec = Vector3.new(x - 127, y - 127, z - 127) / 127
                    local sign = (s - 127) / 127

                    table.insert(tangents, {
                        Vector = vec,
                        Sign = sign,
                    })
                end

                -- Build verts
                verts = table.create(numPoints)

                for i = 1, numPoints do
                    verts[i] = {
                        Position = points[i],
                        Normal = norms[i],
                        UV = uvs[i],

                        Tangent = tangents[i],
                        Color = colors[i],

                        Weights = {},
                    }
                end

                -- Build faces
                local numFaces = dracoMesh.NumFaces
                local faceIds = dracoMesh.Faces
                faces = table.create(numFaces)

                for i = 1, numFaces * 3, 3 do
                    local a, b, c = table.unpack(faceIds, i, i + 2)
                    table.insert(faces, { a + 1, b + 1, c + 1 })
                end
            else
                handled = false
            end
        elseif format == 1 then
            if id == "LODS" then
                skip(buf, 2) -- lodType
                skip(buf, 1) -- numHighQualityLODs

                local numLodOffsets = readU32(buf)
                lodOffsets = readLodOffsets(buf, numLodOffsets, #faces)
            elseif id == "SKINNING" then
                local numSkinning = readU32(buf)
                local skinning = readSkinning(buf, numSkinning)

                local numBones = readU32(buf)
                bones = readBones(buf, numBones)

                local boneNamesSize = readU32(buf)
                boneMap = readBoneNames(buf, bones, boneNamesSize)

                local numSubsets = readU32(buf)
                readSubsets(buf, verts, bones, skinning, numSubsets)
            elseif id == "FACS" then
                skip(buf, 4) -- facsDataSize (redundant?)
                facs = readFACS(buf, boneMap)
            else
                handled = false
            end
        else
            handled = false
        end

        if not handled then
            warn("Unknown/unsupported chunk type: " .. id)
            skip(buf, size)
        end
    end

    local lods = mapLodOffsets(faces, lodOffsets)

    return setmetatable({
        FACS = facs,
        LODs = lods,
        Bones = bones,
        Verts = verts,
    }, RobloxMesh)
end

--- Main entry point for reading a mesh from a binary string. Determines the version and format of the mesh and dispatches to the appropriate reader function.
function RobloxMesh.new(bin: string): Class
    local rawBuf = buffer.fromstring(bin)
    local buf = Buffer.new(rawBuf)
    
    local header = readString(buf, 13)
    assert(header:sub(1, 8) == "version ", "Not a mesh file")

    if header:sub(-1) == "\r" then
        -- Some v1 meshes end with \r\n instead of \n
        local tail = readString(buf, 1)
        assert(tail == "\n", "Not a mesh file")
    end

    local meshVersion = assert(tonumber(header:match("%d+")), "Bad version header")
    assert(meshVersion >= 1 and meshVersion <= 7, "mesh version not supported: " .. meshVersion)

    if meshVersion < 2 then
        return readAsciiMesh(bin)
    elseif meshVersion < 6 then
        return readBinaryMesh(buf, meshVersion)
    else
        return readChunkMesh(buf)
    end
end

--- Retrieves the pose data for a given FACS action unit, if it exists in the mesh's FACS data.
function RobloxMesh.GetFacsPose(self: Class, pose: Enum.FacsActionUnit): FacsPose?
    if self.FACS then
        return self.FACS.Poses[pose.Name]
    end

    return nil
end

--- Retrieves the corrective pose data for a combination of two FACS action units, if it exists in the mesh's FACS data.
function RobloxMesh.GetFacsCorrectiveX2(self: Class, poseA: Enum.FacsActionUnit, poseB: Enum.FacsActionUnit): FacsPose?
    if self.FACS then
        local key = `x2_{poseA.Name}_{poseB.Name}`
        return self.FACS.Poses[key]
    end

    return nil
end

--- Retrieves the corrective pose data for a combination of three FACS action units, if it exists in the mesh's FACS data.
function RobloxMesh.GetFacsCorrectiveX3(self: Class, poseA: Enum.FacsActionUnit, poseB: Enum.FacsActionUnit, poseC: Enum.FacsActionUnit): FacsPose?
    if self.FACS then
        local key = `x3_{poseA.Name}_{poseB.Name}_{poseC.Name}`
        return self.FACS.Poses[key]
    end

    return nil
end

--- Converts a Transform (position and rotation) into a CFrame that can be applied to a bone in the mesh.
function RobloxMesh.GetCFrameOfTransform(transform: Transform): CFrame
    local rot = (transform.Rotation * math.pi) / 180
    return CFrame.fromEulerAnglesXYZ(rot.X, rot.Y, rot.Z) + transform.Position
end

--- Given a snapshot of FACS action unit values, computes the resulting Transform for each bone in the mesh based on the poses defined in the mesh's FACS data.
function RobloxMesh.ComputeFacsTransforms(self: Class, snapshot: FaceControls | { [Enum.FacsActionUnit]: number }): { [string]: Transform }
    local facs = self.FACS

    local result = {} :: {
        [string]: Transform
    }

    if facs then
        local state = {} :: {
            [string]: number
        }

        local faceControls = if typeof(snapshot) == "Instance" and snapshot:IsA("FaceControls") then snapshot else nil
        local sourceTable = if typeof(snapshot) == "table" then snapshot else nil

        for name, actionUnit in FACS_ACTION_MAP do
            local value = 0

            if faceControls then
                value = tonumber((snapshot :: any)[name]) or 0
            elseif sourceTable then
                value = sourceTable[actionUnit] or 0
            end

            state[name] = value
        end

        for i, twoPose in facs.TwoPoseCorrectives do
            local nameA = facs.ControlNames[twoPose.IndexA]
            local weightA = state[nameA] or 0

            local nameB = facs.ControlNames[twoPose.IndexB]
            local weightB = state[nameB] or 0

            local weight = weightA * weightB
            state[`x2_{nameA}_{nameB}`] = weight
        end

        for i, threePose in facs.ThreePoseCorrectives do
            local nameA = facs.ControlNames[threePose.IndexA]
            local weightA = state[nameA] or 0

            local nameB = facs.ControlNames[threePose.IndexB]
            local weightB = state[nameB] or 0

            local nameC = facs.ControlNames[threePose.IndexC]
            local weightC = state[nameC] or 0

            local weight = weightA * weightB * weightC
            state[`x3_{nameA}_{nameB}_{nameC}`] = weight
        end

        for i, boneName in facs.BoneNames do
            local pos = Vector3.zero
            local rot = Vector3.zero

            for poseName, weight in state do
                if weight > 0 then
                    local pose = facs.Poses[poseName]
                    local transform = pose and pose[boneName]

                    if transform then
                        pos += transform.Position * weight
                        rot += transform.Rotation * weight
                    end
                end
            end

            result[boneName] = {
                Position = pos,
                Rotation = rot,
            }
        end
    end

    return result
end

--- Creates a deep clone of the mesh, including all of its vertices, faces, bones, and FACS data. Preserves the hierarchy of the bones in the cloned mesh.
function RobloxMesh.Clone(self: Class): Class
    local instMap = {}
    local mesh = deepClone(self, instMap)

    for source, copy in instMap do
        local parent = source.Parent

        if parent and instMap[parent] then
            copy.Parent = instMap[parent]
        end
    end

    return setmetatable(mesh, RobloxMesh)
end

--- Applies a transformation to the mesh by offsetting the position of each vertex and rotating its normal by a given CFrame, and scaling the position by a given Vector3. Returns a new mesh with the transformation applied.
function RobloxMesh.Transform(self: Class, offset: CFrame?, scale: Vector3?): Class
    local copy = self:Clone()

    if scale or offset then
        for i, vert in copy.Verts do
            local pos = vert.Position
            local norm = vert.Normal

            if scale and scale ~= Vector3.one then
                pos *= scale
            end

            if offset and offset ~= CFrame.identity then
                pos = offset:PointToWorldSpace(pos)
                norm = offset:VectorToWorldSpace(norm)
            end

            vert.Position = pos
            vert.Normal = norm
        end
    end

    return copy
end

--- Appends another mesh to this mesh, combining their vertices and faces. Does not merge bones or FACS data from the other mesh.
function RobloxMesh.Append(self: Class, other: Class): Class
    local copy = self:Clone()
    local offset = #copy.Verts

    for i, vert in other.Verts do
        local newVert = deepClone(vert)
        table.insert(copy.Verts, newVert)
    end

    for lod, faces in other.LODs do
        local myFaces = copy.LODs[lod]

        if myFaces == nil then
            myFaces = {}
            copy.LODs[lod] = myFaces
        end

        for i, face in faces do
            local newFace = table.clone(face)

            for f = 1, 3 do
                newFace[f] += offset
            end

            table.insert(myFaces, newFace)
        end
    end

    return copy
end

--- Clones the bones of the mesh, preserving their hierarchy.
--- Returns the root bones of the cloned hierarchy.
function RobloxMesh.ForkBones(self: Class): { Bone }
    local roots = {}

    if self.Bones then
        for i, bone in self.Bones do
            if not bone.Parent then
                local fork = bone:Clone()
                table.insert(roots, fork)
            end
        end
    end

    return roots
end

--- Converts the mesh into an EditableMesh, which is Roblox's official API for editing and manipulating meshes at runtime.
function RobloxMesh.ToEditableMesh(self: Class, lod: number?): EditableMesh
    local lod = lod or 1
    local mesh = AssetService:CreateEditableMesh()
    local faces = assert(self.LODs[lod], `LOD {lod} does not exist in mesh`)

    local bones = nil :: {
        [Bone]: number,
    }?

    local facs = self.FACS

    local vertData = {} :: {{
        Position: number,
        Normal: number,
        Color: number,
        UV: number,
    }}

    if self.Bones then
        local boneData = {}

        for i, bone in self.Bones do
            local name = bone.Name
            local cf = bone.WorldCFrame

            local virtual = bone:HasTag("Virtual")
            local parent = bone.Parent

            local parentId = if parent and parent:IsA("Bone") 
                then boneData[parent] 
                else nil

            boneData[bone] = mesh:AddBone({
                Name = name,
                CFrame = cf,
                Virtual = virtual,
                ParentId = parentId,
            })
        end

        bones = boneData
    end

    if facs and bones then
        local boneMap = {}

        for bone, boneId in bones do
            boneMap[bone.Name] = boneId
        end

        for id, pose in facs.Poses do
            local threePoseA, threePoseB, threePoseC = id:match("x3_(%w+)_(%w+)_(%w+)")
            local twoPoseA, twoPoseB = id:match("x2_(%w+)_(%w+)")
            local actions

            if threePoseA and threePoseB and threePoseC then
                local actionA = FACS_ACTION_MAP[threePoseA]
                local actionB = FACS_ACTION_MAP[threePoseB]
                local actionC = FACS_ACTION_MAP[threePoseC]
                actions = { actionA, actionB, actionC }
            elseif twoPoseA and twoPoseB then
                local actionA = FACS_ACTION_MAP[twoPoseA]
                local actionB = FACS_ACTION_MAP[twoPoseB]
                actions = { actionA, actionB }
            else
                actions = { FACS_ACTION_MAP[id] }
            end

            if next(actions) then
                local snapshot = {}

                for i, action in actions do
                    snapshot[action] = 1
                end

                local pose = self:ComputeFacsTransforms(snapshot)
                local boneIds, cframes = {}, {}

                for boneName, transform in pose do
                    local boneId = boneMap[boneName]

                    if boneId then
                        local cframe = self.GetCFrameOfTransform(transform)
                        table.insert(boneIds, boneId)
                        table.insert(cframes, cframe)
                    end
                end

                if #actions == 1 then
                    mesh:SetFacsPose(actions[1], boneIds, cframes)
                else
                    mesh:SetFacsCorrectivePose(actions, boneIds, cframes)
                end
            end
        end
    end

    for i, vert in self.Verts do
        local color = vert.Color
        local colorId = mesh:AddColor(color.Tint, color.Alpha)

        local vertexId = mesh:AddVertex(vert.Position)
        local normalId = mesh:AddNormal(vert.Normal)
        local uvId = mesh:AddUV(vert.UV)

        if bones then
            local weights = {}
            local boneIds = {}

            for bone, weight in vert.Weights do
                local boneIndex = bones[bone]

                if boneIndex then
                    table.insert(boneIds, boneIndex)
                    table.insert(weights, weight / 0xFF)
                end
            end

            mesh:SetVertexBones(vertexId, boneIds)
            mesh:SetVertexBoneWeights(vertexId, weights)
        end

        vertData[i] = {
            UV = uvId,
            Normal = normalId,
            Position = vertexId,
            Color = colorId,
        }
    end

    local faceNormals = table.create(3, 0)
    local faceColors = table.create(3, 0)
    local faceVerts = table.create(3, 0)
    local faceUVs = table.create(3, 0)

    for i, face in faces do
        for v, vertId in ipairs(face) do
            local data = vertData[vertId]
            faceVerts[v] = data.Position
            faceNormals[v] = data.Normal
            faceColors[v] = data.Color
            faceUVs[v] = data.UV
        end

        local a, b, c = table.unpack(faceVerts)
        local faceId = mesh:AddTriangle(a, b, c)

        mesh:SetFaceVertices(faceId, faceVerts)
        mesh:SetFaceNormals(faceId, faceNormals)
        mesh:SetFaceColors(faceId, faceColors)
        mesh:SetFaceUVs(faceId, faceUVs)
    end

    mesh:RemoveUnused()
    return mesh
end

--- Loads a mesh from an asset ID by fetching the binary data from an asset web proxy.
function RobloxMesh.fromAssetId(assetId: number): Class
    local url = string.format(ASSET_PROXY, assetId)
    local bin

    if Players.LocalPlayer and not RunContext.IsEdit then
        local getMeshBinary = ReplicatedStorage:FindFirstChild("GetMeshBinary", true)
        assert(getMeshBinary and getMeshBinary:IsA("RemoteFunction"), "GetMeshBinary RemoteFunction not found")

        local buf = getMeshBinary:InvokeServer(assetId)
        bin = buffer.tostring(buf)
    else
        bin = HttpService:GetAsync(url, true)
    end

    return RobloxMesh.new(bin)
end

--- Loads a mesh from an asset URL by extracting the asset ID and fetching the binary data from an asset web proxy.
function RobloxMesh.fromAsset(asset: string): Class
    local assetId = tonumber(asset:match("%d+$"))
    assert(assetId, "invalid asset")

    return RobloxMesh.fromAssetId(assetId)
end

--- Loads a mesh from a binary buffer, which can be obtained from an asset web proxy or other sources.
function RobloxMesh.fromBuffer(buf: buffer): Class
    local bin = buffer.tostring(buf)
    return RobloxMesh.new(bin)
end

--- Creates an empty mesh with no vertices or faces, but with the necessary structure to be populated later.
function RobloxMesh.empty(): Class
    return setmetatable({
        LODs = { {} },
        Verts = {},
    }, RobloxMesh)
end

--- Sets the URL format for the asset web proxy used to fetch mesh data. 
--- The URL format must contain a '%i' format specifier, which will be replaced with the asset ID when fetching a mesh.
function RobloxMesh.SetProxyUrl(urlFormat: string)
    if not urlFormat:find("%%i") then
        error("Web Proxy URL must contain a '%i' format specifier.", 2)
    end

    ASSET_PROXY = urlFormat
end

return RobloxMesh