#include "vertexBuffer.h"
#include "compat/gl.h"
#include "main/references.h"
#include "compat/misc.h"
#include <unordered_map>

const unsigned maxVerts = 2048, maxInds = 4096;

unsigned drawnSteps = 0, bufferFlushes = 0;

namespace render {

	unsigned vbFloatLimit = 24, vbMaxSteps = 200;
	unsigned vbFlushCounts[FC_COUNT] = {0,0,0,0};

	extern const RenderMesh* lastRenderedMesh;
	extern float* shaderUniforms;
	VertexBufferTCV tcv;
	threads::Mutex bufferLock;

	extern bool useVertexArrays();

	inline bool getRequestSize(unsigned& indexCount, unsigned& vertCount, unsigned polygons, unsigned polyType) {
		switch(polyType) {
		case PT_Lines:
			indexCount = polygons * 2;
			vertCount = polygons * 2;
			return true;
		case PT_LineStrip:
			indexCount = polygons * 2;
			vertCount = polygons + 1;
			return true;
		case PT_Triangles:
			indexCount = polygons * 3;
			vertCount = polygons * 3;
			return false;
		case PT_Quads:
			indexCount = polygons * 6;
			vertCount = polygons * 4;
			return false;
		NO_DEFAULT
		}
	}

	void buildIndices(std::vector<unsigned short>& indices, unsigned indexCount, unsigned prevVerts, unsigned polygons, unsigned polyType) {
		//Fill out indices according to the polygon type
		auto prevInds = indices.size();
		indices.resize(prevInds + indexCount);
		unsigned short* pIndices = &indices.at(0);

		switch(polyType) {
		case PT_Lines:
			for(unsigned i = 0; i < polygons * 2; ++i)
				pIndices[prevInds + i] = prevVerts + i;
			break;
		case PT_LineStrip:
			for(unsigned i = 0; i < polygons; ++i) {
				pIndices[prevInds + (i*2)] = prevVerts + i;
				pIndices[prevInds + (i*2) + 1] = prevVerts + i + 1;
			}
			break;
		case PT_Triangles:
			for(unsigned i = 0; i < polygons * 3; ++i)
				pIndices[prevInds + i] = prevVerts + i;
			break;
		case PT_Quads:
			for(unsigned i = 0; i < polygons; ++i) {
				auto off = prevInds + (i*6);
				auto vOff = prevVerts + (i*4);
				pIndices[off] = vOff;
				pIndices[off+1] = vOff+2;
				pIndices[off+2] = vOff+1;
				pIndices[off+3] = vOff;
				pIndices[off+4] = vOff+3;
				pIndices[off+5] = vOff+2;
			}
			break;
		NO_DEFAULT
		}
	}

	void renderVertexBuffers() {
		tcv.draw();
	}

	VertexBufferTCV::VertexBufferTCV()
		: last(0)
	{
		vertices.reserve(maxVerts);
		indices.reserve(maxInds);
		steps.reserve(vbMaxSteps);

		shaderBufferSize = 40000;
		shaderBuffer = new float[shaderBufferSize];
		pNextShaderBuffer = shaderBuffer;
	}
	
	VertexBufferTCV::~VertexBufferTCV() {
		for(auto i = vertBuffer.begin(), end = vertBuffer.end(); i != end; ++i)
			glDeleteBuffers(1, &*i);
		for(auto i = indBuffer.begin(), end = indBuffer.end(); i != end; ++i)
			glDeleteBuffers(1, &*i);
		delete[] shaderBuffer;
	}
	
	void VertexBufferTCV::flushRetainingLast(FlushCause reason) {
		RenderStep step = *last;
		float* prevBuffer = pNextShaderBuffer;

		//We may have added a step that we decided we can't render, we just pop the empty step
		if(step.vertEnd == 0)
			steps.pop_back();

		draw(reason);

		step.vertStart = 0;
		step.vertEnd = 0;
		step.indexOffset = 0;

		if(step.shaderCache) {
			memcpy(pNextShaderBuffer, step.shaderCache, (prevBuffer - step.shaderCache) * sizeof(float));
			auto count = prevBuffer - step.shaderCache;
			step.shaderCache = pNextShaderBuffer;
			pNextShaderBuffer += count;
		}

		steps.push_back(step);
		last = &steps.back();
	}
	
	void VertexBufferTCV::duplicateLast() {
		if(steps.size() != steps.capacity()) {
			steps.push_back(*last);
			last = &steps.back();
			
			last->indexOffset = (unsigned short)indices.size();
			last->vertStart = (unsigned short)vertices.size();
		}
		else {
			flushRetainingLast(FC_StepLimit);
		}
	}

	VertexTCV* VertexBufferTCV::request(unsigned polygons, unsigned polyType) {
		unsigned indexCount = 0;
		unsigned vertCount = 0;
		bool isLines = getRequestSize(indexCount, vertCount, polygons, polyType);

		unsigned prevVerts = (unsigned)vertices.size();

		if(prevVerts + vertCount > maxVerts
			|| indices.size() + indexCount > maxInds)
		{
			flushRetainingLast(FC_VertexLimit);
			last->lines = isLines;
			prevVerts = 0;
		}
		
		if(last->lines == isLines) {
			vertices.resize(prevVerts + vertCount);
			buildIndices(indices, indexCount, prevVerts, polygons, polyType);
			if(last->vertEnd)
				last->vertEnd += vertCount;
			else
				last->vertEnd = last->vertStart + vertCount - 1;

			return &vertices[prevVerts];
		}
		else if(last->vertEnd != 0) {
			duplicateLast();
			last->lines = isLines;
			vertices.resize(prevVerts + vertCount);
			buildIndices(indices, indexCount, prevVerts, polygons, polyType);
			last->vertEnd = last->vertStart + vertCount - 1;

			return &vertices[prevVerts];
		}
		else {
			last->lines = isLines;
			vertices.resize(prevVerts + vertCount);
			buildIndices(indices, indexCount, prevVerts, polygons, polyType);
			last->vertEnd = last->vertStart + vertCount - 1;

			return &vertices[prevVerts];
		}
	}

	void VertexBufferTCV::draw(FlushCause reason) {
		if(vertices.empty())
			return;

		if(vertBuffer.empty()) {
			GLuint buffs[24];
			glGenBuffers(24, buffs);
			for(unsigned i = 0; i < 12; ++i)
				vertBuffer.push_back(buffs[i]);
			for(unsigned i = 12; i < 24; ++i)
				indBuffer.push_back(buffs[i]);
		}

		{
			lastRenderedMesh = reinterpret_cast<const render::RenderMesh*>(this);
			if(useVertexArrays())
				glBindVertexArray(0);
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indBuffer.front());
			glBindBuffer(GL_ARRAY_BUFFER, vertBuffer.front());
			
			indBuffer.push_back(indBuffer.front());
			indBuffer.pop_front();
			vertBuffer.push_back(vertBuffer.front());
			vertBuffer.pop_front();

			if(!useVertexArrays()) {
				glDisableVertexAttribArray(0);
				glDisableVertexAttribArray(1);
				glDisableVertexAttribArray(2);
				glDisableVertexAttribArray(3);
				glDisableVertexAttribArray(4);
				glDisableVertexAttribArray(5);
			}

			glEnableClientState(GL_VERTEX_ARRAY);
			glEnableClientState(GL_COLOR_ARRAY);
			glEnableClientState(GL_TEXTURE_COORD_ARRAY);

			glTexCoordPointer(2, GL_FLOAT, sizeof(VertexTCV), (void*)offsetof(VertexTCV, uv));
			glColorPointer(4, GL_UNSIGNED_BYTE, sizeof(VertexTCV), (void*)offsetof(VertexTCV, col));
			glVertexPointer(3, GL_FLOAT, sizeof(VertexTCV), (void*)offsetof(VertexTCV, pos));
		}

		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.size() * sizeof(unsigned short),
					 &indices[0], GL_STREAM_DRAW);

		glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(VertexTCV), &vertices[0], GL_STREAM_DRAW);

		drawnSteps += (unsigned)steps.size();
		bufferFlushes += 1;
		vbFlushCounts[reason] += 1;

		RenderStep* pSteps = steps.data();
		for(unsigned i = 0, cnt = (unsigned)steps.size(); i < cnt; ++i) {
			auto& step = pSteps[i];
			shaderUniforms = step.shaderCache;
			devices.render->switchToRenderState(*step.material);
			unsigned count = ((i+1) < cnt ? pSteps[i+1].indexOffset : (unsigned short)indices.size()) - step.indexOffset;

			glDrawRangeElements(step.lines ? GL_LINES : GL_TRIANGLES, step.vertStart, step.vertEnd,
				count, GL_UNSIGNED_SHORT, (void*)(step.indexOffset * sizeof(unsigned short)));
		}

		shaderUniforms = 0;

		vertices.clear();
		indices.clear();
		steps.clear();
		last = 0;
		pNextShaderBuffer = shaderBuffer;
	}

	VertexBufferTCV* VertexBufferTCV::fetch(const RenderState* mat) {
		auto& vbuff = tcv;
		if(vbuff.last == 0 || vbuff.last->material != mat) {
			if(vbuff.steps.size() == vbMaxSteps)
				vbuff.draw(FC_StepLimit);

			RenderStep step;
			step.material = mat;
			step.lines = false;
			step.indexOffset = (unsigned short)tcv.indices.size();
			step.vertStart = tcv.steps.empty() ? 0 : tcv.steps.back().vertEnd + 1;
			step.vertEnd = 0;

			if(mat->shader && !mat->shader->constant) {
				step.shaderCache = tcv.pNextShaderBuffer;
				mat->shader->saveDynamicVars(tcv.pNextShaderBuffer);
				tcv.pNextShaderBuffer += mat->shader->dynamicFloats;
			}
			else {
				step.shaderCache = 0;
			}

			vbuff.steps.push_back(step);
			vbuff.last = &vbuff.steps.back();
		}
		else if(mat->shader && !mat->shader->constant) {
			auto* buffer = vbuff.pNextShaderBuffer;
			unsigned floats = mat->shader->dynamicFloats;

			if(buffer + floats >= vbuff.shaderBuffer + vbuff.shaderBufferSize) {
				//Flush the buffer and re-fetch the step
				vbuff.draw(FC_ShaderLimit);
				return fetch(mat);
			}
			else {
				mat->shader->saveDynamicVars(buffer);
				auto* lastStep = vbuff.last;

				//When a shader uses a small enough amount of data, check to see if it's duplicated
				//If it is, we can batch it into one step
				if(floats > vbFloatLimit || memcmp(lastStep->shaderCache, buffer, floats * sizeof(float)) != 0) {
					tcv.steps.push_back(*lastStep);
					lastStep = &tcv.steps.back();
					tcv.last = lastStep;

					lastStep->shaderCache = buffer;
					lastStep->indexOffset = (unsigned short)tcv.indices.size();
					lastStep->vertStart = lastStep->vertEnd + 1;
					lastStep->vertEnd = 0;
					vbuff.pNextShaderBuffer += floats;
				}
			}
		}

		return &vbuff;
	}
};
