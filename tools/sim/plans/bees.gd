extends RefCounted

# 巣箱とはちみつで稼ぐ(2026-11-26)。とむの問い「はちみつが強すぎないか」を確かめるための遊び方。
# 1 日目に白樺の苗木を買って植え、丸太になったら斧で伐り(1 日 3 本まで)、自分の丸太で巣箱を作ってくり抜く。
# 蜂は自然に入るのを待つか、養蜂家が来たら分けてもらう。はちみつが harvest_kg 以上たまったら採り、全部売る。
# 小屋・池は作らない。訪問者には決まった形で応える(SimCtx.visitors)。
# 設定(--param): hives = 巣箱の数(既定 3。上限は Bees.MAX_HIVES)/ plots = 一緒に世話する区画の数(既定 0。
#   畑に野菜があると、はちみつが 1 日 +0.2kg 増える)/ harvest_kg = 採る量の目安(既定 4。巣箱は 5kg までたまる)

const Farm = preload("res://tools/sim/plans/_farm.gd")
const Bees = preload("res://logic/Bees.gd")

const DESCRIPTION := "巣箱とはちみつ(白樺の苗木 → 伐って自分の丸太 → 巣箱 → 蜂 → はちみつを採って売る)"
const TREE_ROW := Vector2(-20.0, -20.0)  # 白樺を植える列の西の端。東へ 4m おき
const HIVE_ROW := Vector2(-20.0, -10.0)  # 巣箱の列の西の端。東へ 5m おき(畑・井戸から離れている)

var hives := 3
var harvest_kg := 4
var trees := []  # 植えた白樺の場所
var spots := []  # 巣箱の場所
var farm

func setup(_w, ctx) -> void:
	hives = clampi(int(ctx.param("hives", 3)), 1, Bees.MAX_HIVES)
	harvest_kg = clampi(int(ctx.param("harvest_kg", 4)), 1, int(Bees.COMB_MAX))
	for i in range(hives * Bees.LOG_COST):  # 15 年で丸太 1 本なので、巣箱 1 つに 2 本
		trees.append(TREE_ROW + Vector2(4.0 * i, 0))
	for i in range(hives):
		spots.append(HIVE_ROW + Vector2(5.0 * i, 0))
	farm = Farm.new(int(ctx.param("plots", 0)))

func play_day(w, ctx, day: int) -> void:
	ctx.visitors(w)
	if day == 0:
		_plant(w, ctx)
	_fell(w, ctx)
	_hives(w, ctx)
	farm.day(w, ctx)
	if int(w.bees.stock.honey) > 0:
		ctx.sell_all(w, "honey")

# 白樺の苗木を買って植える(冬で植えられなければ、植えられる日まで毎日試す)
func _plant(w, ctx) -> void:
	for p in trees:
		if w.forest.plant_problem("birch", "sapling") != "":
			return
		if int(w.forest.saplings.get("birch", 0)) <= 0 and ctx.buy(w, "birch_sapling") != "bought":
			return
		if w.forest.add_tree(p, "birch", "sapling"):
			ctx.act("plant")

# 巣箱にまだ足りない丸太の分だけ、丸太になった白樺を伐る
func _fell(w, ctx) -> void:
	var placed: int = w.bees.hives.size()
	var need: int = (hives - placed) * Bees.LOG_COST - int(w.cabin.own_log_count())
	for p in trees:
		if need <= 0:
			return
		var i: int = w.forest.nearest_index(p, 0.5, "")
		if i < 0 or w.forest.wood_yield(w.forest.trees[i]) <= 0:
			continue
		var n: int = w.fell(p, 0.5)
		if n == -2:
			return  # 今日はもう斧を振れない
		if n > 0:
			ctx.act("fell")
			need -= n

func _hives(w, ctx) -> void:
	for p in spots:
		var h: Dictionary = w.bees.hive_near(p)
		if h.is_empty():
			if w.cabin.own_log_count() >= Bees.LOG_COST and w.bees.act(p, p) == "placed":
				ctx.act("hive")
				ctx.count("hive_placed")
			continue
		if not w.bees.is_hollowed(h):
			if w.bees.act(p, p) in ["hollowed", "finished"]:
				ctx.act("hive")
			continue
		if h.occupied and floori(float(h.comb)) >= harvest_kg:
			if w.bees.act(p, p) == "harvested":
				ctx.act("hive")
				ctx.count("honey_harvested_kg", int(w.bees.last_harvest))
