import menus;
import elements.GuiDropdown;
import elements.BaseGuiElement;
import elements.MarkupTooltip;
import util.engine_options;
import dialogs.QuestionDialog;

enum OptionsActions {
	OA_Back,
	OA_Graphics,
	OA_Game,
	OA_Camera,
	OA_Keybinds,
	OA_Audio,
};

bool pendingShaderChanges = false;

class OptionsMenu : MenuBox {
	int prevSelected = 1;

	OptionsMenu() {
		super();
		selectable = true;
	}

	void buildMenu() {
		title.text = locale::MENU_OPTIONS;

		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 11), locale::MENU_BACK, OA_Back));
		items.addItem(MenuAction(locale::OPT_GRAPHICS, OA_Graphics));
		items.addItem(MenuAction(locale::OPT_GAME, OA_Game));
		items.addItem(MenuAction(locale::OPT_CAMERA, OA_Camera));
		items.addItem(MenuAction(locale::OPT_AUDIO, OA_Audio));
		items.addItem(MenuAction(locale::OPT_KEYBINDS, OA_Keybinds));

		if(items.selected < 1)
			items.selected = prevSelected;
	}

	void onSelected(const string& name, int value) {
		switch(value) {
			case OA_Back:
				items.clearSelection();
				checkShaderReload();
				switchToMenu(main_menu, false);
			break;
			default:
				showOptions(value);
				prevSelected = value;
			break;
		}
	}

	void showOptions(int num) {
		switch(num) {
			case OA_Game:
				showDescBox(game_options);
			break;
			case OA_Graphics:
				showDescBox(graphics_options);
			break;
			case OA_Camera:
				showDescBox(camera_options);
			break;
			case OA_Audio:
				showDescBox(audio_options);
			break;
			case OA_Keybinds:
				showDescBox(keybind_options);
			break;
		}
	}

	void animate(MenuAnimation type) {
		if(type == MAni_LeftOut || type == MAni_RightOut)
			showDescBox(null);
		MenuBox::animate(type);
	}

	void completeAnimation(MenuAnimation type) {
		if(type == MAni_LeftShow || type == MAni_RightShow)
			showOptions(items.selected);
		MenuBox::completeAnimation(type);
	}

	void draw() {
		MenuBox::draw();
	}
};

void onGameStateChange() {
	checkShaderReload();
}

void checkShaderReload() {
	if(pendingShaderChanges) {
		pendingShaderChanges = false;
		applySettings();
		saveSettings();
		shader::reloadSettingsShaders();
	}
}

class OptionsBox : DescBox {
	GuiButton@ applyButton;
	EngineOption@[] options;

	OptionsBox() {
		super();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Changed) {
			EngineOption@ opt = cast<EngineOption>(event.caller);
			if(opt !is null)
				opt.apply();
			if(cast<KeybindOption>(event.caller) !is null) {
				saveKeybinds();
			}
			else {
				applySettings();
				saveSettings();
			}
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};

class GameOptions : OptionsBox {
	GameOptions() {
		super();

		title.text = locale::OPT_GAME;

		uint y = 4;
		options.insertLast(GuiLocaleOption(
			panel, recti_area(8, y,  550, 32)
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_GALAXY_BG, "bGalaxyBG"
		));

		y += 34;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_AUTOPAUSE,
			"bAutoPause"
		));

		y += 34;
		GuiEngineDecimal autosave(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_AUTOSAVE,
			"dAutosaveMinutes"
		);
		autosave.decimals = 0;
		options.insertLast(autosave);

		y += 34;
		GuiEngineNumber autosaveCount(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_AUTOSAVE_COUNT,
			"iAutosaveCount"
		);
		autosaveCount.decimals = 0;
		options.insertLast(autosaveCount);

		y += 34;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  268, 28),
			locale::OPT_ICONIFY_NOTIFICATIONS,
			"bIconifyNotifications"
		));

		GuiEngineDecimal maxnotif(
			panel, recti_area(256, y, 268, 28),
			locale::OPT_MAX_NOTIFICATIONS,
			"dMaxNotifications"
		);
		maxnotif.decimals = 0;
		options.insertLast(maxnotif);

		y += 34;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_RESEARCH_EDGE_PAN, "bResearchEdgePan"
		));

		y += 34;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_ESCAPE_GALAXY_TAB, "bEscapeGalaxyTab"
		));

		y += 34;
		GuiEngineToggle toggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_HOLD_FOR_POPUP, "bHoldForPopup"
		);
		setMarkupTooltip(toggle, locale::OPTTT_HOLD_FOR_POPUP);
		options.insertLast(toggle);

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_ROTATE_OBJS, "bRotateUIObjects"
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_MENU_BG_SCREENSHOT, "bMenuBGScreenshot"
		));

		GuiText text(this, Alignment(Left+12, Bottom-32, Right-12, Bottom-8), locale::OPT_RESTART);
		text.color = Color(0xaaaaaaff);
		text.font = FT_Italic;
	}
};

class GuiLocaleOption : GuiDropdownOption, EngineOption {
	array<string> locales;

	GuiLocaleOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::OPT_LANGUAGE);

		FileList flist;
		flist.navigate("locales", "*");
		uint cnt = flist.length;
		for(uint i = 0; i < cnt; ++i) {
			if(flist.isDirectory[i]) {
				string ident = flist.basename[i];
				locales.insertLast(ident);

				string name = localize("#LOC_"+ident);
				if(name[0] == '#')
					name = ident;
				box.addItem(name);
			}
		}

		reset();
	}

	void reset() {
		box.selected = 0;
		for(uint i = 0, cnt = locales.length; i < cnt; ++i) {
			if(locales[i] == settings::sLocale) {
				box.selected = i;
				break;
			}
		}
	}

	void apply() {
		if(box.selected >= 0)
			settings::sLocale = locales[box.selected];
	}
};

class GuiResolutionOption : GuiDropdownOption, EngineOption {
	array<VideoMode> modes;

	GuiResolutionOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::OPT_RESOLUTION);

		getVideoModes(modes);
		box.addItem(locale::RES_DESKTOP);
		for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
			VideoMode mode = modes[cnt-(i+1)];
			box.addItem(format(locale::OPT_RES_ENTRY, mode.width, mode.height, mode.refresh));
		}
		reset();
	}

	void reset() {
		uint w = 0, h = 0, hz = 60;
		if(settings::bFullscreen) {
			w = settings::iFsResolutionX;
			h = settings::iFsResolutionY;
			hz = settings::iRefreshRate;
		}
		else {
			w = settings::iResolutionX;
			h = settings::iResolutionY;
			uint _hz = settings::iRefreshRate;
			if(_hz > 0)
				hz = _hz;
		}

		box.selected = 0;
		for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
			VideoMode mode = modes[cnt-(i+1)];
			if(mode.width == w && mode.height == h && mode.refresh == hz) {
				box.selected = i+1;
				break;
			}
		}
	}

	void apply() {
		int w = 0, h = 0, hz = 0;
		if(box.selected > 0) {
			VideoMode mode = modes[modes.length-box.selected];
			w = mode.width;
			h = mode.height;
			hz = mode.refresh;
		}

		settings::iResolutionX = w;
		settings::iResolutionY = h;
		settings::iFsResolutionX = w;
		settings::iFsResolutionY = h;
		settings::iRefreshRate = hz;
	}
};

class GuiMonitorOption : GuiDropdownOption, EngineOption {
	array<string> names;

	GuiMonitorOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::MONITOR);

		getMonitorNames(names);
		box.addItem(locale::MONITOR_PRIMARY);
		for(uint i = 0, cnt = names.length; i < cnt; ++i)
			box.addItem(names[i]);
		reset();
	}

	void reset() {
		string name = settings::sMonitor;

		box.selected = 0;
		for(uint i = 0, cnt = names.length; i < cnt; ++i) {
			if(names[i] == name) {
				box.selected = i+1;
				break;
			}
		}
	}

	void apply() {
		string name;
		if(box.selected > 0)
			name = names[box.selected-1];

		settings::sMonitor = name;
	}
};

class GuiVsyncOption : GuiDropdownOption, EngineOption {
	GuiVsyncOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::VSYNC);

		box.addItem(locale::VSYNC_Adaptive);
		box.addItem(locale::VSYNC_Off);
		box.addItem(locale::VSYNC_On);
		box.addItem(locale::VSYNC_OnHalf);
		
		reset();
	}

	void reset() {
		box.selected = settings::iVsync+1;
	}

	void apply() {
		if(box.selected >= 0) {
			settings::iVsync = box.selected - 1;
			vsync = box.selected - 1;
		}
	}
};

class GuiAAOption : GuiDropdownOption, EngineOption {
	GuiAAOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::ANTIALIASING);

		box.addItem(locale::AA_None);
		box.addItem(locale::AA_2x);
		box.addItem(locale::AA_4x);
		box.addItem(locale::AA_8x);
		box.addItem(locale::AA_Super);
		
		reset();
	}

	void reset() {
		uint samples = settings::iSamples;
		bool supersample = settings::bSupersample;
		
		if(!supersample) {
			switch(samples) {
				case 0: box.selected = 0; break;
				case 2: box.selected = 1; break;
				case 4: box.selected = 2; break;
				case 8: box.selected = 3; break;
			}
		}
		else if(samples == 1) {
			box.selected = 4;
		}
	}

	void apply() {
		if(box.selected >= 0) {
			uint setting = box.selected;
			uint samples = 1;
			bool supersample = false;
			switch(setting) {
				case 1: samples = 2; break;
				case 2: samples = 4; break;
				case 3: samples = 8; break;
				case 4: supersample = true; break;
			}
			
			settings::iSamples = samples;
			settings::bSupersample = supersample;
			
			scale_3d = supersample ? 2.0 : 1.0;
		}
	}
};

class GuiAudioOption : GuiDropdownOption, EngineOption {
	array<string> names;

	GuiAudioOption(BaseGuiElement@ parent, const recti& pos) {
		super(parent, pos, locale::AUDIO_DEVICE);

		getAudioDeviceNames(names);
		box.addItem(locale::AUDIO_DEVICE_DEFAULT);
		for(uint i = 0, cnt = names.length; i < cnt; ++i)
			box.addItem(names[i]);
		reset();
	}

	void reset() {
		string name = settings::sAudioDevice;

		box.selected = 0;
		for(uint i = 0, cnt = names.length; i < cnt; ++i) {
			if(names[i] == name) {
				box.selected = i+1;
				break;
			}
		}
	}

	void apply() {
		string name;
		if(box.selected > 0)
			name = names[box.selected-1];

		settings::sAudioDevice = name;
	}
};

void updateGuiScale() {
	uiScale = getSettingDouble("dGUIScale");
}

class GraphicsOptions : OptionsBox {
	GuiEngineDropdown@ shadLevel;
	array<IGuiElement@> shaderWatch;

	GraphicsOptions() {
		super();

		title.text = locale::OPT_GRAPHICS;

		uint y = 4;
		options.insertLast(GuiResolutionOption(
			panel, recti_area(8, y,  550, 32)));

		//TODO: Implement this in a way that works
		/*y += 32;
		auto@ scale = GuiEngineSlider(
			panel, recti_area(8, y,  550, 26),
			locale::OPT_GUI_SCALE, "dGUIScale"
		);
		@scale.onChanged = updateGuiScale;
		options.insertLast(scale);*/

		y += 32;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(20, y,  268, 26),
			locale::OPT_FULLSCREEN, "bFullscreen"
		));

		options.insertLast(GuiEngineToggle(
			panel, recti_area(276, y,  268, 26),
			locale::OPT_CAPTURE_CURSOR, "bCursorCapture"
		));
		
		y += 32;
		options.insertLast(GuiMonitorOption(
			panel, recti_area(8, y, 550, 32)));

		y += 32;
		{
			GuiEngineDropdown texQual(
				panel, recti_area(8, y,  550, 32),
				locale::OPT_TEX_QUALITY, "iTextureQuality");
			texQual.addItem(locale::TEX_QUAL_2, 2);
			texQual.addItem(locale::TEX_QUAL_3, 3);
			texQual.addItem(locale::TEX_QUAL_4, 4);
			texQual.addItem(locale::TEX_QUAL_5, 5);
			texQual.reset();
			options.insertLast(texQual);
		}

		y += 32;
		{
			@shadLevel = GuiEngineDropdown(
				panel, recti_area(8, y,  550, 32),
				locale::OPT_SHADER_LEVEL, "iShaderLevel");
			shadLevel.addItem(locale::SHADER_LEVEL_1, 1);
			shadLevel.addItem(locale::SHADER_LEVEL_2, 2);
			shadLevel.addItem(locale::SHADER_LEVEL_3, 3);
			shadLevel.addItem(locale::SHADER_LEVEL_4, 4);
			shadLevel.reset();
			options.insertLast(shadLevel);
		}
		
		y += 32;
		options.insertLast(GuiAAOption(
			panel, recti_area(8, y, 550, 32)));
		
		y += 32;
		options.insertLast(GuiVsyncOption(
			panel, recti_area(8, y, 550, 32)));

		y += 32;
		GuiEngineDecimal fps(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_MAX_FPS,
			"dMaxFPS"
		);
		fps.decimals = 0;
		options.insertLast(fps);

		y += 32;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(20, y,  268, 26),
			locale::OPT_SHOW_GAS, "bShowGalaxyGas"
		));

		GuiEngineToggle@ tog;
		@tog = GuiEngineToggle(
			panel, recti_area(286, y,  268, 26),
			locale::OPT_SKYCUBE_STARS, "bSkycubeStars"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		y += 32;
		@tog = GuiEngineToggle(
			panel, recti_area(20, y,  268, 26),
			locale::OPT_BLOOM, "bBloom"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		@tog = GuiEngineToggle(
			panel, recti_area(286, y,  268, 26),
			locale::OPT_GOD_RAYS, "bGodRays"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		y += 32;
		@tog = GuiEngineToggle(
			panel, recti_area(20, y,  268, 26),
			locale::OPT_VIGNETTE, "bVignette"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		@tog = GuiEngineToggle(
			panel, recti_area(286, y,  268, 26),
			locale::OPT_CHROMATIC_ABERRATION, "bChromaticAberration"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		y += 32;
		@tog = GuiEngineToggle(
			panel, recti_area(20, y,  530, 26),
			locale::OPT_FILM_GRAIN, "bFilmGrain"
		);
		options.insertLast(tog);
		shaderWatch.insertLast(tog);

		y += 32;

		GuiText text(this, Alignment(Left+12, Bottom-32, Right-12, Bottom-8), locale::OPT_RESTART);
		text.color = Color(0xaaaaaaff);
		text.font = FT_Italic;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Changed) {
			if(evt.caller is shadLevel) {
				pendingShaderChanges = true;
			}
			else {
				for(uint i = 0, cnt = shaderWatch.length; i < cnt; ++i) {
					if(evt.caller is shaderWatch[i]) {
						pendingShaderChanges = true;
						break;
					}
				}
			}
		}
		return OptionsBox::onGuiEvent(evt);
	}
};

class CameraOptions : OptionsBox {
	CameraOptions() {
		super();

		title.text = locale::OPT_CAMERA;

		uint y = 4;
		options.insertLast(GuiEngineSlider(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_ZOOM_SPEED, "dZoomSpeed"
		));

		y += 32;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_CURSOR_ZOOM_IN, "bZoomToCursor"
		));

		options.insertLast(GuiEngineToggle(
			panel, recti_area(286, y,  278, 28),
			locale::OPT_CURSOR_ZOOM_OUT, "bZoomFromCursor"
		));

		y += 32;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_INVERT_ZOOM, "bInvertZoom"
		));

		y += 38;
		options.insertLast(GuiEngineSlider(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_PAN_SPEED, "dPanSpeed"
		));

		y += 32;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_INVERT_PAN_X, "bInvertPanX"
		));

		options.insertLast(GuiEngineToggle(
			panel, recti_area(286, y,  278, 28),
			locale::OPT_INVERT_PAN_Y, "bInvertPanY"
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_MOD_SPEED_PAN, "bModSpeedPan"
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_INVERT_ROTATION_X, "bInvertHorizRot"
		));

		options.insertLast(GuiEngineToggle(
			panel, recti_area(286, y,  278, 28),
			locale::OPT_INVERT_ROTATION_Y, "bInvertVertRot"
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_FREE_CAMERA, "bFreeCamera"
		));

		y += 38;
		options.insertLast(GuiEngineToggle(
			panel, recti_area(8, y,  278, 28),
			locale::OPT_EDGE_PAN, "bEdgePan"
		));

		options.insertLast(GuiEngineToggle(
			panel, recti_area(286, y,  278, 28),
			locale::OPT_DELAY_TOP_EDGE, "bDelayTopEdge"
		));
	}
};

double lastPlayed = -INFINITY;
void playSampleSFX() {
	double t = getExactTime();
	if(t - lastPlayed > 0.5) {
		sound::generic_click.play(priority=true);
		lastPlayed = t;
	}
}

class AudioOptions : OptionsBox {
	AudioOptions() {
		super();

		title.text = locale::OPT_AUDIO;

		uint y = 4;
		auto@ master = GuiEngineSlider(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_MASTER_VOLUME, "dMasterVolume"
		);
		@master.onChanged = playSampleSFX;
		options.insertLast(master);

		y += 32;
		auto@ sfx = GuiEngineSlider(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_SFX_VOLUME, "dSFXVolume"
		);
		@sfx.onChanged = playSampleSFX;
		options.insertLast(sfx);

		y += 32;
		auto@ music = GuiEngineSlider(
			panel, recti_area(8, y,  550, 28),
			locale::OPT_MUSIC_VOLUME, "dMusicVolume"
		);
		options.insertLast(music);
		
		y += 32;
		options.insertLast(GuiAudioOption(
			panel, recti_area(8, y, 550, 32)));
	}
};

class ResetKeys : QuestionDialogCallback {
	KeybindOptions@ box;

	ResetKeys(KeybindOptions@ Box) {
		@box = Box;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			box.resetKeysToDefaults();
	}
};

class KeybindOption : BaseGuiElement, EngineOption {
	KeybindOptions@ box;
	KeybindGroup@ group;
	Keybind bind;
	int[] keys;

	bool active;
	bool append;
	bool hover;

	GuiText@ label;
	GuiText@ keysLabel;

	KeybindOption(KeybindOptions@ Box, GuiPanel@ pnl, Alignment@ align, KeybindGroup@ Group, Keybind Bind) {
		super(pnl, align);
		
		bind = Bind;
		@box = Box;
		@group = Group;

		hover = false;
		append = false;
		active = false;

		@label = GuiText(this, recti(), localize("KB_"+group.getBindName(bind)));
		@label.alignment = Alignment(Left+4, Top, Left+0.4f, Bottom);

		@keysLabel = GuiText(this, recti());
		@keysLabel.alignment = Alignment(Left+0.4f, Top, Right-4, Bottom);
		keysLabel.horizAlign = 1.0;

		reset();
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Focus_Lost) {
			active = false;
			hover = false;
			resetText();
		}
		else if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					hover = true;
				break;
				case GUI_Mouse_Left:
					hover = false;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case MET_Button_Down:
				return true;
			case MET_Button_Up:
				if(event.button == 0) {
					active = true;
					append = shiftKey;
					resetText();
				}
				return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(active) {
			switch(event.type) {
				case KET_Key_Down: {
					switch(event.key) {
						case KEY_LCTRL:
						case KEY_RCTRL:
						case KEY_LALT:
						case KEY_RALT:
							resetText();
							return false;
					}
				} return true;
				case KET_Key_Up: {
					switch(event.key) {
						case KEY_LCTRL:
						case KEY_RCTRL:
						case KEY_LALT:
						case KEY_RALT:
						case KEY_LSHIFT:
						case KEY_RSHIFT:
							return false;
					}

					uint num = event.key;
					if(num >= 'A' && num <= 'Z')
						num += 'a'-'A';
					if(ctrlKey)
						num |= MASK_CTRL;
					if(altKey)
						num |= MASK_ALT;
					if(shiftKey)
						num |= MASK_SHIFT;

					if(event.key != KEY_ESC || shiftKey) {
						if(!append)
							keys.length = 0;
						if(event.key != KEY_ESC && keys.find(num) == -1) {
							box.clearKey(num);
							keys.insertLast(num);
						}
						emitChanged();
					}

					active = false;
					setGuiFocus(parent);
					resetText();
					return true;
				}
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void apply() {
		group.clearBinds(bind);
		for(uint i = 0, cnt = keys.length; i < cnt; ++i)
			group.setBind(keys[i], bind);
	}

	void reset() {
		uint kCount = group.getCurrentKeyCount(bind);
		keys.length = kCount;
		for(uint i = 0; i < kCount; ++i)
			keys[i] = group.getCurrentKey(bind, i);

		keys.sortAsc();
		resetText();
	}

	void resetToDefaults() {
		uint kCount = group.getDefaultKeyCount(bind);
		keys.length = kCount;
		for(uint i = 0; i < kCount; ++i)
			keys[i] = group.getDefaultKey(bind, i);

		keys.sortAsc();
		resetText();
	}

	void resetText() {
		string keyText = "";

		if(!active || append) {
			for(uint i = 0, cnt = keys.length; i < cnt; ++i) {
				if(i != 0)
					keyText += ", ";
				keyText += getKeyDisplayName(keys[i]);
			}

			if(active && keys.length > 0)
				keyText += ", ";
		}

		if(active) {
			if(ctrlKey)
				keyText += "ctrl+";
			if(altKey)
				keyText += "alt+";
			if(shiftKey)
				keyText += "shift+";
			keyText += "...";
		}

		keysLabel.text = keyText;
	}

	void draw() {
		uint flags = SF_Normal;
		if(active)
			flags |= SF_Active;
		if(hover)
			flags |= SF_Hovered;

		skin.draw(SS_ListboxItem, flags, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class KeybindOptions : OptionsBox {
	GuiDropdown@ keyGroup;
	GuiPanel@[] keyPanes;

	KeybindOptions() {
		super();
		title.text = locale::OPT_KEYBINDS;
		panel.vertType = ST_Never;

		@keyGroup = GuiDropdown(panel, Alignment(Left+4, Top+2, Right-4, Height=30));
		keyGroup.font = FT_Medium;

		for(uint grpInd = 0, grpCnt = keybindGroupCount; grpInd < grpCnt; ++grpInd) {
			KeybindGroup@ group = keybindGroup[grpInd];

			keyGroup.addItem(localize("KG_"+group.name));

			GuiPanel@ pane = GuiPanel(panel, Alignment(Left+4, Top+36, Right-4, Bottom-4));
			if(grpInd != 0)
				pane.visible = false;
			keyPanes.insertLast(pane);

			uint y = 4;
			for(uint kbInd = 0, kbCnt = group.getBindCount(); kbInd < kbCnt; ++kbInd) {
				options.insertLast(KeybindOption(
					this, pane, Alignment(Left+4, Top+y, Right-4, Top+y+26),
					group, Keybind(kbInd)
				));
				y += 26;
			}
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Changed) {
			if(event.caller is keyGroup) {
				for(uint i = 0, cnt = keyPanes.length; i < cnt; ++i)
					keyPanes[i].visible = false;
				int sel = keyGroup.selected;
				keyPanes[sel].visible = true;
			}
		}
		return OptionsBox::onGuiEvent(event);
	}

	void clearKey(int key) {
		for(uint i = 0, cnt = options.length(); i < cnt; ++i) {
			KeybindOption@ opt = cast<KeybindOption@>(options[i]);
			if(opt !is null) {
				int pos = opt.keys.find(key);
				if(pos != -1) {
					opt.keys.removeAt(pos);
					opt.resetText();
				}
			}
		}
	}

	void resetKeysToDefaults() {
		for(uint i = 0, cnt = options.length(); i < cnt; ++i) {
			KeybindOption@ opt = cast<KeybindOption@>(options[i]);
			if(opt !is null)
				opt.resetToDefaults();
		}
	}
};

DescBox@ game_options;
DescBox@ graphics_options;
DescBox@ camera_options;
DescBox@ keybind_options;
DescBox@ audio_options;

void init() {
	@options_menu = OptionsMenu();
	@game_options = GameOptions();
	@graphics_options = GraphicsOptions();
	@camera_options = CameraOptions();
	@keybind_options = KeybindOptions();
	@audio_options = AudioOptions();
}
