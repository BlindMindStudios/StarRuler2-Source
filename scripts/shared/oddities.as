enum OddityType {
	Odd_Slipstream,
	Odd_Wormhole,
	Odd_Nebula,
};

#section server-side
StrategicIconNode@ makeOddityVisuals(Oddity& obj, uint type, bool fromCreation = true, bool isServer = true, uint color = 0xffffffff) {
	StrategicIconNode@ icon;
	if(type == Odd_Slipstream) {
		auto@ gfx = PersistentGfx();
		gfx.establish(obj, "Tear", 1.0/3.0);
		gfx.rotate(quaterniond_fromAxisAngle(vec3d_up(), pi * 0.5) * obj.rotation);

		@icon = StrategicIconNode();
		icon.establish(obj, 0.0325, spritesheet::OrbitalIcons, 4);
		icon.memorable = true;
		icon.setColor(0xffafffff);

		if(obj.region !is null)
			obj.region.addStrategicIcon(-1, obj, icon);
#section server
		if(fromCreation && (obj.region is null || obj.region.VisionMask & playerEmpire.mask != 0))
			sound::open_slipstream.play(obj.position, priority=true);
		
		addAmbientSource(CURRENT_PLAYER, "tear", obj.id, obj.position, obj.radius);
#section shadow
		if(!inGalaxyCreation && (obj.region is null || obj.region.VisionMask & playerEmpire.mask != 0))
			sound::open_slipstream.play(obj.position, priority=true);
		
		addAmbientSource("tear", obj.id, obj.position, obj.radius);
#section server-side
	}
	else if(type == Odd_Wormhole) {
		auto@ gfx = PersistentGfx();
		gfx.establish(obj, "Wormhole", 1.0/3.0);

		@icon = StrategicIconNode();
		icon.establish(obj, 0.0325, spritesheet::OrbitalIcons, 4);
		icon.memorable = true;
		icon.setColor(0x66f4ffff);

		if(obj.region !is null)
			obj.region.addStrategicIcon(-1, obj, icon);
		
#section server
		addAmbientSource(CURRENT_PLAYER, "tear", obj.id, obj.position, obj.radius);
#section shadow
		addAmbientSource("tear", obj.id, obj.position, obj.radius);
#section server-side
	}
	else if(type == Odd_Nebula) {
		auto@ node = GalaxyGas();
		node.position = obj.position;
		node.scale = obj.radius;
		node.rebuildTransform();
		
		Colorf fCol(Color(color));
		float h = fCol.hue, s = fCol.saturation, v = fCol.value;

		for(uint i = 0; i < 40; ++i) {
			vec2d off = (random2d(0, 0.75) * obj.radius);
			vec3d pos = obj.position;
			pos.x += off.x;
			pos.z += off.y;

			double rad = obj.radius * 0.65;
			Colorf hsv;
			hsv.fromHSV(h + normald(-70.0,70.0), clamp(s * normald(0.6,1.4), 0.0, 1.0), v);
			Color col(hsv);
			col.a = randomi(0x18,0x22);

			node.addSprite(pos, rad, col.rgba, true, baseAlpha=col.a);
		}
	}

	return icon;
}
