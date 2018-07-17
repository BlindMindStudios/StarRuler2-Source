#include "binds.h"
#include "util/hex_grid.h"
#include "main/logging.h"
#include "main/references.h"
#include "str_util.h"
#include "color.h"
#include "vec2.h"
#include "vec3.h"
#include "vec4.h"
#include "line3d.h"
#include "rect.h"
#include "quaternion.h"
#include "plane.h"
#include "general_states.h"
#include "util/random.h"
#include "scripts/manager.h"
#include "util/locked_type.h"
#include "util/lockless_type.h"
#include "util/elevation_map.h"
#include "util/name_generator.h"
#include "util/bbcode.h"
#include "util/link_container.h"
#include "physics/physics_world.h"
#include "main/game_platform.h"
#include <string>
#include <sstream>
#include <queue>
#include <unordered_set>
#include <cmath>

#ifdef _MSC_VER
template<class T>
void unordered_set_reserve(std::unordered_set<T>& set, size_t count) {
	set.rehash((std::unordered_set<T>::size_type)std::ceil(count / set.max_load_factor()));
}
#endif

namespace scripts {

Color white((unsigned)0xffffffff);
Color red((unsigned)0xff0000ff);
Color orange((unsigned)0xff8000ff);
Color green((unsigned)0x00ff00ff);
Color blue((unsigned)0x0000ffff);
Color black((unsigned)0x000000ff);
Color invisible((unsigned)0x00000000);
void color8(Color& col, unsigned char r, unsigned char g, unsigned char b, unsigned char a) {
	col.r = r;
	col.g = g;
	col.b = b;
	col.a = a;
}

void color32(Color& col, unsigned int color) {
	col.set(color);
}

void color_cf(Color& col, Colorf& fcol) {
	col = fcol;
}

void colorw(Color& col) {
	col.set(0xffffffff);
}

unsigned color_get_rgba(const Color& col) {
	return (col.r << 24) | (col.g << 16) | (col.b << 8) | col.a;
}

vec4f color_get_vec4(const Color& col) {
	vec4f v;
	v.x = float(col.r) / 255.f;
	v.y = float(col.g) / 255.f;
	v.z = float(col.b) / 255.f;
	v.w = float(col.a) / 255.f;
	return v;
}

void color_to_vec4(const Color& col, vec4f& v) {
	v.x = float(col.r) / 255.f;
	v.y = float(col.g) / 255.f;
	v.z = float(col.b) / 255.f;
	v.w = float(col.a) / 255.f;
}

void colorfw(Colorf* col) {
	new(col) Colorf();
}

void colorf3(Colorf* col, float r, float g, float b) {
	new(col) Colorf(r, g, b);
}

void colorf4(Colorf* col, float r, float g, float b, float a) {
	new(col) Colorf(r, g, b, a);
}

void colorfc(Colorf* col, const Color& other) {
	new(col) Colorf(other);
}

float interp(float from, float to, float percent) {
	if(percent <= 0)
		return from;
	else if(percent >= 1.f)
		return to;
	else
		return from + (to - from)*percent;
}

float percentBetween(float value, float from, float to) {
	return (value - from) / (to - from);
}

//Returns a Colorf with a color similar to that of a black body with temperature <tempK> in Kelvins.
//The color will then be multiplied by <magnitude>
//
//For reference, our sun has a temperature of 5778 K
Colorf blackBodyColor(float tempK, float magnitude) {
	if(tempK > 29800.f) tempK = 29800.f;
	//Colors approximated from: http://www.vendian.org/mncharity/dir3/blackbody/
	
	float r = interp(1.f, 0.6234f, percentBetween(tempK, 6400.f, 29800.f));

	float g;
	if(tempK < 6600.f)
		g = interp(0.22f, 0.976f, percentBetween(tempK, 1000.f, 6600.f));
	else
		g = interp(.976f, 0.75f, percentBetween(tempK, 6600.f, 29800.f));

	float b = interp(0, 1.f, percentBetween(tempK, 2800.f, 7600.f));

	return Colorf(r * magnitude, g * magnitude, b * magnitude);
}

template<class T, class Q>
void v2d_copy(vec2<T>* dest, vec2<Q>& src) {
	new(dest) vec2<T>(src);
}

template<class T, class Q>
void v3d_copy(vec3<T>* dest, vec3<Q>& src) {
	new(dest) vec3<T>(src);
}

template<class T, class Q>
void v4d_copy(vec4<T>* dest, vec4<Q>& src) {
	new(dest) vec4<T>(src);
}

template<class T>
void vector2d_e(vec2<T>& vec) {
	vec.x = 0;
	vec.y = 0;
}

template<class T>
void vector2d_s(vec2<T>& vec, T def) {
	vec.x = def;
	vec.y = def;
}

template<class T>
void vector2d(vec2<T>& vec, T x, T y) {
	vec.x = x;
	vec.y = y;
}

template<class T>
void vector3d(vec3<T>& vec, T x, T y, T z) {
	vec.x = x;
	vec.y = y;
	vec.z = z;
}

template<class T>
void vector4d(vec4<T>& vec, T x, T y, T z, T w) {
	vec.x = x;
	vec.y = y;
	vec.z = z;
	vec.w = w;
}

template<class T>
void vector3d_e(vec3<T>& vec) {
	vec.x = 0;
	vec.y = 0;
	vec.z = 0;
}

template<class T>
void vector3d_s(vec3<T>& vec, T s) {
	vec.x = s;
	vec.y = s;
	vec.z = s;
}

template<class T>
void vector4d_e(vec4<T>& vec) {
	vec.x = 0;
	vec.y = 0;
	vec.z = 0;
	vec.w = 0;
}

template<class T>
void quat_e(void* mem) {
	new(mem) quaternion<T>();
}

template<class T>
void quat(void* mem, T x, T y, T z, T w) {
	new(mem) quaternion<T>(x, y, z, w);
}

template<class T>
void quat_v(void* mem, vec3<T> v, T w) {
	new(mem) quaternion<T>(v, w);
}

template<class T>
void quat_copy(void* mem, quaternion<T> v) {
	new(mem) quaternion<T>(v);
}

template<class T>
void plane_def(void* mem) {
	new(mem) plane<T>();
}

template<class T>
void plane_dd(void* mem, const vec3<T>& dir, T dist) {
	new(mem) plane<T>(dir, dist);
}

template<class T>
void plane_pd(void* mem, const vec3<T>& point, const vec3<T>& dir) {
	new(mem) plane<T>(point, dir);
}

template<class T>
void plane_tri(void* mem, const vec3<T>& a, const vec3<T>& b, const vec3<T>& c) {
	new(mem) plane<T>(a, b, c);
}

template<class T>
void hexgrid(void* mem) {
	new(mem) HexGrid<T>(1, 1);
}

template<class T>
void hexgrid_v(void* mem, unsigned w, unsigned h) {
	new(mem) HexGrid<T>(w, h);
}

template<class T>
void hexgrid_c(void* mem, const HexGrid<T>& other) {
	new(mem) HexGrid<T>(other);
}

template<class T>
void delhex(HexGrid<T>* grid) {
	grid->~HexGrid<T>();
}

template<class T>
T& hexgrid_get(HexGrid<T>* grid, unsigned x, unsigned y) {
	if(x >= grid->width) {
		scripts::throwException("Hex x coordinate out of bounds.");
		return *(T*)0; // <-- Totally legit code.
	}
	if(y >= grid->height) {
		scripts::throwException("Hex y coordinate out of bounds.");
		return *(T*)0;
	}

	return grid->get(x, y);
}

template<class T>
T& hexgrid_get_v(HexGrid<T>* grid, const vec2u& pos) {
	return hexgrid_get<T>(grid, pos.x, pos.y);
}

template<class T>
T& hexgrid_get_va(HexGrid<T>* grid, const vec2u& pos, HexGridAdjacency adj) {
	vec2u p = pos;
	grid->advance(p, adj);
	return hexgrid_get<T>(grid, p.x, p.y);
}

template<class T>
T& vec_normalize(T& obj) {
	return obj.normalize();
}

template<class T>
T vec_normalized(T& obj) {
	return obj.normalized();
}

template<class From, class To>
void rect_convert(rect<To>& to, const rect<From>& from) {
	to.topLeft.x = (To)from.topLeft.x;
	to.topLeft.y = (To)from.topLeft.y;
	to.botRight.x = (To)from.botRight.x;
	to.botRight.y = (To)from.botRight.y;
}

template<class T>
void rect_c(rect<T>& r, T x1, T y1, T x2, T y2) {
	r.topLeft.x = x1;
	r.topLeft.y = y1;
	r.botRight.x = x2;
	r.botRight.y = y2;
}

template<class T>
void rect_v(rect<T>& r, const vec2<T>& a, const vec2<T>& b) {
	r.topLeft = a;
	r.botRight = b;
}

template<class T>
void rect_e(rect<T>& r) {
	r.topLeft.x = 0;
	r.topLeft.y = 0;
	r.botRight.x = 0;
	r.botRight.y = 0;
}

template<class T>
rect<T> rect_ac(T x1, T y1, T x2, T y2) {
	rect<T> r;
	r.topLeft.x = x1;
	r.topLeft.y = y1;
	r.botRight.x = x1+x2;
	r.botRight.y = y1+y2;
	return r;
}

template<class T>
rect<T> rect_av(const vec2<T>& a, const vec2<T>& b) {
	rect<T> r;
	r.topLeft = a;
	r.botRight = vec2<T>(a.x + b.x, a.y + b.y);
	return r;
}

template<class T>
rect<T> rect_centered(const rect<T>& a, const vec2<T>& b) {
	return rect<T>::centered(a, b);
}

template<class T>
rect<T> rect_centeredv(const vec2<T>& a, const vec2<T>& b) {
	return rect<T>::centered(a, b);
}

template<class T>
void line3(line3d<T>& l, const vec3<T>& a, const vec3<T>& b) {
	l.start = a;
	l.end = b;
}

template<class T>
void line3_e(line3d<T>& l) {
	l.start.x = 0;
	l.start.y = 0;
	l.end.x = 0;
	l.end.y = 0;
}

template<class T>
std::string vec3_toString(const vec3<T>& v, unsigned decimals = 2) {
	std::string result = "(";
	result += toString(v.x, decimals);
	result += ", ";
	result += toString(v.y, decimals);
	result += ", ";
	result += toString(v.z, decimals);
	result += ")";

	return result;
}

template<class T>
std::string vec3_addString(const vec3<T>& v, const std::string& str) {
	return str + vec3_toString(v);
}

template<class T>
void vec3_print(const vec3<T>& v) {
	print(vec3_toString(v));
}

template<class T>
std::string vec2_toString(const vec2<T>& v, std::string& str) {
	std::string result = str;
	result += "(";
	result += toString(v.x, 3);
	result += ", ";
	result += toString(v.y, 3);
	result += ")";

	return result;
}

template<class T>
void vec2_print(const vec2<T>& v) {
	std::string out;
	vec2_toString(v, out);
	print(out);
}

template<class T>
std::string vec4_toString(const vec4<T>& v, const std::string& str) {
	std::string result = str;
	result += "(";
	result += toString(v.x, 2);
	result += ", ";
	result += toString(v.y, 2);
	result += ", ";
	result += toString(v.z, 2);
	result += ", ";
	result += toString(v.w, 2);
	result += ")";

	return result;
}

template<class T>
void vec4_print(const vec4<T>& v) {
	print(vec4_toString(v, ""));
}

template<class T>
std::string rect_toString(const rect<T>& r, std::string& str) {
	std::string result = str;
	result += "[rect | topLeft: ";
	result = vec2_toString(r.topLeft, result);
	result += " | botRight: ";
	result = vec2_toString(r.botRight, result);
	result += "]";

	return result;
}

template<class T>
void rect_print(const rect<T>& v) {
	std::string out;
	rect_toString(v, out);
	print(out);
}

template<class T>
void stringFromType(void* memory, T value) {
	std::stringstream stream;
	stream << value;
	new(memory) std::string(stream.str());
}

static void createStateList(void* memory, const StateDefinition& def) {
	new(memory) StateList(def);
}

static void destroyStateList(StateList* memory) {
	memory->~StateList();
}

static void createDummyStateList(void* memory) {
	new(memory) StateList(errorStateDefinition);
}

struct ScriptImage : AtomicRefCounted {
	Image* img;

	ScriptImage(Image* image) : img(image) {
	}

	ScriptImage(const render::Sprite& sprt) {
		if(sprt.mat && sprt.mat->textures[0])
			fromTex(sprt.mat->textures[0], recti(vec2i(), sprt.mat->textures[0]->size));
		else if(sprt.sheet && sprt.sheet->material.textures[0]) {
			vec2i size = sprt.sheet->material.textures[0]->size;
			recti source = sprt.sheet->getSource(sprt.index);
			recti pos = source;
			source.topLeft.y = size.y - pos.botRight.y;
			source.botRight.y = size.y - pos.topLeft.y;
			fromTex(sprt.sheet->material.textures[0], source);
		}
		else
			img = new Image();
	}

	ScriptImage(const render::Texture* tex, const recti& source) {
		fromTex(tex, source);
	}

	ScriptImage(const ScriptImage& other, const recti& source) {
		img = new Image(source.getWidth(), source.getHeight(), FMT_RGBA, 0);
		fromImage(*other.img, source, false);
	}

	ScriptImage& operator=(const ScriptImage& other) {
		if(!other.img)
			return *this;
		if(!img)
			img = new Image();
		if(img->width != other.img->width || img->height != other.img->height)
			img->resize(other.img->width, other.img->height);
		*img = *other.img;
		return *this;
	}

	void fromTex(const render::Texture* tex, const recti& source) {
		Image orig;
		if(!tex->loaded) {
			scripts::throwException("Texture not yet loaded.");
			return;
		}

		tex->save(orig);

		img = new Image(source.getWidth(), source.getHeight(), FMT_RGBA, 0);
		fromImage(orig, source, false);
	}

	void fromImage(const Image& other, const recti& source, bool flip) {
		vec2i size(other.width, other.height);
		int x1 = std::max(0, std::min(size.x, source.topLeft.x));
		int x2 = std::max(0, std::min(size.x, source.botRight.x));
		int y1 = std::max(0, std::min(size.y, source.topLeft.y));
		int y2 = std::max(0, std::min(size.y, source.botRight.y));
		img->resize(source.getWidth(), source.getHeight());

		if(flip) {
			for(int sx = x1, dx = 0; sx < x2; ++dx, ++sx) {
				for(int sy = y2-1, dy = 0; sy >= y1; ++dy, --sy) {
					Color col = other.get_rgba(sx, sy);
					(*img).get_rgba(dx, dy) = col;
				}
			}
		}
		else {
			for(int sx = x1, dx = 0; sx < x2; ++dx, ++sx) {
				for(int sy = y1, dy = 0; sy < y2; ++dy, ++sy) {
					Color col = other.get_rgba(sx, sy);
					(*img).get_rgba(dx, dy) = col;
				}
			}
		}
	}

	~ScriptImage() {
		delete img;
	}

	Color getTexel(float x, float y) {
		return img->getTexel(x, y);
	}

	Color getTexel(const vec2f& pos) {
		return img->getTexel(pos);
	}

	Color get(unsigned x, unsigned y) {
		if(x < img->width && y < img->height)
			return img->get(x,y);
		else
			return Color();
	}

	Color get(const vec2u& pos) {
		return get(pos.x, pos.y);
	}

	void set(unsigned x, unsigned y, Color col) {
		if(x < img->width && y < img->height) {
			switch(img->format) {
			case FMT_Alpha:
				img->get_alpha(x,y) = col.a; break;
			case FMT_Grey:
				img->get_grey(x,y) = std::max(std::max(col.r,col.b),col.g); break;
			case FMT_RGB:
				img->get_rgb(x,y) = ColorRGB(col.r,col.g,col.b); break;
			case FMT_RGBA:
				img->get_rgba(x,y) = col; break;
			}
		}
	}

	void set(const vec2u& pos, Color col) {
		return set(pos.x, pos.y, col);
	}

	vec2u get_size() {
		return vec2u(img->width, img->height);
	}

	void save(const std::string& filename) {
		if(!isAccessible(filename)) {
			scripts::throwException("Cannot access file outside game or profile directories.");
			return;
		}

		try {
			if(!saveImage(img, filename.c_str()))
				throw 0;
		}
		catch(...) {
			error("Could not write image...");
		}
	}
};

Image* getInternalImage(ScriptImage* img) {
	return img->img;
}

ScriptImage* makeScriptImage(Image* img) {
	return new ScriptImage(img);
}

static void makeLockedInt(void* mem) {
	new(mem) LocklessInt();
}

static void makeLockedInt_v(void* mem, int value) {
	new(mem) LocklessInt(value);
}

static void makeLockedDouble(void* mem) {
	new(mem) LocklessDouble();
}

static void makeLockedDouble_v(void* mem, double value) {
	new(mem) LocklessDouble(value);
}

ScriptImage* makeImage(const std::string& file) {
	Image* img = loadImage(devices.mods.resolve(file).c_str());
	if(img)
		return new ScriptImage(img);
	else
		return 0;
}

ScriptImage* makeImage_sprt(const render::Sprite& sprt) {
	return new ScriptImage(sprt);
}

ScriptImage* makeImage_tex(const render::Texture* tex, const recti& source) {
	return new ScriptImage(tex, source);
}

ScriptImage* makeImage_img(const ScriptImage& other, const recti& source) {
	return new ScriptImage(other, source);
}

ScriptImage* makeImage_size(const vec2u& size, unsigned channels) {
	ColorFormat fmt;
	switch(channels) {
	case 1: fmt = FMT_Grey; break;
	case 3: fmt = FMT_RGB; break;
	case 4: fmt = FMT_RGBA; break;
	default:
		return nullptr;
	}

	return new ScriptImage(new Image(size.width, size.height, fmt));
}

typedef std::priority_queue<std::pair<double,int>> p_queue;
static void pq_construct(void *mem) {
	new(mem) p_queue();
}

static void pq_destruct(p_queue& q) {
	q.~p_queue();
}

static int pq_top(p_queue& q) {
	return q.top().second;
}

static double pq_top_prior(p_queue& q) {
	return q.top().first;
}

static void pq_push(p_queue& q, int value, double priority) {
	q.push(std::pair<double,int>(priority, value));
}

typedef int64_t set_int_type;
typedef std::unordered_set<set_int_type> set_int;
static void si_construct(void* mem) {
	new(mem) set_int();
}

static void si_destruct(set_int& s) {
	s.~set_int();
}

static bool si_has(set_int& s, set_int_type value) {
	auto it = s.find(value);
	return it != s.end();
}

static void si_insert(set_int& s, set_int_type value) {
	s.insert(value);
}

static void si_erase(set_int& s, set_int_type value) {
	s.erase(value);
}

static void em_construct(void* mem) {
	new(mem) ElevationMap();
}

static void em_destruct(ElevationMap& em) {
	em.~ElevationMap();
}

static void ng_construct(void* mem) {
	new(mem) NameGenerator();
}

static void ng_destruct(NameGenerator& ng) {
	ng.~NameGenerator();
}

static void ng_read(NameGenerator& ng, const std::string& filename, bool resolve) {
	std::string fname = filename;
	if(resolve)
		fname = devices.mods.resolve(fname);
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return;
	}
	ng.read(fname);
}

static void ng_write(NameGenerator& ng, const std::string& filename, bool resolve) {
	std::string fname = filename;
	if(resolve)
		fname = devices.mods.resolve(fname);
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return;
	}
	ng.write(fname);
}

template<class T>
static void quatTransform(quaternion<T>& q, vec3<T>& val, vec3<T>& result) {
	result = q * val;
}

static PhysicsWorld* makePhysWorld(double size, double fuzz, unsigned count) {
	if(count == 0 || size <= 0.0 || fuzz <= 0.0) {
		scripts::throwException("Must have a valid grid");
		return 0;
	}

	return new PhysicsWorld(size, fuzz, count);
}

static threads::ReadWriteMutex physWorldLock, nodePhysWorldLock;

static void setPhysicsWorld(PhysicsWorld* world) {
	threads::WriteLock lock(physWorldLock);
	if(devices.physics == 0) {
		devices.physics = world;
	}
	else {
		scripts::throwException("May only set the server physics world once.");
		world->drop();
	}
}

static PhysicsWorld* getPhysicsWorld() {
	threads::ReadLock lock(physWorldLock);
	if(devices.physics) {
		devices.physics->grab();
		return devices.physics;
	}
	else {
		return 0;
	}
}

static void setNodePhysicsWorld(PhysicsWorld* world) {
	threads::WriteLock lock(nodePhysWorldLock);
	if(devices.nodePhysics == 0) {
		devices.nodePhysics = world;
	}
	else {
		scripts::throwException("May only set the node physics world once.");
		world->drop();
	}
}

static void bb_construct(void* mem) {
	new(mem) BBCode();
}

static void bb_destruct(BBCode& bb) {
	bb.~BBCode();
}

static BBCode::Tag* bb_root(BBCode& bb) {
	return &bb.root;
}

static bool bb_parse(BBCode& bb, const std::string& text) {
	try {
		bb.parse(text);
		return true;
	}
	catch(const char*) {
		//scripts::throwException(format("Error parsing bbcode: $1", err).c_str());
		return false;
	}
}

static std::string bb_escape(const std::string& text, bool allowWikiLinks) {
	std::string out;
	out.reserve(text.size());

	for(size_t i = 0, cnt = text.size(); i < cnt; ++i) {
		if(text[i] == '[') {
			if(allowWikiLinks && i < cnt-1 && text[i+1] == text[i]) {
				out.append(2, '[');
				++i;
			}
			else {
				out.append(1, '\\');
				out.append(1, '[');
			}
		}
		else if(text[i] == '\\') {
			out.append(1, '\\');
			out.append(1, '\\');
		}
		else {
			out.append(1, text[i]);
		}
	}
	return out;
}

static std::string bb_makeLinks(const std::string& input) {
	//The saddest link finder considers anything that starts with http:// a link.
	std::string out;
	size_t at = 0, found = 0;
	while(at < input.size()) {
		found = input.find("http", at);
		if(found == std::string::npos)
			break;
		if(found >= input.size() - 8)
			break;

		if((input[found+4] != ':' || input[found+5] != '/' || input[found+6] != '/')
				&& (input[found+4] != 's' || input[found+5] != ':' || input[found+6] != '/' || input[found+7] != '/')) {
			at = found+4;
			continue;
		}

		size_t end = input.find_first_of("\r\n\t] ", found);
		if(end == std::string::npos)
			end = input.size();
		while(input[end-1] == ',' || input[end-1] == '.' || input[end-1] == ':' || input[end-1] == ';')
			--end;

		if(found > at)
			out.append(input, at, found-at);

		out.append("[url=");
		out.append(input, found, end-found);
		if(input[end-1] == '/') //Holy hacks batman
			out.append("?");
		out.append("]");
		out.append(input, found, end-found);
		out.append("[/url]");

		at = end;
	}
	if(at < input.size())
		out.append(input, at, input.size() - at);
	return out;
}

static unsigned bbtag_childCount(BBCode::Tag& tag) {
	return (unsigned)tag.contents.size();
}

static BBCode::Tag* bbtag_child(BBCode::Tag& tag, unsigned index) {
	if(index >= tag.contents.size()) {
		scripts::throwException("BBTag child index out of bounds.");
		return 0;
	}
	return &tag.contents[index];
}

static void achieve(const std::string& id) {
	if(devices.cloud)
		devices.cloud->unlockAchievement(id);
}

template<class T>
static void modStat(const std::string& id, T delta) {
	if(devices.cloud)
		devices.cloud->modStat(id, delta);
}

template<class T>
static bool getStat(const std::string& id, T& delta) {
	if(devices.cloud)
		return devices.cloud->getStat(id, delta);
	else
		return false;
}

template<class T>
static bool getGlobalStat(const std::string& id, T& delta) {
	if(devices.cloud)
		return devices.cloud->getGlobalStat(id, delta);
	else
		return false;
}

class ScriptRandom : public AtomicRefCounted {
public:
	RandomEngine* rnd;

	ScriptRandom(unsigned seed) : rnd(RandomEngine::makeMersenne(seed)) {}

	~ScriptRandom() {
		delete rnd;
	}

	double randomd() {
		return rnd->randomd();
	}

	double randomd_r(double min, double max) {
		return rnd->randomd(min, max);
	}

	float randomf() {
		return (float)randomd();
	}

	float randomf_r(float min, float max) {
		return (float)randomd_r(min, max);
	}

	unsigned randomi() {
		return rnd->randomi();
	}

	unsigned randomi_r(unsigned min, unsigned max) {
		return rnd->randomi(min, max);
	}

	static ScriptRandom* make(unsigned seed) {
		return new ScriptRandom(seed);
	}
};

static void lm_construct(void* mem) {
	new(mem) LinkMap();
}

static void lm_construct_i(void* mem, uint64_t defaultValue) {
	new(mem) LinkMap(defaultValue);
}

static void lm_construct_d(void* mem, double defaultValue) {
	new(mem) LinkMap(defaultValue);
}

static void lm_destruct(LinkMap& mem) {
	mem.~LinkMap();
}

void RegisterDataBinds() {
	ClassBind str("string");
	str.addConstructor("void f(int)", asFUNCTION(stringFromType<int>));
	str.addConstructor("void f(uint)", asFUNCTION(stringFromType<unsigned>));
	str.addConstructor("void f(float)", asFUNCTION(stringFromType<float>));
	str.addConstructor("void f(double)", asFUNCTION(stringFromType<double>));

	ClassBind rnd("RandomEngine", asOBJ_REF, 0);
	rnd.setReferenceFuncs(asMETHOD(ScriptRandom,grab), asMETHOD(ScriptRandom,drop));
	rnd.addFactory("RandomEngine@ f(uint seed)", asFUNCTION(ScriptRandom::make));
	rnd.addMethod("uint randomi()", asMETHOD(ScriptRandom,randomi));
	rnd.addMethod("uint randomi(uint min, uint max)", asMETHOD(ScriptRandom,randomi_r));
	rnd.addMethod("float randomf()", asMETHOD(ScriptRandom,randomf));
	rnd.addMethod("float randomf(float min, float max)", asMETHOD(ScriptRandom,randomf_r));
	rnd.addMethod("double randomd()", asMETHOD(ScriptRandom,randomd));
	rnd.addMethod("double randomd(double min, double max)", asMETHOD(ScriptRandom,randomd_r));

	ClassBind color("Color", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C | asOBJ_APP_CLASS_ALLINTS, sizeof(Color));
	ClassBind colorf("Colorf", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C | asOBJ_APP_CLASS_ALLFLOATS, sizeof(Colorf));

	{
		Namespace ns("colors");
		bindGlobal("Color White", &white);
		bindGlobal("Color Red", &red);
		bindGlobal("Color Green", &green);
		bindGlobal("Color Orange", &orange);
		bindGlobal("Color Blue", &blue);
		bindGlobal("Color Black", &black);
		bindGlobal("Color Invisible", &invisible);
	}

	color.addMember("uint8 r", 0);
	color.addMember("uint8 g", 1);
	color.addMember("uint8 b", 2);
	color.addMember("uint8 a", 3);
	color.addMember("uint color", offsetof(Color, color));
	color.addExternMethod("uint get_rgba() const", asFUNCTION(color_get_rgba))
		doc("Gets the uint representation of the Color's values as 0xRRGGBBAA.", "");

	color.addConstructor("void f(uint8, uint8, uint8, uint8)", asFUNCTION(color8));
	color.addConstructor("void f(uint32)", asFUNCTION(color32));
	color.addConstructor("void f(const Colorf &in)", asFUNCTION(color_cf));
	color.addConstructor("void f()", asFUNCTION(colorw));

	color.addMethod("Color getInterpolated(const Color&in other, float pct) const", asMETHOD(Color, getInterpolated));
	color.addMethod("Color interpolate(const Color&in other, float pct) const", asMETHOD(Color, getInterpolated));
	color.addMethod("Color opMul(const Color&in other) const", asMETHOD(Color, operator*));

	color.addExternMethod("void opAssign(const Colorf &in)", asFUNCTION(color_cf));

	colorf.addMember("float r", offsetof(Colorf, r));
	colorf.addMember("float g", offsetof(Colorf, g));
	colorf.addMember("float b", offsetof(Colorf, b));
	colorf.addMember("float a", offsetof(Colorf, a));

	colorf.addMethod("float get_value()", asMETHOD(Colorf, getValue));
	colorf.addMethod("float get_saturation()", asMETHOD(Colorf, getSaturation));
	colorf.addMethod("float get_hue()", asMETHOD(Colorf, getHue));
	colorf.addMethod("void fromHSV(float h, float s, float v)", asMETHOD(Colorf, fromHSV));
	
	colorf.addMethod("Colorf opMul(float factor) const", asMETHOD(Colorf, operator*));
	colorf.addMethod("void opAddAssign(const Colorf& col)", asMETHODPR(Colorf,operator+=,(const Colorf&),Colorf&));
	colorf.addMethod("void opAssign(const Color& col)", asMETHODPR(Colorf,operator=,(const Color&),void));

	colorf.addConstructor("void f()", asFUNCTION(colorfw));
	colorf.addConstructor("void f(float r, float g, float b)", asFUNCTION(colorf3));
	colorf.addConstructor("void f(float r, float g, float b, float a)", asFUNCTION(colorf4));
	colorf.addConstructor("void f(const Color& other)", asFUNCTION(colorfc));

	bind("Colorf blackBody(float kelvins, float brightness)", asFUNCTION(blackBodyColor));

	ClassBind* v = 0;

#define bindVecOps(v, name, type){\
	v->addMethod(name " opAdd(const " name " &in) const", asMETHOD(type, operator+));\
	v->addMethod(name "& opAddAssign(const " name " &in)", asMETHOD(type, operator+=));\
	v->addMethod(name " opSub(const " name " &in) const", asMETHODPR(type, operator-, (const type&) const, type));\
	v->addMethod(name "& opSubAssign(const " name " &in)", asMETHOD(type, operator-=));\
	v->addMethod("bool opEquals(const " name " &in) const", asMETHOD(type, operator==));\
	}

#define bindScalarOps(v, name, type, tname, ttype){\
	v->addMethod(name " opMul(double) const", asMETHODPR(type, operator*, (double) const, type));\
	v->addMethod(name "& opMulAssign(double)", asMETHODPR(type, operator*=, (double), type&));\
	v->addMethod(name " opDiv(double) const", asMETHODPR(type, operator/, (double) const, type));\
	v->addMethod(name "& opDivAssign(double)", asMETHODPR(type, operator/=, (double), type&));\
	}

	//Bind vec2
#define bindVector2(name, type, tname, ttype, flags){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C | flags, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(vector2d_e<ttype>));\
	v->addConstructor("void f(" tname ")", asFUNCTION(vector2d_s<ttype>));\
	v->addConstructor("void f(" tname "," tname ")", asFUNCTION(vector2d<ttype>));\
	\
	v->addMember(tname " x", offsetof(type, x));\
	v->addMember(tname " width", offsetof(type, x));\
	v->addMember(tname " y", offsetof(type, y));\
	v->addMember(tname " height", offsetof(type, y));\
	\
	v->addMethod("double distanceTo(const " name " &in) const", asMETHOD(type,distanceTo));\
	v->addMethod("double distanceToSQ(const " name " &in) const", asMETHOD(type,distanceToSQ));\
	v->addMethod("double dot(const " name " &in) const", asMETHOD(type,dot));\
	v->addMethod("double radians() const", asMETHOD(type,radians));\
	v->addMethod("double getRotation(const " name "&in) const", asMETHOD(type,getRotation));\
	v->addMethod("double get_length() const", asMETHOD(type,length));\
	v->addMethod("double get_lengthSQ() const", asMETHOD(type,lengthSQ));\
	\
	v->addMethod(name "& normalize(" tname " length = 1)", asMETHOD(type, normalize));\
	v->addMethod(name " normalized(" tname " length = 1) const", asMETHOD(type, normalized));\
	v->addMethod(name "& rotate(double radians)", asMETHOD(type, rotate));\
	\
	bindVecOps(v, name, type);\
	bindScalarOps(v, name, type, tname, ttype);\
	\
	v->addExternMethod("string opAdd_r(string&) const", asFUNCTION(vec2_toString<ttype>));\
	bind("void print(const " name " &in)", asFUNCTION(vec2_print<ttype>));\
	}

#define bindVector2Copy(name, ttype){\
	ClassBind c(name);\
	c.addConstructor("void f(const vec2i& other)", asFUNCTION((v2d_copy<ttype, int>)));\
	c.addConstructor("void f(const vec2u& other)", asFUNCTION((v2d_copy<ttype, unsigned>)));\
	c.addConstructor("void f(const vec2f& other)", asFUNCTION((v2d_copy<ttype, float>)));\
	c.addConstructor("void f(const vec2d& other)", asFUNCTION((v2d_copy<ttype, double>)));\
	}

	bindVector2("vec2i", vec2i, "int", int, asOBJ_APP_CLASS_ALLINTS);
	bindVector2("vec2u", vec2u, "uint", unsigned, asOBJ_APP_CLASS_ALLINTS);
	bindVector2("vec2f", vec2f, "float", float, asOBJ_APP_CLASS_ALLFLOATS);
	bindVector2("vec2d", vec2d, "double", double, asOBJ_APP_CLASS_ALLFLOATS);

	bindVector2Copy("vec2i", int);
	bindVector2Copy("vec2u", unsigned);
	bindVector2Copy("vec2f", float);
	bindVector2Copy("vec2d", double);

	//Bind vec3
#define bindVector3(name, type, tname, ttype, flags){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CK flags, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(vector3d_e<ttype>));\
	v->addConstructor("void f(" tname ")", asFUNCTION(vector3d_s<ttype>));\
	v->addConstructor("void f(" tname "," tname "," tname ")", asFUNCTION(vector3d<ttype>));\
	\
	v->addMember(tname " x", offsetof(type, x));\
	v->addMember(tname " y", offsetof(type, y));\
	v->addMember(tname " z", offsetof(type, z));\
	\
	bindVecOps(v, name, type);\
	bindScalarOps(v, name, type, tname, ttype);\
	\
	v->addMethod("void set(" tname " x, " tname " y, " tname " z) const", asMETHOD(type, set));\
	\
	v->addMethod("double distanceTo(const " name " &in) const", asMETHOD(type, distanceTo));\
	v->addMethod("double distanceToSQ(const " name " &in) const", asMETHOD(type, distanceToSQ));\
	\
	v->addMethod(tname " get_length() const", asMETHOD(type, getLength));\
	v->addMethod(tname "& set_length(" tname " length)", asMETHOD(type, normalize));\
	v->addMethod(tname " get_lengthSQ() const", asMETHOD(type, getLengthSQ));\
	\
	v->addMethod(name " cross(const " name " &in) const", asMETHOD(type, cross));\
	v->addMethod("double dot(const " name " &in) const", asMETHOD(type, dot));\
	v->addMethod("bool get_zero() const", asMETHOD(type, zero));\
	\
	v->addExternMethod(name "& normalize()", asFUNCTION(vec_normalize<type>));\
	v->addExternMethod(name " normalized() const", asFUNCTION(vec_normalized<type>));\
	\
	v->addMethod(name "& normalize(" tname " length)", asMETHOD(type, normalize));\
	v->addMethod(name " normalized(" tname " length) const", asMETHOD(type, normalized));\
	\
	v->addMethod(name " interpolate(const " name " &in, double pct) const", asMETHOD(type, interpolate));\
	v->addMethod(name " slerp(" name "&, double pct)", asMETHOD(type, slerp));\
	v->addMethod("double angleDistance(const " name "&in) const", asMETHOD(type, angleDistance));\
	\
	v->addExternMethod("string toString(uint decimals = 2) const", asFUNCTION(vec3_toString<ttype>));\
	v->addExternMethod("string opAdd_r(const string&) const", asFUNCTION(vec3_addString<ttype>));\
	bind("void print(const " name " &in)", asFUNCTION(vec3_print<ttype>));\
	\
	bind(name " " name "_front(" tname " len = 1)", asFUNCTION(vec3<ttype>::front));\
	bind(name " " name "_right(" tname " len = 1)", asFUNCTION(vec3<ttype>::right));\
	bind(name " " name "_up(" tname " len = 1)", asFUNCTION(vec3<ttype>::up));\
	}

#define bindVector3Copy(name, ttype){\
	ClassBind c(name);\
	c.addConstructor("void f(const vec3i& other)", asFUNCTION((v3d_copy<ttype, int>)));\
	c.addConstructor("void f(const vec3f& other)", asFUNCTION((v3d_copy<ttype, float>)));\
	c.addConstructor("void f(const vec3d& other)", asFUNCTION((v3d_copy<ttype, double>)));\
	}

	bindVector3("vec3i", vec3i, "int", int, | asOBJ_APP_CLASS_ALLINTS);
	bindVector3("vec3f", vec3f, "float", float,);
	bindVector3("vec3d", vec3d, "double", double,);

	bindVector3Copy("vec3i", int);
	bindVector3Copy("vec3f", float);
	bindVector3Copy("vec3d", double);

	//Bind vec4
#define bindVector4(name, type, tname, ttype, flags){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CK flags, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(vector4d_e<ttype>));\
	v->addConstructor("void f(" tname "," tname "," tname "," tname ")", asFUNCTION(vector4d<ttype>));\
	\
	v->addExternMethod("string opAdd_r(const string&) const", asFUNCTION(vec4_toString<ttype>));\
	bind("void print(const " name " &in)", asFUNCTION(vec4_print<ttype>));\
	\
	v->addMember(tname " x", offsetof(type, x));\
	v->addMember(tname " y", offsetof(type, y));\
	v->addMember(tname " z", offsetof(type, z));\
	v->addMember(tname " w", offsetof(type, w));\
	}

#define bindVector4Copy(name, ttype){\
	ClassBind c(name);\
	c.addConstructor("void f(const vec4i& other)", asFUNCTION((v4d_copy<ttype, int>)));\
	c.addConstructor("void f(const vec4f& other)", asFUNCTION((v4d_copy<ttype, float>)));\
	c.addConstructor("void f(const vec4d& other)", asFUNCTION((v4d_copy<ttype, double>)));\
	}

	bindVector4("vec4i", vec4i, "int", int, | asOBJ_APP_CLASS_ALLINTS);
	bindVector4("vec4f", vec4f, "float", float,);
	bindVector4("vec4d", vec4d, "double", double,);

	bindVector4Copy("vec4i", int);
	bindVector4Copy("vec4f", float);
	bindVector4Copy("vec4d", double);

	//color.addExternMethod("vec4f get_vec4() const", asFUNCTION(color_get_vec4))
	//	doc("Get the vec4 representation of a color for passing to shaders.", "");

	color.addExternMethod("void toVec4(vec4f&) const", asFUNCTION(color_to_vec4))
		doc("Write the vec4 representation of a color for passing to shaders.", "");
	
#define bindPlane(name, type, tname, vname, ttype, flags){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CK flags, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(vector4d_e<ttype>));\
	v->addConstructor("void f(const " vname " &in," tname ")", asFUNCTION(plane_dd<ttype>));\
	v->addConstructor("void f(const " vname " &in,const " vname " &in)", asFUNCTION(plane_pd<ttype>));\
	v->addConstructor("void f(const " vname " &in, const " vname " &in, const " vname " &in)", asFUNCTION(plane_tri<ttype>));\
	\
	v->addMember(vname " dir", offsetof(type, dir));\
	v->addMember(tname " dist", offsetof(type, dist));\
	\
	v->addMethod("double distFromPlane(const " vname " &in) const", asMETHOD(type,distanceFromPlane));\
	v->addMethod("bool inFront(const " vname " &in) const", asMETHOD(type,pointInFront));\
	}
	
	bindPlane("planef", plane<float>, "float", "vec3f", float, );
	bindPlane("planed", planed, "double", "vec3d", double, );

#define bindQuaternion_b(name, type, tname, ttype, vname, vtype)\
	v->addConstructor("void f()", asFUNCTION(quat_e<ttype>));\
	v->addConstructor("void f(" tname "," tname "," tname "," tname ")", asFUNCTION(quat<ttype>));\
	v->addConstructor("void f(" vname "," tname ")", asFUNCTION(quat_v<ttype>));\
	\
	v->addMember(vname " xyz", offsetof(type, xyz));\
	v->addMember(tname " w", offsetof(type, w));\
	\
	v->addMethod(name " opMul(" name "&) const", asMETHODPR(type, operator*, (const type&) const, type));\
	v->addExternMethod("void transform(const " vname "&, " vname "&) const", asFUNCTION(quatTransform<ttype>));\
	v->addMethod(name "& opMulAssign(" name "&)", asMETHODPR(type, operator*=, (const type&), type&));\
	\
	v->addMethod(vname " opMul(const " vname "&) const", asMETHODPR(type, operator*, (const vtype&) const, vtype));\
	v->addMethod(name "& normalize(" tname  " len = 1)", asMETHOD(type, normalize));\
	v->addMethod(name " inverted()", asMETHOD(type, inverted));\
	v->addMethod(name " slerp(" name "&, " tname ")", asMETHOD(type, slerp));\
	v->addMethod("bool opEquals(const " name " &in) const", asMETHOD(type, operator==));\
	v->addMethod("double dot(const " name " &in) const", asMETHOD(type, dot));\
	\
	bind(name " " name "_fromAxisAngle(const " vname "& ," tname ")", asFUNCTION(quaternion<ttype>::fromAxisAngle));\
	bind(name " " name "_fromVecToVec(const " vname "& , const " vname "&)", asFUNCTIONPR(quaternion<ttype>::fromImpliedTransform, (const vec3<ttype>&, const vec3<ttype>&), quaternion<ttype>));\
	bind(name " " name "_fromVecToVec(const " vname "& , const " vname "& , const " vname "& up)", asFUNCTIONPR(quaternion<ttype>::fromImpliedTransform, (const vec3<ttype>&, const vec3<ttype>&, const vec3<ttype>&), quaternion<ttype>));\
	}

#ifdef _MSC_VER
#define bindQuaternion(name, type, tname, ttype, vname, vtype){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(type));\
	bindQuaternion_b(name, type, tname, ttype, vname, vtype)
#else
#define bindQuaternion(name, type, tname, ttype, vname, vtype){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CK, sizeof(type));\
	v->addConstructor("void f(const " name "&)", asFUNCTION(quat_copy<ttype>));\
	bindQuaternion_b(name, type, tname, ttype, vname, vtype)
#endif

	bindQuaternion("quaternionf", quaternionf, "float", float, "vec3f", vec3f);
	bindQuaternion("quaterniond", quaterniond, "double", double, "vec3d", vec3d);

#define declareRect(name, type, flags) { ClassBind bind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C flags, sizeof(type)); }

#define bindRect(name, type, tname, ttype, vname, vtype){\
	delete v;\
	v = new ClassBind(name);\
	v->addConstructor("void f()", asFUNCTION(rect_e<ttype>));\
	v->addConstructor("void f(" tname "," tname "," tname "," tname ")", asFUNCTION(rect_c<ttype>));\
	v->addConstructor("void f(const " vname " &in, const " vname " &in)", asFUNCTION(rect_v<ttype>));\
	\
	v->addMember(vname " topLeft", offsetof(type, topLeft));\
	v->addMember(vname " botRight", offsetof(type, botRight));\
	\
	bind(name " " name "_area(" tname "," tname "," tname "," tname ")", asFUNCTION(rect_ac<ttype>));\
	bind(name " " name "_area(const " vname " &in, const " vname " &in)", asFUNCTION(rect_av<ttype>));\
	bind(name " " name "_centered(const " name " &in within, const " vname " &in size)", asFUNCTION(rect_centered<ttype>));\
	bind(name " " name "_centered(const " vname " &in around, const " vname " &in size)", asFUNCTION(rect_centeredv<ttype>));\
	\
	v->addMethod("bool opEquals(const " name " &in) const", asMETHOD(type, operator==));\
	v->addMethod(name " opAdd(const " vname " &in) const", asMETHOD(type, operator+));\
	v->addMethod(name "& opAddAssign(const " vname " &in)", asMETHOD(type, operator+=));\
	v->addMethod(name " opSub(const " vname " &in) const", asMETHOD(type, operator-));\
	v->addMethod(name "& opSubAssign(const " vname " &in)", asMETHOD(type, operator-=));\
	\
	v->addMethod(vname " get_size() const", asMETHOD(type, getSize));\
	v->addMethod(tname " get_width() const", asMETHOD(type, getWidth));\
	v->addMethod(tname " get_height() const", asMETHOD(type, getHeight));\
	v->addMethod(vname " get_center() const", asMETHOD(type, getCenter));\
	\
	v->addMethod("bool isWithin(const " vname " &in) const", asMETHOD(type, isWithin));\
	v->addMethod("float distanceTo(const " vname " &in) const", asMETHOD(type, distanceTo));\
	v->addMethod("bool contains(const " vname " &in) const", asMETHOD(type, isWithin));\
	v->addMethod("bool isRectInside(const " name " &in) const", asMETHOD(type, isRectInside));\
	v->addMethod("bool overlaps(const " name " &in) const", asMETHOD(type, overlaps));\
	v->addMethod(name " resized(" tname " w = 0, " tname " h = 0, double horizAlign = 0.0, double vertAlign = 0.0) const", asMETHOD(type, resized));\
	v->addMethod(name " padded(" tname " padding) const", asMETHODPR(type, padded, (ttype) const, type));\
	v->addMethod(name " padded(" tname " horiz, " tname " vert) const", asMETHODPR(type, padded, (ttype, ttype) const, type));\
	v->addMethod(name " padded(" tname " left, " tname " top, " tname " right, " tname " bottom) const",\
			asMETHODPR(type, padded, (ttype, ttype, ttype, ttype) const, type));\
	v->addMethod(name " clipAgainst(const " name " &in) const", asMETHOD(type, clipAgainst));\
	v->addMethod(name " interpolate(const " name " &in, double percent) const", asMETHOD(type, interpolate));\
	v->addMethod(name " aspectAligned(double aspect, double horizAlign = 0.5, double vertAlign = 0.5) const", asMETHOD(type, aspectAligned));\
	\
	v->addExternMethod("string opAdd_r(string&) const", asFUNCTION(rect_toString<ttype>));\
	bind("void print(const " name " &in)", asFUNCTION(rect_print<ttype>));\
	}

#define bindRectConv(nameFrom, typeFrom, typeTo) v->addConstructor("void f(const " nameFrom " &in)", asFUNCTION((rect_convert<typeFrom, typeTo>)))
	
	declareRect("recti", recti, | asOBJ_APP_CLASS_ALLINTS);
	declareRect("rectf", rectf, | asOBJ_APP_CLASS_ALLFLOATS);
	declareRect("rectd", rectd, | asOBJ_APP_CLASS_ALLFLOATS);

	bindRect("recti", recti, "int", int, "vec2i", vec2i);
	bindRectConv("rectf", float, int);
	bindRectConv("rectd", double, int);

	bindRect("rectf", rectf, "float", float, "vec2f", vec2f);
	bindRectConv("recti", int, float);
	bindRectConv("rectd", double, float);

	bindRect("rectd", rectd, "double", double, "vec2d", vec2d);
	bindRectConv("rectf", float, double);
	bindRectConv("recti", int, double);

#define bindLine3(name, type, tname, ttype, vname, vtype, flags){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C flags, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(line3_e<ttype>));\
	v->addConstructor("void f(const " vname " &in, const " vname " &in)", asFUNCTION(line3<ttype>));\
	\
	v->addMember(vname " start", offsetof(type, start));\
	v->addMember(vname " end", offsetof(type, end));\
	\
	v->addMethod("bool intersectX(" vname "&out vec, " tname " x = 0, bool segment = true) const", asMETHOD(type, intersectX));\
	v->addMethod("bool intersectY(" vname "&out vec, " tname " y = 0, bool segment = true) const", asMETHOD(type, intersectY));\
	v->addMethod("bool intersectZ(" vname "&out vec, " tname " z = 0, bool segment = true) const", asMETHOD(type, intersectZ));\
	v->addMethod(vname " getDirection() const", asMETHOD(type, getDirection));\
	v->addMethod(vname " get_direction() const", asMETHOD(type, getDirection));\
	v->addMethod(vname " getClosestPoint(const " vname " &in, bool) const", asMETHOD(type, getClosestPoint));\
	v->addMethod("double get_length() const", asMETHOD(type, getLength));\
	v->addMethod("double get_lengthSQ() const", asMETHOD(type, getLengthSQ));\
	v->addMethod(vname " get_midpoint() const", asMETHOD(type, getCenter));\
	}

	bindLine3("line3di", line3di, "int", int, "vec3i", vec2i, | asOBJ_APP_CLASS_ALLINTS);
	bindLine3("line3df", line3df, "float", float, "vec3f", vec2f, | asOBJ_APP_CLASS_ALLFLOATS);
	bindLine3("line3dd", line3dd, "double", double, "vec3d", vec2d, | asOBJ_APP_CLASS_ALLFLOATS);

#define bindHex(name, type, tname, ttype){\
	delete v;\
	v = new ClassBind(name, asOBJ_VALUE | asOBJ_APP_CLASS_CDAK, sizeof(type));\
	v->addConstructor("void f()", asFUNCTION(hexgrid<ttype>));\
	v->addConstructor("void f(uint width, uint height)", asFUNCTION(hexgrid_v<ttype>));\
	v->addConstructor("void f(const " name "& other)", asFUNCTION(hexgrid_c<ttype>));\
	v->addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(delhex<ttype>));\
	\
	v->addMember("uint width", offsetof(type, width));\
	v->addMember("uint height", offsetof(type, height));\
	\
	v->addMethod("bool advance(uint& x, uint& y, HexGridAdjacency dir, uint amount = 1) const", asMETHODPR(HexGrid<ttype>, advance, (unsigned&, unsigned&, HexGridAdjacency, unsigned) const, bool));\
	\
	v->addMethod("bool advance(vec2u& pos, HexGridAdjacency dir, uint amount = 1) const", asMETHODPR(HexGrid<ttype>, advance, (vec2u&, HexGridAdjacency, unsigned) const, bool));\
	\
	v->addMethod("void clear(" tname " value)", asMETHOD(HexGrid<ttype>, clear));\
	v->addMethod("uint count(" tname " value) const", asMETHOD(HexGrid<ttype>, count));\
	\
	v->addMethod("bool valid(const vec2u& value) const", asMETHODPR(HexGrid<ttype>, valid, (const vec2u&) const, bool));\
	v->addMethod("bool valid(const vec2u& value, HexGridAdjacency adj) const", asMETHODPR(HexGrid<ttype>, valid, (const vec2u&,HexGridAdjacency) const, bool));\
	\
	v->addMethod("void resize(uint w, uint h)", asMETHODPR(HexGrid<ttype>, resize, (unsigned, unsigned), void));\
	v->addMethod("void resize(vec2u size)", asMETHODPR(HexGrid<ttype>, resize, (vec2u), void));\
	v->addMethod(name "& opAssign(const " name "&in other)", asMETHOD(HexGrid<ttype>, operator=));\
	\
	v->addExternMethod(tname "& get(uint x, uint y)", asFUNCTION(hexgrid_get<ttype>));\
	v->addExternMethod("const " tname "& get(uint x, uint y) const", asFUNCTION(hexgrid_get<ttype>));\
	\
	v->addExternMethod(tname "& get(const vec2u&in pos)", asFUNCTION(hexgrid_get_v<ttype>));\
	v->addExternMethod("const " tname "& get(const vec2u&in pos) const", asFUNCTION(hexgrid_get_v<ttype>));\
	\
	v->addExternMethod(tname "& get(const vec2u&in pos, HexGridAdjacency adj)", asFUNCTION(hexgrid_get_va<ttype>));\
	v->addExternMethod("const " tname "& get(const vec2u&in pos, HexGridAdjacency adj) const", asFUNCTION(hexgrid_get_va<ttype>));\
	\
	v->addExternMethod(tname "& opIndex(const vec2u&in pos)", asFUNCTION(hexgrid_get_v<ttype>));\
	v->addExternMethod("const " tname "& opIndex(const vec2u&in pos) const", asFUNCTION(hexgrid_get_v<ttype>));\
	}

	EnumBind adj("HexGridAdjacency");
	adj["HEX_DownLeft"] = HEX_DownLeft;
	adj["HEX_Down"] = HEX_Down;
	adj["HEX_DownRight"] = HEX_DownRight;
	adj["HEX_UpRight"] = HEX_UpRight;
	adj["HEX_Up"] = HEX_Up;
	adj["HEX_UpLeft"] = HEX_UpLeft;

	bind("vec2d getHexPosition(uint x, uint y)", asFUNCTIONPR(HexGrid<bool>::getEffectivePosition, (unsigned, unsigned), vec2d));
	bind("vec2d getHexPosition(const vec2u&in pos)", asFUNCTIONPR(HexGrid<bool>::getEffectivePosition, (const vec2u&), vec2d));
	bind("vec2i getHexGridPosition(const vec2d&in pos)", asFUNCTION(HexGrid<bool>::getGridPosition));
	bind("bool advanceHexPosition(vec2u& pos, const vec2u&in size, HexGridAdjacency dir, uint amount = 1)", asFUNCTION(HexGrid<bool>::advancePosition));
	bind("double hexToRadians(HexGridAdjacency adj)", asFUNCTION(HexGrid<bool>::RadiansFromAdjacency));
	bind("HexGridAdjacency radiansToHex(double radians)", asFUNCTION(HexGrid<bool>::AdjacencyFromRadians));

	bindHex("HexGridi", HexGrid<int>, "int", int);
	bindHex("HexGridb", HexGrid<bool>, "bool", bool);
	bindHex("HexGridd", HexGrid<double>, "double", double);


	ClassBind image("Image", asOBJ_REF, 0);
	image.addFactory("Image@ f(const string& file)", asFUNCTION(makeImage));
	image.addFactory("Image@ f(const Sprite& sprt)", asFUNCTION(makeImage_sprt));
	image.addFactory("Image@ f(const Texture& tex, const recti& source)", asFUNCTION(makeImage_tex));
	image.addFactory("Image@ f(const Image& other, const recti& source)", asFUNCTION(makeImage_img));
	image.addFactory("Image@ f(const vec2u& size, uint channels)", asFUNCTION(makeImage_size));
	image.setReferenceFuncs(asMETHOD(ScriptImage,grab), asMETHOD(ScriptImage,drop));
	image.addMethod("Image& opAssign(const Image& other)", asMETHOD(ScriptImage,operator=));
	image.addMethod("vec2u get_size() const", asMETHOD(ScriptImage,get_size));
	image.addMethod("Color get(uint x, uint y) const", asMETHODPR(ScriptImage,get,(unsigned,unsigned),Color));
	image.addMethod("Color get(const vec2u &in) const", asMETHODPR(ScriptImage,get,(const vec2u&),Color));
	image.addMethod("void set(uint x, uint y, Color col)", asMETHODPR(ScriptImage,set,(unsigned,unsigned,Color),void));
	image.addMethod("void set(const vec2u &in, Color col)", asMETHODPR(ScriptImage,set,(const vec2u&,Color),void));
	image.addMethod("Color get(float x, float y) const", asMETHODPR(ScriptImage,getTexel,(float,float),Color));
	image.addMethod("Color get(const vec2f &in) const", asMETHODPR(ScriptImage,getTexel,(const vec2f&),Color));
	image.addMethod("void save(const string& filename) const", asMETHOD(ScriptImage, save));

	ClassBind locked_int("locked_int", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(LocklessInt));
	locked_int.addConstructor("void f()", asFUNCTION(makeLockedInt));
	locked_int.addConstructor("void f(int)", asFUNCTION(makeLockedInt_v));
	locked_int.addMember("int value", offsetof(LocklessInt,value));
	locked_int.addMethod("int opAssign(int)", asMETHODPR(LocklessInt,operator=,(int),int));
	locked_int.addMethod("int opAddAssign(int)", asMETHOD(LocklessInt,operator+=));
	locked_int.addMethod("int opSubAssign(int)", asMETHOD(LocklessInt,operator-=));
	locked_int.addMethod("int opMulAssign(int)", asMETHOD(LocklessInt,operator*=));
	locked_int.addMethod("int opDivAssign(int)", asMETHOD(LocklessInt,operator/=));
	locked_int.addMethod("int opOrAssign(int)",  asMETHOD(LocklessInt,operator|=));
	locked_int.addMethod("int opAndAssign(int)", asMETHOD(LocklessInt,operator&=));
	locked_int.addMethod("int opXorAssign(int)", asMETHOD(LocklessInt,operator^=));
	locked_int.addMethod("int opAnd(int) const", asMETHOD(LocklessInt,operator&));
	locked_int.addMethod("int opOr(int) const", asMETHOD(LocklessInt,operator|));
	locked_int.addMethod("int consume(int)", asMETHOD(LocklessInt,consume));
	locked_int.addMethod("int min(int)", asMETHOD(LocklessInt,minimum));
	locked_int.addMethod("int max(int)", asMETHOD(LocklessInt,maximum));
	locked_int.addMethod("int interp(int, double)", asMETHOD(LocklessInt,interp));
	locked_int.addMethod("int average(int)", asMETHOD(LocklessInt,avg));
	locked_int.addMethod("int toggle()", asMETHOD(LocklessInt,toggle));

	ClassBind locked_double("locked_double", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(LocklessDouble));
	locked_double.addConstructor("void f()", asFUNCTION(makeLockedDouble));
	locked_double.addConstructor("void f(double)", asFUNCTION(makeLockedDouble_v));
	locked_double.addMember("double value", offsetof(LocklessDouble,value));
	locked_double.addMethod("double opAssign(double)", asMETHODPR(LocklessDouble,operator=,(double),double));
	locked_double.addMethod("double opAddAssign(double)", asMETHOD(LocklessDouble,operator+=));
	locked_double.addMethod("double opSubAssign(double)", asMETHOD(LocklessDouble,operator-=));
	locked_double.addMethod("double opMulAssign(double)", asMETHOD(LocklessDouble,operator*=));
	locked_double.addMethod("double opDivAssign(double)", asMETHOD(LocklessDouble,operator/=));
	locked_double.addMethod("double consume(double)", asMETHOD(LocklessDouble,consume));
	locked_double.addMethod("double min(double)", asMETHOD(LocklessDouble,minimum));
	locked_double.addMethod("double max(double)", asMETHOD(LocklessDouble,maximum));
	locked_double.addMethod("double interp(double, double)", asMETHOD(LocklessDouble,interp));
	locked_double.addMethod("double average(double)", asMETHOD(LocklessDouble,avg));
	locked_double.addMethod("double toggle()", asMETHOD(LocklessDouble,toggle));

	ClassBind sd("StateDefinition", asOBJ_REF | asOBJ_NOCOUNT);

	ClassBind sl("StateList", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(StateList));

	sl.addConstructor("void f()", asFUNCTION(createDummyStateList));
	sl.addConstructor("void f(const StateDefinition@ def)", asFUNCTION(createStateList));
	sl.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(destroyStateList));

	sl.addMember("StateDefinition@ def", offsetof(StateList, def));
	sl.addMethod("StateList& opAssign(StateList&)", asMETHOD(StateList, operator=));
	sl.addMethod("void change(const StateDefinition@)", asMETHOD(StateList, change));

	bind("const StateDefinition@ getStateDefinition(const string &in name)", asFUNCTION(getStateDefinition));

	ClassBind pq("priority_queue", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(p_queue));
	pq.addConstructor("void f()", asFUNCTION(pq_construct));
	pq.addDestructor("void f()", asFUNCTION(pq_destruct));
	pq.addMethod("bool empty()", asMETHOD(p_queue, empty));
	pq.addMethod("uint size()", asMETHOD(p_queue, size));
	pq.addMethod("void pop()", asMETHOD(p_queue, pop));

	pq.addExternMethod("int top()", asFUNCTION(pq_top));
	pq.addExternMethod("double top_priority()", asFUNCTION(pq_top_prior));

	pq.addExternMethod("void push(int value, double priority = 0)", asFUNCTION(pq_push));

	ClassBind si("set_int", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(set_int));
	si.addConstructor("void f()", asFUNCTION(si_construct));
	si.addDestructor("void f()", asFUNCTION(si_destruct));
	si.addMethod("void clear()", asMETHOD(set_int, clear));
	si.addMethod("uint size() const", asMETHOD(set_int, size));
	si.addExternMethod("bool contains(int64 value) const", asFUNCTION(si_has));
	si.addExternMethod("void insert(int64 value)", asFUNCTION(si_insert));
	si.addExternMethod("void erase(int64 value)", asFUNCTION(si_erase));

#ifdef _MSC_VER
	si.addExternMethod("void reserve(int value)", asFUNCTION(unordered_set_reserve<set_int_type>));
#else
	si.addMethod("void reserve(int value)", asMETHOD(set_int, reserve));
#endif

	//Bind elevation map
	{
		ClassBind em("ElevationMap", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(ElevationMap));
		em.addConstructor("void f()", asFUNCTION(em_construct));
		em.addDestructor("void f()", asFUNCTION(em_destruct));

		em.addMember("vec3d gridStart", offsetof(ElevationMap, gridStart));
		em.addMember("vec2d gridSize", offsetof(ElevationMap, gridSize));
		em.addMember("vec2d gridInterval", offsetof(ElevationMap, gridInterval));
		em.addMember("vec2i gridResolution", offsetof(ElevationMap, gridResolution));

		em.addMethod("void clear()", asMETHOD(ElevationMap, clear));
		em.addMethod("void addPoint(const vec3d& point, double radius = 0.0)", asMETHOD(ElevationMap, addPoint));
		em.addMethod("void generate(const vec2d& interval, double power = 2.0)", asMETHOD(ElevationMap, generate));
		em.addMethod("double lookup(int x, int y)", asMETHOD(ElevationMap, lookup));
		em.addMethod("bool getClosestPoint(const line3dd& line, vec3d &out)", asMETHOD(ElevationMap, getClosestPoint));
		em.addMethod("double get(vec2d point)", asMETHODPR(ElevationMap, get, (vec2d), double));
		em.addMethod("double get(double x, double y)", asMETHODPR(ElevationMap, get, (double, double), double));
	}

	//Bind physics world
	{
		ClassBind phys("PhysicsWorld", asOBJ_REF);
		phys.addFactory("PhysicsWorld@ PhysicsWorld(double gridSize, double gridFuzz, uint gridCount)", asFUNCTION(makePhysWorld));
		phys.setReferenceFuncs(asMETHOD(PhysicsWorld,grab), asMETHOD(PhysicsWorld,drop));

		bind("void set_physicsWorld(PhysicsWorld@ world)", asFUNCTION(setPhysicsWorld));
		bind("PhysicsWorld@ get_physicsWorld()", asFUNCTION(getPhysicsWorld));

		bind("void set_nodePhysicsWorld(PhysicsWorld@ world)", asFUNCTION(setNodePhysicsWorld));
	}

	//Bind name generator
	{
		ClassBind ng("NameGenerator", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(NameGenerator));
		ng.addConstructor("void f()", asFUNCTION(ng_construct));
		ng.addDestructor("void f()", asFUNCTION(ng_destruct));

		ng.addMember("float mutationChance", offsetof(NameGenerator, mutationChance))
			doc("When generating, chance to insert a random character at any point. Defaults to 0.");
		ng.addMember("bool useGeneration", offsetof(NameGenerator, useGeneration))
			doc("Whether to use dynamic generation or only pick random names from the list. Defaults to true.");
		ng.addMember("bool preventDuplicates", offsetof(NameGenerator, preventDuplicates))
			doc("Whether to prevent this generator from generating the same name twice. Defaults to false.");

		ng.addMethod("void clear()", asMETHOD(NameGenerator, clear))
			doc("Clear all internal data, including the name list and mutation chance.");

		ng.addExternMethod("void read(const string&in filename, bool resolve = true)", asFUNCTION(ng_read))
			doc("Read the list of names from a file.", "File to read from.", "Whether to resolve the file to the mod.");
		ng.addExternMethod("void write(const string&in filename, bool resolve = true)", asFUNCTION(ng_write))
			doc("Write the list of names to a file.", "File to write to.", "Whether to resolve the file to the mod.");

		ng.addMethod("bool hasName(const string&in name)", asMETHOD(NameGenerator, hasName))
			doc("Check whether a name is in the internal name list.", "Name to check for.", "Whether it is in the list.");
		ng.addMethod("uint get_nameCount()", asMETHOD(NameGenerator, getNameCount))
			doc("", "The total amount of names stored in this generator.");
		ng.addMethod("void addName(const string&in name)", asMETHOD(NameGenerator, addName))
			doc("Add a name to the internal name list.", "Name to add.");
		ng.addMethod("void addAssociation(int first, int second, int next)", asMETHOD(NameGenerator, addAssociation))
			doc("Add a character association to the markov chance tree.", "First unicode character to associate after.",
				"Second unicode character to associate after.", "Character that comes after the pair of unicode characters.");

		ng.addMethod("string generate()", asMETHOD(NameGenerator, generate))
			doc("Generate a new name using this name generator's rules.", "Generated name.");
	}

	//Bind bbcode parser
	{
		ClassBind tag("BBTag", asOBJ_REF | asOBJ_NOCOUNT);
		tag.addMember("string name", offsetof(BBCode::Tag, name))
			doc("Name of the tag.");
		tag.addMember("string argument", offsetof(BBCode::Tag, argument))
			doc("Argument of the tag.");
		tag.addMember("int type", offsetof(BBCode::Tag, type))
			doc("Type ID of the tag. By default, text nodes are -1 and tags are 0.");
		tag.addMember("int value", offsetof(BBCode::Tag, value))
			doc("Value of the tag, not filled out by default.");
		tag.addExternMethod("uint get_childCount()", asFUNCTION(bbtag_childCount))
			doc("", "Amount of child tags this tag has.");
		tag.addExternMethod("BBTag@ get_children(uint index)", asFUNCTION(bbtag_child))
			doc("", "Index of the child tag to get.", "Index-th child tag.");

		ClassBind bb("BBCode", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(BBCode));
		bb.addConstructor("void f()", asFUNCTION(bb_construct));
		bb.addDestructor("void f()", asFUNCTION(bb_destruct));

		bb.addMethod("void clear()", asMETHOD(BBCode, clear))
			doc("Clear the entire previously parsed tag tree.");
		bb.addExternMethod("BBTag@ get_root()", asFUNCTION(bb_root))
			doc("", "Root tag of the bbcode tree.");
		bb.addExternMethod("bool parse(const string& text)", asFUNCTION(bb_parse))
			doc("Parse BBCode text into a tree of tags.", "BBCode text to parse.",
				"Whether the parsing was succesful.");
		bind("string bbescape(const string& str, bool allowWikiLinks = false)", asFUNCTION(bb_escape));
		bind("string makebbLinks(const string& str)", asFUNCTION(bb_makeLinks));
	}

	//Thread safe linked containers
	{
		ClassBind linkMap("LinkMap", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(LinkMap));
		linkMap.addConstructor("void f()", asFUNCTION(lm_construct));
		linkMap.addConstructor("void f(uint64 defaultValue)", asFUNCTION(lm_construct_i));
		linkMap.addConstructor("void f(double defaultValue)", asFUNCTION(lm_construct_d));
		linkMap.addDestructor("void f()", asFUNCTION(lm_destruct));

		linkMap.addMethod("uint get_length() const", asMETHOD(LinkMap, size));
		linkMap.addMethod("uint64 getKeyAtIndex(uint index) const", asMETHOD(LinkMap, getKeyAtIndex));
		linkMap.addMethod("uint64 getAtIndex(uint index) const", asMETHOD(LinkMap, getAtIndex));
		linkMap.addMethod("double getDoubleAtIndex(uint index) const", asMETHOD(LinkMap, getDoubleAtIndex));

		linkMap.addMethod("uint64 get(uint64 key) const", asMETHOD(LinkMap, get));
		linkMap.addMethod("double getDouble(uint64 key) const", asMETHOD(LinkMap, getDouble));

		linkMap.addMethod("void set(uint64 key, uint64 value, int64 dirtyResolution = 0)", asMETHOD(LinkMap, set));
		linkMap.addMethod("void setDouble(uint64 key, double value, double dirtyResolution = 0.0)", asMETHOD(LinkMap, setDouble));

		linkMap.addMethod("bool hasDirty() const", asMETHOD(LinkMap, hasDirty));
		linkMap.addMethod("bool isDirty(uint64 key) const", asMETHOD(LinkMap, isDirty));
	}

	//Bind achivements
	{
		bind("void unlockAchievement(const string& id)", asFUNCTION(achieve));
		bind("void modStat(const string& id, int delta)", asFUNCTION(modStat<int>));
		bind("void modStat(const string& id, float delta)", asFUNCTION(modStat<float>));
		bind("bool getStat(const string& id, int &out value)", asFUNCTION(getStat<int>));
		bind("bool getStat(const string& id, float &out value)", asFUNCTION(getStat<float>));
		bind("bool getGlobalStat(const string& id, int64 &out value)", asFUNCTION(getGlobalStat<long long>));
		bind("bool getGlobalStat(const string& id, double &out value)", asFUNCTION(getGlobalStat<double>));
	}

	delete v;
}

};
