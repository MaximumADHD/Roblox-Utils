local CONST = table.freeze

return CONST({
    MeshEncoderType = CONST({
        Invalid = -1,
        PointCloud = 0,
        TriangularMesh = 1,
    }),
    
    MeshEncodingMethod = CONST({
        Sequential = 0,
        EdgeBreaker = 1,
    }),

    MetadataConstants = CONST({
        FlagMask = 0x8000,
    }),

    SequentialAttributeEncodingMethod = CONST({
        Generic = 0,
        Integer = 1,
        Quantization = 2,
        Normals = 3,
    }),

    SequentialIndicesEncodingMethod = CONST({
        Compressed = 0,
        Uncompressed = 1,
    }),

    PredictionEncodingMethod = CONST({
        None = -2,
        Difference = 0,
        Parallelogram = 1,
        ConstrainedMultiParallelogram = 4,
        TexCoordsPortable = 5,
        GeometricNormal = 6,
    }),

    PredictionSchemeTransformMethod = CONST({
        Wrap = 1,
        NormalOctahedronCanonicalized = 3,
    }),

    MeshTraversalMethod = CONST({
        DepthFirst = 0,
        PredictionDegree = 1,
    }),

    MeshAttributeEncodingMethod = CONST({
        VertexAttribute = 0,
        CornerAttribute = 1,
    }),

    EdgeBreakerEncodingMethod = CONST({
        Standard = 0,
        Valence = 2,
    }),

    EdgeBreakerConstants = CONST({
        InvalidCornerIndex = -1,
        LeftFaceEdge = 0,
        RightFaceEdge = 1,
        TexCoordsNumComponents = 2,
        MaxNumParallelograms = 4,
        MaxPriority = 3,
    }),

    EdgeBreakerBitPatternConstants = CONST({
        TopologyC = 0,
        TopologyS = 1,
        TopologyL = 3,
        TopologyR = 5,
        TopologyE = 7,
    }),

    ValenceEdgeBreakerConstants = CONST({
        MinValence = 2,
        MaxValence = 7,
        NumUniqueValences = 6,
    }),

    ANSConstants = CONST({
        RAbsAnsP8Precision = 256,
        RAbsAnsP10Precision = 1024,
        RAbsLBase = 4096,
        IOBase = 256,
        LRansBase = 4096,
        TaggedRansBase = 16384,
        TaggedRansPrecision = 4096,
    }),

    SymbolEncodingMethod = CONST({
        TaggedSymbols = 0,
        RawSymbols = 1,
    }),

    AttributeTypes = CONST({
        Position = 0,
        Normal = 1,
        Color = 2,
        TexCoord = 3,
        Generic = 4,
    }),

    DataTypes = CONST({
        INVALID = 0,
        I8 = 1,
        U8 = 2,
        I16 = 3,
        U16 = 4,
        I32 = 5,
        U32 = 6,
        I64 = 7,
        U64 = 8,
        F32 = 9,
        F64 = 10,
        Bool = 11,
    }),

    DataSizes = CONST({
        [0] = 0, -- INVALID
        [1] = 1, -- I8
        [2] = 1, -- U8
        [3] = 2, -- I16
        [4] = 2, -- U16
        [5] = 4, -- I32
        [6] = 4, -- U32
        [7] = 8, -- I64
        [8] = 8, -- U64
        [9] = 4, -- F32
        [10] = 8, -- F64
        [11] = 1, -- Bool
    })
})