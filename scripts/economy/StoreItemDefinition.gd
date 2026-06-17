extends RefCounted

var item_id: String = ""
var display_name: String = ""
var description: String = ""
var category: String = "consumable"
var base_price: int = 0
var stack_max: int = 10
var restock_interval_minutes: int = 120
var restock_quantity: int = 2
var max_stock: int = 5


static func from_dict(data: Dictionary):
	var def = new()
	def.item_id = str(data.get("item_id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.description = str(data.get("description", ""))
	def.category = str(data.get("category", "consumable"))
	def.base_price = int(data.get("base_price", 0))
	def.stack_max = int(data.get("stack_max", 10))
	def.restock_interval_minutes = int(data.get("restock_interval_minutes", 120))
	def.restock_quantity = int(data.get("restock_quantity", 2))
	def.max_stock = int(data.get("max_stock", 5))
	return def
