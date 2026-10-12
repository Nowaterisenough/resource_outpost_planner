local load={}

load.default_min=0.8
load.default_max=1

function load.valid_range(lower,upper)
	return type(lower)=="number" and type(upper)=="number"
		and lower>=0 and upper>0 and lower<=upper and upper<=100
end

function load.migrate_choices(choices)
	if choices.belt_capacity_choice then choices.belt_merge_choice=true end
	if choices.belt_load_min_choice==nil then choices.belt_load_min_choice=load.default_min end
	if choices.belt_load_max_choice==nil then
		local loss=choices.belt_overflow_percent_choice
		choices.belt_load_max_choice=choices.belt_capacity_choice and type(loss)=="number" and loss>=0 and loss<100
			and 1/(1-loss/100) or load.default_max
	end
	choices.belt_capacity_choice=nil
	choices.belt_overflow_percent_choice=nil
end

function load.ratios(state)
	return state.belt_load_min_choice or load.default_min,state.belt_load_max_choice or load.default_max
end

function load.required_outputs(belts,lane_limit)
	local first,second=0,0
	for _,belt in ipairs(belts or {}) do if belt.is_output then
		first=first+(belt.merged_throughput1 or 0)
		second=second+(belt.merged_throughput2 or 0)
	end end
	return math.ceil(math.max(first,second)/lane_limit-1e-8)
end

function load.loss_percent(belts,lane_capacity,count)
	local total,first,second=0,0,0
	for _,belt in ipairs(belts or {}) do if belt.is_output then
		local a,b=belt.merged_throughput1 or 0,belt.merged_throughput2 or 0
		total=total+a+b
		first=first+math.min(a,lane_capacity)
		second=second+math.min(b,lane_capacity)
	end end
	if count then
		first=math.min(first,count*lane_capacity)
		second=math.min(second,count*lane_capacity)
	end
	return total>0 and math.max(0,1-(first+second)/total)*100 or 0
end

function load.output_warning(required,count,loss)
	if count and (required and count<required or (loss or 0)>1e-8) then
		return {"mpp.belt_capacity_outputs",count,string.format("%.1f",loss or 0)}
	end
end

return load
