#!/usr/bin/python2
import os
import sys
import time
import errno
from dulwich.repo import Repo
from dulwich.diff_tree import tree_changes
import shutil
import subprocess

SOURCE_FOLDER = "source"
SOURCE_REPO = "git@github.com:BlindMindStudios/StarRuler2.git"
DEST_FOLDER = "dest"
DEST_REPO = "git@github.com:BlindMindStudios/SR2Beta.git"
LOG_FOLDER = "log"

CURRENT_COMMIT = ""
Source = None
Dest = None

SOURCE_DIRS = ["source/game/", "source/as_addons/",
    "source/os/", "source/sound/", "source/util/",
    "source/network/"]
SOURCE_LINUX = SOURCE_DIRS + ["source/linux/"]
SOURCE_WINDOWS = SOURCE_DIRS + [
    "source/msvc10/", "source/angelscript/",
    "source/glfw/", "source/libpng/", "source/freetype2/",
    "source/linux/"]

class BuildStep(object):
    @classmethod
    def neededBy(cls, path):
        return False

    def execute(self):
        pass

    def finished(self):
        return True

    def finalize(self):
        pass

class BuildGame32(BuildStep):
    @classmethod
    def neededBy(cls, path):
        for d in SOURCE_LINUX:
            if path.startswith(d):
                return True
        return False

    def execute(self):
        #Build 32-bit version
        self.clean32 = subprocess.Popen(
            ["ARCH=32 make -f source/linux/Makefile clean_code"],
            shell=True, cwd=SOURCE_FOLDER)
        self.clean32.wait()

        self.build32 = subprocess.Popen(
            ["ARCH=32 make -f source/linux/Makefile -j3 version compile"],
            shell=True, cwd=SOURCE_FOLDER,
            stdout=open(os.path.join(LOG_FOLDER, "build32_"+CURRENT_COMMIT+".log"), "w"),
            stderr=subprocess.STDOUT)

    def finished(self):
        if self.build32.poll() == None:
            return False
        return True

    def finalize(self):
        if self.build32.returncode == 0:
            copy_stage_folder("bin/lin32")

class BuildGame64(BuildStep):
    @classmethod
    def neededBy(cls, path):
        for d in SOURCE_LINUX:
            if path.startswith(d):
                return True
        return False

    def execute(self):
        self.clean64 = subprocess.Popen(
            ["ARCH=64 make -f source/linux/Makefile clean_code"],
            shell=True, cwd=SOURCE_FOLDER)
        self.clean64.wait()

        self.build64 = subprocess.Popen(
            ["ARCH=64 make -f source/linux/Makefile -j3 version compile"],
            shell=True, cwd=SOURCE_FOLDER,
            stdout=open(os.path.join(LOG_FOLDER, "build64_"+CURRENT_COMMIT+".log"), "w"),
            stderr=subprocess.STDOUT)

    def finished(self):
        if self.build64.poll() == None:
            return False
        return True

    def finalize(self):
        if self.build64.returncode == 0:
            copy_stage_folder("bin/lin64")

class BuildAS32(BuildStep):
    @classmethod
    def neededBy(cls, path):
        if path.startswith("source/angelscript/"):
            return True
        return False

    def execute(self):
        self.build32 = subprocess.Popen(
            ["ARCH=32 make -f source/linux/Makefile -j3 angelscript"],
            shell=True, cwd=SOURCE_FOLDER,
            stdout=open(os.path.join(LOG_FOLDER, "as32_"+CURRENT_COMMIT+".log"), "w"),
            stderr=subprocess.STDOUT)
        self.build32.wait();

class BuildAS64(BuildStep):
    @classmethod
    def neededBy(cls, path):
        if path.startswith("source/angelscript/"):
            return True
        return False

    def execute(self):
        self.build64 = subprocess.Popen(
            ["ARCH=64 make -f source/linux/Makefile -j3 angelscript"],
            shell=True, cwd=SOURCE_FOLDER,
            stdout=open(os.path.join(LOG_FOLDER, "as64_"+CURRENT_COMMIT+".log"), "w"),
            stderr=subprocess.STDOUT)
        self.build64.wait();

class BuildWindows(BuildStep):
    def __init__(self):
        self.running = False

    @classmethod
    def neededBy(cls, path):
        for d in SOURCE_WINDOWS:
            if path.startswith(d):
                return True
        return False

    def execute(self):
        pass

    def finished(self):
        if not self.running:
            #Create marker file for windows build
            with open(os.path.join(SOURCE_FOLDER, "WIN_COMPILE"), "w") as f:
                f.write("BUILD");
            self.running = True
            return False

        return not os.path.exists(os.path.join(SOURCE_FOLDER, "WIN_COMPILE"))

    def finalize(self):
        #Copy over symbols
        self.syncsymbols = subprocess.Popen(
            ["rsync -tavz symbols/ bms@glacicle.org:starruler2.com/symbols/"],
            shell=True)

        #Stage all the files needed
        if os.path.exists(os.path.join(DEST_FOLDER, "Star Ruler 2.exe")):
            Dest.stage("Star Ruler 2.exe")

        for f in os.listdir(os.path.join(DEST_FOLDER, "bin/win32")):
            if f.endswith(".exe") or f.endswith(".dll"):
                Dest.stage("bin/win32/"+f)

        for f in os.listdir(os.path.join(DEST_FOLDER, "bin/win64")):
            if f.endswith(".exe") or f.endswith(".dll"):
                Dest.stage("bin/win64/"+f)

        #Rename the log to indicate the commit
        if os.path.exists(os.path.join(LOG_FOLDER, "msvc32_build.log")):
            os.rename(os.path.join(LOG_FOLDER, "msvc32_build.log"),
                    os.path.join(LOG_FOLDER, "msvc32_"+CURRENT_COMMIT+".log"))

        if os.path.exists(os.path.join(LOG_FOLDER, "msvc64_build.log")):
            os.rename(os.path.join(LOG_FOLDER, "msvc64_build.log"),
                    os.path.join(LOG_FOLDER, "msvc64_"+CURRENT_COMMIT+".log"))


BUILD_STEPS = [BuildAS32, BuildAS64, BuildGame32, BuildGame64, BuildWindows]

def publish_file(path):
    if path.startswith("source/"):
        return False
    return True

def copy(path):
    folder = os.path.dirname(path)

    #Make the target folder
    try:
        os.makedirs(os.path.join(DEST_FOLDER, folder))
    except OSError as exc:
        pass

    #Copy the file
    shutil.copy2(os.path.join(SOURCE_FOLDER, path),
                os.path.join(DEST_FOLDER, path))

def copy_stage_folder(path):
    folder = os.path.join(SOURCE_FOLDER, path)
    for root, folders, files in os.walk(folder):
        for f in files:
            fpath = os.path.join(root[len(SOURCE_FOLDER)+1:], f)
            copy(fpath)
            Dest.stage(fpath)

def setup():
    #Clone the repositories first
    #Note: This assumes source and dest are in a consistent state,
    #which is something that needs to be guaranteed manually
    if not os.path.exists(SOURCE_FOLDER):
        p = subprocess.Popen(["git", "clone", SOURCE_REPO, SOURCE_FOLDER])
        p.wait()
    if not os.path.exists(DEST_FOLDER):
        p = subprocess.Popen(["git", "clone", DEST_REPO, DEST_FOLDER])
        p.wait()
    if not os.path.exists(LOG_FOLDER):
        os.mkdir(LOG_FOLDER)

    #Prepare accessors
    global Source
    Source = Repo(SOURCE_FOLDER)
    global Dest
    Dest = Repo(DEST_FOLDER)

def updateRepo(folder):
    p = subprocess.Popen(["git", "fetch", "origin", "master"], cwd=folder)
    p.wait()

def pushRepo(folder):
    p = subprocess.Popen(["git", "push", "origin", "master"], cwd=folder)
    p.wait()

def listCommits(repo, front, back, l):
    #Find all parent commits
    if not isinstance(back, set):
        stack = [repo.commit(back)]
        back = set()

        while stack:
            c = stack.pop()
            if c.id not in back:
                back.add(c.id)
                for parent in c._get_parents():
                    stack.append(repo.commit(parent))

    #Make sure it isn't already done
    if front in back:
        return

    #Check this commit
    commit = repo.commit(front)
    l.append(commit)

    for parent in commit._get_parents():
        listCommits(repo, parent, back, l)

def switchTo(folder, commit):
    p = subprocess.Popen(["git", "reset", "--hard", commit], cwd=folder)
    p.wait()

def main():
    setup()

    while True:
        #Try to update the repo
        updateRepo(SOURCE_FOLDER)
        HEAD = Source.head();
        FETCH_HEAD = Source.ref("FETCH_HEAD")

        #Check if there are any updates
        if HEAD == FETCH_HEAD:
            time.sleep(60)
            continue

        #Build the tree of commits to build
        commits = []
        listCommits(Source, FETCH_HEAD, HEAD, commits)
        commits.reverse()
        base_tree = Source.commit(HEAD).tree

        for c in commits:
            global CURRENT_COMMIT
            CURRENT_COMMIT = c.id
            switchTo(SOURCE_FOLDER, c.id)
            print("Executing commit "+c.id)

            #Iterate through the difference tree
            diff = tree_changes(Source, base_tree, c.tree)
            steps = [False for x in BUILD_STEPS]
            for d in diff:
                #Handle deletes
                if d.type == 'delete':
                    fname = d.old.path
                    if publish_file(fname):
                        os.remove(os.path.join(DEST_FOLDER, fname))
                        Dest.stage(fname)
                    continue

                #Copy over all the files
                fname = d.new.path
                if not fname:
                    continue
                if publish_file(fname):
                    copy(fname)
                    Dest.stage(fname)
                for i, st in enumerate(BUILD_STEPS):
                    if st.neededBy(fname):
                        steps[i] = True

            #Execute all build steps
            cursteps = []
            for i, needed in enumerate(steps):
                if not needed:
                    continue
                step = BUILD_STEPS[i]()
                step.execute()
                while not step.finished():
                    time.sleep(1)
                cursteps.append(step)

            #Finalize all build steps
            for step in cursteps:
                step.finalize()

            #Set up the commit in the new repo
            Dest.do_commit(
                message=c.message+"\n\nOriginal Commit: BlindMindStudios/StarRuler2@"+c.id,
                committer=c.committer,
                author=c.author,
                commit_timestamp=c._commit_time,
                commit_timezone=c._commit_timezone,
                author_timestamp=c._author_time,
                author_timezone=c._author_timezone)

            #Set up for next
            base_tree = c.tree

            #Push this individual commit
            pushRepo(DEST_FOLDER)

if __name__ == '__main__':
        main()
# vim: ff=unix sw=4 et:
