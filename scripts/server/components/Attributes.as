import attributes;

tidy class AttributeMod : Savable {
	int id;
	uint mode;
	double amount;
	double timer;

	void save(SaveFile& file) {
		file << id << mode << amount << timer;
	}

	void load(SaveFile& file) {
		file >> id >> mode >> amount >> timer;
	}
};

tidy class Attribute : Savable {
	uint index = 0;
	double value = 0.0;
	double base = 0.0;
	bool delta = false;

	int permAdd = 0;
	int permAddBase = 0;
	int permAddFactor = 0;
	double permMultiply = 1.0;

	array<AttributeMod@> mods;
	int nextModId = 1;

	void init(Empire& emp, uint ind) {
		index = ind;
		if(ind < EA_COUNT) {
			base = emp.attributes[ind];
			value = base;
		}
	}

	void update(Empire& emp) {
		double add = double(permAdd) / 1000.0;
		double addBase = double(permAddBase) / 1000.0;
		double addFactor = double(permAddFactor) / 1000.0;
		double mult = permMultiply;

		for(uint i = 0, cnt = mods.length; i < cnt; ++i) {
			switch(mods[i].mode) {
				case AC_Add: add += mods[i].amount; break;
				case AC_AddBase: addBase += mods[i].amount; break;
				case AC_AddFactor: addFactor += mods[i].amount; break;
				case AC_Multiply: mult *= mods[i].amount; break;
			}
		}

		value = ((base + addBase) * (1.0 + addFactor) + add) * mult;
		if(index < EA_COUNT)
			emp.attributes[index] = value;
		delta = true;
	}

	void mod(Empire& emp, uint mode, double amount) {
		switch(mode) {
			case AC_Add: permAdd += int(amount * 1000.0); break;
			case AC_AddBase: permAddBase += int(amount * 1000.0); break;
			case AC_AddFactor: permAddFactor += int(amount * 1000.0); break;
			case AC_Multiply: permMultiply *= amount; break;
		}
		update(emp);
	}

	AttributeMod@ createMod(Empire& emp, uint mode, double amount, double timer = -1.0) {
		AttributeMod mod;
		mod.id = nextModId++;
		mod.mode = mode;
		mod.amount = amount;
		mod.timer = timer;
		mods.insertLast(mod);
		update(emp);
		return mod;
	}

	void removeMod(Empire& emp, int id) {
		for(int i = mods.length - 1; i >= 0; --i) {
			if(mods[i].id == id) {
				mods.removeAt(i);
				update(emp);
				break;
			}
		}
	}

	void tick(Empire& emp, double time) {
		bool changed = false;
		for(int i = mods.length - 1; i >= 0; --i) {
			auto@ mod = mods[i];
			if(mod.timer >= 0) {
				mod.timer -= time;
				if(mod.timer < 0) {
					mods.removeAt(i);
					changed = true;
				}
			}
		}

		if(changed)
			update(emp);
	}

	void save(SaveFile& file) {
		file << index;
		file << value;
		file << base;
		file << permAdd;
		file << permAddBase;
		file << permAddFactor;
		file << permMultiply;
		file << nextModId;

		uint cnt = mods.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << mods[i];
	}

	void load(SaveFile& file) {
		file >> index;
		if(file >= SV_0098)
			file >> value;
		file >> base;
		file >> permAdd;
		file >> permAddBase;
		file >> permAddFactor;
		file >> permMultiply;
		file >> nextModId;

		uint cnt = 0;
		file >> cnt;
		mods.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@mods[i] = AttributeMod();
			file >> mods[i];
		}
	}
};

tidy class Attributes : Component_Attributes, Savable {
	Mutex mtx;
	array<Attribute> attributes(getEmpAttributeCount());

	double getAttribute(Empire& emp, uint id) {
		if(id < EA_COUNT)
			return emp.attributes[id];
		if(id >= attributes.length)
			return 0;
		return attributes[id].value;
	}

	void initAttributes(Empire& emp) {
		Lock lock(mtx);
		for(uint i = 0, cnt = attributes.length; i < cnt; ++i)
			attributes[i].init(emp, i);
	}

	void syncAttributes(Empire& emp) {
		for(uint i = 0, cnt = attributes.length; i < cnt; ++i)
			attributes[i].update(emp);
	}

	double stored = randomd();
	void attributesTick(Empire& emp, double time) {
		Lock lock(mtx);
		stored += time;
		if(stored > 1.0) {
			for(uint i = 0, cnt = attributes.length; i < cnt; ++i)
				attributes[i].tick(emp, time);
			stored = 0.0;
		}
	}

	int createAttributeMod(Empire& emp, uint attrib, uint mode, double amount, double timer = -1.0) {
		if(attrib >= attributes.length)
			return -1;
		auto@ attr = attributes[attrib];

		Lock lock(mtx);
		auto@ mod = attr.createMod(emp, mode, amount, timer);
		if(mod is null)
			return -1;

		return mod.id;
	}

	void removeAttributeMod(Empire& emp, uint attrib, int id) {
		if(attrib >= attributes.length)
			return;
		auto@ attr = attributes[attrib];

		Lock lock(mtx);
		attr.removeMod(emp, id);
	}

	void modAttribute(Empire& emp, uint attrib, uint mode, double amount) {
		if(attrib >= attributes.length)
			return;
		auto@ attr = attributes[attrib];

		Lock lock(mtx);
		attr.mod(emp, mode, amount);
	}

	void save(SaveFile& file) {
		uint cnt = attributes.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file.writeIdentifier(SI_EmpAttribute, i);
			file << attributes[i];
		}
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		attributes.length = max(getEmpAttributeCount(), cnt);
		for(uint i = 0; i < cnt; ++i) {
			uint id = i;
			if(file >= SV_0098)
				id = file.readIdentifier(SI_EmpAttribute);
			if(id < attributes.length)
				file >> attributes[id];
			else
				file >> Attribute();
		}
	}

	void writeAttributes(Empire& emp, Message& msg, bool initial) {
		Lock lock(mtx);

		msg.writeAlign();
		uint pos = msg.reserve();
		uint n = 0;
		for(uint i = 0, cnt = attributes.length; i < cnt; ++i) {
			if(!attributes[i].delta && !initial)
				continue;

			if(!initial)
				attributes[i].delta = false;
			msg.writeLimited(i,cnt-1);
			msg << attributes[i].value;
			++n;
		}

		msg.fill(pos, n);
	}
};
