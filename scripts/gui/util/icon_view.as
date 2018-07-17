import elements.GuiResources;
import planet_types;
import resources;
import orbitals;
from gui import gui_root;

export drawPlanetIcon;
void drawPlanetIcon(Planet@ obj, const recti& pos) {
	//Draw level and owner
	Color col;
	Empire@ owner = obj.visibleOwner;
	if(owner !is null && owner.valid) {
		col = owner.color;

		const Material@ mat;
		uint level = obj.visibleLevel;
		switch(level) {
			case 0: @mat = material::PlanetIcon0; break;
			case 1: @mat = material::PlanetIcon1; break;
			case 2: @mat = material::PlanetIcon2; break;
			case 3: @mat = material::PlanetIcon3; break;
			case 4: @mat = material::PlanetIcon4; break;
			case 5: @mat = material::PlanetIcon5; break;
			default:
				@mat = getMaterial("PlanetIcon"+obj.visibleLevel);
				if(mat is material::error)
					@mat = material::PlanetIcon4;
			break;
		}
		mat.draw(pos, col);
	}

	//Draw planet type
	const PlanetType@ type = getPlanetType(obj.PlanetType);
	type.icon.draw(pos.padded(0.15 * pos.width, 0.15 * pos.height));

	//Draw resource
	{
		const ResourceType@ res = getResource(obj.primaryResourceType);
		if(res !is null)
			res.smallIcon.draw(pos.padded(0.3 * pos.width, 0.3 * pos.height));
	}
}

void drawPlanetIcon(Planet@ obj, const recti& pos, Resource@ r, bool showType = true) {
	//Draw level and owner
	Color col;
	Empire@ owner = obj.visibleOwner;
	if(showType) {
		if(owner !is null && owner.valid) {
			col = owner.color;

			const Material@ mat;
			uint level = obj.visibleLevel;
			switch(level) {
				case 0: @mat = material::PlanetIcon0; break;
				case 1: @mat = material::PlanetIcon1; break;
				case 2: @mat = material::PlanetIcon2; break;
				case 3: @mat = material::PlanetIcon3; break;
				case 4: @mat = material::PlanetIcon4; break;
				case 5: @mat = material::PlanetIcon5; break;
				default:
					@mat = getMaterial("PlanetIcon"+obj.visibleLevel);
					if(mat is material::error)
						@mat = material::PlanetIcon4;
				break;
			}
			mat.draw(pos, col);
		}

	//Draw planet type
		const PlanetType@ type = getPlanetType(obj.PlanetType);
		type.icon.draw(pos.padded(0.15 * pos.width, 0.15 * pos.height));
	}

	recti resourcePos = pos.padded(0.3 * pos.width, 0.3 * pos.height);
	recti expandPos = resourcePos.padded(-2);

	//Draw resource
	if(r !is null && r.type !is null)
		drawSmallResource(r.type, r, resourcePos, obj, onPlanet=true);

	//Draw colonizing tick
	if(obj.isBeingColonized)
		spritesheet::ResourceIconsSmallMods.draw(8, expandPos-(resourcePos.size * 0.5));

	//Draw decay icon
	if(obj.decayTime > 0)
		spritesheet::ResourceIconsSmallMods.draw(9, expandPos);
}

void drawAsteroidIcon(Asteroid@ obj, const recti& pos, Resource@ r = null) {
	//Draw level and owner
	Color col;
	Empire@ owner = obj.owner;
	if(owner !is null && owner.valid)
		col = owner.color;

	recti resourcePos = pos.padded(0.3 * pos.width, 0.3 * pos.height);
	recti iconPos = pos.padded(0.2 * pos.width, 0.2 * pos.height);

	vec2i offset = pos.size * 0.15;
	iconPos -= offset;
	resourcePos += offset;

	//Draw asteroid icon
	material::AsteroidIcon.draw(iconPos, col);

	//Draw resource
	if(r !is null)
		drawSmallResource(r.type, r, resourcePos, obj, onPlanet=true);
}

void drawOrbitalIcon(Orbital@ obj, const recti& pos) {
	auto@ type = getOrbitalModule(obj.coreModule);
	if(type is null)
		return;

	Color col;
	Empire@ owner = obj.owner;
	if(owner !is null && owner.valid)
		col = owner.color;
	type.icon.draw(pos, col);
}

export drawFleetIcon;
void drawFleetIcon(Ship@ leader, const recti& pos, double barCur, double barMax,
		const Color& barColorLeft = Color(0xff6a00ff), const Color& barColorRight = Color(0xffc600ff)) {
	auto@ bp = leader.blueprint;
	if(!leader.valid || bp is null)
		return;

	const Design@ dsg = bp.design;
	if(dsg is null)
		return;

	Color color;
	Empire@ owner = leader.owner;
	if(owner !is null)
		color = owner.color;

	//In combat glow
	if(leader.inCombat) {
		double glowPct = abs((frameTime % 2.0) - 1.0);
		Color glow = Color(0xffc60020).interpolate(Color(0xffc60005), glowPct);
		drawRectangle(pos.padded(0.1 * pos.width), glow);
	}

	dsg.icon.draw(pos.padded(0.2 * pos.width), color);
	
	if(barMax != 0) {
		double pct = clamp(barCur / barMax, 0.0, 1.0);

		//Draw the bar
		recti barPos = pos.padded(0.06 * pos.width, 0.64 * pos.width, 0.06 * pos.width, 0.06 * pos.width);
		gui_root.skin.draw(SS_ProgressBarBG, SF_Normal, barPos);

		recti frontPos = barPos.padded(1);
		frontPos.botRight.x = frontPos.topLeft.x + pct * frontPos.width;

		auto color = barColorLeft.interpolate(barColorRight, pct);
		gui_root.skin.draw(SS_ProgressBar, SF_Normal, frontPos, color);

		//Draw the number
		gui_root.skin.getFont(FT_Small).draw(horizAlign=0.5, vertAlign=0.5,
				text=standardize(barCur, true), pos=barPos);
	}
}

void drawFleetIcon(Ship@ leader, const recti& pos, bool showStrength = true) {
	if(leader is null || !leader.valid)
		return;
	
	double maxStr = 0, curStr = 0;
	if(showStrength) {
		if(leader.supportCount > 0 && pos.height >= 30) {
			maxStr = leader.getFleetMaxStrength() / 1000.0;
			if(maxStr != 0)
				curStr = leader.getFleetStrength() / 1000.0;
		}
	}

	drawFleetIcon(leader, pos, curStr, maxStr);
}

void drawRegionIcon(Region@ region, const recti& pos) {
	material::SystemUnderAttack.draw(pos);
}

export drawObjectIcon;
void drawObjectIcon(Object@ obj, const recti& pos) {
	if(obj.isPlanet)
		drawPlanetIcon(cast<Planet>(obj), pos);
	else if(obj.isAsteroid)
		drawAsteroidIcon(cast<Asteroid>(obj), pos);
	else if(obj.isOrbital)
		drawOrbitalIcon(cast<Orbital>(obj), pos);
	else if(obj.isShip && obj.hasLeaderAI)
		drawFleetIcon(cast<Ship>(obj), pos);
	else if(obj.isArtifact)
		icons::Artifact.draw(pos);
	else if(obj.isRegion)
		drawRegionIcon(cast<Region>(obj), pos);
}

void drawObjectIcon(Object@ obj, const recti& pos, Resource@ r) {
	if(obj.isPlanet)
		drawPlanetIcon(cast<Planet>(obj), pos, r);
	else if(obj.isAsteroid)
		drawAsteroidIcon(cast<Asteroid>(obj), pos, r);
	else if(obj.isOrbital)
		drawOrbitalIcon(cast<Orbital>(obj), pos);
	else if(obj.isShip && obj.hasLeaderAI)
		drawFleetIcon(cast<Ship>(obj), pos);
	else if(obj.isArtifact)
		icons::Artifact.draw(pos);
	else if(obj.isRegion)
		drawRegionIcon(cast<Region>(obj), pos);
}
