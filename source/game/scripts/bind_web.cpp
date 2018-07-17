#include "rapidjson/document.h"
#include "scripts/binds.h"
#include "threads.h"
#include "main/references.h"
#include "util/refcount.h"
#include <curl/curl.h>
#include <sstream>
#include "str_util.h"
#include "manager.h"
#include "files.h"

#undef min

extern bool launchPatcher;

namespace scripts {

static const std::string WikiURI("http://wiki.starruler2.com/api.php?format=json&action=query&titles=$1&prop=revisions&rvprop=content");
static const std::string APIURI("http://api.starruler2.com/$1");

static threads::threadreturn threadcall CurlThread(void*);
static const std::string EMPTY_STRING("");
struct WebData : AtomicRefCounted {
	CURL* curl;
	std::string uri;
	std::string result;
	volatile bool completed;
	std::string errorStr;
	std::function<void(WebData&)> onPerform;
	std::vector<std::pair<std::string,std::string>> postData;
	std::vector<std::pair<std::string,std::string>> headers;

	WebData() : completed(true) {
		curl = curl_easy_init();
	}

	~WebData() {
		while(!completed)
			threads::sleep(10);
		curl_easy_cleanup(curl);
	}

	void request(const std::string& URI, std::function<void(WebData&)> perf = nullptr) {
		if(!completed) {
			scripts::throwException("Attempting to request WebData result before request completed.");
			return;
		}

		completed = false;
		onPerform = perf;
		uri = URI;
		threads::createThread(CurlThread, this);
	}

	bool isCompleted() {
		return completed;
	}

	bool wasError() {
		return errorStr.size() != 0;
	}

	void addPost(const std::string& name, const std::string& value) {
		if(!completed)
			return;
		postData.push_back(std::pair<std::string,std::string>(name, value));
	}

	void addHeader(const std::string& name, const std::string& value) {
		if(!completed)
			return;
		headers.push_back(std::pair<std::string,std::string>(name, value));
	}

	const std::string& getResult() {
		if(!completed) {
			scripts::throwException("Attempting to get WebData result before request completed.");
			return EMPTY_STRING;
		}

		return result;
	}

	const std::string& getError() {
		if(!completed) {
			scripts::throwException("Attempting to get WebData error before request completed.");
			return EMPTY_STRING;
		}

		return errorStr;
	}
};

WebData* makeWebData() {
	return new WebData();
}

static size_t curlOutput(void* data, size_t size, size_t nmemb, void* ptr) {
	if(!ptr)
		return size * nmemb;
	WebData& dat = *(WebData*)ptr;
	int sz = size * nmemb;
	dat.result.append((char*)data, sz);
	return sz;
}

static threads::threadreturn threadcall CurlThread(void* ptr) {
	WebData& dat = *(WebData*)ptr;
	if(dat.result.size() != 0)
		dat.result = "";

	curl_httppost* formpost = nullptr;
	curl_httppost* lastptr = nullptr;
	struct curl_slist* headers = nullptr;

	if(!dat.postData.empty()) {
		for(size_t i = 0, cnt = dat.postData.size(); i < cnt; ++i) {
			curl_formadd(&formpost, &lastptr,
				CURLFORM_COPYNAME, dat.postData[i].first.c_str(),
				CURLFORM_COPYCONTENTS, dat.postData[i].second.c_str(),
				CURLFORM_END);
		}
		dat.postData.clear();

		curl_easy_setopt(dat.curl, CURLOPT_HTTPPOST, formpost);
	}

	if(!dat.headers.empty()) {
		for(size_t i = 0, cnt = dat.headers.size(); i < cnt; ++i) {
			std::string str = dat.headers[i].first+": "+dat.headers[i].second;
			headers = curl_slist_append(headers, str.c_str());
		}
		dat.headers.clear();

		curl_easy_setopt(dat.curl, CURLOPT_HTTPHEADER, headers);
	}

	curl_easy_setopt(dat.curl, CURLOPT_URL, dat.uri.c_str());
	curl_easy_setopt(dat.curl, CURLOPT_WRITEFUNCTION, curlOutput);
	curl_easy_setopt(dat.curl, CURLOPT_WRITEHEADER, nullptr);
	curl_easy_setopt(dat.curl, CURLOPT_WRITEDATA, ptr);
	curl_easy_setopt(dat.curl, CURLOPT_FAILONERROR, 1);
	CURLcode err = curl_easy_perform(dat.curl);

	if(err == CURLE_OK) {
		if(dat.errorStr.size() != 0)
			dat.errorStr = "";
	}
	else
		dat.errorStr = curl_easy_strerror(err);

	if(dat.onPerform)
		dat.onPerform(dat);

	if(formpost)
		curl_formfree(formpost);
	if(headers)
		curl_slist_free_all(headers);
	dat.completed = true;
	return 0;
}

threads::Mutex updateLock;
threads::Signal isUpdating;
double updateProgress = 0;
int updateStatus = 0;

bool getIsUpdating() {
	return !isUpdating.check(0);
}

struct MD5 {
	unsigned bytes[4];

	MD5() : bytes() {
	}

	static unsigned endianFlip(unsigned x) {
		return (x << 24) | (x >> 24) | ((x >> 8) & 0xff00) | ((x & 0xff00) << 8);
	}

	void fromString(const std::string& str) {
		for(unsigned i = 0; i < 4; ++i) {
			std::stringstream s(str.substr(i*8, 8));
			s >> std::hex >> bytes[i];
			bytes[i] = endianFlip(bytes[i]);
		}
	}

	std::string toString() const {
		std::stringstream s;
		s.fill('0');
		s << std::hex;
		for(unsigned i = 0; i < 4; ++i) {
		s.width(8);
		s << endianFlip(bytes[i]);
		}
		return s.str();
	}

	bool zero() {
		return !bytes[0] && !bytes[1] && !bytes[2] && !bytes[3];
	}

	bool operator==(const MD5& other) const {
		return bytes[0] == other.bytes[0] && bytes[1] == other.bytes[1] && bytes[2] == other.bytes[2] && bytes[3] == other.bytes[3];
	}
};

unsigned rotLeft(unsigned value, unsigned shifts) {
    return (value << shifts) | (value >> (32-shifts));
}

MD5 hash(const std::string& filename) {
	//Note: All variables are unsigned 32 bit and wrap modulo 2^32 when calculating
	const unsigned s[64] = { 7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
						5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
						4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
						6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21 };
	const unsigned K[64] = { 0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
			  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
			  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
			  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
			  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
			  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
			  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
			  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
			  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
			  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
			  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
			  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
			  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
			  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
			  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
			  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391 };

	MD5 md5;
	unsigned& a0 = md5.bytes[0];
	unsigned& b0 = md5.bytes[1];
	unsigned& c0 = md5.bytes[2];
	unsigned& d0 = md5.bytes[3];

	FILE* file = fopen(filename.c_str(), "rb");
	if(!file)
		return md5;

	a0 = 0x67452301;
	b0 = 0xefcdab89;
	c0 = 0x98badcfe;
	d0 = 0x10325476;

	unsigned long long length = 0, pos = 0;
	unsigned chunk[16];

	int end = 0;
	while(end != 2) {
		auto bytes = fread(chunk, 1, 16*4, file);
		length += bytes;
		if(bytes < 16 * 4) {
			if(end == 0) {
				memset((char*)chunk + bytes, 0, 16*4 - bytes);
				*((unsigned char*)chunk + bytes) = 0x80;
				end = 1;
				if(bytes < 14*4) {
					length *= 8;
					memcpy(chunk + 14, &length, sizeof(length));
					end = 2;
				}
			}
			else {
				memset(chunk, 0, sizeof(chunk));
				length *= 8;
				memcpy(chunk + 14, &length, sizeof(length));
				end = 2;
			}
		}

		unsigned A = a0, B = b0, C = c0, D = d0;
		for(unsigned i = 0; i < 64; ++i) {
			unsigned F, g;
			if(i < 16) {
				F = (B & C) | (~B & D);
				g = i;
			}
			else if(i < 32) {
				F = (D & B) | (~D & C);
				g = (i*5 + 1) % 16;
			}
			else if(i < 48) {
				F = B ^ C ^ D;
				g = (i * 3 + 5) % 16;
			}
			else {
				F = C ^ (B | ~D);
				g = (i * 7) % 16;
			}

			unsigned newA = D;
			D = C;
			C = B;
			B = B + rotLeft(A + F + K[i] + chunk[g], s[i]);
			A = newA;
		}

		a0 += A;
		b0 += B;
		c0 += C;
		d0 += D;
	}

	fclose(file);

	return md5;
}

static int GameUpdate() {
	unsigned totalFiles = 0, downloaded = 0;
	const std::string profile = path_join(getProfileRoot(), "patch/");
	makeDirectory(profile);
	updateProgress = 0;
	WebData fileList;
	for(unsigned i = 0; i < 3; ++i) {
		fileList.request(format(APIURI.c_str(), "updates/latest"));

		while(!fileList.completed)
			threads::sleep(1);

		if(!fileList.wasError())
			break;
	}

	if(fileList.wasError()) {
		updateProgress = 100.0;
		updateStatus = -1;
		isUpdating.signalDown();
		return 0;
	}

	updateProgress = 1.0;

	std::unordered_map<std::string,MD5> files;

	auto anyHash = hash("Star Ruler 2.exe");

	int failures = 0;
	std::unordered_map<std::string,std::string> queuedDownloads;
	std::unordered_map<std::string,WebData*> activeDownloads;
	std::unordered_set<std::string> queuedDeletions;

	auto checkDownloads = [&](bool beginDownloads) {
		for(auto dl = activeDownloads.begin(), dlend = activeDownloads.end(); dl != dlend; ++dl) {
			auto* web = dl->second;
			if(web->completed) {
				if(web->wasError()) {
					failures += 1;
					queuedDownloads[dl->first] = web->uri;
					delete dl->second;
					activeDownloads.erase(dl);
					return;
				}
				else {
					auto patchName = profile + dl->first;
					if(FILE* file = fopen(patchName.c_str(), "wb")) {
						fwrite(dl->second->result.c_str(), 1, dl->second->result.size(), file);
						fclose(file);
					}
					downloaded += 1;
					delete dl->second;
					activeDownloads.erase(dl);
					return;
				}
			}
		}

		if(beginDownloads && activeDownloads.size() < 3 && !queuedDownloads.empty()) {
			auto f = queuedDownloads.begin();
			auto* web = new WebData();
			web->request(f->second);
			activeDownloads[f->first] = web;
			queuedDownloads.erase(f);
		}
	};

	auto queueDownload = [&](const std::string& relpath, MD5 current, MD5 updated) {
		if(updated.zero()) {
			queuedDeletions.insert(relpath);
			return;
		}

		if(fileExists(profile + relpath)) {
			auto md5 = hash(profile + relpath);
			if(md5 == updated)
				return;
			remove((profile + relpath).c_str());
		}

		{
			std::vector<std::string> paths;
			path_split(relpath, paths);

			std::string path = profile;
			for(unsigned i = 0, cnt = paths.size(); i + 1 < cnt; ++i) {
				path += paths[i] + "/";
				makeDirectory(path);
			}
		}

		totalFiles += 1;
		auto uri = format("http://api.starruler2.com/updates/$1/$2", current.toString(), updated.toString());
		queuedDownloads[relpath] = uri;
		checkDownloads(true);
	};

	std::stringstream list(fileList.result);
	std::string line, key, value;
	//Line Format: relative_path<tab>md5_hash
	while(!list.eof()) {
		std::getline(list, line);
		if(!splitKeyValue(line, key, value, "\t"))
			continue;
		if(value.size() == 32) {
			MD5 md5;
			md5.fromString(value);
			files[key] = md5;
		}
	}

	//Clear out any unnecessary files from the patch folder
	std::function<void(const std::string&)> clearFolder;
	clearFolder = [&](const std::string& relPath) {
		std::vector<std::string> listing;
		if(listDirectory(profile + relPath, listing)) {
			for(auto f = listing.begin(), fend = listing.end(); f != fend; ++f) {
				auto path = path_join(profile, *f);
				if(isDirectory(path)) {
					clearFolder(relPath + *f + "/");
				}
				else {
					auto fExists = files.find(relPath + *f);
					if(fExists == files.end() || fExists->second.zero())
						remove(path.c_str());
				}
			}
		}
	};

	clearFolder("");

	unsigned hashedFiles = 0;

	updateProgress = 5.0;
	//Calculate the hashes of all listed files, and queue the download if they need to be updated
	for(auto f = files.begin(), fend = files.end(); f != fend; ++f) {
		auto md5 = hash(f->first);
		++hashedFiles;

		if(md5.zero()) {
			if(f->second.zero())
				continue;
			md5 = anyHash;
		}
		updateProgress = 5.0 + 45.0 * std::min(1.0, (double)hashedFiles / 2000.0) + 45.0 * (double)downloaded / (double)totalFiles;
		if(md5 == f->second)
			continue;
		queueDownload(f->first, md5, f->second);
	}

	while((!queuedDownloads.empty() || !activeDownloads.empty()) && failures < 25) {
		checkDownloads(true);
		if(totalFiles > 0)
			updateProgress = 50.0 + 45.0 * (double)downloaded / (double)totalFiles;
		threads::sleep(1);
	}

	while(!activeDownloads.empty()) {
		checkDownloads(false);
		if(totalFiles > 0)
			updateProgress = 50.0 + 45.0 * (double)downloaded / (double)totalFiles;
		threads::sleep(1);
	}

	updateProgress = 95.0;

	if(!queuedDownloads.empty()) {
		updateStatus = -1;
		isUpdating.signalDown();
		return 0;
	}

	//Delete queued files
	if(!queuedDeletions.empty()) {
		std::ofstream deletions(profile + ".delete.txt", std::ios_base::out);
		for(auto f = queuedDeletions.begin(), fend = queuedDeletions.end(); f != fend; ++f)
			deletions << *f << std::endl;
		deletions.flush();
		deletions.close();
	}

	//Queue patcher execution and shut down the game
	launchPatcher = true;

	updateProgress = 100.0;
	updateStatus = 1;
	isUpdating.signalDown();
	return 0;
}

void updateGame() {
	threads::Lock lock(updateLock);
	if(isUpdating.check(0)) {
		isUpdating.signalUp();
		updateStatus = 0;
		threads::async(GameUpdate);
	}
}
std::string formatURI(const std::string& uri, std::string param) {
	return replaced(format(uri.c_str(),
				replaced(param, "&", "&amp;")),
			" ", "%20");
}

bool intoMember(WebData& dat, rapidjson::Value*& node, const char* name) {
	if(!node->IsObject()) {
		dat.errorStr = "Invalid json output. Not an object. "+toString(node->GetType());
		return false;
	}
	rapidjson::Value::Member* mem = node->FindMember(name);
	if(!mem) {
		dat.errorStr = "Invalid json output. No member "+std::string(name);
		return false;
	}
	node = &mem->value;
	return true;
}

bool intoMemberNum(WebData& dat, rapidjson::Value*& node, unsigned ind) {
	if(!node->IsObject()) {
		dat.errorStr = "Invalid json output. Not an object.";
		return false;
	}
	auto it = node->MemberBegin();
	while(ind-- && it != node->MemberEnd())
		++it;
	if(it == node->MemberEnd()) {
		dat.errorStr = "Invalid json output.";
		return false;
	}

	node = &it->value;
	return true;
}

bool intoArray(WebData& dat, rapidjson::Value*& node, unsigned ind) {
	if(!node->IsArray()) {
		dat.errorStr = "Invalid json output. Not an array.";
		return false;
	}
	if(ind >= node->Size()) {
		dat.errorStr = "Invalid json output.";
		return false;
	}

	node = &(*node)[ind];
	return true;
}

void WikiJSON(WebData& dat) {
	if(dat.wasError())
		return;

	rapidjson::Document doc;
	doc.Parse<0>(dat.result.c_str());

	rapidjson::Value* cursor = &doc;
	if(!intoMember(dat, cursor, "query"))
		return;
	if(!intoMember(dat, cursor, "pages"))
		return;
	if(!intoMemberNum(dat, cursor, 0))
		return;
	if(!intoMember(dat, cursor, "revisions"))
		return;
	if(!intoArray(dat, cursor, 0))
		return;
	if(!intoMember(dat, cursor, "*"))
		return;

	if(!cursor->IsString()) {
		dat.errorStr = "Invalid json output.";
		return;
	}

	dat.result = cursor->GetString();
}

static void getWikiPage(const std::string& title, WebData& dat) {
	std::string uri = formatURI(WikiURI, title);
	dat.request(uri, WikiJSON);
}

static void webAPICall(const std::string& page, WebData& dat) {
	std::string uri = format(APIURI.c_str(), replaced(page, " ", "%20"));

	auto* token = devices.settings.engine.getSetting("sAPIToken");
	if(token)
		dat.addHeader("APIToken", token->toString());

	dat.request(uri);
}

void RegisterWebBinds() {
	ClassBind wd("WebData", asOBJ_REF);
	classdoc(wd, "Can be used to do requests to data located on the web.");

	wd.addFactory("WebData@ f()", asFUNCTION(makeWebData));
	wd.setReferenceFuncs(asMETHOD(WebData, grab), asMETHOD(WebData, drop));

	wd.addMethod("bool get_completed()", asMETHOD(WebData, isCompleted))
		doc("", "Whether the request that was given has completed yet.");
	wd.addMethod("bool get_error()", asMETHOD(WebData, wasError))
		doc("", "Whether the request ended in an error.");
	wd.addMethod("const string& get_result()", asMETHOD(WebData, getResult))
		doc("", "The result data from the request.");
	wd.addMethod("const string& get_errorStr()", asMETHOD(WebData, getError))
		doc("", "The error that was encountered.");
	wd.addMethod("void addPost(const string& name, const string& data)", asMETHOD(WebData, addPost))
		doc("Add a post parameter to the request.", "Parameter name.", "Parameter data.");

	bind("void getWikiPage(const string&in title, WebData& dat)", asFUNCTION(getWikiPage))
		doc("Load the contents of a page from the wiki.", "Wiki page title to load.",
			"WebData to use for the loading.");

	bind("void webAPICall(const string& page, WebData& dat)", asFUNCTION(webAPICall))
		doc("Make a call to the web API to get data.", "API page to call.", "WebData to use for the loading.");

	bind("void updateGame()", asFUNCTION(updateGame));
	bind("bool get_updating()", asFUNCTION(getIsUpdating));
	bindGlobal("int updateStatus", &updateStatus);
	bindGlobal("double updateProgress", &updateProgress);
}

};
