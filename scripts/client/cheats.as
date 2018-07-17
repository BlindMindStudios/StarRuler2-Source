from obj_selection import selectedObject, selectedObjects, hoveredObject;
from input import activeCamera;
import orbitals;
import influence;

bool get_cheats() {
	if(!getCheatsEnabled()) {
		error("ERROR: Cheats not enabled. Use 'cheats on' to enable.");
		return false;
	}
	else {
		return true;
	}
}

class SetCheats : ConsoleCommand {
	void execute(const string& args) {
		setCheatsEnabled(args.length == 0 || toBool(args));
	}
};

class ColonizeCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;
		cheatColonize(args.length == 0 || toBool(args));
	}
};

class SeeAllCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;
		cheatSeeAll(args.length == 0 || toBool(args));
	}
};

class SpawnFlagshipCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		int space = args.findFirst(" ");
		if(args.length == 0 || space == -1) {
			error("Usage: ch_flagship <empire id> <design name>");
			return;
		}

		string strId = args.substr(0, space);
		string strDesign = args.substr(space+1, args.length - space - 1);
		Empire@ emp;
		if(strId == "*")
			@emp = playerEmpire;
		else
			@emp = getEmpireByID(toUInt(strId));
		if(emp is null) {
			error("ERROR: Cannot find empire with id "+strId);
			return;
		}

		const Design@ dsg = emp.getDesign(strDesign);
		if(dsg is null) {
			error("ERROR: Cannot find design with name "+strDesign);
			return;
		}
		if(dsg.hasTag(ST_IsSupport)) {
			error("ERROR: Design "+strDesign+" is not a flagship.");
			return;
		}

		if(selectedObject is null) {
			if(activeCamera !is null)
				cheatSpawnFlagship(activeCamera.screenToPoint(mousePos), dsg, emp);
		}
		else {
			cheatSpawnFlagship(selectedObject, dsg, emp);
		}
	}
};

class SpawnSupportCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		int space = args.findFirst(" ");
		if(args.length == 0 || space == -1) {
			error("Usage: ch_supports <amount> <design name>");
			return;
		}

		Empire@ emp = playerEmpire;
		if(selectedObject !is null)
			@emp = selectedObject.owner;
		else if(hoveredObject !is null)
			@emp = hoveredObject.owner;

		string strAmount = args.substr(0, space);
		string strDesign = args.substr(space+1, args.length - space - 1);
		uint amount = clamp(toUInt(strAmount), 0, 999999);

		const Design@ dsg = emp.getDesign(strDesign);
		if(dsg is null) {
			error("ERROR: Cannot find design with name "+strDesign);
			return;
		}
		if(!dsg.hasTag(ST_IsSupport)) {
			error("ERROR: Design "+strDesign+" is not a support ship.");
			return;
		}

		if(selectedObject !is null) {
			cheatSpawnSupports(selectedObject, dsg, amount);
		}
		else if(hoveredObject !is null) {
			cheatSpawnSupports(hoveredObject, dsg, amount);
		}
		else {
			if(activeCamera !is null)
				cheatSpawnSupports(activeCamera.screenToPoint(mousePos), dsg, amount, playerEmpire);
		}
	}
};

class SpawnOrbitalCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		int space = args.findFirst(" ");
		if(args.length == 0 || space == -1) {
			error("Usage: ch_orbital <empire id> <orbital ident>");
			return;
		}

		string strId = args.substr(0, space);
		string strOrbital = args.substr(space+1, args.length - space - 1);

		Empire@ emp;
		if(strId == "*")
			@emp = playerEmpire;
		else
			@emp = getEmpireByID(toUInt(strId));

		if(emp is null) {
			error("ERROR: Cannot find empire with id "+strId);
			return;
		}

		const OrbitalModule@ def = getOrbitalModule(strOrbital);
		if(def is null) {
			error("ERROR: Cannot find orbital with name "+strOrbital);
			return;
		}

		if(activeCamera !is null)
			cheatSpawnOrbital(activeCamera.screenToPoint(mousePos), def.id, emp);
	}
};

class TriggerCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		Empire@ emp = playerEmpire;
		Object@ obj;
		if(selectedObject !is null)
			@obj = selectedObject;
		else if(hoveredObject !is null)
			@obj = hoveredObject;

		cheatTrigger(obj, emp, args);
	}
};

class InfluenceCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatInfluence(toInt(args));
	}
};

class ResearchCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatResearch(toDouble(args));
	}
};

class MoneyCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatMoney(toInt(args));
	}
};

class FTLCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatFTL(toInt(args));
	}
};

class EnergyCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatEnergy(toInt(args));
	}
};

class DestroyCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		if(selectedObject !is null) {
			for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i)
				cheatDestroy(selectedObjects[i]);
		}
		else {
			cheatDestroy(hoveredObject);
		}
	}
};

class LaborCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;
		double amount = toDouble(args);
		if(selectedObject !is null) {
			for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i)
				cheatLabor(selectedObjects[i], amount);
		}
		else {
			cheatLabor(hoveredObject, amount);
		}
	}
};

class OwnerCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		Empire@ emp = getEmpireByID(toUInt(args));
		if(emp is null) {
			error("ERROR: Cannot find empire with id "+args);
			return;
		}

		if(selectedObject !is null) {
			for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i)
				cheatChangeOwner(selectedObjects[i], emp);
		}
		else {
			cheatChangeOwner(hoveredObject, emp);
		}
	}
};

class AICheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		cheatActivateAI();
	}
};

class AIDebug : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;
		
		int empireID = toInt(args);
		Empire@ emp = getEmpireByID(empireID);
		cheatDebugAI(emp);
	}
};

class AICommand : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;
		
		int empireID = toInt(args);
		int cmdStart = args.findFirst(" ");
		if(cmdStart > 0) {
			Empire@ emp = getEmpireByID(empireID);
			cheatCommandAI(emp, args.substr(cmdStart + 1, args.length() - (cmdStart + 1)));
		}
	}
};

class AllianceCheat : ConsoleCommand {
	void execute(const string& args) {
		if(!cheats)
			return;

		int space = args.findFirst(" ");
		if(args.length == 0 || space == -1) {
			error("Usage: ch_alliance <emp 1 id> <emp 2 id>");
			return;
		}

		string str1 = args.substr(0, space);
		string str2 = args.substr(space+1, args.length - space - 1);

		Empire@ emp1 = getEmpireByID(toInt(str1));
		if(emp1 is null) {
			error("No such empire id: "+str1);
			return;
		}

		Empire@ emp2 = getEmpireByID(toInt(str2));
		if(emp2 is null) {
			error("No such empire id: "+str2);
			return;
		}

		cheatAlliance(emp1, emp2);
	}
};

void init() {
	addConsoleCommand("cheats", SetCheats());
	addConsoleCommand("ch_colonize", ColonizeCheat());
	addConsoleCommand("ch_seeall", SeeAllCheat());
	addConsoleCommand("ch_flagship", SpawnFlagshipCheat());
	addConsoleCommand("ch_supports", SpawnSupportCheat());
	addConsoleCommand("ch_orbital", SpawnOrbitalCheat());
	addConsoleCommand("ch_influence", InfluenceCheat());
	addConsoleCommand("ch_research", ResearchCheat());
	addConsoleCommand("ch_money", MoneyCheat());
	addConsoleCommand("ch_destroy", DestroyCheat());
	addConsoleCommand("ch_labor", LaborCheat());
	addConsoleCommand("ch_owner", OwnerCheat());
	addConsoleCommand("ch_activate_ai", AICheat());
	addConsoleCommand("ch_ftl", FTLCheat());
	addConsoleCommand("ch_energy", EnergyCheat());
	addConsoleCommand("ch_debug_ai", AIDebug());
	addConsoleCommand("ch_ai_command", AICommand());
	addConsoleCommand("ch_alliance", AllianceCheat());
	addConsoleCommand("ch_trigger", TriggerCheat());
}
