import pickups;
from pickups import IPickupHook, PickupHook;
import hooks;
import bonus_effects;

class OnClear : PickupHook {
	BonusEffect@ hook;

	Document doc("Trigger an effect on the flagship that cleared this camp, immediately.");
	Argument effect(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(effect.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnClear(): could not find inner hook: "+escape(effect.str));
			return false;
		}
		return PickupHook::instantiate();
	}

#section server
	void onClear(Pickup& pickup, Object& obj) const {
		if(hook !is null)
			hook.activate(obj, obj.owner);
	}
#section all
};

class TakeOnClear : PickupHook {
	Document doc("This pickup is immediately taken when the camp is cleared.");

#section server
	void onClear(Pickup& pickup, Object& obj) const {
		auto@ type = getPickupType(pickup.PickupType);
		if(type is null)
			return;

		type.onPickup(pickup, obj);
		pickup.destroy();
	}
#section all
};
