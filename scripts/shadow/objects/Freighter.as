import regions.regions;

tidy class FreighterScript {
	FreighterScript() {
	}

	void makeMesh(Freighter& obj) {
		MeshDesc shipMesh;
		const Shipset@ ss = obj.owner.shipset;
		const ShipSkin@ skin;
		if(ss !is null)
			@skin = ss.getSkin(obj.skin);

		if(skin !is null) {
			@shipMesh.model = skin.model;
			@shipMesh.material = skin.material;
		}
		else {
			@shipMesh.model = model::Fighter;
			@shipMesh.material = material::Ship10;
		}

		@shipMesh.iconSheet = spritesheet::HullIcons;
		shipMesh.iconIndex = 0;

		bindMesh(obj, shipMesh);
	}

	void init(Freighter& ship) {
		//Create the graphics
		makeMesh(ship);
	}

	void destroy(Freighter& ship) {
		leaveRegion(ship);
	}

	bool onOwnerChange(Freighter& obj, Empire@ prevOwner) {
		regionOwnerChange(obj, prevOwner);
		return false;
	}
	
	double tick(Freighter& ship, double time) {
		updateRegion(ship);
		ship.moverTick(time);
		return 0.2;
	}

	void syncInitial(Freighter& ship, Message& msg) {
		msg >> ship.skin;
		ship.readMover(msg);
	}

	void syncDetailed(Freighter& ship, Message& msg, double tDiff) {
		ship.readMover(msg);
	}

	void syncDelta(Freighter& ship, Message& msg, double tDiff) {
		if(msg.readBit())
			ship.readMoverDelta(msg);
	}
};

