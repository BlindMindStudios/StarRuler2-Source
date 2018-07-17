#include "node.h"
#include "color.h"
#include "render/render_state.h"
#include "threads.h"
#include "design/projectiles.h"

#include <unordered_map>

struct MissileTrailMats {
	const render::RenderState* sprite, *trail;

	bool operator==(const MissileTrailMats& other) const {
		return sprite == other.sprite && trail == other.trail;
	}
};

namespace std {
template<>
struct hash<MissileTrailMats> {
	size_t operator()(const MissileTrailMats& trail) const {
		return (size_t)trail.sprite ^ (size_t)trail.trail;
	};
};
};

namespace scene {

#define LINE_POS_COUNT 16

class LineTrailNode : public Node {
	//Stored previous positions so a trail can be rendered
	vec3d prevPositions[LINE_POS_COUNT];
	unsigned storedPositions;
	unsigned firstIndex;

	//The number of seconds since a position has been stored
	double stored_s;

	//Number of steps to process (higher is lower quality)
	unsigned qualitySteps;

	const render::RenderState& mat;

public:
	//The number of seconds the trail lasts
	double lineLen_s;
	Color startCol, endCol;

	LineTrailNode(const render::RenderState& material);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

class ProjectileBatch : public Node {
public:
	struct ProjEffect {
		threads::SharedData<bool>* kill;
		vec3d pos;
		vec3f dir;
		Color start, end;
		float length, life, fadeStart, speed;
		bool line;
	};
private:
	std::unordered_map<const render::RenderState*,std::vector<ProjEffect>*> projectiles;
public:
	ProjectileBatch();
	~ProjectileBatch();

	void registerProj(const render::RenderState& mat, ProjEffect& eff);
	
	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};


class MissileBatch : public Node {
public:
	struct MissileTrail {
		threads::SharedData<MissileData>* track;
		double lastUpdate;
		vec3d trail[LINE_POS_COUNT];
		vec3d pos;
		float length, size;
		Color start, end, color;
		float lineProgress, startProgress;
		unsigned lineStart, lineCount;
	};
private:
	std::unordered_map<MissileTrailMats,std::vector<MissileTrail>*> missiles;
public:
	MissileBatch();
	~MissileBatch();

	void registerProj(const render::RenderState& mat, const render::RenderState& trail, MissileTrail& eff);
	
	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

};
