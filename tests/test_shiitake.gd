extends SceneTree

# 原木シイタケ(2026-11-26)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_shiitake.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")
const Shiitake = preload("res://logic/Shiitake.gd")

const TEST_SAVE := "user://test_shiitake.json"
const SHADE := Vector2(20, 20)   # 日陰を作る育った白樺
const UNDER := Vector2(21, 20)   # その枝の下(幹から 1m)
const OPEN := Vector2(-30, -30)  # 日なた

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_oak_logs()
	_test_place()
	_test_market()
	_test_growth()
	_test_harvest()
	_test_rates()
	_test_save()
	_test_blocking()
	_remove_save()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _world(date := "2026-04-10") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today(date)
	w.refresh_season()
	_tree(w, SHADE, "birch", 20.0)
	return w

func _tree(w: GameWorld, pos: Vector2, species: String, age: float) -> void:
	w.forest.trees.append({"pos": pos, "species": species, "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0, "pruned_year": 0, "id": w.forest.trees.size() + 100})

# コナラの丸太 n 本と種駒 n 袋を持たせる
func _supplies(w: GameWorld, n: int) -> void:
	w.cabin.materials.log = int(w.cabin.materials.log) + n
	w.cabin.own_logs += n
	w.cabin.oak_logs += n
	w.shiitake.spawn += n

func _next_day(w: GameWorld, days := 1) -> void:
	w.time.set_today(Forest.date_of_day(w.forest.day_number() + days))
	w.refresh_season()

func _test_oak_logs() -> void:
	print("コナラ・クヌギの丸太")
	var w := _world()
	var c := w.cabin
	_tree(w, Vector2(-10, 0), "konara", 20.0)
	_tree(w, Vector2(-20, 0), "birch", 20.0)
	_tree(w, Vector2(-30, 0), "kunugi", 20.0)
	var n1: int = c.fell(Vector2(-10, 0), 1.0)
	_check(n1 > 0 and c.oak_log_count() == n1, "コナラを伐ると、原木にできる丸太が増える(%d本)" % n1)
	var n2: int = c.fell(Vector2(-20, 0), 1.0)
	_check(n2 > 0 and c.oak_log_count() == n1 and c.own_log_count() == n1 + n2, "白樺の丸太は原木にならない")
	var n3: int = c.fell(Vector2(-30, 0), 1.0)
	_check(c.oak_log_count() == n1 + n3, "クヌギも原木になる")
	c.materials.log += 5  # 市場の丸太
	_check(c.oak_log_count() == n1 + n3, "市場の丸太は原木にならない")
	c.spend_own_logs(n2)
	_check(c.oak_log_count() == n1 + n3 and c.own_log_count() == n1 + n3, "巣箱にはほかの木の丸太を先に使う")
	c.materials.log = 1
	c.clamp_own_logs()
	_check(c.oak_log_count() == 1, "薪や小屋で丸太が減ると、原木にできる丸太も減る")
	c.spend_oak_logs(1)
	_check(c.oak_log_count() == 0 and c.own_log_count() == 0 and int(c.materials.log) == 0, "原木に使うと丸太全体も減る")

func _test_place() -> void:
	print("ほだ木を置く")
	var w := _world()
	var s := w.shiitake
	_check(s.place(UNDER) == "no_log", "コナラ・クヌギの丸太がなければ置けない")
	w.cabin.materials.log = 1
	w.cabin.own_logs = 1
	w.cabin.oak_logs = 1
	_check(s.place(UNDER) == "no_spawn", "種駒がなければ置けない")
	s.spawn = 1
	_check(s.place(OPEN) == "no_shade", "日なたには置けない")
	_check(s.place(SHADE + Vector2(0.3, 0)) == "trunk", "幹のすぐそばには置けない")
	_tree(w, Vector2(40, 40), "birch", 0.5)
	_check(s.place(Vector2(40.6, 40)) == "no_shade", "若い木の下は日陰にならない")
	_check(s.place(UNDER) == "placed" and s.logs.size() == 1, "育った木の枝の下に置ける")
	_check(w.cabin.oak_log_count() == 0 and int(w.cabin.materials.log) == 0 and s.spawn == 0, "丸太 1 本と種駒 1 袋を使う")
	_check(FileAccess.file_exists(TEST_SAVE), "置くと保存する")
	_supplies(w, 10)
	_check(s.place(UNDER + Vector2(0, 0.5)) == "near_log", "ほだ木どうしは離す")
	for i in range(Shiitake.MAX_LOGS - 1):
		var p := SHADE + Vector2(-1.2, -2.0 + i * 1.0) if i < 4 else SHADE + Vector2(0, 1.5 + (i - 4) * 1.0)
		var r: String = s.place(p)
		if r != "placed":
			print("    placed? ", p, " ", r)
	_check(s.logs.size() == Shiitake.MAX_LOGS and s.place(SHADE + Vector2(-2.5, 0)) == "too_many", "%d 本まで" % Shiitake.MAX_LOGS)
	var w2 := _world()
	_supplies(w2, 1)
	w2.forest.time_offset_years = 1.0
	_check(w2.shiitake.place(UNDER) == "preview", "未来のプレビュー中は置けない")

func _test_market() -> void:
	print("市場")
	var w := _world()
	var m := w.market
	_check(not m.sells(m.good("shiitake_spawn")), "県を選ぶ前(コナラ・クヌギの育たない今までの土地)は種駒が並ばない")
	w.region.choose("tokyo")
	w.forest.region = w.region
	var money: int = m.money
	_check(m.buy("shiitake_spawn") == "bought" and w.shiitake.spawn == 1 and m.money == money - 300, "種駒を 1 袋買える")
	w.shiitake.stock.shiitake = 10
	_check(m.count_of("shiitake") == 10 and m.sell_all("shiitake") == 250 and w.shiitake.stock.shiitake == 0, "生のシイタケを売れる(1 個 25₽)")
	_check(m.sells(m.good("shiitake_spawn")), "コナラの育つ土地(東京)では種駒が並ぶ")
	var w2 := _world()
	w2.region.choose("okinawa")
	w2.forest.region = w2.region
	_check(not w2.market.sells(w2.market.good("shiitake_spawn")), "コナラもクヌギも育たない沖縄では並ばない")
	# 干し椎茸
	var k := w.kitchen
	w.shiitake.stock.shiitake = 10
	_check(k.input_count("hoshi_shiitake") == 10, "干し椎茸の材料はシイタケ")

func _test_growth() -> void:
	print("生える")
	var w := _world("2026-04-01")
	var s := w.shiitake
	_supplies(w, 1)
	s.place(UNDER)
	var l: Dictionary = s.logs[0]
	_next_day(w, Shiitake.SPAWN_DAYS - 1)
	w.check_new_day()
	_check(not s.is_colonized(l) and l.caps == 0 and s.days_to_colonize(l) == 1, "菌が回るまでは生えない(あと 1 日)")
	# 菌が回ってから、春のうちにいつか生える
	var grew := -1
	for i in range(40):
		_next_day(w)
		w.check_new_day()
		if l.caps > 0:
			grew = i
			break
	_check(grew >= 0 and l.caps >= Shiitake.CAPS_MIN and l.caps <= Shiitake.CAPS_MAX and s.last_sprouted == 1, "菌が回ると、春のうちに生える(%d 日目・%d 個)" % [grew + 1, l.caps])
	var caps: int = l.caps
	_next_day(w, 5)
	w.check_new_day()
	_check(l.caps == caps, "採らなくても、なくならない(増えもしない)")
	# 夏と冬は生えない
	var w2 := _world("2026-06-01")
	var s2 := w2.shiitake
	_supplies(w2, 1)
	s2.place(UNDER)
	var l2: Dictionary = s2.logs[0]
	var summer := 0
	for d in range(w2.forest.day_number() + Shiitake.SPAWN_DAYS, w2.forest.day_number() + 80):
		if s2.sprouts_on(l2, d):
			summer += 1
	_check(summer == 0, "夏(6〜8 月)は生えない")
	var autumn := 0
	var sep1: int = int(Time.get_unix_time_from_datetime_string("2026-09-01") / 86400.0)
	for d in range(sep1, sep1 + 91):
		if s2.sprouts_on(l2, d):
			autumn += 1
	_check(autumn > 0, "秋(9〜11 月)は生える(91 日のうち %d 日)" % autumn)
	# 日陰の木を伐ると乾いて生えない
	var w3 := _world("2026-04-01")
	var s3 := w3.shiitake
	_supplies(w3, 1)
	s3.place(UNDER)
	w3.forest.trees = w3.forest.trees.filter(func(t): return t.pos != SHADE)
	for i in range(40):
		_next_day(w3)
		w3.check_new_day()
	_check(s3.logs[0].caps == 0 and not s3.is_shaded(UNDER), "日陰の木がなくなると生えない")

func _test_harvest() -> void:
	print("採る")
	var w := _world()
	var s := w.shiitake
	_supplies(w, 1)
	s.place(UNDER)
	var l: Dictionary = s.logs[0]
	_check(s.harvest(OPEN) == "none", "そばにほだ木がなければ採れない")
	_check(s.harvest(UNDER) == "growing", "菌が回る前")
	_next_day(w, Shiitake.SPAWN_DAYS)
	_check(s.harvest(UNDER) == "waiting", "菌が回っても、生えていなければ採れない")
	for i in range(Shiitake.FLUSHES):
		l.caps = 10
		_check(s.harvest(UNDER + Vector2(0.5, 0)) == "harvested", "%d 回目を採る" % (i + 1))
	_check(s.stock.shiitake == 10 * Shiitake.FLUSHES and s.last_caps == 10, "採った数が持ち物に入る")
	_check(s.logs.is_empty() and s.last_rotted == 1, "%d 回採ると朽ちて消える" % Shiitake.FLUSHES)

# 生える確率: 雨の翌日は RAIN_CHANCE、ふだんは DRY_CHANCE ほど(日付と場所で決まる)
func _test_rates() -> void:
	print("生える確率")
	var w := _world("2026-03-01")
	var s := w.shiitake
	var l := {"pos": UNDER, "placed_day": 0, "flushes": 0, "caps": 0, "grew_day": -1}
	var rain := [0, 0]  # [日数, 生えた]
	var dry := [0, 0]
	var start: int = w.forest.day_number()
	for year in range(6):
		for d in range(start + year * 365, start + year * 365 + 92):  # 3〜5 月
			for k in range(4):
				l.pos = UNDER + Vector2(k * 1.3, 0)
				var rained: bool = w.forest.roll_daily_event(Forest.date_of_day(d - 1)) == "rain"
				var grew: bool = s.sprouts_on(l, d)
				var bucket: Array = rain if rained else dry
				bucket[0] += 1
				bucket[1] += 1 if grew else 0
	var rain_rate: float = float(rain[1]) / maxi(1, rain[0])
	var dry_rate: float = float(dry[1]) / maxi(1, dry[0])
	_check(rain[0] > 50 and absf(rain_rate - Shiitake.RAIN_CHANCE) < 0.12, "雨の翌日はおよそ %d%%(%.2f・%d 日)" % [roundi(Shiitake.RAIN_CHANCE * 100), rain_rate, rain[0]])
	_check(absf(dry_rate - Shiitake.DRY_CHANCE) < 0.05, "ふだんはおよそ %d%%(%.2f・%d 日)" % [roundi(Shiitake.DRY_CHANCE * 100), dry_rate, dry[0]])
	_check(s.sprouts_on(l, start + 10) == s.sprouts_on(l, start + 10), "同じ日と場所なら同じ")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var s := w.shiitake
	_supplies(w, 2)
	s.place(UNDER)
	s.logs[0].caps = 9
	s.logs[0].flushes = 2
	s.stock.shiitake = 7
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var s2 := w2.shiitake
	_check(s2.logs.size() == 1 and s2.logs[0].pos == UNDER and s2.logs[0].caps == 9 and s2.logs[0].flushes == 2, "ほだ木が戻る")
	_check(s2.spawn == 1 and s2.stock.shiitake == 7 and w2.cabin.oak_log_count() == 1, "種駒・シイタケ・原木にできる丸太が戻る")
	var s3 := Shiitake.new()
	s3.from_save({})
	_check(s3.logs.is_empty() and s3.spawn == 0, "記録がないセーブは、ほだ木なしから")
	s3.from_save({"logs": [{"x": 1, "y": 2, "placed_day": 5, "caps": 99, "flushes": 99}, {"x": 1}, "x", {"x": 3, "y": 3}]})
	_check(s3.logs.size() == 1 and s3.logs[0].caps == Shiitake.CAPS_MAX and s3.logs[0].flushes == Shiitake.FLUSHES - 1, "おかしな記録は読まない・数は上限まで")

func _test_blocking() -> void:
	print("ほかの物と重ねない")
	var w := _world()
	var s := w.shiitake
	_supplies(w, 2)
	_check(s.place(UNDER) == "placed", "置く")
	_check(w.tree_spot_problem(UNDER) == "hodagi", "ほだ木の上には木を植えられない")
	_check(w.toggle_plot(UNDER) == "hodagi", "ほだ木にかかる場所には区画を作れない")
	_check(w.pond_action(UNDER + Vector2(2, 0)) == "hodagi", "ほだ木の近くには池を掘れない")
	_check(w.bees.is_blocked(UNDER + Vector2(0.5, 0.5)), "ほだ木のそばには巣箱・餌台・井戸などを置けない")
	_check(w.rect_problem(Rect2(UNDER - Vector2(1, 1), Vector2(2, 2))) == "hodagi", "小屋や増築にもかからない")
	var plot_pos := SHADE + Vector2(-2.5, 0)
	var made: String = w.toggle_plot(plot_pos)
	_check(made == "placed" and s.place(plot_pos) == "plot", "区画の上には置けない(区画: %s)" % made)
