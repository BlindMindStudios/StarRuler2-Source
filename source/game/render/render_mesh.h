#pragma once
#include "aabbox.h"

struct Mesh;

namespace render {

class RenderMesh {
public:
	virtual void resetToMesh(const Mesh& mesh) = 0;
	virtual const RenderMesh* selectLOD(double distance) const = 0;
	virtual void setLOD(double distance, const RenderMesh* mesh) = 0;
	virtual const AABBoxf& getBoundingBox() const = 0;
	virtual const Mesh& getMesh() const = 0;

	virtual unsigned getMeshBytes() const = 0;

	virtual void render() const = 0;
	virtual ~RenderMesh() {}
};

};
