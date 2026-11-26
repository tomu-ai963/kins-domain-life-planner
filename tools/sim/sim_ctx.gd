extends RefCounted

# シミュレーションの記録係(2026-11-26)。遊び方(tools/sim/plans/)は、お金が動く操作をここを通して呼ぶ。
# 操作の前後の所持金の差を見て、何で稼いで(income)何に使ったか(spend)を分けて数える。
# ここを通らずに動いたお金は、run_sim.gd が日ごとの差から「other」に入れる。
# act() で操作の回数も数える(手間の目安。1 回 = キーを 1 回押す作業。市場へ行くのは 1 日 1 回と数える)

const Market = preload("res://logic/Market.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Garden = preload("res://logic/Garden.gd")

var income := {}   # {分類: ₽}
var spend := {}    # {分類: ₽}
var events := {}   # 起きたことの数 {名前: 回数}
var actions := {}  # 操作の回数 {種類: 回数}
var params := {}   # --param で渡した遊び方の設定 {名前: 値}
var market_used := false  # 今日、市場で売り買いしたか(run_sim が 1 日の終わりに「市場へ行った」1 回と数える)

func count(key: String, n := 1) -> void:
	events[key] = int(events.get(key, 0)) + n

func act(kind: String, n := 1) -> void:
	actions[kind] = int(actions.get(kind, 0)) + n

func action_total() -> int:
	var n := 0
	for k in actions:
		n += int(actions[k])
	return n

# 遊び方の設定。--param になければ fallback
func param(key: String, fallback):
	return params.get(key, fallback)

# f を呼び、所持金が増えたら income[category] に、減ったら spend[category] に足す。f の戻り値を返す
func track(w, category: String, f: Callable) -> Variant:
	var before: int = w.market.money
	var result = f.call()
	add_money(category, w.market.money - before)
	return result

# 所持金の増減 d を分類 category に足す(プラスは稼ぎ、マイナスは出費)
func add_money(category: String, d: int) -> void:
	if d > 0:
		income[category] = int(income.get(category, 0)) + d
	elif d < 0:
		spend[category] = int(spend.get(category, 0)) - d

# 市場で 1 つ買う。出費は品の form(material = 丸太、crop_seed = 野菜の種、sapling = 苗木、extension = 増築 など)で分ける
func buy(w, id: String) -> String:
	var g: Dictionary = Market.good(id)
	var r: String = track(w, String(g.get("form", "unknown")), func(): return w.market.buy(id))
	if r == "bought":
		market_used = true
	return r

# 収穫物を全部売る。稼ぎは sell_category で分ける
func sell_all(w, item: String) -> int:
	var got: int = track(w, sell_category(item), func(): return w.market.sell_all(item))
	if got > 0:
		market_used = true
	return got

# 冬に春の種を注文する
func order(w, kind: String) -> String:
	var r: String = track(w, "order", func(): return w.market.order(kind))
	if r == "ordered":
		market_used = true
	return r

static func sell_category(item: String) -> String:
	if item == "honey":
		return "honey"
	if Kitchen.RECIPES.has(item):
		return "preserves"
	if item.begins_with("seed_"):
		return "wild_seeds"
	if item.begins_with("seedling_"):
		return "seedlings"
	if item.begins_with("flour_"):
		return "flour"
	if item == "shiitake":
		return "shiitake"
	if Garden.CROPS.has(item):
		return "vegetables"
	return "fruit"

# 訪問者への決まった応え方(farmer・bees が使う。long_play はテストと同じ形を自分で持つ)。
# 頼まれたものを持っていれば渡す / 蜂を分けてもらう / 助けや贈り物を受け取る / 話すだけの日は話す
func visitors(w) -> void:
	var v = w.visitors
	if v.has_request():
		if track(w, "visitors", func(): return v.give()) == "given":
			count("given")
			act("visitor")
	elif v.has_bees():
		if v.receive_bees() == "received":
			count("bees_shared")
			act("visitor")
	elif v.has_help() or v.has_gift():
		if track(w, "visitors", func(): return v.receive_help()) == "received":
			count("gift_or_help")
			act("visitor")
	elif v.is_here() and v.visit.kind == "chat":
		v.finish_chat()
		act("visitor")
