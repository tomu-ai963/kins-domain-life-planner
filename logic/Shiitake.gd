extends RefCounted

# ── 原木シイタケ(描画を持たない。2026-11-26。Hermes のレビューの案 3) ──────────────
# 自分で伐ったコナラ・クヌギの丸太(Cabin.oak_log_count)を、薪にせず林の日陰に置いて「ほだ木」にする。
# 置くときに、市場で買った種駒を 1 袋打ち込む(とむ決定 2026-11-26)。
# 菌が回るまで SPAWN_DAYS 日。そのあと春と秋に、雨の翌日は生えやすく、ふだんもときどき生える(必ず生えるとはしない)。
# 生えたシイタケは採るまで残る(毎日見に行かないと失う形にはしない)。1 本で FLUSHES 回採ると朽ちて土に還る。
# 日陰の木を伐ると、乾いて生えなくなる(日陰の木を植え直せばまた生える)。
# 日数・回数・確率はゲームのために縮めた仮の数字(野菜と同じ扱い)。文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const LOG_SPECIES := Cabin.OAK_SPECIES  # 原木にできる木(コナラ・クヌギ。どちらも昔からシイタケの原木にしてきた)
const MAX_LOGS := 6         # ほだ木の数の上限
const SPAWN_DAYS := 7       # 種駒を打ってから菌が回るまでの日数
const SEASONS := ["spring", "autumn"]  # 生える季節
const RAIN_CHANCE := 0.5    # 雨の翌日に生える確率
const DRY_CHANCE := 0.1     # ふだんの日に生える確率
const FLUSHES := 6          # 1 本で採れる回数。採りきると朽ちる
const CAPS_MIN := 8         # 1 回に採れる数(個)
const CAPS_MAX := 12
const SHADE_RADIUS := 1.5   # 日陰を作れる木の樹冠の半径(m)。これより小さい木の下は日が当たる
const TRUNK_GAP := 0.6      # 幹からこれより近くには置けない
const LOG_GAP := 1.0        # ほだ木どうしの間
const REACH := 1.5          # ほだ木からこの距離までなら作業できる
const LENGTH := 0.9         # ほだ木の長さ(m。見た目と当たりの目安)
const MAX_CATCH_UP_DAYS := Forest.MAX_CATCH_UP_DAYS

var forest: Forest   # GameWorld が設定する
var cabin = null     # GameWorld が設定する(原木の丸太の持ち物は Cabin にある)
var is_blocked := Callable()  # GameWorld が設定する: (pos) -> String。区画・小屋・池などにかかれば理由、なければ ""

# [{pos: Vector2, placed_day: int, flushes: int(採った回数), caps: int(今生えている数), grew_day: int(生えた日)}]
var logs := []
var spawn := 0                  # 種駒(袋。1 袋で原木 1 本)
var stock := {"shiitake": 0}    # 採ったシイタケ(個)
var last_checked_day := 0
var last_log := {}              # 直前に作業したほだ木(文言用)
var last_rotted := 0            # 直前の収穫で朽ちたか(1 = 朽ちた。文言用)
var last_caps := 0              # 直前に採った数(文言用)
var last_sprouted := 0          # 今日の確認で生えたほだ木の数(知らせる用・保存しない)

func _commit() -> void:
	dirty.emit()
	changed.emit()

func is_ready(l: Dictionary) -> bool:
	return int(l.caps) > 0

# 菌が回ったか(置いた日から SPAWN_DAYS 日)
func is_colonized(l: Dictionary, day := -1) -> bool:
	return (day if day >= 0 else forest.day_number()) - int(l.placed_day) >= SPAWN_DAYS

func days_to_colonize(l: Dictionary) -> int:
	return maxi(0, SPAWN_DAYS - (forest.day_number() - int(l.placed_day)))

func ready_count() -> int:
	return logs.filter(func(l): return is_ready(l)).size()

# pos を日陰にしている木(育った木の樹冠の下で、幹から離れたところ)。なければ {}
func shade_tree(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for t in forest.trees:
		if not forest.is_established(t):
			continue
		var r: float = forest.radius_of(t)
		if r < SHADE_RADIUS:
			continue
		var d: float = t.pos.distance_to(pos)
		if d <= r and d < best_d:
			best_d = d
			best = t
	return best

func is_shaded(pos: Vector2) -> bool:
	return not shade_tree(pos).is_empty()

# pos から REACH 以内でいちばん近いほだ木。なければ {}
func log_near(pos: Vector2, reach := REACH) -> Dictionary:
	var best := {}
	var best_d := reach
	for l in logs:
		var d: float = l.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = l
	return best

# その場所にほだ木がかかるか(radius は調べる範囲)。区画や木・池などを置くときに見る
func covers(pos: Vector2, radius := 0.6) -> bool:
	return logs.any(func(l): return l.pos.distance_to(pos) < radius)

# 区画(中心 c)がほだ木にかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	return logs.any(func(l): return absf(l.pos.x - c.x) <= half + 0.5 and absf(l.pos.y - c.y) <= half + 0.3)

# 足元にほだ木を置ける場所か。"" なら置ける。no_shade / trunk / near_log / その他は is_blocked の理由
func spot_problem(pos: Vector2) -> String:
	if is_blocked.is_valid():
		var p: String = is_blocked.call(pos)
		if p != "":
			return p
	if not is_shaded(pos):
		return "no_shade"
	for t in forest.trees:
		if t.pos.distance_to(pos) < TRUNK_GAP:
			return "trunk"
	for l in logs:
		if l.pos.distance_to(pos) < LOG_GAP:
			return "near_log"
	return ""

# 0: 足元にほだ木を置く(コナラ・クヌギの丸太 1 本と種駒 1 袋)。
# 結果: placed / too_many / no_log(コナラ・クヌギの丸太がない) / no_spawn / preview / no_shade / trunk / near_log / is_blocked の理由
func place(pos: Vector2) -> String:
	if forest.time_offset_years > 0.0:
		return "preview"
	if logs.size() >= MAX_LOGS:
		return "too_many"
	if cabin.oak_log_count() <= 0:
		return "no_log"
	if spawn <= 0:
		return "no_spawn"
	var p := spot_problem(pos)
	if p != "":
		return p
	cabin.spend_oak_logs(1)
	spawn -= 1
	var l := {"pos": pos, "placed_day": forest.day_number(), "flushes": 0, "caps": 0, "grew_day": -1}
	logs.append(l)
	last_log = l
	if last_checked_day <= 0:
		last_checked_day = forest.day_number()
	_commit()
	return "placed"

# E: そばのほだ木のシイタケを採る。結果: harvested / growing(まだ菌が回っていない) / waiting(生えていない) / none
# 採りきったほだ木は朽ちて消える(last_rotted = 1)
func harvest(pos: Vector2) -> String:
	last_rotted = 0
	var l := log_near(pos)
	if l.is_empty():
		return "none"
	last_log = l
	if not is_ready(l):
		return "waiting" if is_colonized(l) else "growing"
	stock.shiitake = int(stock.shiitake) + int(l.caps)
	last_caps = int(l.caps)
	l.caps = 0
	l.flushes = int(l.flushes) + 1
	if int(l.flushes) >= FLUSHES:
		logs.erase(l)
		last_rotted = 1
	_commit()
	return "harvested"

# その日に、そのほだ木に生えるか(日付と場所で決まる。開き直しても同じ)
func sprouts_on(l: Dictionary, day: int) -> bool:
	if not is_colonized(l, day) or is_ready(l):
		return false
	if not (forest.season_of_date(Forest.date_of_day(day)) in SEASONS):
		return false
	var rained: bool = forest.roll_daily_event(Forest.date_of_day(day - 1)) == "rain"
	var rng := RandomNumberGenerator.new()
	rng.seed = ("shiitake:%d:%.2f:%.2f" % [day, l.pos.x, l.pos.y]).hash()
	return rng.randf() < (RAIN_CHANCE if rained else DRY_CHANCE)

func _caps_on(l: Dictionary, day: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("shiitake_caps:%d:%.2f:%.2f" % [day, l.pos.x, l.pos.y]).hash()
	return rng.randi_range(CAPS_MIN, CAPS_MAX)

# 日付が変わったときに呼ぶ。閉じていたあいだの分も、1 日ずつ数える。日陰の木がなくなったほだ木は乾いて生えない
func catch_up() -> void:
	last_sprouted = 0
	var today: int = forest.day_number()
	if last_checked_day <= 0:
		last_checked_day = today
		dirty.emit()
		return
	if today <= last_checked_day:
		return
	var from: int = Forest.catch_up_from(last_checked_day, today)
	for l in logs:
		if not is_shaded(l.pos):
			continue
		for d in range(from, today + 1):
			if sprouts_on(l, d):
				l.caps = _caps_on(l, d)
				l.grew_day = d
				last_sprouted += 1
				break
	last_checked_day = today
	_commit()

# 明日生えるかもしれないほだ木の数(菌が回っていて、生えていなくて、明日が生える季節で、日陰にある)。日記用
func may_sprout_tomorrow() -> int:
	var d: int = forest.day_number() + 1
	if not (forest.season_of_date(Forest.date_of_day(d)) in SEASONS):
		return 0
	return logs.filter(func(l): return is_colonized(l, d) and not is_ready(l) and is_shaded(l.pos)).size()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for l in logs:
		list.append({"x": l.pos.x, "y": l.pos.y, "placed_day": l.placed_day, "flushes": l.flushes, "caps": l.caps, "grew_day": l.grew_day})
	return {"logs": list, "spawn": spawn, "shiitake": stock.shiitake, "last_checked_day": last_checked_day}

# 原木シイタケの記録がないセーブ(2026-11-26 より前)は、ほだ木なしから。読めないほだ木は 1 本ずつ飛ばす
func from_save(d: Dictionary) -> void:
	logs.clear()
	for item in SaveRead.list(d.get("logs")):
		var l := SaveRead.dict(item)
		var pos = SaveRead.point(l)
		if pos == null or not l.has("placed_day"):
			continue
		logs.append({
			"pos": pos, "placed_day": SaveRead.whole(l, "placed_day"),
			"flushes": clampi(SaveRead.count(l, "flushes"), 0, FLUSHES - 1),
			"caps": clampi(SaveRead.count(l, "caps"), 0, CAPS_MAX),
			"grew_day": SaveRead.whole(l, "grew_day", -1),
		})
		if logs.size() >= MAX_LOGS:
			break
	spawn = SaveRead.count(d, "spawn")
	stock.shiitake = SaveRead.count(d, "shiitake")
	last_checked_day = SaveRead.whole(d, "last_checked_day")
	changed.emit()
