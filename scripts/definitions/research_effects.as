import research;
from research import TechnologyHook;
import bonus_effects;
from generic_effects import GenericEffect;
import icons;
import util.formatting;

class CivilanHPBonus : TechnologyHook {
	Document doc("Increases civilian HP by a factor.");
	Argument factor(AT_Decimal);

#section server
	void unlock(TechnologyNode@ node, Empire& emp) const {
		emp.ModHP *= factor.decimal;
	}
#section all
};

class SecondaryInfluenceCost : TechnologyHook {
	Document doc("This node's secondary unlock method takes an influence cost.");
	Argument cost(AT_Integer, doc="Influence cost.");

	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const {
		text = format("[img=$1;20/][b][color=$2]$3[/color][/b]",
			getSpriteDesc(icons::Influence), toString(colors::Influence),
			toString(cost.integer));
		return true;
	}

	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const {
		return emp.Influence >= cost.integer;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		if(emp.ForbidSecondaryUnlock == 0)
			desc += "\n\n"+format(locale::ALT_UNLOCK_INFLUENCE, toString(cost.integer, 0));
	}

#section server
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const {
		return emp.consumeInfluence(cost.integer);
	}

	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {
		emp.modInfluence(cost.integer);
	}
#section all
};

class SecondaryMoneyCost : TechnologyHook {
	Document doc("This node's secondary unlock method takes a money cost.");
	Argument cost(AT_Integer, doc="Money cost.");

	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const {
		text = format("[img=$1;20/][b][color=$2]$3[/color][/b]",
			getSpriteDesc(icons::Money), toString(colors::Money),
			formatMoney(cost.integer));
		return true;
	}

	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const {
		return emp.canPay(cost.integer);
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		if(emp.ForbidSecondaryUnlock == 0)
			desc += "\n\n"+format(locale::ALT_UNLOCK_MONEY, formatMoney(cost.integer));
	}

#section server
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const {
		return emp.consumeBudget(cost.integer) != -1;
	}

	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {
		emp.refundBudget(cost.integer, emp.BudgetCycleId);
	}
#section all
};

class SecondaryEnergyCost : TechnologyHook {
	Document doc("This node's secondary unlock method takes a energy cost.");
	Argument cost(AT_Decimal, doc="Energy cost.");

	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const {
		text = format("[img=$1;20/][b][color=$2]$3[/color][/b]",
			getSpriteDesc(icons::Energy), toString(colors::Energy),
			toString(cost.decimal, 0));
		return true;
	}

	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const {
		return emp.EnergyStored >= cost.decimal;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		if(emp.ForbidSecondaryUnlock == 0)
			desc += "\n\n"+format(locale::ALT_UNLOCK_ENERGY, toString(cost.decimal, 0));
	}

#section server
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const {
		return emp.consumeEnergy(cost.decimal, consumePartial=false) >= cost.decimal - 0.001;
	}

	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {
		emp.modEnergyStored(+cost.decimal);
	}
#section all
};

class SecondaryFTLCost : TechnologyHook {
	Document doc("This node's secondary unlock method takes an FTL cost.");
	Argument cost(AT_Decimal, doc="FTL cost.");

	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const {
		text = format("[img=$1;20/][b][color=$2]$3[/color][/b]",
			getSpriteDesc(icons::FTL), toString(colors::FTL),
			toString(cost.decimal, 0));
		return true;
	}

	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const {
		return emp.FTLStored >= cost.decimal;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		if(emp.ForbidSecondaryUnlock == 0)
			desc += "\n\n"+format(locale::ALT_UNLOCK_FTL, toString(cost.decimal, 0));
	}

#section server
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const {
		return emp.consumeFTL(cost.decimal, partial=false, record=false) >= cost.decimal - 0.001;
	}

	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {
		emp.modFTLStored(+cost.decimal);
	}
#section all
};

tidy final class NotSecondary : TechnologyHook {
	Document doc("Only trigger the inner hook if the research was not bought using the secondary method.");
	Argument function(AT_Hook, "research_effects::ITechnologyHook");

#section server
	ITechnologyHook@ hook;
	
	bool instantiate() override {
		@hook = cast<ITechnologyHook>(parseHook(function.str, "research_effects::", required=false));
		if(hook is null) {
			error("NotSecondary(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return TechnologyHook::instantiate();
	}

	void unlock(TechnologyNode@ node, Empire& emp) const {
		if(!node.secondaryUnlock)
			hook.unlock(node, emp);
	}
#section all
};

tidy final class Trigger : TechnologyHook {
	Document doc("Trigger other types of hooks.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");

#section server
	BonusEffect@ hook;
	
	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("Trigger(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return TechnologyHook::instantiate();
	}

	void unlock(TechnologyNode@ node, Empire& emp) const {
		hook.activate(null, emp);
	}
#section all
};

class ResetWhenUnlocked : TechnologyHook {
	Document doc("When this technology is researched, after it triggers its effects it immediately resets the node to no longer be researched, so it can be researched again.");

#section server
	void unlock(TechnologyNode@ node, Empire& emp) const override {
		node.bought = false;
		node.unlocked = false;
		node.available = true;
		node.unlockable = true;
	}
#section all
};

class RequireUnlockTag : TechnologyHook {
	Document doc("This research node can only be researched if a particular unlock tag is unlocked, otherwise it stays unavailable, even if you have a valid path towards it.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in the UnlockTag() or similar hook that should unlock it.");

	bool canUnlock(TechnologyNode@ node, Empire& emp) const override {
		if(!emp.isTagUnlocked(tag.integer))
			return false;
		return true;
	}
};

class ConflictUnlockTag : TechnologyHook {
	Document doc("This research node can only be researched if a particular unlock tag is NOT unlocked, otherwise it will not be available, even if you have a valid path towards it.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in the UnlockTag() or similar hook that should unlock it.");

	bool canUnlock(TechnologyNode@ node, Empire& emp) const override {
		if(emp.isTagUnlocked(tag.integer))
			return false;
		return true;
	}
};

class AutomaticallyUnlocks : TechnologyHook {
	Document doc("This research node automatically unlocks itself when any nodes next to it are unlocked.");

#section server
	void onStateChange(TechnologyNode@ node, Empire@ emp) const {
		if(!node.bought && node.available) {
			node.timer = node.getTimeCost(emp);
			node.bought = true;
		}
	}
#section all
};

class SkipOnUnlockedSubsystem : TechnologyHook {
	Document doc("This node automatically skips and becomes fully unlocked if a subsystem is already unlocked.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to check for.");

	void tick(TechnologyNode@ node, Empire& emp, double time) const override {
		if(!node.bought && node.available) {
			if(emp !is null && emp.isUnlocked(getSubsystemDef(subsystem.integer))) {
				node.timer = 0.001;
				node.bought = true;
			}
		}
	}
};

class SkipOnUnlockedModule : TechnologyHook {
	Document doc("This node automatically skips and becomes fully unlocked if a modifier module is already unlocked.");
	Argument module(AT_Custom, doc="Identifier of the module to check for.");

	void tick(TechnologyNode@ node, Empire& emp, double time) const override {
		if(!node.bought && node.available) {
			bool have = false;
			for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
				auto@ sys = getSubsystemDef(i);
				auto@ mod = sys.module(module.str);
				if(mod !is null) {
					if(emp !is null && emp.isUnlocked(sys, mod)) {
						have = true;
						break;
					}
				}
			}
			if(have) {
				node.timer = 0.001;
				node.bought = true;
			}
		}
	}
};

class SkipOnUnlockedTag : TechnologyHook {
	Document doc("This node automatically skips and becomes fully unlocked if an unlock tag is already unlocked.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

	void tick(TechnologyNode@ node, Empire& emp, double time) const override {
		if(!node.bought && node.available) {
			if(emp !is null && emp.isTagUnlocked(tag.integer)) {
				node.timer = 0.001;
				node.bought = true;
			}
		}
	}
};

class AutoUnlockOnUnlockedTag : TechnologyHook {
	Document doc("This node is automatically and immediately unlocked if a particular unlock tag is present, even if you are not currently adjacent to it.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

	void tick(TechnologyNode@ node, Empire& emp, double time) const override {
		if(!node.unlocked && !node.bought) {
			if(emp !is null && emp.isTagUnlocked(tag.integer)) {
				node.timer = 0.001;
				node.bought = true;
				node.available = true;
				node.unlockable = true;
			}
		}
	}
};

class RequireBuildShipsWith : TechnologyHook {
	Document doc("This technology can only be researched if a certain amount of ships containing a particular subsystem have been constructed.");
	Argument subsystem(AT_Subsystem, doc="Subsystem to check for.");
	Argument amount(AT_Integer, doc="Amount of ships that need to have been constructed.");

	int getCurrent(Empire& emp) const {
		auto@ def = getSubsystemDef(subsystem.integer);
		int count = 0;

		ReadLock lock(emp.designMutex);
		for(uint i = 0, cnt = emp.designCount; i < cnt; ++i) {
			const Design@ dsg = emp.designs[i];
			if(dsg.hasSubsystem(def))
				count += dsg.built;
		}

		return count;
	}

	bool canUnlock(TechnologyNode@ node, Empire& emp) const override {
		return getCurrent(emp) >= amount.integer;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		int count = 0;
		if(emp !is null)
			count = getCurrent(emp);

		Color col;
		if(count >= amount.integer)
			col = colors::Green;
		else
			col = colors::Red;

		auto@ def = getSubsystemDef(subsystem.integer);
		string req = format(locale::RESEARCH_REQ_BUILDSHIPS, toString(amount.integer), def.name, toString(count));
		req = format(locale::RESEARCH_REQ, req, toString(col));
		desc += "\n\n"+req;
	}
};

class RequireEmpireAttributeGTE : TechnologyHook {
	Document doc("This technology can only be researched if an empire attribute has at least a particular value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Required value.");
	Argument text(AT_Locale, doc="Requirement text to display.");

	bool canUnlock(TechnologyNode@ node, Empire& emp) const override {
		return emp.getAttribute(attribute.integer) >= value.decimal;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		double count = 0;
		if(emp !is null)
			count = emp.getAttribute(attribute.integer);

		Color col;
		if(count >= value.decimal)
			col = colors::Green;
		else
			col = colors::Red;

		string req = format(text.str, standardize(count,true), standardize(value.decimal,true));
		req = format(locale::RESEARCH_REQ, req, toString(col));
		desc += "\n\n"+req;
	}
};

class SecretRequiresTrait : TechnologyHook {
	Document doc("Can only be a secret project if you have a particular trait.");
	Argument trait(AT_Trait, doc="Trait to need.");

	bool canBeSecret(TechnologyNode@ node, Empire& emp) const override {
		return emp.hasTrait(trait.integer);
	}
};

class SecretRequiresNotTrait : TechnologyHook {
	Document doc("Can only be a secret project if you do not have a particular trait.");
	Argument trait(AT_Trait, doc="Trait to forbid.");

	bool canBeSecret(TechnologyNode@ node, Empire& emp) const override {
		return !emp.hasTrait(trait.integer);
	}
};

class AffectsTaggedSubsystems : TechnologyHook {
	Document doc("Show a list of subsystems affected by this technology filtered to have a particular subsystem tag.");
	Argument tag(AT_Custom, doc="Tag to check for.");
	SubsystemTag tagId;

	bool instantiate() override {
		if(!TechnologyHook::instantiate())
			return false;
		tagId = getSubsystemTag(tag.str);
		return true;
	}

	void addToDescription(TechnologyNode@ node, Empire@ emp, string& desc) const override {
		string systems;
		array<string> displayed;
		for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			auto@ sys = getSubsystemDef(i);
			if(!sys.hasTag(tagId))
				continue;
			if(sys.hasTag(ST_DontList) && (emp is null || !emp.isUnlocked(sys)))
				continue;
			if(displayed.find(sys.name) != -1)
				continue;

			if(systems.length != 0)
				systems += ", ";
			systems += sys.name;
			displayed.insertLast(sys.name);
		}

		if(systems.length != 0)
			desc += "\n\n"+format(locale::RESEARCH_AFFECTS, systems);
	}
};

class AddPointCostAttribute : TechnologyHook {
	Document doc("Increase the point cost of this node by the value of an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument multiply(AT_Decimal, "1", doc="Multiply the attribute value by this much before adding to the point cost.");

	void modPointCost(const TechnologyNode@ node, Empire& emp, double& pointCost) const override {
		pointCost += emp.getAttribute(attribute.integer) * multiply.decimal;
	}
};

class AddTimeCostAttribute : TechnologyHook {
	Document doc("Increase the time cost of this node by the value of an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument multiply(AT_Decimal, "1", doc="Multiply the attribute value by this much before adding to the time cost.");

	void modTimeCost(const TechnologyNode@ node, Empire& emp, double& timeCost) const override {
		timeCost += emp.getAttribute(attribute.integer) * multiply.decimal;
	}
};
