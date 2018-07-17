#pragma once
#include "vec2.h"
#include "constants.h"
#include <math.h>
#include <stdio.h>

enum HexGridAdjacency {
	HEX_DownLeft,
	HEX_Down,
	HEX_DownRight,
	HEX_UpRight,
	HEX_Up,
	HEX_UpLeft,
};

//Stores a hex grid layed out as:
// Indices         Positions
//0,0   2,0  0.0,0.0        1.5,0.0
//   1,0            0.75,0.5
//0,1   2,1  0.0,1.0        1.5,1.0
//   1,1            0.75,1.5
//0,2   2,2  0.0,2.0        1.5,2.0

template<class T = bool>
struct HexGrid {
	T* data;
	unsigned width, height;

	HexGrid()
		: data(0) {
	}

	HexGrid(vec2u size, T* Data)
		: data(Data), width(size.width), height(size.height)
	{
	}

	HexGrid(vec2u size)
		: data(new T[size.width*size.height]), width(size.width), height(size.height)
	{
	}

	HexGrid(unsigned Width, unsigned Height)
		: data(new T[Width*Height]), width(Width), height(Height)
	{
	}

	HexGrid(const HexGrid<T>& other)
		: data(0), width(0), height(0)
	{
		*this = other;
	}

	~HexGrid() {
		if(data)
			delete[] data;
	}

	HexGrid<T>& operator=(const HexGrid<T>& other) {
		resize(other.width, other.height);
		for(unsigned x = 0; x < width; ++x) {
			for(unsigned y = 0; y < height; ++y) {
				unsigned index = x * height + y;
				data[index] = other.data[index];
			}
		}
		return *this;
	}

	void resize(unsigned Width, unsigned Height) {
		if(data)
			delete[] data;
		data = new T[Width*Height];
		width = Width;
		height = Height;
	}

	void resize(vec2u size) {
		if(data)
			delete[] data;
		data = new T[size.width*size.height];
		width = size.width;
		height = size.height;
	}

	vec2u size() const {
		return vec2u(width, height);
	}

	size_t length() const {
		return width * height;
	}

	void clear(T value) {
		unsigned amount = width * height;
		for(unsigned i = 0; i < amount; ++i)
			data[i] = value;
	}

	void zero() {
		memset(data, 0, sizeof(T) * width * height);
	}

	unsigned count(T value) const {
		unsigned cnt = 0;
		unsigned amount = width * height;
		for(unsigned i = 0; i < amount; ++i)
			if(data[i] == value)
				++cnt;
		return cnt;
	}

	bool valid(const vec2u& pos) const {
		return pos.x < width && pos.y < height;
	}

	bool valid(const vec2u& pos, HexGridAdjacency dir) const {
		vec2u p = pos;
		if(!advance(p.x, p.y, dir))
			return false;
		return p.x < width && p.y < height;
	}

	T& get(unsigned x, unsigned y) {
		return data[x*height + y];
	}

	const T& get(unsigned x, unsigned y) const {
		return data[x*height + y];
	}

	T& get(unsigned x, unsigned y, HexGridAdjacency dir) {
		advance(x, y, dir);
		return data[x*height + y];
	}

	const T& get(unsigned x, unsigned y, HexGridAdjacency dir) const {
		advance(x, y, dir);
		return data[x*height + y];
	}

	T& get(vec2u pos) {
		return data[pos.x*height + pos.y];
	}

	const T& get(vec2u pos) const {
		return data[pos.x*height + pos.y];
	}

	T& get(vec2u pos, HexGridAdjacency dir) {
		advance(pos.x, pos.y, dir);
		return data[pos.x*height + pos.y];
	}

	const T& get(vec2u pos, HexGridAdjacency dir) const {
		advance(pos.x, pos.y, dir);
		return data[pos.x*height + pos.y];
	}

	const T& operator[](vec2u pos) const {
		return data[pos.x*height + pos.y];
	}

	T& operator[](vec2u pos) {
		return data[pos.x*height + pos.y];
	}

	const T& operator[](unsigned i) const {
		return data[i];
	}

	T& operator[](unsigned i) {
		return data[i];
	}

	static vec2d getEffectivePosition(unsigned x, unsigned y) {
		if(x % 2)
			return vec2d((double)x * 0.75, (double)y + 0.5);
		else
			return vec2d((double)x * 0.75, (double)y);
	}

	static vec2d getEffectivePosition(const vec2u& pos) {
		if(pos.x % 2)
			return vec2d((double)pos.x * 0.75, (double)pos.y + 0.5);
		else
			return vec2d((double)pos.x * 0.75, (double)pos.y);
	}

	static vec2i getGridPosition(const vec2d& pos) {
		vec2i out;

		unsigned x = (unsigned)floor(pos.x / 0.75);
		double xoffset = pos.x - (x * 0.75);

		//In a full tile
		if(xoffset > 0.25) {
			out.x = x;

			if(x % 2 == 1)
				out.y = (int)floor(pos.y - 0.5);
			else
				out.y = (int)floor(pos.y);
		}
		else {
			unsigned y;
			double yoffset;

			if(x % 2 == 1) {
				y = (unsigned)floor(pos.y - 0.5);
				yoffset = pos.y - y - 0.5;
			}
			else {
				y = (unsigned)floor(pos.y);
				yoffset = pos.y - y;
			}

			if(yoffset < 0.5) {
				double linex = 0.25 - (0.5 * yoffset);

				if(xoffset < linex) {
					out.x = x - 1;

					if(x % 2 == 1)
						out.y = y;
					else
						out.y = y - 1;
				}
				else {
					out.x = x;
					out.y = y;
				}
			}
			else {
				double linex = 0.5 * (yoffset - 0.5);

				if(xoffset < linex) {
					out.x = x - 1;

					if(x % 2 == 1)
						out.y = y + 1;
					else
						out.y = y;
				}
				else {
					out.x = x;
					out.y = y;
				}
			}
		}

		return out;
	}

	static bool advancePosition(vec2u& pos, const vec2u& size, HexGridAdjacency direction, unsigned amount = 1) {
		//Are we in the offset (+0.5 y) column? (1,3,5,etc)
		bool offset = (pos.x % 2) != 0;

		int moveY = 0, moveX = 0;

		switch(direction) {
			case HEX_Up:
				moveY = -1;
				break;

			case HEX_UpLeft:
				moveX = -1;
				if(!offset)
					moveY = -1;
				break;

			case HEX_UpRight:
				moveX = 1;
				if(!offset)
					moveY = -1;
				break;

			case HEX_DownLeft:
				moveX = -1;
				if(offset)
					moveY = 1;
				break;

			case HEX_Down:
				moveY = 1;
				break;

			case HEX_DownRight:
				moveX = 1;
				if(offset)
					moveY = 1;
				break;
		}

		bool inBounds = true;
		if(moveY) {
			unsigned newY = pos.y + (unsigned)moveY * amount;
			if(newY >= size.height)
				inBounds = false;
			else
				pos.y = newY;
		}

		if(moveX) {
			unsigned newX = pos.x + (unsigned)moveX * amount;
			if(newX >= size.width)
				inBounds = false;
			else
				pos.x = newX;
		}

		return inBounds;
	}

	//Advances <x,y> toward <direction>
	//Returns false if the result would be out of bounds of the grid
	//If only one dimension is a valid destination, it will move in that dimension
	bool advance(unsigned& x, unsigned& y, HexGridAdjacency direction, unsigned amount = 1) const {
		vec2u pos(x, y);
		bool val = advancePosition(pos, vec2u(width, height), direction, amount);
		x = pos.x;
		y = pos.y;
		return val;
	}

	bool advance(vec2u& pos, HexGridAdjacency direction, unsigned amount = 1) const {
		return advancePosition(pos, vec2u(width, height), direction, amount);
	}

	static HexGridAdjacency AdjacencyFromRadians(double radians) {
		while(radians < 0)
			radians += twopi;
		int dir =((int)floor(radians / (pi / 3.0)) + 3) % 6;
		return HexGridAdjacency(dir);
	}

	static double RadiansFromAdjacency(HexGridAdjacency adj) {
		return ((double)(adj) - 3.0) * (pi / 3.0) + (twopi / 6.0 * 0.5);
	}
};
