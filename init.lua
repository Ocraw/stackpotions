-- All functions taken from mineclonia and adapted where needed.

stackpotions = {}
stackpotions.stack_n = minetest.settings:get("stackpotions_count") or 9
stackpotions.stands_node_names = {
  "mcl_brewing:stand_000",
  "mcl_brewing:stand_100",
  "mcl_brewing:stand_010",
  "mcl_brewing:stand_001",
  "mcl_brewing:stand_110",
  "mcl_brewing:stand_101",
  "mcl_brewing:stand_011",
  "mcl_brewing:stand_111",
}

local function brewable(inv)

	local ingredient = inv:get_stack("input",1):get_name()
	local stands = {}
	local stand_size = inv:get_size("stand")
	local was_alchemy = {false,false,false}

	local bottle, alchemy

	for i=1,stand_size do

		bottle = inv:get_stack("stand", i)
		alchemy = mcl_potions.get_alchemy(ingredient, bottle)

		if alchemy then
			stands[i] = alchemy
			was_alchemy[i] = true
		else
			stands[i] = bottle
		end

	end
	-- if any stand holds a new potion, return the list of new potions
	for i=1,#was_alchemy do
		if was_alchemy[i] then return stands end
	end

	return false
end

local BREW_TIME = 10 -- all brews brew the same
local BURN_TIME = BREW_TIME * 20

local function take_fuel (pos, meta, inv)
	-- only allow blaze powder fuel
	local fuel_name, fuel_count
	fuel_name = inv:get_stack ("fuel", 1):get_name ()
	fuel_count = inv:get_stack ("fuel", 1):get_count ()

	if fuel_name == "mcl_mobitems:blaze_powder" then -- Grab another fuel
	if (fuel_count-1) ~= 0 then
		inv:set_stack("fuel", 1, fuel_name.." "..(fuel_count-1))
	else
		inv:set_stack("fuel", 1, "")
	end
	return BURN_TIME -- New value of fuel_timer_new
	else -- no fuel available
	return 0
	end
end

local function brewing_stand_timer(pos, elapsed)
	-- Inizialize metadata
	local meta = minetest.get_meta(pos)

	-- Number of seconds of fuel remaining to be consumed.
	local fuel_timer = meta:get_float ("fuel_timer_new")
	local stand_timer = meta:get_float ("stand_timer")
	local inv = meta:get_inventory ()
	local brew_output, d
	local input_count, formspec, fuel_percent, brew_percent

	brew_output = brewable(inv)
	if brew_output then
		if fuel_timer <= 0 then -- Is more fuel required?
		fuel_timer = take_fuel (pos, meta, inv)
		end

		-- If enough fuel remains, continue.
		if fuel_timer > 0 then
		fuel_timer = fuel_timer - elapsed
		stand_timer = stand_timer + elapsed
		d = 0.5
		minetest.add_particlespawner({
			amount = 4,
			time = 1,
			minpos = {x=pos.x-d, y=pos.y+0.5, z=pos.z-d},
			maxpos = {x=pos.x+d, y=pos.y+2, z=pos.z+d},
			minvel = {x=-0.1, y=0, z=-0.1},
			maxvel = {x=0.1, y=0.5, z=0.1},
			minacc = {x=-0.05, y=0, z=-0.05},
			maxacc = {x=0.05, y=.1, z=0.05},
			minexptime = 1,
			maxexptime = 2,
			minsize = 0.5,
			maxsize = 2,
			collisiondetection = true,
			vertical = false,
			texture = "mcl_brewing_bubble_sprite.png",
		})

		-- Replace the stand item with the brew result
		if stand_timer >= BREW_TIME then
			input_count = inv:get_stack("input",1):get_count()
			if (input_count-1) ~= 0 then
			local stack
				= inv:get_stack("input",1):get_name().." "..(input_count-1)
			inv:set_stack("input", 1, stack)
			else
			inv:set_stack("input", 1, "")
			end

			for i=1, inv:get_size("stand") do
			if brew_output[i] then
				minetest.sound_play("mcl_brewing_complete",
						{pos=pos, gain=0.4, max_hear_range=6}, true)
				inv:set_stack ("stand", i, brew_output[i])
				minetest.sound_play("mcl_potions_bottle_pour",
						{pos=pos, gain=0.6, max_hear_range=6}, true)
			end
			end
			stand_timer = 0
		end
		end
	end

	-- The formspec must be updated after each change.
	fuel_percent = 100 - math.floor (math.max (fuel_timer, 0)
					 / BURN_TIME * 100)
	brew_percent = math.floor(stand_timer/BREW_TIME*100)
	formspec = active_brewing_formspec(fuel_percent, brew_percent*1 % 100)

	local value = true
	-- If the stand becomes inactive, as when no fuel remains or
	-- no valid recipe exists, cancel the timer.
	if fuel_timer <= 0 or not brew_output then
		minetest.get_node_timer (pos):stop ()
		value = false
	end

	meta:set_float("fuel_timer_new", fuel_timer)
	meta:set_float("stand_timer", stand_timer)
	meta:set_string("formspec", formspec)
	return value
end

local function sort_stack(stack)
	if stack:get_name() == "mcl_mobitems:blaze_powder" then
		return "fuel"
	end
	if minetest.get_item_group(stack:get_name(), "brewing_ingredient" ) > 0 then
		return "input"
	end
	-- Removed glass bottle as it doesn't seem to be used in the stand
	for _, g in pairs({"potion", "splash_potion", "ling_potion", "water_bottle"}) do
		if minetest.get_item_group(stack:get_name(), g ) > 0 then
			return "stand"
		end
	end
end

function stackpotions.allow_put(pos, listname, stack_id, stack, player)
	local name = player:get_player_name()
	if minetest.is_protected(pos, name) then
		minetest.record_protection_violation(pos, name)
		return 0
	end
	local inv = minetest.get_meta(pos):get_inventory()
	local trg = sort_stack(stack)
	local trg_stack = inv:get_stack("stand", stack_id)
	if listname == "stand" then
	  -- If any item is already in stand list[id], no allowed put there
		--if trg ~= "stand" or ((trg_stack:get_count() > 0) and (trg_stack:get_meta() == stack:get_meta())) then
		if trg ~= "stand" or (trg_stack:get_count() > 0) then
			return 0
		end
		return 1
	elseif listname == "fuel" then
		if trg ~= "fuel" then return 0 end
	elseif listname == "sorter" then
		if trg then
		    if trg == "stand" then
		      local r = 0
		      -- Iterate stand list to get the number of allowed potions
		      -- based on how many are already in
		      for i=1,inv:get_size("stand") do
		        local trg_stack = inv:get_stack("stand", i)
		        --if not ((trg_stack:get_count() > 0) and (trg_stack:get_meta() == stack:get_meta())) then
		        if not (trg_stack:get_count() > 0) then
		          r = r + 1
		        end
		      end
		      -- Returning calculated allowed
		      return r
		    end

			local stack1 = ItemStack(stack):take_item()
			if inv:room_for_item(trg, stack) then
				return stack:get_count()
			elseif inv:room_for_item(trg, stack1) then
				return stack:get_stack_max() - inv:get_stack(trg, 1):get_count()
			end
		end
		return 0
	end
	return stack:get_count()
end

local function start_stand_if_not_empty(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local str = ""
	for i=1, inv:get_size("stand") do
		local stack = inv:get_stack("stand", i)
		if not stack:is_empty() then
			str = str.."1"
		else str = str.."0"
		end
	end
	minetest.swap_node(pos, {name = "mcl_brewing:stand_"..str})
	minetest.get_node_timer(pos):start(1.0)
end

function stackpotions.on_put(pos, listname, stack_id, stack, player)
	local meta = minetest.get_meta (pos)
	local inv = meta:get_inventory ()
	local s_flag_in

	if listname == "sorter" then
		listname = sort_stack (stack)
		if not (listname == "stand") then
		  inv:add_item(listname, stack)
		else
		  -- Set the number of potions just inserted in the sorter
		  s_flag_in = inv:get_stack("sorter", 1):get_count()
	    end
		inv:set_stack("sorter", 1, ItemStack(""))
	end

	if listname == "fuel" then
		-- Refuel immediately if no fuel remains.
		local fuel_timer = meta:get_float ("fuel_timer_new")
		if fuel_timer <= 0 then
		fuel_timer = take_fuel (pos, meta, inv)
		meta:set_float ("fuel_timer_new", fuel_timer)
		end
	end

	if listname == "stand" then
	  local new_stack = ItemStack(stack)
	  new_stack:set_count(1)
	  local r=0
	  if s_flag_in then
	    -- Iterate for how many potions were inserted
	    for _=1, s_flag_in do
	      -- Iterate stand slots and set potion only if not already in.
	      for i=1, inv:get_size(listname) do
	        local trg_stack = inv:get_stack(listname, i)
	        --if not ((trg_stack:get_count() > 0) and (trg_stack:get_meta() == stack:get_meta())) then
	        if not (trg_stack:get_count() > 0) then
	  	      inv:set_stack(listname, i, new_stack)
	  	      break
	  	    end
	  	  end
	    end
		start_stand_if_not_empty(pos)
		return
	  end
    end
	minetest.get_node_timer (pos):start (1.0)
end

function stackpotions.allow_move(pos, from_list, from_index, to_list, to_index, count, player)
	if from_list == "sorter" or to_list == "sorter" then return 0 end
	local inv = minetest.get_meta(pos):get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	local trg = sort_stack(stack)
	-- Work around double-clicking potions inside stand somehow letting
	-- them stack, we just not allow moving in stand list.
	if trg == "stand" then return 0 end
	if trg == to_list then return count end
	return 0
end

function stackpotions.hopper_in(pos, to_pos)
	local sinv = minetest.get_inventory({type="node", pos = pos})
	local dinv = minetest.get_inventory({type="node", pos = to_pos})
	if pos.y == to_pos.y then
		local slot_id,_ = mcl_util.get_eligible_transfer_item_slot(sinv, "main", dinv, "fuel", function(itemstack)
			return itemstack:get_name() == "mcl_mobitems:blaze_powder"
		end)
		if slot_id then
			mcl_util.move_item(sinv, "main", slot_id, dinv, "fuel")
			minetest.get_node_timer(to_pos):start(1.0)
		else
			local slot_id,_ = mcl_util.get_eligible_transfer_item_slot(sinv, "main", dinv, "stand", function(itemstack)
				return sort_stack (itemstack) == "stand"
			end)
			if slot_id then
			  local stack = sinv:get_stack("main", slot_id)
			  local new_stack = ItemStack(stack)
			  for i=1, dinv:get_size("stand") do
			    -- Iterate and take/set only if not already in.
			    if not (dinv:get_stack("stand", i):get_count() > 0) then
			      new_stack:set_count(1)
			      dinv:set_stack("stand", i, new_stack)
			      stack:take_item()
			      sinv:set_stack("main", slot_id, stack)
				  start_stand_if_not_empty(to_pos)
				  break
			    end
			  end
			end
		end
		return true
	end
	local slot_id,_ = mcl_util.get_eligible_transfer_item_slot(sinv, "main", dinv, "input", function(itemstack)
		return minetest.get_item_group(itemstack:get_name(), "brewing_ingredient" ) > 0
	end)
	if slot_id then
		mcl_util.move_item(sinv, "main", slot_id, dinv, "input")
		minetest.get_node_timer(to_pos):start(1.0)
	end
	return true
end

-- Here we just update the brewing stand node appaerance.
function stackpotions.hopper_out(pos, to_pos)
	local sinv = minetest.get_inventory({type="node", pos = pos})
	local dinv = minetest.get_inventory({type="node", pos = to_pos})
	local slot_id,_ = mcl_util.get_eligible_transfer_item_slot(sinv, "stand", dinv, "main", nil)
	if slot_id then
		mcl_util.move_item(sinv, "stand", slot_id, dinv, "main")
	end
	start_stand_if_not_empty(pos)
	return true
end

minetest.register_on_mods_loaded(function()
  -- Override stands
  for _,s in pairs(stackpotions.stands_node_names) do
    minetest.override_item(s, {
	allow_metadata_inventory_put = stackpotions.allow_put,
	allow_metadata_inventory_move = stackpotions.allow_move,
	on_metadata_inventory_put = stackpotions.on_put,
	on_metadata_inventory_take = stackpotions.start_stand_if_not_empty,
	_on_hopper_in = stackpotions.hopper_in,
	_on_hopper_out = stackpotions.hopper_out,
    })
  end
  -- Override potions
  local i=0
  for name,def in pairs(minetest.registered_items) do
    if string.find(name, "mcl_potions:") then
      if def.stack_max == 1 then
        minetest.override_item(name, {stack_max = stackpotions.stack_n})
        i=i+1
      end
    end
  end
  minetest.log("action", "Stackpotions: overridden "..i.." potions to stack in " ..stackpotions.stack_n)
end)

