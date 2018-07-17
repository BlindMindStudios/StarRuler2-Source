import construction.Constructible;
import resources;
import object_creation;
import ship_groups;
import cargo;

tidy class ShipConstructible : Constructible {
	const Design@ design;
	array<GroupData@> supports;
	double savedLabor = 0;
	Object@ constructFrom;

	ShipConstructible(const Design@ Design) {
		if(Design.outdated)
			@Design = Design.owner.updateDesign(Design, true);
		@design = Design;
		getBuildCost(design, buildCost, maintainCost, totalLabor, 1);
	}

	ShipConstructible(SaveFile& msg) {
		Constructible::load(msg);

		uint dsgId = 0;
		Empire@ owner;
		msg >> owner;
		msg >> dsgId;
		@design = owner.getDesign(dsgId);

		if(msg >= SV_0149)
			msg >> constructFrom;

		uint cnt = 0;
		msg >> cnt;
		supports.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			GroupData dat;
			msg >> dat;
			@supports[i] = dat;
		}
		msg >> savedLabor;
	}

	void save(SaveFile& msg) {
		Constructible::save(msg);
		msg << design.owner;
		msg << design.id;
		msg << constructFrom;

		uint cnt = supports.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << supports[i];
		msg << savedLabor;
	}

	bool pay(Object& obj) {
		if(!payDesignCosts(obj, design))
			return false;
		if(!Constructible::pay(obj)) {
			reverseDesignCosts(obj, design);
			return false;
		}
		for(uint i = 0, cnt = supports.length; i < cnt; ++i)
			supports[i].orderCycle = obj.owner.BudgetCycleId;
		return true;
	}

	bool repeat(Object& obj) {
		if(!Constructible::repeat(obj))
			return false;
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			@supports[i].dsg = supports[i].dsg.mostUpdated();
			supports[i].ordered += supports[i].amount;
			supports[i].amount = 0;
		}
		return true;
	}

	void cancel(Object& obj) {
		reverseDesignCosts(obj, design, cancel=true);
		Constructible::cancel(obj);
	}

	string get_name() {
		return design.name;
	}

	ConstructibleType get_type() {
		return CT_Flagship;
	}

	void complete(Object& obj) {
		double hpBonus = obj.constructionHPBonus;

		Object@ spawnFrom;
		if(constructFrom !is null && constructFrom.valid && constructFrom.owner is obj.owner)
			@spawnFrom = constructFrom;
		else
			@spawnFrom = obj;

		Ship@ ship = createShip(spawnFrom, design);
		if(hpBonus != 0)
			ship.modHPFactor(+hpBonus);
		
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			GroupData@ d = supports[i];
			const Design@ dsg = d.dsg.mostUpdated();
			ship.addSupportOrdered(dsg, d.ordered);
			for(uint n = 0; n < d.amount; ++n) {
				Ship@ sup = createShip(spawnFrom, dsg, obj.owner, ship);
				if(hpBonus != 0)
					sup.modHPFactor(+hpBonus);
			}
		}
		
		spawnFrom.doRally(ship);

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

	bool addSupports(Object& obj, const Design@ dsg, uint amount, int cycle = -1) {
		GroupData@ d;
		@dsg = dsg.mostUpdated();
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			if(supports[i].dsg.mostUpdated() is dsg) {
				@d = supports[i];
				@d.dsg = dsg;
			}
		}

		if(d is null) {
			@d = GroupData();
			@d.dsg = dsg;
			supports.insertLast(d);
		}

		d.ordered += amount;

		if(cycle == d.orderCycle) {
			d.orderAmount += amount;
		}
		else {
			d.orderCycle = cycle;
			d.orderAmount = amount;
		}

		return true;
	}

	uint removeSupports(const Design@ dsg, uint amount, Object@ refund = null) {
		GroupData@ d;
		@dsg = dsg.mostUpdated();
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			if(supports[i].dsg.mostUpdated() is dsg) {
				@d = supports[i];
				@d.dsg = dsg;
			}
		}

		if(d is null)
			return 0;

		uint prev = d.totalSize;
		uint take = min(d.ordered, amount);
		d.ordered -= take;
		amount -= take;

		if(amount > 0)
			d.amount -= min(amount, d.amount);

		uint removed = prev - d.totalSize;
		if(refund !is null) {
			int cost = getBuildCost(dsg, removed);
			int maint = getMaintenanceCost(dsg, removed);
			maintainCost -= maint;
			buildCost -= cost;

			if(d.orderCycle != -1) {
				uint refd = min(d.orderAmount, removed);
				refund.owner.refundBudget(getBuildCost(dsg, refd), d.orderCycle);
				d.orderAmount -= refd;
			}
			if(started)
				refund.owner.modMaintenance(-maint, MoT_Construction);
			reverseDesignCosts(refund, dsg, removed, true);
		}

		if(d.totalSize <= 0)
			supports.remove(d);
		return removed;
	}

	bool get_hasSupports() {
		return supports.length != 0;
	}

	bool get_hasSupportsBuilding() {
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			GroupData@ d = supports[i];
			if(d.ordered > 0)
				return true;
		}
		return false;
	}

	double getSupportSupplyFree() {
		double supply = design.total(SV_SupportCapacity);
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			GroupData@ d = supports[i];
			supply -= double(d.totalSize) * d.dsg.size;
		}
		return supply;
	}

	double addSupportLabor(double amount) {
		if(supports.length == 0)
			return amount;
		if(!paid)
			return amount;

		savedLabor += amount;

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
