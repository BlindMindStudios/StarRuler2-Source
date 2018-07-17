import tabs.Tab;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiButton;

from tabs.tabbar import newTab, switchToTab;

Tab@ createNameGeneratorTab() {
	return NameGeneratorTab();
}

class NameGeneratorCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = createNameGeneratorTab();
		newTab(editor);
		switchToTab(editor);
	}
};

void init() {
	addConsoleCommand("name_generator", NameGeneratorCommand());
}

class NameGeneratorTab : Tab {
	NameGenerator gen;

	GuiTextbox@ filename;
	GuiButton@ saveButton;
	GuiButton@ loadButton;

	GuiText@ mutationHeader;
	GuiTextbox@ mutationChance;
	GuiText@ nameCount;

	GuiTextbox@ nameBox;
	GuiButton@ generateButton;
	GuiButton@ addButton;

	NameGeneratorTab() {
		super();
		title = "Name Generator";
		gen.read("data/system_names.txt");

		@filename = GuiTextbox(this, recti(4, 4, 404, 30), "data/system_names.txt");
		@loadButton = GuiButton(this, recti(410, 4, 510, 30), locale::LOAD);
		@saveButton = GuiButton(this, recti(516, 4, 616, 30), locale::SAVE);

		@mutationHeader = GuiText(this, recti(4, 34, 204, 60), locale::MUTATION_CHANCE);
		@mutationChance = GuiTextbox(this, recti(210, 34, 310, 60), "0.00");
		@nameCount = GuiText(this, recti(316, 34, 610, 60));
		nameCount.horizAlign = 1.0;
		nameCount.text = format(locale::NAME_COUNT, toString(gen.nameCount));

		@nameBox = GuiTextbox(this, recti(4, 80, 404, 106));
		@generateButton = GuiButton(this, recti(410, 80, 510, 106), locale::GENERATE);
		@addButton = GuiButton(this, recti(516, 80, 616, 106), locale::ADD);

		nameBox.text = gen.generate();

		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Clicked:
				if(event.caller is loadButton) {
					gen.clear();
					gen.read(filename.text);
					nameCount.text = format(locale::NAME_COUNT, toString(gen.nameCount));
					nameBox.text = gen.generate();
					mutationChance.text = toString(gen.mutationChance, 2);
				}
				else if(event.caller is saveButton) {
					gen.write(filename.text);
				}
				else if(event.caller is generateButton) {
					nameBox.text = gen.generate();
				}
				else if(event.caller is addButton) {
					if(!gen.hasName(nameBox.text))
						gen.addName(nameBox.text);
					nameBox.text = gen.generate();
					nameCount.text = format(locale::NAME_COUNT, toString(gen.nameCount));
				}
			break;
			case GUI_Changed:
				if(event.caller is mutationChance) {
					gen.mutationChance = toFloat(mutationChance.text);
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
}
