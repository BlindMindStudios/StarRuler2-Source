Mutex gfxLock;
array<GfxEffect@> gfxNodes;

class GfxEffect {
	int64 id;
	double expireTime = INFINITY;

	void init() {}
	void destroy() {}
	void render(double time) {}
};

class BeamEffect : GfxEffect {
	Object@ from;
	Object@ to;
	Color color;
	double width;
	const Material@ mat = material::MoveBeam;

	BeamNode@ node;

	void init() override {
		@node = BeamNode(mat, width, from.node_position, to.node_position, false);
		node.color = color;
	}

	void destroy() override {
		if(node !is null) {
			node.visible = false;
			node.markForDeletion();
			@node = null;
		}
	}

	void render(double time) override {
		if(node !is null) {
			node.position = from.node_position;
			node.endPosition = to.node_position;
			node.visible = from.visible || to.visible;
			node.rebuildTransform();
		}
	}
};

class PersistentParticlesEffect : GfxEffect {
	Object@ from;
	string particleName;
	double size = 1.0;
	PersistentGfx@ node;

	void init() override {
		@node = PersistentGfx();
		node.establish(from, particleName, size);
		node.setObjectRotation(true);
	}

	void destroy() override {
		if(node !is null) {
			node.stop();
			@node = null;
		}
	}
};

void makeBeamEffect(int64 id, Object@ from, Object@ to, uint color, double width, string material = "", double timer = -1.0) {
	if(from is null || to is null)
		return;

	BeamEffect eff;
	eff.id = id;
	@eff.from = from;
	@eff.to = to;
	eff.color.color = color;
	eff.width = width;

	if(material.length != 0)
		@eff.mat = getMaterial(material);

	if(timer > 0)
		eff.expireTime = gameTime + timer;

	addGfxEffect(eff);
}

void makePersistentParticles(int64 id, Object@ from, string particleName, double size = 1.0, double timer = -1.0) {
	if(from is null)
		return;

	PersistentParticlesEffect eff;
	eff.id = id;
	@eff.from = from;
	eff.size = size;
	eff.particleName = particleName;

	if(timer > 0)
		eff.expireTime = gameTime + timer;

	addGfxEffect(eff);
}

void addGfxEffect(GfxEffect@ eff) {
	Lock lck(gfxLock);

	bool found = false;
	for(uint i = 0, cnt = gfxNodes.length; i < cnt; ++i) {
		if(gfxNodes[i].id == eff.id) {
			gfxNodes[i].destroy();
			@gfxNodes[i] = eff;
			found = true;
		}
	}

	if(!found)
		gfxNodes.insertLast(eff);
	eff.init();
}

void removeGfxEffect(int64 id) {
	Lock lck(gfxLock);
	for(uint i = 0, cnt = gfxNodes.length; i < cnt; ++i) {
		if(gfxNodes[i].id == id) {
			gfxNodes[i].destroy();
			gfxNodes.removeAt(i);
			return;
		}
	}
}

void tick(double time) {
	double gtime = gameTime;
	Lock lck(gfxLock);
	for(int i = gfxNodes.length - 1; i >= 0; --i) {
		if(gfxNodes[i].expireTime < gtime) {
			gfxNodes[i].destroy();
			gfxNodes.removeAt(i);
		}
	}
}

void render(double time) {
	Lock lck(gfxLock);
	for(uint i = 0, cnt = gfxNodes.length; i < cnt; ++i)
		gfxNodes[i].render(time);
}
