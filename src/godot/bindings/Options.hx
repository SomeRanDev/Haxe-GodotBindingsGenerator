package godot.bindings;

/**
	A version of `Options` with all nullable the fields;
**/
@:structInit
class Options {
	/**
		The package all the binding modules will generated for.
	**/
	public var basePackage(default, null): String = "godot";

	/**
		For each Godot class name listed here, a metadata will be added to all
		Godot classes specifying whether they extend from this class or not.

		For example, adding "Node" will add a meta named `@:is_node` to every
		class. The argument will be `true` if "godot.Node" is in their class hierarchy,
		and `false` otherwise.
	**/
	public var generateHierarchyMeta(default, null): Array<String> = ["Node", "Resource"];

	/**
		Adds this content to the top of generated files as a comment.
		Disable by assigning `null`.
	**/
	public var fileComment(default, null): Null<String> = "Generated using Godot Bindings Generator for Haxe.
https://github.com/SomeRanDev/Haxe-GodotBindingsGenerator";
}
