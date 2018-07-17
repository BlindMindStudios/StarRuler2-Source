#include "scene/mesh_node.h"
#include "render/driver.h"
#include "render/render_mesh.h"
#include "render/vertexBuffer.h"
#include "frustum.h"
#include "physics/physics_world.h"
#include "aabbox.h"
#include "main/references.h"

namespace scene {

//Maximum distance away from the camera something can render (according to its scale)
const double MaxRenderDistFactor = 1400.0;

MeshNode::MeshNode(const render::RenderMesh* Mesh, const render::RenderState* Material)
	: mesh(Mesh), material(Material) {
	if(Material->baseMat != render::MAT_Solid)
		setFlag(NF_Transparent, true);
	setFlag(NF_AnimOnlyVisible, true);
}

bool MeshNode::preRender(render::RenderDriver& driver) {
	auto fromCamera = abs_position + (driver.cam_facing * abs_scale) - driver.cam_pos;
	sortDistance = fromCamera.getLength();

	if(sortDistance > MaxRenderDistFactor * abs_scale || !driver.getViewFrustum().overlaps(abs_position,abs_scale))
		return false;
	else
		return true;
}

void MeshNode::render(render::RenderDriver& driver) {
	if(material->baseMat != render::MAT_Solid)
		render::renderVertexBuffers();

	driver.setTransformation(transformation);
	driver.switchToRenderState(*material);
	mesh->selectLOD(sortDistance / abs_scale)->render();
	driver.resetTransformation();
}
	
};
