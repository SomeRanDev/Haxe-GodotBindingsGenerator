package godot;

import haxe.macro.Expr;

/**
	A collection of pure utility functions.
**/
class BindingsUtil {
	/**
		Returns the type with underscores instead of dots.

		Will also prepend "Godot" if "String" or "Array" is passed.
	**/
	public static function processTypeName(name: String): String {
		return switch(name) {
			case "String" | "Array": "Godot" + name;
			case _: StringTools.replace(name, ".", "_");
		}
	}

	/**
		Checks if the identifier is a reserved keyword in Haxe.
		If it is, it will prepend an underscore.

		Otherwise, the identifier is returned unmodified.
	**/
	public static function processIdentifier(name: String): String {
		return switch(name) {
			case "default" | "operator" | "class" | "enum" | "in" | "override" | "interface" | "var" | "new" | "function": "_" + name;
			case _: name;
		}
	}

	/**
		Processes the "description" fields before being assigned to "doc" fields in Haxe.
		Ensures there are no closing comments (* /) that would break Haxe's doc comments.
	**/
	public static function processDescription(description: Null<String>): Null<String> {
		if(description == null) {
			return null;
		}
		if(StringTools.contains(description, "*/")) {
			return StringTools.replace(description, "*/", "* /");
		}
		return description;
	}

	/**
		Generates a blank `Position`.
		Useful to fill in "pos" field for `TypeDefinition`, `Field`, and other AST objects.
	**/
	public static function makeEmptyPosition(): Position {
		return #if eval Context.currentPos() #else { file: "", min: 0, max: 0 } #end;
	}

	/**
		Extracts the `TypePath` from a `TPath` `ComplexType`.
		Throws an error if the `ComplexType` is not a `TPath`.
	**/
	public static function getTypePathFromComplex(cp: ComplexType): TypePath {
		return switch(cp) {
			case TPath(p): p;
			case _: throw 'Cannot convert ComplexType ${cp} to TypePath.';
		}
	}

	/**
		Easily generates a `Metadata` instance given one or more arguments of `Expr`.
		The `Expr` must be a call or identifier and can use `String`.

		```haxe
		// generates @:native("test") and @-something
		makeMetadata(macro native("test"), macro "-something");
		```
	**/
	public static function makeMetadata(...data: Expr): Metadata {
		final result = [];

		for(d in data) {
			switch(d.expr) {
				case ECall(expr, params): {
					final name = switch(expr.expr) {
						case EConst(CIdent(ident)): ":" + ident;
						case EConst(CString(s)): s;
						case _: throw "Invalid input for `makeMetadata`.";
					}
					result.push({
						name: name,
						pos: makeEmptyPosition(),
						params: params
					});
				}
				case EConst(CString(ident)) | EConst(CIdent(ident)): {
					if(!StringTools.startsWith(ident, ":")) {
						ident = ":" + ident;
					}
					result.push({
						name: ident,
						pos: makeEmptyPosition(),
						params: []
					});
				}
				case _: throw "Invalid input for `makeMetadata`.";
			}
		}

		return result;
	}

	/**
		Generates a single `MetadataEntry` from an `Expr`.
	**/
	public static function makeMetadataEntry(e: Expr): MetadataEntry {
		return makeMetadata(e)[0];
	}

	/**
		Given a Godot argument JSON object (with "default_value" and "type" Strings),
		returns the default value expression for Haxe or null.
	**/
	public static function getValue(data: { default_value: Null<String>, type: String }): Null<Expr> {
		if(data.default_value == null) {
			return null;
		}

		if(data.default_value == "null") {
			return macro null;
		}

		final v: Dynamic = switch(data.type) {
			case "bool": data.default_value == "true";
			case "int": Std.parseInt(data.default_value);
			case "float": Std.parseFloat(data.default_value);
			case "String": ~/$"(.*)"^/.replace(data.default_value, "$1");
			case _: return null;
		}

		return #if eval macro $v{v} #else null #end;
	}
}