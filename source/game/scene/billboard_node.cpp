#include "scene/billboard_node.h"
#include "render/driver.h"

namespace scene {

BillboardNode::BillboardNode(const render::RenderState* Material, double Width)
	: material(Material), width(Width)
{
	setFlag(NF_NoMatrix, true);
	if(Material->baseMat != render::MAT_Solid)
		setFlag(NF_Transparent, true);
}

void BillboardNode::setWidth(double Width) {
	if(width != Width)
		width = Width;
}

bool BillboardNode::preRender(render::RenderDriver& driver) {
	auto fromCamera = abs_position - driver.cam_pos;
	if(fromCamera.dot(driver.cam_facing) > 0) {
		sortDistance = fromCamera.getLength();
		return true;
	}
	else {
		return false;
	}
}
	
void BillboardNode::render(render::RenderDriver& driver) {
	driver.switchToRenderState(*material);
	driver.drawBillboard(abs_position, width * abs_scale);
}

SpriteNode::SpriteNode(const render::Sprite& sprt, double Width)
	: sprite(sprt), width(Width)
{
	setFlag(NF_NoMatrix, true);
	if(sprt.mat) {
		if(sprt.mat->baseMat != render::MAT_Solid)
			setFlag(NF_Transparent, true);
	}
	else if(sprt.sheet) {
		if(sprt.sheet->material.baseMat != render::MAT_Solid)
			setFlag(NF_Transparent, true);
	}
}

void SpriteNode::setWidth(double Width) {
	if(width != Width)
		width = Width;
}

bool SpriteNode::preRender(render::RenderDriver& driver) {
	auto fromCamera = abs_position - driver.cam_pos;
	if(fromCamera.dot(driver.cam_facing) > 0) {
		sortDistance = fromCamera.getLength();
		return true;
	}
	else {
		return false;
	}
}
	
void SpriteNode::render(render::RenderDriver& driver) {
	if(sprite.mat) {
		driver.switchToRenderState(*sprite.mat);
		driver.drawBillboard(abs_position, width * abs_scale);
	}
	else {
		driver.drawBillboard(abs_position, width * abs_scale, sprite.sheet->material, sprite.sheet->getSource(sprite.index), 0, Color());
	}
}

};
