#include "save_load.h"
#include "util/save_file.h"
#include "references.h"
#include "logging.h"
#include "obj/universe.h"
#include "obj/obj_group.h"
#include "empire.h"
#include "physics/physics_world.h"
#include "design/projectiles.h"
#include "main/tick.h"
#include "design/hull.h"
#include "design/subsystem.h"
#include "design/effector.h"
#include "main/initialization.h"
#include <map>
#include <assert.h>

extern std::map<int,ObjectGroup*> groups;
extern int SAVE_VERSION, START_VERSION;

void addSubsystemIdentifiers(SaveFile& file) {
	unsigned cnt = getSubsystemDefCount();
	for(unsigned i = 0; i < cnt; ++i) {
		const SubsystemDef* def = getSubsystemDef(i);
		file.addIdentifier(SI_Subsystem, def->index, def->id);

		for(unsigned j = 0, jcnt = def->modules.size(); j < jcnt; ++j) {
			auto* mod = def->modules[j];
			file.addIdentifier(SI_SubsystemModule, mod->umodid, mod->umodident);
		}

		foreach(it, def->modifierIds) {
			auto* mod = it->second;
			file.addIdentifier(SI_SubsystemModifier, mod->umodifid, def->id+"::"+it->first);
		}
	}

	for(auto it = shipVariableIndices.begin(), end = shipVariableIndices.end(); it != end; ++it)
		file.addIdentifier(SI_ShipVar, it->second, it->first);

	for(auto it = variableIndices.begin(), end = variableIndices.end(); it != end; ++it)
		file.addIdentifier(SI_SubsystemVar, it->second, it->first);

	for(auto it = hexVariableIndices.begin(), end = hexVariableIndices.end(); it != end; ++it)
		file.addIdentifier(SI_HexVar, it->second, it->first);

	for(auto it = variableIndices.begin(), end = variableIndices.end(); it != end; ++it)
		file.addIdentifier(SI_SubsystemVar, it->second, it->first);

	for(size_t i = 0, cnt = getEffectorDefinitionCount(); i < cnt; ++i) {
		auto* effdef = getEffectorDefinition(i);
		file.addIdentifier(SI_Effector, effdef->index, effdef->name);
	}

	for(size_t i = 0, cnt = getEffectDefinitionCount(); i < cnt; ++i) {
		auto* effdef = getEffectDefinition(i);
		file.addIdentifier(SI_Effect, effdef->id, effdef->name);
	}
}

void addHullIdentifiers(SaveFile& file) {
	unsigned cnt = getHullCount();
	for(unsigned i = 0; i < cnt; ++i) {
		const HullDef* hull = getHullDefinition(i);
		file.addIdentifier(SI_Hull, hull->id, hull->ident);
	}
}

void addShipsetIdentifiers(SaveFile& file) {
	unsigned cnt = getShipsetCount();
	for(unsigned i = 0; i < cnt; ++i) {
		auto* set = getShipset(i);
		file.addIdentifier(SI_Shipset, set->id, set->ident);
	}
}

void addDummyIdentifiers(SaveFile& file) {
	if(file < SFV_0007) {
		unsigned i = 0;
		file.addDummyLoadIdentifier(SI_Effector, i++, "CarpetBomb");
		file.addDummyLoadIdentifier(SI_Effector, i++, "Railgun");
		file.addDummyLoadIdentifier(SI_Effector, i++, "Laser");
		file.addDummyLoadIdentifier(SI_Effector, i++, "PurpleLaser");
		file.addDummyLoadIdentifier(SI_Effector, i++, "Rockets");
		file.addDummyLoadIdentifier(SI_Effector, i++, "Missile");
		file.addDummyLoadIdentifier(SI_Effector, i++, "Torpedo");
		file.addDummyLoadIdentifier(SI_Effector, i++, "PopulationBomb");
		file.addDummyLoadIdentifier(SI_Effector, i++, "WaveBeam");
		file.addDummyLoadIdentifier(SI_Effector, i++, "StationArtillery");
	}
}

bool saveGame(const std::string& filename) {
	//TODO: Handle errors gracefully, or guarantee they cannot occur
	try {
		SaveFile* pfile = SaveFile::open(filename, SM_Write);
		SaveFile& file = *pfile;
		if(&file == 0) {
			error("Unable to open file '%s'", filename.c_str());
			return false;
		}

		addSubsystemIdentifiers(file);
		addHullIdentifiers(file);
		addShipsetIdentifiers(file);

		devices.scripts.server->saveIdentifiers(file);

		file.saveIdentifiers();
		file << file.scriptVersion;
		file << file.startVersion;
		file << (unsigned)devices.mods.activeMods.size();
		foreach(it, devices.mods.activeMods) {
			file << (*it)->ident;
			file << (*it)->version;
		}

		file.boundary();

		saveGameConfig(file);

		file.boundary();

		file << devices.driver->getGameTime();

		Empire::saveEmpires(file);

		file.boundary();

		saveEffectors(file);

		file.boundary();

		//Save physics
		if(devices.physics) {
			file << true;
			devices.physics->writeSetup(file);
		}
		else {
			file << false;
		}

		if(devices.nodePhysics) {
			file << true;
			devices.nodePhysics->writeSetup(file);
		}
		else {
			file << false;
		}

		file.boundary();

		//Save object id sequences
		unsigned typeCount = getScriptObjectTypeCount();
		file << typeCount;
		for(unsigned i = 0; i < typeCount; ++i) {
			auto* type = getScriptObjectType(i);
			file << type->nextID.get();
		}

		file.boundary();

		//Save object groups
		unsigned groupCount = (unsigned)groups.size();
		file << groupCount;
		for(auto i = groups.begin(), end = groups.end(); i != end; ++i)
			i->second->save(file);

		file.boundary();

		//Save objects
		unsigned objectCount = (unsigned)devices.universe->children.size();
		file << objectCount;

		for(unsigned i = 0; i < objectCount; ++i)
			devices.universe->children[i]->save(file);

		file.boundary();

		saveProjectiles(file);

		file.boundary();

		devices.scripts.server->save(file);

		if(devices.scripts.client)
			devices.scripts.client->save(file);
		else
			file << "";

		file.close();
		return true;
	}
	catch(SaveFileError& err) {
		error("Failed to save: %s", err.text);
		return false;
	}
}

bool loadGame(const std::string& filename) {
#ifndef _DEBUG
	try {
#endif
		SaveFile& file = *SaveFile::open(filename, SM_Read);
		if(&file == 0) {
			error("Unable to open file '%s'", filename.c_str());
			return false;
		}

		file.loadIdentifiers();
		addDummyIdentifiers(file);

		SaveFileInfo info;
		readSaveFileInfo(file, info);
		file.scriptVersion = info.version;
		file.startVersion = info.startVersion;
		SAVE_VERSION = file.scriptVersion;
		START_VERSION = file.startVersion;

		//Initialize server scripts
		devices.scripts.server->init();

		//Load identifiers
		addSubsystemIdentifiers(file);
		addHullIdentifiers(file);
		addShipsetIdentifiers(file);

		devices.scripts.server->saveIdentifiers(file);
		file.scriptVersion = info.version;
		file.startVersion = info.startVersion;

		file.finalizeIdentifiers();

		file.boundary();

		loadGameConfig(file);
		file.boundary();

		devices.driver->resetGameTime(file);
		resetGameTime();

		Empire::loadEmpires(file);

		file.boundary();

		loadEffectors(file);

		file.boundary();

		//Load physics
		if(file.read<bool>())
			devices.physics = PhysicsWorld::fromSave(file);
		if(file.read<bool>())
			devices.nodePhysics = PhysicsWorld::fromSave(file);

		file.boundary();

		//Load object id sequences
		unsigned typeCount = file;
		for(unsigned i = 0; i < typeCount; ++i) {
			auto* type = getScriptObjectType(i);
			type->nextID = file.read<int>();
		}

		file.boundary();

		//Load object groups
		unsigned groupCount = file;
		for(unsigned i = 0; i < groupCount; ++i)
			new ObjectGroup(file);

		file.boundary();

		//Load objects
		unsigned objectCount = file;
		for(unsigned i = 0; i < objectCount; ++i) {
			Object* obj = file;
			obj->load(file);
			devices.universe->children.push_back( obj ); obj->grab();
		}

		file.boundary();
		
		//Perform post init for groups
		for(auto i = groups.begin(), end = groups.end(); i != end;) {
			ObjectGroup* group = i->second;
			if(group->postLoad()) {
				group->postInit();
				++i;
			}
			else {
				i = groups.erase(i);
				group->drop();
			}
		}

		loadProjectiles(file);

		file.boundary();
		
		devices.scripts.server->load(file);

		//Objects that weren't loaded yet at this point are not valid
		invalidateUninitializedObjects();

		//Perform post load on objects
		for(unsigned i = 0; i < objectCount; ++i)
			devices.universe->children[i]->postLoad();

		//Post load on effectors
		postLoadEffectors();

		//Initialize client scripts
		devices.scripts.client->init();

		//TODO: If we don't have a client, there could still be data to load (if we load it last, we don't have to care)
		if(devices.scripts.client)
			devices.scripts.client->load(file);

		file.close();
		return true;
#ifndef _DEBUG
	}
	catch(SaveFileError& err) {
		error("Failed to load save '%s':\n  %s", filename.c_str(), err.text);
		return false;
	}
#endif
}
