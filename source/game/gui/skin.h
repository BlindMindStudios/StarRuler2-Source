#pragma once
#include "render/driver.h"
#include "render/font.h"
#include "render/render_state.h"
#include "color.h"
#include "rect.h"
#include <vector>
#include <functional>

enum DimensionMode {
	DM_Uniform,
	DM_Scaled,
	DM_Tiled
};

enum AspectMarginMode {
	AMM_None,
	AMM_Horizontal,
	AMM_Vertical,
};

enum GradientMode {
	GM_Normal,
	GM_Overlay,
};

namespace gui {
namespace skin {

class Element;

struct Gradient {
	Color colors[4];
	relrecti area;

	void draw(render::RenderDriver& driver, recti pos,
			const recti* clip = 0) const;
};


struct Layer {
	relrecti area;
	const Element* ele;
	Color override;
	bool hasOverride;

	Layer() : ele(0), hasOverride(false) {
	}

	void draw(render::RenderDriver& driver, recti pos,
			const recti* clip = 0, Color color = Color(0xffffffff)) const;
};

class Element {
public:
	unsigned flags;

	const render::RenderState* material;
	recti area;
	recti margin;
	AspectMarginMode aspectMargin;
	bool filled;
	DimensionMode horizMode, vertMode;
	GradientMode gradMode;

	std::vector<Gradient> gradients;
	std::vector<Layer> layers;

	Element() : material(0), aspectMargin(AMM_None), filled(true),
		horizMode(DM_Uniform), vertMode(DM_Uniform), gradMode(GM_Normal) {}

	void clear();
	recti getDestinationMargin(vec2i size) const;
	bool isPixelActive(recti box, vec2i px) const;
	void draw(render::RenderDriver& driver, recti pos,
		const recti* clip = 0, Color color = Color(0xffffffff)) const;
};

class Style {
public:
	std::vector<Element*> elements;
	bool irregular;

	Style() : irregular(false) {}

	void addElement(Element* ele);
	Element* getExactElement(unsigned flags) const;
	const Element* getElement(unsigned flags) const;
};

class Skin {
	const render::Font* errorFont;
	const Style* errorStyle;
	const Element* errorElement;
public:
	const render::RenderState* material;
	std::string materialName;

	std::vector<Style*> styles;
	std::vector<Color> colors;
	std::vector<const render::Font*> fonts;

	void setStyle(unsigned index, Style* style);
	void setColor(unsigned index, Color color);
	void setFont(unsigned index, const render::Font* font);

	bool hasStyle(unsigned index) const;
	const Style& getStyle(unsigned index) const;
	const Element& getElement(unsigned index, unsigned flags) const;
	const render::Font& getFont(unsigned index) const;
	Color getColor(unsigned index) const;

	Skin();
};

unsigned getStyleCount();
int getStyleIndex(const std::string& name, bool addIfMissing = false);
int getColorIndex(const std::string& name, bool addIfMissing = false);
int getFontIndex(const std::string& name, bool addIfMissing = false);

int getElementFlag(const std::string& name, bool addIfMissing = false);
std::string getElementFlagName(unsigned flag);

void enumerateStyleIndices(std::function<void(const std::string&,unsigned)> callback);
void enumerateColorIndices(void (*cb)(const std::string&,unsigned));
void enumerateFontIndices(void (*cb)(const std::string&,unsigned));

void enumerateElementFlags(void (*cb)(const std::string&,unsigned));

void clearDynamicIndices();

};
};
