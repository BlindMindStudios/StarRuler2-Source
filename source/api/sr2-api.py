#!/usr/bin/python
import flask
import datetime
import json
from flask.ext.sqlalchemy import SQLAlchemy
from sqlalchemy import text
from sqlalchemy.sql.expression import asc, desc, or_
from werkzeug.debug import DebuggedApplication
import hashlib
import os, sys
import os.path
from flask.ext.cache import Cache
from os import listdir, walk, chdir
from os.path import isdir, join

app = flask.Flask(__name__)
cache = Cache(app, config={'CACHE_TYPE':'simple'})
application = DebuggedApplication(app, True)
#app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///api.db"
app.config["SQLALCHEMY_DATABASE_URI"] = "mysql://bmssql3:4c403a47@localhost/bmssql3"
db = SQLAlchemy(app)

class Design(db.Model):
    __tablename__ = "designs"
    id = db.Column(db.Integer, primary_key=True)
    ctime = db.Column(db.DateTime, default=datetime.datetime.now)
    name = db.Column(db.String(255))
    size = db.Column(db.Float)
    data = db.Column(db.Text)
    color = db.Column(db.String(7))
    mods = db.Column(db.String(255))
    views = db.Column(db.Integer, default=0)

    voteTime = db.Column(db.DateTime)
    upvotes = db.Column(db.Integer, default=0)

    commentTime = db.Column(db.DateTime)
    commentCount = db.Column(db.Integer, default=0)

    author = db.Column(db.String(255))
    token = db.Column(db.String(255))
    description = db.Column(db.Text)

class Comment(db.Model):
    __tablename__ = "comments"
    id = db.Column(db.Integer, primary_key=True)
    design = db.Column(db.Integer, index=True)

    ctime = db.Column(db.DateTime, default=datetime.datetime.now)
    author = db.Column(db.String(255))
    token = db.Column(db.String(255))
    content = db.Column(db.Text)

class Vote(db.Model):
    __tablename__ = "votes"
    token = db.Column(db.String(255), primary_key=True, autoincrement=False)
    design = db.Column(db.Integer, primary_key=True, autoincrement=False)
    time = db.Column(db.DateTime, default=datetime.datetime.now)

def design_spec(design):
    output = {}
    output["id"] = design.id
    output["name"] = design.name
    output["size"] = design.size
    output["data"] = design.data
    output["author"] = design.author
    output["color"] = design.color
    output["description"] = design.description
    output["mods"] = design.mods
    output["ctime"] = design.ctime.strftime("%Y-%m-%d %H:%M")
    output["commentCount"] = design.commentCount
    output["upvotes"] = design.upvotes

    return output

def design_list(query, paginate=True):
    #Apply paginization
    if paginate:
        pagestart = 0
        pagelimit = 10
        if "limit" in flask.request.args:
            pagelimit = int(flask.request.args["limit"])
        if "page" in flask.request.args:
            pagestart = pagelimit * int(flask.request.args["page"])
        query = query.slice(pagestart, pagestart+pagelimit+1);

    #Unify in output
    output = []
    for d in query.all():
        output.append(design_spec(d))
    return output

@app.route("/design/<int:design_id>")
def design(design_id):
    design = Design.query.filter_by(id=design_id).first()

    if not design:
        flask.abort(404)
        return

    output = design_spec(design)

    token = flask.request.headers.get("APIToken")
    if token:
        output["hasUpvoted"] = Vote.query.filter_by(design=design.id, token=token).count() != 0
        output["isMine"] = design.token == token
    else:
        output["hasUpvoted"] = False
        output["isMine"] = False

    clist = []
    output["comments"] = clist

    comments = Comment.query.filter_by(design=design.id)
    for c in comments:
        clist.append({
            "author": c.author,
            "ctime": c.ctime.strftime("%Y-%m-%d %H:%M"),
            "content": c.content
            })

    design.views += 1
    db.session.commit()

    return json.dumps(output)

@app.route("/design/<int:design_id>/vote", methods=["POST"])
def design_vote(design_id):
    design = Design.query.filter_by(id=design_id).first()
    token = flask.request.headers.get("APIToken")

    if not design or not token:
        flask.abort(404)
        return

    if design.token == token:
        flask.abort(403)
        return

    if Vote.query.filter_by(design=design.id, token=token).count() != 0:
        flask.abort(403)
        return

    vote = Vote()
    vote.token = token
    vote.design = design.id

    design.upvotes += 1
    design.voteTime = datetime.datetime.now()

    db.session.add(vote)
    db.session.commit()

    return "{}"

@app.route("/design/<int:design_id>/comment", methods=["POST"])
def design_comment(design_id):
    design = Design.query.filter_by(id=design_id).first()
    token = flask.request.headers.get("APIToken")

    if not design or not token:
        flask.abort(404)
        return

    comment = Comment()
    comment.design = design.id
    comment.author = flask.request.form.get("author", "")
    comment.content = flask.request.form.get("content", "")
    comment.token = token

    if not comment.author or not comment.content:
        flask.abort(400)
        return

    design.commentCount += 1
    design.commentTime = datetime.datetime.now()

    db.session.add(comment)
    db.session.commit()

    return "{}"

@app.route("/design/<int:design_id>/delete", methods=["POST"])
def design_delete(design_id):
    design = Design.query.filter_by(id=design_id).first()
    token = flask.request.headers.get("APIToken")

    if not design or not token:
        flask.abort(404)
        return

    if design.token != token:
        flask.abort(403)
        return

    Vote.query.filter_by(design=design.id).delete()
    Comment.query.filter_by(design=design.id).delete()

    db.session.delete(design)
    db.session.commit()

    return "{}"

@app.route("/designs/submit", methods=["POST"])
def submit_design():
    design = Design()
    design.name = flask.request.form.get("name", "")
    design.author = flask.request.form.get("author", "")
    design.description = flask.request.form.get("description", "")
    design.data = flask.request.form.get("data", "")
    design.mods = flask.request.form.get("mods", "base")
    design.color = flask.request.form.get("color", "#ffffff")

    token = flask.request.headers.get("APIToken")
    if token:
        design.token = token

    try:
        design.size = float(flask.request.form.get("size", "0"))
    except:
        design.size = 0

    if not design.name or not design.author or not design.data or design.size < 1:
        flask.abort(400)
        return

    db.session.add(design)
    db.session.commit()
    return str(design.id)

@app.route("/designs/recent")
def designs_recent():
    q = Design.query.order_by(desc(Design.ctime))
    return json.dumps(design_list(q))

@app.route("/designs/toprated")
def designs_toprated():
    q = Design.query.order_by(desc(Design.upvotes))
    return json.dumps(design_list(q))

@app.route("/designs/search/<term>")
def designs_search(term):
    q = Design.query.filter(or_(Design.name.like("%"+term+"%"), Design.author.like("%"+term+"%")))
    return json.dumps(design_list(q))

@app.route("/designs/featured")
def designs_featured():
    featured = []
    #featured += design_list(Design.query.order_by(desc(Design.upvotes)).limit(2), paginate=False)
    featured = design_list(Design.query.order_by(desc(text("(upvotes / POW((UNIX_TIMESTAMP()-UNIX_TIMESTAMP(ctime))/60/60/24+1,1.8))"))).limit(2), paginate=False)
    featured += design_list(Design.query.order_by(desc(Design.voteTime)).limit(1), paginate=False)
    featured += design_list(Design.query.order_by(desc(Design.commentTime)).limit(1), paginate=False)
    featured += design_list(Design.query.order_by(desc(Design.ctime)).limit(6), paginate=False)

    output = []
    for d in featured:
        if any(x["id"] == d["id"] for x in output):
            continue
        d["description"] = d["description"] if len(d["description"]) < 120 else d["description"][0:120]
        output.append(d)
        if len(output) > 6:
            break
    return json.dumps(output)

@app.route("/updates/version")
def up_version():
    data = getVersions()
    return data["latest"]

@app.route("/updates/latest")
def latest_list():
    data = getVersions()
    VERSIONS = data["versions"]
    LATEST_VERSION = data["latest"]
    NEW_HASHES = data["new_hashes"]

    if LATEST_VERSION not in VERSIONS:
        return "Invalid latest version: "+LATEST_VERSION
    ver = VERSIONS[LATEST_VERSION]
    output = ""
    for relfile, filehash in ver["files"].items():
        output += relfile+"\t"+filehash+"\n"
    return output

@app.route("/updates/<prevhash>/<newhash>")
def get_file(prevhash, newhash):
    if prevhash == newhash:
        return ""
    data = getVersions()
    VERSIONS = data["versions"]
    LATEST_VERSION = data["latest"]
    NEW_HASHES = data["new_hashes"]

    newfname = ""
    relname = ""
    oldfname = ""
    oldrelname = ""
    for vname, ver in VERSIONS.items():
        if newhash in ver["hashes"]:
            relname = ver["hashes"][newhash]
            newfname = join("updates", vname, relname)
        if prevhash in ver["hashes"]:
            oldrelname = ver["hashes"][prevhash]
            oldfname = join("updates", vname, relname)

    if oldrelname != relname:
        havefile = True
        for vname, ver in VERSIONS.items():
            if relname not in ver["files"]:
                havefile = False
                break

        if havefile or prevhash not in NEW_HASHES:
            flask.abort(404)
            return "INVALID PREVIOUS HASH GIVEN"

    if not os.path.exists(newfname):
        flask.abort(404)
        return "FILE NOT FOUND"

    bsize = 65536
    def generate():
        with open(newfname, 'rb') as newfile:
            buf = newfile.read(bsize)
            while len(buf) > 0:
                yield buf
                buf = newfile.read(bsize)

    return flask.Response(generate(), mimetype='application/octet-stream')

@cache.memoize()
def getVersions():
    output = {"latest": "v1.0.0", "versions": {}, "new_hashes": set(), "new_files": {"Star Ruler 2.exe"}}
    dirlist = listdir("updates")
    for f in dirlist:
        prefix = join("updates", f)
        if not isdir(prefix):
            continue
        ver = {"hashes": {}, "files": {}}
        output["versions"][f] = ver
        for (dirpath, dirnames, filenames) in walk(prefix):
            for fname in filenames:
                absfile = join(dirpath, fname)
                relfile = absfile[len(prefix)+1:]
                filehash = hashfile(absfile)
                ver["hashes"][filehash] = relfile
                ver["files"][relfile] = filehash

                if relfile in output["new_files"]:
                    output["new_hashes"].add(filehash)
    with open("updates/latest") as f:
        output["latest"] = f.read().strip()
    if output["latest"] in output["versions"]:
        latest = output["versions"][output["latest"]]
        for vname, ver in output["versions"].items():
            if vname == output["latest"]:
                continue
            for f in ver["files"]:
                if f not in latest["files"]:
                    latest["files"][f] = "0"*32
    return output


def hashfile(fname):
    hasher = hashlib.md5()
    bsize = 65536
    with open(fname, 'rb') as f:
        buf = f.read(bsize)
        while len(buf) > 0:
            hasher.update(buf)
            buf = f.read(bsize)
    return hasher.hexdigest()

if __name__ == "__main__":
    #db.create_all()
    #app.run(debug=True)
    app.run(host="0.0.0.0", port=2041, debug=True)

# vim: ff=unix et sw=4 :
