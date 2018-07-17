#section client
int uploadStage = 0;
uint uploadPercent = 0;

string title, description, contentFolder, imagePath, changelog;
array<string> tags;

void tick(double t) {
	switch(uploadStage) {
		case 1:
			if(cloud::isActive) {
				print("Attempting to create or update cloud item");
				cloud::prepItem(contentFolder);
				uploadStage = 2;
			}
			break;
		case 2:
			if(cloud::itemReady) {
				uploadStage = 3;
				print("Updating cloud item " + cloud::itemID);
				cloud::itemTitle = title;
				cloud::itemDescription = description;
				cloud::setItemContent(contentFolder);
				cloud::setItemImage(imagePath);
				cloud::setItemTags(tags);
				cloud::setItemPublic();
				cloud::commitItem(changelog);
				uploadPercent = 0;
			}
			break;
		case 3: {
			uint pct = uint(100.0 * cloud::uploadProgress);
			if(pct >= 100 && cloud::isUploading)
				pct = 99;
			if(pct > uploadPercent) {
				print("Upload " + pct + "%");
				uploadPercent = pct;
			}
			
			if(!cloud::isUploading) {
				cloud::closeItem();
				uploadStage = 0;
			}
			} break;
	}
}

void uploadMod(const string& name, const string& changenote = "", const array<string>& modtags = array<string>()) {
	auto@ mod = getMod(name);
	if(mod is null || uploadStage != 0)
		return;
	title = mod.name;
	description = mod.description;
	if(isLinux)
		contentFolder = mod.abspath+"/";
	else
		contentFolder = mod.abspath;
	imagePath = mod.abspath + "/logo.png";
	tags = modtags;
	if(tags.length == 0)
		tags.insertLast("Mod");
	changelog = changenote;
	uploadStage = 1;
}

#section menu
class UploadMod : ConsoleCommand {
	void execute(const string& args) {
		uploadMod(args);
	}
};

void init() {
	addConsoleCommand("upload_mod", UploadMod());
}
