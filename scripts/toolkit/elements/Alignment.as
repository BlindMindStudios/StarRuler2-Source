enum AlignmentSide {
	AS_Left,
	AS_Right,
	AS_Add,
	AS_Top = AS_Left,
	AS_Bottom = AS_Right,
	AS_Width = AS_Add,
	AS_Height = AS_Add
}

AlignedPoint@ get_Left() {
	return AlignedPoint(AS_Left);
}

AlignedPoint@ get_Right() {
	return AlignedPoint(AS_Right);
}

AlignedPoint@ get_Top() {
	return AlignedPoint(AS_Top);
}

AlignedPoint@ get_Bottom() {
	return AlignedPoint(AS_Bottom);
}

final tidy class AlignedPoint {
	int type;
	float percent;
	int pixels;

	AlignedPoint() {
		type = AS_Left;
		pixels = 0;
		percent = 0;
	}

	AlignedPoint(AlignmentSide side) {
		type = side;
		pixels = 0;
		percent = 0;
	}

	AlignedPoint(int px) {
		pixels = px;
		percent = 0;
		type = AS_Left;
	}

	AlignedPoint(float perc, int px) {
		pixels = px;
		percent = perc;
		type = AS_Left;
	}

	AlignedPoint(int tp, float perc, int px) {
		type = tp;
		pixels = px;
		percent = perc;
	}

	AlignedPoint(int tp, float perc, int px, int anch) {
		type = tp;
		pixels = px;
		percent = perc;
	}

	void set(int px) {
		pixels = px;
		percent = 0;
		type = AS_Left;
	}

	void set(float perc, int px) {
		pixels = px;
		percent = perc;
		type = AS_Left;
	}

	void set(int tp, float perc, int px) {
		type = tp;
		pixels = px;
		percent = perc;
	}

	void set(int tp, float perc, int px, int anch) {
		type = tp;
		pixels = px;
		percent = perc;
	}

	int resolve(int size, int addFrom = 0) const {
		if(type == AS_Left)
			return percent * size + pixels;
		else if(type == AS_Right)
			return size - percent * size - pixels;
		else if(type == AS_Add)
			return addFrom + percent * size + pixels;
		return 0;
	}

	AlignedPoint& opAssign(const AlignedPoint& other) {
		type = other.type;
		percent = other.percent;
		pixels = other.pixels;
		return this;
	}

	AlignedPoint& opAdd(int px) {
		if(type == AS_Left)
			pixels += px;
		else
			pixels -= px;
		return this;
	}

	AlignedPoint& opSub(int px) {
		if(type == AS_Left)
			pixels -= px;
		else
			pixels += px;
		return this;
	}

	AlignedPoint& opAdd(float pct) {
		if(type == AS_Left)
			percent += pct;
		else
			percent -= pct;
		return this;
	}

	AlignedPoint& opSub(float pct) {
		if(type == AS_Left)
			percent -= pct;
		else
			percent += pct;
		return this;
	}

	void dump() {
		print(""+type+" : "+pixels+" : "+percent+"%");
	}
};

final tidy class Alignment {
	AlignedPoint@ left;
	AlignedPoint@ right;
	AlignedPoint@ top;
	AlignedPoint@ bottom;
	
	Alignment() {
		@left = AlignedPoint(AS_Left, 0.f, 0);
		@right = AlignedPoint(AS_Right, 0.f, 0);
		@top = AlignedPoint(AS_Top, 0.f, 0);
		@bottom = AlignedPoint(AS_Bottom, 0.f, 0);
	}

	Alignment(AlignedPoint@ Left, AlignedPoint@ Top, AlignedPoint@ Right, AlignedPoint@ Bot) {
		@left = Left;
		@right = Right;
		@top = Top;
		@bottom = Bot;
	}

	Alignment(AlignedPoint@ Left, AlignedPoint@ Top, int Width, int Height) {
		@left = Left;
		@top = Top;
		@right = AlignedPoint(AS_Add, 0.f, Width);
		@bottom = AlignedPoint(AS_Add, 0.f, Height);
	}

	Alignment(AlignedPoint@ Left, AlignedPoint@ Top, AlignedPoint@ Right, int Height) {
		@left = Left;
		@top = Top;
		@right = Right;
		@bottom = AlignedPoint(AS_Add, 0.f, Height);
	}

	Alignment& fill() {
		left.set(AS_Left, 0.f, 0);
		right.set(AS_Right, 0.f, 0);
		top.set(AS_Top, 0.f, 0);
		bottom.set(AS_Bottom, 0.f, 0);
		return this;
	}

	Alignment& padded(int padding) {
		left.pixels += padding;
		right.pixels += padding;
		top.pixels += padding;
		bottom.pixels += padding;
		return this;
	}

	Alignment& padded(int x, int y) {
		left.pixels += x;
		right.pixels += x;
		top.pixels += y;
		bottom.pixels += y;
		return this;
	}

	Alignment& padded(int x, int y, int x2, int y2) {
		left.pixels += x;
		right.pixels += x2;
		top.pixels += y;
		bottom.pixels += y2;
		return this;
	}
	
	Alignment(int lt, float lp, int lx,
			 int tt, float tp, int tx,
			 int rt, float rp, int rx,
			 int bt, float bp, int bx) {
		left.set(lt, lp, lx);
		top.set(tt, tp, tx);
		right.set(rt, rp, rx);
		bottom.set(bt, bp, bx);
	}

	Alignment(recti from) {
		@left = AlignedPoint(from.topLeft.x);
		@right = AlignedPoint(from.topLeft.y);
		@top = AlignedPoint(from.botRight.x);
		@bottom = AlignedPoint(from.botRight.y);
	}

	void set(int lt, float lp, int lx,
			 int tt, float tp, int tx,
			 int rt, float rp, int rx,
			 int bt, float bp, int bx) {
		left.set(lt, lp, lx);
		top.set(tt, tp, tx);
		right.set(rt, rp, rx);
		bottom.set(bt, bp, bx);
	}

	void set(AlignedPoint@ Left, AlignedPoint@ Top, AlignedPoint@ Right, AlignedPoint@ Bot) {
		@left = Left;
		@right = Right;
		@top = Top;
		@bottom = Bot;
	}

	recti resolve(const vec2i& within) const {
		//Get covered rectangle
		recti res;
		res.topLeft.x = left.resolve(within.width);
		res.topLeft.y = top.resolve(within.height);
		res.botRight.x = right.resolve(within.width, res.topLeft.x);
		res.botRight.y = bottom.resolve(within.height, res.topLeft.y);

		return res;
	}

	void dump() {
		print("Left: ");
		left.dump();
		print("Top: ");
		top.dump();
		print("Right: ");
		right.dump();
		print("Bottom: ");
		bottom.dump();
	}
};

Alignment@ Alignment_Fill() {
	return Alignment(Left, Top, Right, Bottom);
}
