//Loads a datafile into a logical structure that can be mutated, then
//dumped back into the datafile properly.

class FileDesc {
	array<LineDesc@> lines;
	bool exists = false;

	FileDesc() {}
	FileDesc(const string& filename) {
		load(filename);
	}

	bool opEquals(const FileDesc& other) const {
		if(lines.length != other.lines.length)
			return false;
		for(uint i = 0, cnt = lines.length; i < cnt; ++i) {
			if(lines[i] != other.lines[i])
				return false;
		}
		return true;
	}

	void load(const string& filename) {
		clear();
		if(fileExists(filename)) {
			exists = true;
			ReadFile f(filename, true);
			f.skipEmpty = false;
			f.skipComments = false;

			while(f++)
				lines.insertLast(LineDesc(f));
			while(lines.length != 0 && lines[lines.length-1].isEmpty && lines[lines.length-1].comment.length == 0)
				lines.removeAt(lines.length-1);
		}
	}

	void clear() {
		lines.length = 0;
		exists = false;
	}

	void save(const string& filename) {
		WriteFile file(filename);
		for(uint i = 0, cnt = lines.length; i < cnt; ++i)
			lines[i].write(file);
	}

	string toString() const {
		string str;
		for(uint i = 0, cnt = lines.length; i < cnt; ++i)
			str += lines[i].toString()+"\n";
		return str;
	}
};

class LineDesc {
	bool isEmpty = false;
	bool isKey = true;
	uint indent = 0;
	string line;
	string key;
	string value;
	string comment;

	LineDesc() {}
	LineDesc(const ReadFile& f) {
		indent = f.indent;
		isKey = !f.fullLine;

		if(isKey) {
			key = f.key.trimmed();
			value = f.value.trimmed();
			line = f.line.trimmed();
			isEmpty = false;

			if(value.findFirst("\n") == -1) {
				int pos = value.findFirst("//");
				if(pos != -1) {
					comment = value.substr(pos+2);
					value = value.substr(0, pos);
				}
			}
		}
		else {
			line = f.line.trimmed();
			int pos = line.findFirst("//");
			if(pos != -1) {
				comment = line.substr(pos+2);
				line = line.substr(0, pos);
			}

			line = line.trimmed();
			isEmpty = line.length == 0;
		}
	}

	bool opEquals(const LineDesc& other) const {
		if(other.isEmpty != isEmpty)
			return false;
		if(other.isKey != isKey)
			return false;
		if(isKey) {
			if(other.key != key)
				return false;
			if(other.value != value)
				return false;
		}
		else {
			if(other.line != line)
				return false;
		}
		return true;
	}

	void write(WriteFile& file) {
		if(isKey && value.length != 0) {
			file.indent(indent);
			file.writeKeyValue(key, value);
			file.deindent(indent);
		}
		else
			file.writeLine(toString());
	}

	string toString() const {
		string str;
		if(!isEmpty || comment.length != 0) {
			for(uint i = 0; i < indent; ++i)
				str += "\t";
		}
		if(!isEmpty) {
			if(isKey) {
				str += key+":";
				if(value.length != 0)
					str += " "+value;
			}
			else
				str += line;
		}
		if(comment.length != 0) {
			if(str.length != 0 && !isEmpty)
				str += " ";
			str += "//"+comment;
		}
		return str;
	}
};
