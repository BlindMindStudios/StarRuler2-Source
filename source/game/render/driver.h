#pragma once
#include "scene/node.h"
#include "render/render_state.h"
#include "render/render_mesh.h"
#include "render/texture.h"
#include "matrix.h"
#include "mesh.h"
#include "rect.h"
#include "image.h"
#include "color.h"
#include "vec2.h"
#include "line3d.h"

struct frustum;

namespace scene {
	class Node;
};

namespace render {

	enum PrimitiveType {
		PT_Lines,
		PT_LineStrip,
		PT_Triangles,
		PT_Quads,
	};

	class Camera;

class RenderDriver {
public:
	RenderState activeRenderState;
	scene::Node rootNode;
	vec3d cam_pos, cam_facing, cam_up;

	virtual bool init() = 0;
	virtual void reportErrors(const char* context = nullptr) const = 0;

	virtual const RenderState* getLastRenderState() const = 0;

	virtual void setSkybox(const RenderState* mat) = 0;
	virtual void setSkyboxMesh(const RenderMesh* mesh) = 0;
	virtual void setScreenSize(int w, int h) = 0;
	virtual void setFOV(double fov) = 0;
	virtual void setNearFarPlanes(double near, double far) = 0;

	virtual const frustum& getViewFrustum() const = 0;
	virtual void setCameraData(Camera& camera) = 0;

	virtual void setDefaultRenderState() = 0;
	virtual void set2DRenderState() = 0;
	virtual void switchToRenderState(const RenderState&) = 0;
	
	virtual void setTransformation(const Matrix&) = 0;
	virtual void setTransformationAbs(const Matrix&) = 0;
	virtual void setTransformationIdentity() = 0;
	virtual void setBBTransform(vec3d pos, double width, double rot) = 0;
	virtual void resetTransformation() = 0;
	
	virtual void getInverseView(float* mat3) const = 0;

	virtual void getBillboardVecs(vec3d& upLeft, vec3d& upRight, double rotation = 0) const = 0;
	virtual void getBillboardVecs(const vec3d& from, vec3d& upLeft, vec3d& upRight, double rotation = 0) const = 0;

	virtual void clearRenderPrepared() = 0;
	virtual bool isRenderPrepared() = 0;
	virtual void prepareRender3D(Camera& camera, const recti* clip = 0) = 0;
	virtual void prepareRender2D() = 0;
	virtual void renderWorld() = 0;

	virtual RenderMesh* createMesh(const Mesh& mesh) = 0;
	virtual Shader* createShader() = 0;
	virtual ShaderProgram* createShaderProgram(const char* vertex_shader, const char* fragment_shader) = 0;
	virtual Texture* createTexture(Image& image, bool mipmap = true, bool cachePixels = false) = 0;
	static Texture* createTexture();
	static Texture* createCubemap();

	virtual Texture* createRenderTarget(const vec2i& size) = 0;
	virtual void setRenderTarget(Texture* texture, bool intermediate = false) = 0;

	virtual Image* getScreen(int x, int y, int w, int h) = 0;

	virtual void drawFPSGraph(const recti& location) = 0;

	virtual void drawBillboard(vec3d center, double width) = 0;

	virtual void drawLine(line3dd line, Color start, Color end) = 0;

	virtual void drawQuad(
		const RenderState* mat,
		const vec2<float>* vertices,
		const vec2<float>* textureCoords = 0,
		const Color* color = 0
	) = 0;

	virtual void drawQuad(
		const vec2<float>* vertices,
		const vec2<float>* textureCoords,
		const Color* colors
	) = 0;

	virtual void drawQuad(
		const vec3d* vertices,
		const vec2<float>* textureCoords,
		const Color* colors
	) = 0;
	
	virtual void drawRectangle(
		const recti& rectangle,
		const RenderState* mat,
		Color color,
		const recti* clip = 0
	) = 0;

	virtual void drawRectangle(
		recti rectangle,
		const RenderState* mat = 0,
		const recti* sourceRect = 0,
		const Color* color = 0,
		const recti* clip = 0
	) = 0;

	virtual void drawRectangle(
		recti rectangle,
		const RenderState* mat,
		const recti* sourceRect,
		const Color* color,
		const recti* clip,
		double rotation
	) = 0;

	virtual void drawBillboard(
		vec3d center,
		double width,
		const RenderState& mat,
		double rotation,
		Color* color = 0
	) = 0;

	virtual void drawBillboard(
		vec3d center,
		double width,
		const RenderState& mat,
		const recti& source,
		Color* color = 0
	) = 0;

	virtual void drawBillboard(
		vec3d center,
		double width,
		const RenderState& mat,
		const recti& source,
		double rotation,
		Color color = Color()
	) = 0;

	virtual void pushScreenClip(const recti& box) = 0;
	virtual void popScreenClip() = 0;

	virtual ~RenderDriver() {}
};

};
