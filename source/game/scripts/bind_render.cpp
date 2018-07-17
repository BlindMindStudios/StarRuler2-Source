#include "binds.h"
#include "obj/universe.h"
#include "render/camera.h"
#include "render/render_state.h"
#include "render/vertexBuffer.h"
#include "render/lighting.h"
#include "main/references.h"
#include "main/tick.h"
#include "main/logging.h"
#include "files.h"
#include "processing.h"
#include "threads.h"
#include "network/network_manager.h"

#include "obj/object.h"
#include "empire.h"

#include "frustum.h"
#include "physics/physics_world.h"

#include "scene/billboard_node.h"
#include "scene/beam_node.h"
#include "scene/plane_node.h"
#include "scene/scripted_node.h"
#include "scene/billboard_node.h"
#include "scene/mesh_icon_node.h"
#include "scene/mesh_node.h"
#include "scene/animation/anim_linear.h"
#include "scene/animation/anim_node_sync.h"
#include "scene/particle_system.h"

#include "../as_addons/include/scriptarray.h"

#include "compat/gl.h"

#include "ISoundDevice.h"

#include <string>

//Fix Windows.h being an asshole
#ifdef min
#undef min
#endif

extern double pixelSizeRatio, scale_3d;
extern Colorf fallbackNodeColor;
extern Object* fallbackNodeObject;
extern void queueDestroyTexture(const render::Texture* tex);
extern void setShaderLightRadius(unsigned,double);

namespace scripts {

template<class From, class To>
To* dynamicCast(From* f) {
	return dynamic_cast<To*>(f);
}

template<class From, class To>
To* grabbedCast(From* f) {
	To* other = dynamic_cast<To*>(f);
	if(other)
		other->grab();
	return other;
}

void takeScreenshot(const std::string& fname, bool increment = true) {
	Image* screen = devices.render->getScreen(0,0,devices.driver->win_width,devices.driver->win_height);

	std::string filename = devices.mods.getGlobalProfile("screenshots") + "/" + fname;
	if(filename.empty())
		filename = "screenshot";
	if(filename.size() > 4 && filename.compare(filename.size() - 4, 4, ".png") == 0)
		filename = filename.substr(0, filename.size() - 4);

	std::string base = filename;
	filename += ".png";

	unsigned number = 2;
	while(fileExists(filename))
		filename = base + toString(number++) + ".png";

	if(!isAccessible(filename)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return;
	}

	threads::async([screen,filename]() -> int {
		try {
			if(!saveImage(screen, filename.c_str(), true))
				throw 0;
			print("Wrote screenshot to %s", filename.c_str());
		}
		catch(...) {
			print("Could not write image");
		}

		delete screen;
		return 0;
	});
}

extern asITypeInfo* getObjectArrayType();

asITypeInfo* getNodeArrayType() {
	return (asITypeInfo*)asGetActiveContext()->GetEngine()->GetUserData(EDID_nodeArray);
}

static const render::RenderState& getErrorMat() {
	return devices.library.getErrorMaterial();
}

static const render::RenderState& getMat(const std::string& name) {
	return devices.library.getMaterial(name);
}

static const render::RenderMesh& getErrorModel() {
	return devices.library.getMesh("");
}

static const render::RenderMesh& getModel(const std::string& name) {
	return devices.library.getMesh(name);
}

static const render::RenderState& getMat_index(unsigned index) {
	if(index >= devices.library.material_names.size()) {
		scripts::throwException("Out of bounds material index");
		return *(const render::RenderState*)0;
	}
	return devices.library.getMaterial(devices.library.material_names[index]);
}

static const std::string& getMat_name(unsigned index) {
	if(index >= devices.library.material_names.size()) {
		scripts::throwException("Out of bounds material index");
		return *(const std::string*)0;
	}
	return devices.library.material_names[index];
}

static unsigned getMatCount() {
	return (unsigned)devices.library.material_names.size();
}

static const render::SpriteSheet& getErrorSheet() {
	return devices.library.getSpriteSheet("");
}

static const render::SpriteSheet& getSheet(const std::string& name) {
	return devices.library.getSpriteSheet(name);
}

static render::Sprite getSprite(const std::string& name) {
	return devices.library.getSprite(name);
}

static std::string getSpriteDesc(const render::Sprite& sprt) {
	return devices.library.getSpriteDesc(sprt);
}

static const render::SpriteSheet& getSheet_index(unsigned index) {
	if(index >= devices.library.spritesheet_names.size()) {
		scripts::throwException("Out of bounds spritesheet index");
		return *(const render::SpriteSheet*)0;
	}
	return devices.library.getSpriteSheet(devices.library.spritesheet_names[index]);
}

static const std::string& getSheet_name(unsigned index) {
	if(index >= devices.library.spritesheet_names.size()) {
		scripts::throwException("Out of bounds spritesheet index");
		return *(const std::string*)0;
	}
	return devices.library.spritesheet_names[index];
}

static unsigned getSheetCount() {
	return (unsigned)devices.library.spritesheet_names.size();
}

static const render::MaterialGroup& getMatGroup(const std::string& id) {
	return devices.library.getMaterialGroup(id);
}

static std::string getGroupMatID(render::MaterialGroup& group, unsigned index) {
	if(index < group.names.size())
		return group.names[index];
	else
		return "";
}

static const render::RenderState* getGroupMat(render::MaterialGroup& group, unsigned index) {
	if(index < group.materials.size())
		return group.materials[index];
	return nullptr;
}

static unsigned getGroupMatCount(render::MaterialGroup& group) {
	return group.materials.size();
}

static void setSkybox(const render::RenderState* mat) {
	devices.render->setSkybox(mat);
}

static void setSkyboxMesh(const render::RenderMesh* mesh) {
	devices.render->setSkyboxMesh(mesh);
}

static void draw_rect(const recti& pos, const Color& color) {
	Color colors[4] = {color, color, color, color};
	devices.render->drawRectangle(pos, 0, 0, colors, getClip());
}

static void draw_rect_m(const recti&pos, const render::RenderState* mat, const Color& color) {
	Color colors[4] = {color, color, color, color};
	devices.render->drawRectangle(pos, mat, 0, colors, getClip());
}

static void draw_rect_g(const recti& pos, const Color& topleft, const Color& topright, const Color& botright, const Color& botleft) {
	Color colors[4] = {topleft, topright, botright, botleft};
	devices.render->drawRectangle(pos, 0, 0, colors, getClip());
}

static void draw_mat(const render::RenderState* mat, const recti& pos) {
	devices.render->drawRectangle(pos, mat, 0, 0, getClip());
}

static void draw_mat_c(const render::RenderState* mat, const recti& pos, const Color& color) {
	devices.render->drawRectangle(pos, mat, color, getClip());
}

static void draw_mat_csh(const render::RenderState* mat, const recti& pos, const Color& color, const render::Shader* shader) {
	static render::RenderState state;
	state = *mat;
	state.constant = false;
	state.shader = shader;
	devices.render->drawRectangle(pos, &state, color, getClip());
}

static void draw_mat_s(const render::RenderState* mat, const recti& pos, const recti* src) {
	devices.render->drawRectangle(pos, mat, src, 0, getClip());
}

static void draw_mat_sc(const render::RenderState* mat, const recti& pos, const recti* src, const Color& color) {
	Color colors[4] = {color, color, color, color};
	devices.render->drawRectangle(pos, mat, src, colors, getClip());
}

static void draw_mat_scr(const render::RenderState* mat, const recti& pos, const recti* src, const Color& color, double rotation) {
	Color colors[4] = {color, color, color, color};
	devices.render->drawRectangle(pos, mat, src, colors, getClip(), rotation);
}

static void draw_mat_scc(const render::RenderState* mat, const recti& pos,
						const recti* src, const Color& topleft, const Color& topright,
						const Color& botright, const Color& botleft) {
	Color colors[4] = {topleft, topright, botright, botleft};
	devices.render->drawRectangle(pos, mat, src, colors, getClip());
}

static void draw_fps(const recti& pos) {
	devices.render->drawFPSGraph(pos);
}

static vec2i sprite_size(const render::SpriteSheet& sheet) {
	return vec2i(sheet.width, sheet.height);
}

static render::Sprite sprite_offset(const render::SpriteSheet& sheet, unsigned number) {
	return render::Sprite(&sheet, number);
}

static void sprite_sourceUV(const render::SpriteSheet& sheet, unsigned index, vec4f& output) {
	output = sheet.getSourceUV(index);
}

static void draw_sprite(const render::SpriteSheet& sheet, unsigned index, const recti& pos) {
	sheet.render(*devices.render, index, pos, 0, getClip());
}

static void draw_sprite_s(const render::SpriteSheet& sheet, unsigned index, const recti& pos, const render::Shader* shader) {
	sheet.render(*devices.render, index, pos, 0, getClip(), shader);
}

static void draw_sprite_c(const render::SpriteSheet& sheet, unsigned index, const recti& pos, const Color& color) {
	Color colors[4] = {color, color, color, color};
	sheet.render(*devices.render, index, pos, colors, getClip());
}

static void draw_sprite_cr(const render::SpriteSheet& sheet, unsigned index, const recti& pos, const Color& color, double rotation) {
	Color colors[4] = {color, color, color, color};
	sheet.render(*devices.render, index, pos, colors, getClip(), 0, rotation);
}

static void draw_sprite_cc(const render::SpriteSheet& sheet, unsigned index,
		const recti& pos, const Color& topleft, const Color& topright, const Color& botright, const Color& botleft) {
	Color colors[4] = {topleft, topright, botright, botleft};
	sheet.render(*devices.render, index, pos, colors, getClip());
}

static void draw_sprt(const render::Sprite* sprt, const recti& pos) {
	if(sprt->sheet)
		draw_sprite_c(*sprt->sheet, sprt->index, pos, sprt->color);
	else if(sprt->mat)
		draw_mat_c(sprt->mat, pos, sprt->color);
}

static void draw_sprt_c(const render::Sprite* sprt, const recti& pos, const Color& color) {
	if(sprt->sheet)
		draw_sprite_c(*sprt->sheet, sprt->index, pos, color * sprt->color);
	else if(sprt->mat)
		draw_mat_c(sprt->mat, pos, color * sprt->color);
}

static void draw_sprt_csh(const render::Sprite* sprt, const recti& pos, const Color& color, const render::Shader* shader) {
	Color blended = sprt->color * color;
	if(sprt->sheet) {
		Color colors[4] = {blended, blended, blended, blended};
		sprt->sheet->render(*devices.render, sprt->index, pos, colors, getClip(), shader);
	}
	else if(sprt->mat)
		draw_mat_csh(sprt->mat, pos, blended, shader);
}

static void draw_sprt_cr(const render::Sprite* sprt, const recti& pos, const Color& color, double rotation) {
	Color blended = sprt->color * color;
	if(sprt->sheet) {
		Color colors[4] = {blended, blended, blended, blended};
		sprt->sheet->render(*devices.render, sprt->index, pos, colors, getClip(), 0, rotation);
	}
	else if(sprt->mat)
		draw_mat_scr(sprt->mat, pos, 0, blended, rotation);
}

static vec2i mat_size(const render::RenderState& mat) {
	if(mat.textures[0])
		return mat.textures[0]->size;
	return vec2i();
}

static void mat_activate(const render::RenderState& mat) {
	devices.render->switchToRenderState(mat);
}

static bool mat_pxactive(const render::RenderState& mat, const vec2i& px) {
	if(mat.textures[0])
		return mat.textures[0]->isPixelActive(px);
	return false;
}

static inline void complex_clip_start() {
	if(recti* clip = getClip())
		devices.render->pushScreenClip(*clip);
}

static inline void complex_clip_end() {
	if(getClip())
		devices.render->popScreenClip();
}

static void getVideoModes(CScriptArray* arr) {
	std::vector<os::OSDriver::VideoMode> modes;
	devices.driver->getVideoModes(modes);

	arr->Resize(modes.size());
	for(unsigned i = 0, cnt = modes.size(); i < cnt; ++i)
		*(os::OSDriver::VideoMode*)arr->At(i) = modes[i];
}

static void getMonitorNames(CScriptArray* arr) {
	std::vector<std::string> names;
	devices.driver->getMonitorNames(names);

	arr->Resize(names.size());
	for(unsigned i = 0, cnt = names.size(); i < cnt; ++i)
		*(std::string*)arr->At(i) = names[i];
}

static void setVsync(int frames) {
	devices.driver->setVerticalSync(frames);
}

static void getAudioNames(CScriptArray* arr) {
	std::vector<std::string> names;
	audio::enumerateDevices([&](const char* name) { names.push_back(name); });

	arr->Resize(names.size());
	for(unsigned i = 0, cnt = names.size(); i < cnt; ++i)
		*(std::string*)arr->At(i) = names[i];
}

render::VertexTCV* verts = 0;
unsigned allocatedVerts = 0;
unsigned nextIndex = 0;
Color vertCol;
bool flushVB = false;

static inline render::VertexTCV* getNextVertex() {
	if(nextIndex < allocatedVerts)
		return &verts[nextIndex++];
	else
		return 0;
}

static void poly_start_c(unsigned polyCount, const render::RenderState* mat, const Color& col) {
	if(polyCount == 0)
		return;

	if(mat == 0) {
		devices.render->set2DRenderState();
		mat = devices.render->getLastRenderState();
	}

	if(getClip()) {
		render::renderVertexBuffers();
		flushVB = true;
	}
	else if(!mat->constant) {
		flushVB = true;
	}

	auto* buffer = render::VertexBufferTCV::fetch(mat);
	verts = buffer->request(polyCount, render::PT_Triangles);
	allocatedVerts = 3 * polyCount;
	vertCol = col;

	complex_clip_start();
}

static void poly_start(unsigned polyCount, const render::RenderState* mat) {
	poly_start_c(polyCount, mat, Color());
}

static void poly_start_t(render::PrimitiveType type, unsigned polyCount, const render::RenderState* mat) {
	if(polyCount == 0)
		return;

	if(mat == 0) {
		devices.render->set2DRenderState();
		mat = devices.render->getLastRenderState();
	}

	if(getClip()) {
		render::renderVertexBuffers();
		flushVB = true;
	}
	else if(!mat->constant) {
		flushVB = true;
	}

	auto* buffer = render::VertexBufferTCV::fetch(mat);
	verts = buffer->request(polyCount, type);
	vertCol = Color();

	switch(type) {
	case render::PT_Lines:
		allocatedVerts = 2 * polyCount; break;
	case render::PT_LineStrip:
		allocatedVerts = 1 + polyCount; break;
	case render::PT_Triangles:
		allocatedVerts = 3 * polyCount; break;
	case render::PT_Quads:
		allocatedVerts = 4 * polyCount; break;
	}

	complex_clip_start();
}

static void poly_end() {
	if(allocatedVerts == 0)
		return;

	if(flushVB) {
		render::renderVertexBuffers();
		complex_clip_end();
		flushVB = false;
	}

	allocatedVerts = 0;
	nextIndex = 0;
}

static void poly_coord(const vec2i& pos) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = vec2f();
		vert->pos.x = float(pos.x);
		vert->pos.y = float(pos.y);
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_coord_uv(const vec2i& pos, const vec2f& uv) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = uv;
		vert->pos.x = float(pos.x);
		vert->pos.y = float(pos.y);
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_coord_uvc(const vec2i& pos, const vec2f& uv, const Color& col) {
	if(auto* vert = getNextVertex()) {
		vertCol = col;
		vert->col = col;
		vert->uv = uv;
		vert->pos.x = float(pos.x);
		vert->pos.y = float(pos.y);
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_coord_c(const vec2i& pos, const Color& col) {
	if(auto* vert = getNextVertex()) {
		vertCol = col;
		vert->col = col;
		vert->uv = vec2f();
		vert->pos.x = float(pos.x);
		vert->pos.y = float(pos.y);
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_fcoord(const vec2f& pos) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = vec2f();
		vert->pos.x = pos.x;
		vert->pos.y = pos.y;
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_fcoord_uv(const vec2f& pos, const vec2f& uv) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = uv;
		vert->pos.x = pos.x;
		vert->pos.y = pos.y;
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly_fcoord_c(const vec2f& pos, const Color& col) {
	if(auto* vert = getNextVertex()) {
		vertCol = col;
		vert->col = col;
		vert->uv = vec2f();
		vert->pos.x = pos.x;
		vert->pos.y = pos.y;
		vert->pos.z = 0;
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly3_coord(const vec3d& pos) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = vec2f();

		vert->pos = vec3f(pos - devices.render->cam_pos);
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly3_coord_uv(const vec3d& pos, const vec2f& uv) {
	if(auto* vert = getNextVertex()) {
		vert->col = vertCol;
		vert->uv = uv;

		vert->pos = vec3f(pos - devices.render->cam_pos);
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly3_coord_uvc(const vec3d& pos, const vec2f& uv, const Color& col) {
	if(auto* vert = getNextVertex()) {
		vertCol = col;
		vert->col = col;
		vert->uv = uv;

		vert->pos = vec3f(pos - devices.render->cam_pos);
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void poly3_coord_c(const vec3d& pos, const Color& col) {
	if(auto* vert = getNextVertex()) {
		vertCol = col;
		vert->col = col;
		vert->uv = vec2f();

		vert->pos = vec3f(pos - devices.render->cam_pos);
	}
	else {
		scripts::throwException("Attempted to write to more vertices than were allocated.");
	}
}

static void draw_line_c(const vec2i& from, const vec2i& to, const Color& color, int size, const render::RenderState* mat) {
	double angle = (to - from).radians();
	vec2d off(cos(angle-1.5708) * double(size) * 0.5, sin(angle-1.5708) * double(size) * 0.5);

	vec2d fTo(to);
	vec2d fFrom(from);

	poly_start_t(render::PT_Quads, 1, mat);
	
	poly_coord_uvc(vec2i(fFrom - off), vec2f(0,0), color);
	poly_coord_uv(vec2i(fFrom + off), vec2f(0,1));
	poly_coord_uv(vec2i(fTo + off), vec2f(1,1));
	poly_coord_uv(vec2i(fTo - off), vec2f(1,0));

	poly_end();
}

static void draw_line(const vec2i& from, const vec2i& to, int size, const render::RenderState* mat) {
	draw_line_c(from, to, Color(0xffffffff), size, mat);
}

static void draw_model(render::RenderMesh* mesh, render::RenderState* mat, recti& pos, quaterniond rotation, double Scale) {
	render::renderVertexBuffers();

	vec2i center = pos.getCenter();
	double scale = (double)std::min(pos.getWidth(), pos.getHeight()) * 0.5 * Scale;

	complex_clip_start();
	Matrix transform;

	rotation.toTransform(transform, vec3d(center.x, center.y, 0), vec3d(scale, -scale, scale));

	devices.render->setTransformationAbs(transform);
	if(mat)
		devices.render->switchToRenderState(*mat);
	else
		devices.render->setDefaultRenderState();
	mesh->render();
	devices.render->resetTransformation();
	complex_clip_end();
}

static void drawBuffers() {
	render::renderVertexBuffers();
}

static void meshRenderLOD(render::RenderMesh* mesh, double lodDist) {
	mesh->selectLOD(lodDist)->render();
}

static render::Camera* cameraFactory() {
	return new render::Camera();
}

static void updateCamera(render::Camera& cam) {
	devices.render->setCameraData(cam);
}

static void prepareRender(render::Camera& cam) {
	devices.render->prepareRender3D(cam);
}

static void prepareRenderClip(render::Camera& cam, const recti& clip) {
	devices.render->prepareRender3D(cam, &clip);
}

static void renderWorld() {
	devices.render->renderWorld();
}

static Object* objectFromPixel(render::Camera& cam, const vec2i& px) {
	if(devices.universe) {
		Object* obj = devices.universe->getClosestOnLine(
			cam.screenToRay(
			(double)px.x / ((double)devices.driver->win_width / ui_scale),
			(double)px.y / ((double)devices.driver->win_height / ui_scale)
			));
		if(obj)
			obj->grab();
		return obj;
	}
	else {
		return 0;
	}
}

static double cam_dist(const vec3d& pos, double scale) {
	auto fromCamera = pos + (devices.render->cam_facing * scale) - devices.render->cam_pos;
	return fromCamera.getLength();
}

static vec3d cam_pos() {
	return devices.render->cam_pos;
}

static vec3d cam_up() {
	return devices.render->cam_up;
}

static vec3d cam_facing() {
	return devices.render->cam_facing;
}

static bool isInView(const vec3d& center, double radius) {
	return devices.render->getViewFrustum().overlaps(center, radius);
}

static ObjArray* boxSelect(render::Camera& cam, const recti& box) {
	ObjArray* results = new ObjArray();
	results->reserve(100);

	vec2i screenSize = vec2i(devices.driver->win_width, devices.driver->win_height);

	rectd boxd = rectd( double(box.topLeft.x) / double(screenSize.width),
						double(box.topLeft.y) / double(screenSize.height),
						double(box.botRight.x) / double(screenSize.width),
						double(box.botRight.y) / double(screenSize.height));

	frustum ViewFrustum = frustum(  cam.screenToRay(boxd.topLeft.x, boxd.topLeft.y),
									cam.screenToRay(boxd.botRight.x, boxd.topLeft.y),
									cam.screenToRay(boxd.topLeft.x, boxd.botRight.y),
									cam.screenToRay(boxd.botRight.x, boxd.botRight.y) );

	Empire* player = Empire::getPlayerEmpire();

	devices.nodePhysics->findInBox(ViewFrustum.bound,
		[&results,&ViewFrustum,player](const PhysicsItem& item) {
			scene::Node* node = item.node;
			if(!node || !node->frameVisible || !node->obj)
				return;
			bool inFrustum;
			inFrustum = ViewFrustum.overlaps(node->position, node->abs_scale);

			if(inFrustum) {
				node->obj->grab();
				results->push_back(node->obj);
			}
		}
	);

	return results;
}

static void nodeConeSelect(const line3dd& line, double slope, CScriptArray* results) {
	results->Resize(0);

	if(!devices.nodePhysics)
		return;

	results->Reserve(100);

	AABBoxd bound(line);
	bound.addBox(AABBoxd::fromCircle(line.end, line.getLength() * slope));

	vec3d dir = line.getDirection();
	planed clip(line.start, dir);

	devices.nodePhysics->findInBox(bound,
		[&](const PhysicsItem& item) {
			if(item.type == PIT_Node) {
				auto* node = item.node;
				if(!node->frameVisible)
					return;

				const vec3d& pos = node->abs_position;
				double dist = clip.distanceFromPlane(pos);
				//Only select node after the start of the line
				if(dist < 0.0)
					return;

				//Collide sphere with cone
				vec3d pt = line.start + dir * dist;
				double dSq = pt.distanceToSQ(pos);

				double rad = node->abs_scale;
				if(dSq < rad * rad) {
					results->InsertLast(&node);
				}
				else if(!node->getFlag(scene::NF_FixedSize)) {
					rad += dist * slope;
					if(dSq < rad * rad) {
						results->InsertLast(&node);
					}
				}
			}
		}
	);
}

static void renderBillboard(const render::RenderState& mat, const vec3d& pos, double width, double rotation) {
	devices.render->drawBillboard(pos, width, mat, rotation);
}

static void renderBillboard_sheet(const render::SpriteSheet& sheet, unsigned index, const vec3d& pos, double width, double rotation) {
	devices.render->drawBillboard(pos, width, sheet.material, sheet.getSource(index), rotation);
}

static void renderBillboard_sprite(const render::Sprite& sprite, const vec3d& pos, double width, double rotation) {
	if(sprite.mat)
		renderBillboard(*sprite.mat, pos, width, rotation);
	else if(sprite.sheet)
		renderBillboard_sheet(*sprite.sheet, sprite.index, pos, width, rotation);
}

static void renderBillboard_c(const render::RenderState& mat, const vec3d& pos, double width, double rotation, Color& color) {
	devices.render->drawBillboard(pos, width, mat, rotation, &color);
}

static void renderBillboard_sheet_c(const render::SpriteSheet& sheet, unsigned index, const vec3d& pos, double width, double rotation, Color& color) {
	devices.render->drawBillboard(pos, width, sheet.material, sheet.getSource(index), rotation, color);
}

static void renderBillboard_sprite_c(const render::Sprite& sprite, const vec3d& pos, double width, double rotation, Color& color) {
	if(sprite.mat)
		renderBillboard_c(*sprite.mat, pos, width, rotation, color);
	else if(sprite.sheet)
		renderBillboard_sheet_c(*sprite.sheet, sprite.index, pos, width, rotation, color);
}

static void renderPlane(const render::RenderState& mat, const vec3d& pos, double width, Color& color, double angle) {
	vec3d tr;
	vec3d tl;
	if(angle != 0.0) {
		double cn = cos(angle), sn = sin(angle);
		vec3d r = vec3d(cn * width, 0.0, sn * width);
		vec3d u = vec3d(-sn * width, 0.0, cn * width);

		tr = r + u;
		tl = u - r;
	}
	else {
		tr = vec3d(width, 0.0, width);
		tl = vec3d(-width, 0.0, width);
	}

	vec3d verts[] = {
		pos - tr,
		pos - tl,
		pos + tr,
		pos + tl
	};

	vec2f uvs[] = { vec2f(0,0), vec2f(1,0), vec2f(1,1), vec2f(0,1) };
	Color colors[] = { color, color, color, color };

	devices.render->switchToRenderState(mat);
	devices.render->drawQuad(verts, uvs, colors);
}

render::Camera& copyCamera(render::Camera& dest, render::Camera& src) {
	dest = src;
	return dest;
}

#define decl_access(member, type) \
	void set_##member(type v) {\
		member = v;\
	}\
	type get_##member() {\
		return member;\
	}\

#define bind_access(member, type) \
	mat.addMethod(#type " get_" #member "() const", asMETHOD(ScriptMaterial, get_##member));\
	mat.addMethod("void set_" #member "(" #type " value)", asMETHOD(ScriptMaterial, set_##member));

struct ScriptMaterial : public render::RenderState {
	threads::atomic_int refs;

	ScriptMaterial(const ScriptMaterial& other) : refs(1) {
		*(render::RenderState*)this = *(render::RenderState*)&other;
		constant = false;
		culling = render::FC_None;
		depthTest = render::DT_Always;
		depthWrite = true;
		lighting = false;
		baseMat = render::MAT_Alpha;
	}

	ScriptMaterial() : RenderState(), refs(1) {
		constant = false;
		culling = render::FC_None;
		depthTest = render::DT_Always;
		depthWrite = true;
		lighting = false;
		baseMat = render::MAT_Alpha;
	}

	decl_access(culling, render::FaceCulling);
	decl_access(depthTest, render::DepthTest);
	decl_access(baseMat, render::BaseMaterial);
	decl_access(drawMode, render::DrawMode);
	decl_access(depthWrite, bool);
	decl_access(constant, bool);
	decl_access(lighting, bool);
	decl_access(normalizeNormals, bool);
	decl_access(wrapHorizontal, render::TextureWrap);
	decl_access(wrapVertical, render::TextureWrap);
	decl_access(filterMin, render::TextureFilter);
	decl_access(filterMag, render::TextureFilter);
	decl_access(mipmap, bool);
	decl_access(cachePixels, bool);

	ScriptMaterial& assign(const render::RenderState& other) {
		*(render::RenderState*)this = other;
		constant = false;
		return *this;
	}

	void* operator new(size_t size) {
		return ::operator new(size);
	}

	void operator delete(void* address) {
		::operator delete(address);
	}

	void grab() {
		if(!constant) {
			++refs;
		}
	}

	void drop() {
		if(!constant) {
			if(!--refs)
				delete this;
		}
	}
};

ScriptMaterial* createMat() {
	return new ScriptMaterial();
}

ScriptMaterial* copyMat(const ScriptMaterial& other) {
	return new ScriptMaterial(other);
}

static void createSprite_e(void* memory) {
	new(memory) render::Sprite();
}

static void createSprite(void* memory, const render::SpriteSheet* sheet, unsigned index) {
	new(memory) render::Sprite(sheet, index);
}

static void createSprite_mat(render::Sprite* memory, const render::RenderState* material) {
	new(memory) render::Sprite(material);
}

static void createSprite_c(render::Sprite* memory, const render::SpriteSheet* sheet, unsigned index, const Color& color) {
	new(memory) render::Sprite(sheet, index);
	memory->color = color;
}

static void createSprite_mat_c(render::Sprite* memory, const render::RenderState* material, const Color& color) {
	new(memory) render::Sprite(material);
	memory->color = color;
}

static void delSprite(render::Sprite* sprite) {
	sprite->~Sprite();
}

static vec2i spriteSize(render::Sprite& sprite) {
	if(sprite.sheet) {
		return vec2i(sprite.sheet->width, sprite.sheet->height);
	}
	else if(sprite.mat) {
		auto* tex = sprite.mat->textures[0];
		if(tex)
			return tex->size;
	}
	return vec2i(0, 0);
}

static double spriteAspect(render::Sprite& sprite) {
	double w = 0.0, h = 0.0;
	if(sprite.sheet) {
		w = sprite.sheet->width;
		h = sprite.sheet->height;
	}
	else if(sprite.mat) {
		auto* tex = sprite.mat->textures[0];
		if(tex) {
			w = tex->size.width;
			h = tex->size.height;
		}
	}
	if(h == 0.0)
		return 1.0;
	return w / h;
}

static render::Sprite& copySprite(render::Sprite& into, const render::Sprite& other) {
	into = other;
	return into;
}

static bool spriteValid(render::Sprite& sprt) {
	if(sprt.mat == nullptr && sprt.sheet == nullptr)
		return false;
	if(sprt.mat == &devices.library.getErrorMaterial())
		return false;
	if(sprt.sheet == &devices.library.getErrorSpriteSheet())
		return false;
	return true;
}

static render::Sprite spriteColorized(render::Sprite& sprt, const Color& color, float blend = 1.f) {
	render::Sprite newsprt = sprt;
	newsprt.color = newsprt.color.getInterpolated(color, blend);
	return newsprt;
}

static render::Sprite sprt_color(render::Sprite& sprt, const Color& color) {
	render::Sprite newsprt = sprt;
	newsprt.color = newsprt.color * color;
	return newsprt;
}

class CreateNodePhysics : public scene::NodeEvent {
public:
	CreateNodePhysics(scene::Node* node) : NodeEvent(node) {}

	void process() override {
		if(!node->physics && devices.nodePhysics)
			node->createPhysics();
	}
};

void makeNodePhysics(scene::Node* node) {
	scene::queueNodeEvent(new CreateNodePhysics(node));
}

class SetNodeObject : public scene::NodeEvent {
	Object* object;
public:
	SetNodeObject(scene::Node* node, Object* obj) : NodeEvent(node), object(obj) {
	}

	~SetNodeObject() {
		if(object)
			object->drop();
	}

	void process() override {
		node->setObject(object);
	}
};

void setNodeObject(scene::Node* node, Object* obj) {
	scene::queueNodeEvent(new SetNodeObject(node, obj));
}

template<scene::NodeFlag flag>
void setNodeFlag(scene::Node& node, bool state) {
	node.setFlag(flag, state);
}

template<scene::NodeFlag flag>
bool getNodeFlag(scene::Node& node) {
	return node.getFlag(flag);
}

template<scene::NodeFlag flag>
void setNodeFlagInv(scene::Node& node, bool state) {
	node.setFlag(flag, !state);
}

void pushNodeTransform(scene::Node& node) {
	devices.render->setTransformation(node.transformation);
}

void renderNode(scene::Node& node) {
	node.render(*devices.render);
}

void animateNode(scene::Node& node, double frameLen) {
	int frameLenMS = (int)(frameLen * 1000.0);
	std::swap(frameLen, frameLen_s);
	std::swap(frameLenMS, frameLen_ms);
	node.animate();
	std::swap(frameLenMS, frameLen_ms);
	std::swap(frameLen, frameLen_s);
}

bool isNodeInView(const scene::Node& node) {
	return devices.render->getViewFrustum().overlaps(node.abs_position, node.abs_scale);
}

void applyTransform(const vec3d& pos, const vec3d& scale, const quaterniond& rot) {
	Matrix transform;
	rot.toTransform(transform, pos, scale);
	devices.render->setTransformation(transform);
}

void applyAbsTransform(const vec3d& pos, const vec3d& scale, const quaterniond& rot) {
	Matrix transform;
	rot.toTransform(transform, pos, scale);
	devices.render->setTransformationAbs(transform);
}

void applyBBTransform(const vec3d& pos, double width, double rot) {
	devices.render->setBBTransform(pos, width, rot);
}

void popTransform() {
	devices.render->resetTransformation();
}

void getBBVecs(vec3d& upLeft, vec3d& upRight, double rot) {
	devices.render->getBillboardVecs(upLeft, upRight, rot);
}

void getBBVecsFacing(const vec3d& pos, vec3d& upLeft, vec3d& upRight, double rot) {
	devices.render->getBillboardVecs(pos, upLeft, upRight, rot);
}

void nodeSyncObject(scene::Node* node, Object* obj) {
	node->animator = scene::NodeSyncAnimator::getSingleton();
	node->scale = node->abs_scale = obj->radius;
	node->position = node->abs_position = obj->position;
	node->rotation = obj->rotation;
	node->setObject(obj);
}

scene::BeamNode* makeBeam(const render::RenderState* mat, float width, const vec3d& startPoint, const vec3d& endPoint, bool staticSize) {
	auto* node = new scene::BeamNode(mat, width, startPoint, endPoint, staticSize);
	if(processing::isRunning())
		node->queueReparent(devices.scene);
	else
		devices.scene->addChild(node);
	return node;
}

scene::SpriteNode* makeBillboard(const render::Sprite& sprt, float width) {
	auto* node = new scene::SpriteNode(sprt, width);
	if(processing::isRunning())
		node->queueReparent(devices.scene);
	else
		devices.scene->addChild(node);
	return node;
}

scene::PlaneNode* makePlane(const render::RenderState* mat, double size) {
	auto* node = new scene::PlaneNode(mat, size);
	if(processing::isRunning())
		node->queueReparent(devices.scene);
	else
		devices.scene->addChild(node);
	return node;
}

scene::MeshNode* makeMesh(const render::RenderMesh* mesh, const render::RenderState* mat) {
	auto* node = new scene::MeshNode(mesh, mat);
	if(processing::isRunning())
		node->queueReparent(devices.scene);
	else
		devices.scene->addChild(node);
	return node;
}

template<class T>
void setShaderValue(asIScriptGeneric* f) {
	auto* shader = (resource::ShaderGlobal*)f->GetFunction()->GetUserData();
	unsigned index = f->GetArgDWord(0);
	T* v = (T*)f->GetArgAddress(1);
	shader->setValue<T>(index, *v);
}

const scene::ParticleSystemDesc* getParticleSystem(const std::string& name) {
	return devices.library.getParticleSystem(name);
}

scene::ParticleSystem* playParticleSys(const std::string& name, const vec3d& position, float scale, scene::Node* parent) {
	auto* ps = scene::playParticleSystem(devices.library.getParticleSystem(name), parent, position, quaterniond(), vec3d(), scale);
	if(parent)
		parent->drop();
	return ps;
}

scene::ParticleSystem* playParticleSys_ps(scene::ParticleSystemDesc* desc, const vec3d& position, float scale, scene::Node* parent) {
	auto* ps = scene::playParticleSystem(desc, parent, position, quaterniond(), vec3d(), scale);
	if(parent)
		parent->drop();
	return ps;
}

struct PlayParticles : public scene::NodeEvent {
	heldPointer<Object> parent;
	const scene::ParticleSystemDesc* desc;
	vec3d position;
	quaterniond rotation;
	float scale;

	PlayParticles(const scene::ParticleSystemDesc* sys, const vec3d& pos, const quaterniond& rot, float Scale, Object* Parent = nullptr)
		: scene::NodeEvent(nullptr), desc(sys), position(pos), rotation(rot), scale(Scale), parent(Parent) {}

	void process() override {
		scene::Node* pnode = nullptr;
		vec3d vel;
		quaterniond rot = rotation;
		if(parent) {
			pnode = parent->node;
			vel = parent->velocity;
		}
		auto* ps = scene::playParticleSystem(desc, pnode, position, rotation, vel, scale);
		if(ps)
			ps->drop();
	}
};

void playParticleSys_server(const std::string& name, const vec3d& position, const quaterniond& rot, float scale, unsigned mask, bool transmit) {
	if(auto* player = Empire::getPlayerEmpire())
		if(player->visionMask & mask)
			scene::queueNodeEvent(new PlayParticles(devices.library.getParticleSystem(name), position, rot, scale));
	if(transmit && devices.network->isServer)
		devices.network->sendParticleSystem(name, position, vec3d(), rot, scale, mask);
}

void playParticleSys_server_o(const std::string& name, const vec3d& position, const quaterniond& rot, float scale, Object* obj, bool transmit) {
	if(auto* player = Empire::getPlayerEmpire())
		if(obj->isVisibleTo(player))
			scene::queueNodeEvent(new PlayParticles(devices.library.getParticleSystem(name), position, rot, scale, obj));
	if(transmit && devices.network->isServer)
		devices.network->sendParticleSystem(name, position, vec3d(), rot, scale, obj);
}

class ScriptRenderTarget : public AtomicRefCounted {
public:
	render::Texture* rt;
	scene::Node* node;
	render::Camera* camera;
	double nextFrame;

	ScriptRenderTarget(const vec2i& size) : nextFrame(0.0) {
		rt = devices.render->createRenderTarget(size);
		node = new scene::Node();
		camera = new render::Camera();
	}

	~ScriptRenderTarget() {
		delete rt;
		if(node)
			node->drop();
		if(camera)
			camera->drop();
	}

	void resize(const vec2i& size) {
		delete rt;
		rt = devices.render->createRenderTarget(size);
	}

	bool isValid() {
		return rt != nullptr;
	}

	void set() {
		devices.render->setRenderTarget(rt);
	}

	void reset() {
		devices.render->setRenderTarget(nullptr);
	}

	void animate(double time) {
		nextFrame += time;
	}

	void draw(const recti& rect) {
		render::renderVertexBuffers();
		set();
		camera->animate(nextFrame);
		devices.render->prepareRender3D(*camera);
		devices.render->setCameraData(*camera);
		camera->setRenderConstraints(1.0, 1000.0, 70.0, (double)rect.getWidth() / (double)rect.getHeight(), rect.getWidth(), rect.getHeight());
		{
			int frameLenMS = (int)(nextFrame * 1000.0);
			std::swap(nextFrame, frameLen_s);
			std::swap(frameLenMS, frameLen_ms);
			node->animate();
			std::swap(frameLenMS, frameLen_ms);
			std::swap(nextFrame, frameLen_s);
			nextFrame = 0.0;
		}
		
		node->_render(*devices.render);
		render::renderVertexBuffers();
		reset();

		render::RenderState mat;
		mat.textures[0] = rt;
		mat.lighting = false;
		mat.constant = false;
		mat.depthTest = render::DT_Always;
		mat.culling = render::FC_None;

		devices.render->prepareRender2D();
		devices.render->drawRectangle(rect, &mat, Color(), getClip());
	}
};

ScriptRenderTarget* makeRenderTarget(const vec2i& size) {
	return new ScriptRenderTarget(size);
}

struct ImageLoadData {
	std::string fname;
	Image* img;
	bool loaded;
	bool piped;
	bool owned;

	void prepLoad(const std::string& filename) {
		if(img) {
			delete img;
			img = 0;
		}

		loaded = false;
		piped = false;
		fname = filename;
	}

	ImageLoadData() : img(nullptr), loaded(true), piped(true), owned(false) {
	}

	~ImageLoadData() {
		delete img;
	}
};

class DynamicTexture;
struct ScriptImage;

extern Image* getInternalImage(ScriptImage* img);

struct LoadRef {
	DynamicTexture* tex;
	ImageLoadData* dat;
};

threads::threadreturn threadcall ImageLoadThread(void* ptr);

class DynamicTexture : public AtomicRefCounted {
public:
	ScriptMaterial* state;
	ImageLoadData images[RENDER_MAX_TEXTURES];

	DynamicTexture() {
		state = new ScriptMaterial();
	}

	~DynamicTexture() {
		for(unsigned i = 0; i < RENDER_MAX_TEXTURES; ++i) {
			if(state->textures[i] && images[i].owned)
				queueDestroyTexture(state->textures[i]);
			state->textures[i] = nullptr;
		}
		state->drop();
	}

	bool isLoaded(unsigned index = 0) {
		if(index >= RENDER_MAX_TEXTURES)
			return false;
		return images[index].loaded;
	}

	vec2i getSize(unsigned index = 0) {
		if(index >= RENDER_MAX_TEXTURES || !images[index].loaded || !images[index].img)
			return vec2i();
		return vec2i(images[index].img->width, images[index].img->height);
	}

	void load(const std::string& filename, unsigned index = 0) {
		if(index >= RENDER_MAX_TEXTURES)
			return;
		if(!images[index].loaded) {
			error("Attempting to load an image before previous completed.");
			return;
		}

		images[index].prepLoad(filename);
		if(!state->textures[index])
			state->textures[index] = (render::Texture*)devices.library.getErrorTexture();

		LoadRef* ref = new LoadRef();
		ref->dat = &images[index];
		ref->tex = this;
		grab();
		threads::createThread(ImageLoadThread, ref);
	}

	void set(unsigned index, const ScriptImage* img) {
		if(!img)
			return;
		//TODO: Setting an image to overlap an existing texture will break things
		if(index < RENDER_MAX_TEXTURES) {
			auto& load = images[index];
			if(load.loaded) {
				load.prepLoad("");
				load.img = new Image(*getInternalImage((ScriptImage*)img));
				load.loaded = true;
				load.piped = false;
			}
		}
	}

	bool stream() {
		//Load images into the GPU
		bool loaded = true;
		for(unsigned i = 0; i < RENDER_MAX_TEXTURES; ++i) {
			auto& img = images[i];
			if(!img.piped) {
				if(img.loaded) {
					if(img.img) {
						auto*& tex = state->textures[i];
						if(!tex || !img.owned) {
							tex = devices.render->createTexture();
							img.owned = true;
						}
						tex->load(*img.img, state->mipmap, state->cachePixels);
					}
					img.piped = true;
				}
				else {
					loaded = false;
				}
			}
		}
		return loaded;
	}

	void draw(const recti& pos, const Color& color) {
		//Draw the full material
		if(stream()) {
			Color colors[4] = {color, color, color, color};
			devices.render->drawRectangle(pos, state, 0, colors, getClip());
		}
	}
};

DynamicTexture* makeDynamicTexture() {
	return new DynamicTexture();
}

threads::threadreturn threadcall ImageLoadThread(void* ptr) {
	LoadRef* ref = (LoadRef*)ptr;
	ImageLoadData* dat = ref->dat;

	dat->img = loadImage(dat->fname.c_str());
	dat->loaded = true;

	ref->tex->drop();
	delete ref;

	return 0;
}

const unsigned MAX_LIGHTS = 8;
unsigned activeLights = 0;
render::light::PointLight lights[MAX_LIGHTS];

void lightEnable(render::light::PointLight* light) {
	if(activeLights < MAX_LIGHTS) {
		vec3f nullOffset;
		setShaderLightRadius(activeLights,light->getRadius());
		light->enable(activeLights, nullOffset);
	}
}

void resetLights() {
	activeLights = 0;
	render::light::resetLights();
}

render::light::PointLight* getLight(unsigned i) {
	if(i < MAX_LIGHTS)
		return &lights[i];
	else
		return 0;
}

template<class T>
void bindNode(ClassBind& bind) {
	bind.setReferenceFuncs(asMETHOD(T,grab),asMETHOD(T,drop));
	bind.addMethod("Object@ get_object() const", asMETHOD(T,getObject));
	bind.addExternMethod("void set_object(Object@)", asFUNCTION(setNodeObject))
		doc("Changes the node's associated object. This is an asynchronous call.", "");
	bind.addMethod("void markForDeletion()", asMETHOD(T,markForDeletion))
		doc("Flags the node for destruction, removing it from the node tree and destroying it some time in the future.");

	bind.addExternMethod("void createPhysics()", asFUNCTION(makeNodePhysics))
		doc("Gives the node a physics representation in the node physics world.");
	bind.addMethod("void rebuildTransform()", asMETHOD(T,rebuildTransformation))
		doc("Recalculates the node's absolute position, scale, and rotation.");
	bind.addExternMethod("void set_transparent(bool)", asFUNCTION(setNodeFlag<scene::NF_Transparent>))
		doc("Sets whether the node should be treated as transparent.", "");
	bind.addExternMethod("void set_memorable(bool)", asFUNCTION(setNodeFlag<scene::NF_Memorable>))
		doc("Sets whether the node should be visible when the associated object is only remembered.", "");
	bind.addExternMethod("bool get_memorable()", asFUNCTION(getNodeFlag<scene::NF_Memorable>));
	bind.addExternMethod("void set_animInvis(bool)", asFUNCTION(setNodeFlagInv<scene::NF_AnimOnlyVisible>))
		doc("Sets whether the node should call preRender when invisible.", "");
	bind.addExternMethod("void set_autoCull(bool)", asFUNCTION(setNodeFlagInv<scene::NF_NoCulling>))
		doc("Sets whether the node should be automatically culled based on the camera view frustum.", "");
	bind.addExternMethod("void set_fixedSize(bool)", asFUNCTION(setNodeFlag<scene::NF_FixedSize>))
		doc("Sets whether the node is a fixed apparent size. Disables cone behavior in node searches.", "");
	bind.addExternMethod("void set_customColor(bool)", asFUNCTION(setNodeFlag<scene::NF_CustomColor>))
		doc("Sets whether this node should not receive its object's empire's color.", "");
	bind.addExternMethod("void set_needsTransform(bool)", asFUNCTION(setNodeFlagInv<scene::NF_NoMatrix>))
		doc("Sets whether the node should build its matrix when the transform is updated (e.g. for applyTransform).", "");
	bind.addExternMethod("void applyTransform()", asFUNCTION(pushNodeTransform))
		doc("Applies the node's position, scale, and rotation to the model transform.");
	bind.addExternMethod("void render()", asFUNCTION(renderNode))
		doc("Renders the node and its children.");
	bind.addExternMethod("void animate(double seconds)", asFUNCTION(animateNode))
		doc("Animates the node and its children.", "Amount of time to animate by.");
	bind.addExternMethod("bool isInView() const", asFUNCTION(isNodeInView))
		doc("Returns true if the node's bounding sphere is within the camera's view frustum.", "");
	bind.addMethod("void hintParentObject(Object@ obj, bool checkDistance = true)", asMETHOD(T,hintParentObject))
		doc("Hint that this node should be parented to an object's node.",
			"Whether to check whether the node is fully contained or assume it is.",
			"Object to hint for.");
	bind.addMethod("void reparent(Node@+ parent)", asMETHOD(T, queueReparent));
	
	bind.addMember("Colorf color", offsetof(T, color))
		doc("Color of the node (Owner color for bound nodes).");
	bind.addMember("vec3d position", offsetof(T, position))
		doc("Position relative to the parent.");
	bind.addMember("double scale", offsetof(T, scale))
		doc("Scale relative to the parent.");
	bind.addMember("double sortDistance", offsetof(T, sortDistance))
		doc("Distance to the camera for sorting.");
	bind.addMember("quaterniond rotation", offsetof(T, rotation))
		doc("Rotationg relative to the parent.");
	bind.addMember("vec3d abs_position", offsetof(T, abs_position))
		doc("Absolute position.");
	bind.addMember("double abs_scale", offsetof(T, abs_scale))
		doc("Absolute scale.");
	bind.addMember("quaterniond abs_rotation", offsetof(T, abs_rotation))
		doc("Absolute rotation.");
	bind.addMember("double distanceCutoff", offsetof(T, distanceCutoff))
		doc("Squared distance at which nodes synced to objects will not be rendered for any reason.");
	bind.addMember("bool visible", offsetof(T, visible))
		doc("Determines if the node is rendered when otherwise visible.");
	bind.addMember("bool remembered", offsetof(T, remembered))
		doc("For memorable nodes, tracks whether the associated objects is remembered.");
	bind.addMember("Node@ parent", offsetof(T, parent))
		doc("Parent node in the node tree.");
}

void bindScriptNode(ClassBind& bind) {
	bindNode<scene::ScriptedNode>(bind);
}

void reloadSettingsShaders() {
	foreach(it, devices.library.settingsShaders) {
		if((*it)->program) {
			(*it)->program->compile();
			(*it)->compile();
		}
	}
}

scene::Node* getRenderingNode() {
	auto* n = scene::renderingNode;
	if(n)
		n->grab();
	return n;
}

void setRenderingNode(scene::Node* newNode) {
	auto* n = scene::renderingNode;
	if(n)
		n->drop();
	scene::renderingNode = newNode; //reference moved from argument
}

void RegisterRenderBinds(bool decl, bool isMenu, bool server) {
	if(decl) {
		ClassBind tex("Texture", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind shd("Shader", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind light("Light", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind group("MatGroup", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind mat("Material", asOBJ_REF, 0);
		ClassBind sheet("SpriteSheet", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind sprt("Sprite", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CDA, sizeof(render::Sprite));
		return;
	}

	ClassBind tex("Texture");
	ClassBind shd("Shader");
	ClassBind light("Light");
	ClassBind mat("Material");
	ClassBind sheet("SpriteSheet");
	ClassBind sprt("Sprite");
	ClassBind group("MatGroup");

	//Library access
	mat.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(ScriptMaterial, grab));
	mat.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(ScriptMaterial, drop));
	mat.addFactory("Material@ f()", asFUNCTION(createMat));
	mat.addFactory("Material@ f(const Material&)", asFUNCTION(copyMat));

	mat.addMethod("Material& opAssign(const Material&)", asMETHOD(ScriptMaterial, assign));
	mat.addMember("Colorf diffuse", offsetof(render::RenderState, diffuse));
	mat.addMember("float shininess", offsetof(render::RenderState, shininess));
	mat.addMember("const Shader@ shader", offsetof(render::RenderState, shader));

	for(unsigned i = 0; i < RENDER_MAX_TEXTURES; ++i)
		mat.addMember(format("const Texture@ texture$1", toString(i)).c_str(),
				offsetof(render::RenderState, textures)+(i*sizeof(render::Texture*)));
	
	light.addMember("vec3f position", offsetof(render::light::PointLight,position));
	light.addMember("float att_constant", offsetof(render::light::PointLight,att_constant));
	light.addMember("float att_linear", offsetof(render::light::PointLight,att_linear));
	light.addMember("float radius", offsetof(render::light::PointLight,radius));
	light.addMember("float att_quadratic", offsetof(render::light::PointLight,att_quadratic));
	light.addMember("Colorf diffuse", offsetof(render::light::PointLight,diffuse));
	light.addMember("Colorf specular", offsetof(render::light::PointLight,specular));
	light.addExternMethod("void enable()", asFUNCTION(lightEnable));

	bind("void resetLights()", asFUNCTION(resetLights))
		doc("Resets to default lighting. State of input lights is unchanged.");
	bind("Light@ get_light(uint index)", asFUNCTION(getLight));
	bindGlobal("const uint MAX_LIGHTS", (void*)&MAX_LIGHTS);
	bindGlobal("Colorf NODE_COLOR", (void*)&fallbackNodeColor);
	bindGlobal("Object@ NODE_OBJECT", (void*)&fallbackNodeObject);

	EnumBind fc("FaceCulling");
	fc["FC_None"] = render::FC_None;
	fc["FC_Front"] = render::FC_Front;
	fc["FC_Back"] = render::FC_Back;
	fc["FC_Both"] = render::FC_Both;

	EnumBind dt("DepthTest");
	dt["DT_Never"] = render::DT_Never;
	dt["DT_Less"] = render::DT_Less;
	dt["DT_Equal"] = render::DT_Equal;
	dt["DT_LessEqual"] = render::DT_LessEqual;
	dt["DT_Greater"] = render::DT_Greater;
	dt["DT_NotEqual"] = render::DT_NotEqual;
	dt["DT_GreaterEqual"] = render::DT_GreaterEqual;
	dt["DT_Always"] = render::DT_Always;
	dt["DT_NoDepthTest"] = render::DT_NoDepthTest;

	EnumBind tw("TextureWrap");
	tw["TW_Repeat"] = render::TW_Repeat;
	tw["TW_Clamp"] = render::TW_Clamp;
	tw["TW_ClampEdge"] = render::TW_ClampEdge;
	tw["TW_Mirror"] = render::TW_Mirror;

	EnumBind tf("TextureFilter");
	tf["TF_Nearest"] = render::TF_Nearest;
	tf["TF_Linear"] = render::TF_Linear;

	EnumBind bm("BaseMaterial");
	bm["MAT_Solid"] = render::MAT_Solid;
	bm["MAT_Alpha"] = render::MAT_Alpha;
	bm["MAT_Font"] = render::MAT_Font;
	bm["MAT_Overlay"] = render::MAT_Overlay;

	EnumBind dm("DrawMode");
	dm["DM_Fill"] = render::DM_Fill;
	dm["DM_Line"] = render::DM_Line;

	bind_access(culling, FaceCulling);
	bind_access(depthTest, DepthTest);
	bind_access(baseMat, BaseMaterial);
	bind_access(drawMode, DrawMode);
	bind_access(depthWrite, bool);
	bind_access(lighting, bool);
	bind_access(normalizeNormals, bool);
	bind_access(wrapHorizontal, TextureWrap);
	bind_access(wrapVertical, TextureWrap);
	bind_access(filterMin, TextureFilter);
	bind_access(filterMag, TextureFilter);
	bind_access(mipmap, bool);
	bind_access(cachePixels, bool);
	bind_access(constant, bool);

	bind("void drawBuffers()", asFUNCTION(drawBuffers));
	
	bind("const MatGroup& getMatGroup(const string& id)", asFUNCTION(getMatGroup));
	group.addExternMethod("string getMaterialName(uint index) const", asFUNCTION(getGroupMatID));
	group.addExternMethod("const Material@ getMaterial(uint index) const", asFUNCTION(getGroupMat));
	group.addExternMethod("uint get_materialCount() const", asFUNCTION(getGroupMatCount));

	bind("const Material@ getMaterial(const string &in)", asFUNCTION(getMat));
	bind("const Material@ getMaterial(uint)", asFUNCTION(getMat_index));
	bind("const string& getMaterialName(uint)", asFUNCTION(getMat_name));
	bind("uint getMaterialCount()", asFUNCTION(getMatCount));

	ClassBind mod("Model", asOBJ_REF | asOBJ_NOCOUNT, 0);
	bind("const Model@ getModel(const string &in)", asFUNCTION(getModel));

	bind("const SpriteSheet@ getSpriteSheet(const string &in)", asFUNCTION(getSheet));
	bind("const SpriteSheet@ getSpriteSheet(uint)", asFUNCTION(getSheet_index));
	bind("const string& getSpriteSheetName(uint)", asFUNCTION(getSheet_name));
	bind("uint getSpriteSheetCount()", asFUNCTION(getSheetCount));

	sprt.addConstructor("void f()", asFUNCTION(createSprite_e));
	sprt.addConstructor("void f(const SpriteSheet@ sheet, uint index)", asFUNCTION(createSprite));
	sprt.addConstructor("void f(const Material@ mat)", asFUNCTION(createSprite_mat));
	sprt.addConstructor("void f(const SpriteSheet@ sheet, uint index, const Color& color)", asFUNCTION(createSprite_c));
	sprt.addConstructor("void f(const Material@ mat, const Color& color)", asFUNCTION(createSprite_mat_c));
	sprt.addDestructor("void f()", asFUNCTION(delSprite));
	sprt.addMember("const Material@ mat", offsetof(render::Sprite, mat));
	sprt.addMember("const SpriteSheet@ sheet", offsetof(render::Sprite, sheet));
	sprt.addMember("uint index", offsetof(render::Sprite, index));
	sprt.addMember("Color color", offsetof(render::Sprite, color));
	sprt.addExternMethod("vec2i get_size() const", asFUNCTION(spriteSize));
	sprt.addExternMethod("double get_aspect() const", asFUNCTION(spriteAspect));
	sprt.addExternMethod("Sprite& opAssign(const Sprite&in other)", asFUNCTION(copySprite));
	sprt.addExternMethod("bool get_valid() const", asFUNCTION(spriteValid));
	sprt.addExternMethod("Sprite colorized(const Color& color, float blend = 1.f) const", asFUNCTION(spriteColorized));
	sprt.addExternMethod("Sprite opMul(const Color& color) const", asFUNCTION(sprt_color));
	bind("Sprite getSprite(const string &in)", asFUNCTION(getSprite));
	bind("string getSpriteDesc(const Sprite&in)", asFUNCTION(getSpriteDesc));
	bind("void takeScreenshot(const string& filename, bool increment = true)", asFUNCTION(takeScreenshot));


	{
		Namespace ns("material");
		bind("const Material@ get_error()", asFUNCTION(getErrorMat));
		foreach(it, devices.library.materials)
			bindGlobal(format("const Material $1", it->first).c_str(), it->second);
	}

	{
		Namespace ns("model");
		bind("const Model@ get_error()", asFUNCTION(getErrorModel));
		foreach(it, devices.library.meshes)
			bindGlobal(format("const Model $1", it->first).c_str(), it->second);
	}

	{
		Namespace ns("spritesheet");
		bind("const SpriteSheet@ get_error()", asFUNCTION(getErrorSheet));
		foreach(it, devices.library.spritesheets)
			bindGlobal(format("const SpriteSheet $1", it->first).c_str(), it->second);
	}

	if(!isMenu) {
		ClassBind node("Node", asOBJ_REF);
		bindNode<scene::Node>(node);

		bind("Node@ get_renderingNode()", asFUNCTION(getRenderingNode));
		bind("void set_renderingNode(Node@ node)", asFUNCTION(setRenderingNode));

		asIScriptEngine* engine = getEngine();
		asITypeInfo* nodeArrayType = engine->GetTypeInfoById(engine->GetTypeIdByDecl("array<Node@>"));
		engine->SetUserData(nodeArrayType, EDID_nodeArray);

		bind("void nodeConeSelect(const line3dd &in line, double slope, array<Node@>&)", asFUNCTION(nodeConeSelect));
		bind("void nodeSyncObject(Node& node, Object& obj)", asFUNCTION(nodeSyncObject));

		ClassBind bb("BillboardNode", asOBJ_REF);
		bb.addFactory("BillboardNode@ f(const Sprite& sprt, float width)",
				asFUNCTION(makeBillboard));
		bb.addMember("Sprite sprite", offsetof(scene::SpriteNode, sprite));
		bb.addMember("float width", offsetof(scene::SpriteNode, width));
		bindNode<scene::SpriteNode>(bb);


		node.addExternMethod("BillboardNode@ opCast() const", asFUNCTION((grabbedCast<scene::Node,scene::SpriteNode>)));
		bb.addExternMethod("Node@ opImplCast() const", asFUNCTION((grabbedCast<scene::SpriteNode,scene::Node>)));

		ClassBind beam("BeamNode", asOBJ_REF);
		beam.addFactory("BeamNode@ f(const Material& mat, float width, const vec3d&in startPoint, const vec3d&in endPoint, bool staticSize = false)",
				asFUNCTION(makeBeam));
		beam.addMember("bool staticSize", offsetof(scene::BeamNode, staticSize));
		beam.addMember("float width", offsetof(scene::BeamNode, width));
		beam.addMember("vec3d endPosition", offsetof(scene::BeamNode, endPosition));
		bindNode<scene::BeamNode>(beam);

		node.addExternMethod("BeamNode@ opCast() const", asFUNCTION((grabbedCast<scene::Node,scene::BeamNode>)));
		beam.addExternMethod("Node@ opImplCast() const", asFUNCTION((grabbedCast<scene::BeamNode,scene::Node>)));

		ClassBind plane("PlaneNode", asOBJ_REF);
		plane.addMember("const Material@ material", offsetof(scene::PlaneNode, material));
		plane.addMember("float minRad", offsetof(scene::PlaneNode, minRad));
		plane.addMember("float maxRad", offsetof(scene::PlaneNode, maxRad));
		plane.addFactory("PlaneNode@ f(const Material& mat, double size)",
				asFUNCTION(makePlane));
		bindNode<scene::PlaneNode>(plane);

		node.addExternMethod("PlaneNode@ opCast() const", asFUNCTION((grabbedCast<scene::Node,scene::PlaneNode>)));
		plane.addExternMethod("Node@ opImplCast() const", asFUNCTION((grabbedCast<scene::PlaneNode,scene::Node>)));

		ClassBind mesh("MeshNode", asOBJ_REF);
		mesh.addMember("const Model@ model", offsetof(scene::MeshNode, mesh));
		mesh.addMember("const Material@ material", offsetof(scene::MeshNode, material));

		node.addExternMethod("MeshNode@ opCast() const", asFUNCTION((grabbedCast<scene::Node,scene::MeshNode>)));
		mesh.addExternMethod("Node@ opImplCast() const", asFUNCTION((grabbedCast<scene::MeshNode,scene::Node>)));

		mesh.addFactory("MeshNode@ f(const Model& model, const Material& mat)",
				asFUNCTION(makeMesh));
		bindNode<scene::MeshNode>(mesh);
	}

	if(server) {
		bind("void playParticleSystem(const string& name, const vec3d& position, const quaterniond& rot, float scale = 1, uint mask = 4294967295, bool networked = true)", asFUNCTION(playParticleSys_server));
		bind("void playParticleSystem(const string& name, const vec3d& position, const quaterniond& rot, float scale, Object& parent, bool networked = true)", asFUNCTION(playParticleSys_server_o));
		return;
	}

	{
		Namespace ns("shader");
		bind("void reloadSettingsShaders()", asFUNCTION(reloadSettingsShaders));
		foreach(it, devices.library.shaders)
			bindGlobal(format("const ::Shader $1", it->first).c_str(), it->second);

		devices.library.iterateShaderGlobals([&](std::string& name, resource::ShaderGlobal* shader) {
			if(shader->arraySize == 1) {
				void* ptr = shader->ptr;
				switch(shader->type) {
					case render::Shader::VT_int:
						bindGlobal(format("int $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_int2:
						bindGlobal(format("::vec2i $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_int3:
						bindGlobal(format("::vec3i $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_int4:
						bindGlobal(format("::vec4i $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_float:
						bindGlobal(format("float $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_float2:
						bindGlobal(format("::vec2f $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_float3:
						bindGlobal(format("::vec3f $1", name).c_str(), ptr);
					break;
					case render::Shader::VT_float4:
						bindGlobal(format("::vec4f $1", name).c_str(), ptr);
					break;
				}
			}
			else {
				int fid = -1;
				auto* engine = getEngine();

				switch(shader->type) {
					case render::Shader::VT_int:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const int &in)", name).c_str(),
							asFUNCTION(setShaderValue<int>), asCALL_GENERIC);
					break;
					case render::Shader::VT_int2:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec2i &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec2i>), asCALL_GENERIC);
					break;
					case render::Shader::VT_int3:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec3i &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec3i>), asCALL_GENERIC);
					break;
					case render::Shader::VT_int4:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec4i &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec4i>), asCALL_GENERIC);
					break;
					case render::Shader::VT_float:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const float &in)", name).c_str(),
							asFUNCTION(setShaderValue<float>), asCALL_GENERIC);
					break;
					case render::Shader::VT_float2:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec2f &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec2f>), asCALL_GENERIC);
					break;
					case render::Shader::VT_float3:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec3f &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec3f>), asCALL_GENERIC);
					break;
					case render::Shader::VT_float4:
						fid = engine->RegisterGlobalFunction(format("void set_$1(uint,const ::vec4f &in)", name).c_str(),
							asFUNCTION(setShaderValue<vec4f>), asCALL_GENERIC);
					break;
				}

				if(auto* func = engine->GetFunctionById(fid))
					func->SetUserData(shader);
			}
		});
	}

	//Sprite draw shortcuts
	sprt.addExternMethod("void draw(const recti &in pos) const", asFUNCTION(draw_sprt));
	sprt.addExternMethod("void draw(const recti &in pos, const Color&in color) const", asFUNCTION(draw_sprt_c));
	sprt.addExternMethod("void draw(const recti &in pos, const Color&in color, const Shader@ shader) const", asFUNCTION(draw_sprt_csh));
	sprt.addExternMethod("void draw(const recti &in pos, const Color&in color, double rotation) const", asFUNCTION(draw_sprt_cr));

	//Material definitions
	mat.addExternMethod("vec2i get_size() const", asFUNCTION(mat_size));
	mat.addExternMethod("void switchTo() const", asFUNCTION(mat_activate));

	mat.addExternMethod("bool isPixelActive(const vec2i&in px) const", asFUNCTION(mat_pxactive));
	mat.addExternMethod("void draw(const recti &in pos) const", asFUNCTION(draw_mat));
	mat.addExternMethod("void draw(const recti &in pos, const Color&in color) const", asFUNCTION(draw_mat_c));
	mat.addExternMethod("void draw(const recti &in pos, const Color&in color, const Shader@ shader) const", asFUNCTION(draw_mat_csh));
	mat.addExternMethod("void draw(const recti &in pos, const recti &in src) const", asFUNCTION(draw_mat_s));
	mat.addExternMethod("void draw(const recti &in pos, const recti &in src, const Color&in color) const", asFUNCTION(draw_mat_sc));
	mat.addExternMethod("void draw(const recti &in pos, const recti &in src, const Color&in color, double rotation) const", asFUNCTION(draw_mat_scr));
	mat.addExternMethod("void draw(const recti &in pos, const recti &in src, const Color&in topleft, const Color&in topright, const Color&in botright, const Color&in botleft) const", asFUNCTION(draw_mat_scc));

	//Spritesheet definitions
	sheet.addMember("const Material material", offsetof(render::SpriteSheet, material));
	sheet.addMember("int width", offsetof(render::SpriteSheet, width));
	sheet.addMember("int height", offsetof(render::SpriteSheet, height));
	sheet.addMethod("uint get_count() const", asMETHOD(render::SpriteSheet, getCount));
	sheet.addExternMethod("void getSourceUV(uint index, vec4f&out value) const", asFUNCTION(sprite_sourceUV));
	sheet.addExternMethod("vec2i get_size() const", asFUNCTION(sprite_size));
	sheet.addExternMethod("Sprite opAdd(uint num) const", asFUNCTION(sprite_offset));

	sheet.addMethod("bool isPixelActive(uint index, const vec2i&in px) const", asMETHOD(render::SpriteSheet, isPixelActive));
	sheet.addMethod("recti getSource(uint index) const", asMETHODPR(render::SpriteSheet, getSource, (unsigned) const, recti));
	sheet.addExternMethod("void draw(uint index, const recti &in pos) const", asFUNCTION(draw_sprite));
	sheet.addExternMethod("void draw(uint index, const recti &in pos, const Shader@ shader) const", asFUNCTION(draw_sprite_s));
	sheet.addExternMethod("void draw(uint index, const recti &in pos, const Color&in color) const", asFUNCTION(draw_sprite_c));
	sheet.addExternMethod("void draw(uint index, const recti &in pos, const Color&in color, double rotation) const", asFUNCTION(draw_sprite_cr));
	sheet.addExternMethod("void draw(uint index, const recti &in pos, const Color&in topleft, const Color&in topright, const Color&in botright, const Color&in botleft) const", asFUNCTION(draw_sprite_cc));

	//Model definitions
	mod.addExternMethod("void draw(const Material& mat, const recti&in pos, quaterniond rotation = quaterniond(), double scale = 1.0) const", asFUNCTION(draw_model));
	mod.addMethod("void draw() const", asMETHOD(render::RenderMesh,render));
	mod.addExternMethod("void draw(double lodDist) const", asFUNCTION(meshRenderLOD));

	//Global functions
	bind("void setSkybox(const Material@)", asFUNCTION(setSkybox));
	bind("void setSkyboxMesh(const Model@)", asFUNCTION(setSkyboxMesh));
	bindGlobal("const Shader@ fullscreenShader", &fsShader);
	bind("void applyTransform(const vec3d &in pos, const vec3d &in scale, const quaterniond &in rot)", asFUNCTION(applyTransform))
		doc("Applies a transformation to the modelview matrix. Also applies the camera's position as an offset. Call undoTransform() afterwards.", "", "", "");
	bind("void applyAbsTransform(const vec3d &in pos, const vec3d &in scale, const quaterniond &in rot)", asFUNCTION(applyAbsTransform))
		doc("Applies a transformation to the modelview matrix. Call undoTransform() afterwards.", "", "", "");
	bind("void applyBBTransform(const vec3d &in pos, double width, double rot)", asFUNCTION(applyBBTransform))
		doc("Applies a transformation that rotates a model in the same way a billboard would rotate. Call undoTransform() afterwards.", "", "", "");
	bind("void undoTransform()", asFUNCTION(popTransform))
		doc("Undoes a modelview transform.");
	bind("void getBillboardVecs(vec3d &out upLeft, vec3d &out upRight, double rot = 0)", asFUNCTION(getBBVecs))
		doc("Fetches the two cached vectors necessary to build a billboard.", "Top left corner offset.", "Top right corner offset.", "Optional rotation to apply to the billboard.");
	bind("void getBillboardVecs(const vec3d &in from, vec3d &out upLeft, vec3d &out upRight, double rot = 0)", asFUNCTION(getBBVecsFacing))
		doc("Fetches the two cached vectors necessary to build a billboard that faces the camera.", "Position to face the billboard from.", "Top left corner offset.", "Top right corner offset.", "Optional rotation to apply to the billboard.");
	bind("const ParticleSystem@ getParticleSystem(const string& name)", asFUNCTION(getParticleSystem));
	if(!server) {
		ClassBind psn("ParticleSystemNode", asOBJ_REF);
		bindNode<scene::ParticleSystem>(psn);
		psn.addMember("vec3d velocity", offsetof(scene::ParticleSystem,vel));
		psn.addMember("quaterniond emitRot", offsetof(scene::ParticleSystem,rot));
		psn.addMethod("void stop()", asMETHOD(scene::ParticleSystem,end));
		
		ClassBind node("Node");

		node.addExternMethod("ParticleSystemNode@ opCast() const", asFUNCTION((grabbedCast<scene::Node,scene::ParticleSystem>)));
		psn.addExternMethod("Node@ opImplCast() const", asFUNCTION((grabbedCast<scene::ParticleSystem,scene::Node>)));

		bind("ParticleSystemNode@ playParticleSystem(const string& name, const vec3d& position, float scale = 1, Node@ parent = null)", asFUNCTION(playParticleSys));
		bind("ParticleSystemNode@ playParticleSystem(const ParticleSystem& system, const vec3d& position, float scale = 1, Node@ parent = null)", asFUNCTION(playParticleSys_ps));
	}

	//Camera
	ClassBind cam("Camera", asOBJ_REF);
	cam.addFactory("Camera@ f()", asFUNCTION(cameraFactory));
	cam.setReferenceFuncs(asMETHOD(render::Camera, grab), asMETHOD(render::Camera, drop));
	cam.addMethod("void animate(double time)", asMETHOD(render::Camera, animate));
	cam.addExternMethod("Camera& opAssign(const Camera&in other)", asFUNCTION(copyCamera));

	cam.addMethod("void yaw(double rad, bool snap = false)", asMETHOD(render::Camera, yaw));
	cam.addMethod("void pitch(double rad, bool snap = false)", asMETHOD(render::Camera, pitch));
	cam.addMethod("void roll(double rad, bool snap = false)", asMETHOD(render::Camera, roll));
	cam.addMethod("void zoom(double)", asMETHOD(render::Camera, zoom));
	cam.addMethod("void zoomTo(double, const vec3d &in, double minDistance = 0.0)", asMETHOD(render::Camera, zoomTo));
	cam.addMethod("void zoomAlong(double, const vec3d &in)", asMETHOD(render::Camera, zoomAlong));
	cam.addMethod("void resetRotation()", asMETHOD(render::Camera, resetRotation));
	cam.addMethod("void resetZoom()", asMETHOD(render::Camera, resetZoom));
	cam.addMethod("void snap()", asMETHOD(render::Camera, snap));
	cam.addMethod("void snapTranslation()", asMETHOD(render::Camera, snapTranslation));

	cam.addMethod("double get_radius()", asMETHOD(render::Camera, getRadius));
	cam.addMethod("void set_radius(double value)", asMETHOD(render::Camera, setRadius));
	
	cam.addMethod("void set_linearZoom(bool) const", asMETHOD(render::Camera, setLinearZoom));
	cam.addMethod("void set_lockedRotation(bool) const", asMETHOD(render::Camera, setLockedRotation))
		doc("Sets whether the camera is allowed to rotate to be upside down.", "");

	cam.addMethod("void setPositionBound(const vec3d &in minimum, const vec3d &in maximum)", asMETHOD(render::Camera, setPositionBound));
	cam.addMethod("void set_maxDistance(double dist)", asMETHOD(render::Camera, setMaxDistance));

	cam.addMethod("void abs_yaw(double rad, bool snap = false)", asMETHOD(render::Camera, abs_yaw));
	cam.addMethod("void abs_pitch(double rad, bool snap = false)", asMETHOD(render::Camera, abs_pitch));

	cam.addMethod("void abs_yaw_to(double rad, bool snap = false)", asMETHOD(render::Camera, abs_yaw_to));
	cam.addMethod("void abs_pitch_to(double rad, bool snap = false)", asMETHOD(render::Camera, abs_pitch_to));
	
	cam.addMethod("void move_abs(const vec3d &in)", asMETHOD(render::Camera, move_abs));
	cam.addMethod("void move_world_abs(const vec3d &in)", asMETHOD(render::Camera, move_world_abs));
	cam.addMethod("void move_world(const vec3d &in)", asMETHOD(render::Camera, move_world));
	cam.addMethod("void move_cam(const vec3d &in)", asMETHOD(render::Camera, move_cam));
	cam.addMethod("void move_cam_abs(const vec3d &in)", asMETHOD(render::Camera, move_cam_abs));

	cam.addMethod("vec3d get_position() const", asMETHOD(render::Camera, getPosition));
	cam.addMethod("vec3d get_finalPosition() const", asMETHOD(render::Camera, getFinalPosition));
	cam.addMethod("vec3d get_facing() const", asMETHOD(render::Camera, getFacing));
	cam.addMethod("vec3d get_right() const", asMETHOD(render::Camera, getRight));
	cam.addMethod("vec3d get_lookAt() const", asMETHOD(render::Camera, getLookAt));
	cam.addMethod("vec3d get_finalLookAt() const", asMETHOD(render::Camera, getFinalLookAt));
	cam.addMethod("vec3d get_up() const", asMETHOD(render::Camera, getUp));
	cam.addMethod("double get_distance() const", asMETHOD(render::Camera, getDistance));
	cam.addMethod("bool get_inverted()", asMETHOD(render::Camera, inverted));

	cam.addMethod("double get_yaw() const", asMETHOD(render::Camera, getYaw));
	cam.addMethod("double get_pitch() const", asMETHOD(render::Camera, getPitch));
	cam.addMethod("double get_roll() const", asMETHOD(render::Camera, getRoll));

	cam.addMethod("double screenAngle(const vec3d&in pos) const", asMETHOD(render::Camera, screenAngle));
	cam.addMethod("vec2i screenPos(const vec3d&in pos) const", asMETHOD(render::Camera, screenPos));
	cam.addMethod("line3dd screenToRay(double, double) const", asMETHOD(render::Camera, screenToRay));

	cam.addMethod("void toLookAt(vec3d &out, vec3d &out, vec3d &out) const", asMETHOD(render::Camera, toLookAt));
	cam.addMethod("void setRenderConstraints(double, double, double, double, double, double)", asMETHOD(render::Camera, setRenderConstraints));

	if(!isMenu) {
		cam.addExternMethod("Object@ getObject(const vec2i& line) const", asFUNCTION(objectFromPixel));
		cam.addExternMethod("array<Object@>@ boxSelect(const recti& box)", asFUNCTION(boxSelect));
	}

	bind("double getCameraDistance(const vec3d&in pos, double scale = 0)", asFUNCTION(cam_dist));
	bind("vec3d get_cameraPos()", asFUNCTION(cam_pos));
	bind("vec3d get_cameraUp()", asFUNCTION(cam_up));
	bind("vec3d get_cameraFacing()", asFUNCTION(cam_facing));
	bind("bool isSphereVisible(const vec3d& center, double radius)", asFUNCTION(isInView));

	bindGlobal("double pixelSizeRatio", &pixelSizeRatio);
	bindGlobal("bool render3DIcons", &scene::MeshIconNode::render3DIcons);

	ClassBind rt("RenderTarget", asOBJ_REF);
	rt.addFactory("RenderTarget@ f(const vec2i &in size)", asFUNCTION(makeRenderTarget));
	rt.setReferenceFuncs(asMETHOD(ScriptRenderTarget, grab), asMETHOD(ScriptRenderTarget, drop));
	rt.addMethod("bool get_valid() const", asMETHOD(ScriptRenderTarget, isValid));
	rt.addMethod("void set() const", asMETHOD(ScriptRenderTarget, set));
	rt.addMethod("void reset() const", asMETHOD(ScriptRenderTarget, reset));
	rt.addMethod("void animate(double time)", asMETHOD(ScriptRenderTarget, animate));
	rt.addMethod("void draw(const recti& in)", asMETHOD(ScriptRenderTarget, draw));
	rt.addMethod("void set_size(const vec2i& in)", asMETHOD(ScriptRenderTarget, resize));
	rt.addMember("Node@ node", offsetof(ScriptRenderTarget, node));
	rt.addMember("Camera@ camera", offsetof(ScriptRenderTarget, camera));

	//-- Dynamic texture loading
	ClassBind dtex("DynamicTexture", asOBJ_REF);
	dtex.addFactory("DynamicTexture@ f()", asFUNCTION(makeDynamicTexture));
	dtex.setReferenceFuncs(asMETHOD(DynamicTexture, grab), asMETHOD(DynamicTexture, drop));

	dtex.addMember("Material@ material", offsetof(DynamicTexture, state));
	dtex.addMethod("bool isLoaded(uint index = 0)", asMETHOD(DynamicTexture, isLoaded));
	dtex.addMethod("vec2i get_size(uint index = 0)", asMETHOD(DynamicTexture, getSize));
	dtex.addMethod("void load(const string&in filename, uint index = 0)", asMETHOD(DynamicTexture, load));
	dtex.addMethod("void set_image(uint index, const Image@+ img)", asMETHOD(DynamicTexture, set));
	dtex.addMethod("void draw(const recti&in pos, const Color& color)", asMETHOD(DynamicTexture, draw));
	dtex.addMethod("bool stream()", asMETHOD(DynamicTexture, stream));

	//-- Render functions
	bind("void drawRectangle(const recti &in pos, const Color&in color)", asFUNCTION(draw_rect));
	bind("void drawRectangle(const recti &in pos, const Material@ mat, const Color&in color)", asFUNCTION(draw_rect_m));
	bind("void drawRectangle(const recti &in pos, const Color&in topleft, const Color&in topright, const Color&in botright, const Color&in botleft)", asFUNCTION(draw_rect_g));
	
	//TODO: Figure out why the JIT doesn't supoprt asCALL_THISCALL_ASGLOBAL
	//bind("void updateRenderCamera(Camera& cam)", asMETHOD(render::RenderDriver,setCameraData), devices.render);
	//bind("void prepareRender(Camera& cam)", asMETHOD(render::RenderDriver,prepareRender3D), devices.render);
	bind("void updateRenderCamera(Camera& cam)", asFUNCTION(updateCamera));
	bind("void prepareRender(Camera& cam)", asFUNCTION(prepareRender));
	bind("void prepareRender(Camera& cam, const recti&)", asFUNCTION(prepareRenderClip));
	bind("void renderWorld()", asFUNCTION(renderWorld));
	bind("void renderBillboard(const Material& mat, const vec3d &in pos, double width, double rotation = 0)", asFUNCTION(renderBillboard));
	bind("void renderBillboard(const SpriteSheet& sheet, uint index, const vec3d &in pos, double width, double rotation = 0)", asFUNCTION(renderBillboard_sheet));
	bind("void renderBillboard(const Sprite& spr, const vec3d &in pos, double width, double rotation = 0)", asFUNCTION(renderBillboard_sprite));
	bind("void renderBillboard(const Material& mat, const vec3d &in pos, double width, double rotation, const Color&in)", asFUNCTION(renderBillboard_c));
	bind("void renderBillboard(const SpriteSheet& sheet, uint index, const vec3d &in pos, double width, double rotation, const Color&in)", asFUNCTION(renderBillboard_sheet_c));
	bind("void renderBillboard(const Sprite& spr, const vec3d &in pos, double width, double rotation, const Color&in)", asFUNCTION(renderBillboard_sprite_c));
	bind("void renderPlane(const Material& mat, const vec3d &in pos, double width, const Color&in, double rotation = 0)", asFUNCTION(renderPlane));
	bind("void drawFPSGraph(const recti &in pos)", asFUNCTION(draw_fps));

	EnumBind pt("PolygonType");
	pt["PT_Lines"] = render::PT_Lines;
	pt["PT_LineStrip"] = render::PT_LineStrip;
	pt["PT_Triangles"] = render::PT_Triangles;
	pt["PT_Quads"] = render::PT_Quads;
	
	bind("void drawPolygonStart(uint triangles, const Material@ mat = null)", asFUNCTION(poly_start));
	bind("void drawPolygonStart(uint triangles, const Material@ mat, const Color&in)", asFUNCTION(poly_start_c));
	bind("void drawPolygonStart(PolygonType type, uint polyCount, const Material@ mat = null)", asFUNCTION(poly_start_t));
	bind("void drawPolygonEnd()", asFUNCTION(poly_end));

	bind("void drawPolygonPoint(const vec2i &in)", asFUNCTION(poly_coord));
	bind("void drawPolygonPoint(const vec2i &in, const vec2f& in)", asFUNCTION(poly_coord_uv));
	bind("void drawPolygonPoint(const vec2i &in, const vec2f& in, const Color& in)", asFUNCTION(poly_coord_uvc));
	bind("void drawPolygonPoint(const vec2i &in, const Color&in)", asFUNCTION(poly_coord_c));

	bind("void drawPolygonPoint(const vec2f &in)", asFUNCTION(poly_fcoord));
	bind("void drawPolygonPoint(const vec2f &in, const vec2f& in)", asFUNCTION(poly_fcoord_uv));
	bind("void drawPolygonPoint(const vec2f &in, const Color&in)", asFUNCTION(poly_fcoord_c));

	bind("void drawPolygonPoint(const vec3d &in)", asFUNCTION(poly3_coord));
	bind("void drawPolygonPoint(const vec3d &in, const vec2f& in)", asFUNCTION(poly3_coord_uv));
	bind("void drawPolygonPoint(const vec3d &in, const Color&in)", asFUNCTION(poly3_coord_c));
	bind("void drawPolygonPoint(const vec3d &in, const vec2f& in, const Color&in)", asFUNCTION(poly3_coord_uvc));

	bind("void drawLine(const vec2i&in from, const vec2i& to, int size = 1, const Material@ mat = null)", asFUNCTION(draw_line));
	bind("void drawLine(const vec2i&in from, const vec2i& to, const Color&in color, int size = 1, const Material@ mat = null)", asFUNCTION(draw_line_c));

	//-- Video modes
	ClassBind vm("VideoMode", asOBJ_POD | asOBJ_VALUE, sizeof(os::OSDriver::VideoMode));
	vm.addMember("uint width", offsetof(os::OSDriver::VideoMode, width));
	vm.addMember("uint height", offsetof(os::OSDriver::VideoMode, height));
	vm.addMember("uint refresh", offsetof(os::OSDriver::VideoMode, refresh));
	bind("void getVideoModes(array<VideoMode>& output)", asFUNCTION(getVideoModes));
	bind("void getMonitorNames(array<string>& output)", asFUNCTION(getMonitorNames));

	bind("void set_vsync(int blanks)", asFUNCTION(setVsync))
		doc("Sets vsync mode (applied immediately if possible)", "Number of frames to wait for. -1 for adaptive vsync where available.");
	bindGlobal("double scale_3d", &scale_3d)
		doc("Linear factor by which to scale the 3D render for supersampling.");

	//-- Sound
	bind("void getAudioDeviceNames(array<string>& output)", asFUNCTION(getAudioNames));
}

};
