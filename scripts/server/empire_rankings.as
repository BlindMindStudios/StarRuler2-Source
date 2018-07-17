from empire import majorEmpireCount;
import bool getCheatsEverOn() from "cheats";
import systems;

const double SubjugatePointRatio = 0.2;
double totalStrength = 0.0;
double totalInfluence = 0.0;
double totalPlanets = 0.0;

void reset() {
	totalStrength = 0.0;
	totalInfluence = 0.0;
	totalPlanets = 0.0;
}

void updateEmp(Empire& emp) {
	totalPlanets += double(emp.TotalPlanets.value);
	totalInfluence += double(emp.Influence);
	totalInfluence += double(emp.DiplomacyPoints.value / 10.0);

	emp.TotalMilitary = emp.getTotalFleetStrength();
	totalStrength += emp.TotalMilitary;

	if(emp.SubjugatedBy !is null) {
		int pts = emp.points.value * SubjugatePointRatio;
		int prevPts = emp.prevPoints;
		if(pts != prevPts) {
			emp.SubjugatedBy.points += (pts - prevPts);
			emp.prevPoints = pts;
		}
	}

	if(emp.Victory == 0) {
		if(emp.TotalPlanets.value == 0) {
			emp.Victory = -1;
		}
		else if(emp.SubjugatedBy !is null) {
			emp.Victory = -2;
		}
	}
}

void finish() {
	//Calculate strength measurements
	double strPoint = totalStrength / double(majorEmpireCount);
	double strRange = strPoint * 0.33;

	double infPoint = totalInfluence / double(majorEmpireCount);
	double infRange = infPoint * 0.33;

	double empPoint = totalPlanets / double(majorEmpireCount);
	double empRange = empPoint * 0.33;

	for(uint i = 0, empCnt = getEmpireCount(); i < empCnt; ++i) {
		Empire@ emp = getEmpire(i);
		if(!emp.major)
			continue;

		//Military
		double str = emp.TotalMilitary;
		if(str < strPoint - strRange)
			emp.MilitaryStrength = -1;
		else if(str > strPoint + strRange)
			emp.MilitaryStrength = +1;
		else
			emp.MilitaryStrength = 0;

		//Political
		double inf = emp.Influence + (emp.DiplomacyPoints.value / 10);
		if(inf < infPoint - infRange)
			emp.PoliticalStrength = -1;
		else if(inf > infPoint + infRange)
			emp.PoliticalStrength = +1;
		else
			emp.PoliticalStrength = 0;

		//Empire
		double pl = emp.TotalPlanets.value;
		if(pl < empPoint - empRange)
			emp.EmpireStrength = -1;
		else if(pl > empPoint + empRange)
			emp.EmpireStrength = +1;
		else
			emp.EmpireStrength = 0;
	}
}

uint empireIndex = 0;
void updateStrengths() {
	uint empCnt = getEmpireCount();
	if(empireIndex >= empCnt) {
		finish();
		reset();
		empireIndex = 0;
	}
	else {
		Empire@ emp = getEmpire(empireIndex);
		while(empireIndex < empCnt && !emp.major)
			@emp = getEmpire(++empireIndex);
		if(emp !is null) {
			updateEmp(emp);
			++empireIndex;
		}
	}
}

double strengthTimer = 0.125;
void tick(double time) {
	strengthTimer -= time;
	if(strengthTimer <= 0) {
		updateStrengths();
		strengthTimer += 0.125;
	}
}
