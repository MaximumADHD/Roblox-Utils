-- Baseline wrapper around the default BoundsChangedTracker implementation provided in DraggerFramework.
-- This provides backwards compatibility for its previous place of residence, while still allowing
-- consumers to extend it as needed.

local DraggerSchemaCore = script.Parent
local Packages = DraggerSchemaCore.Parent

local DraggerFramework = require(Packages.DraggerFramework)
local BoundsChangedTracker = DraggerFramework.Utility.BoundsChangedTracker

export type Class = DraggerFramework.BoundsChangedTracker
return BoundsChangedTracker