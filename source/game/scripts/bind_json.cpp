#include "rapidjson/document.h"
#include "rapidjson/writer.h"
#include "rapidjson/prettywriter.h"
#include "util/refcount.h"
#include <stdint.h>
#include <string>
#include <fstream>
#include "main/initialization.h"
#include "scripts/binds.h"
#include "files.h"
#include "threads.h"
#include "manager.h"

namespace scripts {

class StrOutputStream {
public:
	std::string value;

	StrOutputStream() {}
	void Put(char c) { value += c; }
	void Flush() {}
};

static Threaded(rapidjson::MemoryPoolAllocator<>*) allocator = 0;
rapidjson::MemoryPoolAllocator<>& getAllocator() {
	if(!allocator) {
		allocator = new rapidjson::MemoryPoolAllocator<>();
		addThreadCleanup([]() {
			delete allocator;
			allocator = 0;
		});
	}
	return *allocator;
}

class JSONTree : public AtomicRefCounted {
public:
	rapidjson::Document doc;

	void parse(const std::string& str) {
		doc.Parse<0>(str.c_str());
	}

	void readFile(const std::string& fname) {
		if(!isAccessible(fname)) {
			scripts::throwException("Cannot access file outside game or profile directories.");
			return;
		}
		doc.Parse<0>(getFileContents(fname).c_str());
	}

	void writeFile(const std::string& fname, bool pretty) {
		if(!isAccessible(fname)) {
			scripts::throwException("Cannot access file outside game or profile directories.");
			return;
		}
		
		std::fstream file(fname, std::ios_base::out);
		file << toString(pretty);
	}

	std::string toString(bool pretty) {
		StrOutputStream stream;

		if(pretty) {
			rapidjson::PrettyWriter<StrOutputStream> writer(stream);
			writer.SetIndent('\t', 1);
			doc.Accept(writer);
		}
		else {
			rapidjson::Writer<StrOutputStream> writer(stream);
			doc.Accept(writer);
		}

		return stream.value;
	}

	rapidjson::Value* root() {
		return &doc;
	}
};

static JSONTree* makeJSONTree() {
	return new JSONTree();
}

static std::string nodeString(rapidjson::Value* node) {
	if(!node->IsString()) {
		scripts::throwException("Node is not a string value.");
		return "";
	}
	return std::string(node->GetString());
}

static int nodeBool(rapidjson::Value* node) {
	if(!node->IsBool()) {
		scripts::throwException("Node is not a boolean value.");
		return 0;
	}
	return node->GetBool();
}

static int nodeInt(rapidjson::Value* node) {
	if(!node->IsInt()) {
		scripts::throwException("Node is not an int value.");
		return 0;
	}
	return node->GetInt();
}

static unsigned nodeUint(rapidjson::Value* node) {
	if(!node->IsUint()) {
		scripts::throwException("Node is not a uint value.");
		return 0;
	}
	return node->GetUint();
}

static int64_t nodeInt64(rapidjson::Value* node) {
	if(!node->IsInt64()) {
		scripts::throwException("Node is not an int64 value.");
		return 0;
	}
	return node->GetInt64();
}

static uint64_t nodeUint64(rapidjson::Value* node) {
	if(!node->IsUint64()) {
		scripts::throwException("Node is not a uint64 value.");
		return 0;
	}
	return node->GetUint64();
}

static double nodeDouble(rapidjson::Value* node) {
	if(!node->IsDouble()) {
		scripts::throwException("Node is not a double value.");
		return 0;
	}
	return node->GetDouble();
}

static double nodeNumber(rapidjson::Value* node) {
	if(node->IsDouble())
		return node->GetDouble();
	if(node->IsInt())
		return (double)node->GetInt();
	if(node->IsUint())
		return (double)node->GetUint();
	if(node->IsInt64())
		return (double)node->GetInt64();
	if(node->IsUint64())
		return (double)node->GetUint64();
	scripts::throwException("Node is not a numeric value.");
	return 0;
}

static rapidjson::Value* findMember(rapidjson::Value* node, const std::string& name) {
	if(!node->IsObject()) {
		scripts::throwException("Node is not an object.");
		return 0;
	}
	rapidjson::Value::Member* mem = node->FindMember(name.c_str());
	if(!mem)
		return 0;
	return &mem->value;
}

static void removeMember(rapidjson::Value* node, const std::string& name) {
	if(!node->IsObject()) {
		scripts::throwException("Node is not an object.");
		return;
	}

	node->RemoveMember(name.c_str());
}

static rapidjson::Value* getMember(rapidjson::Value* node, const std::string& name) {
	if(!node->IsObject()) {
		scripts::throwException("Node is not an object.");
		return 0;
	}
	rapidjson::Value::Member* mem = node->FindMember(name.c_str());
	if(mem)
		return &mem->value;
	rapidjson::Value nullValue;
	node->AddMember(name.c_str(), getAllocator(), nullValue, getAllocator());
	return findMember(node, name);
}

static void clearItems(rapidjson::Value* node) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return;
	}
	node->Clear();
}

static rapidjson::Value* getItem(rapidjson::Value* node, unsigned index) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return 0;
	}
	if(index >= node->Size()) {
		scripts::throwException("Index out of bounds.");
		return 0;
	}
	return &(*node)[index];
}

static unsigned arrSize(rapidjson::Value* node) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return 0;
	}
	return node->Size();
}

static void arrReserve(rapidjson::Value* node, unsigned amount) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return;
	}
	node->Reserve(amount, getAllocator());
}

static rapidjson::Value* arrPush(rapidjson::Value* node) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return 0;
	}
	rapidjson::Value nullValue;
	node->PushBack(nullValue, getAllocator());
	return &(*node)[node->Size() - 1];
}

static void arrPop(rapidjson::Value* node) {
	if(!node->IsArray()) {
		scripts::throwException("Node is not an array.");
		return;
	}
	node->PopBack();
}

static rapidjson::Value* setString(rapidjson::Value* node, const std::string& value) {
	node->SetString(value.c_str(), value.size(), getAllocator());
	return node;
}

void RegisterJSONBinds() {
	ClassBind node("JSONNode", asOBJ_REF | asOBJ_NOCOUNT);
	classdoc(node, "A node within a json tree. Careful when holding references, as"
			" changes to the tree can invalidate them.");

	//* Tree methods *//
	ClassBind tree("JSONTree", asOBJ_REF);
	classdoc(tree, "Represents a tree of json nodes that can be altered."
		" Please make note that JSONNode@ references are not reference counted,"
		" and can be invalidated by changes to the tree. Do not hold references"
		" unless you know what you're doing.");
	tree.addFactory("JSONTree@ f()", asFUNCTION(makeJSONTree));
	tree.setReferenceFuncs(asMETHOD(JSONTree, grab), asMETHOD(JSONTree, drop));

	tree.addMethod("void parse(const string& data)", asMETHOD(JSONTree, parse))
		doc("Parse a json tree from string data.", "Data string to parse.");

	tree.addMethod("void readFile(const string& filename)", asMETHOD(JSONTree, readFile))
		doc("Read a json tree from a file.", "Filename of the file to read from.");

	tree.addMethod("string toString(bool pretty = false)", asMETHOD(JSONTree, toString))
		doc("Dump the json tree to a string.",
				"Whether to pretty-print with newlines and indentation.",
			"Output data string.");

	tree.addMethod("void writeFile(const string& filename, bool pretty = false)",
			asMETHOD(JSONTree, writeFile))
		doc("Write a json tree to a file.", "Filename of the file to write to.",
				"Whether to pretty-print with newlines and indentation.");

	tree.addMethod("JSONNode@ get_root()", asMETHOD(JSONTree, root))
		doc("", "The root json node in this tree.");


	//* Node methods *//
	node.addMethod("bool isNull()", asMETHOD(rapidjson::Value, IsNull))
		doc("", "Whether the node is a null.");

	node.addMethod("bool isFalse()", asMETHOD(rapidjson::Value, IsFalse))
		doc("", "Whether the node is a false.");

	node.addMethod("bool isTrue()", asMETHOD(rapidjson::Value, IsTrue))
		doc("", "Whether the node is a true.");

	node.addMethod("bool isBool()", asMETHOD(rapidjson::Value, IsBool))
		doc("", "Whether the node is a boolean value (true or false).");

	node.addMethod("bool isObject()", asMETHOD(rapidjson::Value, IsObject))
		doc("", "Whether the node is an object / mapping.");

	node.addMethod("bool isArray()", asMETHOD(rapidjson::Value, IsArray))
		doc("", "Whether the node is an array.");

	node.addMethod("bool isNumber()", asMETHOD(rapidjson::Value, IsNumber))
		doc("", "Whether the node is a numerical type.");

	node.addMethod("bool isInt()", asMETHOD(rapidjson::Value, IsInt))
		doc("", "Whether the node is an integer.");

	node.addMethod("bool isUint()", asMETHOD(rapidjson::Value, IsUint))
		doc("", "Whether the node is an unsigned integer.");

	node.addMethod("bool isInt64()", asMETHOD(rapidjson::Value, IsInt64))
		doc("", "Whether the node is an long integer.");

	node.addMethod("bool isUint64()", asMETHOD(rapidjson::Value, IsUint64))
		doc("", "Whether the node is an long unsigned integer.");

	node.addMethod("bool isDouble()", asMETHOD(rapidjson::Value, IsDouble))
		doc("", "Whether the node is a double.");

	node.addMethod("bool isString()", asMETHOD(rapidjson::Value, IsString))
		doc("", "Whether the node is a string.");


	node.addMethod("JSONNode& setNull()", asMETHOD(rapidjson::Value, SetNull))
		doc("Set this node to a null value.", "This node.");

	node.addMethod("JSONNode& setBool(bool value)",
			asMETHOD(rapidjson::Value, SetBool))
		doc("Set this node to a boolean value.",
				"Boolean value to set to.",
				"This node.");

	node.addMethod("JSONNode& makeArray()",
			asMETHOD(rapidjson::Value, SetArray))
		doc("Set this node to be an array.",
				"This node.");

	node.addMethod("JSONNode& makeObject()",
			asMETHOD(rapidjson::Value, SetObject))
		doc("Set this node to be an object.",
				"This node.");

	node.addMethod("JSONNode& setInt(int value)",
			asMETHOD(rapidjson::Value, SetInt))
		doc("Set this node to an int value.",
				"Integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& setUint(uint value)",
			asMETHOD(rapidjson::Value, SetUint))
		doc("Set this node to an unsigned int value.",
				"Unsigned integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& setInt64(int64 value)",
			asMETHOD(rapidjson::Value, SetInt64))
		doc("Set this node to a long int value.",
				"Long integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& setUint64(uint64 value)",
			asMETHOD(rapidjson::Value, SetUint64))
		doc("Set this node to a long unsigned int value.",
				"Long unsigned integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& setDouble(double value)",
			asMETHOD(rapidjson::Value, SetDouble))
		doc("Set this node to a double value.",
				"Double value to set to.",
				"This node.");

	node.addExternMethod("JSONNode& setString(const string&in value)",
			asFUNCTION(setString))
		doc("Set this node to a string value.",
				"String value to set to.",
				"This node.");

	node.addMethod("JSONNode& opAssign(int value)",
			asMETHOD(rapidjson::Value, SetInt))
		doc("Set this node to an int value.",
				"Integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& opAssign(uint value)",
			asMETHOD(rapidjson::Value, SetUint))
		doc("Set this node to an unsigned int value.",
				"Unsigned integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& opAssign(int64 value)",
			asMETHOD(rapidjson::Value, SetInt64))
		doc("Set this node to a long int value.",
				"Long integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& opAssign(uint64 value)",
			asMETHOD(rapidjson::Value, SetUint64))
		doc("Set this node to a long unsigned int value.",
				"Long unsigned integer value to set to.",
				"This node.");

	node.addMethod("JSONNode& opAssign(double value)",
			asMETHOD(rapidjson::Value, SetDouble))
		doc("Set this node to a double value.",
				"Double value to set to.",
				"This node.");

	node.addExternMethod("JSONNode& opAssign(const string&in value)",
			asFUNCTION(setString))
		doc("Set this node to a string value.",
				"String value to set to.",
				"This node.");


	node.addExternMethod("string getString()", asFUNCTION(nodeString))
		doc("", "The string value of the node.");

	node.addExternMethod("bool getBool()", asFUNCTION(nodeBool))
		doc("", "The boolean value of the node.");

	node.addExternMethod("int getInt()", asFUNCTION(nodeInt))
		doc("", "The integer value of the node.");

	node.addExternMethod("uint getUint()", asFUNCTION(nodeUint))
		doc("", "The unsigned integer value of the node.");

	node.addExternMethod("int64 getInt64()", asFUNCTION(nodeInt64))
		doc("", "The long integer value of the node.");

	node.addExternMethod("uint64 getUint64()", asFUNCTION(nodeUint64))
		doc("", "The long unsigned integer value of the node.");

	node.addExternMethod("double getDouble()", asFUNCTION(nodeDouble))
		doc("", "The double value of the node.");

	node.addExternMethod("double getNumber()", asFUNCTION(nodeNumber))
		doc("", "The numeric value of the node.");


	node.addExternMethod("JSONNode@ findMember(const string& name)",
			asFUNCTION(findMember))
		doc("Retrieve a member node from an object.",
				"The name of the member.",
			"Reference to the member node. Null if it does not exist.");

	node.addExternMethod("JSONNode@ getMember(const string& name)",
			asFUNCTION(getMember))
		doc("Retrieve a member node from an object, creating it if it does not exist.",
				"The name of the member.",
			"Reference to the member node, can be a newly created null node.");

	node.addExternMethod("JSONNode@ opIndex(const string& name)",
			asFUNCTION(getMember))
		doc("Retrieve a member node from an object, creating it if it does not exist.",
				"The name of the member.",
			"Reference to the member node, can be a newly created null node.");

	node.addExternMethod("void removeMember(const string& name)", asFUNCTION(removeMember))
		doc("Remove a member from an object.", "Name of the member to remove.");


	node.addExternMethod("void clearItems()", asFUNCTION(clearItems))
		doc("Clear all items from an array node.");

	node.addExternMethod("JSONNode@ getItem(uint index)", asFUNCTION(getItem))
		doc("Get an item from an array node.", "Index of the item.",
			"Node at the specified index in the array.");

	node.addExternMethod("JSONNode@ opIndex(uint index)", asFUNCTION(getItem))
		doc("Get an item from an array node.", "Index of the item.",
			"Node at the specified index in the array.");

	node.addExternMethod("uint size()", asFUNCTION(arrSize))
		doc("", "The size of the array node.");

	node.addExternMethod("void reserve(uint amount)", asFUNCTION(arrReserve))
		doc("Reserve an array node to hold an amount of items.",
			"Amount of items to reserve for.");

	node.addExternMethod("JSONNode@ pushBack()", asFUNCTION(arrPush))
		doc("Add a new node to the end of an array node.",
			"Newly created null node.");

	node.addExternMethod("void popBack()", asFUNCTION(arrPop))
		doc("Remove a node from the end of an array node.");
}

};
