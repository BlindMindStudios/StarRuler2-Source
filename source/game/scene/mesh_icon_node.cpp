#include "scene/mesh_icon_node.h"
#include "render/driver.h"
#include "render/render_mesh.h"
#include "render/spritesheet.h"
#include "render/vertexBuffer.h"
#include "constants.h"
#include "frustum.h"

namespace scene {

//Maximum distance away from the camera something can render (according to its scale)
const double MaxRenderDistFactor = 8000.0;
const double IconRenderDistFactor = 1000.0;
const double BothRenderDistFactor = 500.0;
bool MeshIconNode::render3DIcons = true;

MeshIconNode::MeshIconNode(
	const render::RenderMesh* Mesh, const render::RenderState* Material,
	const render::SpriteSheet* Sheet, unsigned Index)
		: mesh(Mesh), material(Material), iconSheet(Sheet), iconIndex(Index) {
	if(Material->baseMat != render::MAT_Solid || (Sheet && Sheet->material.baseMat != render::MAT_Solid))
		setFlag(NF_Transparent, true);
	setFlag(NF_AnimOnlyVisible, true);
}

bool MeshIconNode::preRender(render::RenderDriver& driver) {
	auto fromCamera = abs_position + (driver.cam_facing * abs_scale) - driver.cam_pos;
	sortDistance = fromCamera.getLength();

	if(sortDistance > MaxRenderDistFactor * abs_scale || !driver.getViewFrustum().overlaps(abs_position,abs_scale))
		return false;
	else
		return true;
}

void MeshIconNode::render(render::RenderDriver& driver) {
	if(render3DIcons) {
		double scaleMod = pow(abs_scale, 0.3);
		if(iconSheet) {
			if(sortDistance > BothRenderDistFactor * scaleMod) {
				double iconScale = sqrt(sortDistance / abs_scale) * abs_scale * 0.25;

				//Calculate best-fit facing of the 2D sprite (Assuming the sprite is facing +x)
				auto& cam_facing = driver.cam_facing;
				auto& cam_up = driver.cam_up;

				double rot;

				vec3d obj_facing = rotation * vec3d::front();
				double alongDot = cam_facing.dot(obj_facing);

				//If it's facing along the camera vector, we can't get an accurate angle
				if(alongDot > -0.9999 && alongDot < 0.9999) {
					obj_facing -= cam_facing * alongDot;
					obj_facing.normalize();

					vec3d cam_right = cam_facing.cross(cam_up).normalized();
					rot = acos(cam_right.dot(obj_facing));
					if(cam_right.cross(cam_facing).dot(obj_facing) < 0)
						rot = -rot;
				}
				else {
					//Point up when going away, down when coming toward
					rot = alongDot > 0 ? pi * 0.5 : pi * -0.5;
				}

				color.a = std::min(1.0, (sortDistance / scaleMod - BothRenderDistFactor) / (IconRenderDistFactor - BothRenderDistFactor));

				Color c = color;

				driver.drawBillboard(abs_position, iconScale,
					iconSheet->material, iconSheet->getSource(iconIndex), rot, c);

				if(sortDistance > IconRenderDistFactor * scaleMod)
					return;
			}
		}
		else if(sortDistance > IconRenderDistFactor * scaleMod) {
			return;
		}
	}
	
	if(material->baseMat != render::MAT_Solid)
		render::renderVertexBuffers();

	driver.setTransformation(transformation);
	driver.switchToRenderState(*material);
	mesh->selectLOD(sortDistance / abs_scale)->render();
	driver.resetTransformation();
}
	
};
