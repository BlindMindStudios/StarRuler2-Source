#include "include/resource_constants.as"

import resources;
import attributes;
from saving import SaveVersion;

//Amount of money spent in welfare that gives you one influence stock
const int MONEY_PER_INFLUENCE = 350;

//Amount of money spent in welfare that gives you one energy stock
const int MONEY_PER_ENERGY = 350;

//Amount of money spent in welfare that gives you one research stock
const int MONEY_PER_RESEARCH = 350;

//Amount of money spent in welfare that gives you one labor generation on the homeworld
const int MONEY_PER_HW_LABOR = 350;

//Amount of money spent in welfare that gives you one global defense generation
const int MONEY_PER_DEFENSE = 350;

tidy class EnergyFloat {
	Empire@ forEmp;
	double amount;
};

tidy class ResourceManager : Component_ResourceManager, Savable {
	Mutex popMutex;
	Mutex budgetMutex;
	Mutex ftlMutex;
	Mutex energyMutex;

	double Population = 0;

	double FTL_Capacity = 0;
	double FTL_Stored = 0;
	double FTL_Income = 0;
	double FTL_Use = 0;

	double Energy_Stored = 0;
	double Energy_Income = 0;
	double Energy_Use = 0;
	double Energy_Allocated = 0;
	array<EnergyFloat@> floatedEnergy;

	int Budget_Total = 0;
	int Maintenance = 0;
	int PrevBudget = 0;
	int PrevMaintenance = 0;
	int Budget_Remaining = 0;
	int Budget_Forward = 0;
	int Budget_CycleId = 0;
	int Budget_Bonus = 0;
	int Budget_CycleBonus = 0;
	double Budget_Cycle = 3.0 * 60.0;
	double Budget_Tick = Budget_Cycle - 0.2;
	double Borrow_Rate = 1.5;

	double StatRecordDelay = 5.0;

	uint welfareMode = WM_Influence;
	int welfareInfluence = 0, welfareEnergy = 0, welfareResearch = 0, welfareHWLabor = 0, welfareDefense = 0;
	int storedWelfare = 0;

	array<int> moneyTypes = array<int>(MoT_COUNT, 0);

	void load(SaveFile& msg) {
		msg >> Population;

		msg >> FTL_Capacity;
		msg >> FTL_Stored;
		msg >> FTL_Income;
		if(msg >= SV_0009)
			msg >> FTL_Use;

		msg >> Energy_Stored;
		msg >> Energy_Income;
		msg >> Energy_Use;
		if(msg >= SV_0055)
			msg >> Energy_Allocated;

		msg >> Budget_Total;
		msg >> Maintenance;
		msg >> PrevBudget;
		msg >> PrevMaintenance;
		msg >> Budget_Remaining;
		msg >> Budget_Forward;
		msg >> Budget_CycleId;
		msg >> Budget_Cycle;
		msg >> Budget_Tick;
		msg >> Borrow_Rate;
		msg >> Budget_Bonus;
		msg >> Budget_CycleBonus;

		msg >> StatRecordDelay;

		msg >> welfareMode;
		msg >> welfareInfluence;
		if(msg > SV_0003) {
			msg >> welfareEnergy;
			msg >> welfareResearch;
			msg >> welfareHWLabor;
		}
		if(msg >= SV_0125)
			msg >> welfareDefense;
		msg >> storedWelfare;

		for(uint i = 0; i < MoT_COUNT-1; ++i)
			msg >> moneyTypes[i];
		if(msg >= SV_0070)
			msg >> moneyTypes[MoT_Vassals];

		if(msg >= SV_0067) {
			uint cnt = 0;
			msg >> cnt;
			floatedEnergy.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				EnergyFloat flt;
				msg >> flt.forEmp;
				msg >> flt.amount;
				@floatedEnergy[i] = flt;
			}
		}
	}
	
	void save(SaveFile& msg) {
		msg << Population;

		msg << FTL_Capacity;
		msg << FTL_Stored;
		msg << FTL_Income;
		msg << FTL_Use;

		msg << Energy_Stored;
		msg << Energy_Income;
		msg << Energy_Use;
		msg << Energy_Allocated;

		msg << Budget_Total;
		msg << Maintenance;
		msg << PrevBudget;
		msg << PrevMaintenance;
		msg << Budget_Remaining;
		msg << Budget_Forward;
		msg << Budget_CycleId;
		msg << Budget_Cycle;
		msg << Budget_Tick;
		msg << Borrow_Rate;
		msg << Budget_Bonus;
		msg << Budget_CycleBonus;

		msg << StatRecordDelay;

		msg << welfareMode;
		msg << welfareInfluence;
		msg << welfareEnergy;
		msg << welfareResearch;
		msg << welfareHWLabor;
		msg << welfareDefense;
		msg << storedWelfare;

		for(uint i = 0; i < MoT_COUNT; ++i)
			msg << moneyTypes[i];

		uint cnt = floatedEnergy.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg << floatedEnergy[i].forEmp;
			msg << floatedEnergy[i].amount;
		}
	}

	//Population
	double get_EstTotalPopulation() const {
		return max(round(Population / 10.0), 1.0) * 10.0;
	}

	double get_TotalPopulation() const {
		return Population;
	}

	void modTotalPopulation(Empire& emp, double amount) {
		Lock lock(popMutex);
		Population += amount;
	}

	//FTL
	double get_FTLIncome() {
		return FTL_Income;
	}

	double get_FTLStored() {
		return FTL_Stored;
	}

	double get_FTLCapacity() {
		return FTL_Capacity;
	}

	double get_FTLUse(const Empire& emp) {
		return FTL_Use * emp.FTLCostFactor;
	}

	double consumeFTL(Empire& emp, double amount, bool consumePartial = true, bool record = true) {
		if(!consumePartial && FTL_Stored < amount)
			return 0.0;
		Lock lock(ftlMutex);
		amount = min(FTL_Stored, amount);
		FTL_Stored -= amount;
		if(amount > 0 && record)
			emp.modAttribute(EA_FTLEnergySpent, AC_Add, amount);
		return amount;
	}

	void modFTLCapacity(double amount) {
		Lock lock(ftlMutex);
		FTL_Capacity += amount;
	}

	void modFTLStored(double amount, bool obeyMaximum = false) {
		Lock lock(ftlMutex);
		if(obeyMaximum)
			FTL_Stored = clamp(FTL_Stored + amount, 0.0, max(FTL_Capacity, FTL_Stored));
		else
			FTL_Stored = max(FTL_Stored + amount, 0.0);
	}

	void modFTLIncome(double amount) {
		Lock lock(ftlMutex);
		FTL_Income += amount;
	}

	bool get_FTLShortage(const Empire& emp) const {
		return FTL_Stored <= 0.0001 && (FTL_Use * emp.FTLCostFactor) > FTL_Income + 0.0001;
	}

	bool isFTLShortage(const Empire& emp, double amt) const {
		if(FTL_Use + amt <= FTL_Income + 0.0001)
			return false;

		//Only not a shortage if we can run it for at least a minute
		double cons = (FTL_Use + amt) * emp.FTLCostFactor * 60.0;
		double have = FTL_Stored + FTL_Income * 60.0;
		return cons >= have;
	}

	bool consumeFTLUse(Empire& emp, double amt) {
		Lock lock(ftlMutex);
		if(FTL_Use + amt <= FTL_Income + 0.0001) {
			FTL_Use += amt;
			return true;
		}

		//Only not a shortage if we can run it for at least a minute
		double cons = (FTL_Use + amt) * emp.FTLCostFactor * 60.0;
		double have = FTL_Stored + FTL_Income * 60.0;
		if(cons >= have)
			return false;

		FTL_Use += amt;
		return true;
	}

	void modFTLUse(double amount) {
		Lock lock(ftlMutex);
		FTL_Use += amount;
	}

	//Energy
	double get_EnergyIncome(Empire& emp) {
		return Energy_Income * emp.EnergyGenerationFactor;
	}

	double get_EnergyStored() {
		return Energy_Stored;
	}

	double get_EnergyUse() {
		return Energy_Use;
	}

	double get_EnergyEfficiency(Empire& emp) {
		return pow(0.5, max(Energy_Stored + Energy_Allocated - emp.FreeEnergyStorage, 0.0) / config::ENERGY_EFFICIENCY_STEP);
	}

	bool get_EnergyShortage(Empire& emp) {
		return Energy_Stored <= 0.0001 && Energy_Use > (Energy_Income * emp.EnergyGenerationFactor) + 0.0001;
	}

	bool isEnergyShortage(Empire& emp, double amt) {
		if(Energy_Use + amt <= (Energy_Income * emp.EnergyGenerationFactor) + 0.0001)
			return false;

		//Only not a shortage if we can run it for at least a minute
		double cons = (Energy_Use + amt) * 60.0;
		double have = Energy_Stored + Energy_Income * 60.0 * emp.EnergyGenerationFactor;
		return cons >= have;
	}

	bool consumeEnergyUse(Empire& emp, double amt) {
		Lock lock(energyMutex);
		if(Energy_Use + amt <= (Energy_Income * emp.EnergyGenerationFactor) + 0.0001) {
			Energy_Use += amt;
			return true;
		}

		//Only not a shortage if we can run it for at least a minute
		double cons = (Energy_Use + amt) * 60.0;
		double have = Energy_Stored + Energy_Income * 60.0 * emp.EnergyGenerationFactor;
		if(cons >= have)
			return false;

		Energy_Use += amt;
		return true;
	}

	double consumeEnergy(double amount, bool consumePartial = true) {
		if(!consumePartial && Energy_Stored < amount)
			return 0.0;
		Lock lock(energyMutex);
		amount = min(Energy_Stored, amount);
		Energy_Stored -= amount;
		for(uint i = 0, cnt = floatedEnergy.length; i < cnt && amount > 0; ++i) {
			auto@ flt = floatedEnergy[i];
			double take = min(flt.amount, amount);

			if(take != 0) {
				flt.amount -= take;
				amount -= take;
				flt.forEmp.modEnergyAllocated(-take);

				if(flt.amount < 0.001) {
					floatedEnergy.removeAt(i);
					--i; --cnt;
				}
			}
		}
		return amount;
	}

	void addFloatedEnergy(Empire@ forEmp, double value) {
		EnergyFloat flt;
		@flt.forEmp = forEmp;
		flt.amount = value;
		floatedEnergy.insertLast(flt);
	}

	void modEnergyAllocated(double amount) {
		Lock lock(energyMutex);
		Energy_Allocated += amount;
	}

	void modEnergyStored(double amount) {
		Lock lock(energyMutex);
		Energy_Stored = max(Energy_Stored + amount, 0.0);
	}

	void modEnergyIncome(double amount) {
		Lock lock(energyMutex);
		Energy_Income += amount;
	}

	void modEnergyUse(double amount) {
		Lock lock(energyMutex);
		Energy_Use += amount;
	}

	//Budget
	int get_TotalBudget() {
		return Budget_Total;
	}

	int get_MaintenanceBudget() {
		return Maintenance;
	}

	int get_RemainingBudget() {
		return Budget_Remaining;
	}

	int get_ForwardBudget() {
		return Budget_Forward;
	}

	int get_BonusBudget() {
		return Budget_Bonus;
	}

	double get_BorrowRate() {
		return Borrow_Rate;
	}

	void multBorrowPenalty(double multiply) {
		Borrow_Rate = 1.0 + (Borrow_Rate - 1.0) * multiply;
	}

	double get_BudgetCycle() {
		return Budget_Cycle;
	}

	double get_BudgetTimer() {
		return Budget_Tick;
	}

	float get_DebtFactor() {
		auto remaining = Budget_Remaining - Budget_Bonus;
		if(remaining >= 0)
			return 0.f;
		if(Budget_Total < 100)
			return float(-remaining) / 100.f;
		return float(-remaining) / float(Budget_Total);
	}

	int getMoneyFromType(uint type) {
		if(type < MoT_COUNT)
			return moneyTypes[type];
		return 0;
	}

	int get_EstNextBudget() const {
		int budget = Budget_Total - Maintenance + Budget_Forward;
		budget += min(Budget_Remaining - min(PrevBudget - PrevMaintenance, 0), 0);
		return budget;
	}

	int getEstBudgetConsuming(int amount) const {
		int budget = Budget_Total - Maintenance + Budget_Forward;
		budget += min(Budget_Remaining - amount - min(PrevBudget - PrevMaintenance, 0), 0);
		return budget;
	}

	void addBonusBudget(Empire& emp, int amount) {
		amount = floor(double(amount) * emp.SpecialFundsFactor);

		Lock lock(budgetMutex);
		Budget_Bonus += amount;
		Budget_CycleBonus += amount;
		Budget_Remaining += amount;
	}

	int get_BudgetCycleId() {
		return Budget_CycleId;
	}
	
	uint get_WelfareMode() const {
		return welfareMode;
	}
	
	void set_WelfareMode(uint mode) {
		welfareMode = mode;
	}

	int consumeBudget(int amount, bool borrow) {
		if(amount == 0)
			return Budget_CycleId;
		Lock lock(budgetMutex);
		if(Budget_Remaining >= amount) {
			Budget_Remaining -= amount;
			Budget_Bonus = max(Budget_Bonus - amount, 0);
			return Budget_CycleId;
		}
		else {
			if(!borrow)
				return -1;
			int borrowAmount = amount;
			if(Budget_Remaining > 0)
				borrowAmount -= Budget_Remaining;
			int borrowCost = ceil(double(borrowAmount) * Borrow_Rate);
			if(getEstBudgetConsuming(borrowCost) < borrowCost)
				return -1;
			Budget_Remaining -= amount;
			Budget_Bonus = max(Budget_Bonus - amount, 0);
			Budget_Forward -= (borrowCost - borrowAmount);
			return Budget_CycleId;
		}
	}

	int lowerBudget(int amount) {
		Lock lock(budgetMutex);
		if(Budget_Remaining >= amount) {
			Budget_Remaining -= amount;
			Budget_Bonus = max(Budget_Bonus - amount, 0);
			return Budget_CycleId;
		}
		else {
			int borrowAmount = amount;
			if(Budget_Remaining > 0)
				borrowAmount -= Budget_Remaining;
			int borrowCost = ceil(double(borrowAmount) * Borrow_Rate);
			Budget_Remaining -= amount;
			Budget_Bonus = max(Budget_Bonus - amount, 0);
			Budget_Forward -= (borrowCost - borrowAmount);
			return Budget_CycleId;
		}
	}

	bool canBorrow(int amount) const {
		if(amount == 0)
			return true;
		amount = ceil(double(amount) * Borrow_Rate);
		return getEstBudgetConsuming(amount) >= amount;
	}

	bool canPay(int amount) const {
		if(amount == 0)
			return true;
		if(amount <= Budget_Remaining)
			return true;
		return canBorrow(amount - Budget_Remaining);
	}

	void refundBudget(int amount, int cycleId) {
		Lock lock(budgetMutex);
		if(cycleId != Budget_CycleId)
			return;
		int refundedBorrow = min(amount, -Budget_Remaining);
		Budget_Remaining += amount;
		Budget_Bonus = min(Budget_Bonus + amount, Budget_CycleBonus);
		if(refundedBorrow > 0)
			Budget_Forward += round(double(refundedBorrow) * (Borrow_Rate - 1.0));
	}

	void modMaintenance(int amount, uint type = 0) {
		Lock lock(budgetMutex);
		Maintenance += amount;

		if(type < MoT_COUNT)
			moneyTypes[type] -= amount;
	}

	void modTotalBudget(Empire& emp, int amount, uint type = 0) {
		Lock lock(budgetMutex);
		Budget_Total += amount;

		if(type < MoT_COUNT)
			moneyTypes[type] += amount;
	}

	void modForwardBudget(int amount) {
		Lock lock(budgetMutex);
		Budget_Forward += amount;
	}

	void modRemainingBudget(int amount) {
		Lock lock(budgetMutex);
		Budget_Remaining += amount;
	}

	void resetBudget(Empire& emp) {
		if(Budget_CycleId != 0) {
			int remaining = Budget_Remaining + storedWelfare - Budget_Bonus;

			//New values for each welfare type
			int nwf_influence = 0, nwf_energy = 0, nwf_research = 0, nwf_hw_labor = 0, nwf_defense = 0;
			
			if(remaining > 0) {
				switch(welfareMode) {
					case WM_Influence:
					{
						double fact = MONEY_PER_INFLUENCE / emp.WelfareEfficiency;
						nwf_influence = floor(double(remaining) / fact);
						storedWelfare = remaining - (nwf_influence * fact);
					} break;
					case WM_Energy:
					{
						double fact = MONEY_PER_ENERGY / emp.WelfareEfficiency;
						nwf_energy = floor(double(remaining) / fact);
						storedWelfare = remaining - (nwf_energy * fact);
					} break;
					case WM_Research:
					{
						double fact = MONEY_PER_RESEARCH / emp.WelfareEfficiency;
						nwf_research = floor(double(remaining) / fact);
						storedWelfare = remaining - (nwf_research * fact);
					} break;
					case WM_HW_Labor:
					{
						double fact = MONEY_PER_HW_LABOR / emp.WelfareEfficiency;
						nwf_hw_labor = floor(double(remaining) / fact);
						storedWelfare = remaining - (nwf_hw_labor * fact);
					} break;
					case WM_Defense:
					{
						double fact = MONEY_PER_DEFENSE / emp.WelfareEfficiency;
						nwf_defense = floor(double(remaining) / fact);
						storedWelfare = remaining - (nwf_defense * fact);
					} break;
					default:
						storedWelfare = remaining;
					break;
				}
			}
			else {
				storedWelfare = 0;
			}
			
			if(nwf_influence != welfareInfluence) {
				emp.modInfluenceIncome(nwf_influence - welfareInfluence);
				welfareInfluence = nwf_influence;
			}
			if(nwf_energy != welfareEnergy) {
				emp.modEnergyIncome(double(nwf_energy - welfareEnergy) * TILE_ENERGY_RATE);
				welfareEnergy = nwf_energy;
			}
			if(nwf_research != welfareResearch) {
				emp.modResearchRate(double(nwf_research - welfareResearch) * TILE_RESEARCH_RATE);
				welfareResearch = nwf_research;
			}
			if(nwf_defense != welfareDefense) {
				emp.modDefenseRate(double(nwf_defense - welfareDefense) * (1.0 / 60.0));
				welfareDefense = nwf_defense;
			}
			if(nwf_hw_labor != welfareHWLabor) {
				Object@ home = emp.Homeworld;
				if(home is null) {
					@home = emp.HomeObj;
					if(home !is null && !home.hasConstruction)
						@home = null;
				}
				if(home !is null && home.valid) {
					if(home.owner !is emp) {
						//In case we lose access to our homeworld, reset the labor being sent
						nwf_hw_labor = 0;
						welfareMode = WM_Influence;
					}
					home.modLaborIncome(double(nwf_hw_labor - welfareHWLabor) * TILE_LABOR_RATE);
				}
				welfareHWLabor = nwf_hw_labor;
			}
		}

		Budget_CycleBonus = Budget_Bonus;
		Budget_Remaining = EstNextBudget + Budget_Bonus;
		PrevBudget = Budget_Total;
		PrevMaintenance = Maintenance;
		Budget_Forward = 0;
		Budget_Tick = 0;
		++Budget_CycleId;
	}

	void resourceTick(Empire& emp, double time) {
		StatRecordDelay -= time;
		
		bool recordStats = StatRecordDelay <= 0;
		if(recordStats)
			StatRecordDelay += 5.0;

		Object@ home = emp.HomeObj;
		if(home is null || !home.valid || home.owner !is emp)
			@emp.HomeObj = null;
	
		//Handle FTL income rate
		{
			Lock lock(ftlMutex);
			FTL_Stored = clamp(FTL_Stored + time * (FTL_Income - FTL_Use * emp.FTLCostFactor), 0, max(FTL_Capacity, FTL_Stored));

			if(FTL_Use > 0) {
				double usedFTL = time * min(FTL_Use * emp.FTLCostFactor, FTL_Stored + FTL_Income);
				if(usedFTL > 0)
					emp.modAttribute(EA_FTLEnergySpent, AC_Add, usedFTL);
			}
			
			if(recordStats)
				emp.recordStat(stat::FTL, float(FTL_Stored));
		}

		//Handle Energy income rate
		{
			Lock lock(energyMutex);
			double netEnergy = ((Energy_Income * emp.EnergyGenerationFactor) - Energy_Use);
			if(netEnergy > 0)
				netEnergy *= emp.EnergyEfficiency;
			Energy_Stored = max(Energy_Stored + time * netEnergy, 0.0);
			if(recordStats)
				emp.recordStat(stat::EnergyIncome, netEnergy);
		}

		//Handle budget ticks
		{
			Lock lock(budgetMutex);

			if(Budget_Tick >= Budget_Cycle) {
				double remainder = Budget_Tick - Budget_Cycle;
				resetBudget(emp);
				Budget_Tick += remainder;
			}
			else
				Budget_Tick += time;

			if(recordStats) {
				emp.recordStat(stat::Budget, float(Budget_Total));
				emp.recordStat(stat::NetBudget, float(EstNextBudget));
			}
		}

		//Handle extra stats
		if(recordStats) {
			emp.recordStat(stat::Points, emp.points.value);
			emp.recordStat(stat::Military, float(sqr(emp.TotalMilitary) * 0.001));
		}
	}

	//Networking
	void writeResources(Message& msg) {
		msg << float(Population);

		msg << float(FTL_Capacity);
		msg << float(FTL_Stored);
		msg << float(FTL_Income);
		msg << float(FTL_Use);

		msg << float(Energy_Stored);
		msg << float(Energy_Income);
		msg << float(Energy_Use);
		msg << float(Energy_Allocated);

		msg << Budget_Total;
		msg << Maintenance;
		msg << PrevMaintenance;
		msg << PrevBudget;
		msg << Budget_Remaining;
		msg << Budget_Forward;
		msg << Budget_Bonus;
		msg << Budget_CycleId;
		msg << float(Budget_Cycle);
		msg << float(Budget_Tick);
		msg << float(Borrow_Rate);
		
		for(uint i = 0; i < MoT_COUNT; ++i)
			msg.writeSignedSmall(moneyTypes[i]);
		
		msg.writeLimited(welfareMode, WM_COUNT-1);
	}
};
