export type Shape =
	| "Brick"
	| "Sphere"
	| "Cylinder"
	| "Wedge"
	| "CornerWedge"
	| "Terrain"
	| "Mesh"

export type Surface =
	| "RightSurface"
	| "LeftSurface"
	| "TopSurface"
	| "BottomSurface"
	| "FrontSurface"
	| "BackSurface"

type IGeometry<T> = {
	type: T,
	id: number?,
	part: BasePart?,
}

export type Face = IGeometry<"Face"> & {
	point: Vector3,
	normal: Vector3,
	direction: Vector3,
	vertices: { Vector3 },
	surface: Surface?,
	center: Vector3?,
}

export type Vertex = IGeometry<"Vertex"> & {
	position: Vector3,
}

export type Edge = IGeometry<"Edge"> & {
	a: Vector3,
	b: Vector3,
	length: number,
	direction: Vector3?,
	edgeMargin: number,
	vertexMargin: number?,
}

export type Geometry = {
	part: BasePart,
	shape: Shape,
	vertices: { Vertex },
	edges: { Edge },
	faces: { Face },
	vertexMargin: number,
}

local function getShape(part: BasePart): (Shape, Vector3)
	if part:IsA("WedgePart") then
		return "Wedge", Vector3.one
	elseif part:IsA("CornerWedgePart") then
		return "CornerWedge", Vector3.one
	elseif part:IsA("Terrain") then
		return "Terrain", Vector3.one
	elseif part:IsA("UnionOperation") then
		return "Brick", Vector3.one
	elseif part:IsA("MeshPart") then
		return "Brick", Vector3.one
	elseif part:IsA("Part") then
		-- BasePart
		if part.Shape == Enum.PartType.Ball then
			return "Sphere", Vector3.one
		elseif part.Shape == Enum.PartType.Cylinder then
			return "Cylinder", Vector3.one
		elseif part.Shape == Enum.PartType.Block then
			return "Brick", Vector3.one
		elseif part.Shape == Enum.PartType.CornerWedge then
			return "CornerWedge", Vector3.one
		elseif part.Shape == Enum.PartType.Wedge then
			return "Wedge", Vector3.one
		else
			assert(false, "Unreachable")
		end
	else
		return "Brick", Vector3.one
	end
end

return function(part: BasePart, hit: Vector3?, assumedCFrame: CFrame?): Geometry
	local cf = assumedCFrame or part.CFrame
	local pos = cf.Position

	local sx = part.Size.X / 2
	local sy = part.Size.Y / 2
	local sz = part.Size.Z / 2

	local xvec = cf.XVector
	local yvec = cf.YVector
	local zvec = cf.ZVector

	local shape, scale = getShape(part)
	local verts = {} :: { Vector3 }
	local edges = {} :: { Edge }
	local faces = {} :: { Face }

	sx = sx * scale.X
	sy = sy * scale.Y
	sz = sz * scale.Z

	if shape == "Brick" or shape == "Sphere" or shape == "Cylinder" then
		--8 vertices
		verts = {
			pos +xvec*sx  +yvec*sy  +zvec*sz, --top 4
			pos +xvec*sx  +yvec*sy  -zvec*sz,
			pos -xvec*sx  +yvec*sy  +zvec*sz,
			pos -xvec*sx  +yvec*sy  -zvec*sz,
			--
			pos +xvec*sx  -yvec*sy  +zvec*sz, --bottom 4
			pos +xvec*sx  -yvec*sy  -zvec*sz,
			pos -xvec*sx  -yvec*sy  +zvec*sz,
			pos -xvec*sx  -yvec*sy  -zvec*sz,
		}

		--12 edges
		edges = {
			{a = verts[1], b = verts[2], length = math.min(2*sx, 2*sy)}, --top 4
			{a = verts[3], b = verts[4], length = math.min(2*sx, 2*sy)},
			{a = verts[1], b = verts[3], length = math.min(2*sy, 2*sz)},
			{a = verts[2], b = verts[4], length = math.min(2*sy, 2*sz)},
			--
			{a = verts[5], b = verts[6], length = math.min(2*sx, 2*sy)}, --bottom 4
			{a = verts[7], b = verts[8], length = math.min(2*sx, 2*sy)},
			{a = verts[5], b = verts[7], length = math.min(2*sy, 2*sz)},
			{a = verts[6], b = verts[8], length = math.min(2*sy, 2*sz)},
			--
			{a = verts[1], b = verts[5], length = math.min(2*sx, 2*sz)}, --verticals
			{a = verts[2], b = verts[6], length = math.min(2*sx, 2*sz)},
			{a = verts[3], b = verts[7], length = math.min(2*sx, 2*sz)},
			{a = verts[4], b = verts[8], length = math.min(2*sx, 2*sz)},
		} :: { Edge }

		--6 faces
		faces = {
			RightSurface = {
				point = verts[1],
				normal = xvec,
				direction = zvec,
				vertices = { verts[5], verts[6], verts[2], verts[1] }
			},

			LeftSurface = {
				point = verts[3],
				normal = -xvec,
				direction = zvec,
				vertices = {verts[3], verts[4], verts[8], verts[7] }
			},

			TopSurface = {
				point = verts[1],
				normal = yvec,
				direction = xvec,
				vertices = {verts[1], verts[2], verts[4], verts[3] }
			},

			BottomSurface = {
				point = verts[5],
				normal = -yvec,
				direction = xvec,
				vertices = {verts[7], verts[8], verts[6], verts[5] }
			},

			BackSurface = {
				point = verts[1],
				normal = zvec,
				direction = xvec,
				vertices = {verts[1], verts[3], verts[7], verts[5] }
			},

			FrontSurface = {
				point = verts[2],
				normal = -zvec,
				direction = xvec,
				vertices = {verts[6], verts[8], verts[4], verts[2] }
			},
		}
	elseif (shape == "Sphere" or shape == "Cylinder") and hit then
		-- Just have one face and vertex, at the hit pos
		verts = { hit }
		edges = {} --edge can be selected as the normal of the face if the user needs it

		local norm = (hit - pos).Unit
		local norm2 = norm:Cross(Vector3.yAxis).Unit
		local surfaceName: Surface

		if math.abs(norm.X) > math.abs(norm.Y) and math.abs(norm.X) > math.abs(norm.Z) then
			surfaceName = (if (norm.X > 0) then "RightSurface" else "LeftSurface") :: Surface
		elseif math.abs(norm.Y) > math.abs(norm.Z) then
			surfaceName = (if (norm.Y > 0) then "TopSurface" else "BottomSurface") :: Surface
		else
			surfaceName = (if (norm.Z > 0) then "BackSurface" else "FrontSurface") :: Surface
		end

		faces = {
			[surfaceName] = {
				point = hit,
				normal = norm,
				direction = norm2,
				vertices = {},
			} :: Face
		}
	elseif shape == "CornerWedge" then
		local slantVec1 = ( zvec*sy + yvec*sz).Unit
		local slantVec2 = (-xvec*sy + yvec*sx).Unit

		-- 5 verts
		verts = {
			pos +xvec*sx  +yvec*sy  -zvec*sz, --top 1
			--
			pos +xvec*sx  -yvec*sy  +zvec*sz, --bottom 4
			pos +xvec*sx  -yvec*sy  -zvec*sz,
			pos -xvec*sx  -yvec*sy  +zvec*sz,
			pos -xvec*sx  -yvec*sy  -zvec*sz,
		}

		-- 8 edges
		edges = {
			{a = verts[2], b = verts[3], length = 0}, -- bottom 4
			{a = verts[3], b = verts[5], length = 0},
			{a = verts[5], b = verts[4], length = 0},
			{a = verts[4], b = verts[2], length = 0},
			--
			{a = verts[1], b = verts[3], length = 0}, -- vertical
			--
			{a = verts[1], b = verts[2], length = 0}, -- side diagonals
			{a = verts[1], b = verts[5], length = 0},
			--
			{a = verts[1], b = verts[4], length = 0}, -- middle diagonal
		} :: { Edge }

		-- 5 faces
		faces = {
			-- bottom
			BottomSurface = {
				point = verts[2],
				normal = -yvec,
				direction = xvec,
				vertices = {verts[2], verts[3], verts[5], verts[4]},
			},

			-- sides
			RightSurface = {
				point = verts[1],
				normal = xvec,
				direction = -yvec,
				vertices = {verts[1], verts[3], verts[2]},
			},

			FrontSurface = {
				point = verts[1],
				normal = -zvec,
				direction = -yvec,
				vertices = {verts[1], verts[3], verts[5]},
			},

			-- tops
			BackSurface = {
				point = verts[1],
				normal = slantVec1,
				direction = xvec,
				vertices = {verts[1], verts[2], verts[4]},
			},

			LeftSurface = {
				point = verts[1],
				normal = slantVec2,
				direction = zvec,
				vertices = {verts[1], verts[5], verts[4]},
			},
		}

	elseif shape == "Wedge" then
		local slantVec = (-zvec*sy + yvec*sz).Unit

		--6 vertices
		verts = {
			pos +xvec*sx  +yvec*sy  +zvec*sz, --top 2
			pos -xvec*sx  +yvec*sy  +zvec*sz,
			--
			pos +xvec*sx  -yvec*sy  +zvec*sz, --bottom 4
			pos +xvec*sx  -yvec*sy  -zvec*sz,
			pos -xvec*sx  -yvec*sy  +zvec*sz,
			pos -xvec*sx  -yvec*sy  -zvec*sz,
		}

		--9 edges
		edges = {
			{a = verts[1], b = verts[2], length = math.min(2*sy, 2*sz)}, --top 1
			--
			{a = verts[1], b = verts[4], length = math.min(2*sy, 2*sz)}, --slanted 2
			{a = verts[2], b = verts[6], length = math.min(2*sy, 2*sz)},
			--
			{a = verts[3], b = verts[4], length = math.min(2*sx, 2*sy)}, --bottom 4
			{a = verts[5], b = verts[6], length = math.min(2*sx, 2*sy)},
			{a = verts[3], b = verts[5], length = math.min(2*sy, 2*sz)},
			{a = verts[4], b = verts[6], length = math.min(2*sy, 2*sz)},
			--
			{a = verts[1], b = verts[3], length = math.min(2*sx, 2*sz)}, --vertical 2
			{a = verts[2], b = verts[5], length = math.min(2*sx, 2*sz)},
		} :: { Edge }

		--5 faces
		faces = {
			-- right
			RightSurface = {
				point = verts[1],
				normal = xvec,
				direction = zvec,
				vertices = {verts[1], verts[4], verts[3], verts[2]},
			},

			-- left
			LeftSurface = {
				point = verts[2],
				normal = -xvec,
				direction = zvec,
				vertices = {verts[2], verts[3], verts[4], verts[1]},
			},

			-- bottom
			BottomSurface = {
				point = verts[3],
				normal = -yvec,
				direction = xvec,
				vertices = {verts[3], verts[4], verts[6], verts[5]},
			},

			-- back
			BackSurface = {
				point = verts[1],
				normal = zvec,
				direction = xvec,
				vertices = {verts[1], verts[2], verts[5], verts[3]},
			},

			-- slanted
			FrontSurface = {
				point = verts[4],
				normal = -slantVec,
				direction = slantVec:Cross(xvec),
				vertices = {verts[4], verts[1], verts[2], verts[6]},
			},
		}
	elseif shape == "Terrain" then
		assert(false, "Called GetGeometry on Terrain")
	else
		assert(false, "Bad shape: " .. shape)
	end

	local vertData = {} :: { Vertex }
	local faceData = {} :: { Face }
	local geomId = 0

	local geometry: Geometry = {
		part = part;
		shape = ((shape == "Sphere" or shape == "Cylinder") and shape or "Mesh") :: Shape;
		vertices = vertData;
		faces = faceData;
		edges = edges;
		vertexMargin = math.min(sx, sy, sz) * 2;
	}

	for surfaceType, dat in pairs(faces) do
		geomId += 1
		dat.id = geomId
		dat.part = part
		dat.type = "Face"
		dat.surface = surfaceType
		table.insert(faceData, dat)
	end

	for _, dat in ipairs(edges) do
		geomId += 1
		dat.id = geomId

		dat.direction = (dat.b - dat.a).Unit
		dat.length = (dat.b - dat.a).Magnitude
		dat.vertexMargin = geometry.vertexMargin
		dat.part = part
		dat.type = "Edge"
	end

	for i, dat in ipairs(verts) do
		geomId += 1

		vertData[i] = {
			position = dat;
			id = geomId;
			type = "Vertex";
		} :: Vertex
	end

	return geometry
end