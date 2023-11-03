package godot;

import godot.bindings.Options;

import godot.ExtensionApi.GlobalConstant;
import godot.ExtensionApi.GlobalEnum;
import godot.ExtensionApi.UtilityFunction;

import haxe.Json;
import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;
#if (haxe >= version("4.3.2"))
import haxe.macro.Expr.AbstractFlag;
#end
import haxe.macro.Printer;

import sys.FileSystem;
import sys.io.File;

using godot.bindings.NullableArrayTools;

#if eval

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
			kind: TDClass(null, null, false, false, false),
			isExtern: true
		}
	}

	function makeEmptyPosition(): Position {
		return #if eval Context.currentPos() #else { file: "", min: 0, max: 0 } #end;
	}

	function getType(typeString: String): ComplexType {
		return switch(typeString) {
			case "bool": macro : Bool;
			case "int": macro : Int;
			case "float": macro : Float;
			case "String": macro : String;
			case "Variant": macro : Dynamic;
			case _: TPath({
				pack: getPack(),
				name: typeString
			});
		}
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
		Generates the `TypeDefinition`s.
	**/
	function make(): Array<TypeDefinition> {
		final data = loadData(extensionJsonPath);
		final result: Array<TypeDefinition> = [];

		result.push(makeClassTypeDefinition("Godot", []
			.concat(data.utility_functions.map(generateUtilityFunction))
			.concat(data.global_constants.map(generateGlobalConstant))
		));

		for(e in data.global_enums) {
			result.push(generateGlobalEnum(e));
		}

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

	function generateGlobalConstant(globalConstant: GlobalConstant): Field {
		return {
			name: globalConstant.name,
			pos: makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FVar(macro : Int, null), // not sure if always typing as `Int` is correct?
			meta: makeMetadata(
				macro is_bitfield($v{globalConstant.is_bitfield})
			),
			doc: globalConstant.description
		}
	}

	function generateGlobalEnum(globalEnum: GlobalEnum): TypeDefinition {
		return {
			name: globalEnum.name,
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: globalEnum.values.map(function(godotEnumValue): Field {
				return {
					name: godotEnumValue.name,
					pos: makeEmptyPosition(),
					access: [APublic, AStatic],
					kind: FVar(macro : Int, macro $v{godotEnumValue.value}),
					doc: godotEnumValue.description
				}
			}),
			meta: makeMetadata(
				#if (haxe < version("4.3.2"))
				macro ":enum"(),
				#end
				macro is_bitfield($v{globalEnum.is_bitfield})
			),
			kind: TDAbstract(macro : Int, 
				#if (haxe >= version("4.3.2"))
				[AbstractFlag.AbEnum]
				#else
				#end
			)
		}
	}
}

#end
