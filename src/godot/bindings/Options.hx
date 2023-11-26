package godot.bindings;

/**
	A version of `Options` with all nullable the fields;
**/
@:structInit
class Options {
	/**
		The type used for Godot's variant type.
	**/
	public var godotVariantType(default, null): haxe.macro.Expr.ComplexType = macro : Dynamic;

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

	/**
		The metadata used to signify the "native" name of a class field.
		It should replace the name, but not the entire call expression.
	**/
	public var nativeNameMeta(default, null): String = ":native";

	/**
		The metadata used for `@:native` meta that should replace the field access portion
		of the call expression (this is the behavior of Haxe/C++ `@:native`).
	**/
	public var nativeReplaceMeta(default, null): String = ":native";

	/**
		If `true`, the bindings will contain `@:include`s for godot-cpp and wrap
		parameters/returns with representation for pointers and Godot's `Ref`. 
	**/
	public var cpp(default, null): Bool = false;

	/**
		This is the condition that wraps cpp related metadata.
	**/
	public var cppDefine(default, null): String = "cxx";

	/**
		The type used to represent Godot's `Ref` in `--cpp` mode.
	**/
	public var refType(default, null): { name: String, pack: Array<String> } = {
		name: "GodotRef",
		pack: []
	}

	/**
		The type used to represent C++ pointers in `--cpp` mode.
	**/
	public var ptrType(default, null): { name: String, pack: Array<String> } = {
		name: "GodotPtr",
		pack: []
	}
}
