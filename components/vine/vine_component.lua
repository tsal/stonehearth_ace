--[[
   vines are complicated enough as cubic entities, we're going to assume that's the only shape they can be
   if someone wants another shape, they'll just have to mod it themselves
   also assume the vine is only 1x1x1 because otherwise it significantly increases the complexity of neighbor checks
   also assume the model is centered at 0.5, 0.5
]]
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local RegionCollisionType = _radiant.om.RegionCollisionShape
local rng = _radiant.math.get_default_rng()

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local ConnectionUtils = require 'lib.connection.connection_utils'
local log = radiant.log.create_logger('vine_component')

local VineComponent = class()

local _origin = Point3(0.5, 0, 0.5)
local _region = Region3(Cube3(Point3.zero, Point3.one))
local _directions = {
   ['x-'] = Point3(-1, 0, 0),
   ['x+'] = Point3(1, 0, 0),
   ['z-'] = Point3(0, 0, -1),
   ['z+'] = Point3(0, 0, 1),
   ['y-'] = Point3(0, -1, 0),
   ['y+'] = Point3(0, 1, 0)
}
local STRUCTURE_URI = 'stonehearth:build2:entities:structure'

function VineComponent:initialize()
   if not self._sv.render_directions then
      self._sv.render_directions = {}
      self.__saved_variables:mark_changed()
   end
end

function VineComponent:activate()
   self._uri = self._entity:get_uri()
   self._growth_data = stonehearth_ace.vine:get_growth_data(self._uri) or {}
   for dir, chance in pairs(self._growth_data.growth_directions or {}) do
      if chance <= 0 then
         self._growth_data.growth_directions[dir] = nil
      end
   end
   self._growth_roller = WeightedSet(rng)

   self._connection_data = self._entity:get_component('stonehearth_ace:connection'):get_connections(self._uri)

   self._parent_trace = self._entity:add_component('mob'):trace_parent('vine entity added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
   :on_changed(function(parent_entity)
      self:_set_render_directions()
   end)
end

function VineComponent:destroy()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function VineComponent:get_render_directions()
   if not next(self._sv.render_directions) then
      self:_set_render_directions()
   end

   return self._sv.render_directions
end

-- determine what sides of the voxel the vine should be rendered on
function VineComponent:_set_render_directions()
   local neighbors = self:get_neighbors(true)
   --log:error('setting render directions from neighbors: %s', radiant.util.table_tostring(neighbors))
   local render_dirs = {}
   -- the vine should render anywhere it's alongside terrain and anywhere it's connecting to another vine
   for dir, neighbor in pairs(neighbors) do
      local dir_permitted = (dir == 'y-' and self._growth_data.grows_on_ground) or
                           (dir == 'y+' and self._growth_data.grows_on_ceiling) or
                           (dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_wall)
      if dir_permitted then
         if neighbor.is_growable_surface then
            render_dirs[dir] = true
         elseif neighbor.vine and dir == 'y+' then
            -- if the vine is hanging down from above, make sure we render on the same side(s)
            -- it's okay that this is recursive because it's only recursive in a single direction: up
            local neighbor_render_dirs = neighbor.vine:get_component('stonehearth_ace:vine'):get_render_directions()

            for n_dir, _ in pairs(neighbor_render_dirs) do
               if n_dir ~= 'y+' and n_dir ~= 'y-' then
                  render_dirs[n_dir] = true
               end
            end
         end
      end
   end

   self._sv.render_directions = render_dirs
   self.__saved_variables:mark_changed()
end

-- try to grow another vine of the same type in a random direction; returns the new entity if successful
function VineComponent:try_grow()
   local neighbors = self:get_neighbors(true)
   if not next(neighbors) then
      return
   end

   self._growth_roller:clear()
   for dir, point in pairs(_directions) do
      local neighbor = neighbors[dir]
      local dir_chance = self._growth_data.growth_directions
      if dir_chance and dir_chance[dir] and neighbor and not neighbor.blocked then
         -- we can consider this space for growth
         -- however, we only want to grow in specific ways:
         --    - along a terrain wall (or possibly structure) in four cardinal directions
         --    - along the ground (or possibly structure) in four cardinal directions (but consider all six because of orientation)
         --    - along the ceiling (or possibly structure) in four cardinal directions
         --    - downward from a hanging vine
         -- so wherever we want to grow should share at least one horizontal growable surface neighbor direction
         -- or be downward growth with grows_hanging is true
         
         local add_dir = false

         if dir == 'y-' and self._growth_data.grows_hanging then
            add_dir = true
         else
            local new_neighbors = self:_eval_neighbors_at(neighbor.location, 0)
            if dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_ground and neighbors['y-'] and neighbors['y-'].is_growable_surface
                  and new_neighbors['y-'] and new_neighbors['y-'].is_growable_surface then
               add_dir = true
            elseif dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_ceiling and neighbors['y+'] and neighbors['y+'].is_growable_surface
                  and new_neighbors['y+'] and new_neighbors['y+'].is_growable_surface then
               add_dir = true
            elseif self._growth_data.grows_on_wall then
               for grow_dir, _ in pairs(_directions) do
                  if neighbors[grow_dir] and neighbors[grow_dir].is_growable_surface and new_neighbors[grow_dir] and new_neighbors[grow_dir].is_growable_surface then
                     add_dir = true
                     break
                  end
               end
            end
         end

         if add_dir then
            --log:spam('adding growth dir chance for %s %s (%s)', self._entity, dir, dir_chance[dir])
            self._growth_roller:add(neighbor.location, dir_chance[dir])
         end
      end
   end

   if not self._growth_roller:is_empty() then
      local grow_location = self._growth_roller:choose_random()
      local new_vine = radiant.entities.create_entity(self._uri, { owner = self._entity:get_player_id() })
      radiant.terrain.place_entity_at_exact_location(new_vine, grow_location, {force_iconic = false})
      return new_vine
   end
end

function VineComponent:get_neighbors(force_eval)
   force_eval = force_eval or not self._sv.neighbors
   if force_eval then
      self:_eval_neighbors()
   end

   return self._sv.neighbors
end

function VineComponent:_eval_neighbors()
   local location = radiant.entities.get_world_grid_location(self._entity)

   if location then
      local facing = radiant.entities.get_facing(self._entity)
      self._sv.neighbors = self:_eval_neighbors_at(location, facing)
   else
      self._sv.neighbors = {}
   end
   self.__saved_variables:mark_changed()
end

function VineComponent:_eval_neighbors_at(location, facing)
   local neighbors = {}
   
   -- check in each direction
   for dir, point in pairs(_directions) do
      local neighbor = {}

      neighbor.location = location + point --+ radiant.math.rotate_about_y_axis(point, facing)
      neighbor.region = _region:translated(neighbor.location)

      -- first check if it's terrain
      local tag = radiant.terrain.get_block_tag_at(neighbor.location)
      neighbor.is_growable_surface = tag and tag ~= 0

      if neighbor.is_growable_surface then
         neighbor.blocked = true
      else
         -- if it's not terrain (i.e., it's null/air), check if any entities there are vines or solid
         for _, entity in pairs(radiant.terrain.get_entities_in_region(neighbor.region)) do
            if entity:get_uri() == self._uri then
               neighbor.vine = entity
               neighbor.blocked = true
               break
            elseif entity:get_uri() == STRUCTURE_URI then
               if self._growth_data.grows_on_structure then
                  neighbor.is_growable_surface = true
               end
               neighbor.blocked = true
               break
            else
               local collision = entity:get_component('region_collision_shape')
               local type = collision and collision:get_region_collision_type()
               if type == RegionCollisionType.SOLID or type == RegionCollisionType.PLATFORM then
                  neighbor.blocked = true
               end
            end
         end
      end

      neighbors[dir] = neighbor
   end

   return neighbors
end

return VineComponent
