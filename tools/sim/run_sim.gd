extends SceneTree

# シミュレーション(2026-11-26)。決まった遊び方で N 日回し、数字の推移を JSON に書き出す。
# 数字の釣り合い(値段・確率など、ROADMAP で「仮の数字」のもの)を、実際に回した結果で確かめるための道具。合否は出さない。
# 本物のセーブには触れない(user://sim_save.json だけを使い、控えも取らず、終わったら消す)。
#
# 実行:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/sim/run_sim.gd -- [オプション]
# オプション:
#   --plan=long_play       遊び方(tools/sim/plans/<名前>.gd)。既定 long_play
#   --start=2026-11-01     始める日。既定 2026-11-01
#   --days=121             回す日数。既定 121
#   --region=hokkaido      県を選んでから始める(Region.PREFS の id)。付けなければ県を選ぶ前のルール
#   --every=1              日ごとの記録を何日おきに残すか(最後の日は必ず残す)。既定 1
#   --out=sim_out/x.json   書き出し先(プロジェクトからの相対か絶対パス)。既定 sim_out/<plan>_<start>_<days>.json
#   --param=plots=8,hives=3  遊び方の設定(名前=値 をカンマで区切る。何が使えるかは遊び方のファイルの先頭に書いてある)
#   --check-save           毎日、保存して開き直しても中身が変わらないかも見る(遅くなる)
# 遊び方: long_play(test_long_play と同じ)/ farmer(畑だけ)/ bees(巣箱とはちみつ)。plans/_farm.gd は部品なので渡さない
# 乱数は日付と場所から決まるので、同じ条件なら毎回同じ結果になる。

const GameWorld = preload("res://logic/GameWorld.gd")
const SimCtx = preload("res://tools/sim/sim_ctx.gd")

const SAVE := "user://sim_save.json"
const PLAN_DIR := "res://tools/sim/plans/"

var _opts := {
	"plan": "long_play", "start": "2026-11-01", "days": "121", "region": "",
	"every": "1", "out": "", "check-save": false, "param": "",
}
var _params := {}
var _offset := 0

func _initialize() -> void:
	var err := _parse_args()
	if err != "":
		printerr("ERROR: ", err)
		quit(2)
		return
	_clean()
	var code := _run()
	_clean()
	quit(code)

func _parse_args() -> String:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			return "知らない引数: %s" % a
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		if not _opts.has(kv[0]):
			return "知らないオプション: %s" % a
		_opts[kv[0]] = kv[1] if kv.size() == 2 else true
	if not String(_opts.days).is_valid_int() or int(_opts.days) < 1:
		return "--days は 1 以上の整数: %s" % _opts.days
	if not String(_opts.every).is_valid_int() or int(_opts.every) < 1:
		return "--every は 1 以上の整数: %s" % _opts.every
	for pair in String(_opts.param).split(",", false):
		var kv2: PackedStringArray = pair.split("=", true, 1)
		if kv2.size() != 2 or kv2[0] == "":
			return "--param は 名前=値 をカンマで区切る: %s" % _opts.param
		_params[kv2[0]] = int(kv2[1]) if kv2[1].is_valid_int() else (float(kv2[1]) if kv2[1].is_valid_float() else kv2[1])
	if String(_opts.plan).begins_with("_") or not FileAccess.file_exists(PLAN_DIR + String(_opts.plan) + ".gd"):
		return "遊び方がない: %s%s.gd" % [PLAN_DIR, _opts.plan]
	return ""

func _clean() -> void:
	for n in DirAccess.get_files_at("user://"):
		if n.begins_with("sim_save"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))

func _open() -> GameWorld:
	var w := GameWorld.new()
	w.save_path = SAVE
	w.time.offset_seconds = _offset
	w.refresh_season()
	w.load_game()
	w.check_new_day()
	return w

func _run() -> int:
	var plan = load(PLAN_DIR + String(_opts.plan) + ".gd").new()
	var ctx = SimCtx.new()
	ctx.params = _params
	var days := int(_opts.days)
	var every := int(_opts.every)
	var warnings := []

	# はじめの日(test_long_play と同じ順: 日付を決める → 遊び方の準備 → 保存)
	var first := GameWorld.new()
	first.save_path = SAVE
	first.time.set_today(String(_opts.start))
	_offset = first.time.offset_seconds
	if String(_opts.region) != "":
		first.is_new_game = true  # 本物のゲームと同じく、新しく始めて県を選ぶ(その土地のはじめの種が配られる)
		var r: String = first.choose_region(String(_opts.region))
		if r != "chosen":
			printerr("ERROR: 県を選べなかった(%s): %s" % [r, _opts.region])
			return 2
	plan.setup(first, ctx)
	first.save_game()
	var money_start: int = first.market.money

	var daily := []
	var season_days := {}
	var money_prev := money_start
	var money_low := 999999999
	var money_low_date := ""
	var money_high := -999999999
	var w: GameWorld
	for day in range(days):
		w = _open()
		var date: String = w.forest.today()
		if w.load_notice != "":
			warnings.append("%s: セーブが読めなかった: %s" % [date, w.load_notice])
		season_days[w.forest.season] = int(season_days.get(w.forest.season, 0)) + 1
		if w.visitors.is_here():
			ctx.count("visits")
		if w.pond.last_gain > 0:
			ctx.count("pond_rain_days")
		var tracked_before := _net(ctx)
		ctx.market_used = false
		plan.play_day(w, ctx, day)
		if ctx.market_used:
			ctx.act("market")  # 市場へ行くのは 1 日 1 回と数える
		# 記録係を通らずに動いたお金(開いたときの出来事など)は other
		ctx.add_money("other", (w.market.money - money_prev) - (_net(ctx) - tracked_before))
		money_prev = w.market.money
		if w.market.money < money_low:
			money_low = w.market.money
			money_low_date = date
		money_high = maxi(money_high, w.market.money)
		if w.market.money < 0:
			warnings.append("%s: 所持金がマイナス(%d₽)" % [date, w.market.money])
		w.save_game()
		if _opts["check-save"]:
			var why := _save_roundtrip()
			if why != "":
				warnings.append("%s: 保存し直すと中身が変わった: %s" % [date, why])
		if day % every == 0 or day == days - 1:
			daily.append(_snapshot(w))
		_offset += 86400  # 次の日

	var result := {
		"meta": {
			"plan": _opts.plan, "description": plan.DESCRIPTION, "params": _params, "start": _opts.start, "days": days,
			"region": _opts.region if String(_opts.region) != "" else null,
			"every": every, "check_save": _opts["check-save"], "commit": _git(["rev-parse", "--short", "HEAD"]),
			"logic_changed": _git(["diff", "--stat", "HEAD", "--", "logic"]),  # 数字を書き換えて回したとき、何を変えたか
		},
		"summary": {
			"money_start": money_start, "money_end": w.market.money, "net": w.market.money - money_start,
			"money_min": money_low, "money_min_date": money_low_date, "money_max": money_high,
			"income": ctx.income, "income_total": _sum(ctx.income),
			"spend": ctx.spend, "spend_total": _sum(ctx.spend),
			"events": ctx.events, "actions_total": ctx.action_total(), "actions": ctx.actions,
			"net_per_action": snappedf(float(w.market.money - money_start) / maxf(1.0, ctx.action_total()), 0.1),
			"season_days": season_days, "end_date": w.forest.today(),
		},
		"warnings": warnings,
		"daily": daily,
	}
	var path := _write(result)
	_print_summary(result, path)
	return 0

func _net(ctx) -> int:
	return _sum(ctx.income) - _sum(ctx.spend)

func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

func _total(d: Dictionary) -> float:
	var n := 0.0
	for k in d:
		n += float(d[k])
	return n

# その日の終わり(遊んで保存した後)の数字
func _snapshot(w: GameWorld) -> Dictionary:
	return {
		"date": w.forest.today(), "season": w.forest.season, "money": w.market.money,
		"trees": w.forest.trees.size(), "plots": w.land.plots.size(), "crops": w.garden.crops.size(),
		"produce_kg": _total(w.garden.produce), "fruit": _total(w.forest.produce),
		"preserves": _total(w.kitchen.stock), "firewood": w.kitchen.firewood, "logs": int(w.cabin.materials.get("log", 0)),
		"hives": w.bees.hives.size(), "honey_kg": float(w.bees.stock.get("honey", 0)),
		"cabin_done": w.cabin.is_complete(), "extension": w.cabin.has_extension(), "pond_dug": w.pond.is_dug(),
	}

# 保存して開き直し、もう一度保存した中身が同じか。違えば違う所のあたりを返す
func _save_roundtrip() -> String:
	var before: String = FileAccess.get_file_as_string(SAVE)
	var again := GameWorld.new()
	again.save_path = SAVE
	again.time.offset_seconds = _offset
	again.refresh_season()
	again.load_game()
	again.save_game()
	var after: String = FileAccess.get_file_as_string(SAVE)
	if after == before:
		return ""
	var at := 0
	while at < mini(before.length(), after.length()) and before[at] == after[at]:
		at += 1
	return "%s … → %s" % [before.substr(maxi(0, at - 60), 90), after.substr(at, 30)]

func _git(args: Array) -> String:
	var out := []
	var all := ["-C", ProjectSettings.globalize_path("res://")]
	all.append_array(args)
	if OS.execute("git", all, out) != 0 or out.is_empty():
		return ""
	return String(out[0]).strip_edges()

func _write(result: Dictionary) -> String:
	var out := String(_opts.out)
	if out == "":
		var tag := String(_opts.param).replace("=", "").replace(",", "_")
		out = "sim_out/%s%s_%s_%dd.json" % [_opts.plan, ("_" + tag) if tag != "" else "", _opts.start, int(_opts.days)]
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("ERROR: 書き出せなかった: ", out)
		return ""
	f.store_string(JSON.stringify(result, "  "))
	f.close()
	return out

func _print_summary(r: Dictionary, path: String) -> void:
	var s: Dictionary = r.summary
	print("遊び方 %s %s / %s から %d 日(%s まで)" % [r.meta.plan, r.meta.params, r.meta.start, r.meta.days, s.end_date])
	print("  季節ごとの日数: ", s.season_days)
	print("  起きたこと: ", s.events)
	print("  所持金: はじめ %d₽ → 最後 %d₽(いちばん少ない日 %d₽ %s・いちばん多い日 %d₽)" % [s.money_start, s.money_end, s.money_min, s.money_min_date, s.money_max])
	print("  稼ぎ %d₽: %s" % [s.income_total, s.income])
	print("  出費 %d₽: %s" % [s.spend_total, s.spend])
	print("  差し引き %+d₽・操作 %d 回(1 回あたり %+.1f₽): %s" % [s.net, s.actions_total, s.net_per_action, s.actions])
	for wmsg in r.warnings:
		print("  注意: ", wmsg)
	print("WROTE: ", path)
