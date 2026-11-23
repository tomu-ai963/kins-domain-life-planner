extends SceneTree

# 記念樹と歳時記(木の番号・名前とメモ・伐ったあと・セーブ・暦の日の数え方)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_memorials.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")
const Memorials = preload("res://logic/Memorials.gd")

const TEST_SAVE := "user://test_memorials.json"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_tree_ids()
	_test_old_save_ids()
	_test_name_tree()
	_test_gone()
	_test_save()
	_test_days()
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

func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today("2026-05-10")
	w.forest.saplings.birch = 10
	w.forest.seeds.birch = 10
	return w

func _test_tree_ids() -> void:
	print("木の番号")
	var w := _world()
	var f := w.forest
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	f.add_tree(Vector2(5, 0), "birch", "sapling")
	f.add_tree(Vector2(10, 0), "birch", "sapling")
	_check(f.trees.map(func(t): return t.id) == [1, 2, 3], "植えた順に 1・2・3")
	f.remove_nearest(Vector2(5, 0), 1.0)
	f.add_tree(Vector2(15, 0), "birch", "sapling")
	_check(f.trees.map(func(t): return t.id) == [1, 3, 4], "伐った木の番号は使い回さない")
	_check(f.tree_by_id(3).pos == Vector2(10, 0) and f.tree_by_id(2).is_empty(), "番号から木を探せる(伐った木は見つからない)")
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.forest.trees.map(func(t): return t.id) == [1, 3, 4] and w2.forest.next_tree_id == 5, "番号と次の番号はセーブに残る")

func _test_old_save_ids() -> void:
	print("番号のない前のセーブ")
	var w := _world()
	var data := {"trees": [
		{"x": 0, "y": 0, "species": "birch", "planted_at": 100},
		{"x": 5, "y": 0, "species": "birch", "planted_at": 100, "id": 7},
		{"x": 9, "y": 0, "species": "birch", "planted_at": 100, "id": 7},
		{"x": 12, "y": 0, "species": "birch", "planted_at": 100, "id": "x"},
	]}
	w.forest.from_save(data)
	var ids: Array = w.forest.trees.map(func(t): return t.id)
	_check(ids[1] == 7, "読める番号はそのまま")
	_check(ids[0] == 8 and ids[2] == 9 and ids[3] == 10, "番号のない木・重なった番号の木には、新しい番号を付ける: %s" % str(ids))
	_check(w.forest.next_tree_id == 11, "次の番号はその次から")

func _test_name_tree() -> void:
	print("名前とメモを付ける")
	var w := _world()
	var f := w.forest
	var m := w.memorials
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	var tree: Dictionary = f.trees[-1]
	_check(m.name_tree(tree, "  ") == "empty" and m.records.is_empty(), "名前が空なら記念樹にしない")
	_check(m.name_tree(tree, "あいうえおかきくけこさしす") == "too_long", "%d 文字をこえる名前は付けられない" % Memorials.NAME_MAX)
	_check(m.name_tree(tree, "木", "あ".repeat(Memorials.NOTE_MAX + 1)) == "note_too_long", "%d 文字をこえるメモは付けられない" % Memorials.NOTE_MAX)
	_check(m.name_tree(tree, " 長男の木\n", "春の朝") == "named", "名前とメモを付ける")
	var r := m.record_for(tree)
	_check(r.name == "長男の木" and r.note == "春の朝" and r.named_on == "2026-05-10" and r.planted_on == "2026-05-10" and r.gone_on == "", "記録: 名前・メモ・名付けた日・植えた日")
	_check(r.tree_id == tree.id and r.species == "birch", "木は番号で指す")
	_check(m.name_tree(tree, "長男の木", "春の朝") == "same", "同じなら same")
	_check(m.name_tree(tree, "長男の木", "") == "renamed" and m.record_for(tree).note == "", "メモだけ変えても付け直し")
	_check(m.records.size() == 1, "付け直しても記録は 1 つ")
	_check(m.name_tree(tree, "") == "cleared" and m.records.is_empty() and m.record_for(tree).is_empty(), "名前を空にすると記念樹をやめる")
	f.germination_rates.birch = 1.0
	f.add_tree(Vector2(5, 0), "birch", "seed")
	_check(m.name_tree(f.trees[-1], "まだ種") == "young", "芽が出る前の種には付けられない")
	w.time.shift_days(1)
	_check(m.name_tree(f.trees[-1], "芽が出た") == "named", "芽が出たと分かった次の日からは付けられる")
	_check(m.nearest(Vector2(5.5, 0), 2.0)[1].name == "芽が出た" and m.nearest(Vector2(30, 0), 2.0).is_empty(), "そばの記念樹を探せる")

func _test_gone() -> void:
	print("伐ったあとも歳時記に残る")
	var w := _world()
	var f := w.forest
	var m := w.memorials
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	f.add_tree(Vector2(10, 0), "birch", "sapling")
	var a: Dictionary = f.trees[0]
	m.name_tree(a, "祖母の白樺")
	m.name_tree(f.trees[1], "となり")
	w.time.shift_days(3)
	f.remove_nearest(Vector2(0, 0), 1.0)
	_check(m.records.size() == 2 and m.records[0].gone_on == "2026-05-13", "伐った日が残る")
	_check(m.record_for(a).is_empty() and m.standing_count() == 1, "今ある記念樹からは外れる")
	_check(m.records[1].gone_on == "", "ほかの木はそのまま")
	_check(m.nearest(Vector2(0, 0), 2.0).is_empty(), "伐った木のそばでは何も出ない")
	# 伐ったあとに同じ場所に植えた木は、別の木(番号が違う)
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	_check(m.record_for(f.trees[-1]).is_empty(), "同じ場所に植え直しても、前の記念樹にはならない")
	# 小屋の Z(Cabin.fell)で伐っても残る
	var w2 := _world()
	w2.forest.add_tree(Vector2(20, 20), "birch", "sapling")
	w2.memorials.name_tree(w2.forest.trees[-1], "小屋の木")
	w2.fell(Vector2(20, 20), 2.0)
	_check(w2.memorials.records[0].gone_on == "2026-05-10", "Z で伐っても記録が残る")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var f := w.forest
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	f.add_tree(Vector2(10, 0), "birch", "sapling")
	w.memorials.name_tree(f.trees[0], "一", "メモ1")
	w.memorials.name_tree(f.trees[1], "二")
	f.remove_nearest(Vector2(10, 0), 1.0)
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var m2 := w2.memorials
	_check(m2.records.size() == 2 and m2.records[0].name == "一" and m2.records[0].note == "メモ1", "記録はセーブに残る")
	_check(m2.records[1].gone_on != "" and m2.standing_count() == 1, "なくなった日も残る")
	_check(m2.record_for(w2.forest.trees[0]).name == "一", "読み込んだあとも、番号で木とつながる")
	# 記録のない前のセーブ・おかしな記録
	var m3 := Memorials.new()
	m3.from_save({})
	_check(m3.records.is_empty(), "記録のないセーブは記念樹なし")
	m3.from_save({"records": [
		{"tree_id": 1, "name": "よい", "named_on": "2026-01-02", "note": 5},
		{"tree_id": 0, "name": "番号なし", "named_on": "2026-01-02"},
		{"tree_id": 2, "name": "", "named_on": "2026-01-02"},
		{"tree_id": 3, "name": "日付なし", "named_on": "きのう"},
		"文字",
	]})
	_check(m3.records.size() == 1 and m3.records[0].name == "よい" and m3.records[0].note == "" and m3.records[0].planted_on == "2026-01-02", "読めない記録は飛ばし、足りないところは埋める")

func _test_days() -> void:
	print("暦の日で数える")
	var w := _world()
	var m := w.memorials
	_check(m.days_since("2026-05-10") == 0 and m.days_since("2026-05-07") == 3, "今日は 0 日、3 日前は 3")
	_check(m.anniversary_years("2026-05-10") == 0, "名付けた日そのものは記念日ではない")
	w.time.set_today("2027-05-10")
	_check(m.anniversary_years("2026-05-10") == 1, "1 年後の同じ月日は 1 年の日")
	w.time.set_today("2028-05-11")
	_check(m.anniversary_years("2026-05-10") == 0, "月日がちがえば 0")
	w.time.set_today("2027-02-28")
	_check(m.anniversary_years("2024-02-29") == 3, "2/29 は平年なら 2/28 に数える")
	w.time.set_today("2028-02-28")
	_check(m.anniversary_years("2024-02-29") == 0, "うるう年は 2/29 のまま")
