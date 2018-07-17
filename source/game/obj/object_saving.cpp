#include "object.h"
#include "obj_group.h"
#include "util/save_file.h"
#include "empire.h"
#include "physics/physics_world.h"
#include "main/references.h"
#include "main/logging.h"
#include "network/message.h"
#include "lock.h"

//TODO: Handle save files with different script type definitions

void Object::save(SaveFile& file) {
	file << id;

	file << name;
	file << (flags & objFlagSaveMask);

	file << alwaysVisible << sightRange << visibleMask << sightedMask;
	file << position << velocity << acceleration << rotation;
	file << radius;
	file << seeableRange;

	file << lockHint;

	file << (group ? group->id : int(0));
	file << (owner ? owner->id : INVALID_EMPIRE);

	if(!isValid())
		return;

	auto* func = type->functions[SOC_save];
	if(func) {
		SaveMessage msg(file);

		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject(script);
		cl.push((void*)this);
		cl.push((void*)&msg);
		if(cl.call()) {
			char* pData; net::msize_t size;
			msg.getAsPacket(pData, size);

			file << size;
			file.write(pData, size);
		}
		else {
			file << (net::msize_t)0;
		}
	}
	else {
		file << (net::msize_t)0;
	}
}

void Object::load(SaveFile& file) {
	if(!getFlag(objUninitialized))
		throw SaveFileError("Object already initialized");

	file >> name;
	file >> flags;

	file >> alwaysVisible >> sightRange >> visibleMask >> sightedMask;
	file >> position >> velocity >> acceleration >> rotation;
	file >> radius;
	if(file < SFV_0001) {
		double dummy;
		file >> dummy;
	}
	if(file >= SFV_0017)
		file >> seeableRange;

	if(file >= SFV_0009) {
		file >> lockHint;
		if(lockHint > 0)
			lockGroup = getLock(lockHint % getLockCount());
	}

	int groupID = file;
	if(groupID != 0 && isValid()) {
		group = ObjectGroup::byID(groupID);
		if(group) {
			for(unsigned i = 0; i < group->getObjectCount(); ++i) {
				if(group->getObject(i) == this) {
					physItem = group->getPhysicsItem(i);
					physItem->bound = AABBoxd::fromCircle(position, radius);
					physItem->gridLocation = 0;
					physItem->type = PIT_Object;
					physItem->object = this;
					break;
				}
			}
			if(!physItem) {
				error("%s (#%d) missing in group", name.c_str(), id);
				group->drop();
				group = nullptr;
			}
		}
		else {
			error("%s (#%d) missing group", name.c_str(), id);
		}
	}

	owner = Empire::getEmpireByID(file);

	if(!isValid())
		return;

	if(!physItem && !getFlag(objNoPhysics))
		physItem = devices.physics->registerItem(AABBoxd::fromCircle(position, radius), this);
	
	void* mixinMem = this + 1;
	type->states->prepare(mixinMem);

	script = type->create();

	auto* loadFunc = type->functions[SOC_load];
	SaveMessage scriptTypeData(file);

	net::msize_t size = file;
	if(size > 0) {
		char* buffer = (char*)malloc(size);
		file.read(buffer, size);
		scriptTypeData.setPacket(buffer, size);
		free(buffer);
	}

	//Either load the saved message, or default initialize
	if(loadFunc) {
		scripts::Call cl = devices.scripts.server->call(loadFunc);
		cl.setObject(script);
		cl.push((void*)this);
		cl.push((void*)&scriptTypeData);
		cl.call();
	}
	else {
		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_init]);
		if(cl.valid()) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.call();
		}
	}
	
	lockGroup->add(this);
	setFlag(objUninitialized, false);
}

void Object::postLoad() {
	auto* func = type->functions[SOC_postLoad];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject(script);
		cl.push((void*)this);
		cl.call();
	}
}
