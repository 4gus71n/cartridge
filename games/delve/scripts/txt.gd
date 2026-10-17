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
		return _contract(TranslationServer.translate(spec.f).format(args))
	if spec is String and spec.begins_with("#"):
		return TranslationServer.translate(spec.substr(1))
	return str(spec)


## Spanish contractions after placeholder substitution ("a el" -> "al").
static func _contract(s: String) -> String:
	if not TranslationServer.get_locale().begins_with("es"):
		return s
	return s.replace(" a el ", " al ").replace(" de el ", " del ").replace(" a el.", " al.")


static func cap(s: String) -> String:
	var i := 0
	while i < s.length() and s[i] in ["¡", "¿", "«", " "]:
		i += 1
	if i >= s.length():
		return s
	return s.substr(0, i) + s[i].to_upper() + s.substr(i + 1)


static func sentence(spec: Variant) -> String:
	return cap(render(spec))
