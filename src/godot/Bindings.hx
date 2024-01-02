package godot;

import godot.extension_api.BuiltinClass;
import godot.BindingsUtil as Util;

import godot.bindings.Options;

import godot.extension_api.Class as GodotClass;
import godot.extension_api.GlobalConstant;
import godot.extension_api.Enums.GlobalOrClassEnum;
import godot.extension_api.UtilityFunction;

import godot.generation.GenerateBuiltinClass;
import godot.generation.GenerateClass;
import godot.generation.GenerateEnum;
import godot.generation.GenerateUtilityFunction;
import godot.generation.GenerateGlobalConstant;

import haxe.Json;
import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;
#if (haxe >= version("4.3.2")) import haxe.macro.Expr.AbstractFlag; #end
import godot.haxestd.Printer;

import sys.FileSystem;
import sys.io.File;

// ---

using StringTools;

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

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
		A cache of enums to be referenced later when generating special properties that need them.
	**/
	var globalEnums: Map<String, GlobalOrClassEnum> = [];

	/**
		A cache of builtin-classes to be referenced later when generating special properties that need them.
	**/
	var builtinClasses: Map<String, BuiltinClass> = [];

	/**
		Constructor. Sets up all the fields.
	**/
	function new(extensionJsonPath: String, options: Options) {
		this.extensionJsonPath = extensionJsonPath;
		this.options = options;
		this.typeType = [];

		Bindings.fileComment = options?.fileComment; // Use this later in `output` static function.
	}

	static function isPrimitive(typeName: String) {
		return [
			"Nil", "void", "bool", "real_t", "float", "double", "int",
			"int8_t", "uint8_t", "int16_t", "uint16_t",
			"int32_t", "int64_t", "uint32_t", "uint64_t",
		].contains(typeName);
	}

	/**
		Generates the `TypeDefinition`s.
	**/
	function make(): Array<TypeDefinition> {
		final data = loadData(extensionJsonPath);
		final result: Array<TypeDefinition> = [];

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

			for(builtin in data.builtin_classes) {
				typeType.set(builtin.name, isPrimitive(builtin.name) ? Primitive : Builtin);
			}
		}

		// Generate bindings for "utility_functions" and "global_constants"
		result.push(makeClassTypeDefinition("Godot", (
				data.utility_functions.map(uf -> GenerateUtilityFunction.generate(uf, this)).concat(
					data.global_constants.map(gc -> GenerateGlobalConstant.generate(gc, this))
				)
			)
		));

		// Generate bindings for "global_enums"
		GenerateEnum.generate(data, this, result);

		// Generate bindings for "builtin_classes"
		GenerateBuiltinClass.generate(data, this, result);

		// Generate bindings for "classes"
		GenerateClass.generate(data, this, result);

		return result;
	}

	/**
		Get the "pack" that should be used by the Godot Haxe binding types.
	**/
	public function getPack(): Array<String> {
		return [options.basePackage];
	}

	/**
		Generates a very basic class `TypeDefinition` given a name and list of `Field`s.
	**/
	function makeClassTypeDefinition(name: String, fields: Array<Field>): TypeDefinition {
		return {
			name: name,
			pack: getPack(),
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false),
			isExtern: true
		}
	}

	/**
		Converts a `String` of a Godot type to the Haxe `ComplexType` equivalent.
	**/
	public function getType(typeString: String, noCppWrap: Bool = false): ComplexType {
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
	public function getReturnType(typeString: Null<String>): ComplexType {
		return typeString == null ? (macro : Void) : getType(typeString);
	}

	/**
		Compile type for function argument.
	**/
	public function getArgumentType(typeString: String): ComplexType {
		final result = getType(typeString);

		if(options.cpp && typeType.exists(typeString)) {
			switch(typeType.get(typeString)) {
				case GodotRef | Builtin: {
					return TPath({
						pack: [],
						name: "ConstRef",
						params: [ TPType(result) ]
					});
	/**
		Given a Godot argument JSON object (with "default_value" and "type" Strings),
		returns the default value expression for Haxe or null.
	**/
	public function getValue(data: { default_value: Null<String>, type: String }): Null<Expr> {
		if(data.default_value == null) {
			return null;
		}

		if(data.default_value == "null") {
			return macro null;
		}

		if(data.type.startsWith("enum::")) {
			final key = data.type.substr("enum::".length).replace(".", "_");

			final defValue = Std.parseInt(data.default_value);
			final enumData = globalEnums[key];
			if(enumData != null) {
				for(v in enumData.values) {
					if(v.value == defValue) {
						final fields = haxe.macro.ComplexTypeTools.toString(getType(data.type)).split(".");
						fields.push(v.name);

						return #if eval macro ${haxe.macro.MacroStringTools.toFieldExpr(fields)} #else null #end;
					}
				}
			}
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
