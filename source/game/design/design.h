#pragma once
#include "design/subsystem.h"
#include "design/hull.h"
#include "util/refcount.h"
#include "image.h"
#include <unordered_set>

class SaveFile;

namespace net {
	struct Message;
};

struct DesignClass {
	unsigned id;
	std::string name;
	std::vector<const Design*> designs;
};

struct DesignError {
	bool fatal;
	std::string text;
	const Subsystem* subsys;
	const SubsystemDef::ModuleDesc* module;
	vec2i hex;

	DesignError(bool Fatal, std::string Text,
		const Subsystem* Subsys = 0, const SubsystemDef::ModuleDesc* Module = 0,
		vec2i Hex = vec2i(-1, -1))
		: fatal(Fatal), text(Text), subsys(Subsys), module(Module), hex(Hex) {
	}
};

class Empire;
class Design : public AtomicRefCounted {
public:
	//Metadata
	const HullDef* hull;
	std::string name;
	double size;
	double hexSize;
	unsigned interiorHexes;
	unsigned exteriorHexes;
	unsigned stateCount;
	unsigned effectorStateCount;
	unsigned effectorCount;
	unsigned dataCount;
	bool initialized;
	double totalHP;
	double quadrantTotalHP[4];
	mutable bool outdated;
	Color color;
	Color dullColor;

	//Errors
	std::vector<DesignError> errors;
	bool hasFatalErrors() const;
	bool hasTag(const std::string& tag) const;

	std::unordered_set<int> numTags;
	bool hasTag(int index) const;

	//Subsystems
	std::vector<Subsystem> subsystems;
	std::vector<Subsystem*> damageOrder;
	std::vector<SubsystemDef::ShipModifier> modifiers;
	HexGrid<int> grid;
	HexGrid<int> hexIndex;
	HexGrid<int> hexStatusIndex;
	std::vector<vec2u> hexes;
	std::unordered_set<uint64_t> errorHexes;
	unsigned usedHexCount;
	float* shipVariables;
	vec2u cropMin;
	vec2u cropMax;

	//Ownership and usage data
	mutable unsigned id;
	mutable Empire* owner;
	mutable bool used;
	mutable bool obsolete;
	mutable int revision;
	mutable threads::atomic_int built;
	mutable threads::atomic_int active;
	mutable render::Sprite icon;
	mutable render::Sprite distantIcon;
	mutable render::Sprite fleetIcon;
	bool forceHull;

	mutable net::Message* data;
	mutable asIScriptObject* clientData;
	mutable asIScriptObject* serverData;

	//Manual updates bump revision numbers and
	//use these 'horizontal' lists.
	mutable heldPointer<const Design> newer;
	const Design* newest() const;
	const Design* next() const;

	//Automatic updates do not bump revisions and
	//use this 'vertical' list of designs.
	mutable heldPointer<const Design> original;
	mutable heldPointer<const Design> updated;
	const Design* mostUpdated() const;
	const Design* base() const;

	mutable DesignClass* cls;

	//Designs are created via descriptors
	struct Descriptor {
		struct System {
			const SubsystemDef* type;
			vec3d direction;
			std::vector<vec2u> hexes;
			std::vector<const SubsystemDef::ModuleDesc*> modules;

			System() : type(nullptr), direction(vec3d::front()) {
			}
		};

		Empire* owner;
		const HullDef* hull;
		std::string name;
		std::string className;
		std::string hullName;
		double size;
		vec2u gridSize;
		std::vector<Descriptor::System> systems;
		std::vector<const SubsystemDef*> appliedSystems;
		bool staticHull;
		bool forceHull;
		asIScriptObject* settings;

		Descriptor() : owner(0), hull(0), size(1), staticHull(false), forceHull(false), gridSize(1,1), settings(nullptr) {
		}

		~Descriptor() {
			if(hull)
				hull->drop();
			if(settings)
				settings->Release();
		}
	};

	Design(const Design::Descriptor& desc);
	Design(net::Message& msg);
	Design(SaveFile& file);
	Design();
	~Design();

	void init(net::Message& msg);
	void init(const Design::Descriptor& desc);
	void write(net::Message& msg) const;
	void save(SaveFile& file) const;
	void toDescriptor(Design::Descriptor& desc) const;
	void makeDistanceMap(Image& img, vec2i pos, vec2i size) const;
	void bindData();
	void buildDamageOrder();

	unsigned getQuadrant(const vec2u& pos) const;

	void writeData(net::Message& msg) const;
	void initData(net::Message& msg);
};
