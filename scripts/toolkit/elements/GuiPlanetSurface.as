#section disable menu
import elements.BaseGuiElement;
import elements.MarkupTooltip;
import planets.PlanetSurface;
import biomes;
from traits import getTraitID;

export GuiPlanetSurface, drawHoverBuilding;

class GuiPlanetSurface : BaseGuiElement {
	PlanetSurface@ surface;
	Object@ obj;
	vec2i hovered(-1, -1);
	int maxSize = 32;
	bool showTooltip = true;
	bool showHoverBiome = true;
	DynamicTexture@ surfTex;
	const Material@ developedMat = material::DevelopedTile;
	double horizAlign = 0.5;
	double vertAlign = 0.5;

	GuiPlanetSurface(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		_GuiPlanetSurface();
	}

	GuiPlanetSurface(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		_GuiPlanetSurface();
	}

	void _GuiPlanetSurface() {
		MarkupTooltip tt(400, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = true;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	string get_tooltip() {
		if(showTooltip && hovered.x != -1 && hovered.y != -1) {
			SurfaceBuilding@ bld = surface.getBuilding(hovered.x, hovered.y);
			if(bld is null)
				return "";

			string output = bld.getTooltip(obj);
			if(bld.completion < 1.f) {
				output += format("\n\n"+locale::BUILDING_CONSTRUCTING_PCT,
						toString(bld.completion * 100.f, 0));
			}

			if(bld.disabled)
				output += format("\n\n[color=#ff0000]$1[/color]", locale::BUILDING_DISABLED_POP);
			return output;
		}
		return "";
	}

	vec2i getGridSize() {
		recti area = AbsolutePosition.aspectAligned(float(surface.size.width)
						/ float(surface.size.height), horizAlign, vertAlign);
		int space = min(int(float(area.width) / float(surface.size.width)), maxSize);
		return vec2i(space, space);
	}

	vec2i getTilePosition(const vec2i& tile) {
		recti area = AbsolutePosition.aspectAligned(float(surface.size.width)
						/ float(surface.size.height));
		int space = min(int(float(area.width) / float(surface.size.width)), maxSize);
		area += vec2i((area.width - space*surface.size.width) / 2,
					(area.height - space*surface.size.height) / 2);

		return vec2i(space * tile.x, space * tile.y) + area.topLeft;
	}

	vec2i getOffsetItem(const vec2i& offset) {
		if(surface is null || surface.size.x == 0 || surface.size.y == 0)
			return vec2i(-1, -1);

		recti area = AbsolutePosition.aspectAligned(float(surface.size.width)
						/ float(surface.size.height), horizAlign, vertAlign) - AbsolutePosition.topLeft;
		int space = min(int(float(area.width) / float(surface.size.width)), maxSize);
		area += vec2i((area.width - space*surface.size.width) / 2,
					(area.height - space*surface.size.height) / 2);

		if(offset.x < area.topLeft.x || offset.x > area.botRight.x)
			return vec2i(-1, -1);
		if(offset.y < area.topLeft.y || offset.y > area.botRight.y)
			return vec2i(-1, -1);

		vec2i pos;
		pos.x = (offset.x - area.topLeft.x) / space;
		pos.y = (offset.y - area.topLeft.y) / space;

		if(pos.x >= int(surface.size.width) || pos.y >= int(surface.size.height))
			return vec2i(-1, -1);

		return pos;
	}
	
	vec2u prevSurfSize;
	void drawSurfaceData() {
		@surfTex = DynamicTexture();
		vec2u size = vec2u(surface.size);
		Image@ img = Image(size, 4);
		prevSurfSize = size;
		if(img is null) {
			error("Bad image");
			return;
		}

		renderSurfaceData(obj, surface, img);
		
		@surfTex.image[0] = img;
		@surfTex.material.texture1 = material::GuiPlanetSurface.texture0;
		@surfTex.material.texture2 = material::GuiPlanetSurface.texture1;
		@surfTex.material.shader = shader::PlanetSurfaceGeneric;
	}

	void remove() override {
		@surfTex = null;
		BaseGuiElement::remove();
	}

	bool pressed = false;
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Moved: {
					vec2i mouse = vec2i(event.x, event.y);
					vec2i offset = mouse - AbsolutePosition.topLeft;
					vec2i prevHovered = hovered;
					hovered = getOffsetItem(offset);

					if(hovered != prevHovered && Tooltip !is null)
						Tooltip.update(skin, this);
				} break;
				case MET_Button_Down:
					if(surface.isValidPosition(hovered)) {
						pressed = true;
						return true;
					}
				break;
				case MET_Button_Up: {
					if(pressed && surface.isValidPosition(hovered)) {
						emitClicked(event.button);
						pressed = false;
						return true;
					}
				}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Mouse_Left)
			hovered = vec2i(-1, -1);
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		auto size = surface.size;
		if(surface is null || size.x == 0 || size.y == 0)
			return;
		
		if(surfTex is null || size != prevSurfSize)
			drawSurfaceData();

		recti area = AbsolutePosition.aspectAligned(float(size.width)
						/ float(size.height), horizAlign, vertAlign);
		int space = min(int(float(area.width) / float(size.width)), maxSize);
		area += vec2i((area.width - space * size.width) / 2,
					(area.height - space * size.height) / 2);

		recti surfArea = recti_area(area.topLeft, vec2i(space * size.width, space * size.height));

		preparePlanetShader(obj);
		if(surfTex.stream()) {
			vec2i tl = surfArea.topLeft;
			vec2i br = surfArea.botRight;
			vec2i bl(tl.x, br.y);
			vec2i tr(br.x, tl.y);

			vec2i tc(tl.x+surfArea.width/2, tl.y);
			vec2i bc(tc.x, br.y);

			drawPolygonStart(PT_Quads, 2, surfTex.material);
			drawPolygonPoint(tl, vec2f(0.f,0.f), Color(0x00000000));
			drawPolygonPoint(tc, vec2f(0.5f,0.f), Color(0xffffffff));
			drawPolygonPoint(bc, vec2f(0.5f,1.f), Color(0xffffffff));
			drawPolygonPoint(bl, vec2f(0.f,1.f), Color(0x00000000));

			drawPolygonPoint(tc, vec2f(0.5f,0.f), Color(0x00000000));
			drawPolygonPoint(tr, vec2f(1.f,0.f), Color(0xffffffff));
			drawPolygonPoint(br, vec2f(1.f,1.f), Color(0xffffffff));
			drawPolygonPoint(bc, vec2f(0.5f,1.f), Color(0x00000000));
			drawPolygonEnd();
		}
		/*surfTex.draw(surfArea, Color());*/

		if(obj !is null && obj.owner.hasTrait(verdantTrait))
			@developedMat = material::GrownTile;
		else
			@developedMat = material::DevelopedTile;
		bool hasDevelopment = obj is null || obj.owner is null || obj.owner.HasPopulation != 0;
		
		recti pos = recti_area(area.topLeft, vec2i(space, space));
		vec2i spaceX(space, 0);
		vec2i spaceY(-space * size.width, space);

		for(uint y = 0, height = size.height; y < height; ++y) {
			for(uint x = 0, width = size.width; x < width; ++x) {
				const Biome@ biome = surface.getBiome(x, y);
				uint8 flags = surface.getFlags(x, y);

				//Draw biome background
				//biome.tile.draw(pos);

				//Draw building
				SurfaceBuilding@ bld = surface.getBuilding(x, y);
				if(bld !is null) {
					Color col(0xffffffff);
					if(bld.disabled)
						col.r = 0xff;
					col.a = (bld.completion * 0xbf) + 0x40;

					if(bld.type.size.x == 1 && bld.type.size.y == 1) {
						bld.type.sprite.draw(pos, col);

						//Draw developed border
						if(flags & SuF_Usable != 0 && hasDevelopment)
							developedMat.draw(pos.padded(-1));
						if(bld.disabled)
							drawRectangle(pos, Color(0xff000040));
					}
					else {
						int relX = x - bld.position.x;
						int relY = y - bld.position.y;
						vec2u center = bld.type.getCenter();
						if(relX == int(bld.type.size.x - center.x - 1)
								&& relY == int(bld.type.size.y - center.y - 1)) {
							vec2i ssize(bld.type.size.x * space, bld.type.size.y * space);
							recti spos = recti_area(pos.topLeft - ssize + vec2i(space,space), ssize);
							bld.type.sprite.draw(spos, col);
						}

						//Draw undeveloped overlay
						if(hasDevelopment || bld.disabled) {
							for(uint rx = 0; rx < bld.type.size.x; ++rx) {
								uint px = bld.position.x - center.x + rx;
								for(uint ry = 0; ry < bld.type.size.y; ++ry) {
									uint py = bld.position.y - center.y + ry;
									uint8 tileFlags = surface.getFlags(px, py);
									if(bld.disabled) {
										drawRectangle(recti_area(area.topLeft + vec2i(space * px, space * py),
												vec2i(space, space)), Color(0xff000040));
									}
									else if(tileFlags & SuF_Usable == 0 && bld.type.getMaintenanceFor(surface.getBiome(px, py)) != 0 && hasDevelopment) {
										drawRectangle(recti_area(area.topLeft + vec2i(space * px, space * py),
												vec2i(space, space)), Color(0x80800040));
									}
								}
							}
						}
					}
				}
				else {
					//Draw developed border
					if(flags & SuF_Usable != 0 && hasDevelopment)
						developedMat.draw(pos.padded(-1));
				}

				pos += spaceX;
			}
			pos += spaceY;
		}

		if(showHoverBiome && hovered.x >= 0 && hovered.y >= 0 && surface.getBuilding(hovered.x, hovered.y) is null) {
			auto@ biome = surface.getBiome(hovered.x, hovered.y);
			if(biome !is null) {
				recti tilePos = recti_area(area.topLeft + vec2i(space * hovered.x, space * hovered.y), vec2i(space, space));

				const Font@ ft = skin.getFont(FT_Normal);
				string txt;
				if(biome.isVoid || !hasDevelopment) {
					txt = biome.name;
				}
				else if(obj !is null && obj.owner.hasTrait(verdantTrait)) {
					if(surface.getFlags(hovered.x, hovered.y) & SuF_Usable != 0)
						txt = format(locale::TILE_BIOME_GROWN, biome.name);
					else
						txt = format(locale::TILE_BIOME_UNGROWN, biome.name);
				}
				else {
					if(surface.getFlags(hovered.x, hovered.y) & SuF_Usable != 0)
						txt = format(locale::TILE_BIOME_DEVELOPED, biome.name);
					else
						txt = format(locale::TILE_BIOME_UNDEVELOPED, biome.name);
				}

				material::DevelopedTile.draw(tilePos, Color(0x000000ff));
				ft.draw(pos=surfArea.padded(4),
						text=txt, horizAlign=1.0, vertAlign=1.0,
						stroke=colors::Black, color=biome.color.interpolate(colors::White, 0.5));
			}
		}

		BaseGuiElement::draw();
	}
};

void drawHoverBuilding(Planet& pl, const Skin@ skin, const BuildingType@ type, const vec2i& mousePos, const vec2i&in gridPos, GuiPlanetSurface@ surface = null) {
	vec2i gridSize(26, 26);
	if(surface !is null)
		gridSize = surface.getGridSize();

	vec2i pos;
	if(surface is null || gridPos.x == -1 || gridPos.y == -1) {
		//Draw at mouse position
		pos = mousePos;
		pos.x -= gridSize.x / 2;
		pos.y -= gridSize.y / 2;
	}
	else {
		//Draw on surface
		pos = surface.getTilePosition(gridPos);
	}

	//Draw each tile
	double costFactor = pl.owner.BuildingCostFactor;
	int buildCost = ceil(double(type.baseBuildCost) * costFactor);
	int maintainCost = type.baseMaintainCost;

	vec2i center = vec2i(type.getCenter());
	vec2i bldSize = vec2i(gridSize.x * type.size.x, gridSize.y * type.size.y);

	if(type.size.x > 0 || type.size.y > 0) {
		type.sprite.draw(recti_area(pos - vec2i(center.x * gridSize.x, center.y * gridSize.y), bldSize));
	}
	for(int y = 0; y < int(type.size.y); ++y) {
		for(int x = 0; x < int(type.size.x); ++x) {
			recti tpos = recti_area(pos - vec2i((center.x - x) * gridSize.x, (center.y - y) * gridSize.y), gridSize);
			Color color(0x00000080);

			if(surface !is null && gridPos.x != -1 && gridPos.y != -1) {
				vec2i rpos = gridPos - (center - vec2i(x, y));
				if(rpos.x < 0 || rpos.y < 0
					|| uint(rpos.x) >= surface.surface.size.x
					|| uint(rpos.y) >= surface.surface.size.y)
				{
					buildCost += ceil(double(type.tileBuildCost) * costFactor);
					maintainCost += type.tileMaintainCost;
					color = Color(0xff000080);
				}
				else {
					if(!surface.surface.getBiome(rpos.x, rpos.y).buildable) {
						color = Color(0xff0000ff);
					}
					else if(surface.surface.getFlags(rpos.x, rpos.y) & SuF_Usable == 0) {
						auto@ biome = surface.surface.getBiome(rpos.x, rpos.y);
						
						double bld = type.tileBuildCost * biome.buildCost * costFactor;
						for(uint n = 0, ncnt = type.buildAffinities.length; n < ncnt; ++n) {
							auto@ aff = type.buildAffinities[n];
							if(aff.biome is biome)
								bld *= aff.factor;
						}

						double mnt = type.tileMaintainCost;
						for(uint n = 0, ncnt = type.maintainAffinities.length; n < ncnt; ++n) {
							auto@ aff = type.maintainAffinities[n];
							if(aff.biome is biome)
								mnt *= aff.factor;
						}

						buildCost += ceil(bld);
						maintainCost += ceil(mnt);

						if(bld > type.tileBuildCost)
							color = Color(0xff006180);
						else if(bld != 0)
							color = Color(0xffc80080);
					}
				
					SurfaceBuilding@ bld = surface.surface.getBuilding(rpos.x, rpos.y);
					if(bld !is null) {
						if(bld.type.civilian)
							color = Color(0xff9d0080);
						else
							color = Color(0xff000080);
					}
				}
			}
			if(type.size.y == 1 && type.size.x == 1) {
				type.sprite.draw(tpos.padded(2), color);
			}
			else {
				color.a = 0x40;
				drawRectangle(tpos, color);
			}
		}
	}

	if(buildCost != 0 || maintainCost != 0) {
		const Font@ small = skin.getFont(FT_Normal);
		string cost = formatMoney(buildCost, maintainCost);
		
		vec2i corner = pos-vec2i(center.x*gridSize.x, center.y*gridSize.y);
		small.draw(pos=recti_area(corner-vec2i(300,0), vec2i(600+bldSize.x,bldSize.y)),
			text=cost, color=Color(0xffffffff), stroke=colors::Black, horizAlign=0.5, vertAlign=0.5);
	}
}

uint verdantTrait = uint(-1);
void init() {
	verdantTrait = getTraitID("Verdant");
}
