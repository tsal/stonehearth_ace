local constants = require 'stonehearth.constants'

local BaseJob = class()

--[[
   A base class for all classes. Contains getters for job variables common to all classes
   TODO: Move functions out of classes that inherit from this class if its function is identical to the one here
]]

function BaseJob:initialize()
   self._sv._entity = nil
   self._sv._alias = nil
   self._sv._json_path = nil
   self._sv.last_gained_lv = 1
   self._sv.is_current_class = false
   self._sv.equipment = {}
   self._sv.attained_perks = {}
   -- ADDED FOR ACE
   self._sv.max_num_training = {}

   -- These are for the UI only
   self._sv.is_max_level = false
   self._sv.no_levels = false
   self._sv.is_combat_class = false

   self._xp_rewards = {}
   self._level_data = {}
   self._job_json = nil
   self._max_level = 0
end

function BaseJob:create(entity)
   self._sv._entity = entity
end

function BaseJob:activate()
   self:_load_json_tuning()

   self._job_component = self._sv._entity:get_component('stonehearth:job')

   --If we load and we're the current class, do these things
   if self._sv.is_current_class then
      if self._create_listeners then
         self:_create_listeners()
      end

      self:_register_with_town()
   end
end

function BaseJob:restore()
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function BaseJob:fixup_job_json_path(json_path)
   self._sv._json_path = json_path
   self:_load_json_tuning()
end

function BaseJob:_load_json_tuning()
   if not self._sv._json_path then
      return
   end

   self._job_json = radiant.resources.load_json(self._sv._json_path, true)
   if self._job_json.xp_rewards then
      self._xp_rewards = self._job_json.xp_rewards
   end

   if self._job_json.level_data then
      self._level_data = self._job_json.level_data
   end

   self._max_level = self._job_json.max_level or 0
   
   if self._sv.last_gained_lv >= self._max_level then
      self._sv.is_max_level = true
   else
      self._sv.is_max_level = false
   end
end

function BaseJob:promote(json_path)
   self._sv.is_current_class = true
   self._sv._json_path = json_path
   self:_load_json_tuning()
   local entity = self._sv._entity

   if not self._sv.is_combat_class then
      --Unless you are a combat class (role is combat) remove self
      --from any preexisting parties on promote
      --clear self of any combat commands
      local curr_party = stonehearth.unit_control:get_party_for_entity_command({}, {}, entity)
      if curr_party then
         local party_component = curr_party:get_component('stonehearth:party')
         if party_component then
            party_component:remove_member(entity:get_id())
         end
      end
      stonehearth.combat_server_commands:clear_entity_of_combat_commands(entity:get_id())
   end

   if self._create_listeners then
      self:_create_listeners()
   end

   -- ADDED FOR ACE
   self:_register_with_town()
end

function BaseJob:level_up()
   self._sv.last_gained_lv = self._sv.last_gained_lv + 1

   if self._sv.last_gained_lv >= self._max_level then
      self._sv.is_max_level = true
   end
   self.__saved_variables:mark_changed()
end

-- Returns the level the character has in this class
function BaseJob:get_job_level()
   return self._sv.last_gained_lv
end

-- Returns whether we're at max level.
function BaseJob:is_max_level()
   return self._sv.is_max_level
end

function BaseJob:can_level_up()
   if self._sv.no_levels or self:is_max_level() then
      return false
   end
   return true
end

-- Returns all the data for all the levels
function BaseJob:get_level_data()
   return self._level_data
end

-- Given the ID of a perk, find out if we have the perk. 
function BaseJob:has_perk(id)
   return self._sv.attained_perks[id]
end

function BaseJob:demote()
   self._sv.is_current_class = false

   if self._remove_listeners then
      self:_remove_listeners()
   end

   self.__saved_variables:mark_changed()
   
   -- ADDED FOR ACE
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_placement_slot_entity(self._sv._entity)
   end
   
end

function BaseJob:destroy()
   if self._sv.is_current_class then
      -- if we were destroyed without demote
      if self._remove_listeners then
         self:_remove_listeners()
      end
   end
end

-- We keep an index of perks we've unlocked for easy lookup
function BaseJob:unlock_perk(id)
   self._sv.attained_perks[id] = true
   self.__saved_variables:mark_changed()
end

-- Shared Perk Application functionality
function BaseJob:apply_chained_buff(args)
   radiant.entities.remove_buff(self._sv._entity, args.last_buff)
   radiant.entities.add_buff(self._sv._entity, args.buff_name)   
end

function BaseJob:apply_buff(args)
   radiant.entities.add_buff(self._sv._entity, args.buff_name)   
end

function BaseJob:remove_buff(args)
   radiant.entities.remove_buff(self._sv._entity, args.buff_name)
end

function BaseJob:add_equipment(args)
   local equipment = radiant.entities.create_entity(args.equipment)
   self._sv.equipment[args.equipment] = equipment
   radiant.entities.equip_item(self._sv._entity, equipment)
end

-- Remove equipment from the character
function BaseJob:remove_equipment(args)
   local equipment = self._sv.equipment[args.equipment]
   if equipment then
      radiant.entities.unequip_item(self._sv._entity, equipment)
      radiant.entities.destroy_entity(equipment)
      self._sv.equipment[args.equipment] = nil
   end
end

function BaseJob:apply_chained_equipment(args)
   local old_equipment_args = {
      equipment = args.last_equipment
   }
   self:remove_equipment(old_equipment_args)
   self:add_equipment(args)
end

-- BELOW FUNCTIONS ADDED IN ACE:

function BaseJob:get_all_equipment_preferences()
   if not self._sv.equipment_prefs or not self._sv.equipment_roles_ordered then
      self._sv.equipment_prefs = {}
      self._sv.equipment_roles_ordered = {}
      self._sv.equipment_role = nil

      local equipment_prefs = self._job_json.equipment_preferences
      if equipment_prefs and equipment_prefs.roles then
         for role, prefs in pairs(equipment_prefs.roles) do
            self._sv.equipment_prefs[role] = {types = prefs.types, multiplier = prefs.multiplier, command = prefs.command}
            table.insert(self._sv.equipment_roles_ordered, role)
         end
         table.sort(self._sv.equipment_roles_ordered)
         self._sv.equipment_role = equipment_prefs.default_role
      end

      self.__saved_variables:mark_changed()
   end

   return self._sv.equipment_prefs
end

function BaseJob:get_equipment_preferences()
   local prefs = self:get_all_equipment_preferences()
   local role = self:get_equipment_role()
   return role and prefs and prefs[role]
end

function BaseJob:get_equipment_roles()
   self:get_all_equipment_preferences()
   return self._sv.equipment_roles_ordered
end

function BaseJob:get_equipment_role()
   return self._sv.equipment_role
end

function BaseJob:set_equipment_role(role)
   if self._sv.equipment_role ~= role then
      self._sv.equipment_role = role
      self.__saved_variables:mark_changed()

      radiant.events.trigger(self._sv._entity, 'stonehearth_ace:equipment_role_changed')
      
      return role
   end
end

function BaseJob:set_next_equipment_role(from_role)
   -- if the current equipment role is nil or cannot be found, set the role to the first one
   -- otherwise set it to the next one in the list, wrapping around to the first
   self:get_all_equipment_preferences()
   local roles = self._sv.equipment_roles_ordered
   local cur_role = from_role or self:get_equipment_role()
   local new_role
   local first

   for i, role in ipairs(roles) do
      if not first then
         first = role
      end
      if role == cur_role then
         local temp
         temp, new_role = next(roles, i)
         break
      end
   end

   return self:set_equipment_role(new_role or first)
end

function BaseJob:increase_max_placeable_training(args)
   self._sv.max_num_training = args.max_num_training
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

function BaseJob:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_training)
   end
end

return BaseJob
