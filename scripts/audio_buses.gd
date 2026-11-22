extends RefCounted
## Shared helper: makes sure the "SFX" and "Ambient" audio buses exist and sets their volume.

const SFX := "SFX"
const AMBIENT := "Ambient"
const BRIEFING := "Briefing"


static func ensure() -> void:
	for bus_name in [SFX, AMBIENT, BRIEFING]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


## key: "master", "sfx" or "ambient"; linear: 0.0 .. 1.0
static func set_volume(key: String, linear: float) -> void:
	var bus_name := "Master"
	if key == "sfx":
		bus_name = SFX
	elif key == "ambient":
		bus_name = AMBIENT
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))
