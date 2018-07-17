import construction.Constructible;
import orbitals;
import object_creation;
import attributes;

tidy class OrbitalConstructible : Constructible {
	const OrbitalModule@ def;
	vec3d position;
	Orbital@ target;

	OrbitalConstructible(Object& obj, const OrbitalModule@ Def, const vec3d& pos) {
		@def = Def;
		buildCost = def.buildCost * obj.owner.OrbitalBuildCostFactor;
		totalLabor = def.laborCost * obj.owner.OrbitalLaborCostFactor;
		position = pos;
	}

	bool repeat(Object& obj) {
		if(!Constructible::repeat(obj))
			return false;
		if(!def.canBuild(obj, position))
			return false;
		vec2d offset = random2d(def.size * 2.0, def.size * 4.0);
		position.x += offset.x;
		position.z += offset.y;
		return true;
	}

	OrbitalConstructible(SaveFile& file) {
		Constructible::load(file);

		uint defId = file.readIdentifier(SI_Orbital);
		@def = getOrbitalModule(defId);
		file >> position;
		file >> target;
	}

	void save(SaveFile& file) {
		Constructible::save(file);
		file.writeIdentifier(SI_Orbital, def.id);
		file << position;
		file << target;
	}

	bool pay(Object& obj) {
		for(uint i = 0, cnt = def.hooks.length; i < cnt; ++i) {
			if(!def.hooks[i].consume(obj)) {
				for(uint j = 0; j < i; ++j)
					def.hooks[j].reverse(obj, false);
				return false;
			}
		}
		if(!Constructible::pay(obj)) {
			for(uint i = 0, cnt = def.hooks.length; i < cnt; ++i)
				def.hooks[i].reverse(obj, false);
			return false;
		}
		@target = createOrbital(position, def, obj.owner, disabled=true);
		return true;
	}

	void cancel(Object& obj) {
		if(buildCost != 0 && target !is null) {
			if(!target.valid) {
				buildCost = 0;
			}
			else {
				double maxHealth = target.maxHealth + target.maxArmor;
				double pct = 0.0;
				if(totalLabor > 0)
					maxHealth *= curLabor / totalLabor;
				if(maxHealth != 0)
					pct = clamp((target.health + target.armor) / maxHealth, 0.0, 1.0);
				pct = clamp((pct-0.01) / 0.99, 0.0, 1.0);
				buildCost = int(double(buildCost) * pct);
			}
		}
		for(uint i = 0, cnt = def.hooks.length; i < cnt; ++i)
			def.hooks[i].reverse(obj, true);
		Constructible::cancel(obj);
		if(target !is null && target.valid)
			target.destroy();
	}

	ConstructibleType get_type() {
		return CT_Orbital;
	}

	string get_name() {
		return def.name;
	}

	TickResult tick(Object& obj, double time) override {
		if(target is null || !target.valid || !def.canBuild(obj, target.position, initial=false)) {
			cancel(obj);
			return TR_Remove;
		}
		target.setBuildPct(curLabor / totalLabor);
		return TR_UsedLabor;
	}

	void complete(Object& obj) {
		if(target !is null) {
			target.setDisabled(false);
			obj.owner.modAttribute(EA_OrbitalsBuilt, AC_Add, 1.0);
		}
	}

	void write(Message& msg) {
		Constructible::write(msg);
		msg << def.id;
	}
};
