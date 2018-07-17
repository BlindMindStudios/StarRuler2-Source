import tabs.tabbar;
import elements.GuiBlueprint;
import elements.GuiMarkupText;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiButton;
import elements.GuiPanel;
import elements.MarkupTooltip;
import dialogs.MessageDialog;
import dialogs.QuestionDialog;
import util.design_export;
import icons;
from tabs.DesignEditorTab import createDesignEditorTab;
from community.DesignPage import createCommunityDesignPage;

class DesignElement : BaseGuiElement {
	GuiDownloadedBlueprint@ bp;
	GuiMarkupText@ description;
	GuiMarkupText@ curLine;
	const Design@ dsg;

	GuiButton@ downloadProfile;
	GuiButton@ downloadEmpire;
	GuiButton@ editButton;

	bool Hovered = false;

	DesignElement(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		updateAbsolutePosition();
		_();
	}

	DesignElement(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		updateAbsolutePosition();
		_();
	}

	void _() {
		 @bp = GuiDownloadedBlueprint(this, recti());
		 @description = GuiMarkupText(this, recti());
		 description.flexHeight = false;
		 @curLine = GuiMarkupText(this, recti());

		 @downloadEmpire = GuiButton(this, Alignment(Right-42, Top+8, Width=34, Height=34));
		 downloadEmpire.style = SS_IconButton;
		 downloadEmpire.setIcon(icons::Add);
		 setMarkupTooltip(downloadEmpire, locale::TT_DOWNLOAD_TO_EMPIRE, width=400);

		 @downloadProfile = GuiButton(this, Alignment(Right-42, Top+8+40, Width=34, Height=34));
		 downloadProfile.style = SS_IconButton;
		 downloadProfile.setIcon(icons::Import);
		 setMarkupTooltip(downloadProfile, locale::TT_DOWNLOAD_TO_PROFILE, width=400);

		 @editButton = GuiButton(this, Alignment(Right-42, Top+8+40+40, Width=34, Height=34));
		 editButton.style = SS_IconButton;
		 editButton.setIcon(icons::Edit);
		 editButton.allowOtherButtons = true;
		 setMarkupTooltip(editButton, locale::TT_DOWNLOAD_EDIT, width=400);
	}

	void load(int id) {
		bp.load(id);
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		if(bp !is null) {
			int unit = min(size.height-8, size.width-8);
			bp.rect = recti_area(vec2i(4,4), vec2i(unit, unit));
			description.rect = recti_area(vec2i(12+unit, 4), vec2i(size.width-unit-24-42, size.height-42));
			curLine.rect = recti_area(vec2i(12+unit, size.height-34), vec2i(size.width-unit-24-42, 30));
		}
	}

	void finishLoad(JSONNode@ root) {
		bp.finishLoad(root);
	}

	void update() {
		@dsg = bp.dsg;
		if(dsg !is null) {
			string author = bp.author;
			if(author.length > 20)
				author = author.substr(0,17)+"...";
			string specLine = format(locale::COMMUNITY_DESIGN_SPEC, toString(dsg.size,0),
					bbescape(author), bbescape(bp.ctime));

			string desc = bp.description;
			string name = dsg.name;
			uint len = 100;
			if(size.height > 150)
				len = 200;
			if(desc.length > len) {
				desc = desc.substr(0,len);
				desc += "...";
			}
			if(name.length > 36) {
				name = name.substr(0,36);
				name += "...";
			}

			description.text = format("[font=Medium][color=$1]$2[/color][/font]\n"
					"[b]$3[/b]\n[i][color=#aaa]$4[/color][/i]",
					toString(dsg.color), bbescape(name),
					specLine, bbescape(desc, true));

			curLine.text = format(locale::COMMUNITY_DESIGN_CURLINE, toString(bp.upvotes), toString(bp.commentCount));

			updateAbsolutePosition();

			downloadEmpire.disabled = dsg.hasFatalErrors();
			if(dsg.hasFatalErrors()) {
				string errors = locale::TT_DOWNLOAD_ERRORS;
				for(uint i = 0, cnt = dsg.errorCount; i < cnt; ++i)
					errors += "\n\n"+dsg.errors[i].text;
				setMarkupTooltip(downloadEmpire, errors, width=400);
			}
			else {
				setMarkupTooltip(downloadEmpire, locale::TT_DOWNLOAD_TO_EMPIRE, width=400);
			}
		}
	}

	void showPage(bool bg) {
		if(bg)
			newTab(createCommunityDesignPage(bp.designId));
		else
			browseTab(ActiveTab, createCommunityDesignPage(bp.designId), true);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				if(evt.caller is this)
					Hovered = true;
			break;
			case GUI_Mouse_Left:
				if(evt.caller is this)
					Hovered = false;
			break;
			case GUI_Clicked:
				if(evt.caller is downloadEmpire) {
					if(dsg !is null) {
						auto@ cls = playerEmpire.getDesignClass(locale::DOWNLOAD_DESIGN_CLASS, true);
						auto@ prev = playerEmpire.getDesign(dsg.name);
						if(prev !is null)
							playerEmpire.changeDesign(prev, dsg, cls);
						else
							playerEmpire.addDesign(cls, dsg);
						message(locale::SUCCESS_DOWNLOAD_TO_EMPIRE);
					}
					return true;
				}
				else if(evt.caller is downloadProfile) {
					string fname = path_join(modProfile["designs"], dsg.name+".design");
					write_design(dsg, fname);
					message(locale::SUCCESS_DOWNLOAD_TO_PROFILE);
					return true;
				}
				else if(evt.caller is editButton) {
					if(dsg !is null) {
						if(ctrlKey || evt.value == 2)
							newTab(createDesignEditorTab(dsg));
						else
							browseTab(ActiveTab, createDesignEditorTab(dsg), true);
					}
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source.isChildOf(this)) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0 || event.button == 2)
						return true;
				break;
				case MET_Button_Up:
					if(event.button == 0 || event.button == 2) {
						showPage(ctrlKey || event.button == 2);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		Color color;
		if(bp.dsg !is null)
			color = bp.dsg.color;
		if(bp.dsg !is dsg)
			update();

		skin.draw(SS_PatternBox, SF_Normal, AbsolutePosition, color);
		if(Hovered)
			skin.draw(SS_SubtleGlow, SF_Normal, AbsolutePosition, color);
		BaseGuiElement::draw();
	}
};
