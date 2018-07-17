#!/usr/bin/python
import os
import sys
import json
from mako.template import Template
from mako.lookup import TemplateLookup
import pprint


def main(infile, outdir):
	# Load JSON
	data = json.load(open(infile))
	tmpl = TemplateLookup(directories=["source/doc/"])
	tmpl_engine = ""
	tmpl_edata = None

	def render(template, filename, data):
		result = tmpl.get_template(template).render(
			engine = tmpl_engine,
			data = tmpl_edata,
			**data)
		with open(os.path.join(outdir, filename), "w") as fl:
			fl.write(result)

	# Render CSS
	render("template.styles.css", "styles.css", data)
	render("template.top.html", "index.html", data)

	# Output data files
	for engine, edata in data.items():
		tmpl_engine = engine
		tmpl_edata = edata
		edata["classmap"] = {c["name"] for c in edata["classes"]}
		edata["enummap"] = {e["name"] for e in edata["enums"]}

		render("template.index.html", "%s.index.html" % engine, edata)
		render("template.globals.html", "%s.globals.html" % engine, edata)
		render("template.functions.html", "%s.functions.html" % engine, edata)

		for cls in edata["classes"]:
			render("template.class.html", "%s.class.%s.html" % (engine, cls["name"]), cls)

		for en in edata["enums"]:
			render("template.enum.html", "%s.enum.%s.html" % (engine, en["name"]), en)


if __name__ == '__main__':
	infile = sys.argv[1] if len(sys.argv) >= 2 else "api_documentation.json"
	outdir = sys.argv[2] if len(sys.argv) >= 3 else "api_documentation/"
	try:
		os.makedirs(outdir)
	except:
		pass
	main(infile, outdir)

# vim: ff=unix :
