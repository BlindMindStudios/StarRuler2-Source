class PersistentGfxScript {
	Object@ obj;
	ParticleSystemNode@ gfx;
	Region@ prevParent;
	bool objRotate = false;

	PersistentGfxScript(Node& node) {
		node.visible = false;
	}

	~PersistentGfxScript() {
		if(gfx !is null) {
			gfx.stop();
			@gfx = null;
		}
	}
	
	void stop(Node& node) {
		if(gfx !is null) {
			gfx.stop();
			@gfx = null;
		}
		
		@obj = null;
		@prevParent = null;
		node.markForDeletion();
	}
	
	void establish(Node& node, Object@ Obj, string psName, double scale) {
		@obj = Obj;
		@gfx = playParticleSystem(psName, obj.position, obj.radius * scale);
		@prevParent = obj.region;
		gfx.hintParentObject(prevParent, false);
		node.visible = obj !is null;
		gfx.visible = obj.visible || obj.known;
	}
	
	void establish(Node& node, vec3d at, string psName, double scale, Object@ parent) {
		@gfx = playParticleSystem(psName, at, scale);
		gfx.hintParentObject(parent, false);
		node.visible = true;
	}
	
	void rotate(quaterniond rot) {
		if(gfx !is null)
			gfx.emitRot = rot;
	}

	void setObjectRotation(bool value) {
		objRotate = value;
	}

	bool preRender(Node& node) {
		if(gfx is null)
			return false;
		
		if(obj !is null) {
			if(!obj.valid) {
				stop(node);
				return false;
			}
			
			if(obj.region !is prevParent) {
				@prevParent = obj.region;
				gfx.hintParentObject(prevParent, false);
			}
			
			//TODO: Make less awful
			bool visible = obj.visible || obj.known;
			gfx.visible = visible;
		
			gfx.position = obj.position;
			if(objRotate)
				gfx.emitRot = obj.rotation;
			gfx.rebuildTransform();
			
			gfx.velocity = obj.velocity;
		}
		return false;
	}
	
	//We don't actually need to render anything ourselves, we just manage a particle effect
	//void render(Node& node) {
	//}
};
