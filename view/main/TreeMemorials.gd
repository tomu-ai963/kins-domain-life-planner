extends RefCounted

# ── 記念樹: 木のそばの Y で名前とメモを付ける画面・歳時記の行・木のそばの 1 行の文言(2026-11-23) ──
# Main が 1 つ持ち(Main.tree_memorials)、main を通して world・HUD を使う。ルールは logic/Memorials.gd
const MainScript = preload("res://Main.gd")
const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

var main: MainScript
var world: GameWorld:
	get:
		return main.world
var hud: Node:
	get:
		return main.get_node("HUD")

var _tree_id := 0  # 画面を開いている木の番号

func _init(m: MainScript) -> void:
	main = m

# Y: そばに木があれば記念樹の画面、なければ自分と家族の名前の画面
func open_names() -> void:
	var f := world.forest
	var i: int = f.nearest_index(main.player_pos(), main.REACH, "")
	if i < 0:
		main.family_talk._open_family_names()
		return
	var tree: Dictionary = f.trees[i]
	if not f.is_established(tree):
		hud.show_message("芽が出てから名前を付けられる(芽が出るかは、まいた次の日に分かる)")
		return
	_tree_id = int(tree.id)
	var r: Dictionary = world.memorials.record_for(tree)
	main.get_node("Player").set_physics_process(false)  # 名前を打つあいだは歩かない
	hud.open_tree_memorial(tree_info(tree), r.get("name", ""), r.get("note", ""), chronicle_lines())

# 画面の上に出す木の 1 行: 「コナラ  2026/11/20 に植えた(植えて 3 日)」
func tree_info(tree: Dictionary) -> String:
	var f := world.forest
	var planted := Forest.date_of_day(f.planted_day(tree))
	return "%s  %s に植えた(%s)" % [_species_name(str(tree.species)), _date(planted), _planted_days(planted)]

# 歳時記の行(日付の順。同じ日は記念樹が先)。「2026/11/23  コナラ「長男の木」 春の朝、みんなで植えた」。なくなった木は日付を足す
# 暮らしの節目(2026-11-26)も混ぜる: 「2026/11/26  家族ではじめての夕食  ジャム(アリョーナ・ワーニャと)」
func chronicle_lines() -> PackedStringArray:
	var rows := []  # [日付, 順番, 行]
	for r in world.memorials.records:
		var line := "%s  %s「%s」" % [_date(r.named_on), _species_name(r.species), r.name]
		if r.note != "":
			line += "  " + r.note
		if r.gone_on != "":
			line += "(%s になくなった)" % _date(r.gone_on)
		rows.append([r.named_on, rows.size(), line])
	for e in world.memorials.events:
		rows.append([e.on, rows.size(), event_line(e)])
	rows.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return PackedStringArray(rows.map(func(r): return r[2]))

# 節目の 1 行
static func event_line(e: Dictionary) -> String:
	var line := "%s  家族ではじめての夕食" % _date(e.on)
	if str(e.food) != "":
		line += "  " + str(e.food)
	if not e.people.is_empty():
		line += "(%sと)" % "・".join(PackedStringArray(e.people))
	return line

func _on_tree_named(tree_name: String, note: String) -> void:
	main.get_node("Player").set_physics_process(true)
	var tree: Dictionary = world.forest.tree_by_id(_tree_id)
	if tree.is_empty():
		return
	var before: String = world.memorials.record_for(tree).get("name", "")
	var sp := _species_name(str(tree.species))
	match world.memorials.name_tree(tree, tree_name, note):
		"named":
			hud.show_message("%sを記念樹「%s」にした" % [sp, world.memorials.record_for(tree).name], 5.0)
		"renamed":
			hud.show_message("記念樹「%s」の名前とメモを付け直した" % world.memorials.record_for(tree).name, 5.0)
		"same":
			hud.show_message("記念樹はそのまま")
		"cleared":
			hud.show_message("「%s」を記念樹からはずした" % before, 5.0)
		"empty":
			hud.show_message("名前が空なので、記念樹にしなかった")
		"too_long":
			hud.show_message("名前は %d 文字まで" % world.memorials.NAME_MAX)
		"note_too_long":
			hud.show_message("メモは %d 文字まで" % world.memorials.NOTE_MAX)
		"young":
			hud.show_message("芽が出てから名前を付けられる")

func _on_closed() -> void:
	main.get_node("Player").set_physics_process(true)

# 左上に出す、そばの記念樹の 1 行。名付けて 1 年たった同じ月日は、それも出す
# 例: 「記念樹「長男の木」コナラ・植えて 3 日  春の朝、みんなで植えた」
func memorial_line() -> String:
	var near: Array = world.memorials.nearest(main.player_pos(), main.REACH)
	if near.is_empty():
		return ""
	var tree: Dictionary = near[0]
	var r: Dictionary = near[1]
	var planted := Forest.date_of_day(world.forest.planted_day(tree))
	var line := "記念樹「%s」%s・%s" % [r.name, _species_name(str(tree.species)), _planted_days(planted)]
	var years: int = world.memorials.anniversary_years(r.named_on)
	if years > 0:
		line += "・今日は名付けて %d 年の日" % years
	if r.note != "":
		line += "  " + r.note
	return line

# 伐る前の確かめの文言に足す: 記念樹なら「記念樹「長男の木」の」
func fell_prefix(tree: Dictionary) -> String:
	var r: Dictionary = world.memorials.record_for(tree)
	return "記念樹「%s」の" % r.name if not r.is_empty() else ""

func _planted_days(planted: String) -> String:
	var days: int = world.memorials.days_since(planted)
	return "今日植えた" if days <= 0 else "植えて %d 日" % days

static func _species_name(sp: String) -> String:
	return Forest.SPECIES[sp].name if Forest.SPECIES.has(sp) else "木"

static func _date(d: String) -> String:
	return d.replace("-", "/")
