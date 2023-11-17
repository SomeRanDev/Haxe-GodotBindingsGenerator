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
using godot.bindings.NullTools;

class Bindings {
	/**
		Need to store this option statically since cannot access `bindings.Options` from
		the `output` function.
	**/
	static var fileComment: Null<String> = null;

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
			final content = printer.printTypeDefinition(definition);
			final prefixContent = if(fileComment != null) {
				'/**\n${fileComment.split("\n").map(s -> "\t" + s).join("\n")}\n**/\n';
			} else {
				"";
			}
			File.saveContent(p, prefixContent + content);
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
		throw 'Could not find ${extensionJsonPath}.\nCurrent working directory: ${Sys.getCwd()}';
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

		Bindings.fileComment = options?.fileComment; // Use this later in `output` static function.
	}

	/**
		Converts a camel-case identifier to snake-case.
		Used to generate the proper header `@:include`s for godot-cpp.

		Based on the same technique:
		https://github.com/godotengine/godot-cpp/blob/master/binding_generator.py
		https://github.com/godotengine/godot-cpp/blob/master/LICENSE.md
	**/
	static function camelToSnake(name: String): String {
		name = ~/(.)([A-Z][a-z]+)/.replace(name, "$1_$2");
		name = ~/([a-z0-9])([A-Z])/.replace(name, "$1_$2");
		return StringTools.replace(StringTools.replace(name, "2_D", "2D"), "3_D", "3D").toLowerCase();
	}

	/**
		Returns the type with underscores instead of dots.

		Will also prepend "Godot" if "String" or "Array" is passed.
	**/
	function processTypeName(name: String): String {
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
	function processIdentifier(name: String): String {
		return switch(name) {
			case "default" | "operator" | "class" | "enum" | "in" | "override" | "interface" | "var" | "new" | "function": "_" + name;
			case _: name;
		}
	}

	/**
		Processes the "description" fields before being assigned to "doc" fields in Haxe.
		Ensures there are no closing comments (* /) that would break Haxe's doc comments.
	**/
	function processDescription(description: Null<String>): Null<String> {
		if(description == null) {
			return null;
		}
		if(StringTools.contains(description, "*/")) {
			return StringTools.replace(description, "*/", "* /");
		}
		return description;
	}

	/**
		Get the "pack" that should be used by the Godot Haxe binding types.
	**/
	function getPack(): Array<String> {
		return [options.basePackage];
	}

	/**
		Generates a very basic class `TypeDefinition` given a name and list of `Field`s.
	**/
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

	/**
		Generates a blank `Position`.
		Useful to fill in "pos" field for `TypeDefinition`, `Field`, and other AST objects.
	**/
	function makeEmptyPosition(): Position {
		return #if eval Context.currentPos() #else { file: "", min: 0, max: 0 } #end;
	}

	/**
		Converts a `String` of a Godot type to the Haxe `ComplexType` equivalent.
	**/
	function getType(typeString: String): ComplexType {
		final typearrPrefix = "typedarray::";
		if(StringTools.startsWith(typeString, typearrPrefix)) {
			return TPath({
				pack: [],
				name: "Array",//"GodotArray",
				params: [
					TPType(getType(typeString.substring(typearrPrefix.length)))
				]
			});
		}

		if(StringTools.startsWith(typeString, "enum::") || StringTools.startsWith(typeString, "bitfield::")) {
			return macro : Dynamic;
		}

		return switch(typeString) {
			case "bool": macro : Bool;
			case "int": macro : Int;
			case "float": macro : Float;
			case "String": macro : String;
			case "Array": macro : godot.GodotArray;
			case "Variant": macro : Dynamic;
			case _: TPath({
				pack: getPack(),
				name: typeString
			});
		}
	}

	/**
		The same as `getType`, but can accept `null`.
		If `null` is passed, `Void` `ComplexType` is returned.
	**/
	function getReturnType(typeString: Null<String>): ComplexType {
		return typeString == null ? (macro : Void) : getType(typeString);
	}

	/**
		Extracts the `TypePath` from a `TPath` `ComplexType`.
		Throws an error if the `ComplexType` is not a `TPath`.
	**/
	function getTypePathFromComplex(cp: ComplexType): TypePath {
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
	function makeMetadata(...data: Expr): Metadata {
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
	function makeMetadataEntry(e: Expr): MetadataEntry {
		return makeMetadata(e)[0];
	}

	/**
		Generates the `TypeDefinition`s.
	**/
	function make(): Array<TypeDefinition> {
		final data = loadData(extensionJsonPath);
		final result: Array<TypeDefinition> = [];

		result.push(makeClassTypeDefinition("Godot", (
				data.utility_functions.map(generateUtilityFunction).concat(
					data.global_constants.map(generateGlobalConstant)
				)
			)
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

		final hierarchyData = options.generateHierarchyMeta.length > 0 ? generateHierarchyData(data.classes) : null;
		for(cls in data.classes) {
			final typeDefinition = generateClass(cls);

			// Generate additional metadata from `generateHierarchyMeta`
			if(hierarchyData != null && hierarchyData.exists(cls.name)) {
				for(className => inherits in hierarchyData.get(cls.name).trustMe()) {
					final m = typeDefinition.meta ?? [];
					m.push({
						name: ":is_" + className.toLowerCase(),
						params: [#if eval macro $v{inherits} #end],
						pos: makeEmptyPosition()
					});
					typeDefinition.meta = m;
				}
			}

			result.push(typeDefinition);
		}

		return result;
	}

	/**
		Preemptively iterate through the "classes" and figure out which ones
		extend from the `generateHierarchyMeta` list.
	**/
	function generateHierarchyData(classes: Array<GodotClass>): Map<String, Map<String, Bool>> {
		final hierarchyData: Map<String, Map<String, Bool>> = [];
		final unprocessedChildren: Map<String, Array<GodotClass>> = [];

		function processHierarchy(cls: GodotClass) {
			if(hierarchyData.exists(cls.name)) {
				return;
			}

			final isBase = options.generateHierarchyMeta.contains(cls.name);
			final superClass = cls.inherits;
			if(superClass == null || superClass == "Object") {
				final map: Map<String, Bool> = [];
				for(m in options.generateHierarchyMeta) {
					map.set(m, cls.name == m);
				}
				hierarchyData.set(cls.name, map);
			} else if(hierarchyData.exists(superClass)) {
				final map = Reflect.copy(hierarchyData.get(superClass));
				if(map == null) {
					throw "Reflect.copy failed.";
				}
				if(isBase) {
					map.set(cls.name, true);
				}
				hierarchyData.set(cls.name, map);
			} else {
				if(!unprocessedChildren.exists(superClass)) {
					unprocessedChildren.set(superClass, []);
				}
				unprocessedChildren.get(superClass).trustMe().push(cls);
				return;
			}

			if(unprocessedChildren.exists(cls.name)) {
				for(child in unprocessedChildren.get(cls.name).trustMe()) {
					processHierarchy(child);
				}
				unprocessedChildren.remove(cls.name);
			}
		}

		for(cls in classes) {
			processHierarchy(cls);
		}

		return hierarchyData;
	}

	/**
		Generates the `TypeDefinition` from a "utility_functions" object from `extension_api.json`.
	**/
	function generateUtilityFunction(utilityFunction: UtilityFunction): Field {
		final meta = makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("utility_function"),
			macro godot_name($v{utilityFunction.name}),
			macro category($v{utilityFunction.category}),
			macro is_vararg($v{utilityFunction.is_vararg}),
			macro hash($v{utilityFunction.hash})
			#end
		);

		if(options.cpp) {
			#if eval
			meta.push(makeMetadataEntry(macro include("godot_cpp/variant/utility_functions.hpp")));
			meta.push(makeMetadataEntry(macro native($v{"godot::UtilityFunctions::" + utilityFunction.name})));
			#end
		}

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
			meta: meta,
			doc: processDescription(utilityFunction.description)
		}
	}

	/**
		Generates the `TypeDefinition` from a "global_constants" object from `extension_api.json`.
	**/
	function generateGlobalConstant(globalConstant: GlobalConstant): Field {
		return {
			name: processIdentifier(globalConstant.name),
			pos: makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FVar(macro : Int, null), // not sure if always typing as `Int` is correct?
			meta: makeMetadata(
				#if eval
				macro generated_godot_api,
				macro bindings_api_type("global_constant"),
				macro is_bitfield($v{globalConstant.is_bitfield})
				#end
			),
			doc: processDescription(globalConstant.description)
		}
	}

	/**
		Generates the `TypeDefinition` from a "global_enums" object from `extension_api.json`.
	**/
	function generateGlobalEnum(globalEnum: GlobalEnum): TypeDefinition {
		final meta = makeMetadata(
			#if eval
				#if (haxe < version("4.3.2"))
				macro ":enum"(),
				#end
				macro generated_godot_api,
				macro bindings_api_type("global_enum"),
				macro is_bitfield($v{globalEnum.is_bitfield})
			#end
		);

		if(options.cpp) {
			#if eval
			meta.push(makeMetadataEntry(macro include("godot_cpp/classes/global_constants_binds.hpp")));
			#end
		}

		return {
			name: processTypeName(globalEnum.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: globalEnum.values.map(function(godotEnumValue): Field {
				return {
					name: processIdentifier(godotEnumValue.name),
					pos: makeEmptyPosition(),
					access: [APublic, AStatic],
					kind: FVar(macro : Int, #if eval macro $v{godotEnumValue.value} #end),
					doc: processDescription(godotEnumValue.description)
				}
			}),
			meta: meta,
			kind: TDAbstract(macro : Int, 
				#if (haxe >= version("4.3.2"))
				[AbstractFlag.AbEnum]
				#else
				#end
			)
		}
	}

	/**
		Generates the `TypeDefinition` from a "builtin_classes" object from `extension_api.json`.
	**/
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
					kind: FFun({ args: args, ret: null }),
					meta: [],
					doc: processDescription(constructor.description)
				});
			} else {
				fields.push({
					name: "make",
					pos: makeEmptyPosition(),
					access: fieldAccess.concat([AStatic, AOverload]),
					kind: FFun({ args: args, ret: getType(processTypeName(cls.name)) }),
					meta: makeMetadata(
						macro constructor
					),
					doc: processDescription(constructor.description)
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
				doc: processDescription(member.description)
			});
		}

		for(constant in cls.constants.denullify()) {
			fields.push({
				name: processIdentifier(constant.name),
				pos: makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(getType(constant.type), null),
				meta: makeMetadata(
					#if eval
					macro value($v{constant.value})
					#end
				),
				doc: processDescription(constant.description)
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
								#if eval
								macro default_value($v{arg.default_value})
								#end
							),
							// value: Null<Expr>
						}
					}),
					ret: getReturnType(method.return_type)
				}),
				meta: makeMetadata(
					#if eval
					macro is_vararg($v{method.is_vararg}),
					macro is_const($v{method.is_const}),
					macro is_static($v{method.is_static}),
					macro hash($v{method.hash})
					#end
				),
				doc: processDescription(method.description)
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

		final meta = makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("builtin_classes"),
			macro indexing_return_type($v{cls.indexing_return_type}),
			macro is_keyed($v{cls.is_keyed}),
			macro has_destructor($v{cls.has_destructor})
			#end
		);

		if(options.cpp) {
			#if eval
			final p = "godot_cpp/classes/" + camelToSnake(cls.name) + ".hpp";
			meta.push(makeMetadataEntry(macro include($v{p})));
			#end
		}

		return {
			name: processTypeName(cls.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: processDescription(cls.description)
		}
	}

	/**
		Generates the `TypeDefinition` from a "classes" object from `extension_api.json`.
	**/
	function generateClass(cls: GodotClass): TypeDefinition {
		final fields = [];
		final fieldAccess = [APublic];

		for(constant in cls.constants.denullify()) {
			fields.push({
				name: processIdentifier(constant.name),
				pos: makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(macro : Int,
					// Cannot have value on extern, but if we could we'd use: macro $v{constant.value}),
					null
				),
				meta: [],
				doc: processDescription(constant.description)
			});
		}

		final renamedMethods: Map<String, String> = [];

		for(property in cls.properties.denullify()) {
			if(StringTools.contains(property.type, ",") || StringTools.contains(property.type, "/")) {
				continue;
			}

			fields.push({
				name: processIdentifier(property.name),
				pos: makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(getType(property.type)),
				meta: makeMetadata(
					#if eval
					macro index($v{property.index}),
					macro getter($v{property.getter}),
					macro setter($v{property.setter})
					#end
				),
				doc: processDescription(property.description)
			});
		}

		for(method in cls.methods.denullify()) {
			final metadata = makeMetadata(
				#if eval
				macro is_const($v{method.is_const}),
				macro is_static($v{method.is_static}),
				macro is_vararg($v{method.is_vararg}),
				macro is_virtual($v{method.is_virtual}),
				macro hash($v{method.hash}),
				macro hash_compatibility($v{method.hash_compatibility}),
				#end
			);

			if(method.return_value != null) {
				#if eval
				metadata.unshift(
					makeMetadata(
						macro return_value_meta($v{method.return_value.meta})
					)[0]
				);
				#end
			}

			var hasCppType = StringTools.endsWith(method.return_value?.type ?? "", "*");
			for(a in method.arguments.denullify()) {
				if(StringTools.endsWith(a.type, "*")) {
					hasCppType = true;
					break;
				}
			}
			if(hasCppType) continue;

			var name = processIdentifier(method.name);
			if(renamedMethods.exists(name)) {
				name = renamedMethods.get(name).trustMe();
			}

			fields.push({
				name: name,
				pos: makeEmptyPosition(),
				access: fieldAccess,
				kind: FFun({
					args: method.arguments.maybeMap(function(godotArg): FunctionArg {
						return {
							name: processIdentifier(godotArg.name),
							type: getType(godotArg.type),
							meta: makeMetadata(
								#if eval
								macro meta($v{godotArg.meta}),
								macro default_value($v{godotArg.default_value}),
								#end
							)
						}
					}),
					ret: getReturnType(method.return_value?.type)
				}),
				meta: metadata,
				doc: processDescription(method.description)
			});
		}

		/**TODO
			// https://github.com/godotengine/godot/blob/93cdacbb0a30f12b2f3f5e8e06b90149deeb554b/core/extension/extension_api_dump.cpp#L1142C13-L1142C13
			signals: MaybeArray<{
				name: String,
				arguments: MaybeArray<{
					name: String,
					type: String,
					meta: Null<String>
				}>,
				description: Null<String>
			}>,
		**/

		/**TODO
			// https://github.com/godotengine/godot/blob/93cdacbb0a30f12b2f3f5e8e06b90149deeb554b/core/extension/extension_api_dump.cpp#L956C16-L956C16
			enums: MaybeArray<{
				name: String,
				is_bitfield: Int,
				values: Array<{
					name: String,
					value: Int,
					description: Null<String>
				}>,
				description: Null<String>
			}>,
		**/

		final meta = makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("class"),
			macro is_refcounted($v{cls.is_refcounted}),
			macro is_instantiable($v{cls.is_instantiable}),
			macro api_type($v{cls.api_type})
			#end
		);

		if(options.cpp) {
			#if eval
			final p = "godot_cpp/classes/" + camelToSnake(cls.name) + ".hpp";
			meta.push(makeMetadataEntry(macro include($v{p})));
			#end
		}

		return {
			name: processTypeName(cls.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: fields,
			kind: TDClass((cls.inherits == null ? null : getTypePathFromComplex(getType(cls.inherits))), null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: processDescription(cls.description)
		}
	}
}
