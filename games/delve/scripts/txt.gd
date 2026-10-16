class_name Txt
extends RefCounted
## Renders language-neutral text specs. A spec is either a plain value, a
## "#KEY" string (translated) or {"f": KEY, "a": [specs]} where the
## translated template uses {0}, {1}… placeholders.


static func render(spec: Variant) -> String:
	if spec is Dictionary:
		var args := []
		for a in spec.get("a", []):
			args.append(render(a))
		return TranslationServer.translate(spec.f).format(args)
	if spec is String and spec.begins_with("#"):
		return TranslationServer.translate(spec.substr(1))
	return str(spec)


static func cap(s: String) -> String:
	if s.is_empty():
		return s
	return s[0].to_upper() + s.substr(1)


static func sentence(spec: Variant) -> String:
	return cap(render(spec))
