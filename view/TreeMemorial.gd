extends ColorRect

# ── 記念樹の名前とメモを付ける画面と、歳時記(2D と 3D で共通。HUD が持つ。2026-11-23) ──────────────
# 木のそばで Y(タッチはメニューの「名前」)で開く。名前と一言のメモの欄、その下に歳時記(記念樹の記録と暮らしの節目を日付の順に)を出す。
# 「決める」で decided(名前, メモ)を出す。ルールは logic/Memorials.gd、文言は Main(view/main/TreeMemorials.gd)
const Memorials = preload("res://logic/Memorials.gd")
const BUTTON_SIZE := Vector2(160, 40)
const TOUCH_BUTTON_SIZE := Vector2(180, 52)
const NAME_WIDTH := 320.0
const CHRONICLE_ROWS := 8  # 歳時記に出す行の数(新しいものから)

signal decided(tree_name, note)
signal closed

var touch_mode := false
var _title: Label
var _info: Label
var _name_edit: LineEdit
var _note_edit: LineEdit
var _chronicle: Label
var _buttons := []

func _init() -> void:
	color = Color(0.05, 0.07, 0.05, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.text = "記念樹"
	box.add_child(_title)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 12)
	rows.add_theme_constant_override("v_separation", 8)
	box.add_child(rows)
	_name_edit = _add_row(rows, "名前", Memorials.NAME_MAX, "例: 長男が生まれた日のコナラ")
	_note_edit = _add_row(rows, "メモ", Memorials.NOTE_MAX, "例: 春の朝、みんなで植えた")
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "名前は%d文字・メモは%d文字まで。名前を空にして決めると、記念樹をやめます。\n名前を付けても、木の育ち方や収穫は変わりません。" % [Memorials.NAME_MAX, Memorials.NOTE_MAX]
	box.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	for pair in [["決める", _decide], ["やめる", _cancel]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		buttons.add_child(b)
		_buttons.append(b)
	_chronicle = Label.new()
	box.add_child(_chronicle)

func _add_row(rows: GridContainer, label_text: String, max_len: int, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(label)
	var edit := LineEdit.new()
	edit.max_length = max_len
	edit.placeholder_text = placeholder
	edit.text_submitted.connect(func(_t): _decide())
	rows.add_child(edit)
	return edit

# info は木の 1 行(樹種・植えた日など)。chronicle は歳時記の行(古い順。多ければ新しい CHRONICLE_ROWS 行だけ出す)
func open(info: String, current_name: String, current_note: String, chronicle: PackedStringArray) -> void:
	_info.text = info
	_name_edit.text = current_name
	_note_edit.text = current_note
	var h: float = TOUCH_BUTTON_SIZE.y if touch_mode else BUTTON_SIZE.y
	for e in [_name_edit, _note_edit]:
		e.custom_minimum_size = Vector2(NAME_WIDTH, h)
	for b in _buttons:
		b.custom_minimum_size = TOUCH_BUTTON_SIZE if touch_mode else BUTTON_SIZE
	var lines := PackedStringArray(["─ 歳時記 ─"])
	if chronicle.is_empty():
		lines.append("まだ記録はありません")
	else:
		if chronicle.size() > CHRONICLE_ROWS:
			lines.append("(前の %d 件は省略)" % (chronicle.size() - CHRONICLE_ROWS))
		lines.append_array(chronicle.slice(chronicle.size() - CHRONICLE_ROWS) if chronicle.size() > CHRONICLE_ROWS else chronicle)
	_chronicle.text = "\n".join(lines)
	visible = true
	_name_edit.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _decide() -> void:
	var n := _name_edit.text
	var note := _note_edit.text
	close()
	decided.emit(n, note)

func _cancel() -> void:
	close()
	closed.emit()

# ── テスト用 ──
func type_text(tree_name: String, note := "") -> void:
	_name_edit.text = tree_name
	_note_edit.text = note

func chronicle_text() -> String:
	return _chronicle.text

func info_text() -> String:
	return _info.text

func press(text: String) -> bool:
	for b in _buttons:
		if b.text == text:
			b.pressed.emit()
			return true
	return false
