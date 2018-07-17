#pragma once
#include <vector>
#include "vec3.h"
#include "color.h"
#include "scene/node.h"

namespace render {
namespace light {

struct LightSource {
	//Returns a distance that can be used in comparative distance checks (not actual distance)
	virtual float distanceFrom(const vec3f& pos) = 0;

	//Enables the light, and advance <lightIndex>
	virtual void enable(unsigned& lightIndex, const vec3f& offset) = 0;

	//Get data from light
	virtual vec3f getPosition() const = 0;
	virtual float getRadius() const = 0;

	virtual ~LightSource() {}
};

struct PointLight : public LightSource {
	vec3f position;
	float radius;

	float att_constant, att_linear, att_quadratic;
	Colorf diffuse, specular;

	float distanceFrom(const vec3f& pos);

	void enable(unsigned& lightIndex, const vec3f& offset);
	vec3f getPosition() const;
	float getRadius() const;
	PointLight();
};

struct NodePointLight : public PointLight {
	scene::Node* followNode;

	void enable(unsigned& lightIndex, const vec3f& offset);
	vec3f getPosition() const;
	float getRadius() const;
	NodePointLight(scene::Node* follow);
	~NodePointLight();
};

void registerLight(LightSource* light);
void unregisterLight(LightSource* light);
//Removes all registered lights
void destroyLights();
//Returns lighting to its default state (a single white light at 0,0,0)
void resetLights();

//Finds up to <maximum> nearest lights to <from>
unsigned findNearestLights(const vec3f& from, LightSource** lights, unsigned maximum);

};
};
