extends SceneTree
func _init():
	var spec = ShipAssembler.SPECIAL_SHIPS[0]
	var r = ShipAssembler.generate_recipe(spec["role"], hash(str(spec["name"])), spec["hull"])
	var engines = []
	var weapons = []
	for p in r["parts"]:
		if p["cat"]=="engines": engines.append(p["stem"])
		elif p["cat"]=="weapons": weapons.append(p["stem"])
	print("SPECIAL hull=", r["hull"], " engines=", engines, " weapons=", weapons)
	quit()
