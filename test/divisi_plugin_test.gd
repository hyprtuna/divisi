extends GdUnitTestSuite

## The plugin's one job: registering the [code]DivisiState[/code] autoload.
##
## [method EditorPlugin.add_autoload_singleton] and its removal counterpart only exist inside
## a running editor, so a headless run cannot call them. What it can check is the contract they
## carry, which is a name and a path shared between two files that never reference each other:
## the plugin writes them into the project, and [DivisiPlayer] resolves
## [code]/root/DivisiState[/code] by name at runtime and loads nothing itself. Renaming either
## end silently turns persistence off, and nothing else in the suite would notice.

const PLUGIN := preload("res://addons/divisi/plugin.gd")


func test_the_plugin_names_an_autoload_that_exists_and_holds_state() -> void:
	assert_str(String(PLUGIN.AUTOLOAD_NAME)).is_equal("DivisiState")
	assert_bool(ResourceLoader.exists(PLUGIN.AUTOLOAD_PATH)).is_true()
	var script: GDScript = load(PLUGIN.AUTOLOAD_PATH)
	var state: Node = auto_free(script.new())
	assert_bool(state.has_method("put")).is_true()
	assert_bool(state.has_method("take")).is_true()
	assert_bool(state.has_method("peek")).is_true()
	assert_bool(state.has_method("clear")).is_true()


func test_the_registered_autoload_is_the_script_the_plugin_points_at() -> void:
	# The plugin is enabled in this project, so the autoload it added is running right now and
	# the two ends of the contract can be compared against each other rather than asserted.
	var state := get_node_or_null(^"/root/DivisiState")
	assert_object(state).is_not_null()
	assert_str(String(state.name)).is_equal(String(PLUGIN.AUTOLOAD_NAME))
	assert_str((state.get_script() as GDScript).resource_path).is_equal(PLUGIN.AUTOLOAD_PATH)
