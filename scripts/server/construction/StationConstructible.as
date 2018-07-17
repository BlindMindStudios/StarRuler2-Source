import construction.Constructible;
import construction.ShipConstructible;
import resources;
import object_creation;
import ship_groups;
import util.formatting;

tidy class StationConstructible : ShipConstructible {
	double laborPenalty = 1.0;
	vec3d position;
	Orbital@ target;

	StationConstructible(const Design@ Design, vec3d pos, double penalty) {
		super(Design);
		laborPenalty = penalty;
		position = pos;
		totalLabor *= penalty;
	}

	StationConstructible(SaveFile& msg) {
		super(msg);
		msg >> laborPenalty;
		msg >> position;
		msg >> target;
	}

	void save(SaveFile& msg) {
		ShipConstructible::save(msg);
		msg << laborPenalty;
		msg << position;
		msg << target;
	}

	ConstructibleType get_type() {
		return CT_Station;
	}

	bool repeat(Object& obj) {
		if(!ShipConstructible::repeat(obj))
			return false;
		@target = null;
		double size = stationRadiusFactor * pow(design.size,1.0/shipVolumePower);
		vec2d offset = random2d(size * 2.0, size * 4.0);
		position.x += offset.x;
		position.z += offset.y;
		return true;
	}

	bool pay(Object& obj) {
		if(!ShipConstructible::pay(obj))
			return false;
		double hp = design.totalHP;
		string name = format(locale::NAME_SCAFFOLDING, formatShipName(design));

		@target = createOrbital(position,
				getOrbitalModule("Scaffolding"),
				obj.owner, disabled=true,
				nameOverride=name);
		target.modMaxHealth(hp);
		target.setBuildPct(0.0);
		return true;
	}

	void cancel(Object& obj) {
		if(buildCost != 0 && target !is null) {
			if(!target.valid) {
				buildCost = 0;
			}
			else {
				double maxHealth = target.maxHealth + target.maxArmor;
				double pct = 0.0;
				if(totalLabor > 0)
					maxHealth *= curLabor / totalLabor;
				if(maxHealth != 0)
					pct = clamp((target.health + target.armor) / maxHealth, 0.0, 1.0);
				pct = clamp((pct-0.01) / 0.99, 0.0, 1.0);
				buildCost = int(double(buildCost) * pct);
			}
		}
		ShipConstructible::cancel(obj);
		if(target !is null && target.valid)
			target.destroy();
	}

	TickResult tick(Object& obj, double time) override {
		if(target is null || !target.valid) {
			cancel(obj);
			return TR_Remove;
		}
		target.setBuildPct(curLabor / totalLabor);
		return TR_UsedLabor;
	}

	void complete(Object& obj) {
		Ship@ ship = createShip(target.position, design, obj.owner);
		
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			GroupData@ d = supports[i];
			const Design@ dsg = d.dsg.mostUpdated();
			ship.addSupportOrdered(dsg, d.ordered);
			for(uint n = 0; n < d.amount; ++n)
				createShip(obj, dsg, obj.owner, ship);
		}
		
		obj.doRally(ship);
		if(target !is null && target.valid) {
			ship.setHealthPct(target.health / target.maxHealth);
			target.destroy();
		}

		obj.owner.recordStatDelta(stat::ShipsBuilt, 1);
		obj.owner.notifyFlagship(ship);
	}

	void write(Message& msg) {
		Constructible::write(msg);
		msg << design;

		uint cnt = supports.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << supports[i];
	}

	bool addSupports(Object& obj, const Design@ dsg, uint amount, int cycle = -1) override {
		if(target is null)
			return false;
		Region@ myRegion = obj.region;
		Region@ targRegion = target.region;
		if(myRegion is null || myRegion !is targRegion)
			return false;
		ShipConstructible::addSupports(obj, dsg, amount, cycle=cycle);
		return true;
	}

	double addSupportLabor(double amount) {
		if(supports.length == 0)
			return amount;
		if(!paid)
			return amount;

		savedLabor += amount / laborPenalty;

		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			GroupData@ d = supports[i];
			if(d.ordered > 0) {
				double laborCost = getLaborCost(d.dsg);
				if(savedLabor < laborCost)
					return 0.0;

				while(d.ordered > 0 && savedLabor >= laborCost) {
					savedLabor -= laborCost;
					d.amount += 1;
					d.ordered -= 1;
				}

				if(d.ordered > 0)
					return 0.0;
			}
		}

		savedLabor = 0.0;
		return savedLabor;
	}
};
