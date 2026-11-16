extends RefCounted
## Resolve visual overrides separately from physics materials and global defaults.

## An absent override preserves the rendering of existing scene files.
static func material(spec: Dictionary, render: Dictionary) -> Dictionary:
	var result := render.duplicate(true)
	var custom: Dictionary = spec.get("appearance", {}).get("material", {})
	if custom.get("mode", "inherit") == "custom":
		for key in ["roughness", "metallic", "emission", "neon"]:
			if custom.has(key): result[key] = custom[key]
	return result

## The global effects master switch remains authoritative; other controls may be local.
static func effects(spec: Dictionary, global: Dictionary) -> Dictionary:
	var result := global.duplicate(true)
	var custom: Dictionary = spec.get("appearance", {}).get("effects", {})
	if custom.get("mode", "inherit") == "custom": result.merge(custom, true)
	result["enabled"] = bool(global.get("enabled", true)) and bool(result.get("enabled", true))
	return result

## Descendants read the edited appearance of their initial root without changing the Take.
static func definition(id: String, definitions: Dictionary, initial: Dictionary) -> Dictionary:
	var result: Dictionary = definitions.get(id, {}).duplicate()
	var root_id := str(result.get("root_id", id))
	if initial.has(root_id): result["appearance"] = initial[root_id].get("appearance", {})
	return result
