-- Partial implementation of Google's DRACO mesh compression format.
-- This only implements the bare minimum needed to decode the meshes Roblox is using, and is not a full implementation of the DRACO spec.

-- MAJOR PROPS to AntiBoomz for going through the effort of working
-- through Draco's spec/C++ source and figuring out what Roblox was using.

-- This is largely just a Luau port of their JavaScript implementation:
-- https://github.com/AntiBoomz/BTRoblox/blob/master/js/rbx/DracoStream/DracoBitstream.js

--!strict
local RobloxMesh = script.Parent

local Buffer = require(RobloxMesh.Buffer)
type Buffer = Buffer.Class

local Rans = require(script.Rans)
local Debug = require(script.Debug)
local Constants = require(script.Constants)
local MetadataFlagMask = Constants.MetadataConstants.FlagMask

local DataTypes = Constants.DataTypes
local DataSizes = Constants.DataSizes
local MeshEncoderType = Constants.MeshEncoderType
local MeshEncodingMethod = Constants.MeshEncodingMethod
local SymbolEncodingMethod = Constants.SymbolEncodingMethod
local PredictionEncodingMethod = Constants.PredictionEncodingMethod
local PredictionSchemeTransformMethod = Constants.PredictionSchemeTransformMethod
local SequentialIndicesEncodingMethod = Constants.SequentialIndicesEncodingMethod
local SequentialAttributeEncodingMethod = Constants.SequentialAttributeEncodingMethod

local DracoStream = {}
DracoStream.__index = DracoStream

type Rans = Rans.Class

type Attribute = {
    AttributeType: number,
    DataType: number,
    NumComponents: number,
    Normalized: number,
    UniqueId: number,
    DecoderType: number,
    Output: { number },

    PredictionScheme: number?,
    PredictionTransformType: number?,

    MinValues: { number }?,
    MaxValueDf: number?,

    QuantizationBits: number?,
    CompressedValue: number?,

    OctaMaxQ: number?,
    WrapMin: number?,
    WrapMax: number?,
}

type Decoder = {
    Attributes: { Attribute },
    PointIds: { number },
    Index: number,

    DataId: number?,
    DecoderType: number?,
    TraversalMethod: number?,
}

export type DracoStream = typeof(setmetatable({} :: {
    ConnectivityMethod: number,
    Faces: { number },

    NumPoints: number,
    NumFaces: number,

    Rans: Rans,
    Decoders: { Decoder },
    Attributes: { Attribute },
}, DracoStream))

local I8 = Buffer.ReadInt8
local U8 = Buffer.ReadUInt8
local I32 = Buffer.ReadInt32
local U16 = Buffer.ReadUInt16
local U32 = Buffer.ReadUInt32
local F32 = Buffer.ReadFloat32
local LEB128 = Buffer.ReadVarInt

export type AttributeType = 
    | "Position"
    | "Normal"
    | "Color"
    | "TexCoord"
    | "Generic"

type Reader<T... = (number)> = (Buffer) -> T...

local function parseHeader(buf: Buffer)
    local magic = buf:ReadString(5)

    if magic ~= "DRACO" then
        Debug.Error("Not a valid draco mesh!")
    end

    local majorVersion = U8(buf)
    local minorVersion = U8(buf)

    local encoderType = U8(buf)
    local encoderMethod = U8(buf)

    local flags = U16(buf)

    return {
        majorVersion = majorVersion,
        minorVersion = minorVersion,
        encoderType = encoderType,
        encoderMethod = encoderMethod,
        flags = flags
    }
end

local function decodeConnectivityData(buf: Buffer, stream: DracoStream, encoderMethod: number)
    -- DecodeConnectivityData
    if encoderMethod == MeshEncodingMethod.Sequential then
        local numFaces = LEB128(buf) 
        stream.NumFaces = numFaces

        local numPoints = LEB128(buf)
        stream.NumPoints = numPoints

        local connectivityMethod = U8(buf)
        stream.ConnectivityMethod = connectivityMethod

        local faces = table.create(numFaces * 3)
        stream.Faces = faces

        if (connectivityMethod == SequentialIndicesEncodingMethod.Compressed) then
            Debug.Error("SequentialIndicesEncodingMethod.Compressed not implemented!")
        elseif (connectivityMethod == SequentialIndicesEncodingMethod.Uncompressed) then
            local readFunc: Reader =
                if numPoints < 256 then U8
                elseif numPoints < bit32.lshift(1, 16) then U16
                elseif numPoints < bit32.lshift(1, 21) then LEB128
                else U32

            for i = 1, numFaces do
                faces[(i - 1) * 3 + 1] = readFunc(buf)
                faces[(i - 1) * 3 + 2] = readFunc(buf)
                faces[(i - 1) * 3 + 3] = readFunc(buf)
            end
        end
    elseif encoderMethod == MeshEncodingMethod.EdgeBreaker then
        Debug.Error("Edgebreaker not implemented")
    else
        Debug.Error(`EncoderMethod {Debug.NameOf(MeshEncodingMethod, encoderMethod)} not implemented!`)
    end
end

local function generateSequence(stream: DracoStream, encoderMethod: number)
    -- GenerateSequence
    if encoderMethod == MeshEncodingMethod.Sequential then
        local decoders = stream.Decoders

        for _, decoder in ipairs(decoders) do
            local numPoints = stream.NumPoints
            
            local pointIds = table.create(numPoints)
            decoder.PointIds = pointIds
            
            for i = 1, numPoints do
                pointIds[i] = i - 1
            end
        end
    elseif encoderMethod == MeshEncodingMethod.EdgeBreaker then
        Debug.Error("Edgebreaker not implemented")
    end
end

local function decodeAttributeGeneric(buf: Buffer, stream: DracoStream, decoder: Decoder, attribute: Attribute)
    Debug.Print("decodeAttributeGeneric")
    Debug.StackOpen()

    local startPos = buf:GetPosition()
    local pointIds = decoder.PointIds
    local numEntries = #pointIds

    local numComponents = attribute.NumComponents
    local numValues = numEntries * numComponents

    local output = table.create(numValues)
    local size = DataSizes[attribute.DataType]
    
    Debug.Print(`numComponents={numComponents}, numEntries={numEntries}, numValues={numValues}, dataType={Debug.NameOf(DataTypes, attribute.DataType)}, size={size}`)
    Debug.Print(`Starting position: {startPos}, expected bytes to read: {numValues * size}`)
    Debug.PrintBufferState(buf)

    local readFunc: Reader =
        if size == 1 then U8
        elseif size == 2 then U16
        elseif size == 4 then U32
        else error("invalid/unsupported generic attribute data type")
    
    for k = 1, numValues do
        output[k] = readFunc(buf)
    end

    local endPos = buf:GetPosition()
    local bytesRead = endPos - startPos
    Debug.Print(`Ending position: {endPos}, bytes read: {bytesRead}, expected: {numValues * size}`)

    attribute.Output = output
    Debug.StackClose()
end

local function decodeSymbols(buf: Buffer, stream: DracoStream, numValues: number, numComponents: number, output: { number })
    -- symbol_decoding.cc - DecodeSymbols
    local scheme = U8(buf)
    local rans = stream.Rans

    Debug.StackOpen()
    Debug.Print(`decodeSymbols | scheme={scheme}, numValues={numValues}, numComponents={numComponents}`)

    if scheme == SymbolEncodingMethod.TaggedSymbols then
        rans:InitSymbols(buf, 5)

        for i = 1, numValues, numComponents do
            local numBits = rans:ReadSymbol()
            --Debug.Print(`readSymbol {i} | numBits={numBits}`)
            --Debug.StackOpen()

            for j = 0, numComponents - 1 do
                local value = buf:ReadBits(numBits)
                --Debug.Print(`readBits output[{i + j}] ({i}, {j}) | value={value}`)
                output[i + j] = value
            end

            --Debug.StackClose()
        end

        buf:FlushBits()
    elseif scheme == SymbolEncodingMethod.RawSymbols then
        local maxBitLength = U8(buf)
        rans:InitSymbols(buf, maxBitLength)

        for i = 1, numValues do
            output[i] = rans:ReadSymbol()
        end
    end

    Debug.StackClose()
end
    
local function decodePredictionData(
    buf: Buffer,
    attribute: Attribute,
    predictionScheme: number,
    predictionTransformType: number?)
    -- DecodePredictionData
    
    if predictionScheme == PredictionEncodingMethod.ConstrainedMultiParallelogram then
        Debug.Error("Edgebreaker not implemented, cannot decode ConstrainedMultiParallelogram prediction scheme")
    elseif predictionScheme == PredictionEncodingMethod.TexCoordsPortable then
        Debug.Error("Edgebreaker not implemented, cannot decode TexCoordsPortable prediction scheme")
    end
    
    -- DecodeTransformData
    if predictionTransformType == PredictionSchemeTransformMethod.Wrap then
        attribute.WrapMin = I32(buf)
        attribute.WrapMax = I32(buf)
    elseif predictionTransformType == PredictionSchemeTransformMethod.NormalOctahedronCanonicalized then
        attribute.OctaMaxQ = I32(buf)
        I32(buf) -- unused
    end
    
    -- DecodePredictionData
    if predictionScheme == PredictionEncodingMethod.GeometricNormal then
        Debug.Error("Edgebreaker not implemented, cannot decode GeometricNormal prediction scheme")
    end    
end

local function getRotationCount(pred: Vector2)
    local sign_x = pred.X
    local sign_y = pred.Y
    local rotation_count = 0
    
    if sign_x == 0 then
        if sign_y == 0 then
            rotation_count = 0
        elseif sign_y > 0 then
            rotation_count = 3
        else
            rotation_count = 1
        end
    elseif sign_x > 0 then
        if sign_y >= 0 then
            rotation_count = 2
        else
            rotation_count = 1
        end
    else
        if sign_y <= 0 then
            rotation_count = 0
        else
            rotation_count = 3
        end
    end
    
    return rotation_count
end

local function rotatePoint(point: Vector2, rotationCount: number)
    if rotationCount == 1 then
        return Vector2.new(point.Y, -point.X)
    elseif rotationCount == 2 then
        return Vector2.new(-point.X, -point.Y)
    elseif rotationCount == 3 then
        return Vector2.new(-point.Y, point.X)
    else
        return point
    end
end

local function addAsUnsigned(a: number, b: number)
    local ua = if a >= 0 then a else 4294967296 + a
    local ub = if b >= 0 then b else 4294967296 + b
    return bit32.band(ua + ub, 0xFFFFFFFF)
end

local function quantizedOctahedralToNormal(s: number, t: number, bits: number?)
    if not bits then
        return Vector3.yAxis
    end

    local maxValue = bit32.lshift(1, bits) - 2
    local dequantizationScale = 2 / maxValue

    local y = s * dequantizationScale - 1
    local z = t * dequantizationScale - 1
    local x = 1 - math.abs(y) - math.abs(z)

    local x_offset = -x
    x_offset = x_offset < 0 and 0 or x_offset

    y += y < 0 and x_offset or -x_offset
    z += z < 0 and x_offset or -x_offset
    
    local vec = Vector3.new(x, y, z)
    local normSquared = x * x + y * y + z * z

    if normSquared > 1e-6 then
        return vec.Unit
    end

    return Vector3.yAxis
end

local function computeOriginalValues(
    stream: DracoStream,
    decoder: Decoder,
    attribute: Attribute,
    numValues: number,
    numComponents: number, 
    predictionScheme: number,
    predictionTransformType: number?, 
    output: { number }
): ()
    local computeOriginalValue: (
        predictedArray: { number },
        predictedIndex: number, 
        corrArray: { number },
        corrIndex: number, 
        outputArray: { number }, 
        outputIndex: number
    ) -> ()

    if predictionTransformType == PredictionSchemeTransformMethod.Wrap then
        local wrapMax = attribute.WrapMax or 0
        local wrapMin = attribute.WrapMin or 0
        local maxDif = 1 + wrapMax - wrapMin
        
        computeOriginalValue = function (predictedArray, predictedIndex, corrArray, corrIndex, outputArray, outputIndex)
            for i = 0, numComponents - 1 do
                local value = math.max(wrapMin, math.min(wrapMax, predictedArray[predictedIndex + i + 1])) + corrArray[corrIndex + i + 1]
                
                if value > wrapMax then
                    value -= maxDif
                elseif value < wrapMin then 
                    value += maxDif
                end
                
                outputArray[outputIndex + i + 1] = value
            end
        end
    elseif predictionTransformType == PredictionSchemeTransformMethod.NormalOctahedronCanonicalized then
        local maxQuantizedValue = bit32.lshift(1, attribute.OctaMaxQ or 0) - 1
        local maxValue = maxQuantizedValue - 1
        local centerValue = maxValue / 2
        
        local invertDiamond = function (s: number, t: number)
            local sign_s, sign_t
            
            if s >= 0 and t >= 0 then
                sign_s = 1
                sign_t = 1
            elseif s <= 0 and t <= 0 then
                sign_s = -1
                sign_t = -1
            else
                sign_s = (s > 0) and 1 or -1
                sign_t = (t > 0) and 1 or -1
            end
            
            local corner_point_s = sign_s * centerValue
            local corner_point_t = sign_t * centerValue
            
            local us = t + t - corner_point_t
            local ut = s + s - corner_point_s
            
            if sign_s * sign_t >= 0 then
                us = -us
                ut = -ut
            end
            
            return Vector2.new(
                (us + corner_point_s) / 2,
                (ut + corner_point_t) / 2
            )
        end
        
        local modMax = function (x: number)
            return x > centerValue and x - maxQuantizedValue
                    or x < -centerValue and x + maxQuantizedValue
                    or x
        end
        
        computeOriginalValue = function (predictedArray, predictedIndex, corrArray, corrIndex,  outputArray, outputIndex)
            local pred = Vector2.new(
                predictedArray[predictedIndex + 1] - centerValue,
                predictedArray[predictedIndex + 2] - centerValue
            )
            
            local corr = Vector2.new(
                corrArray[corrIndex + 1],
                corrArray[corrIndex + 2]
            )
            
            local isInDiamond = math.abs(pred.X) + math.abs(pred.Y) <= centerValue
            
            if not isInDiamond then
                pred = invertDiamond(pred.X, pred.Y)
            end
            
            local isInBottomLeft = (pred.X == 0 and pred.Y == 0) or (pred.X < 0 and pred.Y <= 0)
            local rotationCount = getRotationCount(pred)
            
            if not isInBottomLeft then
                pred = rotatePoint(pred, rotationCount)
            end
            
            local orig = Vector2.new(
                modMax(addAsUnsigned(pred.X, corr.X)),
                modMax(addAsUnsigned(pred.Y, corr.Y))
            )
            
            if not isInBottomLeft then
                orig = rotatePoint(orig, (4 - rotationCount) % 4)
            end
            
            if not isInDiamond then
                orig = invertDiamond(orig.X, orig.Y)
            end
            
            outputArray[outputIndex + 1] = orig.X + centerValue
            outputArray[outputIndex + 2] = orig.Y + centerValue
        end
    else
        computeOriginalValue = function (predictedArray, predictedIndex, corrArray, corrIndex,  outputArray, outputIndex)
            for i = 1, numComponents do
                outputArray[outputIndex + i] = predictedArray[predictedIndex + i] + corrArray[corrIndex + i]
            end
        end
    end

    if predictionScheme == PredictionEncodingMethod.Difference then
        local zeroValues = table.create(numComponents, 0)
        
        -- Decode the original value for the first element.
        computeOriginalValue(zeroValues, 0, output, 0, output, 0)
        
        -- Decode data from the front using D(i) = D(i) + D(i - 1).
        for i = numComponents, numValues - 1, numComponents do
            computeOriginalValue(output, i - numComponents, output, i, output, i)
        end
    elseif predictionScheme == PredictionEncodingMethod.Parallelogram then
        Debug.Error("Edgebreaker not implemented, cannot decode Parallelogram prediction scheme")
    elseif predictionScheme == PredictionEncodingMethod.ConstrainedMultiParallelogram then
        Debug.Error("Edgebreaker not implemented, cannot decode ConstrainedMultiParallelogram prediction scheme")
    elseif predictionScheme == PredictionEncodingMethod.TexCoordsPortable then
        Debug.Error("Edgebreaker not implemented, cannot decode TexCoordsPortable prediction scheme")
    elseif predictionScheme == PredictionEncodingMethod.GeometricNormal then
        Debug.Error("Edgebreaker not implemented, cannot decode GeometricNormal prediction scheme")
    end
end
    
local function decodePortableAttributeTransformData(buf: Buffer, decoder: Decoder, attribute: Attribute, decoderType: number)
    -- DecodeDataNeededByPortableTransforms
    -- This reads the transform parameters from the buffer
    if decoderType == SequentialAttributeEncodingMethod.Quantization then
        -- SequentialQuantizationAttributeDecoder::DecodeQuantizedDataInfo()
        -- AttributeQuantizationTransform::DecodeParameters
        local numComponents = attribute.NumComponents
        local minValues = {}
        
        for i = 1, numComponents do
            minValues[i] = F32(buf)
        end

        local range = F32(buf)
        local quantizationBits = U8(buf)
        
        attribute.MinValues = minValues
        attribute.MaxValueDf = range
        attribute.QuantizationBits = quantizationBits
    elseif decoderType == SequentialAttributeEncodingMethod.Normals then
        -- Read quantization bits for normal octahedron
        local quantizationBits = U8(buf)
        attribute.QuantizationBits = quantizationBits
    end
end

local function transformAttributeQuantized(decoder: Decoder, attribute: Attribute)
    -- TransformAttributesToOriginalFormat - Quantization
    -- Uses parameters already read by decodePortableAttributeTransformData

    local numComponents = attribute.NumComponents
    local pointIds = decoder.PointIds
    local numValues = #pointIds * numComponents
    local output = attribute.Output

    local minValues = attribute.MinValues or {}
    local range = attribute.MaxValueDf or 0
    local quantizationBits = attribute.QuantizationBits or 0
    
    local maxQuantizedValue = bit32.lshift(1, quantizationBits) - 1
    local delta = range / maxQuantizedValue
    
    for i = 1, numValues, numComponents do
        for j = 1, numComponents do
            output[i + j - 1] = minValues[j] + output[i + j - 1] * delta
        end
    end
end

local function transformAttributeNormals(decoder: Decoder, attribute: Attribute)
    -- TransformAttributesToOriginalFormat - Normals
    -- Uses parameters already read by decodePortableAttributeTransformData

    local pointIds = decoder.PointIds
    local numValues = #pointIds * 2
    local input = attribute.Output

    local output = table.create(numValues * 3 / 2)
    attribute.Output = output

    local quantizationBits = attribute.QuantizationBits
    local outputIndex = 1

    for i = 1, numValues, 2 do
        local s = input[i]
        local t = input[i + 1]
        local norm = quantizedOctahedralToNormal(s, t, quantizationBits)

        output[outputIndex] = norm.X
        output[outputIndex + 1] = norm.Y
        output[outputIndex + 2] = norm.Z

        outputIndex += 3
    end
end

local function transformAttributeGeneric(stream: DracoStream, decoder: Decoder, attribute: Attribute)
    local output = attribute.Output

    if attribute.DataType == DataTypes.F32 then -- DT_FLOAT32
        for i = 1, #output do
            local value = output[i]
            local buf = buffer.create(4)

            buffer.writeu32(buf, 0, value)
            output[i] = buffer.readf32(buf, 0)
        end
    elseif attribute.DataType == DataTypes.Bool then -- DT_BOOL
        for i = 1, #output do
            output[i] = output[i] > 0 and 1 or 0
        end
    end
end

local function decodeAttributeData(buf: Buffer, stream: DracoStream, encoderMethod: number)
    -- DecodeAttributeData
    local decoders = stream.Decoders
    local numAttributeDecoders = U8(buf)
    Debug.Print(`DecodeAttributeData: numAttributeDecoders = {numAttributeDecoders}`)

    for i = 1, numAttributeDecoders do
        decoders[i] = {
            Attributes = {},
            PointIds = {},
            Index = i,
        }
    end

    if (encoderMethod == MeshEncodingMethod.EdgeBreaker) then
        for _, decoder in ipairs(decoders) do
            decoder.DataId = U8(buf)
            decoder.DecoderType = U8(buf)
            decoder.TraversalMethod = U8(buf)
        end
    end

    for _, decoder in ipairs(decoders) do
        local numAttributes = LEB128(buf)
        Debug.Print(`Decoder {decoder.Index}: numAttributes = {numAttributes}`)

        local attributes = table.create(numAttributes)
        decoder.Attributes = attributes

        for j = 1, numAttributes do
            local attributeType = U8(buf)
            local dataType = U8(buf)
            local numComponents = U8(buf)
            local normalized = U8(buf)
            local uniqueId = LEB128(buf)
            
            attributes[j] = {
                AttributeType = attributeType,
                DataType = dataType,
                NumComponents = numComponents,
                Normalized = normalized,
                UniqueId = uniqueId,
                DecoderType = 0,
                Output = {},
            }
        end
        
        for _, attribute in ipairs(attributes) do
            attribute.DecoderType = U8(buf)
        end
    end
end

local function decodeAttributeCompressed(buf: Buffer, stream: DracoStream, decoder: Decoder, attribute: Attribute, decoderType: number)
    local startPos = buf:GetPosition()
    Debug.Print(`decodeAttributeCompressed starting at position: {startPos}`)

    local scheme = U8(buf)
    Debug.Print(`Read prediction scheme: {Debug.NameOf(PredictionEncodingMethod, scheme)}`)
    Debug.PrintBufferState(buf)

    attribute.PredictionScheme = scheme

    local transformType = if scheme ~= PredictionEncodingMethod.None
        then I8(buf)
        else nil

    Debug.Print(`Read prediction transform type: {Debug.NameOf(PredictionSchemeTransformMethod, transformType)}`)
    Debug.PrintBufferState(buf)

    local compressed = U8(buf)
    Debug.Print(`Read compressed flag: {compressed}`)
    Debug.PrintBufferState(buf)

    local numEntries = #decoder.PointIds
    local numComponents = attribute.NumComponents

    if decoderType == SequentialAttributeEncodingMethod.Normals and scheme == PredictionEncodingMethod.Difference then
        numComponents = 2
    end

    local numValues = numEntries * numComponents
    local output = table.create(numValues, 0)

    attribute.Output = output
    attribute.PredictionTransformType = transformType

    if compressed > 0 then
        decodeSymbols(buf, stream, numValues, numComponents, output)
    else
        local size = U8(buf)

        local readFunc: Reader =
            if size == 1 then U8
            elseif size == 2 then U16
            elseif size == 4 then U32
            else error("invalid/unsupported compressed attribute data type")

        for i = 1, numValues do
            output[i] = readFunc(buf)
        end
    end

    -- Convert the values back to the original signed format
    if numValues > 0 and transformType ~= PredictionSchemeTransformMethod.NormalOctahedronCanonicalized then
        for i = 1, numValues do
            local value = output[i]
            output[i] = if value % 2 == 0 then value // 2 else -(value + 1) // 2
        end
    end

    if scheme ~= PredictionEncodingMethod.None then
        decodePredictionData(buf, attribute, scheme, transformType)

        if numValues > 0 then
            computeOriginalValues(stream, decoder, attribute, numValues, numComponents, scheme, transformType, output)
        end
    end
end

local function decodeAttributes(buf: Buffer, stream: DracoStream)
    -- initialize rans
    stream.Rans = Rans.new()

    -- initialize values for bits methods
    Debug.Print(`DecodeAttributes: Processing {#stream.Decoders} decoders`)
    buf:FlushBits()

    for _, decoder in stream.Decoders do
        -- SequentialAttributeDecodersController::DecodePortableAttributes()
        Debug.Print(`Processing decoder {decoder.Index} with {#decoder.Attributes} attributes`)

        for _, attribute in decoder.Attributes do
            local decoderType = attribute.DecoderType
            Debug.Print(`Decoding attribute with decoderType {Debug.NameOf(SequentialAttributeEncodingMethod, decoderType)}, uniqueId {attribute.UniqueId}, numComponents {attribute.NumComponents}, dataType {Debug.NameOf(DataTypes, attribute.DataType)}, normalized {attribute.Normalized}`)
            Debug.Print(`Buffer position before decode: {buf:GetPosition()}`)
            Debug.StackOpen()

            if decoderType == SequentialAttributeEncodingMethod.Generic then
                decodeAttributeGeneric(buf, stream, decoder, attribute)
            else
                decodeAttributeCompressed(buf, stream, decoder, attribute, decoderType)
            end

            Debug.StackClose()
            Debug.Print(`Buffer position after decode: {buf:GetPosition()}`)
        end

        Debug.Print(`Reading portable transform data at buffer position: {buf:GetPosition()}`)

        for _, attribute in decoder.Attributes do
            local decoderType = attribute.DecoderType

            if decoderType == SequentialAttributeEncodingMethod.Quantization or decoderType == SequentialAttributeEncodingMethod.Normals then
                Debug.Print(`Reading transform data for attribute {attribute.UniqueId}, decoderType {Debug.NameOf(SequentialAttributeEncodingMethod, decoderType)}`)
                Debug.StackOpen()

                local beforePos = buf:GetPosition()
                decodePortableAttributeTransformData(buf, decoder, attribute, decoderType)

                local afterPos = buf:GetPosition()
                Debug.Print(`Read {afterPos - beforePos} bytes of transform data`)

                Debug.StackClose()
            end
        end

        Debug.Print(`Finished reading portable transform data at buffer position: {buf:GetPosition()}`)

        -- TransformAttributesToOriginalFormat()

        for _, attribute in decoder.Attributes do
            local decoderType = attribute.DecoderType
            Debug.Print(`Transforming attribute with decoderType {Debug.NameOf(SequentialAttributeEncodingMethod, decoderType)}, uniqueId {attribute.UniqueId}, numComponents {attribute.NumComponents}, dataType {Debug.NameOf(DataTypes, attribute.DataType)}, normalized {attribute.Normalized}`)

            if decoderType == SequentialAttributeEncodingMethod.Quantization then
                transformAttributeQuantized(decoder, attribute)
            elseif decoderType == SequentialAttributeEncodingMethod.Normals then
                transformAttributeNormals(decoder, attribute)
            else
                transformAttributeGeneric(stream, decoder, attribute)
            end
            
            Debug.Print(`Sample of transformed attribute output: {attribute.Output[1]}, {attribute.Output[2]}, {attribute.Output[3]}, ..., {attribute.Output[#attribute.Output - 2]}, {attribute.Output[#attribute.Output - 1]}, {attribute.Output[#attribute.Output]}`)
        end
    end
end

local function readStream(buf: Buffer): DracoStream
    local stream = setmetatable({
        Faces = {},
        NumFaces = 0,
        NumPoints = 0,
        ConnectivityMethod = 0,

        Decoders = {},
        Attributes = {},
        Rans = Rans.new(),
    }, DracoStream)
    
    local header = parseHeader(buf)
    Debug.Print(`{header.majorVersion}.{header.minorVersion} | encoderType = {header.encoderType}, encoderMethod = {header.encoderMethod}, flags = {header.flags}`)

    if header.encoderType ~= MeshEncoderType.TriangularMesh then
        Debug.Error(`EncoderType {Debug.NameOf(MeshEncoderType, header.encoderType)} not implemented!`)
    end

    -- DecodeMetadata
    if bit32.btest(header.flags, MetadataFlagMask) then
        Debug.Error("Metadata not implemented!")
    end

    -- DecodeConnectivityData
    decodeConnectivityData(buf, stream, header.encoderMethod)

    -- DecodeAttributeData
    decodeAttributeData(buf, stream, header.encoderMethod)

    -- GenerateSequence
    generateSequence(stream, header.encoderMethod)

    -- DecodeAttributes
    decodeAttributes(buf, stream)
    stream.Attributes = stream.Decoders[#stream.Decoders].Attributes

    return stream
end

function DracoStream.FindAttributeByUniqueId(self: DracoStream, uniqueId: number): Attribute?
    for _, attribute in self.Attributes do
        if attribute.UniqueId == uniqueId then
            return attribute
        end
    end
    
    return nil
end

function DracoStream.FindFirstAttributeByType(self: DracoStream, attributeType: number | AttributeType): Attribute?
    local id = if typeof(attributeType) == "string"
        then Constants.AttributeTypes[attributeType]
        else attributeType

    for i, attribute in self.Attributes do
        if attribute.AttributeType == id then
            return attribute
        end
    end
    
    return nil
end

function DracoStream.ComponentsOf(self: DracoStream, target: Attribute | AttributeType | number): () -> ...number
    local maybeAttribute = 
        if typeof(target) == "number" then
            self:FindAttributeByUniqueId(target)
        elseif typeof(target) == "string" then
            self:FindFirstAttributeByType(target)
        else
            target
    
    local attribute: Attribute = Debug.Assert(maybeAttribute, `Attribute '{target}' not found!`)
    local numComponents = attribute.NumComponents
    local components = attribute.Output
    local at = 1
    
    return function ()
        if at > #components then
            return
        end

        local current = at
        at += numComponents

        return table.unpack(components, current, at - 1)
    end
end

return table.freeze({
    AttributeTypes = Constants.AttributeTypes,
    ReadStream = readStream,
    Constants = Constants,
})