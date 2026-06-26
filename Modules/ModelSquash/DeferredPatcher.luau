local DeferredPatcher = {}
local AssetService = game:GetService("AssetService")

type MeshPatch = {
    MeshContent: Content?,
    FluidFidelity: Enum.FluidFidelity?,
    RenderFidelity: Enum.RenderFidelity?,
    CollisionFidelity: Enum.CollisionFidelity?,
}

local pendingMeshes = {} :: {
    [MeshPart]: MeshPatch
}

local patchThread: thread?

local function applyPatches()
    patchThread = nil

    for meshPart, patch in pendingMeshes do
        if not meshPart.Parent then
            pendingMeshes[meshPart] = nil
            continue
        end

        local content = patch.MeshContent or meshPart.MeshContent

        task.spawn(function ()
            local newMeshPart = AssetService:CreateMeshPartAsync(content, {
                CollisionFidelity = patch.CollisionFidelity or meshPart.CollisionFidelity,
                RenderFidelity = patch.RenderFidelity or meshPart.RenderFidelity,
                FluidFidelity = patch.FluidFidelity or meshPart.FluidFidelity,
            })

            newMeshPart.TextureContent = meshPart.TextureContent
            meshPart:ApplyMesh(newMeshPart)
        end)
    end

    table.clear(pendingMeshes)
end

function DeferredPatcher.PatchMeshPart<K, V>(meshPart: MeshPart, key: K & keyof<MeshPatch>, value: V & index<MeshPatch, K>)
    local patch = (pendingMeshes[meshPart] or (function ()
        pendingMeshes[meshPart] = {}
        return pendingMeshes[meshPart]
    end)()) :: { [K]: index<MeshPatch, K> }

    patch[key] = value
    patchThread = patchThread or task.defer(applyPatches)
end

return DeferredPatcher