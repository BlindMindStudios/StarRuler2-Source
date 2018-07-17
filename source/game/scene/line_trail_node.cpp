#include "line_trail_node.h"
#include "render/driver.h"
#include "compat/gl.h"
#include "main/references.h"
#include "render/vertexBuffer.h"

extern double frameLen_s;
extern double pixelSizeRatio;

namespace render {
	extern const RenderMesh* lastRenderedMesh;
};

namespace scene {

	LineTrailNode::LineTrailNode(const render::RenderState& material) :
		storedPositions(0), firstIndex(1), stored_s(0), lineLen_s(1), qualitySteps(1), mat(material)
	{
		setFlag(NF_NoMatrix, true);
		setFlag(NF_Independent, false);
	}

	bool LineTrailNode::preRender(render::RenderDriver& driver) {
		rebuildTransformation();

		stored_s += frameLen_s;
		double step = lineLen_s / double(LINE_POS_COUNT-1);

		if(stored_s >= step) {
			stored_s -= step;

			--firstIndex;
			if(firstIndex >= LINE_POS_COUNT)
				firstIndex = LINE_POS_COUNT - 1;
			if(storedPositions < LINE_POS_COUNT)
				++storedPositions;

			prevPositions[firstIndex] = abs_position;
		}

		sortDistance = abs_position.distanceTo(driver.cam_pos);

		return sortDistance < (3500.0 * pixelSizeRatio);
	}

	void LineTrailNode::render(render::RenderDriver& driver) {
		auto* vertBuffer = render::VertexBufferTCV::fetch(&mat);
		auto* v = vertBuffer->request(storedPositions + 1, render::PT_LineStrip);
		float startPct = (float)(stored_s / lineLen_s);

		auto& camPos = driver.cam_pos;

		v[0].pos = vec3f(abs_position - camPos);
		v[0].col = startCol;
		v[0].uv = vec2f(0, 0);

		for(unsigned i = 0; i < storedPositions; ++i) {
			auto& vert = v[i+1];
			unsigned index = (firstIndex + i) % LINE_POS_COUNT;
			vert.pos = vec3f(prevPositions[index] - camPos);

			float pct = startPct + (float(i) / float(LINE_POS_COUNT-1));

			vert.col = startCol.getInterpolated(endCol, pct);

			vert.uv = vec2f(pct, float(index) / float(LINE_POS_COUNT));
		}
	}

	ProjectileBatch::ProjectileBatch() {
		setFlag(NF_Transparent, true);
		sortDistance = 0.0;
	}

	ProjectileBatch::~ProjectileBatch() {
		for(auto i = projectiles.begin(), end = projectiles.end(); i != end; ++i) {
			auto* projs = i->second;
			if(!projs)
				continue;

			for(unsigned ind = 0, cnt = projs->size(); ind != cnt; ++ind) {
				auto& proj = projs->at(ind);
				proj.kill->drop();
			}

			delete projs;
		}
	}

	void ProjectileBatch::registerProj(const render::RenderState& mat, ProjEffect& eff) {
		auto*& projs = projectiles[&mat];
		if(!projs)
			projs = new std::vector<ProjEffect>;
		projs->push_back(eff);
	}
	
	bool ProjectileBatch::preRender(render::RenderDriver& driver) {
		if(projectiles.empty())
			return false;
		float time = (float)frameLen_s;

		for(auto i = projectiles.begin(), end = projectiles.end(); i != end; ++i) {
			auto* projs = i->second;
			if(!projs || projs->empty())
				continue;

			auto* pProj = &(*projs)[0];
			unsigned copyOff = 0;
			for(unsigned ind = 0, cnt = projs->size(); ind != cnt; ++ind) {
				auto& proj = pProj[ind];
				proj.life -= time;
				if(proj.life < 0 || **proj.kill) {
					copyOff += 1;
					proj.kill->drop();
				}
				else {
					proj.pos += vec3d(proj.dir * (proj.speed * time));
					if(copyOff)
						(*projs)[ind - copyOff] = proj;
				}
			}

			if(copyOff)
				projs->resize(projs->size() - copyOff);
		}

		return true;
	}

	void ProjectileBatch::render(render::RenderDriver& driver) {
		auto& camPos = driver.cam_pos;

		for(auto i = projectiles.begin(), end = projectiles.end(); i != end; ++i) {
			auto* projs = i->second;
			if(!projs)
				continue;

			unsigned count = projs->size();
			if(count == 0)
				continue;

			if(projs->begin()->line) {
				//Draw out projectiles in batches of 128
				unsigned start = 0;
				while(start < count) {
					unsigned drawCount;
					if(start + 128 <= count)
						drawCount = 128;
					else
						drawCount = count - start;
				
					auto* buffer = render::VertexBufferTCV::fetch(i->first);
					auto* verts = buffer->request(drawCount, render::PT_Lines);

					for(unsigned p = start; p < start + drawCount; ++p, verts += 2) {
						auto& proj = (*projs)[p];
						float alpha = std::min(1.f, proj.life / proj.fadeStart);

						verts[0].pos = vec3f(proj.pos - camPos);
						verts[0].uv = vec2f(0,0);
						verts[0].col = proj.start;
						verts[0].col.a *= alpha;

						verts[1].pos = vec3f(proj.pos - vec3d(proj.dir * proj.length) - camPos);
						verts[1].uv = vec2f(1,0);
						verts[1].col = proj.end;
						verts[1].col.a *= alpha;
					}

					start += drawCount;
				}
			}
			else {
				auto& cam_pos = driver.cam_pos;
				double aspect = 1.0;
				if(i->first->textures[0]) {
					auto size = i->first->textures[0]->size;
					if(size.x > 0 && size.y > 0)
						aspect = (float)size.y / (float)size.x;
				}

				//Draw out projectiles in batches of 64
				unsigned start = 0;
				while(start < count) {
					unsigned drawCount;
					if(start + 64 <= count)
						drawCount = 64;
					else
						drawCount = count - start;
				
					auto* buffer = render::VertexBufferTCV::fetch(i->first);
					auto* verts = buffer->request(drawCount, render::PT_Quads);

					for(unsigned p = start; p < start + drawCount; ++p, verts += 4) {
						auto& proj = (*projs)[p];
						float alpha = std::min(1.f, proj.life / proj.fadeStart);

						double size = aspect * proj.length * 0.5;

						vec3d end = proj.pos - vec3d(proj.dir * proj.length);

						vec3d offset = vec3d(proj.pos - end).cross(driver.cam_facing).normalized(size);

						Color col = color;

						verts[0].pos = vec3f(end + offset - cam_pos);
						verts[0].uv = vec2f(0,0);
						verts[0].col = proj.end;
						verts[0].col.a *= alpha;

						verts[1].pos = vec3f(proj.pos + offset - cam_pos);
						verts[1].uv = vec2f(1.f,0);
						verts[1].col = proj.start;
						verts[1].col.a *= alpha;

						verts[2].pos = vec3f(proj.pos - offset - cam_pos);
						verts[2].uv = vec2f(1.f,1.f);
						verts[2].col = proj.start;
						verts[2].col.a *= alpha;

						verts[3].pos = vec3f(end - offset - cam_pos);
						verts[3].uv = vec2f(0,1.f);
						verts[3].col = proj.end;
						verts[3].col.a *= alpha;
					}

					start += drawCount;
				}
			}
		}
	}

	MissileBatch::MissileBatch() {
		setFlag(NF_Transparent, true);
		sortDistance = 0.0;
	}

	MissileBatch::~MissileBatch() {
		for(auto i = missiles.begin(), end = missiles.end(); i != end; ++i) {
			auto* msls = i->second;
			if(!msls)
				continue;

			for(unsigned ind = 0, cnt = msls->size(); ind != cnt; ++ind) {
				auto& missile = msls->at(ind);
				missile.track->drop();
			}

			delete msls;
		}
	}

	void MissileBatch::registerProj(const render::RenderState& mat, const render::RenderState& trail, MissileTrail& eff) {
		eff.lineStart = eff.lineCount = 0;
		eff.lineProgress = eff.startProgress = 0;
		MissileTrailMats mats = {&mat, &trail};
		auto*& msls = missiles[mats];
		if(!msls)
			msls = new std::vector<MissileTrail>;
		msls->push_back(eff);
	}
	
	bool MissileBatch::preRender(render::RenderDriver& driver) {
		if(missiles.empty())
			return false;
		if(frameLen_s == 0)
			return true;

		double gameTime = devices.driver->getGameTime();

		for(auto i = missiles.begin(), end = missiles.end(); i != end; ++i) {
			auto* msls = i->second;
			if(!msls)
				continue;

			unsigned copyOff = 0;
			for(unsigned ind = 0, cnt = msls->size(); ind != cnt; ++ind) {
				auto& missile = (*msls)[ind];
				auto& track = **missile.track;
				if(track.aliveUntil >= 0 && gameTime > track.aliveUntil) {
					if((int)missile.lineCount <= (int)missile.startProgress) {
						copyOff += 1;
						missile.track->drop();
					}
					else {
						missile.startProgress += frameLen_s * float(LINE_POS_COUNT) / missile.length;

						if(copyOff)
							(*msls)[ind - copyOff] = missile;
					}
				}
				else {
					missile.pos = (missile.pos).interpolate(track.pos + vec3d(track.vel) * (gameTime - track.lastUpdate), std::min(frameLen_s / 0.25, 1.0));
					missile.lastUpdate = gameTime;

					missile.lineProgress += frameLen_s * float(LINE_POS_COUNT) / missile.length;
					while(missile.lineProgress >= 1.f) {
						missile.lineProgress -= 1.f;
						missile.lineCount += 1;
						missile.lineStart = (missile.lineStart + LINE_POS_COUNT - 1) % LINE_POS_COUNT;
						if(missile.lineCount > LINE_POS_COUNT)
							missile.lineCount = LINE_POS_COUNT;
						missile.trail[missile.lineStart] = missile.pos;
					}

					if(copyOff)
						(*msls)[ind - copyOff] = missile;
				}
			}

			if(copyOff)
				msls->resize(msls->size() - copyOff);
		}

		return true;
	}
	
	void MissileBatch::render(render::RenderDriver& driver) {
		double gameTime = devices.driver->getGameTime();

		for(auto i = missiles.begin(), end = missiles.end(); i != end; ++i) {
			auto* msls = i->second;
			if(!msls)
				continue;

			//Render all sprites
			for(unsigned ind = 0, cnt = msls->size(); ind != cnt; ++ind) {
				auto& missile = (*msls)[ind];
				double until = missile.track->data.aliveUntil;
				if(until < 0 || until > gameTime)
					devices.render->drawBillboard(missile.pos, missile.size, *i->first.sprite, 0.0, &missile.color);
			}

			auto& cam_pos = driver.cam_pos;

			//Then render all trails
			for(unsigned ind = 0, cnt = msls->size(); ind != cnt; ++ind) {
				auto& missile = (*msls)[ind];
				if(missile.lineCount == 0)
					continue;
				
				auto* vertBuffer = render::VertexBufferTCV::fetch(i->first.trail);
				auto* v = vertBuffer->request(missile.lineCount + 1, render::PT_LineStrip);
				float startPct = (missile.startProgress + missile.lineProgress) * missile.length / float(LINE_POS_COUNT);

				v[0].pos = vec3f(missile.pos - cam_pos);
				v[0].col = missile.start;
				v[0].uv = vec2f(missile.startProgress * missile.length / float(LINE_POS_COUNT), 0);

				for(unsigned i = 0; i < missile.lineCount; ++i) {
					auto& vert = v[i+1];
					unsigned index = (missile.lineStart + i) % LINE_POS_COUNT;
					vert.pos = vec3f(missile.trail[index] - cam_pos);

					float pct = startPct + (float(i) / float(LINE_POS_COUNT-1));
					if(pct > 1.f)
						pct = 1.f;

					vert.col = missile.start.getInterpolated(missile.end, pct);

					vert.uv = vec2f(pct, float(index) / float(LINE_POS_COUNT));
				}
			}
		}
	}
};
