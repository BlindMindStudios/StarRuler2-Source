class WordWrap {
	string[] lines;
	int[] positions;
	int[] ends;
	int maxWidth;

	bool changed;

	const Font@ Font;
	string Text;
	int Width;

	WordWrap() {
		Width = 100;
		maxWidth = 100;
		changed = true;
	}

	void set_font(const Font@ fnt) {
		if(fnt is Font)
			return;
		@Font = fnt;
		changed = true;
	}

	void set_text(const string& txt) {
		Text = txt;
		changed = true;
	}

	void set_width(int wd) {
		if(wd == Width)
			return;
		Width = wd;
		changed = true;
	}

	int get_lineCount() {
		return lines.length();
	}

	void update() {
		if(!changed)
			return;

		uint len = Text.length();
		uint line = 0;
		uint start = 0;
		int pos = 0;
		int w = 0, ch = 0, prevCh = 0;
		int word = -1, word_w = 0;
		maxWidth = 0;

		while(pos >= 0) {
			int prevPos = pos;
			u8next(Text, pos, ch);

			if(ch == '\n') {
				if(lines.length() <= line) {
					lines.insertLast(Text.substr(start, prevPos - start));
					positions.insertLast(start);
					ends.insertLast(prevPos);
				}
				else {
					lines[line] = Text.substr(start, prevPos - start);
					positions[line] = start;
					ends[line] = prevPos;
				}

				if(w > maxWidth)
					maxWidth = w;

				++line;
				start = prevPos+1;
				w = 0;
				word = -1;
			}
			else {
				int chW = Font.getDimension(ch, prevCh).x;
				w += chW;

				if(w > Width) {
					if(word >= 0) {
						prevPos = word;
						w = w - word_w;
					}
					else {
						w = chW;
					}

					if(lines.length() <= line) {
						lines.insertLast(Text.substr(start, prevPos - start));
						positions.insertLast(start);
						ends.insertLast(prevPos);
					}
					else {
						lines[line] = Text.substr(start, prevPos - start);
						positions[line] = start;
						ends[line] = prevPos;
					}

					++line;
					start = prevPos;
					word = -1;
					maxWidth = Width;
				}
				else if(ch == ' ') {
					word = pos;
					word_w = w;
				}
			}

			prevCh = ch;
		}

		if(start <= len) {
			if(lines.length() <= line) {
				lines.insertLast(Text.substr(start, len - start));
				positions.insertLast(start);
				ends.insertLast(len);
			}
			else {
				lines[line] = Text.substr(start, len - start);
				positions[line] = start;
				ends[line] = len;
			}
			++line;
		}

		if(line != lines.length()) {
			lines.resize(line);
			positions.resize(line);
			ends.resize(line);
		}

		if(w > maxWidth)
			maxWidth = w;

		changed = false;
	}
};
