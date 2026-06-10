class_name ArtgenLedger
extends RefCounted

## Append-only generation ledger (art/generated/ledger.jsonl, one JSON event per
## line, committed) + the fold that turns it into an in-memory index. The ledger
## is the only durable history — Recraft keeps nothing and its URLs expire.


static func append(path: String, event: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	f.store_line(JSON.stringify(event))
	f.close()


## Folds the event log into current state:
##   {"generations": {id: record}, "order": [ids, oldest first], "styles": [events]}
## Each generation record gains "state": generated|saved|discarded|error, and
## saved records carry "dest" + "dest_sha256" from their save event.
static func fold(path: String) -> Dictionary:
	var gens := {}
	var order: Array = []
	var styles: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line.is_empty():
				continue
			var ev: Variant = JSON.parse_string(line)
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			match ev.get("type", ""):
				"generation":
					var rec: Dictionary = ev.duplicate()
					rec["state"] = "generated" if ev.get("status", "ok") == "ok" else "error"
					gens[ev["id"]] = rec
					order.append(ev["id"])
				"save":
					if gens.has(ev.get("gen_id")):
						var saved: Dictionary = gens[ev["gen_id"]]
						saved["state"] = "saved"
						saved["dest"] = ev.get("dest")
						saved["dest_sha256"] = ev.get("sha256")
				"discard":
					if gens.has(ev.get("gen_id")):
						gens[ev["gen_id"]]["state"] = "discarded"
				"style_created":
					styles.append(ev)
		f.close()
	return {"generations": gens, "order": order, "styles": styles}
