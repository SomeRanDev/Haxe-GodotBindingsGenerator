package godot;

import godot.bindings.Options;

import godot.ExtensionApi.UtilityFunction;

import haxe.Json;
import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Printer;

import sys.FileSystem;
import sys.io.File;

using godot.bindings.NullableArrayTools;

class Bindings {
	/**
		Generates a list of `TypeDefinition`s generated from the `extension_api.json` file.
	**/
	public static function generate(extensionJsonPath: String, options: Null<Options> = null): Array<TypeDefinition> {
		final bindings = new Bindings(extensionJsonPath, options ?? {});
		return bindings.make();
	}

	/**
		Outputs `TypeDefinition`s as Haxe source files.
	**/
	public static function output(outputPath: String, typeDefinitions: Array<TypeDefinition>) {
		if(!FileSystem.exists(outputPath)) {
			FileSystem.createDirectory(outputPath);
		}
  
		final printer = new Printer();
		for(definition in typeDefinitions) {
			final p = Path.join([outputPath, definition.name + ".hx"]);
			File.saveContent(p, printer.printTypeDefinition(definition));
		}
	}

	/**
		Loads the `extension_api.json` data, or throws an error if fails.
	**/
	static function loadData(extensionJsonPath: String): ExtensionApi {
		if(FileSystem.exists(extensionJsonPath)) {
			final content = File.getContent(extensionJsonPath);
			return try {
				Json.parse(content);
			} catch(e) {
				throw 'Could not parse ${extensionJsonPath}. ${e}';
			}
		}
		throw 'Could not find ${extensionJsonPath}.';
	}

	/**
		The `extension_api.json` path.
	**/
	var extensionJsonPath: String;

	/**
		Stored reference to the provided option object.
	**/
	var options: Options;

	/**
		Constructor. Sets up all the fields.
	**/
	function new(extensionJsonPath: String, options: Options) {
		this.extensionJsonPath = extensionJsonPath;
		this.options = options;
	}

	function getPack(): Array<String> {
		return [options.basePackage];
	}

	function makeClassTypeDefinition(name: String, fields: Array<Field>): TypeDefinition {
		return {
			name: name,
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false)
		}
	}

	function makeEmptyPosition(): Position {
		return #if eval Context.currentPos() #else { file: "", min: 0, max: 0 } #end;
	}

	function getType(typeString: String): ComplexType {
		return macro : Void;
	}

	function getReturnType(typeString: Null<String>): ComplexType {
		return typeString == null ? (macro : Void) : getType(typeString);
	}

	function makeMetadata(...data: Expr) {
		final result = [];

		for(d in data) {
			switch(d.expr) {
				case ECall(expr, params): {
					final name = switch(expr.expr) {
						case EConst(CIdent(ident)): ident;
						case _: throw "Invalid input for `makeMetadata`.";
					}
					result.push({
						name: ":" + name,
						pos: makeEmptyPosition(),
						params: params
					});
				}
				case _: throw "Invalid input for `makeMetadata`.";
			}
		}

		return result;
	}

	/**
		Generates the `TypeDefinition`s.
	**/
	function make(): Array<TypeDefinition> {
		final data = loadData(extensionJsonPath);
		final result: Array<TypeDefinition> = [];

		result.push(makeClassTypeDefinition("Godot", data.utility_functions.map(generateUtilityFunction)));

		return result;
	}

	function generateUtilityFunction(utilityFunction: UtilityFunction): Field {
		return {
			name: utilityFunction.name,
			pos: makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FFun({
				ret: getReturnType(utilityFunction.return_type),
				args: utilityFunction.arguments.maybeMap(t -> ({
					name: t.name,
					type: getType(t.type)
				} : FunctionArg))
			}),
			meta: makeMetadata(
				macro category($v{utilityFunction.category}),
				macro is_vararg($v{utilityFunction.is_vararg}),
				macro hash($v{utilityFunction.hash})
			),
			doc: utilityFunction.description
		}
	}
}
