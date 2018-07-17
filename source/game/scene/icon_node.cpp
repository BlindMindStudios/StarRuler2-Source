#include "icon_node.h"
#include "render/driver.h"
#include "render/spritesheet.h"
#include "obj/object.h"
#include "frustum.h"

const double MinRenderDistanceFactor = 5000.0;

namespace scene {
	

	IconNode::IconNode(const render::SpriteSheet* spriteSheet, unsigned spriteIndex) : sheet(spriteSheet), index(spriteIndex) {
		setFlag(NF_NoMatrix, true);
		if(spriteSheet->material.baseMat != render::MAT_Solid)
			setFlag(NF_Transparent, true);
	}

	bool IconNode::preRender(render::RenderDriver& driver) {
		auto fromCamera = abs_position + (driver.cam_facing * abs_scale) - driver.cam_pos;
		sortDistance = fromCamera.getLength();

		if(sortDistance < MinRenderDistanceFactor * abs_scale || !driver.getViewFrustum().overlaps(abs_position,abs_scale))
			return false;
		else
			return true;
	}

	void IconNode::render(render::RenderDriver& driver) {
		double iconScale = sortDistance * abs_scale * 0.25;
		bool selected = false;
		if(obj)
			selected = obj->getFlag(objSelected);
		if(selected)
			iconScale *= 1.1;

		//Calculate best-fit facing of the 2D sprite (Assuming the sprite is facing +x)
		auto& cam_up = driver.cam_up;
		auto& cam_facing = driver.cam_facing;

		double rot;

		vec3d obj_facing = rotation * vec3d::front();
		double alongDot = cam_facing.dot(obj_facing);

		//If it's facing along the camera vector, we can't get an accurate angle
		if(alongDot > -0.999 && alongDot < 0.999) {
			obj_facing -= cam_facing * alongDot;
			obj_facing.normalize();

			vec3d cam_right = cam_up.cross(cam_facing);
			rot = acos(cam_right.dot(obj_facing));
			if(cam_up.dot(obj_facing) < 0)
				rot = -rot;
		}
		else {
			//Point up when going away, down when coming toward
			rot = alongDot > 0 ? pi * 0.5 : pi * -0.5;
		}

		driver.drawBillboard(abs_position, iconScale,
			sheet->material, sheet->getSource(index), rot);

		//TODO: Draw other icons based on group unit count
	}

};
