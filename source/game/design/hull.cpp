#include "design/hull.h"
#include "str_util.h"
#include "main/logging.h"
#include "main/references.h"
#include "compat/misc.h"
#include "design/design.h"
#include "design/subsystem.h"
#include "design/subsystem.h"
#include "threads.h"
#include "vec3.h"
#include "line3d.h"
#include <algorithm>
#include "files.h"
#include <math.h>
#include <cmath>
#include <assert.h>
#include <stdint.h>

static std::vector<Shipset*> shipsets;
static umap<std::string, unsigned> shipsetIndices;

static std::vector<HullDef*> hullDefinitions;
static umap<std::string, unsigned> hullIndices;

static unsigned computedHulls = 0;
void computeHulls(unsigned amount) {
	unsigned offset = randomi(0, hullDefinitions.size()-1);
	for(unsigned n = 0, cnt = hullDefinitions.size(); n < cnt; ++n) {
		if(hullDefinitions[(offset+n)%cnt]->calculateImpacts()) {
			++computedHulls;
			if(computedHulls >= hullDefinitions.size())
				return;
			--amount;
			if(amount == 0)
				return;
		}
	}
}

bool isFinishedComputingHulls() {
	return computedHulls >= hullDefinitions.size();
}

unsigned getHullCount() {
	return (unsigned)hullDefinitions.size();
}

const HullDef* getHullDefinition(unsigned id) {
	if(id >= hullDefinitions.size())
		return 0;
	return hullDefinitions[id];
}

const HullDef* getHullDefinition(const std::string& name) {
	auto it = hullIndices.find(name);
	if(it == hullIndices.end())
		return 0;
	return hullDefinitions[it->second];
}

HullDef::HullDef()
	: id(-1), background(0), material(0), mesh(0),
	iconSheet(0), iconIndex(0), gridSize(16, 8), backgroundScale(1.0), modelScale(1.0),
	active(gridSize), exterior(gridSize), activeCount(0), exteriorCount(0),
	minSize(1.0), maxSize(-1.0), baseHull(this), shape(nullptr), special(false)
{
	active.clear(false);
	exterior.clear(false);
}

HullDef::HullDef(const HullDef& other) {
	*this = other;
}

void clearHullDefinitions() {
	foreach(it, hullDefinitions) {
		auto* hull = *it;
		hull->baseHull = nullptr;
		hull->drop();
	}
	hullDefinitions.clear();
	hullIndices.clear();
	computedHulls = 0;
}

void loadHullDefinitions(const std::string& filename) {
	std::vector<HullDef*> defs;
	readHullDefinitions(filename, defs);

	foreach(it, defs) {
		(*it)->calculateDist();
		(*it)->calculateExterior();
		(*it)->id = (unsigned)hullDefinitions.size();
		hullDefinitions.push_back(*it);
		hullIndices[(*it)->ident] = (*it)->id;
	}
}

bool meshIntersect(const Mesh& mesh, const line3dd& line, vec3d& output) {
	double closestDist = 1e100;
	vec3d closestIntersect;

	for(unsigned i = 0, cnt = mesh.faces.size(); i < cnt; ++i) {
		const Mesh::Face& face = mesh.faces[i];

		vec3d v1 = vec3d(mesh.vertices[face.a].position);
		vec3d v2 = vec3d(mesh.vertices[face.b].position);
		vec3d v3 = vec3d(mesh.vertices[face.c].position);

		vec3d point;
		if(line.intersectTriangle(v1, v2, v3, point)) {
			double dist = line.start.distanceToSQ(point);
			if(dist < closestDist) {
				closestIntersect = point;
				closestDist = dist;
			}
		}
	}

	if(!closestIntersect.zero()) {
		output = closestIntersect;
		return true;
	}
	return false;
}

bool HullDef::calculateImpacts() {
	if(!impacts.empty())
		return false;
	if(!this->mesh)
		return true;
	const Mesh& mesh = this->mesh->getMesh();
	if(mesh.faces.empty())
		return false;

	//double t = devices.driver->getAccurateTime();

	std::vector<vec3d> lineImpacts;
	lineImpacts.resize(8 * 64);
	impacts.resize(8 * 64);

	//Trace the impact lines
	for(unsigned n = 0; n < 8; ++n) {
		double theta = (double)n / 8.0 * pi;
		for(unsigned i = 0; i < 64; ++i) {
			double phi = (double)i / 64.0 * twopi;

			double st = sin(theta);
			vec3d start = vec3d(
				st * cos(phi),
				cos(theta),
				st * sin(phi)
			);

			line3dd ray(start, vec3d(0.0));

			vec3d point;
			if(meshIntersect(mesh, ray, point))
				lineImpacts[n*64 + i] = point;
			else
				lineImpacts[n*64 + i] = vec3d();
		}
	}

	//Pre-calculate the closest impact points for angles
	for(unsigned n = 0; n < 8; ++n) {
		double theta = (double)n / 8.0 * pi;
		for(unsigned i = 0; i < 64; ++i) {
			double phi = (double)i / 64.0 * twopi;

			double st = sin(theta);
			vec3d point = vec3d(
				st * cos(phi),
				cos(theta),
				st * sin(phi)
			);

			double d = 1e80;
			vec3d imp;
			for(unsigned j = 0, jcnt = lineImpacts.size(); j < jcnt; ++j) {
				double dist = lineImpacts[j].distanceToSQ(point);
				if(dist < d) {
					d = dist;
					imp = lineImpacts[j];
				}
			}

			impacts[n*64 + i] = imp;
		}
	}

	//double tend = devices.driver->getAccurateTime();
	//print("Impacts %s - %gms", ident.c_str(), (tend-t)*1000.0);
	return true;
}

vec3d HullDef::getImpact(const vec3d& offset, double radius, bool constant) const {
	if(baseHull != nullptr && baseHull != this)
		return baseHull->getImpact(offset, radius);
	
	if(impacts.size() == 0)
		return offset;

	vec3d uoffset = offset / radius;

	double theta = std::fmod(twopi + acos(uoffset.y / uoffset.getLength()), twopi);
	double phi = std::fmod(twopi + atan2(uoffset.z, uoffset.x), twopi);

	unsigned row = (unsigned)floor(theta / pi * 8.0 + 0.5) % 8;
	unsigned index;
	if(constant)
		index = ((unsigned)floor(phi / twopi * 64.0 + 0.5)) % 64;
	else
		index = ((unsigned)floor(phi / twopi * 64.0 + 0.5) + randomi(-1,1)) % 64;

	vec3d imp = impacts[row*64 + index];
	if(imp.zero())
		return offset;

	return imp * radius;
}

vec3d HullDef::getClosestImpact(const vec3d& offset) const {
	if(baseHull != nullptr && baseHull != this)
		return baseHull->getClosestImpact(offset);
	
	if(impacts.size() == 0)
		return offset;

	double d = 1e80;
	vec3d imp;
	for(unsigned j = 0, jcnt = impacts.size(); j < jcnt; ++j) {
		double dist = impacts[j].distanceToSQ(offset);
		if(dist < d) {
			d = dist;
			imp = impacts[j];
		}
	}

	return imp;
}

void HullDef::calculateExterior() {
	//Top & Bottom Lines
	for(unsigned i = 0, cnt = gridSize.x; i < cnt; ++i) {
		if(i % 2 == 0) {
			calculateExterior(vec2u(i, 0), HEX_DownLeft);
			calculateExterior(vec2u(i, 0), HEX_Down);
			calculateExterior(vec2u(i, 0), HEX_DownRight);

			calculateExterior(vec2u(i, gridSize.y-1), HEX_Up);
		}
		else {
			calculateExterior(vec2u(i, 0), HEX_Down);

			calculateExterior(vec2u(i, gridSize.y-1), HEX_UpLeft);
			calculateExterior(vec2u(i, gridSize.y-1), HEX_Up);
			calculateExterior(vec2u(i, gridSize.y-1), HEX_UpRight);
		}
	}

	//Right & Left Lines
	for(unsigned i = 0, cnt = gridSize.y; i < cnt; ++i) {
		calculateExterior(vec2u(0, i), HEX_DownRight);
		calculateExterior(vec2u(0, i), HEX_UpRight);

		calculateExterior(vec2u(gridSize.x-1, i), HEX_DownLeft);
		calculateExterior(vec2u(gridSize.x-1, i), HEX_UpLeft);
	}
}

void HullDef::calculateExterior(vec2u pos, unsigned direction) {
	unsigned mask = (1<<((direction+3)%6));
	do {
		if((mask & flagExteriorFaux) && !(exterior[pos] & (flagExteriorFaux | flagExteriorPass)) && active[pos])
			break;
		exterior[pos] |= mask;
		if(active[pos]) {
			if(exterior[pos] & flagExteriorPass)
				continue;
			if(exterior[pos] & flagExteriorFaux) {
				mask |= flagExteriorFaux;
				continue;
			}
			break;
		}
	}
	while(exterior.advance(pos, (HexGridAdjacency)direction));
}

void HullDef::calculateDist() {
	if(shape == nullptr || shape->format != FMT_RGBA)
		return;

	if(shapeMapped)
		return;

	//First, make it binary. This is a distance map, so every active
	//pixel should be 0 and every inactive should be full distance.
	for(unsigned x = 0; x < shape->width; ++x) {
		for(unsigned y = 0; y < shape->height; ++y) {
			Color& col = shape->get_rgba(x, y);
			if(col.a != 0)
				col.a = 0;
			else
				col.a = 0xff;
		}
	}

	//Calculate distances
	for(unsigned x = 0; x < shape->width; ++x) {
		for(unsigned y = 0; y < shape->height; ++y) {
			if(shape->get_rgba(x, y).a == 0)
				calculateDist(vec2u(x,y), 0);
		}
	}

	saveImage(shape, shapeMap.c_str());
}

void HullDef::calculateDist(vec2u pos, int dist) {
	assert(dist <= shape->get_rgba(pos.x, pos.y).a);
	shape->get_rgba(pos.x, pos.y).a = std::min(dist, 255);

	int wmod = std::max(512 / (int)shape->width, 1);
	int hmod = std::max(512 / (int)shape->height, 1);

	if(pos.x > 0) {
		if(shape->get_rgba(pos.x-1, pos.y).a > dist+wmod)
			calculateDist(vec2u(pos.x-1, pos.y), dist+wmod);
	}
	if(pos.x < shape->width-1) {
		if(shape->get_rgba(pos.x+1, pos.y).a > dist+wmod)
			calculateDist(vec2u(pos.x+1, pos.y), dist+wmod);
	}
	if(pos.y > 0) {
		if(shape->get_rgba(pos.x, pos.y-1).a > dist+hmod)
			calculateDist(vec2u(pos.x, pos.y-1), dist+hmod);
	}
	if(pos.y < shape->height-1) {
		if(shape->get_rgba(pos.x, pos.y+1).a > dist+hmod)
			calculateDist(vec2u(pos.x, pos.y+1), dist+hmod);
	}
}

double HullDef::getMatchDistance(const vec2d& pos) const {
	if(shape == nullptr)
		return 128.0;
	return shape->getTexel(pos.x, pos.y).a;
}

double HullDef::getMatchDistance(void* descPtr) const {
	auto& desc = *(Design::Descriptor*)descPtr;
	double dist = 0.0;

	vec2u grid = desc.gridSize;
	unsigned count = grid.x * grid.y;
	uint8_t* cache;
	if(count < 2500)
		cache = (uint8_t*)alloca(count * sizeof(uint8_t));
	else
		cache = (uint8_t*)malloc(count * sizeof(uint8_t));
	memset(cache, 0, count * sizeof(uint8_t));

	for(size_t i = 0, cnt = desc.systems.size(); i < cnt; ++i) {
		auto& sys = desc.systems[i];
		for(size_t j = 0, jcnt = sys.hexes.size(); j < jcnt; ++j) {
			vec2u hex = sys.hexes[j];
			if(hex.x < grid.x && hex.y < grid.y) {
				unsigned index = hex.y * grid.x + hex.x;
				cache[index] = 1;
			}
		}
	}

	for(unsigned x = 0; x < grid.x; ++x) {
		for(unsigned y = 0; y < grid.y; ++y) {
			vec2d pctPos = HexGrid<>::getEffectivePosition(vec2u(x, y));
			pctPos.x += 0.75 * 0.5;
			pctPos.y += 0.5;
			pctPos.x /= ((double)grid.x) * 0.75;
			pctPos.y /= (double)grid.y;

			double d = getMatchDistance(pctPos);

			unsigned index = y * grid.x + x;
			if(cache[index])
				dist += d*d;
			else
				dist += 0.5 * (255.0 - d);
		}
	}


	if(count >= 2500)
		free(cache);

	return dist;
}

bool HullDef::checkConnected() {
	HexGrid<bool> connected(active.width, active.height);
	connected.clear(false);

	bool found = false;
	for(unsigned x = 0; x < active.width && !found; ++x) {
		for(unsigned y = 0; y < active.height && !found; ++y) {
			if(active.get(x,y)) {
				fillConnected(connected, vec2u(x,y));
				found = true;
			}
		}
	}

	for(unsigned x = 0; x < active.width; ++x) {
		for(unsigned y = 0; y < active.height; ++y) {
			if(active.get(x,y) && !connected.get(x,y))
				return false;
		}
	}
	return true;
}

void HullDef::fillConnected(HexGrid<bool>& connected, vec2u pos) {
	connected[pos] = true;
	for(unsigned i = 0; i < 6; ++i) {
		vec2u hex = pos;
		if(active.advance(hex, (HexGridAdjacency)i)) {
			if(active[hex] && !connected[hex])
				fillConnected(connected, hex);
		}
	}
}

bool HullDef::isExterior(const vec2u& hex) const {
	if(!exterior.valid(hex))
		return false;
	return exterior.get(hex) & 0x00ffffff;
}

bool HullDef::isExteriorInDirection(const vec2u& hex, unsigned dir) const {
	if(!exterior.valid(hex))
		return false;
	return exterior.get(hex) & (1<<dir);
}

void readHullDefinitions(const std::string& filename, std::vector<HullDef*>& hulls) {
	HullDef* def = 0;
	int x = 0, y = 0;

	DataHandler datahandler;
	datahandler.lineHandler([&](std::string& line) {
		if(!def)
			return;

		if(y >= def->gridSize.height) {
			error("Error: Too many rows for hull '%s'.", def->ident.c_str());
			return;
		}

		x = 0;
		line = trim(line, "\r\n\t");
		unsigned cnt = (unsigned)line.size();
		for(unsigned i = 0; i < cnt; ++i) {
			if(x >= def->gridSize.width) {
				error("Error: Too many characters on row for hull '%s'.", def->ident.c_str());
				break;
			}

			bool& active = def->active.get(x, y);
			int& exterior = def->exterior.get(x, y);

			switch(line[i]) {
				case '-':
					active = false;
					exterior = 0;
					++x;
				break;
				case 'X':
				case 'x':
					active = true;
					exterior = 0;
					++def->activeCount;
					++x;
				break;
				case '#':
					active = true;
					exterior = 0xff;
					++def->activeCount;
					++def->exteriorCount;
					++x;
				break;
				case ' ':
				break;
				default:
					error("Error: Invalid character '%c' on row for hull '%s'.", line[i], def->ident.c_str());
				break;
			}
		}

		++y;
	});

	datahandler("Hull", [&](std::string& value) {
		def = new HullDef();
		def->ident = value;
		def->name = "__"+def->ident+"__";
		hulls.push_back(def);

		x = 0;
		y = 0;
	});

	datahandler("Name", [&](std::string& value) {
		if(!def)
			return;
		def->name = devices.locale.localize(value);
	});

	datahandler("Tags", [&](std::string& value) {
		if(!def)
			return;
		split(value, def->tags, ',', true);
		for(size_t i = 0, cnt = def->tags.size(); i < cnt; ++i)
			def->numTags.insert(getSysTagIndex(def->tags[i], true));
	});

	datahandler("Subsystem", [&](std::string& value) {
		if(!def)
			return;
		def->subsystems.push_back(value);
	});

	datahandler("Background", [&](std::string& value) {
		if(!def)
			return;

		const render::RenderState* bg = &devices.library.getMaterial(value);
		if(!bg) {
			error("(Hull %s): Error: Unknown material %s.", def->ident.c_str(), value.c_str());
			return;
		}

		def->background = bg;
		def->backgroundName = value;
	});

	datahandler("BackgroundScale", [&](std::string& value) {
		if(!def)
			return;
		def->backgroundScale = toNumber<double>(value);
	});

	datahandler("ModelScale", [&](std::string& value) {
		if(!def)
			return;
		def->modelScale = toNumber<double>(value);
	});

	datahandler("Material", [&](std::string& value) {
		if(!def)
			return;

		const render::RenderState* mat = &devices.library.getMaterial(value);
		if(!mat) {
			error("(Hull %s): Error: Unknown material %s.", def->ident.c_str(), value.c_str());
			return;
		}

		def->materialName = value;
		def->material = mat;
	});

	datahandler("Model", [&](std::string& value) {
		if(!def)
			return;

		const render::RenderMesh* mesh = &devices.library.getMesh(value);
		if(!mesh) {
			if(devices.render)
				error("(Hull %s): Error: Unknown model %s.", def->ident.c_str(), value.c_str());
			return;
		}

		def->meshName = value;
		def->mesh = mesh;
	});

	datahandler("Shape", [&](std::string& value) {
		if(!def)
			return;

		std::string fname = devices.mods.resolve(value);
		def->shapeMap = fname+".map.png";
		if(fileExists(def->shapeMap)) {
			def->shape = loadImage(def->shapeMap.c_str());
			def->shapeMapped = true;
		}
		else {
			def->shape = loadImage(fname.c_str());
			def->shapeMapped = false;
		}
	});

	datahandler("GridSize", [&](std::string& value) {
		if(!def)
			return;

		std::vector<std::string> args;
		split(value, args, ',');

		if(args.size() != 2) {
			error("(Hull %s): Error: Invalid grid size specification.", def->ident.c_str());
			return;
		}

		def->gridSize = vec2i(toNumber<int>(args[0]), toNumber<int>(args[1]));

		def->active.resize(def->gridSize);
		def->active.clear(false);

		def->exterior.resize(def->gridSize);
		def->exterior.clear(0);
	});

	datahandler("GridOffset", [&](std::string& value) {
		if(!def)
			return;

		std::vector<std::string> args;
		split(value, args, ',');

		if(args.size() != 4) {
			error("(Hull %s): Error: Invalid grid offset specification.", def->ident.c_str());
			return;
		}

		def->gridOffset = recti(toNumber<int>(args[0]), toNumber<int>(args[1]),
			toNumber<int>(args[2]), toNumber<int>(args[3]));
	});

	datahandler("GuiIcon", [&](std::string& value) {
		if(def) {
			def->guiIcon = devices.library.getSprite(value);
			def->guiIconName = value;
		}
	});

	datahandler("FleetIcon", [&](std::string& value) {
		if(def) {
			def->fleetIcon = devices.library.getSprite(value);
			def->fleetIconName = value;
		}
	});

	datahandler("IconSheet", [&](std::string& value) {
		if(def) {
			def->iconSheet = &devices.library.getSpriteSheet(value);
			def->iconName = value;
		}
	});

	datahandler("IconIndex", [&](std::string& value) {
		if(def)
			def->iconIndex = toNumber<unsigned>(value);
	});

	datahandler("MinSize", [&](std::string& value) {
		if(def)
			def->minSize = toNumber<double>(value);
	});

	datahandler("MaxSize", [&](std::string& value) {
		if(def)
			def->maxSize = toNumber<double>(value);
	});

	datahandler("Special", [&](std::string& value) {
		if(def)
			def->special = toBool(value);
	});

	datahandler.read(filename);
}

bool HullDef::hasTag(const std::string& tag) const {
	auto it = std::find(tags.begin(), tags.end(), tag);
	return it != tags.end();
}

void writeHullDefinitions(const std::string& filename, std::vector<HullDef*>& hulls) {
	std::ofstream file(filename);
	foreach(it, hulls) {
		const HullDef* def = *it;
		file << "Hull: " << def->ident << "\n";
		file << "\tName: " << def->name << "\n";
		file << "\tBackground: " << def->backgroundName << "\n";
		if(def->backgroundScale != 1.0)
			file << "\tBackgroundScale: " << def->backgroundScale << "\n";
		file << "\tMaterial: " << def->materialName << "\n";
		file << "\tModel: " << def->meshName << "\n";
		file << "\tGuiIcon: " << def->guiIconName << "\n";
		if(!def->fleetIconName.empty())
			file << "\tFleetIcon: " << def->fleetIconName << "\n";
		file << "\tIconSheet: " << def->iconName << "\n";
		file << "\tIconIndex: " << def->iconIndex << "\n";
		file << "\n";

		if(!def->tags.empty()) {
			file << "\tTags: ";
			bool first = true;
			for(auto t = def->tags.begin(), tend = def->tags.end(); t != tend; ++t) {
				if(!first)
					file << ", ";
				first = false;
				file << *t;
			}
			file << "\n\n";
		}

		file << "\tGridSize: " << def->gridSize.x << ", " << def->gridSize.y << "\n";
		file << "\tGridOffset: " << def->gridOffset.topLeft.x << "," << def->gridOffset.topLeft.y;
		file << ", " << def->gridOffset.botRight.x << "," << def->gridOffset.botRight.y << "\n";
		file << "\n";

		for(int y = 0; y < def->gridSize.y; ++y) {
			file << "\t";

			for(int x = 0; x < def->gridSize.x; ++x) {
				if(x != 0)
					file << " ";
				if(def->active.get(x, y)) {
					if(def->exterior.get(x, y)) {
						file << "#";
					}
					else {
						file << "X";
					}
				}
				else {
					file << "-";
				}
			}

			file << "\n";
		}

		file << "\n";
	}
}

unsigned Shipset::getHullCount() const {
	return hulls.size();
}

ShipSkin* Shipset::getSkin(const std::string& name) const {
	auto it = skins.find(name);
	if(it == skins.end())
		return nullptr;
	return it->second;
}

Shipset::~Shipset() {
	for(auto it = skins.begin(); it != skins.end(); ++it)
		delete it->second;
}

const HullDef* Shipset::getHull(unsigned index) const {
	if(index >= hulls.size())
		return nullptr;
	return hulls[index];
}

const HullDef* Shipset::getHull(const std::string& ident) const {
	for(auto i = hulls.begin(), end = hulls.end(); i != end; ++i)
		if((*i)->ident == ident)
			return *i;
	return nullptr;
}

bool Shipset::hasHull(const HullDef* hull) const {
	for(auto i = hulls.begin(), end = hulls.end(); i != end; ++i)
		if(*i == hull)
			return true;
	return false;
}

void loadShipset(const std::string& filename) {
	Shipset* set = nullptr;
	ShipSkin* skin = nullptr;

	DataHandler datahandler;

	datahandler("Shipset", [&](std::string& value) {
		if(shipsetIndices.find(value) != shipsetIndices.end())
			error("Duplicate Shipset ID: %s", value.c_str());
		set = new Shipset();
		set->ident = value;
		set->available = true;
		set->id = (unsigned)shipsets.size();
		shipsetIndices[value] = set->id;
		shipsets.push_back(set);
	});

	datahandler("Name", [&](std::string& value) {
		if(set)
			set->name = value;
	});

	datahandler("DLC", [&](std::string& value) {
		if(set)
			set->dlc = value;
	});

	datahandler("Available", [&](std::string& value) {
		if(set)
			set->available = toBool(value, true);
	});

	datahandler("Hull", [&](std::string& value) {
		if(set) {
			auto* hull = getHullDefinition(value);
			if(hull)
				set->hulls.push_back(hull);
			else
				error("Could not find hull %s for shipset %s", value.c_str(), set->ident.c_str());
		}
	});

	datahandler("Skin", [&](std::string& value) {
		if(set) {
			skin = new ShipSkin();
			skin->ident = value;
			set->skins[value] = skin;
		}
	});

	datahandler("Model", [&](std::string& value) {
		if(skin && set) {
			const render::RenderMesh* mesh = &devices.library.getMesh(value);
			if(!mesh) {
				if(devices.render)
					error("(%s Ship Skin %s): Error: Unknown model %s.", set->ident.c_str(), skin->ident.c_str(), value.c_str());
				return;
			}

			skin->mesh = mesh;
		}
	});

	datahandler("Material", [&](std::string& value) {
		if(skin && set) {
			const render::RenderState* mat = &devices.library.getMaterial(value);
			if(!mat) {
				if(devices.render)
					error("(%s Ship Skin %s): Error: Unknown material %s.", set->ident.c_str(), skin->ident.c_str(), value.c_str());
				return;
			}

			skin->material = mat;
		}
	});

	datahandler("Icon", [&](std::string& value) {
		if(skin && set) {
			skin->icon = devices.library.getSprite(value);
		}
	});


	datahandler.read(filename);
}

void initAllShipset() {
	auto* set = new Shipset();
	set->ident = "ALL";
	set->available = false;
	set->id = (unsigned)shipsets.size();

	for(size_t i = 0, cnt = shipsets.size(); i < cnt; ++i) {
		auto* other = shipsets[i];
		if(!other->available)
			continue;
		for(size_t n = 0, ncnt = other->hulls.size(); n < ncnt; ++n)
			set->hulls.push_back(other->hulls[n]);
	}

	shipsetIndices[set->ident] = set->id;
	shipsets.push_back(set);
}

void clearShipsets() {
	shipsets.clear(); shipsets.shrink_to_fit();
	shipsetIndices.clear();
}

unsigned getShipsetCount() {
	return (unsigned)shipsets.size();
}

const Shipset* getShipset(unsigned id) {
	if(id >= (unsigned)shipsets.size())
		return nullptr;
	return shipsets[id];
}

const Shipset* getShipset(const std::string& ident) {
	auto i = shipsetIndices.find(ident);
	if(i == shipsetIndices.end())
		return nullptr;
	return shipsets[i->second];
}
