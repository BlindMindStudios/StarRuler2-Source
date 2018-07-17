import resources;

tidy class ResourceManager : Component_ResourceManager {
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

	uint welfareMode = WM_Influence;
	int Budget_Total = 0;
	int Maintenance = 0;
	int PrevBudget = 0;
	int PrevMaintenance = 0;
	int Budget_Remaining = 0;
	int Budget_Forward = 0;
	int Budget_CycleId = 0;
	int Budget_Bonus = 0;
	double Budget_Cycle = 3.0 * 60.0;
	double Budget_Tick = Budget_Cycle;
	double Borrow_Rate = 1.5;

	array<int> moneyTypes = array<int>(MoT_COUNT, 0);

	//Population
	double get_EstTotalPopulation() const {
		return max(round(Population / 10.0), 1.0) * 10.0;
	}

	double get_TotalPopulation() const {
		return Population;
	}

	//FTL
	double get_FTLIncome() {
		return FTL_Income;
	}

	double get_FTLStored() {
		return FTL_Stored;
	}

	double get_FTLUse(const Empire& emp) {
		return FTL_Use * emp.FTLCostFactor;
	}

	double get_FTLCapacity() {
		return FTL_Capacity;
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

	//Energy
	double get_EnergyIncome() {
		return Energy_Income;
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

	bool get_EnergyShortage() {
		return Energy_Stored <= 0.0001 && Energy_Use > EnergyIncome + 0.0001;
	}

	bool isEnergyShortage(double amt) {
		if(Energy_Use + amt <= EnergyIncome + 0.0001)
			return false;

		//Only not a shortage if we can run it for at least a minute
		double cons = (Energy_Use + amt) * 60.0;
		double have = Energy_Stored + EnergyIncome * 60.0;
		return cons >= have;
	}

	bool consumeEnergyUse(double amt) {
		Lock lock(energyMutex);
		if(Energy_Use + amt <= EnergyIncome + 0.0001) {
			Energy_Use += amt;
			return true;
		}

		//Only not a shortage if we can run it for at least a minute
		double cons = (Energy_Use + amt) * 60.0;
		double have = Energy_Stored + EnergyIncome * 60.0;
		if(cons >= have)
			return false;

		Energy_Use += amt;
		return true;
	}

	//Budget
	int getMoneyFromType(uint type) {
		if(type < MoT_COUNT)
			return moneyTypes[type];
		return 0;
	}

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

	double get_BudgetCycle() {
		return Budget_Cycle;
	}

	double get_BudgetTimer() {
		return Budget_Tick;
	}

	float get_DebtFactor() {
		if(Budget_Remaining >= 0)
			return 0.f;
		if(Budget_Total < 100)
			return float(-Budget_Remaining) / 100.f;
		return float(-Budget_Remaining) / float(Budget_Total);
	}

	int get_EstNextBudget() const {
		int budget = Budget_Total - Maintenance + Budget_Forward + Budget_Bonus;
		budget += min(Budget_Remaining - min(PrevBudget - PrevMaintenance, 0), 0);
		return budget;
	}

	int getEstBudgetConsuming(int amount) const {
		int budget = Budget_Total - Maintenance + Budget_Forward + max(Budget_Bonus - amount, 0);
		budget += min(Budget_Remaining - amount - min(PrevBudget - PrevMaintenance, 0), 0);
		return budget;
	}

	int get_BudgetCycleId() {
		return Budget_CycleId;
	}
	
	uint get_WelfareMode() const {
		return welfareMode;
	}

	bool canBorrow(int amount) const {
		amount = ceil(double(amount) * Borrow_Rate);
		return EstNextBudget >= amount;
	}

	bool canPay(int amount) const {
		if(amount <= Budget_Remaining)
			return true;
		return canBorrow(amount - Budget_Remaining);
	}

	//Networking
	void readResources(Empire& emp, Message& msg) {
		Population = msg.read_float();

		FTL_Capacity = msg.read_float();
		FTL_Stored = msg.read_float();
		FTL_Income = msg.read_float();
		FTL_Use = msg.read_float();

		Energy_Stored = msg.read_float();
		Energy_Income = msg.read_float();
		Energy_Use = msg.read_float();
		Energy_Allocated = msg.read_float();

		msg >> Budget_Total;
		msg >> Maintenance;
		msg >> PrevMaintenance;
		msg >> PrevBudget;
		msg >> Budget_Remaining;
		msg >> Budget_Forward;
		msg >> Budget_Bonus;
		msg >> Budget_CycleId;
		Budget_Cycle = msg.read_float();
		Budget_Tick = msg.read_float();
		Borrow_Rate = msg.read_float();

		for(uint i = 0; i < MoT_COUNT; ++i)
			moneyTypes[i] = msg.readSignedSmall();
		
		welfareMode = msg.readLimited(WM_COUNT-1);
	}
};
