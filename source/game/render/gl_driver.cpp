#include "compat/misc.h"
#include "compat/gl.h"
#include "render/driver.h"
#include "render/gl_driver.h"
#include "render/gl_mesh.h"
#include "render/gl_shader.h"
#include "render/gl_texture.h"
#include "render/lighting.h"
#include "render/camera.h"
#include "render/gl_framebuffer.h"
#include "render/vertexBuffer.h"
#include "util/mesh_generation.h"
#include "main/references.h"
#include "main/tick.h"
#include "main/logging.h"
#include "matrix.h"
#include "frustum.h"
#include <algorithm>
extern char lockText[1024];

bool glDirectStateAccess = false;

namespace render {
unsigned drawCalls = 0;

extern const RenderMesh* lastRenderedMesh;
float* shaderUniforms = 0;

bool alphaTest = false, blend = false;

static inline void setRenderFuncs(BaseMaterial mat, bool intermediate) {
	switch(mat) {
		case MAT_Solid:
			if(alphaTest) {
				glDisable(GL_ALPHA_TEST);
				alphaTest = false;
			}
			if(blend) {
				glDisable(GL_BLEND);
				blend = false;
			}
		break;
		case MAT_Add:
			if(alphaTest) {
				glDisable(GL_ALPHA_TEST);
				alphaTest = false;
			}
			if(!blend) {
				glEnable(GL_BLEND);
				blend = true;
			}
			glBlendFuncSeparate(
				GL_ONE, GL_ONE,
				GL_ONE, GL_ZERO);
			break;
		case MAT_Alpha:
		case MAT_Font:
			if(!alphaTest) {
				glEnable(GL_ALPHA_TEST);
				alphaTest = true;
			}
			if(!blend) {
				glEnable(GL_BLEND);
				blend = true;
			}
			if(intermediate) {
				glBlendFuncSeparate(
					GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
					GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
			}
			else {
				glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			}
		break;
		case MAT_Overlay:
			if(!alphaTest) {
				glEnable(GL_ALPHA_TEST);
				alphaTest = true;
			}
			if(!blend) {
				glEnable(GL_BLEND);
				blend = true;
			}
			glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		break;
	}
}

Texture* RenderDriver::createTexture() {
	return new GLTexture();
}

Texture* RenderDriver::createCubemap() {
	return new GLCubeMap();
}

bool isIntelCard = false;
class GLDriver : public RenderDriver {
public:
	const RenderState* pLastRenderState;
	unsigned textureStage;
	unsigned char activeType[RENDER_MAX_TEXTURES];
	const RenderState* skybox;
	const RenderMesh* skyboxMesh;
	bool cleared;
	bool intermediateBlend;
	vec2i screenSize, frameSize;
	double fov;
	double zNear, zFar;

	std::stack<recti> viewportClips;

	frustum viewFrustum;
	vec3d cam_right,
		bb_up_p_right, bb_up_m_right;
	quaterniond BBFacingRot;

	Colorf diffuse, specular;
	float shininess;

	RenderState state_3d;
	RenderState state_2d;

	float invView[9];

	vec3f lightPosition[2];
	vec2f screenLight[2];
	double lightRadius[2];
	bool lightActive[2];
	bool isPrepared;

	GLDriver() : textureStage(GL_TEXTURE0), pLastRenderState(0), skybox(0), skyboxMesh(0),
		cleared(false), intermediateBlend(false), fov(50.0), zNear(1.0), zFar(240000.0)
	{
		state_2d.lighting = false;
		state_2d.depthTest = DT_NoDepthTest;
		state_2d.baseMat = MAT_Alpha;
		state_2d.culling = FC_None;
	}

	~GLDriver() {
	}
	
	const RenderState* getLastRenderState() const override {
		return pLastRenderState ? pLastRenderState : &activeRenderState;
	}

	void reportErrors(const char* context = nullptr) const override {
		GLenum err = glGetError();
		while(err != GL_NO_ERROR) {
			error("Error %s: %d (0x%04x)", context ? context : "in OpenGL", err, err);
			err = glGetError();
		}
	}

	const frustum& getViewFrustum() const {
		return viewFrustum;
	}

	void getInverseView(float* mat3) const override {
		memcpy(mat3, invView, 9 * sizeof(float));
	}

	void setCameraData(Camera& camera) {
		cam_pos = camera.getPosition();
		cam_facing = camera.getFacing();
		cam_up = camera.getUp();
		cam_right = camera.getRight();
		
		bb_up_p_right = cam_up - cam_right;
		bb_up_m_right = cam_up + cam_right;

		auto rot = camera.getRotation();
		Matrix mat = rot.toMatrix();
		
		vec3d f = cam_facing;
		vec3d s = f.cross(cam_up);
		vec3d u = s.cross(f);

		//s0 s1 s2 0
		//u0 u1 u2 0
		//-f0 -f1 -f2 0
		//0 0 0 1

		invView[0] = s.x;
		invView[1] = u.x;
		invView[2] = -f.x;
		invView[3] = s.y;
		invView[4] = u.y;
		invView[5] = -f.y;
		invView[6] = s.z;
		invView[7] = u.z;
		invView[8] = -f.z;

		auto yaw = quaterniond::fromAxisAngle(vec3d::up(-1.0), atan2(cam_facing.z, cam_facing.x));
		auto pitch = quaterniond::fromAxisAngle(vec3d::right(), asin(-cam_facing.y));

		BBFacingRot = yaw * pitch;

		viewFrustum = frustum(camera.screenToRay(0,0), camera.screenToRay(1,0), camera.screenToRay(0,1), camera.screenToRay(1,1));
	}

	void setTextureStage(unsigned stage) {
		if(stage != textureStage) {
			glActiveTexture(stage);
			textureStage = stage;
		}
	}

	void setTransformation(const Matrix& matrix) override {
		glPushMatrix();
		Matrix temp(matrix);
		temp[12] -= cam_pos.x;
		temp[13] -= cam_pos.y;
		temp[14] -= cam_pos.z;
		glMultMatrixd(temp.m);
	}

	void setTransformationAbs(const Matrix& matrix) override {
		glPushMatrix();
		glMultMatrixd(matrix.m);
	}
	
	void setTransformationIdentity() override {
		glPushMatrix();
		glLoadIdentity();
	}

	void setBBTransform(vec3d pos, double width, double rot) override {
		glPushMatrix();
		Matrix m;
		//BBFacingRot.toTransform(m, pos - cam_pos, vec3d(width * 0.5));
		(quaterniond::fromAxisAngle(cam_facing, -rot) * BBFacingRot).toTransform(m, pos - cam_pos, vec3d(width * 0.5));
		glMultMatrixd(m.m);
	}

	void resetTransformation() override {
		glPopMatrix();
	}

	void setDefaultRenderState() {
		activeRenderState = RenderState();
		pLastRenderState = 0;

		lastRenderedMesh = 0;

		glEnable(GL_CULL_FACE);
		glCullFace(GL_BACK);

		glDepthMask(GL_TRUE);
		glEnable(GL_DEPTH_TEST);
		glDepthFunc(GL_LESS);

		glAlphaFunc(GL_GREATER, 1.f/255.f);
		setRenderFuncs(MAT_Solid, false);

		glEnable(GL_LIGHTING);

		glDisable(GL_NORMALIZE);
		
		glUseProgram(0);

		for(int i = 0; i < RENDER_MAX_TEXTURES; ++i) {
			glActiveTexture(GL_TEXTURE0 + i);
			glDisable(GL_TEXTURE_2D);
			glDisable(GL_TEXTURE_CUBE_MAP);
		}

		glActiveTexture(GL_TEXTURE0);
		textureStage = GL_TEXTURE0;

		diffuse = Colorf(1.f, 1.f, 1.f, 1.f);
		specular = Colorf(1.f, 1.f, 1.f, 1.f);
		shininess = 8.f;
		glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, (const GLfloat*)&diffuse);
		glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, (const GLfloat*)&specular);
		glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, shininess);
	}

	void set2DRenderState() {
		switchToRenderState(state_2d);
	}

	void switchToRenderState(const RenderState& state) {
		if(state.constant && pLastRenderState == &state) {
			if(state.shader && !state.shader->constant) {
				if(shaderUniforms)
					state.shader->loadDynamicVars(shaderUniforms);
				else
					state.shader->updateDynamicVars();
			}
			return;
		}

		//Front/Back face culling
		if(state.culling != activeRenderState.culling) {
			if(state.culling == FC_None) {
				glDisable(GL_CULL_FACE);
			}
			else {
				if(activeRenderState.culling == FC_None)
					glEnable(GL_CULL_FACE);

				switch(state.culling) {
					case FC_Front:
						glCullFace(GL_FRONT); break;
					case FC_Back:
						glCullFace(GL_BACK); break;
					case FC_Both:
						glCullFace(GL_FRONT_AND_BACK); break;
					NO_DEFAULT
				}
			}
		}

		//Depth write
		if(state.depthWrite != activeRenderState.depthWrite)
			glDepthMask(state.depthWrite ? GL_TRUE : GL_FALSE);

		//Depth test
		if(state.depthTest != activeRenderState.depthTest) {
			if(state.depthTest == DT_NoDepthTest)
				glDisable(GL_DEPTH_TEST);
			else {
				if(activeRenderState.depthTest == DT_NoDepthTest)
					glEnable(GL_DEPTH_TEST);

				switch(state.depthTest) {
					case DT_Never:
						glDepthFunc(GL_NEVER); break;
					case DT_Less:
						glDepthFunc(GL_LESS); break;
					case DT_Equal:
						glDepthFunc(GL_EQUAL); break;
					case DT_LessEqual:
						glDepthFunc(GL_LEQUAL); break;
					case DT_Greater:
						glDepthFunc(GL_GREATER); break;
					case DT_NotEqual:
						glDepthFunc(GL_NOTEQUAL); break;
					case DT_GreaterEqual:
						glDepthFunc(GL_GEQUAL); break;
					//case DT_Always:
					//	glDepthFunc(GL_ALWAYS); break;
					NO_DEFAULT
				}
			}
		}

		//Texture states
		for(int i = 0; i < RENDER_MAX_TEXTURES; ++i) {
			if(activeRenderState.textures[i] == state.textures[i])
				continue;
			Texture* tex = state.textures[i];

			if(glDirectStateAccess) {
				if(tex == 0) {
					if(activeType[i] == TT_2D)
						glDisablei(GL_TEXTURE_2D, i);
					else
						glDisablei(GL_TEXTURE_CUBE_MAP, i);
				}
				else {
					auto type = tex->type;
					GLenum glType;
					if(type == TT_2D)
						glType = GL_TEXTURE_2D;
					else
						glType = GL_TEXTURE_CUBE_MAP;

					if(activeRenderState.textures[i] == 0) {
						glEnablei(glType, i);
						activeType[i] = type;
					}
					else if(activeType[i] != type) {
						if(type == TT_2D)
							glDisablei(GL_TEXTURE_CUBE_MAP, i);
						else
							glDisablei(GL_TEXTURE_2D, i);
						glEnablei(glType, i);
						activeType[i] = type;
					}
				
					auto texunit = GL_TEXTURE0 + i;
					glBindMultiTextureEXT(texunit, glType, tex->getID());

					//Wrapping settings
					bool changed = false;
					if(state.wrapHorizontal != tex->prevRenderState.wrapHorizontal) {
						GLint mode;
						switch(state.wrapHorizontal) {
						case TW_Repeat:
							mode = GL_REPEAT; break;
						case TW_Clamp:
							mode = GL_CLAMP; break;
						case TW_ClampEdge:
							mode = GL_CLAMP_TO_EDGE; break;
						case TW_Mirror:
							mode = GL_MIRRORED_REPEAT; break;
						NO_DEFAULT
						}
						glMultiTexParameteriEXT(texunit, glType, GL_TEXTURE_WRAP_S, mode);
						changed = true;
					}

					if(state.wrapVertical != tex->prevRenderState.wrapVertical) {
						GLint mode;
						switch(state.wrapVertical) {
						case TW_Repeat:
							mode = GL_REPEAT; break;
						case TW_Clamp:
							mode = GL_CLAMP; break;
						case TW_ClampEdge:
							mode = GL_CLAMP_TO_EDGE; break;
						case TW_Mirror:
							mode = GL_MIRRORED_REPEAT; break;
						NO_DEFAULT
						}
						glMultiTexParameteriEXT(texunit, glType, GL_TEXTURE_WRAP_T, mode);
						changed = true;
					}

					//Mipmap settings
					if(state.filterMin != tex->prevRenderState.filterMin) {
						GLint mode;
						switch(state.filterMin) {
						case TF_Nearest:
							mode = tex->hasMipMaps ? GL_NEAREST_MIPMAP_NEAREST : GL_NEAREST; break;
						case TF_Linear:
							mode = tex->hasMipMaps ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR; break;
						NO_DEFAULT
						}
						glMultiTexParameteriEXT(texunit, glType, GL_TEXTURE_MIN_FILTER, mode);
						changed = true;
					}

					if(state.filterMag != tex->prevRenderState.filterMag) {
						GLint mode;
						switch(state.filterMag) {
						case TF_Nearest:
							mode = tex->hasMipMaps ? GL_NEAREST_MIPMAP_NEAREST : GL_NEAREST; break;
						case TF_Linear:
							mode = tex->hasMipMaps ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR; break;
						NO_DEFAULT
						}
						glMultiTexParameteriEXT(texunit, glType, GL_TEXTURE_MAG_FILTER, mode);
						changed = true;
					}

					//Update the previous render state
					if(changed)
						tex->prevRenderState = state;
				}
			}
			else {
				setTextureStage(GL_TEXTURE0 + i);

				if(tex == 0) {
					if(activeType[i] == TT_2D)
						glDisable(GL_TEXTURE_2D);
					else
						glDisable(GL_TEXTURE_CUBE_MAP);
				}
				else {
					auto type = tex->type;
					GLenum glType;
					if(type == TT_2D)
						glType = GL_TEXTURE_2D;
					else
						glType = GL_TEXTURE_CUBE_MAP;

					if(activeRenderState.textures[i] == 0) {
						glEnable(glType);
						activeType[i] = type;
					}
					else if(activeType[i] != type) {
						if(type == TT_2D)
							glDisable(GL_TEXTURE_CUBE_MAP);
						else
							glDisable(GL_TEXTURE_2D);
						glEnable(glType);
						activeType[i] = type;
					}

					//Bind the texture
					tex->bind();

					//Wrapping settings
					bool changed = false;
					if(state.wrapHorizontal != tex->prevRenderState.wrapHorizontal) {
						GLint mode;
						switch(state.wrapHorizontal) {
						case TW_Repeat:
							mode = GL_REPEAT; break;
						case TW_Clamp:
							mode = GL_CLAMP; break;
						case TW_ClampEdge:
							mode = GL_CLAMP_TO_EDGE; break;
						case TW_Mirror:
							mode = GL_MIRRORED_REPEAT; break;
						NO_DEFAULT
						}
						glTexParameteri(glType, GL_TEXTURE_WRAP_S, mode);
						changed = true;
					}

					if(state.wrapVertical != tex->prevRenderState.wrapVertical) {
						GLint mode;
						switch(state.wrapVertical) {
						case TW_Repeat:
							mode = GL_REPEAT; break;
						case TW_Clamp:
							mode = GL_CLAMP; break;
						case TW_ClampEdge:
							mode = GL_CLAMP_TO_EDGE; break;
						case TW_Mirror:
							mode = GL_MIRRORED_REPEAT; break;
						NO_DEFAULT
						}
						glTexParameteri(glType, GL_TEXTURE_WRAP_T, mode);
						changed = true;
					}

					//Mipmap settings
					if(state.filterMin != tex->prevRenderState.filterMin) {
						GLint mode;
						switch(state.filterMin) {
						case TF_Nearest:
							mode = tex->hasMipMaps ? GL_NEAREST_MIPMAP_NEAREST : GL_NEAREST; break;
						case TF_Linear:
							mode = tex->hasMipMaps ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR; break;
						NO_DEFAULT
						}
						glTexParameteri(glType, GL_TEXTURE_MIN_FILTER, mode);
						changed = true;
					}

					if(state.filterMag != tex->prevRenderState.filterMag) {
						GLint mode;
						switch(state.filterMag) {
						case TF_Nearest:
							mode = tex->hasMipMaps ? GL_NEAREST_MIPMAP_NEAREST : GL_NEAREST; break;
						case TF_Linear:
							mode = tex->hasMipMaps ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR; break;
						NO_DEFAULT
						}
						glTexParameteri(glType, GL_TEXTURE_MAG_FILTER, mode);
						changed = true;
					}

					//Update the previous render state
					if(changed)
						tex->prevRenderState = state;
				}
			}
		}

		if(state.normalizeNormals != activeRenderState.normalizeNormals) {
			if(state.normalizeNormals)
				glEnable(GL_RESCALE_NORMAL);
			else
				glDisable(GL_RESCALE_NORMAL);
		}

		if(state.drawMode != activeRenderState.drawMode) {
			switch(state.drawMode) {
				case DM_Line:
					glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
				break;
				case DM_Fill:
					glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
				break;
			}
		}

		if(state.baseMat != activeRenderState.baseMat) {
			setRenderFuncs(state.baseMat, intermediateBlend);
		}

		if(!state.shader && (state.lighting != activeRenderState.lighting || activeRenderState.shader)) {
			if(state.lighting)
				glEnable(GL_LIGHTING);
			else
				glDisable(GL_LIGHTING);
		}

		if(state.lighting) {
			//Lighting model material settings
			if(state.diffuse != diffuse) {
				diffuse = state.diffuse;
				glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, (GLfloat*)&state.diffuse);
			}

			if(state.specular != specular) {
				specular = state.specular;
				glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, (GLfloat*)&state.specular);
			}

			if(state.shininess != shininess) {
				shininess = state.shininess;
				glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, state.shininess);
			}
		}

		//Shader and shader variables
		if(state.shader == 0 && activeRenderState.shader != 0)
			glUseProgram(0);

		activeRenderState = state;
		pLastRenderState = &state;
		
		//The shader bind can inspect the current material
		if(state.shader)
			state.shader->bind(shaderUniforms);
	}

	void getBillboardVecs(vec3d& upLeft, vec3d& upRight, double rotation) const {
		if(rotation == 0) {
			upLeft = bb_up_m_right;
			upRight = bb_up_p_right;
		}
		else {
			double st = sin(rotation), ct = cos(rotation);
			upLeft = (bb_up_m_right * ct) - (bb_up_p_right * st);
			upRight = (bb_up_p_right * ct) + (bb_up_m_right * st);
		}
	}

	void getBillboardVecs(const vec3d& from, vec3d& upLeft, vec3d& upRight, double rotation) const {
		vec3d toward = (from - cam_pos).normalize();
		vec3d right = cam_up.cross(toward).normalize();
		vec3d up = toward.cross(right);

		vec3d ul = up - right;
		vec3d ur = up + right;

		if(rotation == 0) {
			upLeft = ul;
			upRight = ur;
		}
		else {
			double st = sin(rotation), ct = cos(rotation);
			upLeft = (ul * ct) - (ur * st);
			upRight = (ur * ct) + (ul * st);
		}
	}

	void drawBillboard(vec3d center, double width) {
		center -= cam_pos;
		width *= 0.5;
		
		vec3d UpMinRight, UpPlusRight;
		getBillboardVecs(UpMinRight, UpPlusRight, 0);
		UpMinRight *= width;
		UpPlusRight *= width;

		auto& mat = *pLastRenderState;
		auto* buffer = VertexBufferTCV::fetch(&mat);
		auto* verts = buffer->request(1, PT_Quads);

		Color col = Color();
		
		verts[0].set(vec3f(center + UpMinRight), vec2f(0,0), col);
		verts[1].set(vec3f(center + UpPlusRight), vec2f(1,0), col);
		verts[2].set(vec3f(center - UpMinRight), vec2f(1,1), col);
		verts[3].set(vec3f(center - UpPlusRight), vec2f(0,1), col);
	}

	void drawBillboard(vec3d center, double width, const RenderState& mat, double rotation, Color* color) {
		center -= cam_pos;
		width *= 0.5;

		vec3d UpMinRight, UpPlusRight;
		getBillboardVecs(UpMinRight, UpPlusRight, rotation);
		UpMinRight *= width;
		UpPlusRight *= width;

		auto* buffer = VertexBufferTCV::fetch(&mat);
		auto* verts = buffer->request(1, PT_Quads);

		Color col = color ? *color : Color();
		
		verts[0].set(vec3f(center + UpMinRight), vec2f(0,0), col);
		verts[1].set(vec3f(center + UpPlusRight), vec2f(1,0), col);
		verts[2].set(vec3f(center - UpMinRight), vec2f(1,1), col);
		verts[3].set(vec3f(center - UpPlusRight), vec2f(0,1), col);
	}

	void drawBillboard( vec3d center, double width, const RenderState& mat, const recti& source, Color* color) {
		rectf texCoords;
		Texture* tex = mat.textures[0];
		if(tex) {
			texCoords.topLeft.x = (float)source.topLeft.x / tex->size.width;
			texCoords.topLeft.y = (float)source.topLeft.y / tex->size.height;
			texCoords.botRight.x = (float)source.botRight.x / tex->size.width;
			texCoords.botRight.y = (float)source.botRight.y / tex->size.height;
		}

		center -= cam_pos;
		width *= 0.5;

		auto UpMinRight = bb_up_m_right * width, UpPlusRight = bb_up_p_right * width;

		Color col = color ? *color : Color();

		auto* buffer = VertexBufferTCV::fetch(&mat);
		auto* verts = buffer->request(1, PT_Quads);
		
		verts[0].set(vec3f(center + UpMinRight), texCoords.topLeft, col);
		verts[1].set(vec3f(center + UpPlusRight), texCoords.getTopRight(), col);
		verts[2].set(vec3f(center - UpMinRight), texCoords.botRight, col);
		verts[3].set(vec3f(center - UpPlusRight), texCoords.getBotLeft(), col);
	}

	void drawBillboard( vec3d center, double width, const RenderState& mat, const recti& source, double rotation, Color color) override {
		rectf texCoords;
		Texture* tex = mat.textures[0];
		if(tex) {
			texCoords.topLeft.x = (float)source.topLeft.x / tex->size.width;
			texCoords.topLeft.y = (float)source.topLeft.y / tex->size.height;
			texCoords.botRight.x = (float)source.botRight.x / tex->size.width;
			texCoords.botRight.y = (float)source.botRight.y / tex->size.height;
		}

		center -= cam_pos;
		width *= 0.5;

		vec3d UpMinRight, UpPlusRight;
		getBillboardVecs(UpMinRight, UpPlusRight, rotation);
		UpMinRight *= width;
		UpPlusRight *= width;

		auto* buffer = VertexBufferTCV::fetch(&mat);
		auto* verts = buffer->request(1, PT_Quads);
		
		verts[0].set(vec3f(center + UpMinRight), texCoords.topLeft, color);
		verts[1].set(vec3f(center + UpPlusRight), texCoords.getTopRight(), color);
		verts[2].set(vec3f(center - UpMinRight), texCoords.botRight, color);
		verts[3].set(vec3f(center - UpPlusRight), texCoords.getBotLeft(), color);

		if(!mat.constant)
			buffer->draw();
	}

	void drawLine(line3dd line, Color start, Color end) {
		auto* buffer = VertexBufferTCV::fetch(pLastRenderState);
		auto* verts = buffer->request(1, PT_Lines);
		
		verts[0].set(vec3f(line.start - cam_pos), vec2f(), start);
		verts[1].set(vec3f(line.end - cam_pos), vec2f(1,0), start);

		if(!pLastRenderState->constant)
			buffer->draw();
	}

	virtual void drawQuad(
		const RenderState* mat,
		const vec2<float>* vertices,
		const vec2<float>* textureCoords,
		const Color* color = 0)
	{
		auto* buffer = VertexBufferTCV::fetch(mat);
		auto* verts = buffer->request(1, PT_Quads);

		Color col = color ? *color : Color();

		for(unsigned i = 0; i < 4; ++i) {
			auto& v = verts[i];
			v.uv = textureCoords[i];
			v.col = col;
			v.pos = vec3f(vertices[i].x, vertices[i].y, 0);
		}

		if(!mat->constant)
			buffer->draw();
	}

	void drawQuad(const vec3d* vertices,
				  const vec2<float>* textureCoords,
				  const Color* colors)
	{
		auto* buffer = VertexBufferTCV::fetch(pLastRenderState);
		auto* verts = buffer->request(1, PT_Quads);

		for(unsigned i = 0; i < 4; ++i) {
			auto& v = verts[i];
			v.uv = textureCoords[i];
			v.col = colors[i];
			v.pos = vec3f(vertices[i] - cam_pos);
		}

		if(!pLastRenderState->constant)
			buffer->draw();
	}

	void drawQuad(const vec2<float>* vertices,
				  const vec2<float>* textureCoords,
				  const Color* colors)
	{
		auto* buffer = VertexBufferTCV::fetch(pLastRenderState);
		auto* verts = buffer->request(1, PT_Quads);

		for(unsigned i = 0; i < 4; ++i) {
			auto& v = verts[i];
			v.uv = textureCoords[i];
			v.col = colors ? colors[i] : Color();
			v.pos = vec3f(vertices[i].x, vertices[i].y, 0);
		}

		if(!pLastRenderState->constant)
			buffer->draw();
	}

	void drawRectangle(const recti& rect, const Color& color) {
		auto* buffer = VertexBufferTCV::fetch(&state_2d);
		auto* verts = buffer->request(1, PT_Quads);

		auto& tl = verts[0];
		tl.uv.set(0,0);
		tl.col = color;
		tl.pos = vec3f(vec3i(rect.topLeft.x, rect.topLeft.y, 0));
			
		auto& tr = verts[1];
		tr.uv.set(0,0);
		tr.col = color;
		tr.pos = vec3f(vec3i(rect.botRight.x, rect.topLeft.y, 0));
			
		auto& br = verts[2];
		br.uv.set(0,0);
		br.col = color;
		br.pos = vec3f(vec3i(rect.botRight.x, rect.botRight.y, 0));
			
		auto& bl = verts[3];
		bl.uv.set(0,0);
		bl.col = color;
		bl.pos = vec3f(vec3i(rect.topLeft.x, rect.botRight.y, 0));
	}
	
	void drawRectangle(const recti& rectangle, const RenderState* mat, Color color, const recti* clip = 0) {
		if(clip && !clip->overlaps(rectangle))
			return;

		if(!mat)
			mat = &state_2d;

		recti rect = rectangle;
		rectf uv(0,0,1,1);

		if(clip && !clip->isRectInside(rect)) {
			rect = clip->clipAgainst(rect);
			uv.topLeft.x =  (float)(rect.topLeft.x - rectangle.topLeft.x) / (float)rectangle.getWidth();
			uv.topLeft.y =  (float)(rect.topLeft.y - rectangle.topLeft.y) / (float)rectangle.getHeight();
			uv.botRight.x = 1.f - (float)(rectangle.botRight.x - rect.botRight.x) / (float)rectangle.getWidth();
			uv.botRight.y = 1.f - (float)(rectangle.botRight.y - rect.botRight.y) / (float)rectangle.getHeight();
		}

		auto* buffer = VertexBufferTCV::fetch(mat);
		auto* verts = buffer->request(1, PT_Quads);

		auto& tl = verts[0];
		tl.uv = uv.topLeft;
		tl.col = color;
		tl.pos = vec3f(vec3i(rect.topLeft.x, rect.topLeft.y, 0));
			
		auto& tr = verts[1];
		tr.uv.set(uv.botRight.x,uv.topLeft.y);
		tr.col = color;
		tr.pos = vec3f(vec3i(rect.botRight.x, rect.topLeft.y, 0));
			
		auto& br = verts[2];
		br.uv = uv.botRight;
		br.col = color;
		br.pos = vec3f(vec3i(rect.botRight.x, rect.botRight.y, 0));
			
		auto& bl = verts[3];
		bl.uv.set(uv.topLeft.x,uv.botRight.y);
		bl.col = color;
		bl.pos = vec3f(vec3i(rect.topLeft.x, rect.botRight.y, 0));

		if(!mat->constant)
			buffer->draw();
	}

	void drawRectangle(recti rect, const RenderState* mat, const recti* src,
						const Color* color, const recti* clip) {
		//Store source rect
		recti source;
		if(src)
			source = *src;

		//Clipping
		if(clip) {
			if(!clip->overlaps(rect))
				return;
			if(!clip->isRectInside(rect)) {
				recti clipped = clip->clipAgainst(rect);
				if(src) {
					source = source.clipProportional(rect, clipped);
				}
				else if(mat && mat->textures[0]) {
					source = recti(vec2i(0, 0), mat->textures[0]->size);
					source = source.clipProportional(rect, clipped);
					src = &source;
				}
				rect = clipped;
			}
		}

		if(!mat)
			mat = &state_2d;

		rectf uv(0,0,1.f,1.f);
		if(mat && src && mat->textures[0]) {
			Texture* tex = mat->textures[0];
			uv.topLeft.x = (float)source.topLeft.x / tex->size.width;
			uv.topLeft.y = (float)source.topLeft.y / tex->size.height;
			uv.botRight.x = (float)source.botRight.x / tex->size.width;
			uv.botRight.y = (float)source.botRight.y / tex->size.height;
		}

		auto* buffer = VertexBufferTCV::fetch(mat);
		auto* verts = buffer->request(1, PT_Quads);

		auto& tl = verts[0];
		tl.uv = uv.topLeft;
		tl.col = color ? color[0] : Color();
		tl.pos = vec3f(vec3i(rect.topLeft.x, rect.topLeft.y, 0));
			
		auto& tr = verts[1];
		tr.uv.set(uv.botRight.x,uv.topLeft.y);
		tr.col = color ? color[1] : Color();
		tr.pos = vec3f(vec3i(rect.botRight.x, rect.topLeft.y, 0));
			
		auto& br = verts[2];
		br.uv = uv.botRight;
		br.col = color ? color[2] : Color();
		br.pos = vec3f(vec3i(rect.botRight.x, rect.botRight.y, 0));
			
		auto& bl = verts[3];
		bl.uv.set(uv.topLeft.x,uv.botRight.y);
		bl.col = color ? color[3] : Color();
		bl.pos = vec3f(vec3i(rect.topLeft.x, rect.botRight.y, 0));

		if(!mat->constant)
			buffer->draw();
	}

	void drawRectangle(recti rect, const RenderState* mat, const recti* src,
						const Color* color, const recti* clip, double rotation) {
		if(rotation == 0.0) {
			drawRectangle(rect, mat, src, color, clip);
			return;
		}

		//Store source rect
		recti source;
		if(src)
			source = *src;

		//Clipping
		if(clip) {
			if(!clip->overlaps(rect))
				return;
			if(!clip->isRectInside(rect)) {
				recti clipped = clip->clipAgainst(rect);
				if(src) {
					source = source.clipProportional(rect, clipped);
				}
				else if(mat && mat->textures[0]) {
					source = recti(vec2i(0, 0), mat->textures[0]->size);
					source = source.clipProportional(rect, clipped);
					src = &source;
				}
				rect = clipped;
			}
		}

		//Render the correct material
		if(!mat)
			mat = &state_2d;

		//Compute texture coordinates
		rectf uv(0,0,1.f,1.f);
		if(mat && src && mat->textures[0]) {
			Texture* tex = mat->textures[0];
			uv.topLeft.x = (float)source.topLeft.x / tex->size.width;
			uv.topLeft.y = (float)source.topLeft.y / tex->size.height;
			uv.botRight.x = (float)source.botRight.x / tex->size.width;
			uv.botRight.y = (float)source.botRight.y / tex->size.height;
		}

		//Handle rotations
		rectf frect = rectf(rect);
		vec2f center = vec2f(frect.getCenter());
		rectf preRot = rectf(frect.topLeft - center, frect.botRight - center);
		vec2f pos;

		auto* buffer = VertexBufferTCV::fetch(mat);
		auto* verts = buffer->request(1, PT_Quads);

		auto& tl = verts[0];
		tl.uv = uv.topLeft;
		tl.col = color ? color[0] : Color();

		pos = preRot.topLeft.rotated(rotation) + center;
		tl.pos = vec3f(pos.x, pos.y, 0);
			
		auto& tr = verts[1];
		tr.uv = uv.getTopRight();
		tr.col = color ? color[1] : Color();

		pos = preRot.getTopRight().rotated(rotation) + center;
		tr.pos = vec3f(pos.x, pos.y, 0);
			
		auto& br = verts[2];
		br.uv = uv.botRight;
		br.col = color ? color[3] : Color();

		pos = preRot.botRight.rotated(rotation) + center;
		br.pos = vec3f(pos.x, pos.y, 0);
			
		auto& bl = verts[3];
		bl.uv = uv.getBotLeft();
		bl.col = color ? color[2] : Color();

		pos = preRot.getBotLeft().rotated(rotation) + center;
		bl.pos = vec3f(pos.x, pos.y, 0);

		if(!mat->constant)
			buffer->draw();
	}

	RenderMesh* createMesh(const Mesh& mesh) {
		return createGLMesh(mesh);
	}

	Shader* createShader() {
		return createGLShader();
	}

	ShaderProgram* createShaderProgram(const char* vertex_shader, const char* fragment_shader) {
		return createGLShaderProgram(vertex_shader, fragment_shader);
	}

	Texture* createTexture(Image& image, bool mipmap = true, bool cachePixels = false) {
		return new GLTexture(image, mipmap, cachePixels);
	}

	Texture* createRenderTarget(const vec2i& size) {
		return new glFrameBuffer(size);
	}

	void clear(unsigned flags) {
		//If we need to clear the depth buffer, we need to enable the depth buffer for writing
		if(flags & GL_DEPTH_BUFFER_BIT) {
			if(!activeRenderState.depthWrite) {
				glDepthMask(GL_TRUE);
				activeRenderState.depthWrite = true;
				pLastRenderState = 0;
			}
		}
		glClear(flags);
#ifdef _DEBUG
		reportErrors("Clearing");
#endif
	}

	void setRenderTarget(Texture* texture, bool intermediate = false) {
		renderVertexBuffers();

		glFrameBuffer* frame = dynamic_cast<glFrameBuffer*>(texture);
		if(!frame) {
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
			glViewport(0,0,screenSize.x,screenSize.y);
			frameSize = screenSize;
		}
		else {
			frame->setAsTarget();
			clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			frameSize = frame->size;
		}
		if(intermediate != intermediateBlend)
			setRenderFuncs(activeRenderState.baseMat, intermediate);
		intermediateBlend = intermediate;
	}

	Image* getScreen(int x, int y, int w, int h) {
		Image* img = new Image(w, h, FMT_RGB);

		glReadBuffer(GL_BACK);
		glReadPixels(x, y, w, h, GL_RGB, GL_UNSIGNED_BYTE, img->rgb);

		return img;
	}

	bool init() {
		//Check for sufficient opengl version
		glewInit();

		if(!GLEW_VERSION_2_1) {
			fprintf(stderr, "Error: Requires OpenGL 2.1\n");
			return false;
		}

		//Initialize state
		setDefaultRenderState();

		//Lighting
		float lightCol[4] = {2.5f, 2.5f, 2.5f, 1.f};
		glLightfv(GL_LIGHT0, GL_DIFFUSE, lightCol);
		float lightSpec[4] = {1, 1, 1, 1.f};
		glLightfv(GL_LIGHT0, GL_SPECULAR, lightSpec);
		glLightf(GL_LIGHT0, GL_QUADRATIC_ATTENUATION, 1.f/(500.f*500.f));
		glEnable(GL_LIGHT0);

		float deadCol[4] = {0,0,0,1};
		glLightfv(GL_LIGHT1, GL_DIFFUSE, deadCol);
		glLightfv(GL_LIGHT1, GL_SPECULAR, deadCol);
		glLightf(GL_LIGHT1, GL_QUADRATIC_ATTENUATION, 1.f/(500.f*500.f));
		glEnable(GL_LIGHT1);

		//System defaults
		float globalAmbient[4] = {0.175f, 0.175f, 0.175f, 0.f};
		glLightModelfv(GL_LIGHT_MODEL_AMBIENT, globalAmbient);

		if(GLEW_ARB_seamless_cube_map)
			glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);
		if(GLEW_EXT_direct_state_access)
			glDirectStateAccess = true;

		//Support strange sizes of image
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
		glPixelStorei(GL_PACK_ALIGNMENT, 1);

		//Report vendor
		const char* vendorString = (const char*)glGetString(GL_VENDOR);
		const char* rendererString = (const char*)glGetString(GL_RENDERER);
		const char* versionString = (const char*)glGetString(GL_VERSION);
		isIntelCard = vendorString != nullptr && std::string(vendorString) == "Intel";
		print("OpenGL vendor '%s', renderer '%s'", vendorString, rendererString);
		print("       version '%s'", versionString);
		if(isIntelCard)
			print("-- Using Intel mode. (%d)", GLEW_ARB_texture_storage);

		return true;
	}

	void setScreenSize(int w, int h) {
		screenSize.x = w;
		screenSize.y = h;
		frameSize = screenSize;
	}

	void setFOV(double FOV) {
		fov = FOV;
	}

	void setNearFarPlanes(double near, double far) {
		zNear = near;
		zFar = far;
	}

	void clearRenderPrepared() {
		isPrepared = false;
	}

	bool isRenderPrepared() {
		return isPrepared;
	}

	void prepareRender3D(Camera& camera, const recti* clip) {
		//Cache camera calculations
		setCameraData(camera);
		cleared = true;
		isPrepared = true;

		if(clip)
			pushScreenClip(*clip);

		//Draw 3D
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		double aspect = ((double)screenSize.x)/((double)screenSize.y);
		gluPerspective(fov, aspect, zNear, zFar);
		camera.setRenderConstraints(zNear, zFar, fov, aspect, (double)screenSize.x, (double)screenSize.y);
		glMatrixMode(GL_MODELVIEW);
		{

			vec3d pos, at, lookDir, up;
			camera.toLookAt(pos, at, up);

			lookDir = (at - pos).normalized();

			glLoadIdentity();
			gluLookAt(0,0,0, lookDir.x, lookDir.y, lookDir.z, up.x, up.y, up.z);

			{ //Setup lights in the scene
				vec3f camPosf(float(pos.x),float(pos.y),float(pos.z));
				vec3f lightOffset = camPosf * -1.f;

				glDisable(GL_LIGHT0);
				light::LightSource* sources[2];
				unsigned lightCount = light::findNearestLights(camPosf,sources,2);

				unsigned lightIndex = 0;
				lightActive[0] = false;
				lightActive[1] = false;

				while(lightIndex < lightCount) {
					lightPosition[lightIndex] = sources[lightIndex]->getPosition();
					lightRadius[lightIndex] = sources[lightIndex]->getRadius();

					vec2i onScreen = camera.screenPos(vec3d(lightPosition[lightIndex]));
					screenLight[lightIndex] = vec2f((float)onScreen.x / (float)screenSize.x, 1.f - (float)onScreen.y / (float)screenSize.y);
					lightActive[lightIndex] = true;

					sources[lightIndex]->enable(lightIndex, lightOffset);
				}
			}

			//Render Skybox
			if(skybox) {
				clear(GL_DEPTH_BUFFER_BIT);
				switchToRenderState(*skybox);

				if(skyboxMesh == 0) {
					Mesh* mesh = generateSphereMesh(64,32);
					skyboxMesh = createGLMesh( *mesh );
					delete mesh;
				}
				
				glPushMatrix();
				glScaled((zNear + zFar) * 0.5, (zNear + zFar) * 0.5, (zNear + zFar) * 0.5);
				skyboxMesh->render();
				glPopMatrix();
			}
			else {
				clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			}
		}
	}

	void renderWorld() {
		rootNode._render(*this);
		scene::renderingNode = nullptr;
		renderVertexBuffers();
		popScreenClip();
	}

	void prepareRender2D() {
		isPrepared = true;

		if(!cleared)
			clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		else
			clear(GL_DEPTH_BUFFER_BIT);

		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		glOrtho(0,screenSize.x,screenSize.y,0,-4096.0,4096.0);

		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();

		light::resetLights();

		switchToRenderState(state_2d);
		if(!intermediateBlend)
			cleared = false;
	}

	void drawFPSGraph(const recti& location) {
		double max_time = 0.03333333;
		foreach(frame, frames)
			if(*frame > max_time)
				max_time = *frame;

		float x = (float)location.topLeft.width, yOff = (float)location.topLeft.y, height = (float)location.getHeight();

		static render::RenderState rs;
		rs.lighting = false;
		rs.culling = render::FC_None;
		rs.depthTest = render::DT_NoDepthTest;

		switchToRenderState(rs);

		auto* buffer = VertexBufferTCV::fetch(&rs);
		auto* v = buffer->request(1, PT_Lines);

		v[0].col = v[1].col = Color(0,0,196);

		float yFrameLine = floor( yOff + height * (float)(1.0 - (0.0166667 / max_time)) );

		v[0].pos = vec3f(x,yFrameLine,0);
		v[1].pos = vec3f((float)location.botRight.x,yFrameLine,0);

		glColor3ub(0,255,0);

		if(frames.size() > 1) {
			v = buffer->request((unsigned)frames.size() - 1, PT_LineStrip);

			for(auto frame = frames.begin(), end = frames.end(); frame != end; ++frame, ++v) {
				v->col = Colorf((float)(*frame/0.033333), 1.f - (float)(*frame/0.0333333), 0);
				v->pos = vec3f(x, yOff + height * (1.f - (float)(*frame/max_time)), 0 );
				
				x += (float)location.getWidth() / (float)max_frames;
			}
		}

		glColor3ub(255,255,255);
	}

	void setSkybox(const RenderState* mat) {
		skybox = mat;
	}

	void setSkyboxMesh(const RenderMesh* mesh) {
		skyboxMesh = mesh;
	}

	void setScissor(const recti& clip) const {
		double x = (double)clip.topLeft.x / (double)screenSize.width;
		double y = (double)(screenSize.height - clip.botRight.y) / (double)screenSize.height;
		double w = clip.getWidth() / (double)screenSize.width;
		double h = clip.getHeight() / (double)screenSize.height;

		glScissor((int)(x * frameSize.x), (int)(y * frameSize.y), (int)(w * frameSize.x), (int)(h * frameSize.y));
	}

	void pushScreenClip(const recti& box) override {
		if(viewportClips.empty())
			glEnable(GL_SCISSOR_TEST);
		viewportClips.push(box);
		setScissor(box);
	}

	void popScreenClip() override {
		if(viewportClips.empty())
			return;
		viewportClips.pop();
		if(viewportClips.empty())
			glDisable(GL_SCISSOR_TEST);
		else
			setScissor(viewportClips.top());
	}
};

RenderDriver* createGLDriver() {
	return new GLDriver();
}

};

void shader_tex_size(float* out,unsigned short n,void* args) {
	vec2f* sizes = (vec2f*)out;
	auto* texs = ((render::GLDriver*)devices.render)->activeRenderState.textures;
	unsigned* texIndices = (unsigned*)args;
	for(unsigned short i = 0; i < n; ++i) {
		unsigned index = texIndices[i];
		if(index >= RENDER_MAX_TEXTURES)
			new(sizes+i) vec2f(0);
		else if(render::Texture* tex = texs[index])
			new(sizes+i) vec2f(tex->size);
		else
			new(sizes+i) vec2f(0);
	}
}

void shader_light_radius(float* out,unsigned short n,void* args) {
	auto* radii = ((render::GLDriver*)devices.render)->lightRadius;

	unsigned* indices = (unsigned*)args;
	for(unsigned short i = 0; i < n; ++i) {
		unsigned index = indices[i];
		if(index < 2)
			out[i] = radii[index];
		else
			out[i] = 0.f;
	}
}

void shader_light_position(float* out,unsigned short n,void* args) {
	auto* positions = ((render::GLDriver*)devices.render)->lightPosition;

	unsigned* indices = (unsigned*)args;
	for(unsigned short i = 0; i < n; ++i) {
		unsigned index = indices[i];
		if(index < 2) {
			out[i*3+0] = positions[index].x;
			out[i*3+1] = positions[index].y;
			out[i*3+2] = positions[index].z;
		}
		else {
			out[i*3+0] = 0.f;
			out[i*3+1] = 0.f;
			out[i*3+2] = 0.f;
		}
	}
}

void shader_light_screen(float* out,unsigned short n,void* args) {
	auto* positions = ((render::GLDriver*)devices.render)->screenLight;

	unsigned* indices = (unsigned*)args;
	for(unsigned short i = 0; i < n; ++i) {
		unsigned index = indices[i];
		if(index < 2) {
			out[i*2+0] = positions[index].x;
			out[i*2+1] = positions[index].y;
		}
		else {
			out[i*2+0] = 0.f;
			out[i*2+1] = 0.f;
		}
	}
}

void shader_light_active(float* out,unsigned short n,void* args) {
	auto* active = ((render::GLDriver*)devices.render)->lightActive;

	unsigned* indices = (unsigned*)args;
	for(unsigned short i = 0; i < n; ++i) {
		unsigned index = indices[i];
		if(index < 2)
			out[i] = active[index] ? 1.f : 0.f;
		else
			out[i] = 0.f;
	}
}

void setShaderLightRadius(unsigned index, double radius) {
	auto* active = ((render::GLDriver*)devices.render)->lightRadius;
	if(index < 2)
		active[index] = radius;
}
