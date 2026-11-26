extends RefCounted

# ── 原木シイタケ: 0 でほだ木を置く・E で採る・そばの 1 行・日記の行の文言(2026-11-26) ──────────
# Main が 1 つ持ち(Main.shiitake_work)、main を通して world・HUD を使う。ルールは logic/Shiitake.gd
const MainScript = preload("res://Main.gd")
const GameWorld = preload("res://logic/GameWorld.gd")
const Shiitake = preload("res://logic/Shiitake.gd")

# 置けないときの文言(Shiitake.place の結果)。木を植えられない場所の理由は SPOT_NAMES で「…の近くには置けない」にする
const PLACE_MESSAGES := {
	"too_many": "ほだ木は%d本まで",
	"no_log": "コナラかクヌギの丸太がいる(自分で育てた木を Z で伐る。市場の丸太や、ほかの木の丸太は原木にならない)",
	"no_spawn": "シイタケの種駒がない(市場で買える。1袋で原木1本)",
	"preview": "未来のプレビュー中は置けない",
	"no_shade": "日なたには置けない(育った木の枝の下の、日陰に置く)",
	"trunk": "幹に近すぎる(少し離れた、枝の下に置く)",
	"near_log": "ほかのほだ木に近すぎる",
	"outside": "一族の土地の外には置けない",
	"plot": "菜園の区画には置けない",
	"pond": "池の近くには置けない",
}
const SPOT_NAMES := {"cabin": "小屋", "hive": "巣箱", "feeder": "餌台", "well": "井戸", "mill": "石臼", "tent": "テント", "yard": "小屋の東の庭"}

var main: MainScript
var world: GameWorld:
	get:
		return main.world
var hud: Node:
	get:
		return main.get_node("HUD")

func _init(m: MainScript) -> void:
	main = m

# 0: 足元にほだ木を置く(コナラ・クヌギの丸太 1 本に種駒 1 袋を打ち込む)
func place() -> void:
	var s := world.shiitake
	var pos: Vector2 = main.player_pos()
	var result: String = s.place(pos)
	if result == "placed":
		main._act("build", pos)
		hud.show_message("コナラ・クヌギの丸太に種駒を打ち込んで、林の日陰に置いた(ほだ木 %d/%d本)。菌が回るまで %d日。そのあと春と秋、雨の翌日に生えやすい" % [s.logs.size(), s.MAX_LOGS, s.SPAWN_DAYS], 7.0)
		return
	hud.show_message(place_message(result))

static func place_message(result: String) -> String:
	if result == "too_many":
		return PLACE_MESSAGES.too_many % Shiitake.MAX_LOGS
	if PLACE_MESSAGES.has(result):
		return PLACE_MESSAGES[result]
	return "%sの近くには置けない" % SPOT_NAMES.get(result, "ほかの物")

# E: そばのほだ木のシイタケを採る。ほだ木がなければ false(ほかの収穫へ)。
# まだ生えていなくて、そばに実った果樹があれば、果樹のほうを採る(false)
func try_harvest(pos: Vector2) -> bool:
	var s := world.shiitake
	var l: Dictionary = s.log_near(pos)
	if l.is_empty():
		return false
	if not s.is_ready(l):
		var f := world.forest
		var i: int = f.nearest_fruit_index(pos, main.REACH)
		if i >= 0 and f.shows_fruit(f.trees[i]):
			return false
		hud.show_message("ほだ木: " + state_text(l))
		return true
	s.harvest(pos)
	main._act("pick", l.pos)
	var after := "。このほだ木は採りきって、朽ちて土に還った" if s.last_rotted > 0 else "(このほだ木から、あと %d回採れる)" % (s.FLUSHES - int(l.flushes))
	hud.show_message("シイタケを%d個採った%s。市場で1個 %d₽。ストーブで干し椎茸にもできる" % [s.last_caps, after, world.market.SELL_PRICES.shiitake], 6.0)
	return true

# ほだ木の今の様子
func state_text(l: Dictionary) -> String:
	var s := world.shiitake
	if s.is_ready(l):
		return "シイタケが %d個生えている(E で採る)" % int(l.caps)
	if not s.is_colonized(l):
		return "菌が回るまで、あと %d日" % s.days_to_colonize(l)
	if not s.is_shaded(l.pos):
		return "日陰の木がなくなって乾いている(そばに木が育つと、また生える)"
	var left := "あと %d回採れる" % (s.FLUSHES - int(l.flushes))
	if not (world.forest.season in s.SEASONS):
		return "春と秋に生える(%s)" % left
	return "春と秋、雨の翌日に生えやすい(%s)" % left

# 左上に出す、ほだ木のそば・置ける日陰の 1 行。どちらでもなければ ""
func line() -> String:
	var s := world.shiitake
	var pos: Vector2 = main.player_pos()
	var l: Dictionary = s.log_near(pos)
	if not l.is_empty():
		return "ほだ木: " + state_text(l)
	# 置ける日陰: コナラ・クヌギの丸太を持っているときだけ出す(持っていなければ、日陰のたびに出てうるさい)
	if s.logs.size() >= s.MAX_LOGS or world.cabin.oak_log_count() <= 0 or s.spot_problem(pos) != "":
		return ""
	if s.spawn <= 0:
		return "日陰: 市場でシイタケの種駒を買うと、0 でコナラ・クヌギの丸太を原木にして置ける"
	return "日陰: 0 で原木を置ける(コナラ・クヌギの丸太 %d本・種駒 %d袋)" % [world.cabin.oak_log_count(), s.spawn]

# 体のそばの札(Main.near_action)。なければ []
func near_action() -> Array:
	var text := line()
	if text.contains("(E で採る)"):
		return [KEY_E, "シイタケ"]
	if text.begins_with("日陰: 0 で"):
		return [KEY_0, "原木を置く"]
	return []

# 日記の「今日」の行
func diary_today() -> PackedStringArray:
	var lines := PackedStringArray()
	var n: int = world.shiitake.ready_count()
	if n > 0:
		lines.append("シイタケが生えているほだ木が %d本ある" % n)
	return lines

# 日記の「明日」の行: 今日が雨なら、明日は生えやすい
func diary_tomorrow() -> PackedStringArray:
	var lines := PackedStringArray()
	if world.forest.is_raining() and world.shiitake.may_sprout_tomorrow() > 0:
		lines.append("雨の翌日なので、シイタケが生えやすい(ほだ木 %d本)" % world.shiitake.may_sprout_tomorrow())
	return lines

# 朝の知らせ(日付が変わったとき)
func morning_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if world.shiitake.last_sprouted > 0:
		lines.append("ほだ木にシイタケが生えた(%d本。E で採る)" % world.shiitake.last_sprouted)
	return lines

# 持ち物の道具の行に足す: 「種駒 2袋  原木にできる丸太 1本」
func stock_text() -> String:
	var parts := PackedStringArray()
	if world.shiitake.spawn > 0:
		parts.append("種駒 %d袋" % world.shiitake.spawn)
	if world.cabin.oak_log_count() > 0:
		parts.append("原木にできる丸太 %d本" % world.cabin.oak_log_count())
	return ("  " + "  ".join(parts)) if not parts.is_empty() else ""
