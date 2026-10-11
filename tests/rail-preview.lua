-- Run from the repository root with Lua 5.2.
local function picture(part,y)
	return {filename=part..".png",width=256,height=256,x=32,y=y,scale=.5,shift={.25,-.5},variation_count=8}
end
local modern,legacy={pictures={}},{pictures={}}
local parts={
	{"rail-stone-path-lower","stone_path_background","stone_path_lower"},
	{"rail-stone-path","stone_path","stone_path"},{"rail-tie","ties","tie"},
	{"rail-screw","backplates","screw"},{"rail-metal","metals","metal"},
}
for _,direction in ipairs{"north","east"} do
	local y=direction=="north" and 256 or 0
	modern.pictures[direction]={};legacy.pictures[direction]={}
	for _,part in ipairs(parts) do
		modern.pictures[direction][part[2]]=picture(part[2],y)
		legacy.pictures[direction][part[3]]=picture(part[3],y)
	end
end
local shadow=picture("metal-shadow",0);shadow.draw_as_shadow=true
modern.pictures.east.metals={layers={modern.pictures.east.metals,shadow}}
local sprites={}
data={raw={["straight-rail"]={rail=modern,legacy=legacy}},extend=function(_,list)
	for _,s in ipairs(list) do assert(not sprites[s.name],"duplicate rail sprite");sprites[s.name]=s end
end}
dofile("prototypes/preview.lua")
local count=0
for _,name in ipairs{"rail","legacy"} do for _,direction in ipairs{"north","east","south","west"} do
	for _,part in ipairs(parts) do
		local prefix="mpp-preview-"..name.."-"..direction.."-"..part[1]
		local s=assert(sprites[prefix.."-1"],"missing rail component: "..prefix)
		assert(s.filename==part[name=="rail" and 2 or 3]..".png","wrong rail component")
		assert(s.x==32 and s.y==((direction=="north" or direction=="south") and 256 or 0),"wrong rail atlas frame")
		assert(s.width==256 and s.height==256 and s.scale==.5 and s.shift[1]==.25 and s.shift[2]==-.5,"rail footprint changed")
		assert(not sprites[prefix.."-2"],"rail shadow rendered as solid artwork")
		count=count+1
	end
end end
print("Rail preview: "..count.." component, direction and atlas checks passed")
