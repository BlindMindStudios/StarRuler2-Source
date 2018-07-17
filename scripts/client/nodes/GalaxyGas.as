import util.convar;

final class GasSprite {
	bool draw = true;
	uint baseCol = 0xffffff00;
	int trueAlpha = 20;
	int baseAlpha = 0;
	Color resultCol;
	double scale = 1.0;
	double rotation = randomd(0,twopi);
	double sortDist = 0;
	uint index;
	vec3d position;
	
	GasSprite(const vec3d& pos, double Scale, uint col, bool structured, int baseAlpha = 0) {
		position = pos;
		scale = Scale * 2.0;
		baseCol = col & 0xffffff00;
		trueAlpha = int(col & 0xff);
		index = structured ? randomi(0,23) : randomi(24,47);
		this.baseAlpha = baseAlpha;
	}
};

final class GalaxyGasScript {
	array<GasSprite@> sprites;
	array<int64> sorter;
	
	bool dirty = true;

	GalaxyGasScript(Node& node) {
		node.transparent = true;
		node.autoCull = false;
	}
	
	void addSprite(vec3d pos, double scale, uint color, bool structured, int baseAlpha = 0) {
		sorter.insertLast( int64(sprites.length) );
		sprites.insertLast( GasSprite(pos, scale, color, structured, baseAlpha) );
		
		dirty = true;
	}
	
	void recalculateBounds(Node& node) {
		vec3d p;
		for(uint i = 0, cnt = sprites.length; i < cnt; ++i)
			p += sprites[i].position;
		p /= double(sprites.length);
		node.position = p;
		double maxDist = 0;
		for(uint i = 0, cnt = sprites.length; i < cnt; ++i)
			maxDist = max(maxDist, p.distanceTo(sprites[i].position) + sprites[i].scale);
		node.scale = maxDist;
		node.rebuildTransform();
	}
	
	bool preRender(Node& node) {
		if(!settings::bShowGalaxyGas)
			return false;
		if(dirty) {
			dirty = false;
			if(sprites.length == 0)
				return false;
			recalculateBounds(node);
		}
		if(!node.isInView())
			return false;
		bool anyVisible = false;
		
		//Update the sprite's color and decide if it needs rendered/sorted
		for(uint i = 0, cnt = sprites.length; i < cnt; ++i) {
			uint index = uint(sorter[i]) & 0x7fffffff;
			GasSprite@ sprite = sprites[index];
			
			double sortDist = getCameraDistance(sprite.position);
			if(sortDist < 0.0) {
				sprite.draw = false;
				continue;
			}
			
			double fadeOut = ((sortDist / 30000.0) - 0.3);
			int trueAlpha = sprite.trueAlpha;
			int a = fadeOut < 1.0 ? int(double(trueAlpha) * fadeOut) : trueAlpha;
			a += sprite.baseAlpha;
			if(a < 4) {
				sprite.draw = false;
				continue;
			}
			
			sprite.resultCol = Color(sprite.baseCol | a);
			sprite.draw = true;
			anyVisible = true;
				
			sorter[i] = (int64(sortDist * 100.0) << 32) | int64(index);
		}
		
		if(anyVisible)
			sorter.sortAsc();
		
		return anyVisible;
	}
	
	void render(Node& node) {
		for(uint i = 0, cnt = sprites.length; i < cnt; ++i) {
			GasSprite@ sprite = sprites[sorter[i] & 0x7fffffff];
			if(sprite.draw)
				renderBillboard(spritesheet::Nebulas, sprite.index, sprite.position, sprite.scale, sprite.rotation, sprite.resultCol);
		}
	}
};
