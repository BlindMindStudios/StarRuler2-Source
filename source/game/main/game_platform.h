#pragma once
#include <string>
#include <stdint.h>
#include <vector>

enum ServerAccess {
	SA_Public,
	SA_Friends,
	SA_Private,
};

struct QueueType {
	std::string id;
};

struct CloudDownload {
	unsigned long long id;
	std::string path;
};

struct OwnedItem {
	long long uid, type;
};

//GamePlatform
//Defines various interactions with third party game services (e.g. Steam)
class GamePlatform {
public:
	GamePlatform() {}
	virtual ~GamePlatform() {}

	virtual void update() = 0;

	virtual void logException(unsigned code, void* exception, unsigned version, const char* comment) = 0;

	//Servers
	virtual void announceServer(unsigned ip4, unsigned short port, const std::string& password) = 0;
	virtual void announceDisconnect() = 0;
	virtual void inviteFriend() = 0;
	virtual std::string getLobbyConnectAddress(const std::string& lobbyID, std::string* pwd = nullptr) = 0;
	virtual uint64_t getLobby() = 0;
	virtual void joinLobby(uint64_t id) = 0;

	virtual void enterQueue(const std::string& type, unsigned players, const std::string& version) = 0;
	virtual bool inQueue() = 0;
	virtual bool queueRequest() = 0;
	virtual bool queuePlayerWait(unsigned& ready, unsigned& cap) = 0;
	virtual bool queueReady() = 0;
	virtual void leaveQueue() = 0;
	virtual void acceptQueue() = 0;
	virtual void rejectQueue() = 0;
	virtual int remainingTime() const = 0;
	virtual unsigned queueTotalPlayers() const = 0;

	//Achievements/Stats
	virtual void modStat(const std::string& id, int delta) = 0;
	virtual void modStat(const std::string& id, float delta) = 0;
	virtual bool getStat(const std::string& id, int& value) = 0;
	virtual bool getStat(const std::string& id, float& value) = 0;
	virtual bool getGlobalStat(const std::string& id, long long& value) = 0;
	virtual bool getGlobalStat(const std::string& id, double& value) = 0;
	virtual void unlockAchievement(const std::string& id) = 0;

	//Cloud Files
	virtual void addCloudFolder(const std::string& home, const std::string& folder) = 0;
	virtual void writeCloudFile(const std::string& filename, const std::string& cloudname) = 0;
	//Syncs changed files down from the cloud
	virtual void syncCloudFiles(const std::string& home) = 0;
	//Clear all files for debug purposes
	virtual void flushCloud() = 0;

	//User Generated Content
	virtual void createCloudItem(const std::string& folder) = 0;
	virtual void closeItem() = 0;
	virtual void setItemTitle(const std::string& title) = 0;
	virtual void setItemDescription(const std::string& desc) = 0;
	virtual void setItemTags(const std::vector<std::string>& tags) = 0;
	virtual void setItemVisibility() = 0;
	virtual void setItemContents(const std::string& folder) = 0;
	virtual void setItemImage(const std::string& filename) = 0;
	virtual void commitItem(const std::string& changelog) = 0;
	virtual double getUploadProgress() = 0;
	virtual bool isItemUpdating() = 0;
	virtual bool isItemActive() = 0;
	virtual unsigned long long getItemID() = 0;

	virtual bool getDownloadedItem(unsigned index, CloudDownload& download) = 0;
	virtual unsigned getDownloadedItemCount() = 0;

	virtual bool hasDLC(const std::string& dlcIdent) const = 0;

	//Sell-out API
	virtual void playtimeHeartbeat() = 0;
	virtual void rewardPlaytime() = 0;
	virtual void getOwnedItems(std::vector<OwnedItem>& ids) = 0;
	virtual void getAwardedItems(std::vector<long long>& types) = 0;
	virtual bool hasItem(long long typeID) = 0;

	//Friends
	virtual std::string getNickname() = 0;
	virtual void openURL(const std::string& url) = 0;

#ifndef NSTEAM
	static GamePlatform* acquireSteam();
#endif
};
