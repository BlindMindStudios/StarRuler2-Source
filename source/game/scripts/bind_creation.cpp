#include "scripts/binds.h"
#include "obj/lock.h"
#include "obj/object.h"
#include "obj/universe.h"
#include "obj/obj_group.h"
#include "empire.h"
#include "main/references.h"
#include "render/render_state.h"
#include "render/render_mesh.h"
#include "render/lighting.h"
#include "scene/mesh_node.h"
#include "scene/mesh_icon_node.h"
#include "scene/icon_node.h"
#include "scene/animation/anim_node_sync.h"
#include "scene/animation/anim_group.h"
#include "scene/scripted_node.h"
#include "scene/culling_node.h"
#include "util/random.h"
#include "vec2.h"
#include "color.h"
#include "processing.h"
#include "physics/physics_world.h"

namespace scripts {

struct ObjectDesc {
	int type;
	unsigned flags;
	std::string name;
	double radius;
	vec3d position;
	Empire* owner;
	bool delayedCreation;

	ObjectDesc() : type(0), flags(objValid | objUninitialized),
		radius(1.0), owner(0), delayedCreation(false) {
	}

	void reset() {
		type = 0;
		flags = objValid | objUninitialized;
		radius = 1.0;
		owner = 0;
		delayedCreation = false;
		name.clear();
		position = vec3d();
	}
};

void createDesc(void* mem) {
	new(mem) ObjectDesc();
}

bool hintLocks = false;
LockGroup* hintedGroup = 0;
unsigned hintID = 0;

Object* makeObject(ObjectDesc& desc) {
	ScriptObjectType* stype = getScriptObjectType(desc.type);
	if(stype == 0) {
		throwException("Invalid object type to create.");
		return 0;
	}

	LockGroup* group = 0;
	if(hintLocks)
		group = hintedGroup;
	else if(LockGroup* active = getActiveLockGroup())
		group = active;

	Object* obj = Object::create(stype, group);
	obj->flags = desc.flags;
	obj->name = desc.name;
	obj->radius = desc.radius;
	obj->position = desc.position;
	if(desc.owner)
		obj->owner = desc.owner;
	else
		obj->owner = Empire::getDefaultEmpire();

	if(!obj->getFlag(objNoPhysics))
		obj->physItem = devices.physics->registerItem(AABBoxd::fromCircle(obj->position, obj->radius), obj);

	if(desc.delayedCreation)
		obj->setFlag(objStopTicking, true);
	
	obj->owner->registerObject(obj);
	devices.universe->addChild(obj);
	obj->init();

	if(hintLocks) {
		if(!group) {
			hintedGroup = obj->lockGroup;
			hintID = randomi(1,INT_MAX);
			obj->lockHint = hintID;
		}
		else {
			obj->lockHint = hintID;
		}
	}

	obj->grab();
	if(!desc.delayedCreation)
		obj->postInit();
	return obj;
}

ObjectGroup* makeGroup(ObjectDesc& desc, unsigned count) {
	ScriptObjectType* stype = getScriptObjectType(desc.type);
	if(stype == 0) {
		throwException("Invalid object type to create.");
		return 0;
	}

	LockGroup* lockGroup = 0;
	if(hintLocks)
		lockGroup = hintedGroup;

	ObjectGroup* group = new ObjectGroup(count);
	group->grab();

	for(unsigned i = 0; i < count; ++i) {
		Object* obj = Object::create(stype, lockGroup);
		if(hintLocks)
			obj->lockHint = hintID;
		lockGroup = obj->lockGroup;

		obj->name = desc.name;
		obj->radius = desc.radius;
		obj->position = desc.position;
		if(desc.owner)
			obj->owner = desc.owner;
		else
			obj->owner = Empire::getDefaultEmpire();

		if(desc.delayedCreation)
			obj->setFlag(objStopTicking, true);

		obj->group = group;
		group->grab();

		if(!obj->getFlag(objNoPhysics)) {
			obj->physItem = group->getPhysicsItem(i);
			obj->physItem->bound = AABBoxd::fromCircle(obj->position, obj->radius);
			obj->physItem->gridLocation = 0;
			obj->physItem->type = PIT_Object;
			obj->physItem->object = obj;

			obj->grab();
		}

		group->setObject(i, obj);
	}

	group->postInit();
	
	for(unsigned i = 0; i < count; ++i) {
		Object* obj = group->getObject(i);

		obj->owner->registerObject(obj);
		devices.universe->addChild(obj);
		obj->init();

		if(!desc.delayedCreation)
			obj->postInit();
	}

	return group;
}

struct LightDesc {
	Colorf diffuse;
	Colorf specular;
	float att_quadratic;
	vec3f position;
	float radius;

	LightDesc() : att_quadratic(0.f) {
	}
};

void createLight(void* mem) {
	new(mem) LightDesc();
}

void makeLight(LightDesc& desc) {
	auto* light = new render::light::PointLight();

	light->diffuse = desc.diffuse;
	light->specular = desc.specular;
	light->att_quadratic = desc.att_quadratic;
	light->position = desc.position;
	light->radius = desc.radius;

	render::light::registerLight(light);
}

void makeNodeLight(LightDesc& desc, scene::Node* follow) {
	auto* light = new render::light::NodePointLight(follow); //grabbed by constructor

	light->diffuse = desc.diffuse;
	light->specular = desc.specular;
	light->att_quadratic = desc.att_quadratic;
	light->position = desc.position;
	light->radius = desc.radius;

	render::light::registerLight(light);
}

struct MeshDesc {
	const render::RenderState* material;
	const render::RenderMesh* mesh;
	const render::SpriteSheet* iconSheet;
	unsigned iconIndex;
	bool memorable;

	Colorf color;

	MeshDesc() : material(0), mesh(0), iconSheet(0), iconIndex(0), memorable(false) {
	}
};

void createMeshDesc(void* mem) {
	new(mem) MeshDesc();
}

void bindMesh(Object* obj, MeshDesc& desc) {
	if(obj->node) {
		throwException("Binding mesh to object that already has a node.");
		return;
	}

	if(!desc.material || !desc.mesh) {
		throwException("Mesh descriptor data incomplete (missing material/model?).");
		return;
	}

	scene::Node* mesh;
	if(!desc.iconSheet)
		mesh = new scene::MeshNode(desc.mesh, desc.material);
	else
		mesh = new scene::MeshIconNode(desc.mesh, desc.material,
								desc.iconSheet, desc.iconIndex);
	mesh->position = mesh->abs_position = obj->position;
	mesh->scale = mesh->abs_scale = obj->radius;
	mesh->color = desc.color;
	mesh->setObject(obj);
	mesh->animator = scene::NodeSyncAnimator::getSingleton();
	mesh->createPhysics();
	mesh->setFlag(scene::NF_Memorable, desc.memorable);

	auto* player = Empire::getPlayerEmpire();
	if(player)
		mesh->visible = obj->isVisibleTo(player);

	obj->node = mesh;

	mesh->queueReparent(devices.scene);
}

void bindGroupIcon(ObjectGroup* group, const render::SpriteSheet* sheet, unsigned spriteIndex) {
	scene::Node* icon = new scene::IconNode(sheet, spriteIndex);

	icon->position = group->getCenter();
	double radius = group->getOwner()->radius;
	icon->scale = 0.3 * (1.0 + radius) / (3.0 + radius);

	icon->animator = new scene::GroupAnim(group);

	icon->queueReparent(devices.scene);
}

scene::Node* bindCullingNode(Object* obj, const vec3d& pos, double radius) {
	if(obj->node) {
		throwException("Binding culling node to object that already has a node.");
		return nullptr;
	}

	scene::Node* node = new scene::CullingNode(pos, radius);
	node->grab();

	node->setObject(obj);
	obj->node = node;

	node->queueReparent(devices.scene);

	return node;
}

scene::Node* createCullingNode(const vec3d& pos, double radius) {
	scene::Node* node = new scene::CullingNode(pos, radius);
	node->grab();

	node->queueReparent(devices.scene);

	return node;
}

scene::Node* bindNode(Object* obj, const std::string& typeName) {
	scene::Node* node = scene::ScriptedNode::create(typeName);
	if(node) {
		node->grab();
		node->position = obj->position;
		node->scale = obj->radius;
		node->setObject(obj);
		node->animator = scene::NodeSyncAnimator::getSingleton();
		node->createPhysics();

		auto* player = Empire::getPlayerEmpire();
		if(player)
			node->visible = obj->isVisibleTo(player);

		obj->node = node;

		node->queueReparent(devices.scene);
	}
	return node;
}

scene::Node* makeNode(const std::string& typeName) {
	scene::Node* node = scene::ScriptedNode::create(typeName);
	if(node)
		node->queueReparent(devices.scene);
	return node;
}

bool* startLockHint() {
	hintLocks = true;
	return &hintLocks;
}

bool* objLockHint(Object* obj) {
	hintLocks = true;
	hintedGroup = obj->lockGroup;
	if(obj->lockHint)
		hintID = obj->lockHint;
	else
		hintID = randomi(1,INT_MAX);
	return &hintLocks;
}

void endLockHint(bool* mem) {
	hintLocks = false;
	hintedGroup = 0;
}

void RegisterObjectCreation(bool declarations) {
	if(declarations) {
		ClassBind desc("ObjectDesc", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(ObjectDesc));
		ClassBind mdesc("MeshDesc", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(MeshDesc));
		ClassBind ldesc("LightDesc", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(LightDesc));
		ClassBind lhint("LockHint", asOBJ_REF | asOBJ_SCOPED, 0);
		return;
	}

	ClassBind desc("ObjectDesc");
	classdoc(desc, "Descriptor for data to create objects.");

	ClassBind mdesc("MeshDesc");
	classdoc(mdesc, "Descriptor to create a mesh representation for an object.");

	ClassBind ldesc("LightDesc");
	classdoc(ldesc, "Descriptor to create a 3d light instance.");

	ClassBind lhint("LockHint");
	classdoc(lhint, "Scoped structure. Any objects created within the same lock hint will"
		" start in the same lock group, reducing initial variability.");

	//Objects
	desc.addMember("ObjectType type", offsetof(ObjectDesc, type))
		doc("Type of the object to create.");

	desc.addMember("uint flags", offsetof(ObjectDesc, flags))
		doc("Flags the object starts with.");

	desc.addMember("string name", offsetof(ObjectDesc, name))
		doc("Name the object is given.");

	desc.addMember("bool delayedCreation", offsetof(ObjectDesc, delayedCreation))
		doc("If true, delay finalizing the creation until the script can do"
			" some of its own initialization steps. Don't forget to call"
			" finalizeCreation() on the object afterwards.");

	desc.addMember("double radius", offsetof(ObjectDesc, radius))
		doc("Size of the object's bounding sphere.");

	desc.addMember("vec3d position", offsetof(ObjectDesc, position))
		doc("Position the object is spawned at.");

	desc.addMember("Empire@ owner", offsetof(ObjectDesc, owner))
		doc("Initial owner of the object.");

	desc.addMethod("void reset()", asMETHOD(ObjectDesc, reset))
		doc("Reset the descriptor to its initial empty state.");
	desc.addConstructor("void f()", asFUNCTION(createDesc));

	bind("Object@ makeObject(const ObjectDesc& desc)", asFUNCTION(makeObject))
		doc("Create an object based on a description of it.",
			"Object descriptor to use.", "Created object.");

	bind("ObjectGroup@ makeObjectGroup(ObjectDesc& desc, uint count)", asFUNCTION(makeGroup))
		doc("Create an object group based on a description of an object.",
			"Object descriptor to use.", "Number of objects to create in the group.", "Created object.");

	//Meshes
	mdesc.addMember("const Material@ material", offsetof(MeshDesc, material))
		doc("Texture to render on the model.");

	mdesc.addMember("const Model@ model", offsetof(MeshDesc, mesh))
		doc("Model to use to display the object.");

	mdesc.addMember("const SpriteSheet@ iconSheet", offsetof(MeshDesc, iconSheet))
		doc("Spritesheet to render distant icon from, if given.");

	mdesc.addMember("uint iconIndex", offsetof(MeshDesc, iconIndex))
		doc("Icon in the spritesheet to use as a distant icon.");

	mdesc.addMember("Colorf color", offsetof(MeshDesc, color))
		doc("Base color to set for the graphics node.");

	mdesc.addMember("bool memorable", offsetof(MeshDesc, memorable))
		doc("Whether the node represents a memorable object.");

	mdesc.addConstructor("void f()", asFUNCTION(createMeshDesc));

	bind("void bindMesh(Object& obj, MeshDesc& desc)", asFUNCTION(bindMesh))
		doc("Bind a graphical representation to an object in accordance to a mesh descriptor.",
			"Game object to bind to.", "Descriptor for the mesh to display.");
	
	bind("void bindGroupIcon(ObjectGroup& group, const SpriteSheet@ sheet, uint index)", asFUNCTION(bindGroupIcon))
		doc("Binds an icon to represent a ship group.", "", "", "");

	bind("Node@ bindCullingNode(Object& obj, const vec3d&in position, double radius)", asFUNCTION(bindCullingNode))
		doc("Bind a node that can be used for region culling to the object.", "Object to bind to.",
			"Center position for the cullable region.", "Radius of the cullable region.", "Handle to the created node.");

	bind("Node@ createCullingNode(const vec3d&in position, double radius)", asFUNCTION(createCullingNode))
		doc("Create a node that can be used for region culling.",
			"Center position for the cullable region.", "Radius of the cullable region.",
			"Handle to the created node.");

	bind("Node@ bindNode(Object& obj, const string &in type)", asFUNCTION(bindNode))
		doc("Bind a custom graphical node to an object.", "Object to bind to.", "Type of script node to create.", "Handle to the created node.");

	bind("Node@ createNode(const string &in type)", asFUNCTION(makeNode));

	//Lights
	ldesc.addMember("Colorf diffuse", offsetof(LightDesc, diffuse))
		doc("Diffuse light color.");

	ldesc.addMember("Colorf specular", offsetof(LightDesc, specular))
		doc("Specular light color.");

	ldesc.addMember("float att_quadratic", offsetof(LightDesc, att_quadratic))
		doc("Quadratic attenuation.");

	ldesc.addMember("float radius", offsetof(LightDesc, radius))
		doc("Radius associated with the light.");

	ldesc.addMember("vec3f position", offsetof(LightDesc, position))
		doc("Position of the light in 3d space.");

	ldesc.addConstructor("void f()", asFUNCTION(createLight));

	bind("void makeLight(LightDesc& desc)", asFUNCTION(makeLight))
		doc("Create a light based on a description of it.",
			"Light descriptor to use.");
	bind("void makeLight(LightDesc& desc, Node& node)", asFUNCTION(makeNodeLight))
		doc("Create a light following a particular scene node.",
				"Light descriptor to use.", "Node to follow with the light.");

	//Locking hints
	lhint.addFactory("LockHint@ f()", asFUNCTION(startLockHint));
	lhint.addFactory("LockHint@ f(Object& obj)", asFUNCTION(objLockHint));
	lhint.addExternBehaviour(asBEHAVE_RELEASE, "void f()", asFUNCTION(endLockHint));
}

};
