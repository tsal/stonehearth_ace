App.StonehearthZonesModeView.reopen({
   customEntityZoneViews: [],

   // modders can override this function to add their own custom entity zone views
   init: function() {
      var self = this;
      self._super();
      
      self.customEntityZoneViews.push(self._ACE_CustomZoneViews)
   },
   
   _examineEntity: function(entity) {
      var self = this;
      if (!entity && self._propertyView) {
         self._propertyView.destroyWithoutDeselect();
         self._propertyView = null;
         return;
      }

      var viewType = null;
       if (entity['stonehearth:player_market_stall']) {
         viewType = App.StonehearthPlayerMarketStallView;
      } else if (entity['stonehearth:storage'] && entity['stonehearth:storage'].is_public) {
         // TODO: sigh, the above is probably wrong, but highly convenient.
         viewType = App.StonehearthStockpileView;
      } else if (entity['stonehearth:farmer_field']) {
         viewType = App.StonehearthFarmView;
      } else if (entity['stonehearth:trapping_grounds']) {
         viewType = App.StonehearthTrappingGroundsView;
      } else if (entity['stonehearth:mining_zone']) {
         viewType = App.StonehearthMiningZoneView;
      } else if (entity['stonehearth:shepherd_pasture']) {
         viewType = App.StonehearthPastureView;
      }

      if (!viewType) {
         viewType = self._getCustomZoneView(entity);
      }

      if (viewType) {
         self._showZoneUi(entity, viewType);
      } else {
         if (self._propertyView) {
            self._propertyView.destroyWithoutDeselect();
            self._propertyView = null;
         }
      }
   },

   _getCustomZoneView: function(entity) {
      var self = this;
      for (var i = 0; i < self.customEntityZoneViews.length; i++)
      {
         var mode = self.customEntityZoneViews[i](entity);
         if (mode) {
            return mode;
         }
      }
      
      return null;
   },

   _ACE_CustomZoneViews: function(entity) {
      if (entity['stonehearth_ace:grower_underfield']) {
         return App.StonehearthAceUnderfarmView;
      } else if (entity['stonehearth_ace:guard_zone']) {
         return App.StonehearthAceGuardZoneView;
      }

      return null
   }
});
