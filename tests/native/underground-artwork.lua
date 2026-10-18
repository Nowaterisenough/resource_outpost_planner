local artwork_renderer=require("mpp.preview_renderer")
local artwork_started=false
script.on_nth_tick(1,function()
 if artwork_started then return end
 artwork_started=true
 local p=game.get_player(1)
 p.set_controller{type=defines.controllers.god}
 local s=game.create_surface("underground-artwork",{width=128,height=128,autoplace_controls={}})
 s.request_to_generate_chunks({0,0},2);s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities()) do e.destroy() end
 s.destroy_decoratives{}
 local tiles={};for x=-40,40 do for y=-30,30 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
 s.set_tiles(tiles);s.daytime=0;s.freeze_daytime=true
 p.teleport({0,0},s)
 local draft={surface=s,player_index=p.index,specs={}}
 local function label(text,x,y)
  rendering.draw_text{surface=s,target={x,y},text=text,color={1,1,1},alignment="center",scale=1.2}
 end
 label("Native ghosts (top) / planner artwork (bottom)",0,-9)
 for i,dir in ipairs{defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west} do
  local x=-18+(i-1)*12
  label(({"North","East","South","West"})[i],x,-6)
  local step=({[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}})[dir]
  for j,kind in ipairs{"input","output"} do
   local px,py=x+step[1]*(j-1)*4+.5,step[2]*(j-1)*4+.5
   s.create_entity{name="entity-ghost",inner_name="express-underground-belt",position={px,py},direction=dir,type=kind,force=p.force}
   draft.specs[#draft.specs+1]={name="entity-ghost",inner_name="express-underground-belt",position={x=px,y=py+13},direction=dir,type=kind}
  end
 end
 artwork_renderer.render(draft,{})
 game.take_screenshot{surface=s,position={0,7},resolution={1600,1100},zoom=1,show_gui=false,show_entity_info=false,
  path="underground-artwork.png",anti_alias=true}
 log("PLACEMENT artwork screenshot requested")
end)
