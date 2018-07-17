#pragma once
#include "node.h"
#include <string>

namespace scene {

struct ParticleSystemDesc;
struct ParticleFlowDesc;
struct Particle;

struct FlowData {
	const ParticleFlowDesc* flow;
	Particle* list;
	float progress;
	bool started;

	FlowData() : flow(0), list(0), progress(1.f), started(false) {}
};

class ParticleSystem : public Node {
	std::vector<FlowData> flows;
public:
	vec3d vel;
	quaterniond rot;
	float scale;
	float age;
	float delay;
	double lastUpdate;

	ParticleSystem(const ParticleSystemDesc* system);
	~ParticleSystem();

	//Stops streaming new particles
	void end();

	bool preRender(render::RenderDriver& driver) override;
	void render(render::RenderDriver& driver) override;

	NodeType getType() const override { return NT_ParticleSystem; };
};

ParticleSystem* playParticleSystem(const ParticleSystemDesc* desc, Node* parent, const vec3d& pos, const quaterniond& rot, const vec3d& vel, float scale = 1.f, float delay = 0.f);
ParticleSystemDesc* loadParticleSystem(const std::string& filename);
ParticleSystemDesc* createDummyParticleSystem();

};
