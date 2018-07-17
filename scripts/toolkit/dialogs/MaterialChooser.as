import dialogs.Dialog;

enum MaterialChooserMode {
	MCM_All,
	MCM_Materials,
	MCM_Spritesheets,
};

MaterialChooser@ openMaterialChooser(MaterialChoiceCallback@ callback, MaterialChooserMode mode = MCM_All) {
	MaterialChooser@ matDialog = MaterialChooser(callback, null, mode);
	addDialog(matDialog);
	return matDialog;
}

interface MaterialChoiceCallback {
	void onMaterialChosen(const Material@ material, const string& id);
	void onSpriteSheetChosen(const SpriteSheet@ spritebank, uint spriteIndex, const string& id);
};

class MaterialChooser : Dialog {
	MaterialList@ materials;
	MaterialChoiceCallback@ matCallback;

	MaterialChooser(MaterialChoiceCallback@ userCallback, IGuiElement@ bind, MaterialChooserMode mode) {
		super(bind);
		width = 1024;
		height = 768;
		
		@materials = MaterialList(window, recti(4,4,1020,764), mode);
		@matCallback = userCallback;
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return false;
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		return false;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked && event.caller is materials) {
			if(materials.material !is null)
				matCallback.onMaterialChosen(materials.material, materials.identifier);
			else if(materials.spriteSheet !is null)
				matCallback.onSpriteSheetChosen(materials.spriteSheet, materials.spriteIndex, materials.identifier);
			closeDialog(this);
			return true;
		}
		return false;
	}
};

class MaterialList : BaseGuiElement {
	const Material@ material;
	const SpriteSheet@ spriteSheet;
	string identifier;
	uint spriteIndex;
	MaterialChooserMode mode;
	
	int scroll;
	int iconSize, margin;
	uint rowIconCount;
	
	vec2i hoverPos, clickPos;

	MaterialList(IGuiElement@ parent, const recti& position, MaterialChooserMode Mode) {
		super(parent, position);
		hoverPos = vec2i(-1,-1);
		
		iconSize = 96;
		margin = 2;
		mode = Mode;
		rowIconCount = (AbsolutePosition.width - (2 * margin) / (iconSize + margin));
	}
	
	vec2i absoluteToMatPos(int x, int y) const {
		return vec2i((x - (AbsolutePosition.topLeft.x + 4)) / (iconSize + margin),
			(y - (AbsolutePosition.topLeft.y + 4) + scroll) / (iconSize + margin));
	}

	void draw() {
		@material = null;
		@spriteSheet = null;
		vec2i at;
		
		int x = margin, y = margin - scroll;
		int height = AbsolutePosition.height;
		int row = 0, col = 0;
		
		//Draw each material
		uint count = getMaterialCount();
		if(mode == MCM_All || mode == MCM_Materials) {
			for(uint i = 0; i < count; ++i) {
				if(y + iconSize >= 0 && y - iconSize < height) {
					const Material@ mat = getMaterial(i);
					
					if(hoverPos.x == col && hoverPos.y == row) {
						@material = mat;
						identifier = getMaterialName(i);
						at = vec2i(x-iconSize/2,y-iconSize/2);
					}
					else {
						mat.draw(recti(x,y,x+iconSize,y+iconSize) + AbsolutePosition.topLeft, Color(0xffffffff), shader::BaseTexture);
					}
				}
					
				x += iconSize + margin;
				col += 1;
				if(x+iconSize > AbsolutePosition.width - margin) {
					x = margin;
					y += iconSize + margin;
					
					col = 0;
					row += 1; 
				}
			}
			
			//Start on a new line when we switch to sprite sheets
			if(col != 0) {
				x = margin;
				y += iconSize + margin;
				
				col = 0;
				row += 1;
			}
		}
		
		//Draw each sprite in each sprite sheet
		if(mode == MCM_All || mode == MCM_Spritesheets) {
			count = getSpriteSheetCount();
			for(uint i = 0; i < count; ++i) {
				const SpriteSheet@ sheet = getSpriteSheet(i);
				uint spriteCount = sheet.count;
				for(uint j = 0; j < spriteCount; ++j) {
					if(y + iconSize >= 0 && y - iconSize < height) {
						if(hoverPos.x == col && hoverPos.y == row) {
							at = vec2i(x-iconSize/2,y-iconSize/2);
							
							@spriteSheet = sheet;
							spriteIndex = j;
							identifier = getSpriteSheetName(i);
						}
						else {
							sheet.draw(j, recti_area(vec2i(x,y),vec2i(iconSize)) + AbsolutePosition.topLeft, shader::BaseTexture);
						}
					}
							
					x += iconSize + margin;
					col += 1;
					if(x+iconSize > AbsolutePosition.width - margin) {
						x = margin;
						y += iconSize + margin;
						
						col = 0;
						row += 1; 
					}
				}
			}
		}
		
		if(material !is null || spriteSheet !is null) {
			if(at.x < margin)
				at.x = margin;
			else if(at.x + (iconSize*2) > AbsolutePosition.width - margin)
				at.x = AbsolutePosition.width - margin - (iconSize*2);
				
			if(at.y < margin)
				at.y = margin;
			else if(at.y + (iconSize*2) > AbsolutePosition.height - margin)
				at.y = AbsolutePosition.height - margin - (iconSize*2);
			
			recti bgRect = recti(at.x - margin, at.y - margin, at.x + (iconSize*2) + margin, at.y + (iconSize*2) + margin) + AbsolutePosition.topLeft;
		
			if(material !is null) {
				drawRectangle(bgRect, Color(0x70a070ff));
				
				vec2i size = material.size;
				if(size.x > iconSize * 2 || size.y > iconSize * 2) {
					double factor = max(double(size.x), double(size.y)) / double(iconSize * 2);
					size /= factor;
				}
				
				material.draw(recti_area(at + vec2i(iconSize) - size * 0.5,size) + AbsolutePosition.topLeft, Color(0xffffffff), shader::BaseTexture);
				skin.getFont(FT_Normal).draw(bgRect, identifier, Color(0x000000ff), vertAlign = 0.0);
			}
			else if(spriteSheet !is null) {
				drawRectangle(bgRect, Color(0x70a070ff));
				
				vec2i size = spriteSheet.size;
				if(size.x > iconSize * 2 || size.y > iconSize * 2) {
					double factor = max(double(size.x), double(size.y)) / double(iconSize * 2);
					size /= factor;
				}
				
				spriteSheet.draw(spriteIndex, recti_area(at + vec2i(iconSize) - size * 0.5,size) + AbsolutePosition.topLeft, shader::BaseTexture);
				skin.getFont(FT_Normal).draw(bgRect, identifier, Color(0x000000ff), vertAlign = 0.0);
			}
		}
		
		BaseGuiElement::draw();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up) {
			vec2i pos = absoluteToMatPos(event.x, event.y);
			if(pos == clickPos) {
				emitClicked();
			}
			return true;
		}
		else if(event.type == MET_Button_Down) {
			clickPos = absoluteToMatPos(event.x, event.y);
			return true;
		}
		else if(event.type == MET_Moved) {
			hoverPos = absoluteToMatPos(event.x, event.y);
		}
		else if(event.type == MET_Scrolled) {
			scroll -= int(event.y * 32.0);
			if(scroll < 0)
				scroll = 0;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
};
