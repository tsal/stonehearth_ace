stonehearth_ace = {}

stonehearth_ace.util = require("lib.util")

local service_creation_order = {
   'connection',
   'crafter_info',
   'water_pump',
   'water_signal',
   'underfarming',
   'mechanical',
   --'vine'
}

local monkey_patches = {
   ace_craft_order_list = 'stonehearth.components.workshop.craft_order_list',
   ace_craft_order = 'stonehearth.components.workshop.craft_order',
   ace_crafter_component = 'stonehearth.components.crafter.crafter_component',
   ace_door_component = 'stonehearth.components.door.door_component',
   ace_portal_component = 'stonehearth.components.portal.portal_component',
   ace_job_component = 'stonehearth.components.job.job_component',
   ace_find_equipment_upgrade_action = 'stonehearth.ai.actions.upgrade_equipment.find_equipment_upgrade_action',
   ace_town_patrol_service = 'stonehearth.services.server.town_patrol.town_patrol_service',
   ace_equipment_piece_component = 'stonehearth.components.equipment_piece.equipment_piece_component',
   ace_farmer_field_component = 'stonehearth.components.farmer_field.farmer_field_component',
   ace_growing_component = 'stonehearth.components.growing.growing_component',
   ace_renewable_resource_node_component = 'stonehearth.components.renewable_resource_node.renewable_resource_node_component',
   ace_resource_node_component = 'stonehearth.components.resource_node.resource_node_component',
   --ace_task_tracker_component = 'stonehearth.components.task_tracker.task_tracker_component', -- only used for individual auto-harvest
   ace_shepherd_pasture_component = 'stonehearth.components.shepherd_pasture.shepherd_pasture_component',
   ace_shepherd_service = 'stonehearth.services.server.shepherd.shepherd_service',
   ace_swimming_service = 'stonehearth.services.server.swimming.swimming_service',
   ace_town_service = 'stonehearth.services.server.town.town_service',
   ace_town = 'stonehearth.services.server.town.town',
   ace_evolve_component = 'stonehearth.components.evolve.evolve_component',
   ace_crafting_progress = 'stonehearth.components.workshop.crafting_progress',
   ace_workshop_component = 'stonehearth.components.workshop.workshop_component',
   ace_craft_items_orchestrator = 'stonehearth.services.server.town.orchestrators.craft_items_orchestrator',
   ace_collect_ingredients_orchestrator = 'stonehearth.services.server.town.orchestrators.collect_ingredients_orchestrator',
   ace_drop_crafting_ingredients = 'stonehearth.ai.actions.drop_crafting_ingredients',
   ace_produce_crafted_items = 'stonehearth.ai.actions.produce_crafted_items',
   ace_trapping_grounds_component = 'stonehearth.components.trapping.trapping_grounds_component',
   ace_collection_quest_shakedown = 'stonehearth.services.server.game_master.controllers.scripts.collection_quest_shakedown',
   ace_firepit_component = 'stonehearth.components.firepit.firepit_component',
   ace_client_state_service = 'stonehearth.services.server.client_state.client_state_service',
   ace_client_state = 'stonehearth.services.server.client_state.client_state',
   ace_loot_drops_component = 'stonehearth.components.loot_drops.loot_drops_component',
   ace_incapacitation_component = 'stonehearth.components.incapacitation.incapacitation_component',
   ace_crafter_jobs_node = 'stonehearth.components.building2.plan.nodes.crafter_jobs_node',
   ace_patrollable_object = 'stonehearth.services.server.town_patrol.patrollable_object',
   ace_get_patrol_route_action = 'stonehearth.ai.actions.get_patrol_route_action',
   ace_party_component = 'stonehearth.components.party.party_component',
   ace_player_service = 'stonehearth.services.server.player.player_service',
   ace_water_component = 'stonehearth.components.water.water_component',
   ace_waterfall_component = 'stonehearth.components.waterfall.waterfall_component',
   ace_commands_component = 'stonehearth.components.commands.commands_component',
   ace_trapper = 'stonehearth.jobs.trapper.trapper'
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.mixin(monkey_do, monkey_see)
   end
end

local function create_service(name)
   local path = string.format('services.server.%s.%s_service', name, name)
   local service = require(path)()

   local saved_variables = stonehearth_ace._sv[name]
   if not saved_variables then
      saved_variables = radiant.create_datastore()
      stonehearth_ace._sv[name] = saved_variables
   end

   service.__saved_variables = saved_variables
   service._sv = saved_variables:get_data()
   saved_variables:set_controller(service)
   saved_variables:set_controller_name('stonehearth_ace:' .. name)
   service:initialize()
   stonehearth_ace[name] = service
end

function stonehearth_ace:_on_init()
   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.log.write_('stonehearth_ace', 0, 'ACE server initialized')
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()
end

radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
