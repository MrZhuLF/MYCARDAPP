extends Node

signal changed
var SAVE = "user://collection.json"
var images_dir = "user://images"
const GRADES = ["N", "R", "SR", "SSR"]
var data: Dictionary = {}
var last_error = ""
var textures: Dictionary = {}
var rng = RandomNumberGenerator.new()
var writable = true

func _ready() -> void:
	rng.randomize()
	if OS.get_cmdline_user_args().has("--test"):
		SAVE = "user://test-run/collection.json"
		images_dir = "user://test-run/images"
	DirAccess.make_dir_recursive_absolute(images_dir)
	load_data()

func uid() -> String:
	return "%x_%x" % [Time.get_unix_time_from_system()*1000000, rng.randi()]

func load_data() -> void:
	for path in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(path):
			var parsed = parse_json(FileAccess.get_file_as_string(path))
			if valid_data(parsed):
				data = parsed
				if path.ends_with(".bak"):
					last_error = "已从备份恢复存档"
				return
	if FileAccess.file_exists(SAVE) or FileAccess.file_exists(SAVE + ".bak"):
		writable = false
		last_error = "存档损坏，已停止写入。请从备份恢复。"
	data = {"version": 1, "coins": 1000, "series": [], "templates": [], "owned": [], "ledger": []}
	seed_demo()
	if writable:
		save_data()

func valid_data(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	for key in ["series", "templates", "owned", "ledger"]:
		if not value.get(key) is Array:
			return false
	if not value.get("coins") is float and not value.get("coins") is int:
		return false
	for s in value.series:
		if not s is Dictionary or not s.get("cards") is Array or not s.has("id"):
			return false
		for c in s.cards:
			if not c is Dictionary or not c.has("remaining") or not c.get("front") is Array or not c.get("back") is Array:
				return false
	return true

func parse_json(text: String) -> Variant:
	var parser = JSON.new()
	return parser.data if parser.parse(text) == OK else null

func save_data() -> bool:
	if not writable:
		return false
	var file = FileAccess.open(SAVE + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档"
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	# Keep an intact previous generation until the replacement is fully written.
	if FileAccess.file_exists(SAVE) and valid_data(parse_json(FileAccess.get_file_as_string(SAVE))):
		if DirAccess.copy_absolute(SAVE, SAVE + ".bak") != OK:
			last_error = "无法备份存档"
			return false
	var result = DirAccess.rename_absolute(SAVE + ".tmp", SAVE)
	if result != OK:
		last_error = "无法替换存档"
		return false
	changed.emit()
	return true

func commit(before: Dictionary) -> bool:
	if save_data():
		return true
	data = before
	return false

func series_by_id(id: String) -> Dictionary:
	for s in data.series:
		if s.id == id:
			return s
	return {}

func stock(s: Dictionary) -> int:
	var count = 0
	for c in s.get("cards", []):
		count += maxi(0, int(c.remaining))
	return count

func purchase(series_id: String) -> Dictionary:
	var s = series_by_id(series_id)
	if s.is_empty():
		return {"error": "系列不存在"}
	var amount = int(s.get("pack_size", 3))
	var cost = int(s.get("price", 100))
	if amount < 1 or cost < 0:
		return {"error": "牌包设置无效"}
	if int(data.coins) < cost:
		return {"error": "货币不足"}
	if stock(s) < amount:
		return {"error": "库存不足一包"}
	var before = data.duplicate(true)
	var results: Array = []
	for i in amount:
		var ticket = rng.randi_range(1, stock(s))
		for c in s.cards:
			ticket -= maxi(0, int(c.remaining))
			if ticket <= 0:
				c.remaining = int(c.remaining) - 1
				# Snapshot preserves collected cards if a design or series is later deleted.
				var snapshot = c.duplicate(true)
				snapshot["owned_id"] = uid()
				snapshot["series_name"] = s.name
				snapshot["series_id"] = s.id
				snapshot["acquired"] = Time.get_datetime_string_from_system()
				if snapshot.get("shared_back", true):
					snapshot.back = s.get("back", default_back()).duplicate(true)
				data.owned.append(snapshot)
				results.append(snapshot)
				break
	data.coins = int(data.coins) - cost
	data.ledger.push_front({"amount": -cost, "note": s.name, "time": Time.get_datetime_string_from_system()})
	if not commit(before):
		return {"error": last_error}
	return {"cards": results}

func adjust_coins(amount: int, note: String) -> bool:
	if int(data.coins) + amount < 0:
		last_error = "余额不能小于 0"
		return false
	var before = data.duplicate(true)
	data.coins = int(data.coins) + amount
	data.ledger.push_front({"amount": amount, "note": note, "time": Time.get_datetime_string_from_system()})
	return commit(before)

func import_image(path: String) -> String:
	var ext = path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]:
		last_error = "支持 PNG / JPG / WebP / SVG / BMP / TGA"
		return ""
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		last_error = "无法读取图片"
		return ""
	var target = images_dir + "/" + FileAccess.get_sha256(path) + "." + ext
	if not FileAccess.file_exists(target) and DirAccess.copy_absolute(path, target) != OK:
		last_error = "图片复制失败"
		return ""
	return target

func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if textures.has(path):
		return textures[path]
	if path.begins_with("res://"):
		var resource = load(path) as Texture2D
		textures[path] = resource
		return resource
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var tex = ImageTexture.create_from_image(img)
	textures[path] = tex
	return tex

func layer(kind: String, label: String, rect: Array, value: String, color = "#edf3ef") -> Dictionary:
	return {"id": uid(), "kind": kind, "label": label, "x": rect[0], "y": rect[1], "w": rect[2], "h": rect[3], "rotation": 0, "value": value, "color": color, "font_size": 30, "placeholder": kind != "shape", "visible": true, "locked": false, "fit": "contain"}

func default_front(index = 0) -> Array:
	var colors = ["#1e766f", "#60528b", "#a1673a"]
	return [layer("shape", "底色", [0,0,600,840], "", "#101b23"), layer("shape", "牌框", [16,16,568,808], "", colors[index % 3]), layer("shape", "内框", [22,22,556,796], "", "#111e28"), layer("image", "主图", [38,86,524,538], "res://assets/art_%d.svg" % (index % 3)), layer("text", "名称", [40,30,510,50], "CARD / %02d" % (index+1)), layer("text", "属性", [42,653,510,48], "ATK  120     /     DEF  80", "#d2ba83"), layer("text", "记录", [42,720,510,88], "点击编辑内容", "#a8b4c3")]

func default_back() -> Array:
	return [layer("shape", "底色", [0,0,600,840], "", "#142633"), layer("image", "卡背", [30,30,540,780], "res://assets/back.svg")]

func new_card(index = 0) -> Dictionary:
	return {"id": uid(), "name": "新卡牌", "grade": "N", "effect": 0, "remaining": 20, "shared_back": true, "front": default_front(index), "back": default_back(), "attributes": ""}

func new_series() -> Dictionary:
	return {"id": uid(), "name": "新系列", "price": 100, "pack_size": 3, "cover": "", "pack_back": "", "back": default_back(), "cards": []}

func seed_demo() -> void:
	for i in 3:
		var s = new_series()
		s.name = ["深海", "轨道", "遗迹"][i]
		s.cover = "res://assets/art_%d.svg" % i
		for j in 4:
			var c = new_card(i)
			c.name = "%s %02d" % [s.name, j+1]
			c.front[4].value = c.name
			c.grade = GRADES[j]
			c.effect = j
			c.remaining = [40,20,8,2][j]
			s.cards.append(c)
		data.series.append(s)

func export_backup(path: String) -> bool:
	var zip = ZIPPacker.new()
	if zip.open(path) != OK:
		return false
	zip.start_file("collection.json")
	zip.write_file(JSON.stringify(data).to_utf8_buffer())
	zip.close_file()
	for filename in DirAccess.get_files_at(images_dir):
		zip.start_file("images/" + filename)
		zip.write_file(FileAccess.get_file_as_bytes(images_dir + "/" + filename))
		zip.close_file()
	return zip.close() == OK

func restore_backup(path: String) -> bool:
	var zip = ZIPReader.new()
	if zip.open(path) != OK:
		last_error = "无法打开备份"
		return false
	var candidate = parse_json(zip.read_file("collection.json").get_string_from_utf8())
	if not valid_data(candidate):
		zip.close()
		last_error = "备份格式无效"
		return false
	for entry in zip.get_files():
		if entry.ends_with("/"):
			continue
		if entry.begins_with("images/"):
			var filename = entry.trim_prefix("images/")
			if filename.contains("/") or filename.contains("\\") or filename.contains(".."):
				zip.close()
				last_error = "备份路径无效"
				return false
			var target = images_dir + "/" + filename
			# Content-addressed original files are immutable; never overwrite existing assets.
			if not FileAccess.file_exists(target):
				var file = FileAccess.open(target, FileAccess.WRITE)
				if file == null:
					zip.close()
					last_error = "无法恢复图片"
					return false
				file.store_buffer(zip.read_file(entry))
				file.close()
	zip.close()
	var before = data
	data = candidate
	var was_writable = writable
	writable = true
	if not commit(before):
		writable = was_writable
		return false
	textures.clear()
	return true
