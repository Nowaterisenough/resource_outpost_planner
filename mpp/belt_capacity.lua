local common=require("layouts.common")
local train_station=require("mpp.train_station")
local capacity={}

local load=require("mpp.belt_load")
capacity.default_min=load.default_min
capacity.default_max=load.default_max
capacity.valid_range=load.valid_range
capacity.migrate_choices=load.migrate_choices
capacity.ratios=load.ratios

function capacity.merge_limit(state)
	local _,upper=capacity.ratios(state)
	return common.get_belt_capacity_multiplier(state)*(state.belt_merge_choice and upper or 1)
end

function capacity.merge_candidate(state,source)
	if not state.belt_merge_choice then return true end
	local lower=capacity.ratios(state)
	local load=((source.throughput1 or 0)+(source.throughput2 or 0))/(2*common.get_belt_capacity_multiplier(state))
	return load<lower-1e-8
end

function capacity.limit(state)
	local lower,upper=capacity.ratios(state)
	assert(capacity.valid_range(lower,upper),"Invalid belt load range")
	return state.belt.speed*common.get_belt_capacity_multiplier(state)*upper
end

function capacity.enabled(state)
	return state.belt_merge_choice and state.layout_choice~="oil" and state.layout_choice~="blueprints"
		and not state._beacon_logistics and state.belt and state.belts and #state.belts>0
end

function capacity.overloaded(state)
	local limit=capacity.limit(state)/state.belt.speed
	for _,belt in ipairs(state.belts) do
		if (belt.merged_throughput1 or 0)>limit+1e-8 or (belt.merged_throughput2 or 0)>limit+1e-8 then return true end
	end
	return false
end

function capacity.single_error(state)
	local production=common.mining_production_calculator(state)
	local limit=capacity.limit(state)
	for _,miner in ipairs(state.best_attempt.miners) do
		local rate=production(miner)
		if rate>limit+1e-8 then
			return {"mpp.belt_capacity_single",string.format("%.2f",rate),string.format("%.2f",limit)}
		end
	end
end

function capacity.output_budget(choices)
	return choices.output_station_choice and train_station.output_count(choices)
		or choices.output_balance_choice and (choices.output_belt_count_choice or 8)
end

function capacity.output_warning(state,choices)
	if not capacity.enabled(state) then return end
	local count=capacity.output_budget(choices or state)
	local required=load.required_outputs(state.belts,capacity.limit(state)/state.belt.speed)
	local loss=load.loss_percent(state.belts,common.get_belt_capacity_multiplier(state),count)
	return load.output_warning(required,count,loss)
		or state._capacity_tight_big and loss>1e-8 and {"mpp.belt_capacity_dense",string.format("%.1f",loss)} or nil
end

function capacity.can_split(state)
	local budget=capacity.output_budget(state)
	if not budget then return true end
	local rows=0
	for _,miners in pairs(state.miner_lanes or {}) do if #miners>0 then rows=rows+1 end end
	-- Each row needs one receiving lane. Keep the compact layout when even pairing
	-- unsplit rows cannot fit the output budget; the final balancer handles reduction.
	return rows<=2*budget
end

function capacity.coverage(state)
	local result,M={},state.miner
	for _,miner in ipairs(state.best_attempt.miners) do
		for y=miner.y+M.extent_negative,miner.y+M.extent_positive do
			local row=result[y] or {};result[y]=row
			for x=miner.x+M.extent_negative,miner.x+M.extent_positive do row[x]=true end
		end
	end
	return result
end

function capacity.groups(miners,limit,production)
	local groups,current={},nil
	for _,miner in ipairs(miners or {}) do
		local rate=production(miner)
		if not current or current.rate+rate>limit+1e-8 then
			current={miners={},rate=0};groups[#groups+1]=current
		end
		current.miners[#current.miners+1]=miner;current.rate=current.rate+rate
	end
	return groups
end

function capacity.row_groups(lanes,lane_count,limit,production,budget,row_budget)
	local rates,high={},limit
	for i=1,lane_count do
		local total=0
		for _,miner in ipairs(lanes[i] or {}) do
			rates[miner]=production(miner);total=total+rates[miner]
		end
		high=math.max(high,total)
	end
	local function group(bound)
		local result,count={},0
		for i=1,lane_count do
			result[i]=capacity.groups(lanes[i],bound,function(m) return rates[m] end)
			-- Move the contiguous cut toward equal production without increasing either group
			-- above its previous peak. This also reduces avoidable single-side losses.
			local row=result[i]
			for j=1,#row-1,2 do
				local a,b=row[j],row[j+1]
				local joined={};for _,m in ipairs(a.miners) do joined[#joined+1]=m end
				for _,m in ipairs(b.miners) do joined[#joined+1]=m end
				local total=a.rate+b.rate
				local best,pivot,left=math.max(a.rate,b.rate),#a.miners,a.rate
				local sum=0
				for k=1,#joined-1 do
					sum=sum+rates[joined[k]]
					local peak=math.max(sum,total-sum)
					if peak<best-1e-8 then best,pivot,left=peak,k,sum end
				end
				if pivot~=#a.miners then
					a.miners={};b.miners={};a.rate=left;b.rate=total-left
					for k,m in ipairs(joined) do local list=k<=pivot and a.miners or b.miners;list[#list+1]=m end
				end
			end
			count=count+#row
		end
		return result,count
	end
	local function fits(bound)
		local count=0
		for i=1,lane_count do
			local sum,row_count=nil,0
			for _,miner in ipairs(lanes[i] or {}) do
				local rate=rates[miner]
				if not sum or sum+rate>bound+1e-8 then
					count=count+1;row_count=row_count+1;sum=0
					if budget and count>budget or row_budget and row_count>row_budget then return false end
				end
				sum=sum+rate
			end
		end
		return true
	end
	if fits(limit) then return group(limit) end
	if not fits(high) then return group(high) end
	-- Search counts only; allocate miner groups once after finding the bound.
	local low=limit
	for _=1,32 do
		local middle=(low+high)/2
		if fits(middle) then high=middle else low=middle end
	end
	return group(high)
end

-- A compact big-drill row owns at most two physical belts. Partition its
-- production across their four sides independently of other rows and the final
-- balancer's outlet count. A low-load row still needs only one receiving lane.
function capacity.compact_row_groups(lanes,lane_count,limit,production,retained_gaps,max_groups)
	local result={}
	for i=1,lane_count do
		local miners=lanes[i] or {}
		local rates,total={},0
		for _,miner in ipairs(miners) do
			rates[miner]=production(miner);total=total+rates[miner]
		end
		local split=total>limit+1e-8 or retained_gaps and retained_gaps[i]==2
		local count=split and math.min(max_groups or 4,#miners) or math.min(1,#miners)
		if count<=1 then
			result[i]=count==0 and {} or {{miners=miners,rate=total}}
		else
			-- Find the lowest achievable peak side load for this row. In
			-- particular, one very productive row must not coarsen other rows.
			local grouped=capacity.row_groups({miners},1,0,function(m) return rates[m] end,nil,count)
			local row=grouped[1]
			-- An indivisible high-rate drill can make the optimum use fewer
			-- groups. Fill the remaining sides without raising that optimum.
			while #row<count do
				local index
				for j,g in ipairs(row) do
					if #g.miners>1 and (not index or g.rate>row[index].rate) then index=j end
				end
				local group=row[index]
				local sum,best,pivot,left=0,math.huge,1,0
				for j=1,#group.miners-1 do
					sum=sum+rates[group.miners[j]]
					local peak=math.max(sum,group.rate-sum)
					if peak<best then best,pivot,left=peak,j,sum end
				end
				local a,b={miners={},rate=left},{miners={},rate=group.rate-left}
				for j,m in ipairs(group.miners) do
					local side=j<=pivot and a or b;side.miners[#side.miners+1]=m
				end
				row[index]=a;table.insert(row,index+1,b)
			end
			result[i]=row
		end
	end
	return result
end

return capacity
