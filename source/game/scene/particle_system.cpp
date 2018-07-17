#include "particle_system.h"
#include "render/render_state.h"
#include "main/references.h"
#include "util/random.h"
#include "scripts/binds.h"
#include "ISound.h"
#include "constants.h"
#include "files.h"
#include "memory/AllocOnlyPool.h"
#include "render/vertexBuffer.h"
#include <vector>
#include <algorithm>
#include <stdint.h>

extern double frameLen_s, frameTime_s;
const uint32_t fileIdentifier = (uint32_t)(('S' << 24) | ('R' << 16) | ('2' << 8) | 'P');
const uint8_t currentVersion = 3;

struct BinaryFile {
	FILE* file;

	BinaryFile(const char* filename, const char* mode) : file(fopen(filename, mode)) {}

	~BinaryFile() {
		if(file)
			fclose(file);
	}

	bool open() const {
		return file != nullptr;
	}

	template<class T>
	BinaryFile& operator<<(const T& data) {
		fwrite(&data, sizeof(T), 1, file);
		return *this;
	}

	template<class T>
	BinaryFile& operator>>(T& data) {
		fread(&data, sizeof(T), 1, file);
		return *this;
	}

	void read(char* buffer, unsigned bytes) {
		fread(buffer, bytes, 1, file);
	}

	void write(const char* buffer, unsigned bytes) {
		fwrite(buffer, bytes, 1, file);
	}

	void write(const std::string& str) {
		uint8_t len = (uint8_t)str.size();
		*this << len;
		write(str.c_str(), len);
	}

	void read(std::string& str) {
		uint8_t len;
		*this >> len;
		char buffer[255];
		read(buffer, len);
		str.assign(buffer,len);
	}
};

struct RandRange {
	float min, max;

	float get() const {
		return randomf(min,max);
	}

	void set(float low, float hi) {
		min = low;
		max = hi;
	}

	RandRange() : min(0), max(0) {}
	RandRange(const RandRange& other) : min(other.min), max(other.max) {}
};

template<class T>
T interp(const T& a, const T& b, float percent) {
	return a + (b - a) * percent;
}

Color interp(Color a, Color b, float percent) {
	return a.getInterpolated(b, percent);
}

template<class T>
struct BezierCurve {
	std::vector<T> values;
	T def;

	T interp(float percent) const {
		unsigned count = (unsigned)values.size();
		if(count == 0)
			return def;
		if(count == 1)
			return values[0];
		if(count == 2)
			return ::interp(values[0], values[1], percent);
		if(count > 100)
			count = 100;

		//Need additional space for interpolated values
		T buffer[512];

		T* dest = &buffer[0];

		--count;
		for(unsigned i = 0; i < count; ++i)
			dest[i] = ::interp(values[i], values[i+1], percent);

		//Each iteration, swap dest and source, reduce the next count by one, and interp between previous results
		//When count reaches 0, we have the final value
		T* source = dest + count;

		while(--count != 0) {
			std::swap(source, dest);
			for(unsigned i = 0; i < count; ++i)
				dest[i] = ::interp(source[i], source[i+1], percent);
		}

		return dest[0];
	}

	void save(BinaryFile& file) const {
		uint8_t count = (uint8_t)values.size();
		file << count;

		for(uint8_t i = 0; i < count; ++i)
			file << values[i];
	}

	void load(BinaryFile& file) {
		uint8_t count;
		file >> count;
		values.resize(count);
		for(uint8_t i = 0; i < count; ++i)
			file >> values[i];
	}
};

namespace scene {

struct ParticleFlowDesc {
	std::vector<const render::RenderState*> materials;
	std::vector<std::string> matNames;
	BezierCurve<Color> color;
	BezierCurve<float> size;
	float start, end;
	float rate;
	RandRange cone, spawnDist, scale, life, speed;

	std::string sfx_start;
	const resource::Sound* sound_start;

	bool flat;

	ParticleFlowDesc() : start(0.f), end(0.f), rate(1.f), sound_start(nullptr), flat(false) {
		size.def = 1.f;
		cone.set(0.f, pi);
		life.set(1.f, 1.f);
		scale.set(1.f, 1.f);
	}

	unsigned getColorCount() const {
		return color.values.size();
	}

	Color getColor(int index) const {
		if(index < 0 || index >= (int)color.values.size())
			return color.def;
		else
			return color.values[index];
	}

	void setColor(int index, const Color& col) {
		if(index < 0 || index >= (int)color.values.size())
			color.def = col;
		else
			color.values[index] = col;
	}

	void addColor(unsigned index, const Color& col) {
		if(index >= color.values.size())
			color.values.push_back(col);
		else
			color.values.insert(color.values.begin() + index, col);
	}

	void removeColor(unsigned index) {
		if(index < color.values.size())
			color.values.erase(color.values.begin() + index);
	}

	unsigned getSizeCount() const {
		return size.values.size();
	}

	float getSize(int index) const {
		if(index < 0 || index >= (int)size.values.size())
			return size.def;
		else
			return size.values[index];
	}

	void setSize(int index, float Size) {
		if(index < 0 || index >= (int)size.values.size())
			size.def = Size;
		else
			size.values[index] = Size;
	}

	void addSize(unsigned index, float Size) {
		if(index >= size.values.size())
			size.values.push_back(Size);
		else
			size.values.insert(size.values.begin() + index, Size);
	}

	void removeSize(unsigned index) {
		if(index < size.values.size())
			size.values.erase(size.values.begin() + index);
	}

	unsigned getMatCount() const {
		return matNames.size();
	}

	std::string getMatName(unsigned index) const {
		if(index >= matNames.size())
			return "";
		else
			return matNames[index];
	}

	void setMatName(unsigned index, const std::string& name) {
		if(index < matNames.size()) {
			matNames[index] = name;
			materials[index] = &devices.library.getMaterial(name);
		}
	}

	void addMat(const std::string& name) {
		matNames.push_back(name);
		materials.push_back(&devices.library.getMaterial(name));
	}

	void removeMat(unsigned index) {
		if(index >= matNames.size())
			return;
		matNames.erase(matNames.begin() + index);
		materials.erase(materials.begin() + index);
	}

	void save(BinaryFile& file) const {
		file << start << end << rate;
		file << cone << spawnDist;
		file << scale.min << scale.max;
		file << life.min << life.max;
		file << speed.min << speed.max;
		color.save(file);
		size.save(file);

		file << flat;

		uint8_t count = (uint8_t)matNames.size();
		file << count;

		for(uint8_t i = 0; i < count; ++i)
			file.write(matNames[i]);
		file.write(sfx_start);
	}

	void load(BinaryFile& file, unsigned version) {
		file >> start >> end >> rate;
		if(version >= 1) {
			file >> cone >> spawnDist;
		}
		else {
			file >> cone.max;
		}
		file >> scale.min >> scale.max;
		file >> life.min >> life.max;
		file >> speed.min >> speed.max;
		color.load(file);
		size.load(file);

		if(version >= 3)
			file >> flat;

		uint8_t count = 0;
		file >> count;
		matNames.resize(count);
		materials.resize(count);

		for(uint8_t i = 0; i < count; ++i) {
			file.read(matNames[i]);
			//TODO: Defer matching names with materials
			materials[i] = &devices.library.getMaterial(matNames[i]);
		}

		if(version > 1) {
			file.read(sfx_start);
			sound_start = devices.library.getSound(sfx_start);
		}
	}
};

struct Particle {
	const render::RenderState* mat;
	Particle* next;
	quaternionf rot;
	vec3d pos;
	vec3f vel;
	float scale, life, age;
	float rotation;

	float frame_scale;
	Color frame_color;

	bool update(float time, const ParticleFlowDesc* flow) {
		age += time;
		if(age >= life)
			return true;

		pos += vec3d(vel * time);
		float percent = age / life;
		frame_scale = scale * flow->size.interp(percent);
		frame_color = flow->color.interp(percent);
		return false;
	}

	Particle* updateChain(float time, const ParticleFlowDesc* flow) {
		Particle* cur = this, *prev = nullptr, *head = nullptr;
		while(cur) {
			if(cur->update(time, flow)) {
				auto* deleteParticle = cur;
				cur = cur->next;
				if(prev)
					prev->next = cur;
				delete deleteParticle;
			}
			else {
				if(!head)
					head = cur;
				prev = cur;
				cur = cur->next;
			}
		}

		return head;
	}

	Particle(const ParticleFlowDesc* flow, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float Scale, float Life, float timeAdvance)
		: age(0), life(Life), next(0), pos(position)
	{
		scale = flow->scale.get() * Scale;
		rotation = (float)randomd(0,twopi);
		if(!flow->materials.empty())
			mat = flow->materials[randomi(0,(int)flow->materials.size() - 1)];
		else
			mat = &devices.library.getErrorMaterial();

		vec3d from = vec3d::front();
		vec3d perpRight = from.cross(vec3d::right());
		vec3d perpUp = from.cross(perpRight);

		double perpAngle = randomd() * twopi;
		vec3d perp = (perpRight * cos(perpAngle) + perpUp * sin(perpAngle)).normalized();

		//Slerp to the perpendicular vector based on the actual chosen spread angle
		double angle = flow->cone.get();
		vec3d dir;
		if(angle < pi * 0.5)
			dir = from.slerp(perp, angle / (pi * 0.5));
		else
			dir = perp.slerp(-from, (angle - pi*0.5) / (pi * 0.5));

		dir = rot * dir;
		if(flow->flat)
			this->rot = quaternionf::fromImpliedTransform(vec3f::up(), vec3f(dir));

		vel = vec3f((dir * (flow->speed.get() * Scale)) + velocity);
		pos += dir * (flow->spawnDist.get() * Scale);

		update(timeAdvance, flow);
	}

	static Particle* create(const ParticleFlowDesc* flow, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float Scale, float timeAdvance) {
		float life = flow->life.get();
		if(timeAdvance >= life)
			return nullptr;
		return new Particle(flow, position, velocity, rot, Scale, life, timeAdvance);
	}
};

struct ParticleSystemDesc {
	std::vector<ParticleFlowDesc*> flows;

	ParticleFlowDesc* getFlow(unsigned index) {
		if(index < (unsigned)flows.size())
			return flows[index];
		else
			return 0;
	}

	unsigned getFlowCount() const {
		return (unsigned)flows.size();
	}

	void removeFlow(unsigned index) {
		//TODO: Totally unsafe
		if(index < (unsigned)flows.size()) {
			delete flows[index];
			flows.erase(flows.begin() + index);
		}
	}

	ParticleFlowDesc* addFlow() {
		ParticleFlowDesc* desc = new ParticleFlowDesc();
		flows.push_back(desc);
		return desc;
	}

	ParticleFlowDesc* copyFlow(ParticleFlowDesc* flow) {
		if(!flow)
			return nullptr;
		ParticleFlowDesc* desc = new ParticleFlowDesc(*flow);
		flows.push_back(desc);
		return desc;
	}

	void save(const char* filename) const {
		BinaryFile file(filename, "wb");
		if(!file.open())
			return;

		//Identifier and version
		file << fileIdentifier << currentVersion;

		file << (uint16_t)flows.size();

		for(uint16_t i = 0, cnt = (uint16_t)flows.size(); i < cnt; ++i)
			flows[i]->save(file);
	}

	void load(const char* filename) {
		BinaryFile file(filename, "rb");
		if(!file.open())
			return;

		uint32_t identifier;
		uint8_t version;
		file >> identifier >> version;
		if(identifier != fileIdentifier || version > currentVersion)
			return;

		uint16_t flowCount = 0;
		file >> flowCount;
		flows.resize(flowCount);
		for(uint16_t i = 0; i < flowCount; ++i) {
			flows[i] = new ParticleFlowDesc();
			flows[i]->load(file, version);
		}
	}
};

ParticleSystemDesc* loadParticleSystem(const std::string& filename) {
	ParticleSystemDesc* system = new ParticleSystemDesc();
	system->load(filename.c_str());
	return system;
}

ParticleSystemDesc* createDummyParticleSystem() {
	return new ParticleSystemDesc();
}

ParticleSystem* playParticleSystem(const ParticleSystemDesc* desc, Node* parent, const vec3d& pos, const quaterniond& rot, const vec3d& vel, float scale, float delay) {
	if(desc == 0)
		return 0;

	ParticleSystem* sys = new ParticleSystem(desc);

	sys->position = pos;
	sys->vel = vel;
	sys->rot = rot;
	sys->scale = scale;
	sys->delay = delay;

	if(parent) {
		sys->setFlag(NF_Independent, false);
		sys->queueReparent(parent);
	}
	else {
		sys->queueReparent(devices.scene);
	}

	return sys;
}

ParticleSystem::ParticleSystem(const ParticleSystemDesc* system) : age(0.f), delay(0.f), scale(1.f), lastUpdate(frameTime_s) {
	setFlag(NF_NoMatrix, true);
	setFlag(NF_Transparent, true);
	flows.resize(system->flows.size());
	for(size_t i = 0, cnt = flows.size(); i < cnt; ++i)
		flows[i].flow = system->flows[i];
}

ParticleSystem::~ParticleSystem() {
	for(size_t i = 0, cnt = flows.size(); i < cnt; ++i) {
		auto* particle = flows[i].list;
		while(particle) {
			auto* next = particle->next;
			delete particle;
			particle = next;
		}
	}
}

bool ParticleSystem::preRender(render::RenderDriver& driver) {
	float time = (float)(frameTime_s - lastUpdate);
	if(delay > 0) {
		delay -= time;
		if(delay > 0)
			return true;
	}
	if(time > 0) {
		lastUpdate = frameTime_s;
		rebuildTransformation();
		age += time;

		bool alive = false;

		for(size_t i = 0, cnt = flows.size(); i != cnt; ++i) {
			auto& flowData = flows[i];
			auto* flow = flowData.flow;

			if(age >= flow->start) {
				if(!flowData.started) {
					if(flow->sound_start) {
						//At the start of a flow, play its start sound (if the flow isn't already over due)
						if(auto* sound = flow->sound_start->play3D(abs_position,false,true,false)) {
							int msOffset = (int)(1000.0 * (age - flow->start));
							//Avoid offsetting the sound unless it's at least a few frames off
							if(msOffset > 64)
								sound->setPlayPosition(msOffset);
							double base_dist = abs_scale * (flow->life.max * flow->speed.max + flow->scale.max);
							sound->setMinDistance(base_dist);
							sound->setMaxDistance(base_dist * 128.f);
							sound->setVolume(base_dist);
							sound->resume();
							sound->drop();
						}
					}
					
					flowData.started = true;
				}

				unsigned make = 0;
				float overtime = age - flow->end;
				if(overtime < 0.f) {
					alive = true;

					flowData.progress += flow->rate * time;
					float iPart;
					flowData.progress = std::modf(flowData.progress + (flow->rate * time), &iPart);
					make = (unsigned)iPart;
				}
				else if(flowData.progress > 0.f) {
					//If we had enough time in our dying moment to create a particle, do so
					//Handles cases of very short lived flows that only generate one particle or very few
					float iPart;
					std::modf(flowData.progress + flow->rate * (time - overtime), &iPart);
					if(iPart > 0)
						make = (unsigned)iPart;
					flowData.progress = 0.f;
				}

				if(flowData.list)
					flowData.list = flowData.list->updateChain(time, flow);

				if(make > 0) {
					float tStep = time / (float)make;
					float tOff = tStep;

					if(time > flow->life.max) {
						//Skip generating particles that definitely won't survive
						// Special case for long-duration particle systems that may spend long periods invisible
						int skip = (int)((time - flow->life.max) / tStep);
						tOff += (float)skip * tStep;
						make -= (unsigned)skip;
					}

					quaterniond totRot = abs_rotation * rot;

					while(make--) {
						Particle* particle = Particle::create(flow, abs_position, vel, totRot, scale, tOff);
						tOff += tStep;

						if(particle) {
							if(flowData.list)
								particle->next = flowData.list;
							flowData.list = particle;
						}
					}
				}

				if(flowData.list)
					alive = true;
			}
			else if(age < flow->end) {
				alive = true;
			}
		}

		if(!alive) {
			markForDeletion();
			return false;
		}
	}

	sortDistance = devices.render->cam_pos.distanceTo(abs_position);

	return true;
}

void ParticleSystem::end() {
	for(size_t i = 0, cnt = flows.size(); i != cnt; ++i)
		age = std::max(age, flows[i].flow->end);
}

void ParticleSystem::render(render::RenderDriver& driver) {
	for(size_t i = 0, cnt = flows.size(); i != cnt; ++i) {
		auto& flowData = flows[i];
		Particle* particle = flowData.list;

		if(!flowData.flow->flat) {
			while(particle) {
				devices.render->drawBillboard(particle->pos, particle->frame_scale * 2.f, *particle->mat, particle->rotation, &particle->frame_color);
				particle = particle->next;
			}
		}
		else {
			while(particle) {
				vec3f up = particle->rot * vec3f::front(particle->frame_scale);
				vec3f right = particle->rot * vec3f::right(particle->frame_scale);
				vec3f ur = up + right, ul = up - right;
				
				double st = sin(particle->rotation), ct = cos(particle->rotation);
				vec3f upLeft = (ul * ct) - (ur * st);
				vec3f upRight = (ur * ct) + (ul * st);

				vec3f center = vec3f(particle->pos - devices.render->cam_pos);
				auto* buffer = render::VertexBufferTCV::fetch(particle->mat);
				auto* verts = buffer->request(1, render::PT_Quads);

				auto* vert = &verts[0];
				vert->pos = center + upLeft;
				vert->col = particle->frame_color;
				vert->uv = vec2f(0.f, 0.f);

				vert = &verts[1];
				vert->pos = center + upRight;
				vert->col = particle->frame_color;
				vert->uv = vec2f(1.f, 0.f);

				vert = &verts[2];
				vert->pos = center - upLeft;
				vert->col = particle->frame_color;
				vert->uv = vec2f(1.f, 1.f);

				vert = &verts[3];
				vert->pos = center - upRight;
				vert->col = particle->frame_color;
				vert->uv = vec2f(0.f, 1.f);

				particle = particle->next;
			}
		}
	}
}

};

namespace scripts {

void saveParticleSystem(scene::ParticleSystemDesc* system, const std::string& filename) {
	//TODO: Check that they aren't hacking
	system->save(filename.c_str());
}

scene::ParticleSystemDesc*  copyParticleSystem(scene::ParticleSystemDesc* system) {
	auto* ps = new scene::ParticleSystemDesc();
	ps->flows.resize(system->flows.size());
	for(size_t i = 0, cnt = system->flows.size(); i < cnt; ++i) {
		ps->flows[i] = new scene::ParticleFlowDesc(*system->flows[i]);
	}
	return ps;
}

scene::ParticleSystemDesc* makeParticleSystem() {
	return new scene::ParticleSystemDesc();
}

std::string flowGetStartSound(const scene::ParticleFlowDesc* desc) {
	return desc->sfx_start;
}

void flowSetStartSound(scene::ParticleFlowDesc* desc, const std::string& sfx) {
	desc->sfx_start = sfx;
	desc->sound_start = devices.library.getSound(sfx);
}

void RegisterParticleSystemBinds() {
	ClassBind rr("Range", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS | asOBJ_APP_CLASS_ALLFLOATS, sizeof(RandRange));
	rr.addMember("float min", offsetof(RandRange,min));
	rr.addMember("float max", offsetof(RandRange,max));

	//TODO: Leaks, leaks everywhere
	ClassBind ps("ParticleSystem", asOBJ_REF | asOBJ_NOCOUNT);
	ClassBind flow("ParticleFlow", asOBJ_REF | asOBJ_NOCOUNT);

	ps.addFactory("ParticleSystem@ f()", asFUNCTION(makeParticleSystem));
	
	ps.addMethod("ParticleFlow@ createFlow()", asMETHOD(scene::ParticleSystemDesc,addFlow));
	ps.addMethod("ParticleFlow@ duplicateFlow(ParticleFlow@ flow)", asMETHOD(scene::ParticleSystemDesc,copyFlow));
	ps.addMethod("void removeFlow(uint index)", asMETHOD(scene::ParticleSystemDesc,removeFlow));
	ps.addMethod("ParticleFlow@ get_flows(uint index)", asMETHOD(scene::ParticleSystemDesc,getFlow));
	ps.addMethod("uint get_flowCount() const", asMETHOD(scene::ParticleSystemDesc,getFlowCount));
	ps.addExternMethod("void save(const string& in filename) const", asFUNCTION(saveParticleSystem));
	ps.addExternMethod("ParticleSystem@ duplicate() const", asFUNCTION(copyParticleSystem));

	flow.addExternMethod("string get_soundStart() const", asFUNCTION(flowGetStartSound));
	flow.addExternMethod("void set_soundStart(const string& sfx)", asFUNCTION(flowSetStartSound));
	
	flow.addMethod("string get_materials(uint index) const", asMETHOD(scene::ParticleFlowDesc,getMatName));
	flow.addMethod("void set_materials(uint index, const string& id)", asMETHOD(scene::ParticleFlowDesc,setMatName));
	flow.addMethod("uint get_materialCount() const", asMETHOD(scene::ParticleFlowDesc,getMatCount));
	flow.addMethod("void addMaterial(const string& id)", asMETHOD(scene::ParticleFlowDesc,addMat));
	flow.addMethod("void removeMaterial(uint index)", asMETHOD(scene::ParticleFlowDesc,removeMat));
	
	flow.addMethod("uint get_colorCount() const", asMETHOD(scene::ParticleFlowDesc,getColorCount));
	flow.addMethod("Color get_colors(int index) const", asMETHOD(scene::ParticleFlowDesc,getColor));
	flow.addMethod("void set_colors(int index, const Color& col)", asMETHOD(scene::ParticleFlowDesc,setColor));
	flow.addMethod("void removeColor(uint index)", asMETHOD(scene::ParticleFlowDesc,removeColor));
	flow.addMethod("void addColor(uint index, const Color& col) const", asMETHOD(scene::ParticleFlowDesc,addColor));

	flow.addMethod("uint get_sizeCount() const", asMETHOD(scene::ParticleFlowDesc,getSizeCount));
	flow.addMethod("float get_sizes(int i) const", asMETHOD(scene::ParticleFlowDesc,getSize));
	flow.addMethod("void set_sizes(int i, float size)", asMETHOD(scene::ParticleFlowDesc,setSize));
	flow.addMethod("void removeSize(uint index)", asMETHOD(scene::ParticleFlowDesc,removeSize));
	flow.addMethod("void addSize(uint index, float size) const", asMETHOD(scene::ParticleFlowDesc,addSize));
	
	flow.addMember("float start", offsetof(scene::ParticleFlowDesc,start))
		doc("Second offset from when the particle system starts to begin this flow.");
	flow.addMember("float end", offsetof(scene::ParticleFlowDesc,end))
		doc("Second offset from when the particle system starts to end this flow.");
	flow.addMember("float rate", offsetof(scene::ParticleFlowDesc,rate))
		doc("Particles to generate per second.");
	flow.addMember("Range cone", offsetof(scene::ParticleFlowDesc,cone))
		doc("Radian spread of particule emission cone.");
	flow.addMember("Range spawnDist", offsetof(scene::ParticleFlowDesc,spawnDist))
		doc("Radius at which to emit particles.");
	flow.addMember("Range scale", offsetof(scene::ParticleFlowDesc,scale))
		doc("Range of possible particle scales.");
	flow.addMember("Range life", offsetof(scene::ParticleFlowDesc,life))
		doc("Range of possible particle durations (in seconds).");
	flow.addMember("Range speed", offsetof(scene::ParticleFlowDesc,speed))
		doc("Range of possible particle speeds.");
	flow.addMember("bool flat", offsetof(scene::ParticleFlowDesc,flat))
		doc("Whether particles should face the direction they are moving, rather than the camera.");
}
};
