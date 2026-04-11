local Implementation = script.Implementation
local Components = script.Components
local Handles = script.Handles
local Utility = script.Utility

local DraggerTool = require(Components.DraggerTool)
local DraggedPivot = require(Components.DraggedPivot)
local SelectionDot = require(Components.SelectionDot)
local MoveHandleView = require(Components.MoveHandleView)
local ScaleHandleView = require(Components.ScaleHandleView)
local RotateHandleView = require(Components.RotateHandleView)
local AnimatedHoverBox = require(Components.AnimatedHoverBox)
local SummonHandlesNote = require(Components.SummonHandlesNote)
local DragSelectionView = require(Components.DragSelectionView)
local SummonHandlesHider = require(Components.SummonHandlesHider)
local LocalSpaceIndicator = require(Components.LocalSpaceIndicator)
local StandaloneSelectionBox = require(Components.StandaloneSelectionBox)

local ExtrudeHandles = require(Handles.ExtrudeHandles)
local RotateHandles = require(Handles.RotateHandles)
local MoveHandles = require(Handles.MoveHandles)

local HoverTracker = require(Implementation.HoverTracker)
local DraggerContext = require(Implementation.DraggerContext)
local DraggerStateType = require(Implementation.DraggerStateType)
local DraggerToolModel = require(Implementation.DraggerToolModel)

local Math = require(Utility.Math)
local Colors = require(Utility.Colors)
local JointUtil = require(Utility.JointUtil)
local PartMover = require(Utility.PartMover)
local DragHelper = require(Utility.DragHelper)
local JointMaker = require(Utility.JointMaker)
local JointPairs = require(Utility.JointPairs)
local BoundingBox = require(Utility.BoundingBox)
local DragSelector = require(Utility.DragSelector)
local SelectionInfo = require(Utility.SelectionInfo)
local StandardCursor = require(Utility.StandardCursor)
local AttachmentMover = require(Utility.AttachmentMover)
local SelectionHelper = require(Utility.SelectionHelper)
local SelectionWrapper = require(Utility.SelectionWrapper)
local ViewChangeDetector = require(Utility.ViewChangeDetector)
local BoundsChangedTracker = require(Utility.BoundsChangedTracker)
local TemporaryTransparency = require(Utility.TemporaryTransparency)

local getGeometry = require(Utility.getGeometry)
local classifyPivot = require(Utility.classifyPivot)
local roundRotation = require(Utility.roundRotation)
local setInsertPoint = require(Utility.setInsertPoint)
local getFaceInstance = require(Utility.getFaceInstance)
local assertGoodCFrame = require(Utility.assertGoodCFrame)
local shouldDragAsFace = require(Utility.shouldDragAsFace)
local getBoundingBoxScale = require(Utility.getBoundingBoxScale)
local isProtectedInstance = require(Utility.isProtectedInstance)
local computeDraggedDistance = require(Utility.computeDraggedDistance)
local snapRotationToPrimaryDirection = require(Utility.snapRotationToPrimaryDirection)

export type DraggerStateType = DraggerStateType.StateType
export type DragTargetType = DragHelper.DragTargetType
export type DragTarget = DragHelper.DragTarget

export type PivotType = classifyPivot.PivotType
export type Geometry = getGeometry.Geometry
export type Surface = getGeometry.Surface
export type Vertex = getGeometry.Vertex
export type Shape = getGeometry.Shape
export type Edge = getGeometry.Edge
export type Face = getGeometry.Face

export type MoveHandles = MoveHandles.Class
export type RotateHandles = RotateHandles.Class
export type ExtrudeHandles = ExtrudeHandles.Class

export type TemporaryTransparency = TemporaryTransparency.Class
export type BoundsChangedTracker = BoundsChangedTracker.Class
export type ViewChangeDetector = ViewChangeDetector.Class
export type SelectionWrapper = SelectionWrapper.Class
export type DraggerToolModel = DraggerToolModel.Class
export type AttachmentMover = AttachmentMover.Class
export type DraggerContext = DraggerContext.Class
export type SelectionInfo = SelectionInfo.Class
export type HoverTracker = HoverTracker.Class
export type DragSelector = DragSelector.Class
export type JointMaker = JointMaker.Class
export type JointPairs = JointPairs.Class
export type PartMover = PartMover.Class

return table.freeze({
    DraggerTool = DraggerTool,
    DraggerContext = DraggerContext,

    Components = table.freeze({
        DraggerTool = DraggerTool,
        DraggedPivot = DraggedPivot,
        SelectionDot = SelectionDot,

        MoveHandleView = MoveHandleView,
        ScaleHandleView = ScaleHandleView,
        RotateHandleView = RotateHandleView,

        AnimatedHoverBox = AnimatedHoverBox,
        DragSelectionView = DragSelectionView,
        LocalSpaceIndicator = LocalSpaceIndicator,

        StandaloneSelectionBox = StandaloneSelectionBox,
        SummonHandlesHider = SummonHandlesHider,
        SummonHandlesNote = SummonHandlesNote,
    }),

    Handles = table.freeze({
        ExtrudeHandles = ExtrudeHandles,
        RotateHandles = RotateHandles,
        MoveHandles = MoveHandles,
    }),

    Implementation = table.freeze({
        HoverTracker = HoverTracker,
        DraggerContext = DraggerContext,
        DraggerStateType = DraggerStateType,
        DraggerToolModel = DraggerToolModel,
    }),

    Utility = table.freeze({
        Math = Math,
        Colors = Colors,
        PartMover = PartMover,
        JointUtil = JointUtil,
        DragHelper = DragHelper,
        JointMaker = JointMaker,
        JointPairs = JointPairs,
        BoundingBox = BoundingBox,
        DragSelector = DragSelector,
        SelectionInfo = SelectionInfo,
        StandardCursor = StandardCursor,
        AttachmentMover = AttachmentMover,
        SelectionHelper = SelectionHelper,
        SelectionWrapper = SelectionWrapper,
        ViewChangeDetector = ViewChangeDetector,
        BoundsChangedTracker = BoundsChangedTracker,
        TemporaryTransparency = TemporaryTransparency,

        getGeometry = getGeometry,
        classifyPivot = classifyPivot,
        roundRotation = roundRotation,
        setInsertPoint = setInsertPoint,
        getFaceInstance = getFaceInstance,
        assertGoodCFrame = assertGoodCFrame,
        shouldDragAsFace = shouldDragAsFace,
        getBoundingBoxScale = getBoundingBoxScale,
        isProtectedInstance = isProtectedInstance,
        computeDraggedDistance = computeDraggedDistance,
        snapRotationToPrimaryDirection = snapRotationToPrimaryDirection,
    }),
})