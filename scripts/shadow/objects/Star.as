import regions.regions;

LightDesc lightDesc;

tidy class StarScript {
	void syncInitial(Star& star, Message& msg) {
		star.temperature = msg.read_float();

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
		
		if(node !is null)
			node.hintParentObject(star.region);

		star.readOrbit(msg);
		
		lightDesc.position = vec3f(star.position);
		lightDesc.diffuse = node.color * 1.0f;
		lightDesc.specular = lightDesc.diffuse;
		lightDesc.radius = star.radius;

		if(star.inOrbit)
			makeLight(lightDesc, node);
		else
			makeLight(lightDesc);
		
		addAmbientSource("star_rumble", star.id, star.position, soundRadius);
	}

	void destroy(Star& obj) {
		removeAmbientSource(obj.id);
		leaveRegion(obj);
	}

	void syncDetailed(Star& star, Message& msg, double tDiff) {
		star.Health = msg.read_float();
		star.MaxHealth = msg.read_float();
	}

	void syncDelta(Star& star, Message& msg, double tDiff) {
		star.Health = msg.read_float();
		star.MaxHealth = msg.read_float();
	}

	double tick(Star& star, double time) {
		if(updateRegion(star)) {
			auto@ node = star.getNode();
			if(node !is null)
				node.hintParentObject(star.region);
		}
		star.orbitTick(time);

		return 1.0;
	}
};
