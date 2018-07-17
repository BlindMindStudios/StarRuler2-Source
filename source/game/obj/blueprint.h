#pragma once
#include "design/effector.h"
#include "design/design.h"
#include "util/basic_type.h"
#include "util/hex_grid.h"

class SaveMessage;

enum HexFlags {
	HF_Active = 0x1,
	HF_Destroyed = 0x2,
	HF_NoHP = 0x4,
	HF_Gone = 0x8,
	HF_NoRepair = 0x10,
};

enum DamageFlags {
	DF_DestroyedObject = 0x40000000,
};

namespace net {
	struct Message;
};

class CScriptAny;
class Blueprint {
public:
	struct HexStatus {
		unsigned char flags;
		unsigned char hp;
	};

	struct SysStatus {
		unsigned short workingHexes;
		EffectStatus status;
	};

	const Design* design;
	HexStatus* hexes;
	SysStatus* subsystems;
	BasicType* states;
	double* effectorStates;
	EffectorTarget* effectorTargets;
	double currentHP;
	double quadrantHP[4];
	float removedHP;
	double shipEffectiveness;
	unsigned statusID;
	unsigned short destroyedHexes;
	bool designChanged;
	bool hpDelta;
	bool holdFire;
	float hpFactor;
	vec2i repairingHex;
	CScriptAny** data;

	HexStatus* getHexStatus(unsigned index);
	HexStatus* getHexStatus(unsigned x, unsigned y);
	SysStatus* getSysStatus(unsigned index);
	SysStatus* getSysStatus(unsigned x, unsigned y);
	CScriptAny* getHookData(unsigned index);

	Blueprint();

	void destroy(Object* obj);
	void preClear();
	~Blueprint();

	void init(Object* obj);
	float think(Object* obj, double time);
	void ownerChange(Object* obj, Empire* prevEmpire, Empire* newEmpire);

	bool hasTagActive(int index);
	double getTagEfficiency(int index, bool ignoreInactive = true);
	double getEfficiencySum(int variable, int tag = -1, bool ignoreInactive = true);
	double getEfficiencyFactor(int variable, int tag = -1, bool ignoreInactive = true);

	bool doesAutoTarget(Object* obj, Object* target);
	bool canTarget(Object* obj, Object* target);

	void target(Object* obj, Object* target, TargetFlags flags = TF_Target);
	void target(Object* obj, unsigned efftrIndex, Object* target, TargetFlags flags = TF_Target);
	void target(Object* obj, const Subsystem* sys, Object* target, TargetFlags flags = TF_Target);
	void clearTracking(Object* obj);
	Object* getCombatTarget();

	vec3d getOptimalFacing(int sysVariable, int tag = -1, bool ignoreInactive = true);

	void damage(Object* obj, DamageEvent& evt, const vec2u& hex);
	void damage_internal(Object* obj, DamageEvent& evt, const vec2u& hex);

	void damage(Object* obj, DamageEvent& evt, const vec2u& hex, HexGridAdjacency dir, bool runGlobal);
	void damage(Object* obj, DamageEvent& evt, const vec2u& hex, bool runGlobal);
	bool globalDamage(Object* obj, DamageEvent& evt);

	void damage(Object* obj, DamageEvent& evt, const vec2d& direction);
	void damage(Object* obj, DamageEvent& evt, double position, const vec2d& direction);
	void damage(Object* obj, DamageEvent& evt, const vec2u& position, const vec2d& endPoint);
	void create(Object* obj, const Design* design);
	void start(Object* obj, bool fromRetrofit = false);
	void retrofit(Object* obj, const Design* design);

	double repair(Object* obj, double amount);
	double repair(Object* obj, const vec2u& hex, double amount);

	void sendDetails(Object* obj, net::Message& msg);
	void recvDetails(Object* obj, net::Message& msg);

	bool sendDelta(Object* obj, net::Message& msg);
	void recvDelta(Object* obj, net::Message& msg);

	void save(Object* obj, SaveMessage& file);
	void load(Object* obj, SaveMessage& file);
};
