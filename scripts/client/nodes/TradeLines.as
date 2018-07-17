import resources;
import systems;

bool SHOW_TRADE_LINES = true;
void setTradeLinesShown(bool enabled) {
	SHOW_TRADE_LINES = enabled;
}

bool getTradeLinesShown() {
	return SHOW_TRADE_LINES;
}

const Color LINE_START(0x00ffba80);
const Color LINE_MIDDLE(0xaaaaaa80);
const Color LINE_END(0x0000ff80);

const uint8 ALPHA_MIN = 80;
const uint8 ALPHA_MAX = 160;
const uint8 ALPHA_STEP = 10;

const double LOCAL_MAX_DIST = 12000.0;
const double LOCAL_FADE_MIN = 600.0;
const double LOCAL_FADE_MAX = 1000.0;

class TradeDesc {
	Object@ origin;
	int resId;
	Object@ destination;
	double originDist = 0.0, destDist = 0.0;
	const ResourceType@ type;
};

class TradeLine {
	SystemDesc@ to;
	line3dd path;
	vec3d side;

	int trades = 0;
	TradeDesc@[] gives;
	TradeDesc@[] takes;
};

class TradeLinesNodeScript {
	SystemDesc@ system;
	TradeLine[] lines;
	TradeDesc@[] localTrades;
	int dispTrades = 0;

	TradeLinesNodeScript(Node& node) {
	}

	void establish(Node& node, uint sysId) {
		@system = getSystem(sysId);

		uint adjCnt = system.adjacent.length;
		lines.length = adjCnt;
		double maxDist = system.radius * 2.0;
		for(uint i = 0; i < adjCnt; ++i) {
			TradeLine@ line = lines[i];
			@line.to = getSystem(system.adjacent[i]);

			//Build the line verts
			line.path.start = system.position;
			line.path.end = line.to.position;

			vec3d off = line.path.end - line.path.start;
			off.y = 0;
			off.normalize();
			
			line.path.start += off * system.radius;
			line.path.end -= off * line.to.radius;

			line.side = (quaterniond_fromAxisAngle(vec3d_up(), pi * 0.5) * off) * 32.0;
			line.path.start -= line.side;
			line.path.end -= line.side;

			//Discover maximum distance
			double dist = line.path.length + system.radius + line.to.radius;
			if(dist > maxDist)
				maxDist = dist;
		}

		//Set node position
		node.position = system.position;
		node.scale = maxDist;
		node.rebuildTransform();
	}

	void addPathing(Node& node, int towards, Object@ origin, Object@ dest, int resId, uint resType) {
		if(towards < -1 || towards >= int(lines.length))
			return;
		TradeDesc trade;
		@trade.origin = origin;
		trade.originDist = origin.radius;
		Planet@ o = cast<Planet>(origin);
		if(o !is null)
			trade.originDist = o.OrbitSize;
		
		@trade.destination = dest;
		trade.destDist = dest.radius;
		Planet@ d = cast<Planet>(dest);
		if(d !is null)
			trade.destDist = d.OrbitSize;
		trade.resId = resId;
		@trade.type = getResource(resType);

		if(towards == -1) {
			localTrades.insertLast(trade);
		}
		else {
			TradeLine@ line = lines[towards];
			++line.trades;
			if(origin.region is system.object)
				line.gives.insertLast(trade);
			if(dest.region is line.to.object)
				line.takes.insertLast(trade);
		}

		++dispTrades;
		node.visible = true;
	}

	void removePathing(Node& node, int towards, Object@ origin, int resId) {
		if(towards < -1 || towards >= int(lines.length))
			return;
		if(towards == -1) {
			uint cnt = localTrades.length;
			for(uint i = 0; i < cnt; ++i) {
				TradeDesc@ trade = localTrades[i];
				if(trade.origin is origin && trade.resId == resId) {
					localTrades.removeAt(i);
					--dispTrades;
					break;
				}
			}
		}
		else {
			TradeLine@ line = lines[towards];
			--line.trades;
			--dispTrades;

			uint cnt = line.gives.length;
			for(uint i = 0; i < cnt; ++i) {
				TradeDesc@ trade = line.gives[i];
				if(trade.origin is origin && trade.resId == resId) {
					line.gives.removeAt(i);
					break;
				}
			}
			cnt = line.takes.length;
			for(uint i = 0; i < cnt; ++i) {
				TradeDesc@ trade = line.takes[i];
				if(trade.origin is origin && trade.resId == resId) {
					line.takes.removeAt(i);
					break;
				}
			}
		}

		node.visible = dispTrades != 0;
	}

	bool preRender(Node& node) {
		if(system !is null && lines.length != system.adjacent.length)
			establish(node, system.index);
		return system !is null && SHOW_TRADE_LINES;
	}

	void render(Node& node) {
		if(system is null) // Why can this ever be true?
			return;

		bool sysVisible = system.object.VisionMask & playerEmpire.visionMask != 0;
		float localAlpha = 1.f;

		//Draw local trades
		/*if(node.sortDistance < LOCAL_MAX_DIST && sysVisible) {
			//Calculate distance to plane
			line3dd camLine(cameraPos, cameraPos+cameraFacing);
			vec3d intersect;
			double planeDist;
			if(!camLine.intersectY(intersect, node.position.y, false)) {
				intersect = cameraPos;
				intersect.y = node.position.y;
				planeDist = sqrt(
						sqr(max(0.0, intersect.distanceTo(node.position) - system.radius))
						+ sqr(cameraPos.y - node.position.y));
			}
			else {
				planeDist = intersect.distanceTo(cameraPos);
					max(0.0, intersect.distanceTo(node.position) - system.radius);
			}

			Color startColor = LINE_START;
			Color endColor = LINE_END;

			//Fade lines
			localAlpha = clamp((planeDist - LOCAL_FADE_MIN) / (LOCAL_FADE_MAX - LOCAL_FADE_MIN), 0.0, 1.0);
			startColor.a = localAlpha * 180;
			endColor.a = startColor.a;

			if(startColor.a != 0) {
				uint cnt = localTrades.length;
				for(uint i = 0; i < cnt; ++i) {
					TradeDesc@ trade = localTrades[i];
					vec3d from = trade.origin.position;
					vec3d to = trade.destination.position;
					
					drawLine(from + (to - from).normalized(trade.originDist), to + (from - to).normalized(trade.destDist),
						startColor, endColor, 0.0);
				}
			}
		}*/
		
		//Draw paths
		uint cnt = lines.length;
		for(uint i = 0; i < cnt; ++i) {
			TradeLine@ line = lines[i];
			if(line.trades > 0)
				drawPath(line, sysVisible, localAlpha);
		}
	}

	void drawPath(TradeLine@ line, bool sysVisible, float localAlpha) {
		bool otherVisible = line.to.object.VisionMask & playerEmpire.visionMask != 0;
		double startDist = 0.0;
		if(line.gives.length != 0)
			startDist = line.gives[0].origin.position.distanceTo(line.path.start);
		double dist = line.path.length + startDist;
		vec2f startDistLeft(startDist, 0), startDistRight(startDist, 1);
		vec2f endDistLeft(dist, 0), endDistRight(dist, 1);
		
		//Draw the line
		if(sysVisible || otherVisible) {
			Color color = LINE_MIDDLE;
			color.a = min(ALPHA_MAX, ALPHA_MIN + ALPHA_STEP * line.trades);

			drawPolygonStart(2, material::TradePaths, color);
			drawPolygonPoint(line.path.start + line.side, startDistLeft);
			drawPolygonPoint(line.path.end + line.side, endDistLeft);
			drawPolygonPoint(line.path.start - line.side, startDistRight);
			
			drawPolygonPoint(line.path.end + line.side, endDistLeft);
			drawPolygonPoint(line.path.end - line.side, endDistRight);
			drawPolygonPoint(line.path.start - line.side, startDistRight);
			drawPolygonEnd();
		}

		//Draw taking
		/*if(otherVisible) {
			Color midCol = LINE_MIDDLE;
			Color endCol = LINE_END;

			midCol.a = localAlpha * 180;
			endCol.a = midCol.a;

			uint cnt = line.takes.length;
			for(uint i = 0; i < cnt; ++i) {
				auto@ dest = line.takes[i];
				vec3d to = dest.destination.position;
				vec3d from = line.path.end;
				
				drawLine(from, to + (from - to).normalized(dest.destDist), midCol, endCol, dist);
			}
		}*/

		//Draw giving
		/*if(sysVisible) {
			Color startCol = LINE_START;
			Color midCol = LINE_MIDDLE;

			startCol.a = localAlpha * 255;
			midCol.a = startCol.a;

			uint cnt = line.gives.length;
			for(uint i = 0; i < cnt; ++i) {
				auto@ dest = line.gives[i];
				vec3d from = dest.origin.position;
				vec3d to = line.path.start;
				
				drawLine(from + (to - from).normalized(dest.originDist), to, startCol, midCol, 0.0);
			}
		}*/
	}

	void drawLine(const vec3d& from, const vec3d& to, const Color& fromColor, const Color& toColor, double len) {
		line3dd path(from, to);
		vec2f startLeft(len, 0), startRight(len, 1);
		len += path.length;
		vec2f endLeft(len, 0), endRight(len, 1);
		
		vec3d off = path.end - path.start;
		off.y = 0;
		off.normalize();
		
		vec3d side = (quaterniond_fromAxisAngle(vec3d_up(), pi * 0.5) * off) * 10.0;

		drawPolygonStart(2, material::TradePaths);
		drawPolygonPoint(path.start + side, startLeft, fromColor);
		drawPolygonPoint(path.end + side, endLeft, toColor);
		drawPolygonPoint(path.start - side, startRight, fromColor);
		
		drawPolygonPoint(path.end + side, endLeft, toColor);
		drawPolygonPoint(path.end - side, endRight, toColor);
		drawPolygonPoint(path.start - side, startRight, fromColor);
		drawPolygonEnd();
	}
}
