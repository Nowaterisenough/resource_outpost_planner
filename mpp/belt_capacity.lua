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
	local limit=capacity.limit(state)
	for _,miner in ipairs(state.best_attempt.miners) do
		local rate=common.get_mining_drill_production_from_state(state,nil,miner)
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

function capacity.row_groups(lanes,lane_count,limit,production,budget)
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
			count=count+#result[i]
		end
		return result,count
	end
	local result,count=group(limit)
	if not budget or count<=budget then return result end
	local best,minimum=group(high)
	if minimum>budget then return best end
	-- Relax the load target only as much as needed to fit the fixed lane budget.
	local low=limit
	for _=1,32 do
		local middle=(low+high)/2
		local candidate,n=group(middle)
		if n<=budget then high=middle;best=candidate else low=middle end
	end
	return best
end

return capacity
