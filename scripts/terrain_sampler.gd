extends RefCounted
## Reads ground height straight from the terrain's HeightMapShape3D, so gameplay code
## can put the player and enemies on the ground without doing physics queries.

var ok := false

var _data := PackedFloat32Array()
var _w := 0
var _d := 0
var _scale := Vector3.ONE
var _origin := Vector3.ZERO


func setup(collision: CollisionShape3D) -> void:
	if collision == null:
		push_warning("TerrainSampler: terrain collision node not found")
		return
	var shape := collision.shape as HeightMapShape3D
	if shape == null:
		push_warning("TerrainSampler: terrain has no HeightMapShape3D")
		return
	_data = shape.map_data
	_w = shape.map_width
	_d = shape.map_depth
	var xf := collision.global_transform
	_scale = xf.basis.get_scale()
	_origin = xf.origin
	ok = _w > 1 and _d > 1 and _data.size() == _w * _d


func height_at(wx: float, wz: float) -> float:
	if not ok:
		return 0.0
	var fx := (wx - _origin.x) / _scale.x + float(_w - 1) * 0.5
	var fz := (wz - _origin.z) / _scale.z + float(_d - 1) * 0.5
	fx = clampf(fx, 0.0, float(_w) - 1.001)
	fz = clampf(fz, 0.0, float(_d) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var ax := fx - float(ix)
	var az := fz - float(iz)
	var h00 := _data[iz * _w + ix]
	var h10 := _data[iz * _w + ix + 1]
	var h01 := _data[(iz + 1) * _w + ix]
	var h11 := _data[(iz + 1) * _w + ix + 1]
	var h := lerpf(lerpf(h00, h10, ax), lerpf(h01, h11, ax), az)
	return _origin.y + h * _scale.y
