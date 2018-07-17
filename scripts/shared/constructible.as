from orbitals import OrbitalModule, getOrbitalModule, OrbitalValues;
import buildings;
import ship_groups;
import resources;
import string getConstructionName(int id) from "constructions";
import Sprite getConstructionIcon(int id) from "constructions";

enum ConstructibleType {
	CT_Invalid,
	CT_Flagship,
	CT_Orbital,
	CT_Asteroid,
	CT_Terraform,
	CT_Retrofit,
	CT_DryDock,
	CT_Export,
	CT_Station,
	CT_Building,
	CT_Construction
};

tidy class Constructible : Serializable {
	ConstructibleType type;
	double curLabor = 0;
	double totalLabor = 1;
	int id = -1;
	int buildCost = 0;
	int maintainCost = 0;
	bool started = false;
	float pct = 0.f;
	float prog = 0.f;
	bool isTimed = false;

	Object@ obj;
	const OrbitalModule@ orbital;
	const Design@ dsg;
	const ResourceType@ resource;
	const BuildingType@ building;
	int constructionId = -1;
	array<GroupData> groups;

	Constructible() {
		type = CT_Invalid;
	}

	Constructible(const Design@ Design) {
		type = CT_Flagship;
		@dsg = Design;
	}

	string get_name() {
		switch(type) {
			case CT_Flagship:
			case CT_Station:
				return dsg !is null ? dsg.name : "Unknown";
			case CT_Orbital:
				return orbital.name;
			case CT_Asteroid:
				return format(locale::BUILD_ASTEROID, resource.name);
			case CT_Building:
				return building.name;
			case CT_Terraform:
				return format(locale::BUILD_TERRAFORM, obj.name, resource.name);
			case CT_Retrofit:
				return format(locale::BUILD_RETROFIT, obj.name);
			case CT_DryDock:
				if(id == -1)
					return dsg is null ? "Unknown" : dsg.name;
				else
					return format(locale::BUILD_DRY_DOCK, dsg is null ? "Unknown" : dsg.name);
			case CT_Export:
				return format(locale::EXPORT_LABOR, obj.name);
			case CT_Construction:
				return getConstructionName(constructionId);
		}
		return "(null)";
	}

	Sprite get_icon() {
		switch(type) {
			case CT_Flagship:
			case CT_Station:
				return dsg !is null ? dsg.icon : Sprite();
			case CT_Orbital:
				return orbital.icon;
			case CT_Asteroid:
				return icons::Asteroid;
			case CT_Building:
				return building.sprite;
			case CT_Terraform:
				return resource.smallIcon;
			case CT_Retrofit:
				return Sprite();
			case CT_DryDock:
				return Sprite(spritesheet::GuiOrbitalIcons, 3);
			case CT_Export:
				return icons::Labor;
			case CT_Construction:
				return getConstructionIcon(constructionId);
		}
		return Sprite();
	}

	float get_percentage() {
		return pct;
	}

	float get_progress() {
		if(type == CT_Export)
			return 0.f;
		if(type == CT_DryDock)
			return prog;
		return curLabor / totalLabor;
	}

	double getETA(Object& obj) {
		if(isTimed)
			return totalLabor - curLabor;
		if(type == CT_Export)
			return INFINITY;
#section server-side
		if(type == CT_DryDock)
			return INFINITY;
#section client
		if(type == CT_DryDock)
			return cast<Orbital>(this.obj).getValue(OV_DRY_ETA);
#section all
		double income = obj.laborIncome;
		if(income == 0)
			return INFINITY;
		return (totalLabor - curLabor) / income;
	}

	void read(Message& msg) {
		uint8 ctype = CT_Invalid;
		msg >> ctype;
		msg >> id;
		msg >> started;
		type = ConstructibleType(ctype);
		msg >> curLabor;
		msg >> totalLabor;
		msg >> maintainCost;
		msg >> buildCost;

		@dsg = null;
		@orbital = null;
		@resource = null;
		@building = null;
		constructionId = -1;
		isTimed = false;

		switch(type) {
			case CT_Station:
			case CT_Flagship: {
				msg >> dsg;

				uint cnt = 0;
				msg >> cnt;
				groups.length = cnt;
				for(uint i = 0; i < cnt; ++i)
					msg >> groups[i];
			} break;
			case CT_Orbital: {
				uint id = 0;
				msg >> id;
				@orbital = getOrbitalModule(id);
				groups.length = 0;
			 } break;
			case CT_Asteroid: {
				uint id = 0;
				msg >> id;
				@resource = getResource(id);
				groups.length = 0;
			} break;
			case CT_Building: {
				uint id = 0;
				msg >> id;
				msg >> isTimed;
				@building = getBuildingType(id);
				groups.length = 0;
			} break;
			case CT_Terraform: {
				uint id = 0;
				msg >> id;
				@resource = getResource(id);
				msg >> obj;
				groups.length = 0;
			} break;
			case CT_Construction: {
			   msg >> constructionId;
			   msg >> isTimed;
			   groups.length = 0;
			} break;
			case CT_Retrofit: {
				msg >> obj;
			} break;
			case CT_DryDock: {
				msg >> obj;
				Orbital@ orb = cast<Orbital>(obj);
#section server-side
				@dsg = null;
				prog = 0.f;
				pct = 0.f;
#section client
				@dsg = orb.getDesign(OV_DRY_Design);
				prog = orb.getValue(OV_DRY_Progress);
				pct = orb.getValue(OV_DRY_Financed);
#section all
			} break;
			case CT_Export: {
				msg >> obj;
			} break;
		}
	}

	void write(Message& msg) {
		uint8 tp = type;
		msg << tp;
		msg << id;
		msg << started;
		msg << curLabor;
		msg << totalLabor;
		msg << maintainCost;
		msg << buildCost;

		switch(type) {
			case CT_Station:
			case CT_Flagship:
				msg << dsg;
				msg << groups.length;
				for(uint i = 0, cnt = groups.length; i < cnt; ++i)
					msg << groups[i];
				break;
			case CT_Orbital:
				msg << orbital.id;
				break;
			case CT_Asteroid:
				msg << resource.id;
			break;
			case CT_Building:
				msg << building.id;
			break;
			case CT_Terraform:
				msg << resource.id;
				msg << obj;
			break;
			case CT_Retrofit:
				msg << obj;
			break;
			case CT_Export:
				msg << obj;
			break;
			case CT_DryDock:
				msg << obj;
			break;
			case CT_Construction:
				msg << constructionId;
				msg << isTimed;
			break;
		}
	}
};
