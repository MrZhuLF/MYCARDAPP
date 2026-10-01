extends Node

var failures = 0
var app: Control

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test"):
		push_error("Tests require -- --test (isolated storage)")
		get_tree().quit(2)
		return
	Store.data = {"version":1,"coins":1000,"series":[],"templates":[],"owned":[],"ledger":[]}
	Store.seed_demo()
	Store.writable = true
	check(Store.save_data(),"initial save")
	var s = Store.data.series[0]
	var initial = Store.stock(s)
	var result = Store.purchase(s.id)
	check(result.get("cards",[]).size() == 3,"pack yields configured card count")
	check(Store.data.coins == 900 and Store.stock(s) == initial-3,"coins and finite inventory decrease atomically")
	check(Store.data.owned.size() == 3,"all draws enter collection")
	var original_name = Store.data.owned[0].name
	for c in s.cards: c.name="changed"
	check(Store.data.owned[0].name == original_name,"collection keeps design snapshots")
	Store.data.coins = 0
	check(Store.purchase(s.id).has("error") and Store.stock(s) == initial-3,"insufficient balance never consumes stock")
	Store.data.coins = 100000
	for c in s.cards: c.remaining=0
	s.cards[0].remaining=2
	check(Store.purchase(s.id).has("error") and s.cards[0].remaining == 2,"partial packs cannot be charged")
	s.cards[0].remaining=3
	result = Store.purchase(s.id)
	check(result.cards.size() == 3 and s.cards[0].remaining == 0,"last copies are drawn without replacement")
	check(not Store.adjust_coins(-200000,"test"),"ledger disallows negative balances")
	var before = Store.data.duplicate(true)
	Store.writable = false
	check(not Store.adjust_coins(100,"test") and Store.data == before,"failed persistence rolls back balance and ledger")
	Store.writable = true
	check(Store.save_data(),"second generation save replaces existing file")
	var image_path = Store.import_image("res://assets/art_0.svg")
	check(not image_path.is_empty() and FileAccess.get_sha256(image_path) == FileAccess.get_sha256("res://assets/art_0.svg"),"original image imported without recompression")
	check(Store.export_backup("user://test-run/backup.zip"),"backup includes data and images")
	var saved_coins = int(Store.data.coins)
	Store.data.coins=1
	var restored = Store.restore_backup("user://test-run/backup.zip")
	print("RESTORE: ", restored, " actual=", Store.data.coins, " expected=", saved_coins, " error=", Store.last_error)
	check(restored and Store.data.coins == saved_coins,"backup restores balance")
	var damaged = FileAccess.open(Store.SAVE,FileAccess.WRITE)
	damaged.store_string("broken"); damaged.close()
	Store.load_data()
	check(Store.valid_data(Store.data),"corrupted primary recovers from backup")
	Store.data = {"version":1,"coins":1000,"series":[],"templates":[],"owned":[],"ledger":[]}
	Store.seed_demo()
	Store.save_data()
	Store.last_error = ""
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	await screenshot("01-shelf")
	app.navigate("设计")
	await screenshot("02-series")
	app.selected_series=Store.data.series[0].id
	app.cards_list()
	await screenshot("03-cards")
	app.edit_card(Store.data.series[0].cards[2])
	await screenshot("04-editor")
	app.editor.canvas.active=3
	app.editor.refresh_properties()
	app.editor.duplicate_layer()
	check(app.editor.draft.front.size() == 8,"editor duplicates independent layers")
	app.editor.undo()
	check(app.editor.draft.front.size() == 7,"editor undo restores layers")
	app.editor.redo()
	check(app.editor.draft.front.size() == 8,"editor redo restores changes")
	app.editor.delete_layer()
	app.editor.save()
	await get_tree().process_frame
	app.open_pack(Store.data.series[0].id)
	await screenshot("05-pack")
	var draw = Store.purchase(Store.data.series[0].id)
	var view = app.overlay.get_child(1)
	await view.tear()
	app.view_cards(draw.cards)
	await screenshot("06-card")
	app.close_overlay()
	app.navigate("收藏")
	await screenshot("07-collection")
	app.navigate("记账")
	await screenshot("08-ledger")
	app.edit_series(Store.data.series[0])
	await screenshot("09-series-edit")
	app.close_overlay()
	print("TEST_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func screenshot(label: String) -> void:
	await get_tree().create_timer(0.25).timeout
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	get_viewport().get_texture().get_image().save_png("res://test-output/"+label+".png")
