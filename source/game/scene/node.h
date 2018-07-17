#pragma once
#include "vec3.h"
#include "matrix.h"
#include "quaternion.h"
#include "util/refcount.h"
#include "color.h"
#include "animation/animator.h"
#include <vector>

class Object;
struct PhysicsItem;

namespace render {
	class RenderDriver;
};

namespace scene {

enum NodeFlag {
	NF_Dirty = 0x1,
	NF_Transparent = 0x2,
	NF_ParentScale = 0x4,
	NF_FixedSize = 0x8,
	NF_NoCulling = 0x10,
	NF_Independent = 0x20,
	NF_AnimOnlyVisible = 0x40,
	NF_Memorable = 0x80,
	NF_NoMatrix = 0x100,
	NF_CustomColor = 0x200,
};

extern Node* renderingNode;

class NodeEvent {
public:
	Node* node;

	NodeEvent(Node* node);
	virtual void process() = 0;
	virtual ~NodeEvent();

	void* operator new(size_t bytes);
	void operator delete(void* p);
};

void queueNodeEvent(NodeEvent* evt);
void processNodeEvents();
void clearNodeEvents();

//#define PROFILE_ANIMATION
#ifdef PROFILE_ANIMATION
void dumpAnimationProfile();
#endif

enum NodeType {
	NT_System,
	NT_Culling,
	NT_ParticleSystem,
	NT_MeshNode,
	NT_MeshIconNode,
	NT_ScriptBase,
};

class Node : public AtomicRefCounted {
protected:
	int flags;
public:
	bool visible, frameVisible, queuedDelete, remembered;
	double lastUpdate, sortDistance;
	Matrix transformation;
	vec3d position, abs_position;
	double scale, abs_scale;
	quaterniond rotation, abs_rotation;
	double distanceCutoff;
	heldPointer<Animator> animator;
	Colorf color;
	Object* obj;
	PhysicsItem* physics;

	void setObject(Object* Obj);
	Object* getObject();

	std::vector<Node*> children;
	heldPointer<Node> parent;

	bool getFlag(NodeFlag flag) const;
	void setFlag(NodeFlag flag, bool val);
	void flagDirty();

	virtual NodeType getType() const { return NT_System; };
	const char* getName() const;

	void markForDeletion();
	virtual void destroy();

	void queueReparent(Node* newParent);
	void hintParentObject(Object* obj, bool checkDistance = true);

	void rebuildTransformation();

	bool isChild(Node* child);
	void addChild(Node* child);
	void removeChild(Node* child);
	void setParent(Node* parent);
	void destroyTree();
	void animate();
	//Used to sort of nodes of the root node, as that node is not responsible for animating its children
	void sortChildren();

	void createPhysics();

	virtual bool preRender(render::RenderDriver& driver) { return true; }
	virtual void render(render::RenderDriver& driver) { }
	void _render(render::RenderDriver& driver);

	bool operator<(const scene::Node& other) const;

	Node();
	virtual ~Node();
};
	
};
