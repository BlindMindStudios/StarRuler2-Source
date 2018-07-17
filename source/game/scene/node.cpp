#include "scene/node.h"
#include "compat/misc.h"
#include "threads.h"
#include "main/references.h"
#include "main/logging.h"
#include "render/driver.h"
#include "obj/object.h"
#include "empire.h"
#include "physics/physics_world.h"
#include "aabbox.h"
#include "memory/AllocOnlyPool.h"

#include <map>
#include <set>

extern double frameTime_s;
extern unsigned frameNumber;
Colorf fallbackNodeColor;
Object* fallbackNodeObject;

//Produce a vaguely unique value per node, consistent per node
void shader_unique(float* values,unsigned short,void*) {
	if(auto* node = scene::renderingNode)
		values[0] = (float)(((node - (scene::Node*)0) >> 4) & 0xff) / 255.f;
	else
		values[0] = 0.5f;
}

void shader_node_color(float* colors,unsigned short,void*) {
	if(auto* node = scene::renderingNode)
		*(Colorf*)colors = node->color;
	else
		*(Colorf*)colors = fallbackNodeColor;
}

void shader_node_distance(float* distance,unsigned short,void*) {
	if(auto* node = scene::renderingNode)
		*distance = (float)node->sortDistance;
	else
		*distance = 0.f;
}

void shader_node_scale(float* scale,unsigned short,void*) {
	if(auto* node = scene::renderingNode)
		*scale = (float)node->abs_scale;
	else
		*scale = 1.f;
}

void shader_node_selected(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj && obj->getFlag(objSelected))
			*(float*)value = 1.f;
		else
			*(float*)value = 0.f;
	}
	else
		*(float*)value = 0.f;
}

void shader_obj_velocity(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj)
			*(float*)value = (obj->velocity + obj->acceleration * (frameTime_s - obj->lastTick)).getLength();
		else
			*(float*)value = 0.f;
	}
	else if(fallbackNodeObject) {
		*(float*)value = (fallbackNodeObject->velocity + fallbackNodeObject->acceleration * (frameTime_s - fallbackNodeObject->lastTick)).getLength();
	}
	else
		*(float*)value = 0.f;
}

void shader_obj_position(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj) {
			value[0] = obj->position.x;
			value[1] = obj->position.y;
			value[2] = obj->position.z;
		}
		else {
			value[0] = 0.f;
			value[1] = 0.f;
			value[2] = 0.f;
		}
	}
	else if(fallbackNodeObject) {
		value[0] = fallbackNodeObject->position.x;
		value[1] = fallbackNodeObject->position.y;
		value[2] = fallbackNodeObject->position.z;
	}
	else {
		value[0] = 0.f;
		value[1] = 0.f;
		value[2] = 0.f;
	}
}

void shader_obj_rotation(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj) {
			value[0] = obj->rotation.xyz.x;
			value[1] = obj->rotation.xyz.y;
			value[2] = obj->rotation.xyz.z;
			value[3] = obj->rotation.w;
		}
		else {
			value[0] = 0.f;
			value[1] = 0.f;
			value[2] = 0.f;
			value[3] = 1.f;
		}
	}
	else if(fallbackNodeObject) {
		value[0] = fallbackNodeObject->rotation.xyz.x;
		value[1] = fallbackNodeObject->rotation.xyz.y;
		value[2] = fallbackNodeObject->rotation.xyz.z;
		value[3] = fallbackNodeObject->rotation.w;
	}
	else {
		value[0] = 0.f;
		value[1] = 0.f;
		value[2] = 0.f;
		value[3] = 1.f;
	}
}

void shader_node_position(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		value[0] = node->abs_position.x;
		value[1] = node->abs_position.y;
		value[2] = node->abs_position.z;
	}
	else if(fallbackNodeObject) {
		value[0] = fallbackNodeObject->position.x;
		value[1] = fallbackNodeObject->position.y;
		value[2] = fallbackNodeObject->position.z;
	}
	else {
		value[0] = 0.f;
		value[1] = 0.f;
		value[2] = 0.f;
	}
}

void shader_node_rotation(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		value[0] = node->abs_rotation.xyz.x;
		value[1] = node->abs_rotation.xyz.y;
		value[2] = node->abs_rotation.xyz.z;
		value[3] = node->abs_rotation.w;
	}
	else if(fallbackNodeObject) {
		value[0] = fallbackNodeObject->rotation.xyz.x;
		value[1] = fallbackNodeObject->rotation.xyz.y;
		value[2] = fallbackNodeObject->rotation.xyz.z;
		value[3] = fallbackNodeObject->rotation.w;
	}
	else {
		value[0] = 0.f;
		value[1] = 0.f;
		value[2] = 0.f;
		value[3] = 1.f;
	}
}

void shader_obj_acceleration(float* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj)
			*(float*)value = obj->acceleration.getLength();
		else
			*(float*)value = 0.f;
	}
	else if(fallbackNodeObject) {
		*(float*)value = fallbackNodeObject->acceleration.getLength();
	}
	else
		*(float*)value = 0.f;
}

void shader_emp_flag(int* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj) {
			Empire* owner = obj->owner;
			if(owner)
				*(int*)value = (int)owner->flagID;
			else
				*(int*)value = 0;
		}
		else {
			*(int*)value = 0;
		}
	}
	else if(fallbackNodeObject) {
		Empire* owner = fallbackNodeObject->owner;
		if(owner)
			*(int*)value = (int)owner->flagID;
		else
			*(int*)value = 0;
	}
	else
		*(int*)value = 0;
}

void shader_obj_id(int* value,unsigned short,void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;
		if(obj)
			*(int*)value = obj->id;
		else
			*(int*)value = 0;
	}
	else if(fallbackNodeObject) {
		*(int*)value = fallbackNodeObject->id;
	}
	else
		*(int*)value = 0;
}

namespace scene {

const char* typeNames[NT_ScriptBase] = {
	"Misc Node",
	"Culling Node",
	"Particle System",
	"Mesh Node",
	"Mesh+Icon Node"
};
extern const char* getScriptNodeName(unsigned id);

#ifdef PROFILE_ANIMATION
volatile double nodeAnimTimes[32] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
threads::atomic_int nodeAnimCounts[32];

void dumpAnimationProfile() {
	for(unsigned i = 0; i < 32; ++i) {
		int count = nodeAnimCounts[i];
		double total = nodeAnimTimes[i];
		if(count == 0)
			continue;
		nodeAnimTimes[i] = 0;
		nodeAnimCounts[i] = 0;

		const char* name = nullptr;
		if(i < NT_ScriptBase)
			name = typeNames[i];
		else
			name = getScriptNodeName(i - NT_ScriptBase);
		print("%s: %.1lf ms (%.1lf us per)", name, total * 1.0e3, total * 1.0e6 / double(count));
	}
}
#endif

const char* Node::getName() const {
	unsigned typeIndex = (unsigned)getType();
	if(typeIndex < NT_ScriptBase)
		return typeNames[typeIndex];
	else
		return getScriptNodeName(typeIndex - NT_ScriptBase);
}

Node* renderingNode;

threads::Mutex nodeEventLock;
std::vector<NodeEvent*>* pushQueue = new std::vector<NodeEvent*>, *activeQueue = new std::vector<NodeEvent*>;
memory::AllocOnlyRegion<threads::Mutex> nodeEventMemory(2048);

void* NodeEvent::operator new(size_t bytes) {
	return nodeEventMemory.alloc(bytes);
}

void NodeEvent::operator delete(void* p) {
	nodeEventMemory.dealloc((unsigned char*)p);
}

void queueNodeEvent(NodeEvent* evt) {
	nodeEventLock.lock();
	pushQueue->push_back(evt);
	nodeEventLock.release();
}

void clearNodeEvents() {
	nodeEventLock.lock();

	for(auto i = activeQueue->begin(), end = activeQueue->end(); i != end; ++i)
		delete *i;
	for(auto i = pushQueue->begin(), end = pushQueue->end(); i != end; ++i)
		delete *i;
	
	activeQueue->clear();
	pushQueue->clear();

	nodeEventLock.release();
}

void processNodeEvents() {
	if(pushQueue->empty())
		return;

	nodeEventLock.lock();
	std::swap(pushQueue,activeQueue);
	nodeEventLock.release();

	for(auto i = activeQueue->begin(), end = activeQueue->end(); i != end; ++i) {
		NodeEvent* evt = *i;
		evt->process();
		delete evt;
	}

	activeQueue->clear();
}

NodeEvent::NodeEvent(Node* node) : node(node) {
	if(node)
		node->grab();
}

NodeEvent::~NodeEvent() {
	if(node)
		node->drop();
}

void Node::markForDeletion() {
	//TODO: This might be unsafe if the bool is packed alongside another member
	queuedDelete = true;
}

class ReparentNode : public NodeEvent {
	heldPointer<Node> parent;
public:
	ReparentNode(Node* reparent, Node* toParent) : NodeEvent(reparent), parent(toParent) {
	}

	void process() override {
		node->setParent(parent);
		node->rebuildTransformation();
		node->sortDistance = node->abs_position.distanceTo(devices.render->cam_pos);
	}
};

void Node::queueReparent(Node* newParent) {
	if(newParent == 0)
		newParent = devices.scene;
	queueNodeEvent(new ReparentNode(this, newParent));
}

class ReparentToObject : public NodeEvent {
public:
	heldPointer<Object> object;
	ReparentToObject(Node* reparent, Object* obj) : NodeEvent(reparent), object(obj) {
	}

	void process() override {
		//The object can't be destroyed here, so the node should stay valid too
		//TODO: Check that assumption in all cases. (True in practice now because
		//region nodes are never destroyed in game)
		Node* other = object->node;
		if(other) {
			node->setParent(other);
			node->rebuildTransformation();
			node->sortDistance = node->abs_position.distanceTo(devices.render->cam_pos);
		}
	}
};

void Node::hintParentObject(Object* obj, bool checkDistance) {
	if(!obj || !obj->node) {
		//We shouldn't be parented to anything
		if(parent && parent != devices.scene)
			queueReparent(nullptr);
	}
	else {
		//Check that we're completely inside this object
		double maxDist = obj->radius - abs_scale;
		if(!checkDistance || abs_position.distanceToSQ(obj->position) < maxDist * maxDist) {
			//Accessing the random object's node pointer is
			//not technically safe here, but because we're only checking
			//for equality it won't break.
			if(parent != obj->node)
				queueNodeEvent(new ReparentToObject(this, obj));
		}
		else {
			//We're too big to be in this node, leave
			if(parent && parent != devices.scene)
				queueReparent(nullptr);
		}
	}
	if(obj)
		obj->drop();
}

bool Node::getFlag(NodeFlag flag) const {
	return (flags & flag) != 0;
}

void Node::setFlag(NodeFlag flag, bool val) {
	if(val)
		flags |= flag;
	else
		flags &= ~flag;
}

bool Node::isChild(Node* check) {
	foreach(child, children) {
		if(*child == check)
			return true;
	}

	return false;
}

void Node::addChild(Node* child) {
	child->grab();
	children.push_back(child);
	child->setFlag(NF_Dirty, true);
	child->parent = this;
}

void Node::removeChild(Node* check) {
	foreach(child, children) {
		if(*child == check) {
			children.erase(child);
			check->parent = 0;
			check->drop();
			return;
		}
	}
}

void Node::setParent(Node* newParent) {
	if(newParent == parent)
		return;
	Node* oldParent = parent;
	if(newParent)
		newParent->addChild(this);
	if(oldParent)
		oldParent->removeChild(this);
	parent = newParent;
	if(newParent && oldParent)
		animate();
}

void Node::destroyTree() {
	foreach(child, children)
		(*child)->destroyTree();
	children.clear();
	parent = 0;
}

void Node::destroy() {
	if(physics) {
		devices.nodePhysics->unregisterItem(*physics);
		physics = 0;
		drop();
	}

	if(obj) {
		obj->drop();
		obj = 0;
	}

	animator = 0;
	parent = 0;
}

void Node::flagDirty() {
	if(!getFlag(NF_Dirty)) {
		setFlag(NF_Dirty, true);

		foreach(child, children)
			(*child)->flagDirty();
	}
}

bool nodeSort(scene::Node* a, scene::Node* b) {
	return *a < *b;
}

void Node::animate() {
#ifdef PROFILE_ANIMATION
	double start = devices.driver->getAccurateTime();
#endif
	if(animator)
		animator->animate(this);
	
	if(flags & NF_Dirty)
		rebuildTransformation();

	if(flags & NF_AnimOnlyVisible)
		frameVisible = visible && preRender(*devices.render);
	else
		frameVisible = preRender(*devices.render) && visible;
#ifdef PROFILE_ANIMATION
	double end = devices.driver->getAccurateTime();
	double duration = end - start;
	auto type = getType();
	nodeAnimCounts[type]++;
	volatile double& curTime = nodeAnimTimes[type];
	while(true) {
		double prev = curTime;
		double result = prev + duration;
		if(threads::compare_and_swap((long long*)&curTime, *(long long*)&prev, *(long long*)&result) == *(long long*)&prev)
			break;
	}
#endif

	if(frameVisible) {
		foreach(child, children)
			(*child)->animate();
		if(children.size() > 1)
			std::sort(children.begin(), children.end(), nodeSort);
	}
}

void Node::sortChildren() {
	if(children.size() > 1)
		std::sort(children.begin(), children.end(), nodeSort);
}

void Node::rebuildTransformation() {
	setFlag(NF_Dirty, false);

	if(parent && !getFlag(NF_Independent)) {
		if(getFlag(NF_ParentScale)) {
			abs_position = parent->abs_position + (parent->abs_rotation * position) * parent->abs_scale;
			abs_rotation = parent->abs_rotation * rotation;
			abs_scale = parent->abs_scale * scale;
		}
		else {
			abs_position = parent->abs_position + position;
			abs_rotation = rotation;
			abs_scale = scale;
		}
	}
	else {
		abs_position = position;
		abs_rotation = rotation;
		abs_scale = scale;
	}

	if(!getFlag(NF_NoMatrix))
		abs_rotation.toTransform(transformation, abs_position, abs_scale);

	if(physics) {
		auto bbox = AABBoxd::fromCircle(abs_position, abs_scale);
		if(physics->bound != bbox)
			devices.nodePhysics->updateItem(*physics, bbox);
	}
}

Node::Node() : flags(NF_Dirty | NF_Independent), lastUpdate(frameTime_s), sortDistance(0), scale(1), abs_scale(1), distanceCutoff(1.0e8),
	obj(0), physics(0), visible(true), frameVisible(true), queuedDelete(false), remembered(false) {}

Node::~Node() {
	destroy();
}

void Node::setObject(Object* Obj) {
	if(Obj == obj)
		return;
	if(Obj)
		Obj->grab();
	if(obj)
		obj->drop();
	obj = Obj;
}

Object* Node::getObject() {
	if(obj)
		obj->grab();
	return obj;
}

void Node::createPhysics() {
	if(physics || !devices.nodePhysics)
		return;

	rebuildTransformation();
	grab();
	physics = devices.nodePhysics->registerItem(AABBoxd::fromCircle(abs_position, abs_scale), this);
}

bool Node::operator<(const scene::Node& other) const {
	if(frameVisible && other.frameVisible) {
		bool alpha = getFlag(NF_Transparent);
		if(alpha != other.getFlag(NF_Transparent)) {
			if(alpha)
				return false;
			else
				return true;
		}
		else if(alpha) {
			return sortDistance > other.sortDistance;
		}
		else {
			return sortDistance < other.sortDistance;
		}
	}
	else if(frameVisible) {
		return true;
	}
	else {
		return false;
	}
}

void Node::_render(render::RenderDriver& driver) {
	renderingNode = this;
	render(driver);

	if(auto cnt = children.size()) {
		for(decltype(cnt) i = 0; i < cnt;) {
			scene::Node* child = children[i];
			if(!child->queuedDelete) {
				++i;
				if(child->frameVisible)
					child->_render(driver);
			}
			else {
				child->destroy();
				child->drop();

				children[i] = children[cnt-1];
				--cnt;
			}
		}

		if(cnt != children.size())
			children.resize(cnt);
	}
}

};
