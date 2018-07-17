#include "lighting.h"
#include "compat/gl.h"
#include <set>

namespace render {
namespace light {

PointLight::PointLight() : att_constant(1), att_linear(0), att_quadratic(0) {
}

float PointLight::distanceFrom(const vec3f& pos) {
	return (float)pos.distanceToSQ(position);
}

void setPosition(const vec3f& pos);
void setPosition(const vec3d& pos);

void PointLight::enable(unsigned& lightIndex, const vec3f& offset) {
	GLenum LIGHT = GL_LIGHT0 + lightIndex; ++lightIndex;
	glEnable(LIGHT);
	glLightfv(LIGHT,GL_DIFFUSE,(GLfloat*)&diffuse);
	glLightfv(LIGHT,GL_SPECULAR,(GLfloat*)&specular);

	glLightf(LIGHT,GL_QUADRATIC_ATTENUATION,att_quadratic);
	
	float pos[4] = {position.x + offset.x, position.y + offset.y, position.z + offset.z, 1.f};
	glLightfv(LIGHT,GL_POSITION,(GLfloat*)&pos);
}

vec3f PointLight::getPosition() const {
	return position;
}

float PointLight::getRadius() const {
	return radius;
}


NodePointLight::NodePointLight(scene::Node* follow) : followNode(follow) {
	follow->grab();
}

NodePointLight::~NodePointLight() {
	if(followNode)
		followNode->drop();
	followNode = nullptr;
}

vec3f NodePointLight::getPosition() const {
	if(!followNode)
		return position;
	return vec3f(followNode->abs_position);
}

float NodePointLight::getRadius() const {
	if(!followNode)
		return radius;
	return followNode->abs_scale;
}

//TODO: This is probably out of sync by one frame
void NodePointLight::enable(unsigned& lightIndex, const vec3f& offset) {
	if(!followNode) {
		lightIndex += 1;
		return;
	}
	if(followNode->queuedDelete || !followNode->parent) {
		followNode->drop();
		followNode = nullptr;
		lightIndex += 1;
		return;
	}
	const auto& v = followNode->abs_position;
	position.x = (float)v.x;
	position.y = (float)v.y;
	position.z = (float)v.z;
	PointLight::enable(lightIndex, offset);
}

std::set<LightSource*> lights;

void registerLight(LightSource* light) {
	lights.insert(light);
}

void unregisterLight(LightSource* light) {
	lights.erase(light);
}

void destroyLights() {
	for(auto it = lights.begin(); it != lights.end(); ++it)
		delete *it;
	lights.clear();
}

void resetLights() {
	Colorf diffuse, specular;
	float pos[4] = {0.f, 0.f, 0.f, 1.f};

	for(unsigned i = 1; i < 8; ++i)
		glDisable(GL_LIGHT0 + i);

	glEnable(GL_LIGHT0);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, (GLfloat*)&diffuse);
	glLightfv(GL_LIGHT0, GL_SPECULAR, (GLfloat*)&specular);
	glLightf(GL_LIGHT0, GL_QUADRATIC_ATTENUATION, 0.f);
	glLightfv(GL_LIGHT0, GL_POSITION, (GLfloat*)&pos);
}

//Finds up to <maximum> nearest lights to <from>
unsigned findNearestLights(const vec3f& from, LightSource** pLights, unsigned maximum) {
	unsigned found = 0;
	float distances[GL_MAX_LIGHTS];
	if(maximum > GL_MAX_LIGHTS)
		maximum = GL_MAX_LIGHTS;

	for(auto i = lights.begin(), end = lights.end(); i != end; ++i) {
		float dist = (*i)->distanceFrom(from);

		for(unsigned d = 0; d < found; ++d) {
			if(distances[d] > dist) {
				for(unsigned x = found-1; x > d; --x) {
					distances[x] = distances[x-1];
					pLights[x] = pLights[x-1];
				}
				distances[d] = dist;
				pLights[d] = *i;
				goto nextLight;
			}
		}

		if(found < maximum) {
			pLights[found] = *i;
			distances[found] = dist;
			++found;
		}

		nextLight:;
	}

	return found;
}

};
};
