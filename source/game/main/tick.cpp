#include "main/tick.h"
#include "main/input_handling.h"
#include "main/references.h"
#include "main/logging.h"
#include "processing.h"
#include "obj/object.h"
#include "scene/animation/anim_node_sync.h"
#include "main/console.h"
#include "main/initialization.h"
#include "network/network_manager.h"
#include "ISoundDevice.h"
#include "files.h"
#include "design/projectiles.h"
#include "render/vertexBuffer.h"
#include "render/gl_framebuffer.h"
#include "save_load.h"
#include <cmath>
#include <stdio.h>
#include <stdint.h>

extern unsigned drawnSteps, bufferFlushes;

GameState game_state = GS_Menu;
std::string game_locale;
bool game_running = false;
bool reload_gui = false;

bool fullGC = false;

threads::Mutex texDestroyLock;
std::vector<const render::Texture*> queuedDestroyTextures;
void queueDestroyTexture(const render::Texture* tex) {
	threads::Lock lock(texDestroyLock);
	queuedDestroyTextures.push_back(tex);
}

void destroyQueuedTextures() {
	if(queuedDestroyTextures.empty())
		return;

	threads::Lock lock(texDestroyLock);
	for(unsigned i = 0; i < queuedDestroyTextures.size(); ++i)
		delete queuedDestroyTextures[i];
	queuedDestroyTextures.clear();
}

const render::Shader* fsShader = nullptr;
bool hide_ui = false;
double ui_scale = 1.0;
double scale_3d = 1.0;
double pixelSizeRatio = 1.0;
double* maxfps = nullptr;

//Seconds since last autosave
double autosaveTimer = 0.0;
extern double autosaveInterval;

threads::Signal scriptTickSignal;

extern bool queuedModSwitch;
extern std::vector<std::string> modSetup;

namespace scripts {
	void logException();
};

class RunScriptTick : public processing::Action {
	double time;
	double& logTime;
	bool gcLock;
	scripts::Manager* manager;
public:
	RunScriptTick(scripts::Manager* Manager, double Time, bool Gc, double& LogTime)
		: time(Time), gcLock(Gc), manager(Manager), logTime(LogTime) {
	}

	bool run() {
		auto prevSection = enterSection(NS_ScriptTick);
		double start = devices.driver->getAccurateTime();
#ifndef _DEBUG
		try {
#endif
#ifdef TRACE_GC_LOCK
			manager->markGCImpossible();
#endif
			manager->tick(time);
			devices.network->managerNetworking(manager, time);
			scriptTickSignal.signalDown();
#ifdef TRACE_GC_LOCK
			manager->markGCPossible();
#endif
#ifndef _DEBUG
		}
		catch(...) {
			scripts::logException();
			throw;
		}
#endif
		logTime = devices.driver->getAccurateTime() - start;
		enterSection(prevSection);
		return true;
	}
};

class RunScriptGC : public processing::Action {
	scripts::Manager* manager;
	bool full;
public:
	RunScriptGC(scripts::Manager* Manager, bool FullCycle = false)
		: manager(Manager), full(FullCycle) {
	}

	bool run() {
		double start = devices.driver->getAccurateTime();
		manager->pauseScriptThreads();
		double gcStart = devices.driver->getAccurateTime();
		int gcMode = manager->garbageCollect(full);
		double end = devices.driver->getAccurateTime();
		manager->resumeScriptThreads();

#ifdef PROFILE_PROCESSING
		if(end - start > 0.016) {
			const char* name = "Server";
			if(manager == devices.scripts.client)
				name = "Client";
			else if(manager == devices.scripts.menu)
				name = "Menu";
			error("%s GC took %dms (Mode %d)", name, (int)((end - gcStart) * 1.0e3), gcMode);
			if(gcStart - start > 0.01)
				error("%s script pausing took %dms", name, (int)((gcStart - start) * 1.0e3));
		}
#endif

		scriptTickSignal.signalDown();
		return true;
	}
};

unsigned animationThreadCount = 6;
threads::Signal animationSignal, activeAnimCount;
threads::Mutex animDataLock;
double nearestNode = 9.0e35, furthestNode = 0.0;
double animation_s = 0.0, render_s = 0.0, present_s = 0.0;
threads::atomic_int animIndex(-1), animProcessed;

//Animates some nodes, returning how long it processed
double animateSomeNodes(int maxNodes) {
	if(animIndex < 0)
		return 0.0;

	double furthest = 0.0;
	double start = devices.driver->getAccurateTime();

	auto* nodes = &devices.scene->children.front();
	int count = (int)devices.scene->children.size();
	int animCount = count/(animationThreadCount*16);
	if(animCount == 0)
		animCount = 1;

	int index = (animIndex -= animCount);
	while(index >= 0) {
		int animated = 0;
		for(int i = index; i > index - animCount && i >= 0; --i) {
			auto* node = nodes[i];
			node->animate();
			++animated;
			
			double d = node->sortDistance + node->abs_scale;
			if(d > furthest)
				furthest = d;
		}

		if(animated != 0)
			animProcessed += animated;
		
		maxNodes -= animated;
		if(maxNodes < 0)
			break;

		index = (animIndex -= animCount);
	}

	animDataLock.lock();
	//if(nearest < nearestNode)
	//	nearestNode = nearest;
	if(furthest > furthestNode)
		furthestNode = furthest;
	animDataLock.release();

	return devices.driver->getAccurateTime() - start;
}

volatile bool EndAnimationThreads = false;
threads::threadreturn threadcall animateNodes(void* arg) {
	enterSection(NS_Animation);
	double& logTime = *(double*)arg;
	initNewThread();
	activeAnimCount.signalUp();
	//threads::setThreadPriority(threads::TP_High);

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCImpossible();
	devices.scripts.client->markGCImpossible();
#endif
	while(true) {
		while(animIndex < 0 && !EndAnimationThreads)
			threads::sleep(1);
		if(EndAnimationThreads)
			break;

		animationSignal.signalUp();

		double /*nearest = 9.0e35,*/ furthest = 0.0;
		double start = devices.driver->getAccurateTime();

		if(!devices.scene->children.empty()) {
			auto* nodes = &devices.scene->children.front();
			int animCount = (int)devices.scene->children.size()/(animationThreadCount*16);
			if(animCount == 0)
				animCount = 1;

			int index = (animIndex -= animCount);
			while(index >= 0) {
				int animated = 0;
				for(int i = index; i > index - animCount && i >= 0; --i) {
					auto* node = nodes[i];
					node->animate();
					++animated;
			
					double d = node->sortDistance + node->abs_scale;
					if(d > furthest)
						furthest = d;
				}

				if(animated != 0)
					animProcessed += animated;

				index = (animIndex -= animCount);
			}
		}

		logTime = devices.driver->getAccurateTime() - start;

		animDataLock.lock();
		//if(nearest < nearestNode)
		//	nearestNode = nearest;
		if(furthest > furthestNode)
			furthestNode = furthest;
		animDataLock.release();

		animationSignal.signalDown();
		threads::sleep(1);
	}
#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCPossible();
	devices.scripts.client->markGCPossible();
#endif

	activeAnimCount.signalDown();
	cleanupThread();
	return 0;
}

double frameLen_s = 0, frameTime_s = 0;
double realFrameLen = 0, realFrameTime;
int frameTime_ms = 0, frameLen_ms = 0;
unsigned frameNumber = 0;

std::vector<double> frames;
unsigned max_frames = 120;

void shader_gameTime(float* pFloats,unsigned short n,void*) {
	do {
		*pFloats = (float)frameTime_s;
		++pFloats;
	} while(--n);
}

void shader_frameTime(float* pFloats,unsigned short n,void*) {
	do {
		*pFloats = (float)realFrameTime;
		++pFloats;
	} while(--n);
}

void shader_gameTime_cycle(float* pFloats,unsigned short n,void* pArgs) {
	float* period = (float*)pArgs;
	do {
		*pFloats = (float)(std::fmod(frameTime_s, double(*period)) / double(*period));
		++period; ++pFloats;
	} while(--n);
}

void shader_frameTime_cycle(float* pFloats,unsigned short n,void* pArgs) {
	float* period = (float*)pArgs;
	do {
		*pFloats = (float)(std::fmod(realFrameTime, double(*period)) / double(*period));
		++period; ++pFloats;
	} while(--n);
}

void shader_gameTime_cycle_abs(float* pFloats,unsigned short n,void* pArgs) {
	float* period = (float*)pArgs;
	do {
		*pFloats = (float)std::fmod(frameTime_s, double(*period));
		++period; ++pFloats;
	} while(--n);
}

void shader_frameTime_cycle_abs(float* pFloats,unsigned short n,void* pArgs) {
	float* period = (float*)pArgs;
	do {
		*pFloats = (float)std::fmod(realFrameTime, double(*period));
		++period; ++pFloats;
	} while(--n);
}

void shader_pixelRatio(float* pFloats,unsigned short n,void* pArgs) {
	*pFloats = (float)pixelSizeRatio;
}

#ifdef PROFILE_LOCKS
double lockProfileTimer = 0.0;
bool printLockProfile = false;
bool requireObserved = false;
#endif

double menuTickTime = 0, serverTickTime = 0, clientTickTime = 0, animationTime = 0;
double* animTimes = nullptr;

extern double lastLockGlobalUpdate, nextTargetUpdateTime, nextScriptGCTime;

void resetGameTime() {
	nextTargetUpdateTime = lastLockGlobalUpdate = devices.driver->getGameTime();
	frameTime_s = devices.driver->getGameTime() - 0.25;
	nextScriptGCTime = devices.driver->getFrameTime();
}

void endAnimation() {
	if(animTimes) {
		EndAnimationThreads = true;
		activeAnimCount.wait(0);
		EndAnimationThreads = false;
		delete[] animTimes;
		animTimes = nullptr;
	}
}

void idleLoadResources(int maxPriority) {
	if(devices.library.processTextures(maxPriority, true))
		return;
	if(devices.library.processMeshes(maxPriority, 1))
		return;
	if(devices.library.processTextures(INT_MIN, true))
		return;
	if(devices.library.processMeshes(INT_MIN, 1))
		return;
}

GameState prev_state = GS_Menu;
void tickGlobal(bool hasScripts) {
#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCImpossible();
	devices.scripts.client->markGCImpossible();
#endif

	//Get frame timings
	static int lastRender = 0;

	if(queuedModSwitch) {
		queuedModSwitch = false;
		destroyMod();
		initMods(modSetup);
		game_state = GS_Menu;
	}

	if(game_state != prev_state) {
		if(hasScripts) {
			if(game_running && devices.scripts.client)
				devices.scripts.client->stateChange();
			if(devices.scripts.menu)
				devices.scripts.menu->stateChange();
		}
		prev_state = game_state;
	}

	++frameNumber;

	double frame_time = devices.driver->getGameTime() - 0.25;
	frameTime_ms = devices.driver->getTime();

	double real_frame = devices.driver->getFrameTime();
	realFrameLen = real_frame - realFrameTime;
	realFrameTime = real_frame;

	int frame_ms = frameTime_ms - lastRender;
	lastRender = frameTime_ms;

	double frame_s = frame_time - frameTime_s;
	frameTime_s = frame_time;

	if(frame_ms > 250 || frame_s > 0.25) {
		frame_ms = 250;
		frame_s = 0.25;
	}
	else if(frame_ms < 0 || frame_s < 0.0) {
		frame_ms = 0;
		frame_s = 0.0;
	}
	
	frameLen_s = frame_s;
	frameLen_ms = frame_ms;

	frames.push_back(realFrameLen);
	if(frames.size() > max_frames)
		frames.erase(frames.begin());

	//Run network manager tick
	devices.network->tick(realFrameLen);

	//Do lock profiling
#ifdef PROFILE_LOCKS
	lockProfileTimer += frame_s;
	if(lockProfileTimer >= 1.0) {
		lockProfileTimer = 0.0;

		if(printLockProfile) {
			threads::profileMutexCycle([](threads::Mutex* mtx) {
				if((mtx->observed || !requireObserved) && mtx->profileCount > 0) {
					print("%s: %d locks", mtx->name.c_str(), mtx->profileCount);
				}
			});
			threads::profileReadWriteMutexCycle([](threads::ReadWriteMutex* mtx) {
				if((mtx->observed || !requireObserved) && (mtx->profileReadCount > 0 || mtx->profileWriteCount > 0)) {
					print("%s: %d read, %d write", mtx->name.c_str(), mtx->profileReadCount, mtx->profileWriteCount);
				}
			});

			printLockProfile = false;
		}
		else {
			threads::profileMutexCycle(0);
			threads::profileReadWriteMutexCycle(0);
		}
	}
#endif

	idleLoadResources(isPreloading() ? -10 : INT_MIN);

	//Do script GCs
#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCPossible();
	devices.scripts.client->markGCPossible();
#endif

	if(hasScripts) {
		scriptTickSignal.signal(1);
		processing::queueAction(new RunScriptGC(devices.scripts.menu, fullGC));

		if(game_running) {
			scriptTickSignal.signalUp(1);
			processing::queueAction(new RunScriptGC(devices.scripts.client, fullGC));
		}

		fullGC = false;

		while(!scriptTickSignal.check(0)) {
			processing::run();
			threads::sleep(0);
		}
	}

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCImpossible();
	devices.scripts.client->markGCImpossible();
#endif

	//Run all the script ticks
	if(hasScripts) {
		scriptTickSignal.signal(1);
		processing::queueAction(new RunScriptTick(devices.scripts.menu, realFrameLen, false, menuTickTime));

		if(game_running) {
			scriptTickSignal.signalUp(2);
			processing::queueAction(new RunScriptTick(devices.scripts.server, frameLen_s, true, serverTickTime));
			processing::queueAction(new RunScriptTick(devices.scripts.client, realFrameLen, false, clientTickTime));
		}
	}

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCPossible();
	devices.scripts.client->markGCPossible();
#endif
}

std::unordered_map<std::string,time_t> guiModuleTimes;
void tickGuiReload() {
	if(!devices.scripts.client)
		return;
	for(auto it = devices.scripts.client->modules.begin(); it != devices.scripts.client->modules.end(); ++it) {
		scripts::Module& mod = *it->second;
		scripts::File& fl = *mod.file;

		time_t mtime = getModifiedTime(fl.path);
		auto f = guiModuleTimes.find(mod.name);
		if(f == guiModuleTimes.end()) {
			guiModuleTimes[mod.name] = mtime;
		}
		else {
			if(f->second < mtime)
				devices.scripts.client->reload(mod.name);
			guiModuleTimes[mod.name] = mtime;
		}
	}
}

static render::Texture* renderTarget = nullptr;
void getFrameRender(Image& img) {
	if(!game_running || !devices.scripts.client)
		return;

	auto prev_state = game_state;
	game_state = GS_Menu;

	devices.scripts.client->preRender(0.0);
	devices.scripts.client->render(0.0);

	renderTarget->save(img);
	devices.render->setRenderTarget(nullptr);

	game_state = prev_state;
}

void renderFrame(scripts::Manager* uiScript, scripts::Manager* renderScript) {
	drawnSteps = 0;
	bufferFlushes = 0;
	for(unsigned i = 0; i < render::FC_COUNT; ++i)
		render::vbFlushCounts[i] = 0;

	destroyQueuedTextures();

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCImpossible();
	devices.scripts.client->markGCImpossible();
#endif

	vec2i screenSize(devices.driver->win_width,devices.driver->win_height);
	bool render = screenSize.width != 0 && screenSize.height != 0;

	if(render) {
		if(!renderTarget)
			renderTarget = devices.render->createRenderTarget(screenSize * scale_3d);
		if(renderTarget->size != screenSize * scale_3d) {
			delete renderTarget;
			renderTarget = devices.render->createRenderTarget(screenSize * scale_3d);
		}
	}

	devices.sound->setListenerData(vec3f(devices.render->cam_pos), vec3f(), vec3f(devices.render->cam_pos + devices.render->cam_facing), vec3f(devices.render->cam_up));

	if(!Object::GALAXY_CREATION)
		scene::processNodeEvents();

	if(renderScript)
		renderScript->preRender(realFrameLen);

	nearestNode = 9.0e35; furthestNode = 0.0;

	static bool dumpAnimTimes = false;
	if(!animTimes) {
		animationThreadCount = std::max(1u,devices.driver->getProcessorCount()-1);
		animTimes = new double[animationThreadCount]();
		for(unsigned i = 0; i < animationThreadCount; ++i)
			threads::createThread(animateNodes, &animTimes[i]);
#ifdef PROFILE_ANIMATION
		console.addCommand("anim_times", [](argList& args) {
			dumpAnimTimes = true;
		}, true);
#endif
	}

	render::Texture* rt = nullptr;
	const render::Shader* shad = nullptr;
	if(fsShader || scale_3d != 1.0) {
		rt = renderTarget;
		shad = fsShader;
	}

	devices.library.reloadWatchedResources();

	if(render) {
		devices.render->setScreenSize(screenSize.x, screenSize.y);
		devices.render->setRenderTarget(rt);
	}

	if(screenSize.y != 0)
		pixelSizeRatio = (double)screenSize.y / 1024.0;

	double animTotal = 0.0;
	{
		int nodeCount = (int)devices.scene->children.size();
		animProcessed = 0;

		//Animate nodes, signaling the animation threads to work if they get time
		animIndex = nodeCount-1;
		unsigned loops = 0;
		while(true) {
			bool waiting = false;

			if(!scriptTickSignal.check(0)) {
				waiting = true;
				processing::run(true);
			}
			if(animProcessed != nodeCount) {
				waiting = true;
				animTotal += animateSomeNodes(128);
			}

			if(!waiting)
				break;
			if(++loops % 100 == 0)
				threads::sleep(0);
		}

		//Sort the catch-all parent
		devices.scene->sortChildren();

		//Wait for all animation threads to report in
		while(!animationSignal.check(0))
			threads::sleep(0);

		for(unsigned i = 0; i < animationThreadCount; ++i) {
			double t = animTimes[i];
			animTotal += t;
		}
#ifdef PROFILE_ANIMATION
		if(dumpAnimTimes)
			scene::dumpAnimationProfile();
		dumpAnimTimes = false;
#else
		(void)dumpAnimTimes;
#endif
	}

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCImpossible();
	devices.scripts.client->markGCImpossible();
#endif

	double animation_end = devices.driver->getAccurateTime();
	animation_s = animTotal;

	auto prevSection = enterSection(NS_Render);

	if(render) {
		devices.render->setDefaultRenderState();

		//Animation system tells us the near and far distances of everything that gets rendered
		devices.render->setNearFarPlanes(1.0, furthestNode * 1.1);
	
		//3D prepare is done by scripts, since it needs the camera
		devices.render->clearRenderPrepared();
		if(renderScript)
			renderScript->render(realFrameLen);

		if(rt) {
			devices.render->setRenderTarget(0);

			if(devices.render->isRenderPrepared()) {
				render::RenderState rs;
				if(shad)
					rs.shader = shad;
				else
					rs.shader = devices.library["Fullscreen"];
				rs.lighting = false;
				rs.culling = render::FC_None;
				rs.depthWrite = false;
				rs.depthTest = render::DT_NoDepthTest;
				rs.constant = false;
				rs.textures[0] = rt;
				rs.textures[7] = ((render::glFrameBuffer*)rt)->depthTexture; //fuck you framebuffers aren't textures

				auto* buffer = render::VertexBufferTCV::fetch(&rs);
				auto* verts = buffer->request(1, render::PT_Quads);
			
				verts[0].set(vec2f(0,0));
				verts[1].set(vec2f(1,0));
				verts[2].set(vec2f(1,1));
				verts[3].set(vec2f(0,1));

				buffer->draw();
			}
		}
	}

	//Check if we should scale the 2D interface
	if(render && !hide_ui) {
		static render::Texture* uirt = 0;
		vec2i uiArea;
		if(ui_scale != 1.0) {
			uiArea = vec2d(devices.driver->win_width, devices.driver->win_height) / ui_scale;

			if(uirt == 0) {
				uirt = devices.render->createRenderTarget(uiArea);
			}
			else {
				if(uirt->size != uiArea) {
					delete uirt;
					uirt = devices.render->createRenderTarget(uiArea);
				}
			}

			devices.render->setScreenSize(uiArea.x, uiArea.y);
			devices.render->setRenderTarget(uirt, true);
		}

		//2D prepare is done before scripts
		devices.render->prepareRender2D();
		if(uiScript)
			uiScript->draw();

		//Scale the 2D interface
		if(uiArea.x != 0) {
			devices.render->setScreenSize(screenSize.x, screenSize.y);
			devices.render->setRenderTarget(0);
			devices.render->prepareRender2D();

			render::RenderState rs;
			rs.lighting = false;
			rs.constant = false;
			rs.culling = render::FC_None;
			rs.baseMat = render::MAT_Overlay;
			rs.shader = devices.library["Fullscreen"];
			rs.depthWrite = false;
			rs.depthTest = render::DT_NoDepthTest;
			rs.filterMin = render::TF_Linear;
			rs.filterMag = render::TF_Linear;
			rs.textures[0] = uirt;

			auto* buffer = render::VertexBufferTCV::fetch(&rs);
			auto* verts = buffer->request(1, render::PT_Quads);
		
			verts[0].set(vec2f(0,0));
			verts[1].set(vec2f(1,0));
			verts[2].set(vec2f(1,1));
			verts[3].set(vec2f(0,1));

			buffer->draw();
		}
	}

	if(render) {
		if(hide_ui)
			devices.render->prepareRender2D();
		console.render(*devices.render);
		render::renderVertexBuffers();
	}
	else {
		threads::sleep(1);
	}

	double render_end = devices.driver->getAccurateTime();
	
	devices.driver->swapBuffers(maxfps && *maxfps > 0 ? 1.0 / *maxfps : 0.0);

	double present_end = devices.driver->getAccurateTime();

	render_s = render_end - animation_end;
	present_s = present_end - render_end;

#ifdef TRACE_GC_LOCK
	devices.scripts.menu->markGCPossible();
	devices.scripts.client->markGCPossible();
#endif

#ifdef _DEBUG
	devices.render->reportErrors();
#endif

	enterSection(prevSection);
}

void tickConsole() {
	tickGlobal(false);
	renderFrame(0, 0);
}

void tickGame() {
	//General tick
	tickGlobal();

	if(devices.driver->getGameSpeed() > 0 && !devices.network->isClient) {
		autosaveTimer += realFrameLen;

		auto* interval = devices.settings.engine.getSetting("dAutosaveMinutes");
		if(interval && interval->getDouble() >= 1.0 && autosaveTimer > interval->getDouble() * 60.0) {
			int maxAutosaves = 1;
			auto* count = devices.settings.engine.getSetting("iAutosaveCount");
			if(count)
				maxAutosaves = count->getInteger();
			std::string prevName;
			if(maxAutosaves > 1) {
				for(int index = maxAutosaves; index > 0; --index) {
					std::string fname = "autosave";
					if(index != 1)
						fname += toString(index);
					fname += ".sr2";
					fname = path_join(devices.mods.getGlobalProfile("saves"), fname);

					if(fileExists(fname)) {
						if(index == maxAutosaves)
							remove(fname.c_str());
						else
							rename(fname.c_str(), prevName.c_str());
					}
					prevName = fname;
				}
			}

			processing::pause();
			saveGame(path_join(devices.mods.getGlobalProfile("saves"), "autosave.sr2"));
			processing::resume();

			autosaveTimer = 0.0;
		}
	}

	if(reload_gui)
		tickGuiReload();

	renderFrame(devices.scripts.client, devices.scripts.client);
	inputTick();
	processing::runIsolation();
}

void tickMenu() {
	//General tick
	tickGlobal();
	renderFrame(devices.scripts.menu, devices.scripts.menu);
	inputTick();
}

std::unordered_map<std::string, time_t> monitoredFiles;
void monitorFile(const std::string& filename) {
	if(monitor_files)
		monitoredFiles[filename] = getModifiedTime(filename);
}

bool tickMonitor() {
	if(isPreloading())
		return false;

	foreach(it, monitoredFiles) {
		time_t mtime = getModifiedTime(it->first);
		if(mtime > it->second) {
			monitoredFiles.clear();
			return true;
		}
	}

	return false;
}
