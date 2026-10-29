local warnings = require("mpp.fill_warnings")
local function recipe(item, category)
 return {products={{type="item",name=item}},categories={category or "crafting"}}
end
local function cover(item)
 return {name=item,items_to_place_this={{name=item}},collision_mask={layers={ground_tile=true}}}
end
local landfill, ice, foundation = cover("landfill"), cover("ice-platform"), cover("foundation")
local function hazard(name, material)
 return {name=name,default_cover_tile=material,collision_mask={layers={water_tile=true}}}
end
prototypes={tile={landfill=landfill,["ice-platform"]=ice,foundation=foundation},item={},recipe={
 landfill=recipe("landfill"),ice=recipe("ice-platform"),foundation=recipe("foundation"),
 alternative=recipe("landfill"),recycling=recipe("landfill","recycling"),
 hand_recycling=recipe("ice-platform","recycling-or-hand-crafting")}}
for _,item in ipairs{"landfill","ice-platform","foundation"} do prototypes.item[item]={localised_name=item} end
prototypes.tile.water=hazard("water",landfill)
prototypes.tile.lava=hazard("lava",foundation)
prototypes.tile["oil-ocean-shallow"]=hazard("oil-ocean-shallow",foundation)
prototypes.tile["ammoniacal-ocean"]=hazard("ammoniacal-ocean",ice)
prototypes.tile["mod-ocean"]=hazard("mod-ocean",ice)
local p={force={recipes={}},surface={planet={name="nauvis"},map_gen_settings={}}}
for name in pairs(prototypes.recipe) do p.force.recipes[name]={enabled=false} end
p.force.recipes.recycling.enabled=true;p.force.recipes.hand_recycling.enabled=true
local choices={fill_water_choice=true,fill_lava_choice=false,fill_oil_ocean_choice=true}
local result=warnings.for_player(p,choices)
assert(result.fill_water_choice and result.fill_lava_choice and result.fill_oil_ocean_choice,
 "always-enabled recycling must not hide locked material warnings")
p.force.recipes.alternative.enabled=true
assert(not warnings.for_player(p,choices).fill_water_choice,"alternative crafting unlock was ignored")
p.surface.planet.name="aquilo"
assert(warnings.for_player(p,choices).fill_water_choice,"Aquilo used unlocked landfill instead of ice")
p.force.recipes.ice.enabled=true
assert(not warnings.for_player(p,choices).fill_water_choice,"unlocked ice still warns")
p.force.recipes.ice.enabled=false
p.surface.planet.name="mod-planet"
p.surface.map_gen_settings={autoplace_settings={tile={settings={["mod-ocean"]={}}}}}
assert(warnings.for_player(p,choices).fill_water_choice,"modded ocean ignored its native cover")
-- No Space Age prototypes: absent fill materials should not crash or invent warnings.
p.surface.map_gen_settings={}
prototypes.tile.lava=nil;prototypes.tile["oil-ocean-shallow"]=nil
result=warnings.for_player(p,choices)
assert(not result.fill_lava_choice and not result.fill_oil_ocean_choice)
assert(choices.fill_water_choice and not choices.fill_lava_choice and choices.fill_oil_ocean_choice,
 "advisory checks changed terrain choices")
print("Fill warnings: recycling, alternative unlocks, Aquilo, modded oceans and base-only prototypes passed")
