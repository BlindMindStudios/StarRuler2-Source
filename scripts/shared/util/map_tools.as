class Poisson2D {
	array<vec2d> points;
	array<vec2d> grid;
	array<vec2d> output;
	vec2u gridSize;
	double cell;
	double circleRadius = INFINITY;

	//TODO: Use a dequeue (list?)
	array<vec2d> queue;

	Poisson2D() {
	}

	Poisson2D(double width, double height, double distance, uint order = 30) {
		generate(width, height, distance, order);
	}

	void generate(double width, double height, double distance, uint order = 30) {
		cell = distance / sqrt(2.0);
		gridSize = vec2u(ceil(width/cell), ceil(height)/cell);
		grid.length = gridSize.x * gridSize.y;
		for(uint i = 0, cnt = grid.length; i < cnt; ++i)
			grid[i] = vec2d(INFINITY, INFINITY);
		queue.reserve(order * gridSize.x);

		//Generate a first point
		vec2d start = vec2d(randomd(width*0.2, width*0.8), randomd(height*0.2, height*0.8));
		queue.insertLast(start);
		points.insertLast(start);
		grid[gridIndex(start)] = start;

		//Process the grid
		while(queue.length != 0) {
			uint index = randomi(0, queue.length-1);
			vec2d point = queue[index];
			queue.removeAt(index);

			for(uint n = 0; n < order; ++n) {
				vec2d other = point + random2d(distance, distance*2.0);

				if(!validPosition(other))
					continue;
				if(circleRadius != INFINITY && other.distanceToSQ(vec2d(width/2, height/2)) > circleRadius * circleRadius)
					continue;
				if(!checkDistance(other, distance * distance))
					continue;

				queue.insertLast(other);
				grid[gridIndex(other)] = other;
				points.insertLast(other);
			}
		}

		//Shuffle the points
		for(int i = points.length - 1; i >= 0; --i) {
			int swapIndex = randomi(0, i);

			auto first = points[i];
			auto second = points[swapIndex];

			points[i] = second;
			points[swapIndex] = first;
		}
	}

	bool checkDistance(const vec2d& pos, double distSQ) {
		vec2u coords = gridCoords(pos);
		for(int x = -2; x <= 2; ++x) {
			for(int y = -2; y <= 2; ++y) {
				if(pointDistance(pos, vec2u(vec2i(coords) + vec2i(x, y))) < distSQ)
					return false;
			}
		}
		return true;
	}

	double pointDistance(const vec2d& pos, const vec2u& coords) {
		if(coords.x >= gridSize.x || coords.y >= gridSize.y)
			return INFINITY;
		uint index = coords.x + coords.y * gridSize.x;
		return grid[index].distanceToSQ(pos);
	}

	bool validPosition(const vec2d& pos) {
		if(pos.x < 0 || pos.y < 0)
			return false;
		vec2u coords = gridCoords(pos);
		return coords.x < gridSize.x && coords.y < gridSize.y;
	}

	vec2u gridCoords(const vec2d& pos) {
		return vec2u(pos.x / cell, pos.y / cell);
	}

	uint gridIndex(const vec2d& pos) {
		return int(pos.x / cell) + int(pos.y / cell) * gridSize.x;
	}

	uint gridIndex(const vec2u& coords) {
		return coords.x + coords.y* gridSize.x;
	}

	uint get_length() {
		return points.length;
	}

	vec2d opIndex(uint index) {
		return points[index];
	}
};
