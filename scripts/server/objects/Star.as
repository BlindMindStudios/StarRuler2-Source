import regions.regions;
import saving;
import systems;

LightDesc lightDesc;

tidy class StarScript {
	bool hpDelta = false;

	void syncInitial(const Star& star, Message& msg) {
		msg << float(star.temperature);
		star.writeOrbit(msg);
	}

	void save(Star& star, SaveFile& file) {
		saveObjectStates(star, file);
		file << star.temperature;
		file << cast<Savable>(star.Orbit);
		file << star.Health;
		file << star.MaxHealth;
	}
	
	void load(Star& star, SaveFile& file) {
		loadObjectStates(star, file);
		file >> star.temperature;
		
		if(star.owner is null)
			@star.owner = defaultEmpire;

		lightDesc.att_quadratic = 1.f/(2000.f*2000.f);
		
		double temp = star.temperature;
		Node@ node;
		double soundRadius = star.radius;
		if(temp > 0.0) {
			@node = bindNode(star, "StarNode");
			node.color = blackBody(temp, max((temp + 15000.0) / 40000.0, 1.0));
		}
		else {
			@node = bindNode(star, "BlackholeNode");
			node.color = blackBody(16000.0, max((16000.0 + 15000.0) / 40000.0, 1.0));
			cast<BlackholeNode>(node).establish(star);
			soundRadius *= 10.0;
		}
		
		addAmbientSource(CURRENT_PLAYER, "star_rumble", star.id, star.position, soundRadius);

		if(file >= SV_0028)
			file >> cast<Savable>(star.Orbit);

		if(file >= SV_0102) {
			file >> star.Health;
			file >> star.MaxHealth;
		}

		lightDesc.position = vec3f(star.position);
		lightDesc.radius = star.radius;
		lightDesc.diffuse = node.color * 1.0f;
		if(temp <= 0)
			lightDesc.diffuse.a = 0.f;
		lightDesc.specular = lightDesc.diffuse;

		if(star.inOrbit)
			makeLight(lightDesc, node);
		else
			makeLight(lightDesc);
	}

	void syncDetailed(const Star& star, Message& msg) {
		msg << float(star.Health);
		msg << float(star.MaxHealth);
	}

	bool syncDelta(const Star& star, Message& msg) {
		if(!hpDelta)
			return false;

		msg << float(star.Health);
		msg << float(star.MaxHealth);
		hpDelta = false;
		return true;
	}

	void postLoad(Star& star) {
		Node@ node = star.getNode();
		if(node !is null)
			node.hintParentObject(star.region, false);
	}
	
	void postInit(Star& star) {
		double soundRadius = star.radius;
		//Blackholes need a 'bigger' sound
		if(star.temperature == 0.0)
			soundRadius *= 10.0;
		addAmbientSource(CURRENT_PLAYER, "star_rumble", star.id, star.position, soundRadius);
	}

	void dealStarDamage(Star& star, double amount) {
		hpDelta = true;
		star.Health -= amount;
		if(star.Health <= 0) {
			star.Health = 0;
			star.destroy();
		}
	}

	void destroy(Star& star) {
		if(!game_ending) {
			double explRad = star.radius;
			if(star.temperature == 0.0) {
				explRad *= 20.0;

				for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
					auto@ sys = getSystem(i);
					double dist = star.position.distanceTo(sys.position);
					if(dist < 100000.0) {
						double factor = sqr(1.0 - (dist / 100000));
						sys.object.addStarDPS(factor * star.MaxHealth * 0.08);
					}
				}
			}
			playParticleSystem("StarExplosion", star.position, star.rotation, explRad);

			//auto@ node = createNode("NovaNode");
			//if(node !is null)
			//	node.position = star.position;
			removeAmbientSource(CURRENT_PLAYER, star.id);
			if(star.region !is null)
				star.region.addSystemDPS(star.MaxHealth * 0.12);
		}
		leaveRegion(star);
	}
	
	/*void damage(Star& star, DamageEvent& evt, double position, const vec2d& direction) {
		evt.damage -= 100.0;
		if(evt.damage > 0.0)
			star.HP -= evt.damage;
	}*/
	
	double tick(Star& obj, double time) {
		updateRegion(obj);
		obj.orbitTick(time);

		Region@ reg = obj.region;
		uint mask = ~0;
		if(reg !is null && obj.temperature > 0)
			mask = reg.ExploredMask.value;
		obj.donatedVision = mask;

		return 1.0;
	}
};
