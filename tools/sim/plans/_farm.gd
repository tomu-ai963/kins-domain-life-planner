extends RefCounted

# 畑の決まった世話(2026-11-26)。farmer と bees が使う部品で、これだけを --plan には渡さない。
# 井戸を掘り、区画を作り、1 日あたりのもうけがいちばん多い野菜をまき、草を抜き、ジョウロで水をやり、収穫して全部売る。
# 操作はゲームの中と同じ入口(GameWorld.well_action・toggle_plot・plant_crop・fill_can・water_plot)を通す。
# ジョウロは はじめの 5L のまま(5 か所ごとに井戸で汲む)。苗からしか育たない野菜(トマト)と田んぼの米はまかない

const Garden = preload("res://logic/Garden.gd")
const Market = preload("res://logic/Market.gd")

const ORIGIN := Vector2(1.5, 25.5)  # 1 つ目の区画の中心(test_long_play と同じ)。東へ 4 列、南へ行を足す
const COLUMNS := 4
const WELL := Vector2(-3.0, 27.0)    # 井戸(区画の西。区画にかからない)

var plots := []  # 区画の中心 [Vector2]

func _init(count: int) -> void:
	for i in range(count):
		plots.append(ORIGIN + Vector2(3.0 * (i % COLUMNS), 3.0 * (i / COLUMNS)))

func day(w, ctx) -> void:
	if plots.is_empty():
		return
	# 井戸: 1 日目に場所を決め、3 日で掘る
	if not w.well.is_dug():
		var r: String = w.well_action(WELL, WELL)
		if r in ["placed", "dug", "finished"]:
			ctx.act("well")
	# 区画(1 日 2 つまで)
	for p in plots:
		if w.land.plot_at(p) == null and w.toggle_plot(p) == "placed":
			ctx.act("plot")
	for p in plots:
		if w.land.plot_at(p) == null:
			continue
		var crop: Dictionary = w.garden.crop_at(p)
		if not crop.is_empty() and w.garden.is_ripe(crop):
			if w.garden.harvest_at(p) == "harvested":
				ctx.act("harvest")
				ctx.count("harvest")
		if w.garden.crop_at(p).is_empty():
			var kind := best_crop(w)
			if kind != "":
				if int(w.garden.seeds.get(kind, 0)) <= 0 and int(w.seedlings.ready.get(kind, 0)) <= 0:
					ctx.buy(w, seed_good(kind).get("id", ""))
				if w.plant_crop(p, kind).result == "sown":
					ctx.act("sow")
					ctx.count("sown_" + kind)
		crop = w.garden.crop_at(p)
		if crop.is_empty():
			continue
		if w.garden.has_weeds(crop) and w.garden.weed_at(p) == "weeded":
			ctx.act("weed")
		if not w.garden.is_ripe(crop) and not w.garden.watered_today(crop):
			if w.tools.can_water <= 0 and w.well.is_dug() and w.fill_can(WELL) == "filled":
				ctx.act("fill_can")
			if w.water_plot(p) == "watered":
				ctx.act("water")
	for kind in w.garden.produce:
		if int(w.garden.produce[kind]) > 0:
			ctx.sell_all(w, kind)

# 今まける野菜のうち、(収量 × 買い取り値 − 種の値段) ÷ 育つ日数 がいちばん多いもの。なければ ""。
# 霜に弱い野菜は、霜までに育ちきらないならまかない
func best_crop(w) -> String:
	var best := ""
	var best_value := 0.0
	for kind in Garden.CROPS:
		var c: Dictionary = Garden.CROPS[kind]
		if c.get("seedling_only", false) or c.get("paddy", false):
			continue
		if not w.garden.can_sow_now(kind):
			continue
		var g := seed_good(kind)
		if g.is_empty() or not w.market.sells(g):
			continue
		if not c.get("hardy", false) and int(c.grow_days) >= w.garden.days_to_frost():
			continue
		var value := (float(c.yield_kg) * float(Market.SELL_PRICES.get(kind, 0)) - float(g.price)) / float(c.grow_days)
		if value > best_value:
			best = kind
			best_value = value
	return best

# 野菜の種(か苗)の市場の品。なければ {}
static func seed_good(kind: String) -> Dictionary:
	for g in Market.GOODS:
		if g.form == "crop_seed" and g.species == kind:
			return g
	return {}
