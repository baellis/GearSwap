-------------------------------------------------------------------------------------------------------------------
-- Setup functions for this job.  Generally should not be modified.
-------------------------------------------------------------------------------------------------------------------

-- Initialization function for this job file.
function get_sets()
    -- Load and initialize the include file.
    include('Sel-Include.lua')
end


-- Setup vars that are user-independent.  state.Buff vars initialized here will automatically be tracked.
function job_setup()

    state.Buff['Aftermath: Lv.3'] = buffactive['Aftermath: Lv.3'] or false
    state.Buff['Hundred Fists'] = buffactive['Hundred Fists'] or false
	state.Buff['Impetus'] = buffactive['Impetus'] or false
	
	state.AutoBoost = M(true, 'Auto Boost Mode')
	
	--List of which WS you plan to use TP bonus WS with.
	moonshade_ws = S{'Victory Smite'}
	
	autows = 'Victory Smite'
	autofood = 'Soy Ramen'
	
    info.impetus_hit_count = 0
    windower.raw_register_event('action', on_action_for_impetus)
	update_melee_groups()
	init_job_states({"Capacity","AutoRuneMode","AutoTrustMode","AutoWSMode","AutoFoodMode","AutoStunMode","AutoDefenseMode"},{"OffenseMode","WeaponskillMode","IdleMode","Passive","RuneElement","TreasureMode",})
end

-------------------------------------------------------------------------------------------------------------------
-- Job-specific hooks for standard casting events.
-------------------------------------------------------------------------------------------------------------------
-- Set eventArgs.handled to true if we don't want any automatic gear equipping to be done.
-- Set eventArgs.useMidcastGear to true if we want midcast gear equipped on precast.

function job_filtered_action(spell, eventArgs)

end

function job_pretarget(spell, spellMap, eventArgs)

end

function job_precast(spell, spellMap, eventArgs)

	if spell.type == 'WeaponSkill' then
		local abil_recasts = windower.ffxi.get_ability_recasts()
		if abil_recasts[16] == 0 and state.AutoBoost.value then
			cast_delay(1.1)
			send_command('@input /ja "Boost" <me>')
			return
		end
	end

end

-- Run after the general precast() is done.
function job_post_precast(spell, spellMap, eventArgs)
    if spell.type == 'WeaponSkill' and state.DefenseMode.current == 'None' then
        if buffactive.Impetus and (spell.english == "Ascetic's Fury" or spell.english == "Victory Smite") then
			equip(sets.buff.Impetus)
        end
        
		if buffactive.Footwork and (spell.english == "Dragon Kick" or spell.english == "Tornado Kick") then
            equip(sets.FootworkWS)
        end
		
        -- Replace Moonshade Earring if we're at cap TP
        if player.tp == 3000 and moonshade_ws:contains(spell.english) then
			if state.WeaponskillMode.Current:contains('Acc') then
				if sets.precast.AccMaxTP then
					equip(sets.precast.AccMaxTP)
				end
						
			elseif sets.precast.MaxTP then
					equip(sets.precast.MaxTP)
			end

        end
        
    end
end

function job_aftercast(spell, spellMap, eventArgs)

end

-------------------------------------------------------------------------------------------------------------------
-- Job-specific hooks for non-casting events.
-------------------------------------------------------------------------------------------------------------------

-- Called when a player gains or loses a buff.
-- buff == buff gained or lost
-- gain == true if the buff was gained, false if it was lost.
function job_buff_change(buff, gain)
	update_melee_groups()
end

-------------------------------------------------------------------------------------------------------------------
-- User code that supplements standard library decisions.
-------------------------------------------------------------------------------------------------------------------

-- Modify the default melee set after it was constructed.
function job_customize_melee_set(meleeSet)

    if state.ExtraMeleeMode.value ~= 'None' then
        meleeSet = set_combine(meleeSet, sets[state.ExtraMeleeMode.value])
    end
	
    if buffactive.Impetus and state.DefenseMode.value == 'None' and state.OffenseMode.value ~= 'FullAcc' then
		meleeSet = set_combine(meleeSet, sets.buff.Impetus)
    end
	
    if buffactive.Footwork and state.DefenseMode.value == 'None' and state.OffenseMode.value ~= 'FullAcc' then
		meleeSet = set_combine(meleeSet, sets.buff.Footwork)
    end
	
    return meleeSet
end

function job_customize_defense_set(defenseSet)
    if state.ExtraMeleeMode.value ~= 'None' then
        defenseSet = set_combine(defenseSet, sets[state.ExtraMeleeMode.value])
    end

    return defenseSet
end

function job_customize_idle_set(idleSet)

    return idleSet
end

-- Called by the 'update' self-command.
function job_update(cmdParams, eventArgs)
    update_combat_form()
    update_melee_groups()
end

-------------------------------------------------------------------------------------------------------------------
-- Utility functions specific to this job.
-------------------------------------------------------------------------------------------------------------------

function update_combat_form()
    if buffactive.footwork and not buffactive['hundred fists'] then
        state.CombatForm:set('Footwork')
    else
        state.CombatForm:reset()
    end
end

-------------------------------------------------------------------------------------------------------------------
-- Custom event hooks.
-------------------------------------------------------------------------------------------------------------------

-- Keep track of the current hit count while Impetus is up.
function on_action_for_impetus(action)
    if state.Buff.Impetus then
        -- count melee hits by player
        if action.actor_id == player.id then
            if action.category == 1 then
                for _,target in pairs(action.targets) do
                    for _,action in pairs(target.actions) do
                        -- Reactions (bitset):
                        -- 1 = evade
                        -- 2 = parry
                        -- 4 = block/guard
                        -- 8 = hit
                        -- 16 = JA/weaponskill?
                        -- If action.reaction has bits 1 or 2 set, it missed or was parried. Reset count.
                        if (action.reaction % 4) > 0 then
                            info.impetus_hit_count = 0
                        else
                            info.impetus_hit_count = info.impetus_hit_count + 1
                        end
                    end
                end
            elseif action.category == 3 then
                -- Missed weaponskill hits will reset the counter.  Can we tell?
                -- Reaction always seems to be 24 (what does this value mean? 8=hit, 16=?)
                -- Can't tell if any hits were missed, so have to assume all hit.
                -- Increment by the minimum number of weaponskill hits: 2.
                for _,target in pairs(action.targets) do
                    for _,action in pairs(target.actions) do
                        -- This will only be if the entire weaponskill missed or was parried.
                        if (action.reaction % 4) > 0 then
                            info.impetus_hit_count = 0
                        else
                            info.impetus_hit_count = info.impetus_hit_count + 2
                        end
                    end
                end
            end
        elseif action.actor_id ~= player.id and action.category == 1 then
            -- If mob hits the player, check for counters.
            for _,target in pairs(action.targets) do
                if target.id == player.id then
                    for _,action in pairs(target.actions) do
                        -- Spike effect animation:
                        -- 63 = counter
                        -- ?? = missed counter
                        if action.has_spike_effect then
                            -- spike_effect_message of 592 == missed counter
                            if action.spike_effect_message == 592 then
                                info.impetus_hit_count = 0
                            elseif action.spike_effect_animation == 63 then
                                info.impetus_hit_count = info.impetus_hit_count + 1
                            end
                        end
                    end
                end
            end
        end
        
        --add_to_chat(123,'Current Impetus hit count = ' .. tostring(info.impetus_hit_count))
    else
        info.impetus_hit_count = 0
    end
    
end

function job_self_command(commandArgs, eventArgs)

end

function job_tick()
	return false
end


function update_melee_groups()
    classes.CustomMeleeGroups:clear()

	if player.equipment.main and player.equipment.main == "Glanzfaust" and state.Buff['Aftermath: Lv.3'] then
		classes.CustomMeleeGroups:append('AM')
	end
	
    if state.Buff['Hundred Fists'] then
        classes.CustomMeleeGroups:append('HF')
    end
end