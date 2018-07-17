#pragma once
#include "compat/misc.h"
#include "render/render_state.h"
#include "render/render_mesh.h"
#include "mesh.h"
#include "render/driver.h"
#include "render/texture.h"
#include "render/spritesheet.h"
#include "render/shader.h"
#include "gui/skin.h"
#include "str_util.h"
#include <climits>
#include <map>
#include <unordered_map>

namespace audio {
	class ISoundSource;
	class ISound;
};

namespace scene {
	struct ParticleSystemDesc;
};

const Mesh emptyMesh;

namespace resource {

enum ResourceType {
	RT_Sound,
	RT_Material,
	RT_Mesh,
	RT_Shader,
	RT_Font,
	RT_Skin,
	RT_SpriteSheet,
	RT_ParticleSystem
};

class Sound {
public:
	audio::ISoundSource* source;
	std::string streamSource;
	float volume;
	bool loaded;
	Sound() : source(0), volume(1.f), loaded(false) {}
	
	audio::ISound* play2D(bool loop, bool pause, bool priority) const;
	audio::ISound* play3D(const vec3d& pos, bool loop, bool pause, bool priority) const;
};

struct ShaderGlobal {
	std::string name;
	render::Shader::VarType type;
	unsigned arraySize;
	int size;
	void* ptr;

	ShaderGlobal();

	template<class T>
	void setValue(unsigned index, T& v) const {
		if(index < arraySize)
			((T*)ptr)[index] = v;
	}
};

render::Texture* queueImage(Image* img, int priority = 0, bool mipmap = true, bool cachePixels = false);
void queueTextureUpdate(render::Texture* tex, Image* img, int priority = 0, bool mipmap = true, bool cachePixels = false);

class Library {
	void loadMaterials(const std::string& filename);
	void loadFonts(const std::string& filename);
	void loadModels(const std::string& filename);
	void loadShaders(const std::string& filename);
	void loadSkins(const std::string& filename);
	void loadSkin(const std::string& filename, gui::skin::Skin* skin);
	void loadSounds(const std::string& filename);

	static void initSkinNames();
	void clearTextures();

	class ErrorShader : public render::Shader {
		int compile() { return 0; }
		void bind(float*) const {}
		void updateDynamicVars() const {}
		void saveDynamicVars(float*) const { }
		void loadDynamicVars(float*) const { }
	public:
		ErrorShader() { constant = true; dynamicFloats = 0; }
	};

	class ErrorMesh : public render::RenderMesh {
		AABBoxf box;
		void resetToMesh(const Mesh& mesh) {}
		const RenderMesh* selectLOD(double distance) const { return this; }
		void setLOD(double distance, const RenderMesh* mesh) {}
		const AABBoxf& getBoundingBox() const { return box; }
		unsigned getMeshBytes() const { return 0; }
		const Mesh& getMesh() const { return emptyMesh; }

		void render() const {};
	};

	struct {
		render::Texture* texture;
		render::RenderState material;
		render::MaterialGroup group;
		render::RenderMesh* mesh;
		scene::ParticleSystemDesc* particleSystem;
		render::SpriteSheet spriteSheet;
		ErrorShader shader;
		gui::skin::Skin skin;
	} errors;
public:
	struct ResourceAccessor;

	umap<std::string, Sound*> sounds;
	umap<std::string, render::RenderState*> materials;
	umap<std::string, render::MaterialGroup*> matGroups;
	umap<std::string, render::RenderMesh*> meshes;
	umap<std::string, render::Shader*> shaders;
	umap<std::string, render::ShaderProgram*> programs;
	std::vector<render::Shader*> settingsShaders;
	umap<std::string, render::Font*> fonts;
	std::vector<render::Font*> font_list;
	umap<std::string, gui::skin::Skin*> skins;
	umap<std::string, scene::ParticleSystemDesc*> particleSystems;
	umap<std::string, render::SpriteSheet*> spritesheets;
	std::vector<render::Texture*> textures;
	umap<std::string, render::Texture*> texture_files;
	umap<std::string, gui::skin::Skin*> skin_files;

	std::vector<std::string> material_names;
	std::vector<std::string> spritesheet_names;

	umap<const render::RenderState*, unsigned> mat_indices;
	umap<const render::SpriteSheet*, unsigned> sheet_indices;

	ResourceAccessor operator[](const char* name) const;
	
	//Returns the specified material, or an error material if the material is not loaded
	const render::RenderState& getMaterial(const std::string& name) const;
	
	//Returns the specified material group, or an error material group if the material group is not loaded
	const render::MaterialGroup& getMaterialGroup(const std::string& name) const;

	//Returns the specified spritesheet, or an error spritesheet if it is not loaded
	const render::SpriteSheet& getSpriteSheet(const std::string& name) const;
	
	//Returns the specified mesh, or an error mesh if the mesh is not loaded
	const render::RenderMesh& getMesh(const std::string& name) const;

	//Returns the specified skin, or an error skin if the skin is not loaded
	const gui::skin::Skin& getSkin(const std::string& name) const;

	//Returns the specified font, or an error font if the font is not loaded
	const render::Font& getFont(const std::string& name) const;

	//Returns the specified particle system, or an error particle system if the system is not loaded
	const scene::ParticleSystemDesc* getParticleSystem(const std::string& name) const;

	//Returns the specified texture, or an error shader (possibly 0) if the shader is not loaded
	const render::Shader* getShader(const std::string& name) const;

	//Returns the specified sound, or an error sound (possibly 0) if the sound is missing
	const Sound* getSound(const std::string& name) const;

	//Returns a reference to a particular sprite from a description
	render::Sprite getSprite(const std::string& desc);

	//Returns the descriptor string for a particular sprite
	std::string getSpriteDesc(const render::Sprite& sprt) const;

	//Creates fallback resources for when a resource is missing
	void prepErrorResources();
	void generateErrorResources();

	const render::RenderState& getErrorMaterial() const;
	const render::SpriteSheet& getErrorSpriteSheet() const;
	const render::Texture* getErrorTexture() const;

	//Clears all resources held by the library
	void clear();

	void load(ResourceType type, const std::string& filename);
	void loadDirectory(ResourceType type, const std::string& filename);

	void bindHotloading();
	void watchTexture(const std::string& filename);
	void watchShader(const std::string& shadername, const std::string& filename);
	void watchSkin(const std::string& skinname);

	//Bind materials to skins
	void bindSkinMaterials();
	//Bind fonts to skins
	void bindSkinFonts();
	//Compile all loaded shaders
	void compileShaders();
	//Clear shader global variables
	void clearShaderGlobals();
	//Iterate over all shader globals
	void iterateShaderGlobals(std::function<void(std::string&,ShaderGlobal*)> func);
	//Compiles any watched resources that need reloaded
	void reloadWatchedResources();
	//Clears list of watched resources (called by clear)
	void clearWatchedResources();

	//Load queued sounds
	bool hasQueuedSounds();
	bool processSounds(int maxPriority = INT_MIN, int amount = INT_MAX);

	//Load queued images in the background
	bool hasQueuedImages();
	bool processImages(int maxPriority = INT_MIN, int amount = INT_MAX);

	//Load queued textures - must be called from the thread that handles the driver
	bool hasQueuedTextures();
	bool processTextures(int maxPriority = INT_MIN, bool singleFrame = false);

	//Load queued meshes - must be called from the thread that handles the driver
	bool hasQueuedMeshes();
	bool processMeshes(int maxPriority = INT_MIN, int amount = INT_MAX);

	struct ResourceAccessor {
		const Library* source;
		const char* name;
		
		operator const Sound*();
		operator const render::RenderState*();
		operator const render::RenderMesh*();
		operator const render::Shader*();
		operator const render::Font*();
		operator const render::SpriteSheet*();
		operator const gui::skin::Skin*();
		
		operator const Sound&();
		operator const render::RenderState&();
		operator const render::RenderMesh&();
		operator const render::Shader&();
		operator const render::Font&();
		operator const render::SpriteSheet&();
		operator const gui::skin::Skin&();
	};
};

};
