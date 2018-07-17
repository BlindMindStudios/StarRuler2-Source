#include "render/spritesheet.h"

void shader_sprite_pos(float* output, unsigned short,void*) {
	if(render::SpriteSheet::current) {
		vec4f pos = render::SpriteSheet::current->getSourceUV(render::SpriteSheet::currentIndex);
		output[0] = pos.x;
		output[1] = pos.y;
		output[2] = pos.z;
		output[3] = pos.w;
	}
	else {
		output[0] = 0.f;
		output[1] = 0.f;
		output[2] = 1.f;
		output[3] = 1.f;
	}
}

namespace render {

const SpriteSheet* SpriteSheet::current = nullptr;
unsigned SpriteSheet::currentIndex = 0;

SpriteSheet::SpriteSheet() 
	: mode(SM_Horizontal), width(32), height(32), spacing(0), perLine(0), dirty(true) {
}

inline vec2i getXY(const SpriteSheet& sheet, unsigned index) {
	if(sheet.dirty) {
		auto* texture = sheet.material.textures[0];
		if(!texture) {
			sheet.dirty = false;
			sheet.perLine = 0;
			return vec2i();
		}
		else if(!texture->loaded) {
			return vec2i();
		}

		sheet.dirty = false;
		sheet.perLine = 0;

		if(!texture)
			return vec2i();

		if(sheet.mode == SM_Horizontal) {
			unsigned imgWidth = texture->size.width;
			if(imgWidth != 0)
				sheet.perLine = (imgWidth - sheet.spacing) / (sheet.width + sheet.spacing);
		}
		else { //SM_Vertical:
			unsigned imgHeight = texture->size.height;
			if(imgHeight != 0)
				sheet.perLine = (imgHeight - sheet.spacing) / (sheet.height + sheet.spacing);
		}
	}

	if(sheet.mode == SM_Horizontal) {
		int perRow = sheet.perLine;
		if(perRow != 0)
			return vec2i(index % perRow, index / perRow);
	}
	else { //SM_Vertical
		int perCol = sheet.perLine;
		if(perCol != 0)
			return vec2i(index / perCol, index % perCol);
	}

	return vec2i();
}

vec4f SpriteSheet::getSourceUV(unsigned index) const {
	if(material.textures[0]) {
		const vec2i imgSize = material.textures[0]->size;
		if(imgSize.width == 0 || imgSize.height == 0)
			return vec4f();

		switch(mode) {
			case SM_Horizontal: {
				unsigned perRow = (imgSize.width - spacing) / (width + spacing);

				float x = float((index % perRow) * (width + spacing) + spacing) / float(imgSize.width);
				float y = float((index / perRow) * (height + spacing) + spacing) / float(imgSize.height);

				return vec4f(x,y,x + float(width)/float(imgSize.width), y + float(height)/float(imgSize.height));
			} break;
			case SM_Vertical: {
				unsigned perCol = (imgSize.height - spacing) / (height + spacing);

				float x = float((index / perCol) * (width + spacing) + spacing) / float(imgSize.width);
				float y = float((index % perCol) * (height + spacing) + spacing) / float(imgSize.height);

				return vec4f(x,y,x + float(width)/float(imgSize.width), y + float(height)/float(imgSize.height));
			} break;
		}
	}

	return vec4f(0,0,1.f,1.f);
}

bool SpriteSheet::isPixelActive(unsigned index, const vec2i& px) const {
	recti src = getSource(index);
	if(!src.isWithin(px + src.topLeft))
		return false;
	auto* tex = material.textures[0];
	if(!tex)
		return false;
	return tex->isPixelActive(src.topLeft + px);
}

recti SpriteSheet::getSource(unsigned index) const {
	vec2i pos = getXY(*this, index);

	recti source;
	source.topLeft.x = pos.x * (width + spacing) + spacing;
	source.topLeft.y = pos.y * (height + spacing) + spacing;
	source.botRight.x = source.topLeft.x + width;
	source.botRight.y = source.topLeft.y + height;

	return source;
}

void SpriteSheet::getSource(unsigned index, vec2f* out) const {
	vec2i pos = getXY(*this, index);
	
	out[0].x = (float)(pos.x * (width + spacing) + spacing);
	out[0].y = (float)(pos.y * (height + spacing) + spacing);

	out[2].x = out[0].x + width;
	out[2].y = out[0].y + height;

	out[1].x = out[2].x;
	out[1].y = out[0].y;

	out[3].x = out[0].x;
	out[3].y = out[2].y;
}

unsigned SpriteSheet::getCount() const {
	if(material.textures[0]) {
		vec2i texSize = material.textures[0]->size;
		if(texSize.width == 0 || texSize.height == 0)
			return 0;
		return (texSize.width / width) * (texSize.height / height);
	}
	else {
		return 0;
	}
}

void SpriteSheet::render(RenderDriver& driver, unsigned index, const vec3d* vertices, const Color* color) const {
	current = this;
	currentIndex = index;

	vec2f texcoords[4];
	getSource(index, texcoords);
	
	driver.switchToRenderState(material);
	driver.drawQuad(vertices, texcoords, color);

	current = nullptr;
}

void SpriteSheet::render(RenderDriver& driver, unsigned index, recti rectangle, const Color* color, const recti* clip, const Shader* shader, double rotation) const {
	current = this;
	currentIndex = index;

	recti source = getSource(index);

	if(shader) {
		static render::RenderState state;
		state = material;
		state.shader = shader;
		state.constant = false;

		driver.drawRectangle(rectangle, &state, &source, color, clip, rotation);
	}
	else {
		driver.drawRectangle(rectangle, &material, &source, color, clip, rotation);
	}

	current = nullptr;
}

};
