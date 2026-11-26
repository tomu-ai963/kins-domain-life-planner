extends RefCounted

# ── ムクドリの巣箱(描画を持たない) ─────────────────────────────
# 丸太 1 本から、1 日 1 回・3 日かけて小鳥の巣箱を作り、育った木の幹に掛ける(2026-11-11 とむ決定)。
# ロシアでは冬の終わりにムクドリの巣箱(スクヴォレーチニク)を作って掛け、春に渡ってくるのを待つ習慣がある。
# 掛け終えた巣箱には、春と夏にムクドリのつがいが来る(数は Wildlife が決める)。見て楽しむもので、ルールには関わらない。
# 巣箱は木の位置で覚える。その木を伐ると巣箱もなくなる。文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const MAX_BOXES := 3     # 巣箱の数の上限
const LOG_COST := 1      # 巣箱 1 つに使う丸太(市場の丸太でもよい)
const WORK_DAYS := 3     # 作る日数(1 日 1 回)
const REACH := 1.6       # 木の幹からこの距離までなら作業できる
const MIN_RADIUS := 0.8  # 掛けられる木の樹冠の半径(m)。白樺なら幹の高さ 1.8m ほど
const SAME_SPOT := 0.05  # 木と巣箱の位置がこれより近ければ同じ木(セーブで小数が丸まっても見つかるように)
const SEASONS := ["spring", "summer"]  # ムクドリが巣箱にいる季節(春に渡ってきて、夏にひなが巣立つ)

var forest: Forest  # GameWorld が設定する
var cabin: Cabin

var boxes := []     # [{pos: Vector2(木の位置), days_done: int, last_worked: String}]
var last_box := {}  # 直前に作業した巣箱(文言用)

func _commit() -> void:
	dirty.emit()
	changed.emit()

func is_done(b: Dictionary) -> bool:
	return int(b.days_done) >= WORK_DAYS

func done_count() -> int:
	return boxes.filter(func(b): return is_done(b)).size()

func worked_today(b: Dictionary) -> bool:
	return b.last_worked == forest.today()

# 巣箱を掛けられる木か(根付いていて、幹が育っている)
func can_hold(tree: Dictionary) -> bool:
	return forest.is_established(tree) and forest.radius_of(tree) >= MIN_RADIUS

# pos のそばの、巣箱を掛けられる木(なければ空)
func tree_near(pos: Vector2) -> Dictionary:
	var i: int = forest.nearest_index(pos, REACH, "")
	if i < 0 or not can_hold(forest.trees[i]):
		return {}
	return forest.trees[i]

# その木の巣箱(なければ空)
func box_on(tree_pos: Vector2) -> Dictionary:
	for b in boxes:
		if b.pos.distance_to(tree_pos) < SAME_SPOT:
			return b
	return {}

# pos のそばに巣箱の作業ができる木があるか(L を巣箱と餌台のどちらに使うかを Main が決める)
func is_near(pos: Vector2) -> bool:
	return not tree_near(pos).is_empty()

# 伐った木の巣箱をなくす。なくしたら true
func drop_missing() -> bool:
	var before := boxes.size()
	boxes = boxes.filter(func(b): return forest.trees.any(func(t): return t.pos.distance_to(b.pos) < SAME_SPOT))
	if boxes.size() == before:
		return false
	_commit()
	return true

# L: そばの木で巣箱を作りはじめる / 続きを作る。
# 結果: started / worked / finished / no_tree / done / done_today / too_many / no_wood
func act(pos: Vector2) -> String:
	drop_missing()
	var tree := tree_near(pos)
	if tree.is_empty():
		return "no_tree"
	var b := box_on(tree.pos)
	if b.is_empty():
		if boxes.size() >= MAX_BOXES:
			return "too_many"
		if int(cabin.materials.log) < LOG_COST:
			return "no_wood"
		cabin.materials.log = int(cabin.materials.log) - LOG_COST
		cabin.clamp_own_logs()
		b = {"pos": tree.pos, "days_done": 1, "last_worked": forest.today()}
		boxes.append(b)
		last_box = b
		_commit()
		return "finished" if is_done(b) else "started"
	last_box = b
	if is_done(b):
		return "done"
	if worked_today(b):
		return "done_today"
	b.days_done = int(b.days_done) + 1
	b.last_worked = forest.today()
	_commit()
	return "finished" if is_done(b) else "worked"

# ── 夜の巣箱の跡(2026-11-26。Hermes のレビューの案 2) ─────────────────
# ムクドリは昼にしか出ないので、夜しか遊べない人は会いにくい。昼に来る条件がそろっていた日は、
# 夜に巣箱を調べると跡(羽・巣材など)が見つかり、日記に 1 行残る。直接見たときの図鑑の登録(Wildlife.seen)とは分ける。
# 1 つの巣箱を調べられるのは 1 日 1 回。見つかる物は日付と巣箱で決まる(開き直しても同じ)
const TRACES := {
	"spring": ["羽が 1 枚", "巣材の枯れ草", "巣材の小枝"],
	"summer": ["卵の殻のかけら", "羽が 1 枚", "ひなの産毛"],
}

# L(掛け終えた巣箱のそば)で調べる。time は Main が渡す時間帯: day / dawn(夜明け前) / night(昼が過ぎて暗い) / preview
# lives_here: この土地にムクドリがいるか(Wildlife.lives_here)
# 結果: found / found_today(今夜はもう調べた) / day / dawn / preview / off_season / new(今日掛けたばかり) / absent / none
func inspect(pos: Vector2, time: String, lives_here := true) -> String:
	var tree := tree_near(pos)
	var b: Dictionary = box_on(tree.pos) if not tree.is_empty() else {}
	if b.is_empty() or not is_done(b):
		return "none"
	last_box = b
	if not (forest.season in SEASONS):
		return "off_season"
	if not lives_here:
		return "absent"
	if time == "preview":
		return "preview"
	if time == "day":
		return "day"
	if b.get("traced_on", "") == forest.today():
		return "found_today"
	if time == "dawn":
		return "dawn"
	if b.last_worked == forest.today():
		return "new"
	b.traced_on = forest.today()
	b.trace = trace_of(b)
	_commit()
	return "found"

# その日にその巣箱で見つかる物(季節の中から、日付と巣箱で決まる)
func trace_of(b: Dictionary) -> String:
	var list: Array = TRACES.get(forest.season, TRACES.spring)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("starling_trace:%s:%.2f:%.2f" % [forest.today(), b.pos.x, b.pos.y]).hash()
	return list[rng.randi_range(0, list.size() - 1)]

# 今日見つけた跡(日記用)。[見つけた物, ...]
func traces_today() -> Array:
	var out := []
	for b in boxes:
		if b.get("traced_on", "") == forest.today() and str(b.get("trace", "")) != "":
			out.append(str(b.trace))
	return out

# 今、巣箱にムクドリが来ている数(つがい = 2 羽 × 掛け終えた巣箱)。時間帯は Wildlife が見る
func starlings() -> int:
	if not (forest.season in SEASONS):
		return 0
	return 2 * done_count()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for b in boxes:
		list.append({"x": b.pos.x, "y": b.pos.y, "days_done": b.days_done, "last_worked": b.last_worked,
			"traced_on": b.get("traced_on", ""), "trace": b.get("trace", "")})
	return {"boxes": list}

func from_save(d: Dictionary) -> void:
	boxes.clear()
	for item in SaveRead.list(d.get("boxes")):
		var b := SaveRead.dict(item)
		var pos = SaveRead.point(b)
		if pos != null:
			boxes.append({
				"pos": pos,
				"days_done": clampi(SaveRead.whole(b, "days_done"), 0, WORK_DAYS),
				"last_worked": SaveRead.text(b, "last_worked"),
				"traced_on": SaveRead.text(b, "traced_on"),  # 夜の跡の記録がないセーブ(2026-11-26 より前)は、まだ調べていない
				"trace": SaveRead.text(b, "trace"),
			})
	changed.emit()
