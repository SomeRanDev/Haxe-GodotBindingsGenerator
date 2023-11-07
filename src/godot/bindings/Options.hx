package godot.bindings;

/**
	A version of `Options` with all nullable the fields;
**/
@:structInit
class Options {
	public var basePackage(default, null): String = "godot";
	public var generateHierarchyMeta(default, null): Array<String> = ["Node", "Resource"];
}
