import tabs.Tab;
import elements.GuiText;
import elements.GuiPanel;
import elements.GuiTextbox;
import elements.GuiListbox;
import elements.GuiCheckbox;
import elements.GuiButton;
import dialogs.MaterialChooser;
import dialogs.ColorDialog;
import dialogs.InputDialog;
from tabs.tabbar import newTab, switchToTab;

Tab@ createParticlesTab() {
	return ParticlesTab();
}

class ParticlesTabCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = createParticlesTab();
		newTab(editor);
		switchToTab(editor);
	}
}

void init() {
	addConsoleCommand("particle_editor", ParticlesTabCommand());
}

class FlowEntry : GuiListText {
	ParticlesTab@ tab;
	ParticleFlow@ flow;
	uint index;

	FlowEntry(ParticlesTab@ Tab, ParticleFlow@ Flow, uint Index) {
		@tab = Tab;
		@flow = Flow;
		index = Index;
		
		string matName = Flow.materials[0];
		if(matName.length == 0)
			super("Empty Flow");
		else
			super(matName);
	}
	
	void onSelect() override {
		tab.switchToFlow(flow, index);
	}
};

class SizeChangeEvent : InputDialogCallback {
	ParticlesTab@ tab;
	uint index;
	
	SizeChangeEvent(ParticlesTab@ Tab, uint Index) {
		index = Index;
		@tab = Tab;
	}
	
	void inputCallback(InputDialog@ dialog, bool accepted) {
		tab.changeSize(index, dialog.getSpinboxInput(0));
	}

	void changeCallback(InputDialog@ dialog) {
		tab.changeSize(index, dialog.getSpinboxInput(0));
	}
};

class ColorChangeEvent : ColorDialogCallback {
	ParticlesTab@ tab;
	uint index;
	
	ColorChangeEvent(ParticlesTab@ Tab, uint Index) {
		index = Index;
		@tab = Tab;
	}
	
	void colorChosen(Color Col) {
		tab.changeColor(index, Col);
	}
};

class ColorEntry : GuiListElement {
	ParticlesTab@ tab;
	Color col;
	
	ColorEntry(Color Col, ParticlesTab@ Tab) {
		col = Col;
		@tab = Tab;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		Color solid = col;
		solid.a = 255;
		drawRectangle(absPos, solid, col, col, solid);
	}
};

class onMatPicked : MaterialChoiceCallback {	
	ParticlesTab@ tab;
	int editIndex;
	
	onMatPicked(ParticlesTab@ editor, int EditIndex = -1) {
		editIndex = EditIndex;
		@tab = editor;
	}

	void onMaterialChosen(const Material@ material, const string& id) {
		if(editIndex < 0)
			tab.addFlowMaterial(id);
		else
			tab.setFlowMaterial(editIndex, id);
	}
	
	void onSpriteSheetChosen(const SpriteSheet@ spritebank, uint spriteIndex, const string& id) {}
};

dictionary changedSystems;

class ParticlesTab : Tab {
	vec2i prevSize;
	RenderTarget@ rt;
	ParticleSystem@ ps;
	ParticleFlow@ flow;
	uint flowIndex = 0;
	int delFlowIndex = -1;
	Node@ node;
	
	GuiTextbox@ psName;
	GuiButton@ savePS, loadPS;
	GuiListbox@ flows;
	GuiButton@ addFlow, delFlow, copyFlow;
	
	GuiPanel@ flowData;
	
	GuiListbox@ flowMats;
	GuiButton@ addMat, delMat, editMat;
	GuiTextbox@ flowScaleMin, flowScaleMax, flowLifeMin, flowLifeMax, flowRate;
	GuiTextbox@ flowStart, flowEnd, flowConeMin, flowConeMax, flowSpeedMin, flowSpeedMax, flowDistMin, flowDistMax;
	GuiCheckbox@ flowFlat;
	GuiTextbox@ flowStartSound;
	GuiListbox@ flowCols, flowSizes;
	GuiButton@ addCol, delCol, addSize, delSize;
	
	int nextTabIndex = 0;
	void prepTab(IGuiElement@ ele) {
		ele.tabIndex = nextTabIndex++;
	}

	ParticlesTab() {
		super();
		title = "Particle Editor";
		@psName = GuiTextbox(this, recti(4, 4, 220, 28));
		@savePS = GuiButton(this, recti(224, 4, 300, 28), "Save");
		@loadPS = GuiButton(this, recti(304, 4, 380, 28), "Load");
		
		@flows = GuiListbox(this, Alignment(Left+4, Top+32, Left+220, Bottom-304));
		@addFlow = GuiButton(this, Alignment(Left+4, Bottom-260, Left+108, Bottom-220), "New Flow");
		@delFlow = GuiButton(this, Alignment(Left+112, Bottom-260, Left+220, Bottom-220), "Remove");
		@copyFlow = GuiButton(this, Alignment(Left+4, Bottom-300, Left+220, Bottom-264), "Duplicate");
		
		@flowData = GuiPanel(this, Alignment(Left+4, Bottom-216, Right+0, Bottom+0));
		
		@flowMats = GuiListbox(flowData, Alignment(Left+0, Top+0, Left+220, Bottom-60));
		@delMat = GuiButton(flowData, Alignment(Left+0, Bottom-56, Left+108, Bottom-32), "Remove");
		@editMat = GuiButton(flowData, Alignment(Left+112, Bottom-56, Left+220, Bottom-32), "Change");
		@addMat = GuiButton(flowData, Alignment(Left+0, Bottom-28, Left+220, Bottom-4), "Add Material");
		
		GuiText(flowData, Alignment(Left+224, Top+0, Left+300, Top+24), "Scale:");
		@flowScaleMin = GuiTextbox(flowData, Alignment(Left+270, Top+0, Left+370, Top+24));
		prepTab(flowScaleMin);
		@flowScaleMax = GuiTextbox(flowData, Alignment(Left+374, Top+0, Left+474, Top+24));
		prepTab(flowScaleMax);
		
		GuiText(flowData, Alignment(Left+224, Top+26, Left+300, Top+52), "Life:");
		@flowLifeMin = GuiTextbox(flowData, Alignment(Left+270, Top+26, Left+370, Top+52));
		prepTab(flowLifeMin);
		@flowLifeMax = GuiTextbox(flowData, Alignment(Left+374, Top+26, Left+474, Top+52));
		prepTab(flowLifeMax);
		
		GuiText(flowData, Alignment(Left+224, Top+54, Left+300, Top+80), "Play:");
		@flowStart = GuiTextbox(flowData, Alignment(Left+270, Top+54, Left+370, Top+80));
		flowStart.tooltip = "Time offset (seconds) to begin playing this flow";
		prepTab(flowStart);
		@flowEnd = GuiTextbox(flowData, Alignment(Left+374, Top+54, Left+474, Top+80));
		flowEnd.tooltip = "Time offset (seconds) to stop playing this flow";
		prepTab(flowEnd);
		
		GuiText(flowData, Alignment(Left+224, Top+82, Left+300, Top+108), "Rate:");
		@flowRate = GuiTextbox(flowData, Alignment(Left+270, Top+82, Left+370, Top+108));
		prepTab(flowRate);
		
		GuiText(flowData, Alignment(Left+224, Top+110, Left+300, Top+136), "Cone:");
		@flowConeMin = GuiTextbox(flowData, Alignment(Left+270, Top+110, Left+370, Top+136));
		prepTab(flowConeMin);
		@flowConeMax = GuiTextbox(flowData, Alignment(Left+374, Top+110, Left+474, Top+136));
		prepTab(flowConeMax);
		
		GuiText(flowData, Alignment(Left+224, Top+138, Left+300, Top+164), "Speed:");
		@flowSpeedMin = GuiTextbox(flowData, Alignment(Left+270, Top+138, Left+370, Top+164));
		prepTab(flowSpeedMin);
		@flowSpeedMax = GuiTextbox(flowData, Alignment(Left+374, Top+138, Left+474, Top+164));
		prepTab(flowSpeedMax);
		
		GuiText(flowData, Alignment(Left+224, Top+166, Left+300, Top+192), "Dist:");
		@flowDistMin = GuiTextbox(flowData, Alignment(Left+270, Top+166, Left+370, Top+192));
		flowDistMin.tooltip = "Minimum distance to spawn particles away from the center.";
		prepTab(flowDistMin);
		@flowDistMax = GuiTextbox(flowData, Alignment(Left+374, Top+166, Left+474, Top+192));
		prepTab(flowDistMax);
		
		@flowFlat = GuiCheckbox(flowData, Alignment(Left+244, Top+194, Left+474, Top+220), "Flat");
		prepTab(flowFlat);
		
		@flowCols = GuiListbox(flowData, Alignment(Left+478, Top, Left+550, Bottom-36));
		flowCols.DblClickConfirm = true;
		flowCols.Required = true;
		@flowSizes = GuiListbox(flowData, Alignment(Left+554, Top, Left+654, Bottom-36));
		flowSizes.DblClickConfirm = true;
		flowSizes.Required = true;
		
		@addCol = GuiButton(flowData, Alignment(Left+478, Bottom-32, Left+512, Bottom-4), "Add");
		@delCol = GuiButton(flowData, Alignment(Left+516, Bottom-32, Left+550, Bottom-4), "Del");
		
		@addSize = GuiButton(flowData, Alignment(Left+554, Bottom-32, Left+602, Bottom-4), "Add");
		@delSize = GuiButton(flowData, Alignment(Left+606, Bottom-32, Left+654, Bottom-4), "Del");
		
		GuiText(flowData, Alignment(Left+660,Top,Left+720,Top+26), "Sound");
		@flowStartSound = GuiTextbox(flowData, Alignment(Left+724,Top,Left+824,Top+26));
		
		loadParticleSystem("ImpactFlare");
	}
	
	void switchToFlow(ParticleFlow@ Flow, uint Index) {
		@flow = Flow;
		flowIndex = Index;
		if(flow is null) {
			flowData.visible = false;
		}
		else {
			flows.selected = Index;
			flowData.visible = true;
			flowMats.clearItems();
			for(uint i = 0, cnt = flow.materialCount; i < cnt; ++i)
				flowMats.addItem(flow.materials[i]);
			flowCols.clearItems();
			for(uint i = 0, cnt = max(flow.colorCount,1); i < cnt; ++i)
				flowCols.addItem(ColorEntry(flow.colors[i], this));
			flowSizes.clearItems();
			for(uint i = 0, cnt = max(flow.sizeCount,1); i < cnt; ++i)
				flowSizes.addItem(toString(flow.sizes[i], 2));
			flowScaleMin.text = toString(flow.scale.min, 2);
			flowScaleMax.text = toString(flow.scale.max, 2);
			flowLifeMin.text = toString(flow.life.min, 2);
			flowLifeMax.text = toString(flow.life.max, 2);
			flowStart.text = toString(flow.start, 2);
			flowEnd.text = toString(flow.end, 2);
			flowRate.text = toString(flow.rate, 2);
			flowConeMin.text = toString(flow.cone.min, 2);
			flowConeMax.text = toString(flow.cone.max, 2);
			flowSpeedMin.text = toString(flow.speed.min, 2);
			flowSpeedMax.text = toString(flow.speed.max, 2);
			flowDistMin.text = toString(flow.spawnDist.min, 2);
			flowDistMax.text = toString(flow.spawnDist.max, 2);
			flowStartSound.text = flow.soundStart;
			flowFlat.checked = flow.flat;
		}
	}
	
	void parseFlowData() {
		flow.scale.min = toDouble(flowScaleMin.text);
		flow.scale.max = toDouble(flowScaleMax.text);
		flow.life.min = toDouble(flowLifeMin.text);
		flow.life.max = toDouble(flowLifeMax.text);
		flow.start = toDouble(flowStart.text);
		flow.end = toDouble(flowEnd.text);
		flow.rate = toDouble(flowRate.text);
		flow.cone.min = toDouble(flowConeMin.text);
		flow.cone.max = toDouble(flowConeMax.text);
		flow.speed.min = toDouble(flowSpeedMin.text);
		flow.speed.max = toDouble(flowSpeedMax.text);
		flow.spawnDist.min = toDouble(flowDistMin.text);
		flow.spawnDist.max = toDouble(flowDistMax.text);
		flow.soundStart = flowStartSound.text;
		flow.flat = flowFlat.checked;
		postEdit();
	}
	
	void createFlow() {
		if(ps is null)
			return;
		ParticleFlow@ Flow = ps.createFlow();
		flows.addItem(FlowEntry(this, Flow, ps.flowCount-1));
		switchToFlow(Flow, ps.flowCount-1);
	}
	
	void duplicateFlow(uint index) {
		if(ps is null)
			return;
		ParticleFlow@ Flow = ps.duplicateFlow(ps.flows[index]);
		flows.addItem(FlowEntry(this, Flow, ps.flowCount-1));
		switchToFlow(Flow, ps.flowCount-1);
	}
	
	void changeColor(uint index, Color col) {
		if(flow is null)
			return;
		flow.colors[index] = col;
		flowCols.setItem(index, ColorEntry(col, this));
		postEdit();
	}
	
	void changeSize(uint index, double size) {
		if(flow is null)
			return;
		flow.sizes[index] = size;
		flowSizes.setItem(index, toString(size, 2));
		postEdit();
	}
	
	void addFlowMaterial(const string &in matName) {
		if(flow is null)
			return;
		flow.addMaterial(matName);
		flowMats.addItem(matName);
		flows.setItem(flowIndex, FlowEntry(this, flow, flowIndex));
		postEdit();
	}
	
	void setFlowMaterial(uint index, const string &in matName) {
		if(flow is null)
			return;
		flow.materials[index] = matName;
		flowMats.setItem(index, matName);
		flows.setItem(flowIndex, FlowEntry(this, flow, flowIndex));
		postEdit();
	}
	
	void loadParticleSystem(const string &in name) {
		ParticleSystem@ psys;
		if(!changedSystems.get(name, @psys))
			@ps = getParticleSystem(name).duplicate();
		else
			@ps = psys;
		flows.clearItems();
		flowData.visible = false;
			
		if(ps !is null) {
			psName.text = name;
			
			for(uint i = 0, cnt = ps.flowCount; i < cnt; ++i) {
				flows.addItem(FlowEntry(this, ps.flows[i], i));
			}
		}
		else {
			psName.text = "";
		}
		
		postEdit();
	}
	
	void postEdit() {
		if(node !is null)
			node.markForDeletion();
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is addFlow) {
				createFlow();
				return true;
			}
			else if(event.caller is delFlow) {
				if(flows.selected >= 0 && uint(flows.selected) < flows.itemCount && flows.itemCount > 1) {
					delFlowIndex = flows.selected;
					postEdit();
				}
				return true;
			}
			else if(event.caller is copyFlow) {
				if(flows.selected >= 0 && uint(flows.selected) < flows.itemCount) {
					duplicateFlow(uint(flows.selected));
				}
				return true;
			}
			else if(event.caller is addMat) {
				if(flow !is null)
					openMaterialChooser(onMatPicked(this), MCM_Materials);
				return true;
			}
			else if(event.caller is delMat) {
				if(flow !is null) {
					if(flowMats.selected >= 0 && uint(flowMats.selected) < flowMats.itemCount) {
						flow.removeMaterial(flowMats.selected);
						flowMats.removeItem(flowMats.selected);
					}
				}
				return true;
			}
			else if(event.caller is addCol) {
				if(flow !is null) {
					int index = flow.colorCount;
					flow.addColor(index, flow.colors[index-1]);
					if(index == 0)
						flow.addColor(index, flow.colors[index-1]);
					flowCols.addItem(ColorEntry(flow.colors[index], this));
					postEdit();
				}
				return true;
			}
			else if(event.caller is delCol) {
				if(flow !is null && flowCols.selected >= 0 && uint(flowCols.selected) < flowCols.itemCount) {
					flow.removeColor(flowCols.selected);
					flowCols.removeItem(flowCols.selected);
					postEdit();
				}
				return true;
			}
			else if(event.caller is addSize) {
				if(flow !is null) {
					int index = flow.sizeCount;
					flow.addSize(index, flow.sizes[index-1]);
					if(index == 0)
						flow.addSize(index, flow.sizes[index-1]);
					flowSizes.addItem(toString(flow.sizes[index], 2));
					postEdit();
				}
				return true;
			}
			else if(event.caller is delSize) {
				if(flow !is null && flowSizes.selected >= 0 && uint(flowSizes.selected) < flowSizes.itemCount) {
					flow.removeSize(flowSizes.selected);
					flowSizes.removeItem(flowSizes.selected);
					postEdit();
				}
				return true;
			}
			else if(event.caller is editMat) {
				if(flow !is null && flowMats.selected >= 0)
					openMaterialChooser(onMatPicked(this, flowMats.selected), MCM_Materials);
				return true;
			}
			else if(event.caller is savePS) {
				string sysName = psName.text;
				if(sysName.length > 0) {
					if(ps !is null)
						ps.save("data/particles/" + sysName + ".ps");
					changedSystems.set(sysName, @ps);
				}
				else {
					sound::error.play(priority=true);
				}
				return true;
			}
			else if(event.caller is loadPS) {
				loadParticleSystem(psName.text);
				return true;
			}
		}
		else if(event.type == GUI_Confirmed) {
			if(event.caller is flowCols) {
				ColorDialog(ColorChangeEvent(this, event.value), null, flow.colors[event.value]);
				return true;
			}
			else if(event.caller is flowSizes) {
				InputDialog@ dialog = InputDialog(SizeChangeEvent(this, event.value), null);
				dialog.addSpinboxInput("Size", flow.sizes[event.value], 0.1, -1000.0, 1000.0, 3);
				addDialog(dialog);
				return true;
			}
		}
		else if(event.type == GUI_Changed) {
			if(event.caller.isChildOf(flowData)) {
				parseFlowData();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
	
	void draw() {
		vec2i size = AbsolutePosition.size;
		if(size != prevSize) {
			prevSize = size;
			if(rt !is null) {
				rt.size = size;
			}
			else {
				@rt = RenderTarget(size);
				rt.camera.yaw(pi * 0.45, true);
				rt.camera.pitch(pi * 0.1, true);
			}
		}
		
		if((node is null || node.parent is null) && rt !is null) {
			if(delFlowIndex >= 0) {
				ps.removeFlow(delFlowIndex);
				flows.removeItem(delFlowIndex);
				switchToFlow(ps.flows[delFlowIndex], delFlowIndex);
				delFlowIndex = -1;
			}
			@node = playParticleSystem(ps, vec3d(), 20.f, rt.node);
		}
		
		if(rt !is null) {
			rt.animate(frameLength);
			rt.draw(AbsolutePosition);
		}
		
		Tab::draw();
	}
}
