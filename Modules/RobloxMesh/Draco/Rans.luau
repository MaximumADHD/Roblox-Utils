local Draco = script.Parent
local RobloxMesh = Draco.Parent

local Buffer = require(RobloxMesh.Buffer)
local Debug = require(Draco.Debug)

local Rans = {}
Rans.__index = Rans

type ProbEnt = {
    prob: number,
    cumProb: number,
}

export type BitState = {
    BitsValue: number,
    BitsLength: number,
}

export type Class = typeof(setmetatable({} :: {
    ProbabilityTable: { ProbEnt },
    LookupTable: { number },
    RawBuf: buffer?,
    StartPos: number,

    Offset: number,
    Base: number,
    Precision: number,
    State: number,
    ProbZero: number,
}, Rans))

local U8 = Buffer.ReadUInt8
local LEB128 = Buffer.ReadVarInt

local debugPrint = Debug.Print
type Buffer = Buffer.Class

local function newRans(): Class
    return setmetatable({
        ProbabilityTable = {},
        LookupTable = {},

        RawBuf = nil,
        StartPos = 0,
        Offset = 1,

        Base = 0,
        Precision = 0,

        State = 0,
        ProbZero = 0,
    }, Rans)
end

local function decodeTables(self: Class, buf: Buffer, expectedCumProb: number)
    local startPos = buf:GetPosition()
    local numSymbols = LEB128(buf)
    
    local probabilityTable: { ProbEnt } = {}
    local lookupTable: { number } = {}

    local cumProb = 0
    local actProb = 0
    local i = 0

    while i < numSymbols do
        local data = U8(buf)
        local token = bit32.band(data, 3)

        if token == 3 then
            local offset = bit32.rshift(data, 2)

            for j = 0, offset do
                probabilityTable[i + j + 1] = {prob = 0, cumProb = cumProb }
            end

            i += offset + 1
        else
            local prob = bit32.rshift(data, 2)

            for j = 0, token - 1 do
                local eb = U8(buf)
                prob = bit32.bor(prob, bit32.lshift(eb, 8 * (j + 1) - 2))
            end

            probabilityTable[i + 1] = {
                prob = prob,
                cumProb = cumProb
            }

            cumProb += prob

            for j = actProb, cumProb - 1 do
                lookupTable[j + 1] = i
            end

            actProb = cumProb
            i += 1
        end
    end

    self.ProbabilityTable = probabilityTable
    self.LookupTable = lookupTable

    local endPos = buf:GetPosition()
    debugPrint(`decodeTables consumed {endPos - startPos} bytes for {numSymbols} symbols, and expected cumProb {expectedCumProb}, actual cumProb {cumProb}`)
end

local function start(self: Class, rawBuf: buffer, startPos: number, dataSize: number, base: number, precision: number)
    local offset = dataSize
    local lastByte = buffer.readu8(rawBuf, startPos + offset - 1)
    local x = bit32.rshift(lastByte, 6)

    if x == 0 then
        self.Offset = offset - 1
        self.State = bit32.band(lastByte, 0x3F)
    elseif x == 1 then
        self.Offset = offset - 2
        self.State = bit32.band(
            bit32.bor(
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 1), 8),
                buffer.readu8(rawBuf, startPos + offset - 2)
            ),
            0x3FFF
        )
    elseif x == 2 then
        self.Offset = offset - 3
        self.State = bit32.band(
            bit32.bor(
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 1), 16),
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 2), 8),
                buffer.readu8(rawBuf, startPos + offset - 3)
            ),
            0x3FFFFF
        )
    elseif x == 3 then
        self.Offset = offset - 4
        self.State = bit32.band(
            bit32.bor(
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 1), 24),
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 2), 16),
                bit32.lshift(buffer.readu8(rawBuf, startPos + offset - 3), 8),
                buffer.readu8(rawBuf, startPos + offset - 4)
            ),
            0x3FFFFFFF
        )
    end

    self.RawBuf = rawBuf
    self.StartPos = startPos

    self.Base = base
    self.State += base
    self.Precision = precision
end

function Rans.ReadSymbol(self: Class): number
    while self.State < self.Base and self.Offset > 0 do
        self.Offset -= 1
        self.State = bit32.bor(
            bit32.lshift(self.State, 8),
            buffer.readu8(self.RawBuf :: buffer, self.StartPos + self.Offset)
        )
    end

    local quo = self.State // self.Precision
    local rem = self.State % self.Precision

    local symbol = self.LookupTable[rem + 1] or 0
    local probEntry = self.ProbabilityTable[symbol + 1]

    local prob = probEntry and probEntry.prob or 1
    local cumProb = probEntry and probEntry.cumProb or 0

    self.State = quo * prob + rem - cumProb
    return symbol
end

function Rans.InitSymbols(self: Class, buf: Buffer, bitLength: number)
    local precisionBits = (3 * bitLength) // 2
    precisionBits = math.clamp(precisionBits, 12, 20)
    
    local precision = bit32.lshift(1, precisionBits)
    local base = precision * 4
    
    decodeTables(self, buf, precision)
    
    local dataSize = LEB128(buf)
    local startPos = buf:GetPosition()
    local rawBuf = buf:GetBuffer()

    start(self, rawBuf, startPos, dataSize, base, precision)
    buf:Skip(dataSize)
end

return table.freeze({
    new = newRans,
})