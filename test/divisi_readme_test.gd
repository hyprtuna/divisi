extends GdUnitTestSuite

## The README's quickstart, compiled.
##
## It shipped in 0.1.0 with a call to an undefined get_threat_level(), which is a parse error,
## so the whole snippet failed before its first line ran. A snippet nobody can paste is worse
## than no snippet, and nothing in the repository would have noticed.
##
## The stem paths are the one thing rewritten before compiling: the snippet preloads
## res://audio/, which is where a reader's own stems would be, and preload resolves at compile
## time. Everything else, including the parts that were broken, is compiled exactly as written.


func _quickstart_source() -> String:
	var file := FileAccess.open("res://README.md", FileAccess.READ)
	assert_object(file).is_not_null()
	var text := file.get_as_text()
	file.close()
	var from := text.find("## Quickstart")
	assert_int(from).is_greater(-1)
	var open_fence := text.find("```gdscript", from)
	assert_int(open_fence).is_greater(-1)
	var body := open_fence + "```gdscript\n".length()
	var close_fence := text.find("```", body)
	assert_int(close_fence).is_greater(-1)
	return text.substr(body, close_fence - body).replace("res://audio/", "res://demo/audio/")


func test_the_readme_quickstart_compiles() -> void:
	var source := _quickstart_source()
	assert_str(source).contains('player.play(&"combat")')
	var script := GDScript.new()
	script.source_code = source
	assert_int(script.reload()).is_equal(OK)
