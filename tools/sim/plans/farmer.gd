extends RefCounted

# 畑だけで稼ぐ(2026-11-26)。はちみつの強さを比べる相手。
# 小屋・池・木・巣箱は作らない。訪問者には決まった形で応える(SimCtx.visitors)。
# 設定(--param): plots = 区画の数(既定 4)

const Farm = preload("res://tools/sim/plans/_farm.gd")

const DESCRIPTION := "畑だけ(井戸を掘り、もうけの多い野菜をまいて、草取り・ジョウロの水やり・収穫・売る)"

var farm

func setup(_w, ctx) -> void:
	farm = Farm.new(int(ctx.param("plots", 4)))

func play_day(w, ctx, _day: int) -> void:
	ctx.visitors(w)
	farm.day(w, ctx)
