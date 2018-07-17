import generic_effects;
import hooks;

class SubsystemEffect : SubsystemHook, Hook, RegionChangeable, LeaderChangeable {
#section server
	void start(SubsystemEvent& event) const {}
	void tick(SubsystemEvent& event, double time) const {}
	void suspend(SubsystemEvent& event) const {}
	void resume(SubsystemEvent& event) const {}
	void destroy(SubsystemEvent& event) const {}
	void end(SubsystemEvent& event) const {}
	void change(SubsystemEvent& event) const {}
	void ownerChange(SubsystemEvent& event, Empire@ prevOwner, Empire@ newOwner) const {}

	DamageEventStatus damage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position) const {
		return DE_Continue;
	}

	DamageEventStatus globalDamage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position, vec2d& endPoint) const {
		return DE_Continue;
	}

	void preRetrofit(SubsystemEvent& event) const {}
	void postRetrofit(SubsystemEvent& event) const {}

	void save(SubsystemEvent& event, SaveFile& file) const {}
	void load(SubsystemEvent& event, SaveFile& file) const {}
#section all

	void regionChange(SubsystemEvent& event, Region@ prevRegion, Region@ newRegion) const {}
	void leaderChange(SubsystemEvent& event, Object@ prevLeader, Object@ newLeader) const {}
};

class AddSupplyToFleet : SubsystemEffect {
	Document doc("Add a bonus amount of supply storage to the fleet.");
	Argument amount(AT_Decimal, doc="Amount of supply capacity to add.");
	Argument leakpctpersec(AT_Decimal, doc="Drain rate per second when fully damaged.");

#section server
	void tick(SubsystemEvent& event, double time) const override {
		if(event.workingPercent <= 1.0 && leakpctpersec.decimal > 0) {
			Ship@ ship = cast<Ship>(event.obj);
			Ship@ leader = cast<Ship>(ship.Leader);
			if(leader !is null)
				leader.consumeSupply(ship.MaxSupply * leakpctpersec.decimal * (1.0 - sqr(event.workingPercent)) * time);
		}
	}

	void leaderChange(SubsystemEvent& event, Object@ prevLeader, Object@ newLeader) const override {
		if(prevLeader !is null && prevLeader.isShip)
			cast<Ship>(prevLeader).modSupplyBonus(-amount.decimal);
		if(newLeader !is null && newLeader.isShip)
			cast<Ship>(newLeader).modSupplyBonus(+amount.decimal);
	}
#section all
};

class AddPermanentStatus : SubsystemEffect {
	Document doc("Add a status that doesn't go away during a retrofit.");
	Argument status(AT_Status, doc="Status to add.");

#section server
	void start(SubsystemEvent& event) const {
		if(event.obj.hasStatuses && !event.obj.hasStatusEffect(status.integer))
			event.obj.addStatus(status.integer);
	}
#section all
};

class SolarData {
	double timer = 0.0;
	double prevBoost = 0.0;
};

class SolarEfficiency : SubsystemEffect {
	Document doc("Modify the ship's efficiency based on how much light it is getting.");
	Argument loss(AT_Decimal, doc="Amount of efficiency lost when in deep space.");
	Argument min_boost(AT_Decimal, doc="Minimum boost when on a cold star or far away from a star.");
	Argument max_boost(AT_Decimal, doc="Maximum boost when on a hot star or close to a star.");
	Argument power_factor(AT_Boolean, "False", doc="Only apply boosts according to how much of the ship's power is solar power.");
	Argument step(AT_Decimal, "0.05", doc="Only apply changes in steps of this size.");
	Argument temperature_max(AT_Decimal, "15000", doc="Solar temperature (modified by distance) that triggers the maximum boost.");

#section server
	void tick(SubsystemEvent& event, double time) const override {
		SolarData@ dat;
		event.data.retrieve(@dat);
		if(dat is null) {
			@dat = SolarData();
			event.data.store(@dat);
		}

		dat.timer -= time;
		if(dat.timer <= 0) {
			Object@ obj = event.obj;
			Region@ reg = obj.region;

			dat.timer += 1.0;
			if(obj.velocity.lengthSQ <= 1.0 && !obj.inCombat)
				dat.timer += 10.0;

			Ship@ ship = cast<Ship>(obj);
			double powerFactor = event.workingPercent;
			if(ship !is null) {
				const Design@ dsg = ship.blueprint.design;
				if(dsg !is null)
					powerFactor *= dsg.total(SV_SolarPower) / dsg.total(SV_Power);
			}

			double newBoost = 0.0;
			if(reg is null) {
				newBoost = -loss.decimal * powerFactor;
			}
			else {
				double solarFactor = reg.starTemperature * (1.0 - (obj.position.distanceToSQ(reg.position) / sqr(reg.radius)));
				newBoost = min_boost.decimal + clamp(solarFactor / temperature_max.decimal, 0.0, max_boost.decimal);
				newBoost *= powerFactor;
			}

			newBoost = round(newBoost / step.decimal) * step.decimal;
			if(abs(dat.prevBoost - newBoost) >= step.decimal * 0.5) {
				obj.modFleetEffectiveness(newBoost - dat.prevBoost);
				dat.prevBoost = newBoost;
			}
		}
	}

	void save(SubsystemEvent& event, SaveFile& file) const {
		SolarData@ dat;
		event.data.retrieve(@dat);

		if(dat is null) {
			double t = 0.0;
			file << t << t;
		}
		else {
			file << dat.timer;
			file << dat.prevBoost;
		}
	}

	void load(SubsystemEvent& event, SaveFile& file) const {
		SolarData dat;
		event.data.store(@dat);

		file >> dat.timer;
		file >> dat.prevBoost;
	}
#section all
};
