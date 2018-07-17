import resources;
import obj_selection;
import influence;

//class TariffVote : ConsoleCommand {
//	void execute(const string& args) {
//		InfluenceVote vote(getInfluenceVoteType("TradeTariff"));
//		@vote.subjects[0].obj = selectedObject;

//		createInfluenceVote(vote);
//	}
//};

/*class CancelVote : ConsoleCommand {*/
/*	void execute(const string& args) {*/
/*		InfluenceVote vote(getInfluenceVoteType("CancelVote"));*/
/*		vote.subjects[0].index = toInt(args);*/

/*		createInfluenceVote(vote);*/
/*	}*/
/*};*/

/*class PrintVotes : ConsoleCommand {*/
/*	void execute(const string& args) {*/
/*		InfluenceVote[] votes;*/
/*		votes.syncFrom(getActiveInfluenceVotes());*/

/*		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {*/
/*			votes[i].dump();*/
/*			print("");*/
/*		}*/
/*	}*/
/*};*/

class PrintInfluence : ConsoleCommand {
	void execute(const string& args) {
		print("Influence: "+playerEmpire.Influence);
	}
};

class OrderSupport : ConsoleCommand {
	void execute(const string& args) {
		if(selectedObject is null || !selectedObject.hasLeaderAI) {
			error("Error: Need to have valid group leader selected.");
			return;
		}

		int space = args.findFirst(" ");
		if(args.length == 0 || space == -1) {
			print("Usage: order_support <amount> <design name>");
			return;
		}

		string strAmt = args.substr(0, space);
		string strDesign = args.substr(space+1, args.length - space - 1);

		const Design@ dsg = playerEmpire.getDesign(strDesign);
		if(dsg is null) {
			error("ERROR: Cannot find design with name "+strDesign);
			return;
		}

		selectedObject.orderSupports(dsg, toUInt(strAmt));
	}
};

import void setFleetPlanesShown(bool enabled) from "nodes.FleetPlane";
import void setFleetIconsShown(bool enabled) from "nodes.FleetPlane";
import void setPlanetPlanesShown(bool enabled) from "nodes.PlanetIcon";
import void setPlanetIconsShown(bool enabled) from "nodes.PlanetIcon";
import void setStrategicIconsShown(bool enabled) from "nodes.StrategicIcon";
import void setSystemPlanesShown(bool enabled) from "nodes.SystemPlane";
import void setGalaxyPlanesShown(bool enabled) from "nodes.GalaxyPlane";
import void setTerritoryBordersShown(bool enabled) from "nodes.Territory";
import void setTradeLinesShown(bool enabled) from "nodes.TradeLines";

class CineMode : ConsoleCommand {
	void execute(const string& args) {
		bool mode = args.length == 0 || toBool(args);
		render3DIcons = !mode;
		setFleetPlanesShown(!mode);
		setFleetIconsShown(!mode);
		setPlanetPlanesShown(!mode);
		setPlanetIconsShown(!mode);
		setStrategicIconsShown(!mode);
		setSystemPlanesShown(!mode);
		setTerritoryBordersShown(!mode);
		setTradeLinesShown(!mode);
	}
};

class GalaxyPlane : ConsoleCommand {
	void execute(const string& args) {
		bool mode = args.length == 0 || toBool(args);
		setGalaxyPlanesShown(mode);
	}
};

class HideGUI : ConsoleCommand {
	void execute(const string& args) {
		hide_ui = args.length == 0 || toBool(args);
	}
};

class KickCommand : ConsoleCommand {
	void execute(const string& args) {
		auto@ pl = getPlayers();
		for(uint i = 0, cnt = pl.length; i < cnt; ++i) {
			if(pl[i].name.equals_nocase(args))
				mpKick(pl[i].id);
		}
	}
};

class PasswordCommand : ConsoleCommand {
	void execute(const string& args) {
		mpSetPassword(args);
	}
};

void init() {
	//addConsoleCommand("tariff_vote", TariffVote());
	addConsoleCommand("order_support", OrderSupport());
	/*addConsoleCommand("cancel_vote", CancelVote());*/
	/*addConsoleCommand("print_votes", PrintVotes());*/
	addConsoleCommand("print_influence", PrintInfluence());
	addConsoleCommand("cine_mode", CineMode());
	addConsoleCommand("galaxy_plane", GalaxyPlane());
	addConsoleCommand("hide_gui", HideGUI());
	addConsoleCommand("kick", KickCommand());
	addConsoleCommand("password", PasswordCommand());
}
