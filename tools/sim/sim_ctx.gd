extends RefCounted

# シミュレーションの記録係(2026-11-26)。遊び方(tools/sim/plans/)は、お金が動く操作をここを通して呼ぶ。
# 操作の前後の所持金の差を見て、何で稼いで(income)何に使ったか(spend)を分けて数える。
# ここを通らずに動いたお金は、run_sim.gd が日ごとの差から「other」に入れる

const Market = preload("res://logic/Market.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Garden = preload("res://logic/Garden.gd")

var income := {}   # {分類: ₽}
var spend := {}    # {分類: ₽}
var events := {}   # 起きたことの数 {名前: 回数}

func count(key: String, n := 1) -> void:
	events[key] = int(events.get(key, 0)) + n

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

# 市場で 1 つ買う。出費は品の form(material = 丸太、crop_seed = 野菜の種、extension = 増築 など)で分ける
func buy(w, id: String) -> String:
	var g: Dictionary = Market.good(id)
	return track(w, String(g.get("form", "unknown")), func(): return w.market.buy(id))

# 収穫物を全部売る。稼ぎは sell_category で分ける
func sell_all(w, item: String) -> int:
	return track(w, sell_category(item), func(): return w.market.sell_all(item))

# 冬に春の種を注文する
func order(w, kind: String) -> String:
	return track(w, "order", func(): return w.market.order(kind))

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
