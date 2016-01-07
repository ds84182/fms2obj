#!/usr/bin/lua5.3 
local lfs = require "lfs"
local gd = require "gd"
local args = table.pack(...)

local filename = table.remove(args,1)
local rootname = output or (filename:match("^(.+)%..*$") or filename)
local file = io.open(filename, "rb")

--function print() end

local function printf(fmt, ...)
	print(fmt:format(...))
end

local function printError(err)
	io.stderr:write(err.."\n")
end

local function printfError(fmt, ...)
	io.stderr:write(fmt:format(...).."\n")
end

local function go(addr)
	return file:seek("set", addr)
end

local function skip(b)
	return file:seek("cur", b)
end

local function getPosition()
	return file:seek("cur", 0)
end

local function asShort(str)
	return (">I2"):unpack(str)
end

local function asInt(str)
	return (">I"):unpack(str)
end

local function asLEShort(str) --AYY, LMAO
	return ("<I2"):unpack(str)
end

local function asLEInt(str) --BEFORE REDDIT, THIS WAS ONLY asInt
	return ("<I"):unpack(str)
end

local function asFloat(str)
	return (">f"):unpack(str)
end

local function asVertex(str)
	return (">fff"):unpack(str)
end

local function asVertex2(str)
	return (">ff"):unpack(str)
end

local loaders = {}

local magicList = {["FIPAFMS\0"]="FIPAFMS",["FIPAFTEX"]="FIPAFTEX",["pBin"]="pBin"}

function loaders.FIPAFMS(output)
	skip(8) --version data?
	local containedFiles = asLEInt(file:read(4))
	skip(12) --unknown data, maybe padding
	local basePointer = getPosition()+(containedFiles*16)
	
	local filedata = {}
	for i=1, containedFiles do
		filedata[i] = {size=asLEInt(file:read(4)), pointer=asLEInt(file:read(4))+basePointer}
		skip(8) --padding
	end
	
	local typenums = {}

	for i=1, containedFiles do
		local filedat = filedata[i]
		local start = filedat.pointer
		go(start)
		
		local header = file:read(4)
		printf("FIPAFMS Sub File: %s", header)
	
		if header == "FMES" then --mesh file
			print("Extracting Mesh...")
			skip(12)
			local ngroups = asInt(file:read(4))
			skip(20)
			local groupPointers = {}
			for i=1, ngroups do
				groupPointers[i] = asInt(file:read(4))
			end
			
			local groups = {}
			local maxMaterial = 0
			
			for i=1, ngroups do
				go(start+groupPointers[i])
				local pos = getPosition()
				local vpg = asInt(file:read(4)) --verts per group
				local vgc = asInt(file:read(4)) --vert group count
		
				local x1, y1, z1 = asVertex(file:read(4*3)) --bounding box
				local x2, y2, z2 = asVertex(file:read(4*3)) --bounding box
		
				local positionPointer = asInt(file:read(4))+pos
				local normalPointer = asInt(file:read(4))+pos
				local colorPointer = asInt(file:read(4))+pos
				local texturePointer = asInt(file:read(4))+pos+4
				skip(32)
				local usedMaterial = asShort(file:read(2))
				maxMaterial = math.max(maxMaterial, usedMaterial)
				skip(138)
		
				local indexCount = asInt(file:read(4))&0xFFFF
		
				printf("Verts Per Group: %d", vpg)
				printf("Vert Groups: %d", vgc)
				printf("Bounding Box: (%f, %f, %f) -> (%f, %f, %f)", x1, y1, z1, x2, y2, z2)
				printf("Position Pointer: 0x%X", positionPointer)
				printf("Normal Pointer: 0x%X", normalPointer)
				printf("Color Pointer: 0x%X", colorPointer)
				printf("Texture Pointer: 0x%X", texturePointer)
				printf("Index Count: %d", indexCount)
		
				local index = {}
				local position = {}
				local normal = {}
				local color
				if colorPointer > pos then
					color = {}
				end
				local texture
				if texturePointer > pos+4 then
					texture = {}
				end
		
				local maxPositionIndex = 0
				local maxNormalIndex = 0
				local maxColorIndex = 0
				local maxTextureIndex = 0
				print("Index data:")
				for i=1, indexCount do
					print("\tIndexed Vertex "..i)
					local pos = asShort(file:read(2))
					printf("\t\tPosition Index: %d", pos)
					maxPositionIndex = math.max(maxPositionIndex, pos)
					local norm = asShort(file:read(2))
					printf("\t\tNormal Index: %d", norm)
					maxNormalIndex = math.max(maxNormalIndex, norm)
					
					local col, tex
					
					if color then
						col = asShort(file:read(2))
						printf("\t\tColor Index: %d", col)
						maxColorIndex = math.max(maxColorIndex, col)
					end
					
					if texture then
						tex = asShort(file:read(2))
						printf("\t\tTexture Index: %d", tex)
						maxTextureIndex = math.max(maxTextureIndex, tex)
					end
			
					index[i] = {pos,norm,tex}
				end
		
				print("Position data:")
				go(positionPointer)
				for i=1, maxPositionIndex+1 do
					local x, y, z = asVertex(file:read(4*3))
					print("\tVertex "..i..":", x, y, z)
			
					position[i-1] = {x, y, z}
				end
		
				print("Normal data:")
				go(normalPointer)
				for i=1, maxNormalIndex+1 do
					local x, y, z = asVertex(file:read(4*3))
					print("\tNormal "..i..":", x, y, z)
			
					normal[i-1] = {x, y, z}
				end
		
				if texture then
					print("Texture data:")
					go(texturePointer)
					for i=1, maxTextureIndex+1 do
						local x, y = asVertex2(file:read(4*2))
						print("\tTexture "..i..":", x, y)
			
						texture[i-1] = {x, 1-y}
					end
				end
				
				groups[i] = {index=index,position=position,normal=normal,texture=texture,maxPositionIndex=maxPositionIndex,maxNormalIndex=maxNormalIndex,maxTextureIndex=maxTextureIndex,indexCount=indexCount,usedMaterial=usedMaterial}
			end
		
			local out = io.open((output or rootname)..".obj","w")
			out:write("# Generated using fms2obj using the file "..filename.."\n\n")
			
			local positionOffset = 1
			local normalOffset = 1
			local textureOffset = 1
		
			for i=1, ngroups do
				local group = groups[i]
				local index = group.index
				local position = group.position
				local normal = group.normal
				local texture = group.texture
				--add position data--
				out:write("g "..rootname.."_"..i.."\n")
				out:write("# used material for this group: "..group.usedMaterial.." <= 32\n")
				out:write("usemtl MAT"..group.usedMaterial.."\n")
				out:write("# Automagically generated position data\n")
				for i=0, group.maxPositionIndex do
					local p = position[i]
					out:write(("v %f %f %f\n"):format(p[1],p[2],p[3]))
				end
		
				if texture then
					--add texture data--
					out:write("# Automagically generated texture data\n")
					for i=0, group.maxTextureIndex do
						local p = texture[i]
						out:write(("vt %f %f\n"):format(p[1],p[2]))
					end
				end
		
				--add normal data--
				out:write("# Automagically generated normal data\n")
				for i=0, group.maxNormalIndex do
					local p = normal[i]
					out:write(("vn %f %f %f\n"):format(p[1],p[2],p[3]))
				end
		
				out:write("# Automagically generated face data\n")
				for i=1, group.indexCount, 3 do
					local idx = index[i]
					local idx2 = index[i+1]
					local idx3 = index[i+2]
					--[[out:write(("f %d/%d/%d %d/%d/%d %d/%d/%d\n"):format(idx[1]+positionOffset,idx[3]+textureOffset,idx[2]+normalOffset,
																		idx2[1]+positionOffset,idx2[3]+textureOffset,idx2[2]+normalOffset,
																		idx3[1]+positionOffset,idx3[3]+textureOffset,idx3[2]+normalOffset))]]
					if texture then
						out:write(("f %d/%d %d/%d %d/%d\n"):format(idx3[1]+positionOffset,idx3[3]+textureOffset,
																		idx2[1]+positionOffset,idx2[3]+textureOffset,
																		idx[1]+positionOffset,idx[3]+textureOffset))
						out:write(("f %d/%d %d/%d %d/%d\n"):format(idx[1]+positionOffset,idx[3]+textureOffset,
																		idx2[1]+positionOffset,idx2[3]+textureOffset,
																		idx3[1]+positionOffset,idx3[3]+textureOffset))
					else
						out:write(("f %d %d %d\n"):format(idx3[1]+positionOffset,
																		idx2[1]+positionOffset,
																		idx[1]+positionOffset))
						out:write(("f %d %d %d\n"):format(idx[1]+positionOffset,
																		idx2[1]+positionOffset,
																		idx3[1]+positionOffset))
					end
				end
				
				positionOffset = positionOffset+group.maxPositionIndex+1
				textureOffset = textureOffset+group.maxTextureIndex+1
				normalOffset = normalOffset+group.maxNormalIndex+1
			end
		
			out:close()
		elseif header == "FMAT" then
			--load material into memory--
			skip(12)
			local materials = {}
			local numberMaterials = asInt(file:read(4))
			skip(20)
			local unknwn1 = asShort(file:read(2))
			local unknwn2 = asShort(file:read(2))
			
			for i=1, numberMaterials do
				materials[i] = {texture=asShort(file:read(2))}
			end
			if numberMaterials%2 == 1 then skip(2) end
			for i=1, numberMaterials do
				materials[i].pointer = asInt(file:read(4))
			end
			
			local mtl = io.open((output or rootname)..".mtl","w")
			
			for i=1, numberMaterials do
				local material = materials[i]
				mtl:write("newmtl MAT"..(i-1).."\n")
				mtl:write("map_Ka TEX0_"..(material.texture+1)..".png\n")
				mtl:write("map_Kd TEX0_"..(material.texture+1)..".png\n\n")
			end
			mtl:close()
		else
			--extract it as a binary file
			local num = typenums[header] or 0
			typenums[header] = num+1
			
			local out = io.open((output or rootname).."_"..header..num..".bin","wb")
			out:write(header)
			out:write(file:read(filedat.size-4))
			out:close()
		end
	end
end

function loaders.FIPAFTEX(output)
	--TODO: Figure out if files are in more formats than just DXT1
	--TODO: THIS FILE PROBABLY DOES THE SAME THING AS THE FIPAFMS, LITTLE ENDIAN FUCKING HEADER
	skip(8)
	local attrs = file:read(1):byte()
	skip(15)
	skip(attrs*16)
	if attrs%2 ~= 0 then skip(16) end
	printf("Number of Textures: %d", attrs)
	
	for i=1, attrs do
		assert(file:read(4) == "\x00\x20\xAF\x30", "Did not find texture magic!")
		skip(16)
		local height = asShort(file:read(2))
		local width = asShort(file:read(2))
		local format = asInt(file:read(4))
		skip(36)
		
		printf("Texture %d:", i)
		printf("Width: %d", width)
		printf("Height: %d", height)
		printf("Format: %X", format)
	
		local image = gd.createTrueColor(width, height)
		image:saveAlpha(true)
		image:alphaBlending(false)
		image:filledRectangle(0,0,width,height,image:colorAllocate(255,0,255,127))
		
		if format == 0x0 then --I4
			for y=0, height-1 do
				for x=0, width-1, 2 do
					local b = file:read(1):byte()
					local k1 = (b & 0xF) * 0x11
					local k2 = (b >> 4) * 0x11
					
					image:setPixel(x,y,(k1 << 16) | (k1 << 8) | k1)
					image:setPixel(x+1,y,(k2 << 16) | (k2 << 8) | k2)
				end
			end
		elseif format == 0x1 then --I8
			for y=0, height-1 do
				for x=0, width-1 do
					local color = file:read(1):byte()
					image:setPixel(x,y,(color << 16) | (color << 8) | color)
				end
			end
		elseif format == 0xE then --CMPR
			local function lerp(a,b,k) return math.tointeger(math.floor(a * (1-k) + b * k)) end

			local function decodeDXT1Block(dx, dy)
				local fd = file:read(4)
				local rgb565_a = (fd:byte(1) << 8) | fd:byte(2)
				local rgb565_b = (fd:byte(3) << 8) | fd:byte(4)
				local palette = {}
				palette[0] = {(((rgb565_a >> 11) & 0x1F) * 255 + 15)//31, (((rgb565_a >> 5) & 0x3F) * 255 + 31)//63, ((rgb565_a & 0x1F) * 255 +15)//31}
				palette[1] = {(((rgb565_b >> 11) & 0x1F) * 255 + 15)//31, (((rgb565_b >> 5) & 0x3F) * 255 + 31)//63, ((rgb565_b & 0x1F) * 255 +15)//31}
				if rgb565_a > rgb565_b then
					palette[2] = image:colorAllocate(lerp(palette[0][1],palette[1][1],1/3),
									lerp(palette[0][2],palette[1][2],1/3),
									lerp(palette[0][3],palette[1][3],1/3))
		
					palette[3] = image:colorAllocate(lerp(palette[0][1],palette[1][1],2/3),
									lerp(palette[0][2],palette[1][2],2/3),
									lerp(palette[0][3],palette[1][3],2/3))
				else
					palette[2] = image:colorAllocate(lerp(palette[0][1],palette[1][1],1/2),
									lerp(palette[0][2],palette[1][2],1/2),
									lerp(palette[0][3],palette[1][3],1/2))
					palette[3] = 0xFFFFFFFF
				end
			
				palette[0] = image:colorAllocate(palette[0][1],palette[0][2],palette[0][3])
				palette[1] = image:colorAllocate(palette[1][1],palette[1][2],palette[1][3])

				local fb = file:read(4)
				for y=0, 3 do
					local b = fb:byte(y+1)
					for x=0, 3 do
						local pidx = (b >> (x*2)) & 0x3
						image:setPixel((3-x)+dx,y+dy,palette[pidx])
					end
				end
			end

			local function decodeDXT1MainBlock(x, y)
				decodeDXT1Block(x,y)
				decodeDXT1Block(x+4,y)
				decodeDXT1Block(x,y+4)
				decodeDXT1Block(x+4,y+4)
			end

			local function decodeDXT1Image()
				for y=0, height-1, 8 do
					for x=0, width-1, 8 do
						decodeDXT1MainBlock(x, y)
					end
				end
			end
		
			decodeDXT1Image()
		else
			printError("Format unsupported")
			return
		end
	
		image:png((output or rootname).."_"..i..".png")
	end
end

function loaders.pBin(output)
	skip(12)
	local detailsPointer = asInt(file:read(4)) --pointer to a structure detailing the files present
	local detailsLength = asInt(file:read(4))
	
	printf("Details Pointer: 0x%X", detailsPointer)
	printf("Details Length: 0x%X", detailsLength)
	
	--read details into structure--
	local details = {}
	local typenums = {}
	
	print("Details:")
	for i=1, detailsLength do
		printf("\tContainer %d:", i)
		local size = asInt(file:read(4))
		local offset = asInt(file:read(4))
		local type = file:read(8):gsub("%z","")
		printf("\t\tSize: %X", size)
		printf("\t\tOffset: %X", offset)
		printf("\t\tType: %s", type)
		local number = typenums[type] or 0
		printf("\t\tID: %s%d", type, number)
		typenums[type] = number+1
		details[i] = {size=size,offset=offset,type=type,number=number,id=("%s%d"):format(type,number)}
	end
	
	--extract extension from file name--
	printf("Creating folder: %s", rootname)
	lfs.mkdir(rootname)
	
	--extract details--
	for i=1, detailsLength do
		local detail = details[i]
		print("Extracting "..detail.id)
		go(detail.offset)
		
		local main = readMagic()
		if main then
			loaders[main](rootname.."/"..detail.id)
		else
			print(detail.id.." not extracted: Loader not found")
		end
	end
end

function readMagic()
	--attempt to read file magic--
	local pos = getPosition()
	for magic, format in pairs(magicList) do
		go(pos)
		if file:read(#magic) == magic then
			return format
		end
	end
	printError("Could not find magic!")
end

local main = readMagic()
if not main then return end
print("File Format: "..main)
loaders[main](table.unpack(args))
