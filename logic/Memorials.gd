extends RefCounted

# ── 記念樹と歳時記(描画を持たない。2026-11-23) ──────────────────────
# 土地の木に名前と一言のメモを付けて、記念樹にする(Hermes のレビューの案 1 を小さく始める形。ROADMAP)。
# - 木は配列の順番ではなく、変わらない番号(Forest の tree.id)で指す
# - 伐っても、芽が出なくても、記録は消さずに「なくなった日」を残す(歳時記に残る)
# - 何日目かは樹齢ではなく暦の日で数える(木は 1 日で 1 年、人は 30 日で 1 年なので混ぜない)
# - 連続ログインの報酬のような得は付けない。名前を付けても、育ち方・収穫は変わらない
# 今日と明日を見る日記(ベッド・寝袋)とは分け、記録は Y の画面(歳時記)でめくる。文言は Main
const SaveRead = preload("res://logic/SaveRead.gd")
const Family = preload("res://logic/Family.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const NAME_MAX := 12  # 木の名前の文字数の上限(「長男が生まれた日のコナラ」が入る長さ)
const NOTE_MAX := 40  # 一言のメモの文字数の上限

var forest = null  # Forest(GameWorld が設定する)
# [{tree_id: int, species, name, note, named_on: "YYYY-MM-DD", planted_on: "YYYY-MM-DD", gone_on: ""(今もある)}]。名付けた順
var records := []

func _commit() -> void:
	changed.emit()
	dirty.emit()

# 今ある木の記録。なければ {}
func record_for(tree: Dictionary) -> Dictionary:
	var id := int(tree.get("id", 0))
	if id <= 0:
		return {}
	for r in records:
		if r.tree_id == id and r.gone_on == "":
			return r
	return {}

# 木に名前とメモを付ける / 付け直す。名前を空にすると、記念樹をやめる(記録も消す。付け間違いを直せるように)
# 結果: named / renamed / same / cleared / empty / too_long / note_too_long / young(芽が出る前の種)
func name_tree(tree: Dictionary, new_name: String, new_note := "") -> String:
	var n := Family.clean_name(new_name)
	var note := Family.clean_name(new_note)
	var r := record_for(tree)
	if n == "":
		if r.is_empty():
			return "empty"
		records.erase(r)
		_commit()
		return "cleared"
	if n.length() > NAME_MAX:
		return "too_long"
	if note.length() > NOTE_MAX:
		return "note_too_long"
	if not forest.is_established(tree):
		return "young"
	if not r.is_empty():
		if r.name == n and r.note == note:
			return "same"
		r.name = n
		r.note = note
		_commit()
		return "renamed"
	records.append({
		"tree_id": int(tree.id), "species": str(tree.species), "name": n, "note": note,
		"named_on": forest.today(), "planted_on": forest.date_of_day(forest.planted_day(tree)), "gone_on": "",
	})
	_commit()
	return "named"

# Forest.tree_removed から: 記念樹がなくなった日を残す
func on_tree_removed(tree: Dictionary) -> void:
	var r := record_for(tree)
	if r.is_empty():
		return
	r.gone_on = forest.today()
	_commit()

# pos から max_dist 以内でいちばん近い、今ある記念樹の [木, 記録]。なければ []
func nearest(pos: Vector2, max_dist: float) -> Array:
	var best := []
	var best_d := max_dist
	for r in records:
		if r.gone_on != "":
			continue
		var t: Dictionary = forest.tree_by_id(r.tree_id)
		if t.is_empty():
			continue
		var d: float = t.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = [t, r]
	return best

# 今ある記念樹の数
func standing_count() -> int:
	return records.filter(func(r): return r.gone_on == "").size()

# その日付から今日までの暦の日数(今日なら 0)
func days_since(date: String) -> int:
	return forest.day_number() - int(Time.get_unix_time_from_datetime_string(date) / 86400.0)

# 今日が、その日付から何年目の同じ月日か(1 年以上たった同じ月日なら年数、ちがえば 0)。2/29 は平年なら 2/28 に数える
func anniversary_years(date: String) -> int:
	var today: String = forest.today()
	var years := int(today.substr(0, 4)) - int(date.substr(0, 4))
	if years <= 0:
		return 0
	var md := date.substr(5, 5)
	if md == "02-29" and not _is_leap(int(today.substr(0, 4))):
		md = "02-28"
	return years if today.substr(5, 5) == md else 0

static func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"records": records.duplicate(true)}

# 記念樹の記録がないセーブ(2026-11-23 より前)は、記念樹なしから。読めない記録は 1 件ずつ飛ばす
func from_save(d: Dictionary) -> void:
	records.clear()
	for item in SaveRead.list(d.get("records")):
		var r := SaveRead.dict(item)
		var n := Family.clean_name(SaveRead.text(r, "name"))
		var id := SaveRead.whole(r, "tree_id")
		var named_on := SaveRead.text(r, "named_on")
		if n == "" or n.length() > NAME_MAX or id <= 0 or not _is_date(named_on):
			continue
		var planted_on := SaveRead.text(r, "planted_on")
		var gone_on := SaveRead.text(r, "gone_on")
		records.append({
			"tree_id": id, "species": SaveRead.text(r, "species"), "name": n,
			"note": Family.clean_name(SaveRead.text(r, "note")).left(NOTE_MAX),
			"named_on": named_on, "planted_on": planted_on if _is_date(planted_on) else named_on,
			"gone_on": gone_on if _is_date(gone_on) else "",
		})
	changed.emit()

static func _is_date(s: String) -> bool:
	return s.length() == 10 and s[4] == "-" and s[7] == "-" and s.substr(0, 4).is_valid_int() \
		and s.substr(5, 2).is_valid_int() and s.substr(8, 2).is_valid_int()
