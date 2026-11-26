extends Node3D

# ── シイタケのほだ木の見た目(2026-11-26) ───────────────────────────
# 林の日陰に、コナラ・クヌギの丸太を 2 本の枕木の上に寝かせる。種駒を打った白い点が並び、生えたシイタケは茶色の傘で見せる。
# 向きは場所で決める(開き直しても同じ)。ルールは logic/Shiitake.gd
const Shiitake = preload("res://logic/Shiitake.gd")
const Look = preload("res://view/3d/Look.gd")

const RADIUS := 0.07      # 丸太の半径(m)
const REST_H := 0.06      # 枕木の高さ
const SPAWN_DOTS := 6     # 見せる種駒の数
const CAP_SHOWN_MAX := 8  # 見せるシイタケの数の上限(多いと重いので)

var shiitake: Shiitake
var _cyl := CylinderMesh.new()
var _box := BoxMesh.new()
var _ball := SphereMesh.new()
var _bark := Look.mat(Color(0.36, 0.28, 0.20))
var _cut := Look.mat(Color(0.78, 0.66, 0.46))
var _rest := Look.mat(Color(0.45, 0.34, 0.22))
var _spawn := Look.mat(Color(0.92, 0.90, 0.82))
var _cap := Look.mat(Color(0.58, 0.36, 0.20))
var _gill := Look.mat(Color(0.88, 0.82, 0.70))

func setup(s: Shiitake) -> void:
	shiitake = s
	_cyl.top_radius = 0.5
	_cyl.bottom_radius = 0.5
	_cyl.height = 1.0
	_cyl.radial_segments = 10
	_cyl.rings = 1
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 5
	shiitake.changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	Look.clear_children(self)
	for l in shiitake.logs:
		var spot := Node3D.new()
		spot.name = "Hodagi"
		spot.position = Look.at(l.pos)
		spot.rotation.y = _angle(l.pos)
		add_child(spot, true)
		_log(spot)
		var caps: int = mini(int(l.caps), CAP_SHOWN_MAX)
		for i in range(caps):
			_mushroom(spot, i, caps)

# 向き: 場所から決める(0〜180 度)
static func _angle(p: Vector2) -> float:
	return fposmod(p.x * 1.7 + p.y * 2.3, PI)

# 丸太と枕木と種駒。丸太は x の向きに寝かせる
func _log(spot: Node3D) -> void:
	var y: float = REST_H + RADIUS
	for x in [-0.3, 0.3]:
		spot.add_child(Look.mesh_node(_box, _rest, Vector3(x, REST_H * 0.5, 0), Vector3(0.06, REST_H, 0.3)))
	var body := Look.mesh_node(_cyl, _bark, Vector3(0, y, 0), Vector3(RADIUS * 2.0, Shiitake.LENGTH, RADIUS * 2.0))
	body.rotation.z = PI * 0.5
	spot.add_child(body)
	for sx in [-1.0, 1.0]:  # 切り口
		var end := Look.mesh_node(_cyl, _cut, Vector3(sx * Shiitake.LENGTH * 0.5, y, 0), Vector3(RADIUS * 1.9, 0.01, RADIUS * 1.9))
		end.rotation.z = PI * 0.5
		spot.add_child(end)
	for i in range(SPAWN_DOTS):
		var x: float = lerpf(-0.36, 0.36, float(i) / (SPAWN_DOTS - 1))
		var a: float = 0.9 if i % 2 == 0 else -0.9  # 上の左右に互い違い
		spot.add_child(Look.mesh_node(_ball, _spawn, Vector3(x, y + cos(a) * RADIUS, sin(a) * RADIUS), Vector3.ONE * 0.022))

# 生えたシイタケ: 丸太の横から、傘を外に向けて出る
func _mushroom(spot: Node3D, i: int, n: int) -> void:
	var y: float = REST_H + RADIUS
	var x: float = lerpf(-0.34, 0.34, (float(i) + 0.5) / n)
	var side: float = 1.0 if i % 2 == 0 else -1.0
	var a: float = side * (0.6 + 0.25 * float(i % 3))
	var base := Vector3(x, y + cos(a) * RADIUS, sin(a) * RADIUS)
	var out := Vector3(0, cos(a), sin(a))
	var stem_len := 0.03
	var gill := Look.mesh_node(_ball, _gill, base + out * (stem_len + 0.01), Vector3(0.085, 0.02, 0.085))
	gill.rotation.x = -a
	spot.add_child(gill)
	var cap := Look.mesh_node(_ball, _cap, base + out * (stem_len + 0.025), Vector3(0.11, 0.045, 0.11))  # 本物より少し大きく(上から見て分かるように)
	cap.rotation.x = -a
	spot.add_child(cap)
