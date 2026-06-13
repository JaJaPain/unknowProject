class_name ValidationResult
extends RefCounted

var errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []


func is_valid() -> bool:
	return errors.is_empty()


func add_error(
	code: String,
	message: String,
	path: String = ""
) -> ValidationResult:
	errors.append(_make_issue(code, message, path))
	return self


func add_warning(
	code: String,
	message: String,
	path: String = ""
) -> ValidationResult:
	warnings.append(_make_issue(code, message, path))
	return self


func merge(
	other: ValidationResult,
	path_prefix: String = ""
) -> ValidationResult:
	if other == null:
		return self
	for issue in other.errors:
		errors.append(_with_prefix(issue, path_prefix))
	for issue in other.warnings:
		warnings.append(_with_prefix(issue, path_prefix))
	return self


func summary() -> String:
	if is_valid() and warnings.is_empty():
		return "valid"
	if is_valid():
		return "valid with %d warning(s)" % warnings.size()
	return "%d error(s), %d warning(s)" % [errors.size(), warnings.size()]


func to_dict() -> Dictionary:
	return {
		"valid": is_valid(),
		"errors": errors.duplicate(true),
		"warnings": warnings.duplicate(true),
	}


static func _make_issue(
	code: String,
	message: String,
	path: String
) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"path": path,
	}


static func _with_prefix(issue: Dictionary, prefix: String) -> Dictionary:
	var copy := issue.duplicate(true)
	if prefix.is_empty():
		return copy
	var issue_path := str(copy.get("path", ""))
	copy["path"] = prefix if issue_path.is_empty() else "%s.%s" % [
		prefix,
		issue_path,
	]
	return copy
