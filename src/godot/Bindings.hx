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
import godot.haxestd.Printer;

import sys.FileSystem;
import sys.io.File;

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

enum TypeType {
	None;
	GodotRef;
	CppPointer;
}

class Bindings {
	/**
		The conditional compilation condition string for the singleton "C++" calls.
	**/
	static final cxxInlineSingletonsCondition = "godot_cxx_inline_singletons";

	/**
		Makes the `get_node` call redirect `get_node_internal` if this define is enabled.
	**/
	static final cxxFixGetNode = "godot_cxx_fix_get_node";

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
		Stores the kind of "Type" a class should be when used as param or return.
	**/
	var typeType: Map<String, TypeType>;

	/**
		Names of the loaded Godot singletons.
	**/
	var singletons: Map<String, Bool>;

	/**
		Constructor. Sets up all the fields.
	**/
	function new(extensionJsonPath: String, options: Options) {
		this.extensionJsonPath = extensionJsonPath;
		this.options = options;
		this.typeType = [];
		this.singletons = [];

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
	function getType(typeString: String, noCppWrap: Bool = false): ComplexType {
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

		if(options.cpp && !noCppWrap && typeType.exists(typeString)) {
			switch(typeType.get(typeString)) {
				case GodotRef: {
					return TPath({
						pack: options.refType.pack,
						name: options.refType.name,
						params: [
							TPType(TPath({ pack: getPack(), name: typeString }))
						]
					});
				}
				case CppPointer: {
					return TPath({
						pack: options.ptrType.pack,
						name: options.ptrType.name,
						params: [
							TPType(TPath({ pack: getPack(), name: typeString }))
						]
					});
				}
				case _:
			}
		}

		if(StringTools.startsWith(typeString, "enum::")) {
			final enumTypePath = typeString.substr("enum::".length);
			final enumPack = enumTypePath.split(".");
			return TPath({
				pack: getPack(),
				name: enumPack.join("_")
			});
		} else if(StringTools.startsWith(typeString, "bitfield::")) {
			final bitfieldTypePath = typeString.substr("bitfield::".length);
			final bitfieldPack = bitfieldTypePath.split(".");
			return TPath({
				pack: getPack(),
				name: bitfieldPack.join("_")
			});
		}

		return switch(typeString) {
			case "bool": macro : Bool;
			case "int": macro : Int;
			case "float": macro : Float;
			case "String": macro : String;
			case "Array": macro : godot.GodotArray;
			case "Variant": options.godotVariantType;
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
		Given a Godot argument JSON object (with "default_value" and "type" Strings),
		returns the default value expression for Haxe or null.
	**/
	function getValue(data: { default_value: Null<String>, type: String }): Null<Expr> {
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

		// Generate bindings for "utility_functions" and "global_constants"
		result.push(makeClassTypeDefinition("Godot", (
				data.utility_functions.map(generateUtilityFunction).concat(
					data.global_constants.map(generateGlobalConstant)
				)
			)
		));

		// Generate bindings for "global_enums"
		for(e in data.global_enums) {
			result.push(generateGlobalEnum(e));
			globalEnums.set(e.name, e);
		}

		// Generate bindings for "builtin_classes"
		for(builtin in data.builtin_classes) {
			if(builtin.name == "bool" || builtin.name == "int" || builtin.name == "float") {
				continue;
			}
			result.push(generateBuiltinClass(builtin));
		}

		// Figure out which classes should be Ref<T> or T*
		if(options.cpp) {
			typeType.set("Object", CppPointer);
			for(cls in data.classes) {
				if(StringTools.endsWith(cls.name, "*")) {
					typeType.set(cls.name, None);
					continue;
				}
				typeType.set(cls.name, cls.is_refcounted ? GodotRef : CppPointer);
			}
		}

		// Figure out which classes are Singletons
		if(data.singletons != null) {
			for(singleton in data.singletons.denullify()) {
				singletons.set(singleton.name, true);
			}
		}

		for(cls in data.classes) {
			for(e in cls.enums.denullify()) {
				globalEnums.set(cls.name + "_" + e.name, e);
			}
		}

		// Generate bindings for "classes"
		final hierarchyData = options.generateHierarchyMeta.length > 0 ? generateHierarchyData(data.classes) : null;
		for(cls in data.classes) {
			final typeDefinition = generateClass(cls, result);

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
			macro hash($v{utilityFunction.hash}),
			macro $v{'#if gdscript ${options.nativeReplaceMeta}'}($v{processIdentifier(utilityFunction.name)})
			#end
		);

		if(options.cpp) {
			#if eval
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}("godot_cpp/variant/utility_functions.hpp")));
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} ${options.nativeReplaceMeta}'}($v{"godot::UtilityFunctions::" + utilityFunction.name})));
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

	var globalEnums: Map<String, GlobalEnum> = [];

	/**
		Generates the `TypeDefinition` from a "global_enums" object from `extension_api.json`.
	**/
	function generateGlobalEnum(globalEnum: GlobalEnum, wrapperClassName: Null<String> = null): TypeDefinition {
		final meta = makeMetadata(
			#if eval
				#if (haxe < version("4.3.2"))
				macro ":enum"(),
				#end
				macro cppEnum,
				macro generated_godot_api,
				macro bindings_api_type("global_enum"),
				macro is_bitfield($v{globalEnum.is_bitfield}),
				macro "#if gdscript :native"($v{
					(wrapperClassName != null ? (wrapperClassName + ".") : "") + globalEnum.name
				})
			#end
		);

		final uniqueName = (wrapperClassName != null ? (wrapperClassName + "_") : "") + globalEnum.name;
		final name = processTypeName(uniqueName);

		if(options.cpp) {
			#if eval
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}("godot_cpp/classes/global_constants_binds.hpp")));
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :native'}($v{
				"godot::" + (wrapperClassName != null ? (wrapperClassName + "::") : "") + globalEnum.name
			})));
			#end
		}

		return {
			name: name,
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: globalEnum.values.map(function(godotEnumValue): Field {
				return {
					name: processIdentifier(godotEnumValue.name),
					pos: makeEmptyPosition(),
					access: [APublic, AStatic],
					kind: FFun({
						args: [],
						ret: null,
						expr: null,
						params: null
					}),
					doc: processDescription(godotEnumValue.description)
				}
			}),
			meta: meta,
			isExtern: true,
			kind: TDEnum
		}

		// return {
		// 	name: name,
		// 	pack: getPack(),
		// 	pos: makeEmptyPosition(),
		// 	fields: globalEnum.values.map(function(godotEnumValue): Field {
		// 		return {
		// 			name: processIdentifier(godotEnumValue.name),
		// 			pos: makeEmptyPosition(),
		// 			access: [APublic, AStatic],
		// 			kind: FVar(macro : Int, #if eval macro $v{godotEnumValue.value} #end),
		// 			doc: processDescription(godotEnumValue.description)
		// 			// meta: makeMetadata(#if eval macro "#if cxx :native"($v{
		// 			// 	'godot::${(wrapperClassName != null ? wrapperClassName + "::" : "")}${globalEnum.name}::${godotEnumValue.name}'
		// 			// }) #end)
		// 		}
		// 	}),
		// 	meta: meta,
		// 	kind: TDAbstract(macro : Int, 
		// 		#if (haxe >= version("4.3.2"))
		// 		[AbstractFlag.AbEnum]
		// 		#else
		// 		#end
		// 	)
		// }
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
			macro has_destructor($v{cls.has_destructor}),
			macro avoid_temporaries // TODO: should this be optional?
			#end
		);

		if(options.cpp) {
			#if eval
			final p = "godot_cpp/variant/" + camelToSnake(cls.name) + ".hpp";
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}($v{p})));
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :valueType'}));
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
	function generateClass(cls: GodotClass, typeDefinitionArray: Array<TypeDefinition>): TypeDefinition {
		final fields = [];
		final fieldAccess = [APublic];

		final isSingleton = singletons.exists(cls.name);

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

		// Validate property types and their getter/setter types
		final getterExpectedType: Map<String, { name: String, type: String }> = [];
		final setterExpectedType: Map<String, { name: String, type: String }> = [];
		final getterSetterFound: Map<String, { sourceProperty: String, exists: Bool }> = [];
		for(property in cls.properties.denullify()) {
			if(property.getter != null) {
				getterExpectedType.set(property.getter, property);
				getterSetterFound.set(property.getter, { sourceProperty: property.name, exists: false });
			}
			if(property.setter != null) {
				setterExpectedType.set(property.setter, property);
				getterSetterFound.set(property.setter, { sourceProperty: property.name, exists: false });
			}
		}

		// Let's ignore properties who don't have matching types with their getters/setters for the time being.
		// They can still be used by calling the getter/setter function directly.
		final ignoreProperties: Map<String, Bool> = [];
		function prop(p: String) {
			// return if(StringTools.startsWith(p, "enum::")) "int";
			// else if(StringTools.startsWith(p, "bitfield::")) "int";
			// Uncomment once a solution to treat Strings and StringNames the same is found...
			// else if(p == "StringName") "String";
			return p;
		}
		for(method in cls.methods.denullify()) {
			final getterSetterData = getterSetterFound.get(method.name);
			if(getterSetterData != null) {
				getterSetterData.exists = true;
			}

			if(getterExpectedType.exists(method.name)) {
				final property = getterExpectedType.get(method.name).trustMe();
				if(method.return_value == null || prop(method.return_value.type) != prop(property.type)) {
					#if godot_api_bindings_debug
					Sys.println('Property and getter types do not match.\n${cls.name} { func ${method.name}(...) -> ${method.return_value.type}, prop: ${property.name}: ${property.type} }');
					#end
					ignoreProperties.set(property.name, true);
				}
			} else if(setterExpectedType.exists(method.name)) {
				final property = setterExpectedType.get(method.name).trustMe();
				final args = method.arguments.denullify();
				if(args.length == 0 || prop(args[args.length - 1].type) != prop(property.type)) {
					#if godot_api_bindings_debug
					Sys.println('Property and setter types do not match.\n${cls.name} { func ${method.name}(..., v: ${args[args.length - 1].type}), prop: ${property.name}: ${property.type} }');
					#end
					ignoreProperties.set(property.name, true);
				}
			}
		}

		// Check for non-existant methods.
		// Let's ignore these properties too.
		for(_ => data in getterSetterFound) {
			if(!data.exists) {
				ignoreProperties.set(data.sourceProperty, true);
				#if godot_api_bindings_debug
				Sys.println('${cls.name}.$name doesn\'t exist');
				#end
			}
		}

		final propertyRenames: Map<String, String> = [];
		final setters: Map<String, String> = [];

		for(property in cls.properties.denullify()) {
			if(StringTools.contains(property.type, ",") || StringTools.contains(property.type, "/")) {
				continue;
			}

			final ignoreProperty = ignoreProperties.exists(property.name);

			final name = processIdentifier(property.name);

			// This type of property shares its setter and getter with other properties.
			// It distinguishes itself with its "index" that is passed to the first argument of the setter/getter.
			final isSpecialIndexedProp = property.index != null;

			// If it starts with an underscore, it is private and we cannot use it directly afaik??
			// Example: `Control.anchor_XXX` properties and their setter: `Control._set_anchor`
			final hasSetter = property.setter != null && !StringTools.startsWith(property.setter, "_");

			if(!ignoreProperty && !isSpecialIndexedProp) {
				// TODO: check for private getter??
				if(property.getter != null && property.getter != "get_" + name) {
					propertyRenames.set(property.getter, "get_" + name);
				}

				if(hasSetter) {
					final setter = property.setter.trustMe();
					if(setter != "set_" + name) {
						propertyRenames.set(setter, "set_" + name);
					}
					setters.set(setter, property.type);
				}
			}

			final data = if(isSingleton) {
				{
					access: fieldAccess.concat([AStatic]),
					meta: !options.cpp ? [] : makeMetadata(
						#if eval
						macro godot_bindings_gen_prepend($v{'#if !${cxxInlineSingletonsCondition}'}),
						macro godot_bindings_gen_append("#end")
						#end
					)
				}
			} else {
				{
					access: fieldAccess,
					meta: []
				}
			}

			// Setup property if we're not ignoring it.
			if(!ignoreProperty) {
				// For the "special indexed" properties, let's generate their own set/get inline functions.
				var propertyMeta = [];
				if(isSpecialIndexedProp) {
					final typeString = haxe.macro.ComplexTypeTools.toString(getType(property.type));

					var enumName = null;
					final enumIndex = property.index;
					if(enumIndex == null) throw "Impossible";

					var resultingValue = Std.string(enumIndex);

					for(m in cls.methods.denullify()) {
						if(m.name == property.getter) {
							enumName = m.arguments.denullify()[0].trustMe().type;
							break;
						}
					}

					if(enumName != null && StringTools.startsWith(enumName, "enum::")) {
						final enumPack = enumName.substr("enum::".length).split(".");
						final enumClassName = enumPack[0];
						final enumLocalName = enumPack[enumPack.length - 1];
						final enumHaxeName = enumPack.join("_");

						var enumObj = globalEnums.get(enumHaxeName);

						if(enumObj != null) {
							var name = null;
							for(v in enumObj.values) {
								if(v.value == enumIndex) {
									name = v.name;
								}
							}
							if(name != null) resultingValue = name;
						}
					}

					final getter = '\tpublic extern inline function get_$name(): $typeString {
		return cast ${property.getter}(${resultingValue});
	}';

					final setter = !hasSetter ? "" : '\tpublic extern inline function set_$name(v: $typeString): $typeString {
		${property.setter}(${resultingValue}, cast v);
		return v;
	}\n';

					propertyMeta = makeMetadata(
						#if eval
						macro godot_bindings_gen_prepend($v{'$getter\n$setter'}),
						#end
					);
				}

				fields.push({
					name: name,
					pos: makeEmptyPosition(),
					access: data.access,
					kind: FProp("get", property.setter == null ? "never" : "set", getType(property.type)),
					meta: makeMetadata(
						#if eval
						macro index($v{property.index}),
						macro getter($v{property.getter}),
						macro setter($v{property.setter}),
						macro godot_bindings_gen_prepend($v{'#if use_properties'}),
						macro godot_bindings_gen_append("#else")
						#end
					).concat(data.meta).concat(propertyMeta),
					doc: processDescription(property.description)
				});

				// Let's add #end to normal field
				data.meta.push(makeMetadataEntry(macro godot_bindings_gen_append("#end")));
			} else {
				// If ignoring property, let's still wrap the normal variable
				#if eval
				data.meta.push(makeMetadataEntry(macro godot_bindings_gen_prepend($v{'#if !use_properties'})));
				data.meta.push(makeMetadataEntry(macro godot_bindings_gen_append("#end")));
				#end
			}

			fields.push({
				name: name,
				pos: makeEmptyPosition(),
				access: data.access,
				kind: FVar(getType(property.type)),
				meta: makeMetadata(
					#if eval
					macro index($v{property.index}),
					macro getter($v{property.getter}),
					macro setter($v{property.setter})
					#end
				).concat(data.meta),
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
			final originalName = name;

			final setterType = setters.get(name);

			final nativeMeta = if(propertyRenames.exists(name)) {
				final result = makeMetadata(#if eval macro $v{'#if use_properties ${options.nativeNameMeta}'}($v{name}) #end);
				name = propertyRenames.get(name).trustMe();
				result;
			} else {
				[];
			};

			var preimplName = name;
			if(setterType != null) {
				name += "_impl";
			}

			function addField(
				overrideName: Null<String> = null,
				extraMetadata: Null<Array<MetadataEntry>> = null,
				additionalAccess: Null<Array<Access>> = null,
				expr: Null<Expr> = null
			) {
				fields.push({
					name: overrideName ?? name,
					pos: makeEmptyPosition(),
					access: additionalAccess == null ? fieldAccess : (fieldAccess.concat(additionalAccess)),
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
								).concat(nativeMeta),
								value: getValue(godotArg)
							}
						}),
						ret: getReturnType(method.return_value?.type),
						expr: expr
					}),
					meta: extraMetadata == null ? metadata : metadata.concat(extraMetadata),
					doc: processDescription(method.description)
				});
			}

			if(isSingleton) {
				// -----------------------
				// C++ extern inline

				if(options.cpp) {
					var i = 0;
					final margs = method.arguments.denullify();
					final args = margs.map(a -> "{" + (i++) + "}").join(", ");
					final call = 'godot::${cls.name}::get_singleton()->${originalName}($args)';
					final totalArgs = {
						#if eval
						[macro $v{call}].concat(margs.map(a -> macro $i{processIdentifier(a.name)}))
						#else
						[]
						#end;
					}
					
					addField(
						null,
						makeMetadata(
							#if eval
							macro godot_bindings_gen_prepend($v{'#if $cxxInlineSingletonsCondition'}),
							macro godot_bindings_gen_append("\n#else")
							#end
						),
						[AStatic, AExtern, AInline],
						#if eval macro {
							untyped __include__($v{"godot_cpp/classes/" + camelToSnake(cls.name) + ".hpp"});
							return untyped __cpp__($a{totalArgs});
						} #else null #end
					);
				}

				// -----------------------
				// Normal static call
				addField(
					null,
					!options.cpp ? [] : makeMetadata(
						#if eval
						macro godot_bindings_gen_append("#end")
						#end
					),
					[AStatic]
				);
			} else {

				var baseFieldMetadata = [];

				if(setterType != null) {
					final t = haxe.macro.ComplexTypeTools.toString(getReturnType(setterType));
					addField(
						null,
						makeMetadata(
							#if eval
							macro godot_bindings_gen_prepend($v{'#if use_properties
	public extern inline function $preimplName(v: $t): $t {
		${preimplName}_impl(cast v);
		return v;
	}
'}),
							macro godot_bindings_gen_append("\n#else"),
							macro $v{options.nativeNameMeta}($v{preimplName})
							#end
						),
					);


					baseFieldMetadata = makeMetadata(
						#if eval
						macro godot_bindings_gen_append("\n#end")
						#end
					);
				}

				// Special case to deal with Godot-CPP's `get_node<T>`.
				// To get the behavior expected for GDScript's `get_node`, `get_node_internal` should be used.
				if(options.cpp && cls.name == "Node" && originalName == "get_node") {
					#if eval
					baseFieldMetadata.push(makeMetadataEntry(macro $v{'#if $cxxFixGetNode ${options.nativeNameMeta}'}("get_node_internal")));
					#end
				} else if(preimplName != originalName) {
					#if eval
					baseFieldMetadata.push(makeMetadataEntry(macro $v{options.nativeNameMeta}($v{originalName})));
					#end
				}

				addField(
					preimplName,
					baseFieldMetadata
				);
			}

			
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

		for(e in cls.enums.denullify()) {
			typeDefinitionArray.push(generateGlobalEnum(e, processTypeName(cls.name)));
		}

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
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}($v{p})));
			meta.push(makeMetadataEntry(macro $v{'#if ${options.cppDefine} :valueType'}));
			#end
		}

		return {
			name: processTypeName(cls.name),
			pack: getPack(),
			pos: makeEmptyPosition(),
			fields: fields,
			kind: TDClass((cls.inherits == null ? null : getTypePathFromComplex(getType(cls.inherits, true))), null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: processDescription(cls.description)
		}
	}
}
