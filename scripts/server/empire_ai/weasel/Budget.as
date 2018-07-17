// Budget
// ------
// Tasked with managing the empire's money and making sure we have enough to spend
// on various things, as well as dealing with prioritization and budget allocation.
//

import empire_ai.weasel.WeaselAI;

enum BudgetType {
	BT_Military,
	BT_Colonization,
	BT_Development,

	BT_COUNT
};

final class AllocateBudget {
	int id = -1;
	uint type;
	int cost = 0;
	int maintenance = 0;

	double requestTime = 0;
	double priority = 1;

	bool allocated = false;
	int opCmp(const AllocateBudget@ other) const {
		if(priority < other.priority)
			return -1;
		if(priority > other.priority)
			return 1;
		if(requestTime < other.requestTime)
			return 1;
		if(requestTime > other.requestTime)
			return -1;
		return 0;
	}

	void save(SaveFile& file) {
		file << id;
		file << type;
		file << cost;
		file << maintenance;
		file << requestTime;
		file << priority;
		file << allocated;
	}

	void load(SaveFile& file) {
		file >> id;
		file >> type;
		file >> cost;
		file >> maintenance;
		file >> requestTime;
		file >> priority;
		file >> allocated;
	}
};

final class BudgetPart {
	uint type;

	array<AllocateBudget@> allocations;

	//How much we've spent this cycle
	int spent = 0;

	//How much is remaining to be spent this cycle
	int remaining = 0;

	//How much maintenance we've gained this cycle
	int gainedMaintenance = 0;

	//How much maintenance we can still gain this cycle
	int remainingMaintenance = 0;

	void update(AI& ai, Budget& budget) {
		for(uint i = 0, cnt = allocations.length; i < cnt; ++i) {
			auto@ alloc = allocations[i];
			if(alloc.priority < 1.0) {
				if(alloc.cost >= remaining && alloc.maintenance >= remainingMaintenance) {
					budget.spend(type, alloc.cost, alloc.maintenance);
					alloc.allocated = true;
					allocations.removeAt(i);
					break;
				}
			}
			else {
				if(budget.canSpend(type, alloc.cost, alloc.maintenance)) {
					budget.spend(type, alloc.cost, alloc.maintenance);
					alloc.allocated = true;
					allocations.removeAt(i);
					break;
				}
			}
		}
	}

	void turn(AI& ai, Budget& budget) {
		spent = 0;
		remaining = 0;

		gainedMaintenance = 0;
		remainingMaintenance = 0;
	}

	void save(Budget& budget, SaveFile& file) {
		file << spent;
		file << remaining;
		file << gainedMaintenance;
		file << remainingMaintenance;

		uint cnt = allocations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			budget.saveAlloc(file, allocations[i]);
			allocations[i].save(file);
		}
	}

	void load(Budget& budget, SaveFile& file) {
		file >> spent;
		file >> remaining;
		file >> gainedMaintenance;
		file >> remainingMaintenance;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ alloc = budget.loadAlloc(file);
			alloc.load(file);
		}
	}
};

final class Budget : AIComponent {
	array<BudgetPart@> parts;
	int NextAllocId = 0;

	int InitialBudget = 0;
	int InitialUpcoming = 0;

	double Progress = 0;
	double RemainingTime = 0;

	int FreeBudget = 0;
	int FreeMaintenance = 0;

	bool checkedMilitarySpending = false;

	void create() {
		parts.length = BT_COUNT;
		for(uint i = 0; i < BT_COUNT; ++i) {
			@parts[i] = BudgetPart();
			parts[i].type = BudgetType(i);
		}
	}

	void save(SaveFile& file) {
		file << InitialBudget;
		file << InitialUpcoming;
		file << Progress;
		file << RemainingTime;
		file << FreeBudget;
		file << FreeMaintenance;
		file << NextAllocId;
		file << checkedMilitarySpending;

		for(uint i = 0, cnt = parts.length; i < cnt; ++i)
			parts[i].save(this, file);
	}

	void load(SaveFile& file) {
		file >> InitialBudget;
		file >> InitialUpcoming;
		file >> Progress;
		file >> RemainingTime;
		file >> FreeBudget;
		file >> FreeMaintenance;
		file >> NextAllocId;
		file >> checkedMilitarySpending;

		for(uint i = 0, cnt = parts.length; i < cnt; ++i)
			parts[i].load(this, file);
	}

	array<AllocateBudget@> loadIds;
	AllocateBudget@ loadAlloc(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = loadIds.length; i < cnt; ++i) {
			if(loadIds[i].id == id)
				return loadIds[i];
		}
		AllocateBudget alloc;
		alloc.id = id;
		loadIds.insertLast(alloc);
		return alloc;
	}
	AllocateBudget@ loadAlloc(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadAlloc(id);
	}
	void saveAlloc(SaveFile& file, AllocateBudget@ alloc) {
		int id = -1;
		if(alloc !is null)
			id = alloc.id;
		file << id;
	}
	void postLoad(AI& ai) {
		loadIds.length = 0;
	}

	void spend(uint type, int money, int maint = 0) {
		auto@ part = parts[type];

		part.spent += money;
		part.gainedMaintenance += maint;

		if(part.remaining >= money) {
			part.remaining -= money;
		}
		else if(part.remaining >= 0) {
			money -= part.remaining;
			FreeBudget -= money;
			part.remaining = 0;
		}
		else {
			FreeBudget -= money;
		}

		if(part.remainingMaintenance >= maint) {
			part.remainingMaintenance -= maint;
		}
		else if(part.remainingMaintenance >= 0) {
			maint -= part.remainingMaintenance;
			FreeMaintenance -= maint;
			part.remainingMaintenance = 0;
		}
		else {
			FreeMaintenance -= money;
		}
	}

	bool canSpend(uint type, int money, int maint = 0) {
		int canFree = FreeBudget;
		int canFreeMaint = FreeMaintenance;

		//Don't allow generic spending until we've checked if we need to spend on military this cycle
		if(type == BT_Development && !checkedMilitarySpending && Progress < 0.33)
			canFree = 0;
		if(type == BT_Colonization)
			canFree += 160;

		auto@ part = parts[type];
		if(money > part.remaining + canFree)
			return false;
		if(maint != 0 && maint > part.remainingMaintenance + canFreeMaint)
			return false;
		return true;
	}

	int spendable(uint type) {
		return FreeBudget + parts[type].remaining;
	}

	int maintainable(uint type) {
		return FreeMaintenance + parts[type].remainingMaintenance;
	}

	void claim(uint type, int money, int maint = 0) {
		auto@ part = parts[type];

		FreeBudget -= money;
		part.remaining += money;

		FreeMaintenance -= maint;
		part.remainingMaintenance += maint;
	}

	void turn() {
		if(log && gameTime > 10.0) {
			ai.print("==============");
			ai.print("Unspent:");
			ai.print(" Military: "+parts[BT_Military].remaining+" / "+parts[BT_Military].remainingMaintenance);
			ai.print(" Colonization: "+parts[BT_Colonization].remaining+" / "+parts[BT_Colonization].remainingMaintenance);
			ai.print(" Development: "+parts[BT_Development].remaining+" / "+parts[BT_Development].remainingMaintenance);
			ai.print(" FREE: "+FreeBudget+" / "+FreeMaintenance);
			ai.print("==============");
			ai.print("Total Expenditures:");
			ai.print(" Military: "+parts[BT_Military].spent+" / "+parts[BT_Military].gainedMaintenance);
			ai.print(" Colonization: "+parts[BT_Colonization].spent+" / "+parts[BT_Colonization].gainedMaintenance);
			ai.print(" Development: "+parts[BT_Development].spent+" / "+parts[BT_Development].gainedMaintenance);
			ai.print("==============");
		 }

		//Collect some data about this turn
		InitialBudget = ai.empire.RemainingBudget;
		InitialUpcoming = ai.empire.EstNextBudget;

		FreeBudget = InitialBudget;
		FreeMaintenance = InitialUpcoming;

		checkedMilitarySpending = false;

		//Tell the budget parts to perform turns
		for(uint i = 0, cnt = parts.length; i < cnt; ++i)
			parts[i].turn(ai, this);
	}

	void remove(AllocateBudget@ alloc) {
		if(alloc is null)
			return;
		if(alloc.allocated) {
			FreeBudget += alloc.cost;
			FreeMaintenance += alloc.maintenance;
		}
		parts[alloc.type].allocations.remove(alloc);
	}

	AllocateBudget@ allocate(uint type, int cost, int maint = 0, double priority = 1.0) {
		AllocateBudget alloc;
		alloc.id = NextAllocId++;
		alloc.type = type;
		alloc.cost = cost;
		alloc.maintenance = maint;
		alloc.priority = priority;

		return allocate(alloc);
	}

	AllocateBudget@ allocate(AllocateBudget@ allocation) {
		allocation.requestTime = gameTime;
		parts[allocation.type].allocations.insertLast(allocation);
		parts[allocation.type].allocations.sortDesc();
		return allocation;
	}

	void applyNow(AllocateBudget@ alloc) {
		auto@ part = parts[alloc.type];
		spend(alloc.type, alloc.cost, alloc.maintenance);
		alloc.allocated = true;
		part.allocations.remove(alloc);
	}

	void grantBonus(int cost, int maint = 0) {
		//Spread some bonus budget across all the different parts
		FreeBudget += cost;
		FreeMaintenance += maint;
	}

	void tick(double time) {
		//Record some simple data
		Progress = ai.empire.BudgetTimer / ai.empire.BudgetCycle;
		RemainingTime = ai.empire.BudgetCycle - ai.empire.BudgetTimer;

		//Update one of the budget parts
		for(uint i = 0, cnt = parts.length; i < cnt; ++i) {
			auto@ part = parts[i];
			part.update(ai, this);
		}
	}

	void focusTick(double time) {
		//Detect any extra budget we need to use
		int ExpectBudget = FreeBudget;
		int ExpectMaint = FreeMaintenance;
		for(uint i = 0, cnt = parts.length; i < cnt; ++i) {
			ExpectBudget += parts[i].remaining;
			ExpectMaint += parts[i].remainingMaintenance;
		}

		int HaveBudget = ai.empire.RemainingBudget;
		int HaveMaint = ai.empire.EstNextBudget;
		if(ExpectBudget != HaveBudget || ExpectMaint != HaveMaint)
			grantBonus(HaveBudget - ExpectBudget, max(0, HaveMaint - ExpectMaint));
	}
};

AIComponent@ createBudget() {
	return Budget();
}
