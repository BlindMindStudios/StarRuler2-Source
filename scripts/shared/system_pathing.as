from settings.map_lib import SystemDesc;

#section gui
from navigation.systems import get_systemCount, getSystem;
#section server-side
import SystemDesc@ getSystem(uint index) from "game_start";
import SystemDesc@ getSystem(Region@ region) from "game_start";
import uint get_systemCount() from "game_start";
#section menu
uint get_systemCount() { return 0; }
SystemDesc@ getSystem(uint index) { return null; }
SystemDesc@ getSystem(Region@ region) { return null; }
#section all

const double MAX_LINK_DISTANCE = INFINITY;
class SystemPath : Serializable {
	int[] path;
	SystemDesc@ goal;
	SystemDesc@ origin;
	double maxLinkDistance = MAX_LINK_DISTANCE;

	priority_queue q;
	double[] dist;
	int[] previous;
	bool[] visited;

	SystemPath() {
	}

	bool get_valid() {
		return path.length != 0;
	}

	void read(Message& msg) {
		if(msg.readBit()) {
			uint ind = 0;
			msg >> ind;
			@goal = getSystem(ind);
		}
		else {
			@goal = null;
		}

		if(msg.readBit()) {
			uint ind = 0;
			msg >> ind;
			@origin = getSystem(ind);
		}
		else {
			@origin = null;
		}

		uint cnt = msg.readSmall();
		path.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> path[i];

		maxLinkDistance = msg.read_float();
	}

	void write(Message& msg) {
		if(goal !is null) {
			msg.write1();
			msg << goal.index;
		}
		else {
			msg.write0();
		}

		if(origin !is null) {
			msg.write1();
			msg << origin.index;
		}
		else {
			msg.write0();
		}

		uint cnt = path.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg << path[i];

		msg << float(maxLinkDistance);
	}

	void clear() {
		@goal = null;
		@origin = null;
		path.length = 0;
	}

	uint get_pathSize() {
		return path.length;
	}

	SystemDesc@ get_pathNode(uint index) {
		if(index >= path.length)
			return null;
		int sysindex = path[index];
		return getSystem(uint(sysindex));
	}

	void itLink(SystemDesc@ node, SystemDesc@ other, double distance) {
		//Don't consider links over the maximum distance
		if(distance > maxLinkDistance)
			return;

		//Don't consider already visited nodes
		if(visited[other.index])
			return;

		//If the path through here is faster,
		//run it through here instead
		double pthlen = dist[node.index] + distance;

		if(pthlen < dist[other.index]) {
			dist[other.index] = pthlen;
			previous[other.index] = int(node.index);

			q.push(int(other.index), -dist[other.index]);
		}
	}

	void itNodes(SystemDesc@ node) {
		//Add adjacencies
		uint ncnt = node.adjacent.length;
		for(uint j = 0; j < ncnt; ++j) {
			SystemDesc@ other = getSystem(node.adjacent[j]);
			double dist = node.adjacentDist[j];
			itLink(node, other, dist);
		}

		//Add wormholes
		ncnt = node.wormholes.length;
		for(uint j = 0; j < ncnt; ++j) {
			SystemDesc@ other = getSystem(node.wormholes[j]);
			itLink(node, other, 0.0);
		}
	}

	//Run dijkstra and generate a path
	bool generate(SystemDesc@ from, SystemDesc@ to, bool keepCache = false) {
		@origin = from;
		@goal = to;
		return generate(keepCache);
	}

	bool generate(bool keepCache = false) {
		uint cnt = systemCount;
		while(!q.empty())
			q.pop();

		path.length = 0;
		if(origin is null || goal is null)
			return false;
		if(origin is goal) {
			path.insertLast(goal.index);
			return true;
		}

		dist.length = cnt;
		previous.length = cnt;
		visited.length = cnt;

		for(uint i = 0; i < cnt; ++i) {
			dist[i] = INFINITY;
			previous[i] = -1;
			visited[i] = false;
		}

		dist[origin.index] = 0;
		q.push(int(origin.index), 0);

		//Run dijkstra
		while(!q.empty()) {
			//Retrieve the highest priority node
			uint index = uint(q.top());
			SystemDesc@ node = getSystem(index);

			//Stop if all the nodes are unreachable
			if(dist[index] == INFINITY)
				break;

			q.pop();

			//Only visit nodes once
			if(visited[index])
				continue;
			visited[index] = true;

			//Check all neighbours
			itNodes(node);
		}

		//Check if a path was found
		if(previous[goal.index] == -1)
			return false;

		//Generate the path in reverse form
		uint current = goal.index;
		uint orig = origin.index;
		while(current != orig) {
			path.insertLast(current);
			current = previous[current];
		}
		path.insertLast(current);
		path.reverse();

		if(!keepCache) {
			dist.length = 0;
			previous.length = 0;
			visited.length = 0;
		}
		return true;
	}

	void printPath() {
		if(goal is null || origin is null) {
			print("Uninitialized path.");
			return;
		}
		print(origin.name+" --> "+goal.name);
		if(path.length == 0) {
			print("Invalid path.");
			return;
		}
		for(uint i = 0, cnt = path.length; i < cnt; ++i)
			print("  . "+pathNode[i].name);
	}
};

class TradePath : SystemPath {
	Empire@ forEmpire;
	bool onlyValid = true;
	bool foundGate = false;

	TradePath() {
	}

	TradePath(Empire@ emp) {
		@forEmpire = emp;
	}

	void read(Message& msg) {
		msg >> forEmpire;
		msg >> onlyValid;
		SystemPath::read(msg);
	}

	void write(Message& msg) {
		msg << forEmpire;
		msg << onlyValid;
		SystemPath::write(msg);
	}

	bool canLink(SystemDesc@ node, SystemDesc@ other) {
		if(node is other || forEmpire is null)
			return true;
		if(node.isAdjacent(other)) {
			if(forEmpire.GlobalTrade)
				return true;
			if(node !is origin && node.object.TradeMask & forEmpire.TradeMask.value == 0)
				return false;
			if(other !is goal && other.object.TradeMask & forEmpire.TradeMask.value == 0)
				return false;
		}
		else {
			if(node.object.GateMask.value & forEmpire.mask == 0)
				return false;
			if(other.object.GateMask.value & forEmpire.mask == 0)
				return false;
		}
		return true;
	}

	bool get_isUsablePath() {
		if(!valid)
			return false;
		if(forEmpire !is null) {
			uint cnt = path.length;
			SystemDesc@ prev = origin;
			for(uint i = 0, cnt = path.length; i < cnt; ++i) {
				SystemDesc@ desc = getSystem(path[i]);
				if(!canLink(prev, desc))
					return false;
				@prev = desc;
			}
		}
		return true;
	}

	bool generate(bool keepCache = false) override {
		onlyValid = true;
		foundGate = false;
		return SystemPath::generate(keepCache=keepCache);
	}

	bool generate(bool OnlyValid, bool keepCache) {
		onlyValid = OnlyValid;
		foundGate = false;
		return SystemPath::generate(keepCache=keepCache);
	}

	void itLink(SystemDesc@ node, SystemDesc@ other, double distance) override {
		if(forEmpire !is null && onlyValid && !canLink(node, other))
			return;
		SystemPath::itLink(node, other, distance);
	}

	void itNodes(SystemDesc@ node) override {
		if(forEmpire !is null && !foundGate) {
			if(node.object.GateMask.value & forEmpire.mask != 0) {
				foundGate = true;
				for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
					auto@ other = getSystem(i);
					if(other is node)
						continue;
					if(other.object.GateMask.value & forEmpire.mask != 0)
						SystemPath::itLink(node, other, 0.05);
				}
			}
		}
		SystemPath::itNodes(node);
	}
};

const SystemDesc@ getClosestSystem(const vec3d& point, Empire& presence, bool trade = false) {
	const SystemDesc@ best;
	double bestDist = INFINITY;
	for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
		auto@ sys = getSystem(i);
		if(trade) {
			if(sys.object.TradeMask & presence.TradeMask.value == 0)
				continue;
		}
		else {
			if(sys.object.PlanetsMask & presence.mask == 0)
				continue;
		}
		double d = sys.object.position.distanceToSQ(point);
		if(d < bestDist) {
			@best = sys;
			bestDist = d;
		}
	}
	return best;
}
