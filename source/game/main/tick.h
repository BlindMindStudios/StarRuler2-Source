#pragma once
#include <string>
#include <vector>

extern double animation_s, render_s, present_s;

namespace render {
	class Shader;
	class Camera;
};
struct Image;

extern const render::Shader* fsShader;

extern double frameLen_s, frameTime_s, realFrameLen;
extern int frameTime_ms, frameLen_ms;
extern bool reload_gui;

extern std::vector<double> frames;
extern unsigned max_frames;

enum GameState {
	GS_Menu,
	GS_Game,
	GS_Test_Scripts,
	GS_Monitor_Scripts,
	GS_Console_Wait,
	GS_Quit,
	GS_Load_Prep,

	GS_COUNT,
};

extern GameState game_state;
extern std::string game_locale;
extern bool game_running;
extern bool hide_ui;
extern double ui_scale;

void resetGameTime();
void getFrameRender(Image& img);
void tickGlobal(bool hasScripts = true);
void tickMenu();
void tickGame();
void tickConsole();

void monitorFile(const std::string& filename);
bool tickMonitor();
