#include "gui/skin.h"
#include "num_util.h"
#include "main/references.h"
#include "main/logging.h"
#include <map>

const gui::skin::Element* currentDrawnElement = 0;
vec2i eleDestSize;

void shader_skin_margin_src(float* margin,unsigned short,void*) {
	if(currentDrawnElement) {
		margin[0] = (float)currentDrawnElement->margin.topLeft.x;
		margin[1] = (float)currentDrawnElement->margin.topLeft.y;
		margin[2] = (float)currentDrawnElement->margin.botRight.x;
		margin[3] = (float)currentDrawnElement->margin.botRight.y;
	}
}

void shader_skin_margin_dest(float* margin,unsigned short,void*) {
	if(currentDrawnElement) {
		recti destMargin = currentDrawnElement->getDestinationMargin(eleDestSize);
		margin[0] = (float)destMargin.topLeft.x;
		margin[1] = (float)destMargin.topLeft.y;
		margin[2] = (float)destMargin.botRight.x;
		margin[3] = (float)destMargin.botRight.y;
	}
}

void shader_skin_src_pos(float* pos,unsigned short,void*) {
	if(currentDrawnElement) {
		pos[0] = (float)currentDrawnElement->area.topLeft.x;
		pos[1] = (float)currentDrawnElement->area.topLeft.y;
	}
}

void shader_skin_src_size(float* size,unsigned short,void*) {
	if(currentDrawnElement) {
		size[0] = (float)currentDrawnElement->area.getWidth();
		size[1] = (float)currentDrawnElement->area.getHeight();
	}
}

void shader_skin_dst_size(float* size,unsigned short,void*) {
	if(currentDrawnElement) {
		size[0] = (float)eleDestSize.x;
		size[1] = (float)eleDestSize.y;
	}
}

void shader_skin_mode(float* modes,unsigned short,void*) {
	if(currentDrawnElement) {
		modes[0] = (float)currentDrawnElement->horizMode;
		modes[1] = (float)currentDrawnElement->vertMode;
	}
}

void shader_skin_gradientCount(float* count,unsigned short,void*) {
	if(currentDrawnElement) {
		*count = (float)currentDrawnElement->gradients.size();
	}
}

void shader_skin_gradientMode(float* count,unsigned short,void*) {
	if(currentDrawnElement) {
		*count = (float)currentDrawnElement->gradMode;
	}
}

void shader_skin_gradientRects(float* rects, unsigned short n,void*) {
	if(currentDrawnElement) {
		unsigned short cnt = (unsigned short)currentDrawnElement->gradients.size();
		if(cnt < n)
			n = cnt;
		if(n == 0)
			return;

		recti baseRect(0,0, eleDestSize.width, eleDestSize.height);

		for(unsigned short i = 0; i < n; ++i) {
			auto& gradient = currentDrawnElement->gradients[i];
			recti rect = gradient.area.evaluate(baseRect);
			rects[i*4+0] = (float)rect.topLeft.x;
			rects[i*4+1] = (float)rect.topLeft.y;
			rects[i*4+2] = (float)rect.botRight.x;
			rects[i*4+3] = (float)rect.botRight.y;
		}
	}
}

void shader_skin_gradientCols(float* cols, unsigned short n, void*) {
	if(currentDrawnElement) {
		n /= 4;
		unsigned short cnt = (unsigned short)currentDrawnElement->gradients.size();
		if(cnt < n)
			n = cnt;
		if(n == 0)
			return;

		Colorf* fcols = (Colorf*)cols;
		for(unsigned short i = 0; i < n; ++i, fcols += 4) {
			auto& gradient = currentDrawnElement->gradients[i];
			new(fcols+0) Colorf(gradient.colors[0]);
			new(fcols+1) Colorf(gradient.colors[1]);
			new(fcols+2) Colorf(gradient.colors[2]);
			new(fcols+3) Colorf(gradient.colors[3]);
		}
	}
}

namespace gui {
namespace skin {

std::map<std::string,unsigned> dynStyleIndices;
std::map<std::string,unsigned> dynElementFlags;
std::map<std::string,unsigned> dynFontIndices;
std::map<std::string,unsigned> dynColorIndices;
std::map<unsigned,std::string> dynFlagNames;
unsigned nextElementFlag = 1;

bool elementLower(Element* x, Element* y) {
	return x->flags < y->flags;
}

int getDynamicIndex(std::map<std::string, unsigned>& dyn, const std::string& name, bool addIfMissing) {
	auto index = dyn.find(name);
	if(index == dyn.end()) {
		if(addIfMissing) {
			unsigned newIndex = (unsigned)dyn.size();
			dyn[name] = newIndex;
			return newIndex;
		}
		else {
			return -1;
		}
	}
	return index->second;
}

unsigned getStyleCount() {
	return (unsigned)dynStyleIndices.size();
}

int getStyleIndex(const std::string& name, bool addIfMissing) {
	return getDynamicIndex(dynStyleIndices, name, addIfMissing);
}

int getElementFlag(const std::string& name, bool addIfMissing) {
	if(name == "Normal")
		return 0;
	auto index = dynElementFlags.find(name);
	if(index == dynElementFlags.end()) {
		if(addIfMissing) {
			if(nextElementFlag == 0) {
				nextElementFlag = 1;
				error("Error: Skin exceeded limit of 32 unique element flags.");
			}

			unsigned flag = nextElementFlag;
			dynElementFlags[name] = flag;
			dynFlagNames[flag] = name;

			if(flag == 0x100000000)
				nextElementFlag = 0;
			else
				nextElementFlag = nextElementFlag << 1;

			return flag;
		}
		else {
			return 0;
		}
	}
	return index->second;
}

std::string getElementFlagName(unsigned flag) {
	if(flag == 0)
		return "Normal";
	unsigned check = 0x1;
	unsigned cnt = 0;
	std::string name;
	for(unsigned i = 0; i < 32; ++i, check <<= 1) {
		if((flag & check) != 0) {
			if(cnt != 0)
				name += ", ";
			auto it = dynFlagNames.find(check);
			if(it != dynFlagNames.end())
				name += it->second;
			else
				name += "???";
			++cnt;
		}
	}
	return name;
}

int getColorIndex(const std::string& name, bool addIfMissing) {
	return getDynamicIndex(dynColorIndices, name, addIfMissing);
}

int getFontIndex(const std::string& name, bool addIfMissing) {
	return getDynamicIndex(dynFontIndices, name, addIfMissing);
}

void clearDynamicIndices() {
	dynElementFlags.clear();
	dynFlagNames.clear();
	dynFontIndices.clear();
	dynColorIndices.clear();
	dynStyleIndices.clear();
	nextElementFlag = 1;
}

void enumerateStyleIndices(std::function<void(const std::string&,unsigned)> callback) {
	foreach(i, dynStyleIndices)
		callback(i->first,i->second);
}

void enumerateElementFlags(void (*cb)(const std::string&,unsigned)) {
	(*cb)("Normal", 0);
	foreach(i, dynElementFlags)
		(*cb)(i->first,i->second);
}

void enumerateColorIndices(void (*cb)(const std::string&,unsigned)) {
	foreach(i, dynColorIndices)
		(*cb)(i->first,i->second);
}

void enumerateFontIndices(void (*cb)(const std::string&,unsigned)) {
	foreach(i, dynFontIndices)
		(*cb)(i->first,i->second);
}

void Style::addElement(Element* ele) {
	auto at = std::lower_bound(elements.begin(), elements.end(), ele, elementLower);
	if(at == elements.end())
		elements.push_back(ele);
	else
		elements.insert(at, ele);
}

Element* Style::getExactElement(unsigned flags) const {
	foreach(it, elements) {
		if((*it)->flags == flags)
			return *it;
	}
	return nullptr;
}

const Element* Style::getElement(unsigned flags) const {
	if(elements.empty())
		return nullptr;

	Element ele;
	ele.flags = flags;

	auto at = std::lower_bound(elements.begin(), elements.end(), &ele, elementLower);
	size_t index;
	
	if(at == elements.end())
		index = elements.size() - 1;
	else
		index = at - elements.begin();

	if(elements[index]->flags == flags)
		return elements[index];

	while(index > 0 && (~flags & elements[index]->flags))
		--index;

	return elements[index];
}

bool Skin::hasStyle(unsigned index) const {
	if(index >= styles.size())
		return false;
	if(!styles[index])
		return false;
	return true;
}

const Style& Skin::getStyle(unsigned index) const {
	if(index >= styles.size())
		return *errorStyle;
	if(!styles[index])
		return *errorStyle;
	return *styles[index];
}

const Element& Skin::getElement(unsigned index, unsigned flags) const {
	if(index < styles.size() && styles[index]) {
		const Element* ele = styles[index]->getElement(flags);
		if(ele)
			return *ele;
	}
	return *errorElement;
}

const render::Font& Skin::getFont(unsigned index) const {
	if(index < (unsigned)fonts.size() && fonts[index])
		return *fonts[index];
	return *errorFont;
}

Color Skin::getColor(unsigned index) const {
	if(index < (unsigned)colors.size())
		return colors[index];
	return Color();
}

void Skin::setStyle(unsigned index, Style* style) {
	if(index >= (unsigned)styles.size())
		styles.resize(index+1, 0);
	styles[index] = style;
}

void Skin::setColor(unsigned index, Color color) {
	if(index >= (unsigned)colors.size())
		colors.resize(index+1);
	colors[index] = color;
}

void Skin::setFont(unsigned index, const render::Font* font) {
	if(index >= (unsigned)fonts.size())
		fonts.resize(index+1, 0);
	fonts[index] = font;
}

Skin::Skin() : fonts(), material(0) {
	errorFont = render::Font::createDummyFont();
	errorElement = new Element();
	errorStyle = new Style();
}

void Gradient::draw(render::RenderDriver& driver, recti pos,
		const recti* clip) const {

	recti absPos = area.evaluate(pos);
	driver.drawRectangle(absPos, 0, 0, colors, clip);
}

void Layer::draw(render::RenderDriver& driver, recti pos,
		const recti* clip, Color color) const {

	if(!ele)
		return;

	recti absPos = area.evaluate(pos);
	ele->draw(driver, absPos, clip, hasOverride ? override : color);
}

void Element::clear() {
	layers.clear();
	gradients.clear();

	margin = recti();
	filled = true;
	horizMode = DM_Uniform;
	vertMode = DM_Uniform;
	aspectMargin = AMM_None;
}

void Element::draw(render::RenderDriver& driver, recti pos,
					const recti* clip, Color color) const {
	Color colors[4] = {color, color, color, color};

	foreach(it, layers)
		(*it).draw(driver, pos, clip, color);

	//TODO: Support no fill

	if(!area.empty() || gradMode == GM_Overlay) {
		currentDrawnElement = this;
		eleDestSize = pos.getSize();
		driver.drawRectangle(pos, material, 0, colors, clip);
		currentDrawnElement = 0;
	}
}

recti Element::getDestinationMargin(vec2i size) const {
	recti destMargin;
	switch(aspectMargin) {
		case AMM_None:
			destMargin.topLeft.x = margin.topLeft.x;
			destMargin.topLeft.y = margin.topLeft.y;
			destMargin.botRight.x = margin.botRight.x;
			destMargin.botRight.y = margin.botRight.y;
		break;
		case AMM_Horizontal: {
			float l_ratio = ((float)margin.topLeft.x) / ((float)area.getHeight());
			float r_ratio = ((float)margin.botRight.x) / ((float)area.getHeight());

			destMargin.topLeft.x = (int)(l_ratio * (float)size.height);
			destMargin.topLeft.y = margin.topLeft.y;
			destMargin.botRight.x = (int)(r_ratio * (float)size.height);
			destMargin.botRight.y = margin.botRight.y;
		} break;
		case AMM_Vertical: {
			float l_ratio = ((float)margin.topLeft.y) / ((float)area.getWidth());
			float r_ratio = ((float)margin.botRight.y) / ((float)area.getWidth());

			destMargin.topLeft.x = margin.topLeft.x;
			destMargin.topLeft.y = (int)(l_ratio * (float)size.width);
			destMargin.botRight.x = margin.botRight.x;
			destMargin.botRight.y = (int)(r_ratio * (float)size.width);
		} break;
	}
	return destMargin;
}

bool Element::isPixelActive(recti box, vec2i px) const {
	if(!material)
		return true;
	auto* tex = material->textures[0];
	if(!tex)
		return true;

	recti dmargin = getDestinationMargin(box.getSize());
	int tx = 0;
	switch(horizMode) {
		case DM_Uniform:
			tx = px.x + area.topLeft.x;
		break;
		case DM_Scaled:
		case DM_Tiled:
			if(px.x < dmargin.topLeft.x) {
				tx = (int)((float)px.x * (float)margin.topLeft.x / (float)dmargin.topLeft.x) + area.topLeft.x;
			}
			else if(px.x >= box.getWidth() - dmargin.botRight.x) {
				tx = area.botRight.x - (box.getWidth() -
						(int)((float)px.x * (float)margin.botRight.x / (float)dmargin.botRight.x));
			}
			else {
				tx = area.topLeft.x + margin.topLeft.x;
				if(horizMode == DM_Scaled) {
					tx += (int)(((double)(px.x - dmargin.topLeft.x)/
								(double)(box.getWidth() - dmargin.topLeft.x - dmargin.botRight.x))
							* (double)(area.getWidth() - margin.topLeft.x - margin.botRight.x));
				}
				else {
					tx += (px.x - dmargin.topLeft.x) % (area.getWidth() - margin.topLeft.x - margin.botRight.x);
				}
			}
		break;
	}

	int ty = 0;
	switch(vertMode) {
		case DM_Uniform:
			ty = px.y + area.topLeft.y;
		break;
		case DM_Scaled:
		case DM_Tiled:
			if(px.y < dmargin.topLeft.y) {
				ty = (int)((float)px.y * (float)margin.topLeft.y / (float)dmargin.topLeft.y) + area.topLeft.y;
			}
			else if(px.y >= box.getWidth() - dmargin.botRight.y) {
				ty = area.botRight.y - (box.getHeight() -
						(int)((float)px.y * (float)margin.botRight.y / (float)dmargin.botRight.y));
			}
			else {
				ty = area.topLeft.y + margin.topLeft.y;
				if(horizMode == DM_Scaled) {
					ty += (int)(((double)(px.y - dmargin.topLeft.y)/
								(double)(box.getHeight() - dmargin.topLeft.y - dmargin.botRight.y))
							* (double)(area.getHeight() - margin.topLeft.y - margin.botRight.y));
				}
				else {
					ty += (px.y - dmargin.topLeft.y) % (area.getHeight() - margin.topLeft.y - margin.botRight.y);
				}
			}
		break;
	}

	return tex->isPixelActive(vec2i(tx, ty));
}

};
};
