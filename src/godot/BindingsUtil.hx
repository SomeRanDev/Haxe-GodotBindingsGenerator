package godot;

import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

/**
	A collection of pure utility functions.
**/
class BindingsUtil {
	/**
		Converts a camel-case identifier to snake-case.
		Used to generate the proper header `@:include`s for godot-cpp.

		Based on the same technique:
		https://github.com/godotengine/godot-cpp/blob/master/binding_generator.py
		https://github.com/godotengine/godot-cpp/blob/master/LICENSE.md
	**/
	public static function camelToSnake(name: String): String {
		name = ~/(.)([A-Z][a-z]+)/g.replace(name, "$1_$2");
		name = ~/([a-z0-9])([A-Z])/g.replace(name, "$1_$2");
		final result = StringTools.replace(StringTools.replace(name, "2_D", "2D"), "3_D", "3D").toLowerCase();
		return result;
	}

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

	public static function generateInjectionExpr(haxeCode: String): Expr {
		return {
			expr: EMeta({
				name: "-printer-inject",
				pos: makeEmptyPosition()
			}, {
				expr: EConst(CIdent(haxeCode)),
				pos: makeEmptyPosition()
			}),
			pos: makeEmptyPosition()
		};
	}

	/**
		Converts a "value" `String` to valid GDScript.
	**/
	public static function valueStringToGDScript(value: String, stringType: String) {
		// Normally this is generated as `Array[TYPE]([])` for some reason....
		if(stringType.startsWith("typedarray::")) return "[]";

		// Return the value normally otherwise.
		return value;
	}

	/**
		Converts a "value" `String` to valid C++.

		If cannot be converted to C++, `null` is returned.
	**/
	public static function valueStringToCpp(value: String, stringType: String): Null<String> {
		final numRegex = ~/^\d+$/;
		if(numRegex.match(value) && (stringType == "int" || stringType == "float")) {
			return value;
		}

		return null;
	}
}
