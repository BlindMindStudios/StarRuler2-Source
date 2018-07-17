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
from tabs.WikiTab import LinkableMarkupText;

class CommunityDesign : Tab, QuestionDialogCallback {
	GuiDownloadedBlueprint@ bp;
	GuiText@ titleBox;
	GuiPanel@ headerPanel;
	GuiMarkupText@ header;
	GuiText@ linkTip;
	const Design@ dsg;

	GuiButton@ backButton;
	GuiButton@ downloadProfile;
	GuiButton@ downloadEmpire;
	GuiButton@ editButton;

	GuiButton@ votesButton;
	GuiButton@ commentsButton;

	GuiButton@ deleteButton;

	GuiSkinElement@ commentsBox;
	GuiPanel@ commentsPanel;
	GuiMarkupText@ comments;

	GuiTextbox@ commentText;
	GuiButton@ commentSubmit;

	WebData@ waitReload;

	CommunityDesign(int id) {
		@bp = GuiDownloadedBlueprint(this, Alignment().fill());
		bp.showStats = true;
		bp.padding = recti(0,136,0,0);
		bp.load(id);
		bp.bp.hoverArcs = true;

		@backButton = GuiButton(this, Alignment(Left+8, Top+8, Left+144, Height=50), locale::BACK);
		backButton.buttonIcon = icons::Back;

		@downloadEmpire = GuiButton(this, Alignment(Right-208-260, Top+8, Right-264, Height=38), locale::DOWNLOAD_TO_EMPIRE);
		downloadEmpire.setIcon(icons::Add);
		setMarkupTooltip(downloadEmpire, locale::TT_DOWNLOAD_TO_EMPIRE, width=400);

		@downloadProfile = GuiButton(this, Alignment(Right-208-260, Top+8+40, Right-264, Height=38), locale::DOWNLOAD_TO_PROFILE);
		downloadProfile.setIcon(icons::Import);
		setMarkupTooltip(downloadProfile, locale::TT_DOWNLOAD_TO_PROFILE, width=400);

		@editButton = GuiButton(this, Alignment(Right-208-260, Top+8+40+40, Right-264, Height=38), locale::DOWNLOAD_EDIT);
		editButton.setIcon(icons::Edit);
		editButton.allowOtherButtons = true;
		setMarkupTooltip(editButton, locale::TT_DOWNLOAD_EDIT, width=400);

		@deleteButton = GuiButton(this, Alignment(Left+8, Top+8+40+40, Left+144, Height=38), locale::DELETE);
		deleteButton.color = colors::Red;
		deleteButton.setIcon(icons::Delete);
		deleteButton.visible = false;

		@headerPanel = GuiPanel(this, Alignment(Left+154, Top+8, Right-264-208-208, Top+135));
		headerPanel.horizType = ST_Never;

		@titleBox = GuiText(headerPanel, Alignment(Left, Top, Right, Top+38));
		titleBox.font = FT_Big;
		titleBox.stroke = colors::Black;
		titleBox.vertAlign = 0.15;

		@header = LinkableMarkupText(headerPanel, recti());
		@linkTip = GuiText(headerPanel, recti());
		linkTip.font = FT_Italic;
		linkTip.color = Color(0x8888aaff);

		@votesButton = GuiButton(this, Alignment(Right-208-260-208+50, Top+20, Width=100, Height=50), locale::VOTES_BUTTON);
		votesButton.font = FT_Medium;
		votesButton.textColor = colors::Green;
		votesButton.setIcon(icons::Upvote);
		setMarkupTooltip(votesButton, locale::TT_VOTES_BUTTON);

		@commentsBox = GuiSkinElement(this, Alignment(Right-250-500, Top+136, Right-250, Bottom), SS_PlainBox);
		commentsBox.visible = false;

		@commentsPanel = GuiPanel(commentsBox, Alignment(Left, Top, Right, Bottom-100));

		@comments = LinkableMarkupText(commentsPanel, recti_area(6,6,472,100));

		@commentText = GuiTextbox(commentsBox, Alignment(Left+4, Bottom-100, Right-4, Bottom-40));
		commentText.emptyText = locale::COMMENT_TEXT;
		commentText.multiLine = true;

		@commentSubmit = GuiButton(commentsBox, Alignment(Right-200, Bottom-38, Right-4, Bottom-4), locale::COMMENT_SUBMIT);
		commentSubmit.buttonIcon = icons::Chat;

		@commentsButton = GuiButton(this, Alignment(Right-208-260-208, Top+8+40+40, Width=200, Height=38),
				locale::COMMENTS_BUTTON);
		commentsButton.font = FT_Bold;
		commentsButton.toggleButton = true;
		commentsButton.setIcon(icons::Chat);

		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();
		if(header !is null)
			header.rect = recti_area(vec2i(0,36), vec2i(headerPanel.size.width-20, header.size.height));
		if(linkTip !is null)
			linkTip.rect = recti_area(vec2i(0, header.rect.botRight.y), vec2i(headerPanel.size.width, 26));
	}

	Color get_activeColor() {
		return Color(0xff83bcff);
	}

	Color get_inactiveColor() {
		return Color(0xff0077ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x8d4969ff);
	}		

	TabCategory get_category() {
		return TC_Wiki;
	}

	Sprite get_icon() {
		return Sprite(material::TabWiki);
	}

	void reload() {
		bp.load(bp.designId);
	}

	void tick(double time) {
		if(waitReload !is null && waitReload.completed) {
			reload();
			@waitReload = null;
		}

		backButton.disabled = previous is null;
		commentsBox.visible = commentsButton.pressed;
		commentSubmit.disabled = commentText.text.length == 0;
		bp.update();

		if(dsg !is bp.dsg) {
			@dsg = bp.dsg;

			if(dsg !is null) {
				title = format(locale::COMMUNITY_TITLE, dsg.name);
				titleBox.text = dsg.name;
				titleBox.color = dsg.color;

				votesButton.text = format(locale::VOTES_BUTTON, toString(bp.upvotes));
				votesButton.disabled = bp.hasUpvoted;
				if(votesButton.disabled)
					setMarkupTooltip(votesButton, "");
				else
					setMarkupTooltip(votesButton, locale::TT_VOTES_BUTTON);

				string hstr = format(locale::COMMUNITY_DESIGN_SPEC, toString(dsg.size,0), bbescape(bp.author), bbescape(bp.ctime));
				hstr = format("[b]$1[/b]\n[i][color=#aaa]", hstr);
				hstr += bbescape(bp.description, true);
				hstr += "[/color][/i]";
				header.text = hstr;

				linkTip.text = format(locale::DESIGN_LINK_TIP, toString(bp.designId));

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

				deleteButton.visible = bp.isMine;

				commentsButton.text = format(locale::COMMENTS_BUTTON, toString(bp.commentCount));
				string cstr;
				for(uint i = 0, cnt = bp.comments.length; i < cnt; ++i) {
					auto@ c = bp.comments[i];
					cstr += format("[font=Subtitle]$1[color=#aaa] on $2[/color][/font]\n[vspace=6/][offset=20]",
						bbescape(c.author), bbescape(c.ctime));
					cstr += bbescape(c.content, true);
					cstr += "[/offset]\n\n";
				}

				comments.text = cstr;
				updateAbsolutePosition();
			}
			else {
				titleBox.text = "---";
				title = "---";
			}
		}
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			WebData dat;
			dat.addPost("delete", "true");
			webAPICall("design/"+bp.designId+"/delete", dat);
			while(!dat.completed)
				sleep(100);
			popTab(this);
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is backButton) {
				popTab(this);
				return true;
			}
			else if(evt.caller is votesButton) {
				WebData dat;
				dat.addPost("vote", "true");
				webAPICall("design/"+bp.designId+"/vote", dat);

				votesButton.text = format(locale::VOTES_BUTTON, toString(bp.upvotes+1));
				votesButton.disabled = true;
				return true;
			}
			else if(evt.caller is deleteButton) {
				question(locale::COMMUNITY_CONFIRM_DELETE_DESIGN, this);
				return true;
			}
			else if(evt.caller is commentSubmit) {
				if(commentText.text.length > 0 ){
					WebData dat;
					dat.addPost("author", settings::sNickname);
					dat.addPost("content", commentText.text);
					webAPICall("design/"+bp.designId+"/comment", dat);

					commentText.text = "";
					@waitReload = dat;
				}
				return true;
			}
			else if(evt.caller is downloadEmpire) {
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
						browseTab(this, createDesignEditorTab(dsg), true);
				}
				return true;
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_WikiBG, SF_Normal, AbsolutePosition);
		skin.draw(SS_PlainBox, SF_Normal, recti(AbsolutePosition.topLeft,
					vec2i(AbsolutePosition.botRight.x-250, AbsolutePosition.topLeft.y+136)));
		Tab::draw();
	}
};

Tab@ createCommunityDesignPage(int id) {
	return CommunityDesign(id);
}

class CommunityDesignCommand : ConsoleCommand {
	void execute(const string& args) {
		auto@ page = createCommunityDesignPage(toInt(args));
		newTab(page);
		switchToTab(page);
	}
};

void init() {
	addConsoleCommand("design_page", CommunityDesignCommand());
}
