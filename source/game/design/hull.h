#pragma once
#include <vector>
#include "util/hex_grid.h"
#include "util/refcount.h"
#include "vec2.h"
#include "rect.h"
#include "render/render_state.h"
#include "render/render_mesh.h"
#include "render/spritesheet.h"
#include <unordered_set>
#include <unordered_map>

class Shipset;
class HullDef : public AtomicRefCounted {
public:
	static const unsigned flagExteriorPass = 1 << 31;
	static const unsigned flagExteriorFaux = 1 << 30;

	unsigned id;
	std::string ident;
	std::string name;
	std::string backgroundName;
	std::string meshName;
	std::string materialName;
	std::string iconName;
	std::string guiIconName;
	std::string fleetIconName;
	std::vector<std::string> tags;
	std::vector<std::string> subsystems;
	std::unordered_set<int> numTags;
	const render::RenderState* background;
	const render::RenderState* material;
	const render::RenderMesh* mesh;
	const render::SpriteSheet* iconSheet;
	render::Sprite guiIcon;
	render::Sprite fleetIcon;
	unsigned iconIndex;
	vec2i gridSize;
	recti gridOffset;
	double backgroundScale;
	double modelScale;
	HexGrid<bool> active;
	HexGrid<int> exterior;
	unsigned activeCount;
	unsigned exteriorCount;
	double minSize;
	double maxSize;
	mutable heldPointer<const HullDef> baseHull;
	Image* shape;
	std::string shapeMap;
	bool shapeMapped;
	bool special;

	HullDef();
	HullDef(const HullDef& other);

	std::vector<vec3d> impacts;
	bool calculateImpacts();
	vec3d getImpact(const vec3d& offset, double radius, bool constant = false) const;
	vec3d getClosestImpact(const vec3d& offset) const;

	void calculateDist();
	void calculateDist(vec2u pos, int dist);
	void calculateExterior();
	void calculateExterior(vec2u pos, unsigned direction);

	bool checkConnected();
	void fillConnected(HexGrid<bool>& connected, vec2u hex);

	double getMatchDistance(const vec2d& pos) const;
	double getMatchDistance(void* desc) const;

	bool isExterior(const vec2u& hex) const;
	bool isExteriorInDirection(const vec2u& hex, unsigned dir) const;

	bool hasTag(const std::string& tag) const;
};

struct ShipSkin {
	std::string ident;
	const render::RenderState* material;
	const render::RenderMesh* mesh;
	render::Sprite icon;
};

class Shipset : public AtomicRefCounted {
public:
	unsigned id;
	std::vector<const HullDef*> hulls;
	bool available;
	std::string ident, name;
	std::string dlc;

	std::unordered_map<std::string,ShipSkin*> skins;

	~Shipset();
	ShipSkin* getSkin(const std::string& name) const;

	bool hasHull(const HullDef* hull) const;

	unsigned getHullCount() const;
	const HullDef* getHull(unsigned index) const;
	const HullDef* getHull(const std::string& ident) const;
};

void loadHullDefinitions(const std::string& filename);
void clearHullDefinitions();

void readHullDefinitions(const std::string& filename, std::vector<HullDef*>& hulls);
void writeHullDefinitions(const std::string& filename, std::vector<HullDef*>& hulls);

unsigned getHullCount();
const HullDef* getHullDefinition(unsigned id);
const HullDef* getHullDefinition(const std::string& ident);

void computeHulls(unsigned amount);
bool isFinishedComputingHulls();

void loadShipset(const std::string& filename);
void initAllShipset();
void clearShipsets();

unsigned getShipsetCount();
const Shipset* getShipset(unsigned id);
const Shipset* getShipset(const std::string& ident);
