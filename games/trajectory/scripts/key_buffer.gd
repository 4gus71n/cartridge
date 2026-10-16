class_name KeyBuffer
extends RefCounted
## Text buffer behind the on-screen math keypad (no soft keyboard).
## Keeps a list of tokens so backspace removes "sin(" or "x²" as one unit.
## Plain class so the editing rules are unit-tested.

const MAX_TOKENS := 32

## key id -> ASCII token inserted into the formula
const INSERT := {
	"0": "0", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
	".": ".", "x": "x", "+": "+", "-": "-", "*": "*", "/": "/", "^": "^", "(": "(", ")": ")",
	"sq": "^2", "sin": "sin(", "cos": "cos(", "pi": "pi",
}

var tokens: PackedStringArray = []


## Applies a key; returns true when the buffer changed.
func press(key: String) -> bool:
	if key == "back":
		return backspace()
	if key == "clear":
		var had := not tokens.is_empty()
		tokens.clear()
		return had
	if not INSERT.has(key) or tokens.size() >= MAX_TOKENS:
		return false
	tokens.append(INSERT[key])
	return true


func backspace() -> bool:
	if tokens.is_empty():
		return false
	tokens.resize(tokens.size() - 1)
	return true


func is_empty() -> bool:
	return tokens.is_empty()


## ASCII source for MathExpr.parse.
func text() -> String:
	return "".join(tokens)


## Rebuilds the token list from saved ASCII text (drafts).
func set_text(src: String) -> void:
	tokens.clear()
	var i := 0
	while i < src.length() and tokens.size() < MAX_TOKENS:
		var rest := src.substr(i)
		var tok := src[i]
		for multi in ["sin(", "cos(", "pi"]:
			if rest.begins_with(multi):
				tok = multi
				break
		if tok != " ":
			tokens.append(tok)
		i += tok.length()


## Parses with missing ')' auto-closed (the keypad lets players omit them).
func parse() -> MathExpr:
	return MathExpr.parse(text(), true)


## Display form: real minus, ×, ÷, π, superscript squares/cubes.
static func display(src: String) -> String:
	return MathExpr.pretty(src).replace("·", "×").replace("/", "÷")


## How many ')' the auto-close will add (shown as ghost glyphs).
func missing_parens() -> int:
	return maxi(0, MathExpr.open_parens(text()))
