extends RefCounted

# tests/test_long_play.gd の「決まった遊び方」をそのまま移したもの(2026-11-26)。
# 11/1 から 121 日回すと、テストと同じ結果(最後の所持金・いちばん少ない日・起きたことの数)になる。シミュレーションの基準。
# 秋にしか種をまかないので、春と夏はほとんど何もしない(1 年回すなら別の遊び方を書く)

const DESCRIPTION := "test_long_play と同じ遊び方(小屋 → 増築 → 畑と池 → 薪と料理 → 頼みごと)"

const SITE := Vector2(20, 20)            # 小屋
const POND := Vector2(-20, 20)
const PLOTS := [Vector2(1.5, 25.5), Vector2(4.5, 25.5), Vector2(7.5, 25.5), Vector2(10.5, 25.5)]
const OUTSIDE := Vector2(20, 23.0)       # 小屋の南の外
const WEST := Vector2(13.0, 20.0)        # 増築する部屋の西の外
const START_BONUS := 20000               # 前の季節に貯めたお金(テストと同じ)

# 1 日目の前に 1 回。秋のうちに増築まで進められるよう、前の季節に貯めたお金があることにする
func setup(w, _ctx) -> void:
	w.market.money += START_BONUS

func play_day(w, ctx, day: int) -> void:
	var c = w.cabin
	var m = w.market
	if day == 0:
		c.place(SITE)
		w.pond_action(POND)
	for p in PLOTS:  # 区画は 1 日 2 つまでなので、2 日かけて作る
		if w.land.plot_at(p) == null:
			w.toggle_plot(p)
	# 小屋(丸太は市場で)
	if not c.is_complete():
		if c.materials.log < 5:
			ctx.buy(w, "logs")
		c.work(OUTSIDE)
	elif not c.ext_started():
		ctx.buy(w, "cabin_extension")
	elif c.ext_building():
		if c.materials.log < 4:
			ctx.buy(w, "logs")
		c.work_extension(WEST)
	# 池
	if not w.pond.is_dug():
		w.pond_action(POND)
	# 畑: 秋は 2 区画にニンニク(冬の漬物用。霜に強い)、2 区画にラディッシュ。収穫して、ラディッシュは売る。毎日水
	for i in range(PLOTS.size()):
		var p: Vector2 = PLOTS[i]
		var kind: String = "garlic" if i < 2 else "radish"
		var crop: Dictionary = w.garden.crop_at(p)
		if not crop.is_empty() and w.garden.is_ripe(crop):
			if w.garden.harvest_at(p) == "harvested":
				ctx.count("harvest")
		if w.garden.crop_at(p).is_empty() and w.forest.season == "autumn":
			if int(w.garden.seeds[kind]) <= 0:
				ctx.buy(w, kind + "_seed")
			w.garden.sow(p, kind)
		w.garden.water_at(p)
	if ctx.sell_all(w, "radish") > 0:
		ctx.count("sold")
	# 薪と料理(小屋ができてから)。薪は 10 回分まで割っておく
	var k = w.kitchen
	if c.is_complete():
		while k.firewood < 10 and (k.log_left > 0 or c.materials.log > 0):
			k.split()
		if c.materials.log <= 0:
			ctx.buy(w, "logs")
		for i in range(2 if c.has_extension() else 1):
			k.active = i
			if k.is_ready():
				k.collect()
			if k.is_empty():
				if k.start("pickles") == "started" or k.start("garlic_pickle") == "started" or _cook_any(k) == "started":
					ctx.count("cooked_kamado" if i == 1 else "cooked")
		k.active = 0
	# 頼みごと: 渡せるものなら渡す。薪は足りなければ割ってから
	var v = w.visitors
	if v.has_request():
		if v.visit.item == v.FIREWOOD:
			while k.firewood < int(v.visit.amount) and k.split() == "split":
				pass
		if ctx.track(w, "visitors", func(): return v.give()) == "given":
			ctx.count("given")
			if v.visit.item == v.FIREWOOD:
				ctx.count("firewood_given")
	elif v.has_help() or v.has_gift():
		ctx.track(w, "visitors", func(): return v.receive_help())
	elif v.is_here() and v.visit.kind == "chat":
		v.finish_chat()
	# 冬は春の種を注文する(ラディッシュを 5 つまで)
	if m.can_order() and int(m.orders.get("radish", 0)) < 5:
		ctx.order(w, "radish")

# 材料のある保存食を 1 つ仕込む
func _cook_any(k) -> String:
	for id in k.RECIPES:
		if k.input_count(id) >= int(k.RECIPES[id].amount):
			return k.start(id)
	return "none"
