extends Node

signal changed
var SAVE = "user://collection.json"
var images_dir = "user://images"
const GRADES = ["N", "R", "SR", "SSR", "UR"]
const GRADE_COLORS = [Color("e8eef5"),Color("469bff"),Color("a066ff"),Color("f5d24b"),Color("ff853d")]
var vault_unlocked = false
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
	if value.has("vault"):
		if not value.vault is Dictionary or not value.vault.get("salt") is String or not value.vault.get("hash") is String: return false
	for key in ["series", "templates", "owned", "ledger"]:
		if not value.get(key) is Array:
			return false
	if not valid_number(value.get("coins")) or value.coins < 0:
		return false
	for s in value.series:
		if not s is Dictionary or not s.get("cards") is Array or not s.get("id") is String or not s.get("name") is String:
			return false
		if not valid_number(s.get("price")) or s.price < 0 or not valid_number(s.get("pack_size")) or s.pack_size < 1:
			return false
		if not s.get("cover") is String or not s.get("pack_back") is String or not valid_layers(s.get("back")):
			return false
		if not valid_layers(s.get("pack_front_layers",[])) or not valid_layers(s.get("pack_back_layers",[])):
			return false
		for c in s.cards:
			if not valid_card(c):
				return false
	for c in value.owned:
		if not valid_card(c) or not c.get("series_name") is String or not c.get("owned_id") is String:
			return false
	for t in value.templates:
		if not t is Dictionary or not t.get("name") is String or not t.get("id") is String or not valid_layers(t.get("front")) or not valid_layers(t.get("back")):
			return false
	for e in value.ledger:
		if not e is Dictionary or not valid_number(e.get("amount")) or not e.get("note") is String or not e.get("time") is String:
			return false
	return true

func valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func valid_layers(value: Variant) -> bool:
	if not value is Array: return false
	for l in value:
		if not l is Dictionary: return false
		for key in ["id","kind","label","value","color"]:
			if not l.get(key) is String: return false
		if l.kind not in ["image","text","shape"]: return false
		for key in ["x","y","w","h"]:
			if not valid_number(l.get(key)): return false
		if l.w <= 0 or l.h <= 0 or not valid_number(l.get("rotation",0)) or not valid_number(l.get("font_size",30)): return false
	return true

func valid_card(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["id","name","grade"]:
		if not value.get(key) is String: return false
	return valid_number(value.get("remaining")) and value.remaining >= 0 and valid_number(value.get("effect")) and value.effect >= 0 and value.effect <= 3 and valid_layers(value.get("front")) and valid_layers(value.get("back"))

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
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = "存档写入不完整"
		return false
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
		if not visible_item(c) or not visible_item(s): continue
		count += maxi(0, int(c.remaining))
	return count

func purchase(series_id: String) -> Dictionary:
	var s = series_by_id(series_id)
	if s.is_empty():
		return {"error": "系列不存在"}
	if not visible_item(s): return {"error": "请先解锁保险箱"}
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
			if not visible_item(c) or int(c.remaining) <= 0: continue
			ticket -= maxi(0, int(c.remaining))
			if ticket <= 0:
				c.remaining = int(c.remaining) - 1
				# Snapshot preserves collected cards if a design or series is later deleted.
				var snapshot = c.duplicate(true)
				snapshot["owned_id"] = uid()
				snapshot["series_name"] = s.name
				snapshot["series_id"] = s.id
				snapshot["hidden"] = bool(s.get("hidden",false)) or bool(c.get("hidden",false))
				snapshot["acquired"] = Time.get_datetime_string_from_system()
				if snapshot.get("shared_back", true):
					snapshot.back = s.get("back", default_back()).duplicate(true)
				data.owned.append(snapshot)
				results.append(snapshot)
				break
	data.coins = int(data.coins) - cost
	data.ledger.push_front({"amount": -cost, "note": s.name, "series_id":s.id, "hidden":s.get("hidden",false), "time": Time.get_datetime_string_from_system()})
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
	# Android's Storage Access Framework returns content:// URIs without extensions.
	# Identify actual bytes, not a display filename or URI suffix.
	var bytes = FileAccess.get_file_as_bytes(path)
	var ext = image_format(bytes)
	if ext.is_empty():
		last_error = "支持 PNG / JPG / WebP / SVG / BMP / TGA"
		return ""
	var img = Image.new()
	if img.call("load_"+ext+"_from_buffer",bytes) != OK or img.is_empty():
		last_error = "无法读取图片"
		return ""
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var target = images_dir + "/" + hash.finish().hex_encode() + "." + ext
	if not FileAccess.file_exists(target):
		var file = FileAccess.open(target,FileAccess.WRITE)
		if file == null:
			last_error = "图片复制失败"
			return ""
		file.store_buffer(bytes)
		var write_error = file.get_error()
		file.close()
		if write_error != OK:
			DirAccess.remove_absolute(target)
			last_error = "图片写入不完整"
			return ""
	return target

func image_format(bytes: PackedByteArray) -> String:
	if bytes.size() < 12: return ""
	if bytes.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10]): return "png"
	if bytes[0] == 255 and bytes[1] == 216 and bytes[2] == 255: return "jpg"
	if bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP": return "webp"
	if bytes[0] == 66 and bytes[1] == 77: return "bmp"
	if bytes[0] in [60,32,9,10,13,239] and bytes.slice(0,mini(2048,bytes.size())).get_string_from_ascii().contains("<svg"): return "svg"
	if bytes.size() > 18 and bytes[1] in [0,1] and bytes[2] in [1,2,3,9,10,11] and bytes[16] in [8,16,24,32]: return "tga"
	return ""

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
	var front = default_front(index)
	front[4].value = "新卡牌"
	return {"id": uid(), "name": "新卡牌", "grade": "N", "effect": 0, "remaining": 20, "shared_back": true, "front": front, "back": default_back(), "attributes": "ATK  120     /     DEF  80"}

func new_series() -> Dictionary:
	return {"id": uid(), "name": "新系列", "price": 100, "pack_size": 3, "cover": "", "pack_back": "", "pack_front_layers": [], "pack_back_layers": [], "back": default_back(), "cards": []}

func pack_layers(s: Dictionary, back = false) -> Array:
	var layers = s.get("pack_back_layers" if back else "pack_front_layers",[])
	if not layers.is_empty():
		return layers
	var path = s.get("pack_back" if back else "cover","")
	if path.is_empty(): path = "res://assets/back.svg" if back else "res://assets/art_0.svg"
	return [layer("image","封面",[0,0,600,840],path,"#ffffff")]

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
	# SAF document providers may not support the read/write seeking used by ZIP.
	# Finish the archive locally, then stream it to the user's document URI.
	var staging = SAVE.get_base_dir()+"/backup-export.zip"
	if not write_backup_zip(staging):
		last_error = "生成备份失败"
		return false
	return copy_stream(staging,path)

func copy_stream(source: String, target: String) -> bool:
	if ProjectSettings.globalize_path(source) == ProjectSettings.globalize_path(target):
		return FileAccess.file_exists(source)
	var input = FileAccess.open(source,FileAccess.READ)
	if input == null:
		last_error = "无法读取备份"
		return false
	var output = FileAccess.open(target,FileAccess.WRITE)
	if output == null:
		last_error = "无法写入所选位置，请选择本机下载文件夹"
		return false
	var length = input.get_length()
	var written = 0
	while written < length:
		var chunk = input.get_buffer(mini(65536,length-written))
		if chunk.is_empty(): break
		output.store_buffer(chunk)
		if output.get_error() != OK: break
		written += chunk.size()
	output.flush()
	var success = written == length and output.get_error() == OK
	input.close()
	output.close()
	if not success: last_error = "备份写入不完整，请更换保存位置"
	return success

func write_backup_zip(path: String) -> bool:
	var zip = ZIPPacker.new()
	if zip.open(path) != OK:
		return false
	if zip.start_file("collection.json") != OK or zip.write_file(JSON.stringify(data).to_utf8_buffer()) != OK or zip.close_file() != OK:
		zip.close()
		return false
	for filename in DirAccess.get_files_at(images_dir):
		if zip.start_file("images/" + filename) != OK or zip.write_file(FileAccess.get_file_as_bytes(images_dir + "/" + filename)) != OK or zip.close_file() != OK:
			zip.close()
			return false
	return zip.close() == OK

func restore_backup(path: String) -> bool:
	if path.begins_with("content://"):
		var local = SAVE.get_base_dir()+"/backup-import.zip"
		if not copy_stream(path,local): return false
		path=local
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
	vault_unlocked=false
	return true

func visible_item(item: Dictionary) -> bool:
	return vault_unlocked or not item.get("hidden",false)

func visible_series() -> Array:
	return data.series.filter(visible_item)

func owned_visible(card: Dictionary) -> bool:
	if not visible_item(card): return false
	var s = series_by_id(card.get("series_id",""))
	if not visible_item(s): return false
	for design in s.get("cards",[]):
		if design.id == card.id and not visible_item(design): return false
	return true

func discard_owned(id: String) -> bool:
	var before = data.duplicate(true)
	var found = false
	for i in data.owned.size():
		if data.owned[i].owned_id == id and owned_visible(data.owned[i]):
			data.owned.remove_at(i)
			found=true
			break
	if not found:
		last_error="卡牌不存在或已隐藏"
		return false
	return commit(before)

func has_vault() -> bool:
	return not data.get("vault",{}).get("hash","").is_empty()

func password_hash(password: String, salt: String) -> String:
	var result = (salt+password).sha256_text()
	for i in 12000: result=(result+salt).sha256_text()
	return result

func set_vault_password(password: String) -> bool:
	if has_vault() and not vault_unlocked:
		last_error="请先解锁保险箱"
		return false
	if password.length() < 4:
		last_error="密码至少 4 位"
		return false
	var before=data.duplicate(true)
	var salt=Crypto.new().generate_random_bytes(16).hex_encode()
	data["vault"]={"salt":salt,"hash":password_hash(password,salt)}
	if not commit(before): return false
	vault_unlocked=true
	return true

func unlock_vault(password: String) -> bool:
	if not has_vault(): return false
	if password_hash(password,data.vault.salt) != data.vault.hash:
		last_error="密码错误"
		return false
	vault_unlocked=true
	return true

func grade_color(grade: String) -> Color:
	return GRADE_COLORS[maxi(0,GRADES.find(grade))]

func propagate_hidden(series_id: String, card_id = "") -> void:
	# Preserve hidden state in collection snapshots even after deleting designs.
	for owned in data.owned:
		if owned.get("series_id","") == series_id and (card_id.is_empty() or owned.id == card_id):
			var s=series_by_id(series_id)
			if s.get("hidden",false): owned["hidden"]=true
			else:
				for c in s.get("cards",[]):
					if c.id == owned.id: owned["hidden"]=c.get("hidden",false)
	for entry in data.ledger:
		if entry.get("series_id","") == series_id:
			entry["hidden"]=series_by_id(series_id).get("hidden",false)
