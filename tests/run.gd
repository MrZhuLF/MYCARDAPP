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
	var invalid = Store.data.duplicate(true)
	invalid.series[0].cards[0].front[0].w = "invalid"
	check(not Store.valid_data(invalid),"invalid layer types are rejected before restoring")
	var s = Store.data.series[0]
	var initial = Store.stock(s)
	var result = Store.purchase(s.id)
	check(result.get("cards",[]).size() == 3,"pack yields configured card count")
	check(Store.data.coins == 900 and Store.stock(s) == initial-3,"coins and finite inventory decrease atomically")
	check(Store.data.owned.size() == 3,"all draws enter collection")
	var original_name = Store.data.owned[0].name
	for c in s.cards: c.name="changed"
	check(Store.data.owned[0].name == original_name,"collection keeps design snapshots")
	var discarded_id = Store.data.owned[0].owned_id
	check(Store.discard_owned(discarded_id) and Store.data.owned.size() == 2 and Store.data.coins == 900 and Store.stock(s) == initial-3,"discard removes only the owned copy without refund or restock")
	check(not Store.discard_owned(discarded_id),"discarding twice cannot mutate inventory")
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
	DirAccess.copy_absolute("res://assets/art_0.svg","user://test-run/opaque-document")
	check(Store.import_image("user://test-run/opaque-document") == image_path,"images without filename extensions are recognized by bytes")
	check(Store.export_backup("user://test-run/backup.zip"),"backup includes data and images")
	var saved_coins = int(Store.data.coins)
	Store.data.coins=1
	var restored = Store.restore_backup("user://test-run/backup.zip")
	check(restored and Store.data.coins == saved_coins,"backup restores balance")
	check(Store.set_vault_password("1234"),"vault password is set")
	check(Store.data.vault.hash.length() == 64 and Store.data.vault.salt.length() == 32 and not Store.data.vault.has("password"),"vault does not store plaintext password")
	Store.data.series[0]["hidden"]=true
	Store.propagate_hidden(Store.data.series[0].id)
	Store.vault_unlocked=false
	check(Store.visible_series().size() == 2 and Store.purchase(Store.data.series[0].id).has("error"),"locked series cannot appear on shelf or be purchased")
	check(Store.data.owned.filter(Store.owned_visible).is_empty(),"locked collection snapshots stay hidden")
	check(not Store.unlock_vault("wrong") and not Store.vault_unlocked,"wrong password never unlocks")
	check(Store.unlock_vault("1234") and Store.visible_series().size() == 3,"correct password restores hidden series")
	Store.data.series[1].cards[0]["hidden"]=true
	Store.vault_unlocked=false
	check(Store.stock(Store.data.series[1]) == 30,"hidden card stock excluded from public packs")
	Store.vault_unlocked=true
	check(Store.stock(Store.data.series[1]) == 70,"unlocked card stock included in packs")
	Store.vault_unlocked=false
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
	app.editor.center_layer(true)
	app.editor.center_layer(false)
	var centered=app.editor.draft.front[3]
	check(is_equal_approx(centered.x+centered.w/2,300) and is_equal_approx(centered.y+centered.h/2,420),"horizontal and vertical centering aligns the selected layer")
	app.editor.duplicate_layer()
	check(app.editor.draft.front.size() == 8,"editor duplicates independent layers")
	app.editor.undo()
	check(app.editor.draft.front.size() == 7,"editor undo restores layers")
	app.editor.redo()
	check(app.editor.draft.front.size() == 8,"editor redo restores changes")
	app.editor.canvas.active=7
	app.editor.delete_layer()
	check(app.editor.draft.front.size() == 7,"editor deletes selected layer")
	app.editor.save()
	await get_tree().process_frame
	app.edit_pack_surface("pack_front_layers")
	app.editor.add_layer("text")
	app.editor.save()
	await get_tree().process_frame
	check(Store.data.series[0].pack_front_layers.size() == 2,"pack cover uses the same layer editor")
	app.open_pack(Store.data.series[0].id)
	await screenshot("05-pack")
	app.overlay.get_child(1).item.rotation_degrees=Vector3(-10,48,0)
	await screenshot("05a-pack-curvature")
	app.overlay.get_child(1).item.rotation_degrees=Vector3(-4,-12,0)
	var balance_before = int(Store.data.coins)
	var hold = app.overlay.get_child(3).get_child(0)
	hold.pressed.emit()
	check(Store.data.coins == balance_before,"single click does not purchase")
	hold.button_down.emit()
	await get_tree().create_timer(0.7).timeout
	hold.button_up.emit()
	var progress=hold.progress
	check(progress > 0.2 and progress < 0.9 and Store.data.coins == balance_before,"partial hold opens seal without charging")
	await screenshot("05b-partial-tear")
	check(is_equal_approx(hold.progress,progress),"releasing pauses the tear")
	hold.button_down.emit()
	await get_tree().create_timer(1.8).timeout
	check(Store.data.coins == balance_before-100 and app.last_opened.size() == 3,"complete hold debits once and reveals the cards")
	await screenshot("06-card")
	app.view_cards([Store.data.series[0].cards[2]],0,Store.data.series[0].back)
	await screenshot("06b-holographic")
	app.overlay.get_child(1).item.rotation.y=PI-0.2
	await screenshot("06c-back")
	app.close_overlay()
	app.navigate("收藏")
	await screenshot("07-collection")
	app.navigate("记账")
	await screenshot("08-ledger")
	app.edit_series(Store.data.series[0])
	await screenshot("09-series-edit")
	app.close_overlay()
	app.show_licenses()
	await get_tree().process_frame
	app.close_overlay()
	for i in 8:
		var extra=Store.new_series()
		extra.name="系列 %d" % i
		Store.data.series.append(extra)
	app.navigate("货架")
	check(app.stage.display.find_children("*","StaticBody3D",true,false).size() == 9,"one series occupies one of nine shelf slots")
	app.stage.shelf_swiped.emit(1)
	check(app.shelf_page == 1 and app.stage.display.find_children("*","StaticBody3D",true,false).size() == 2,"swipe switches to next shelf without duplicate series")
	app.stage.shelf_swiped.emit(-1)
	Store.set_vault_password("5678")
	Store.data.series[0]["hidden"]=true
	Store.propagate_hidden(Store.data.series[0].id)
	app.open_pack(Store.data.series[0].id)
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not Store.vault_unlocked and not is_instance_valid(app.overlay) and Store.visible_series().size() == 10,"leaving app locks vault and removes private previews")
	Store.unlock_vault("5678")
	app.edit_card(Store.data.series[0].cards[0])
	app._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(not Store.vault_unlocked and app.editor == null and not app.suspended_editor.visible,"backgrounding hides editor drafts and locks vault")
	print("TEST_RESULT: %d failures" % failures)
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

func screenshot(label: String) -> void:
	await get_tree().create_timer(0.25).timeout
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	get_viewport().get_texture().get_image().save_png("res://test-output/"+label+".png")
