// other modders can also reopen this, override init, and add their own custom modes and entity mode checks
App.RootView.reopen({
   init: function() {
      this._super();
      var self = this;

      // also apply any stonehearthClient changes we want to make here
      self._applyStonehearthClientChanges();

      self._game_mode_manager.addCustomMode("military", "military"); //, null, "AceMilitaryModeView", true);
      self._game_mode_manager.addCustomMode("connection", "hud");
      self._game_mode_manager.addCustomEntityModeCheck(self._ACE_getCustomModeForEntity);
   },

   _ACE_getCustomModeForEntity: function(modes, entity) {
      if (entity['stonehearth_ace:patrol_banner'] ||            entity['stonehearth:party']) {
         return modes.MILITARY;
      }

      if (entity['stonehearth_ace:connection']) {
         return modes.CONNECTION;
      }

      return null;
   },

   _applyStonehearthClientChanges: function() {
      App.stonehearthClient._placeItemOrItemType = function (placementType, toolName, item, quality) {
         var self = this;
         var placementCall = placementType == 'item' ? 'stonehearth:choose_place_item_location' : 'stonehearth:choose_place_item_type_location';

         radiant.call('stonehearth:check_can_place_item', item, quality)
            .done(function (response) {
               radiant.call('stonehearth_ace:get_custom_tooltip_command', item, 'stonehearth:ui.game.menu.build_menu.items.place_item')
               .done(function (r) {
                  var custom_tooltips = r.custom_tooltips;
                  var tip_title = custom_tooltips.tip_title || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_title';
                  var tip_description = custom_tooltips.tip_description || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_description';
                  var tip_bindings = custom_tooltips.tip_bindings || {left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'};
                  self.showTipWithKeyBindings(tip_title, tip_description, tip_bindings);

                  App.setGameMode('place');
                  return self._callTool(toolName, function() {
                     return radiant.call(placementCall, item, quality)
                        .done(function(response) {
                           radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} )
                           if ((placementType == 'itemType') && response.more_items) {
                              self.placeItemType(item, quality);
                           } else {
                              self.hideTip();
                           }
                        })
                        .fail(function(response) {
                           //App.setGameMode('normal');
                           self.hideTip();
                        })
                        .always(function(response) {
                           if (placementType == 'item') {
                              App.setGameMode('normal');
                              self.hideTip();
                           }
                        });
                  });
               });
            })
            .fail(function(response) {
               self.showTip(i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_title'),
                            i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_description', {
                               tag: i18n.t("i18n(stonehearth:ui.game.unit_frame.placement_tags." + response.placement_tag + ")"),
                               num: response.num_placed || 0,
                               max: response.max_placeable || 0
                            }),
                            {warning: 'warning'});
            });
      };
   }
});