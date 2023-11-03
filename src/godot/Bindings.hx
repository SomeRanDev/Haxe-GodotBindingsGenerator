package godot;

import godot.bindings.Options;

import godot.ExtensionApi.BuiltinClass;
import godot.ExtensionApi.Class as GodotClass;
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
		trace(outputPath);
		trace(FileSystem.exists(outputPath));
		if(!FileSystem.exists(outputPath)) {
			FileSystem.createDirectory(outputPath);
		}
  
		final printer = new Printer();
		for(definition in typeDefinitions) {
			final p = Path.join([outputPath, definition.name + ".hx"]);
			trace("saveing content: ", p);
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

	function processTypeName(name: String): String {
		return switch(name) {
			case "String" | "Array": "Godot" + name;
			case _: StringTools.replace(name, ".", "_");
		}
	}

	function processIdentifier(name: String): String {
		return switch(name) {
			case "default": "_" + name;
			case _: name;
		}
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

		for(builtin in data.builtin_classes) {
			if(builtin.name == "bool" || builtin.name == "int" || builtin.name == "float") {
				continue;
			}
			result.push(generateBuiltinClass(builtin));
		}

		return result;
	}

	function generateUtilityFunction(utilityFunction: UtilityFunction): Field {
		return {
			name: processIdentifier(utilityFunction.name),
			pos: makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FFun({
				ret: getReturnType(utilityFunction.return_type),
				args: utilityFunction.arguments.maybeMap(t -> ({
					name: processIdentifier(t.name),
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
			name: processIdentifier(globalConstant.name),
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
			name: processTypeName(globalEnum.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: globalEnum.values.map(function(godotEnumValue): Field {
				return {
					name: processIdentifier(godotEnumValue.name),
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

	function generateBuiltinClass(cls: BuiltinClass): TypeDefinition {
		final fields = [];
		final fieldAccess = [APublic];

		for(constructor in cls.constructors.denullify()) {
			final args = constructor.arguments.maybeMap(function(arg): FunctionArg {
				return {
					name: processIdentifier(arg.name),
					type: getType(arg.type)
				}
			});

			if(constructor.arguments?.length == 0 || cls.constructors?.length == 1) {
				fields.push({
					name: "new",
					pos: makeEmptyPosition(),
					access: fieldAccess,
					kind: FFun({ args: args }),
					meta: [],
					doc: constructor.description
				});
			} else {
				fields.push({
					name: "make",
					pos: makeEmptyPosition(),
					access: fieldAccess.concat([AStatic, AOverload]),
					kind: FFun({ args: args, ret: getType(processTypeName(cls.name)) }),
					meta: [],
					doc: constructor.description
				});
			}
		}

		for(member in cls.members.denullify()) {
			fields.push({
				name: processIdentifier(member.name),
				pos: makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(getType(member.type), null),
				meta: [],
				doc: member.description
			});
		}

		for(constant in cls.constants.denullify()) {
			fields.push({
				name: processIdentifier(constant.name),
				pos: makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(getType(constant.type), null),
				meta: makeMetadata(
					macro value($v{constant.value})
				),
				doc: constant.description
			});
		}

		for(method in cls.methods.denullify()) {
			fields.push({
				name: processIdentifier(method.name),
				pos: makeEmptyPosition(),
				access: fieldAccess,
				kind: FFun({
					args: method.arguments.maybeMap(function(arg): FunctionArg {
						return {
							name: processIdentifier(arg.name),
							type: getType(arg.type),
							opt: arg.default_value != null,
							meta: makeMetadata(
								macro default_value($v{arg.default_value})
							),
							// value: Null<Expr>
						}
					}),
					ret: getReturnType(method.return_type)
				}),
				meta: makeMetadata(
					macro is_vararg($v{method.is_vararg}),
					macro is_const($v{method.is_const}),
					macro is_static($v{method.is_static}),
					macro hash($v{method.hash})
				),
				doc: method.description
			});
		}

		/**
			TODO: two members of `BuiltinClass`:

			enums: MaybeArray<{
				name: String,
				values: MaybeArray<{
					name: String,
					value: String,
					description: Null<String>
				}>,
				description: Null<String>
			}>,
			operators: MaybeArray<{
				name: String,
				right_type: Null<String>,
				return_type: String,
				description: Null<String>
			}>,
		**/

		return {
			name: processTypeName(cls.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false),
			isExtern: true,
			meta: makeMetadata(
				macro indexing_return_type($v{cls.indexing_return_type}),
				macro is_keyed($v{cls.is_keyed}),
				macro has_destructor($v{cls.has_destructor})
			),
			doc: cls.description
		}
	}
}

#end
