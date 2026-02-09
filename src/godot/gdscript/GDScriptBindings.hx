package godot.gdscript;

import haxe.macro.Expr;
import godot.BindingsUtil as Util;
import godot.gdscript.GDScriptParser;

using StringTools;

/**
 *  Generates Haxe TypeDefinitions from parsed GDScript classes. 
 * 
 *  @author Elizabeth "Niz" Johana - 2026 
 */
class GDScriptBindings {
	/**
		Native name metadata to use (can be `:native` or `:nativeName`).
	**/
	public static var nativeNameMeta:String = ":native";

	/**
		Generate Haxe type definitions from a directory of GDScript files.
	**/
	public static function generateFromDirectory(path:String, basePackage:String = "addon"):Array<TypeDefinition> {
		final classes = GDScriptParser.parseDirectory(path);
		return generateFromClasses(classes, basePackage);
	}

	/**
		Generate Haxe type definitions from parsed GDScript classes.
	**/
	public static function generateFromClasses(classes:Array<GDScriptClass>, basePackage:String):Array<TypeDefinition> {
		final result:Array<TypeDefinition> = [];

		for (cls in classes) {
			result.push(generateClass(cls, basePackage));
		}

		return result;
	}

	static function generateClass(cls:GDScriptClass, basePackage:String):TypeDefinition {
		final fields:Array<Field> = [];
		final fieldAccess = [APublic];

		// -- CONSTRUCTORS --
		fields.push({
			name: "new",
			pos: Util.makeEmptyPosition(),
			access: fieldAccess,
			kind: FFun({args: []}),
			meta: []
		});

		// -- Constants --
		for (constant in cls.constants) {
			final constMeta:Metadata = [];
			final haxeName = Util.processTypeName(constant.name);
			if (haxeName != constant.name) {
				constMeta.push(makeNativeNameMeta(constant.name));
			}

			fields.push({
				name: haxeName,
				pos: Util.makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(constant.type != null ? gdTypeToHaxe(constant.type) : macro :Dynamic, null),
				meta: constMeta,
				doc: constant.description
			});
		}

		// -- Properties --
		for (prop in cls.properties) {
			final propType = prop.type != null ? gdTypeToHaxe(prop.type) : macro :Dynamic;

			final propMeta:Metadata = [];

			final haxeName = Util.processTypeName(prop.name);
			if (haxeName != prop.name) {
				propMeta.push(makeNativeNameMeta(prop.name));
			}

			if (prop.isExport) {
				propMeta.push({
					name: ":export",
					pos: Util.makeEmptyPosition(),
					params: []
				});
			}

			fields.push({
				name: haxeName,
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(propType),
				meta: propMeta,
				doc: prop.description
			});
		}

		// -- Signals --
		for (signal in cls.signals) {
			var docString = signal.description ?? "";
			if (signal.arguments.length > 0) {
				final argsDoc = signal.arguments.map(arg -> {
					final typeStr = arg.type != null ? ': ${arg.type}' : "";
					return '${arg.name}$typeStr';
				}).join(", ");
				docString = 'Signal arguments: ($argsDoc)\n\n$docString';
			}

			// Process signal name for Haxe compatibility (maybe rename)
			final haxeName = Util.processTypeName(signal.name);

			final signalMeta:Metadata = [
				{
					name: ":signal",
					pos: Util.makeEmptyPosition(),
					params: []
				},
				makeNativeNameMeta(signal.name)
			];

			// Add argument metadata !!
			for (i => arg in signal.arguments) {
				signalMeta.push({
					name: ":signal_arg",
					pos: Util.makeEmptyPosition(),
					params: [
						{expr: EConst(CInt(Std.string(i))), pos: Util.makeEmptyPosition()},
						{expr: EConst(CString(arg.name)), pos: Util.makeEmptyPosition()},
						{expr: EConst(CString(arg.type ?? "Variant")), pos: Util.makeEmptyPosition()}
					]
				});
			}

			fields.push({
				name: haxeName,
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(TPath({
					pack: ["godot"],
					name: "Signal",
					params: null,
					sub: null
				})),
				meta: signalMeta,
				doc: Util.processDescription(docString)
			});
		}

		// Methods
		for (method in cls.methods) {
			final args:Array<FunctionArg> = method.arguments.map(arg -> {
				return {
					name: Util.processIdentifier(arg.name),
					type: arg.type != null ? gdTypeToHaxe(arg.type) : macro :Dynamic,
					opt: arg.defaultValue != null,
					value: null,
					meta: null
				};
			});

			final haxeName = Util.processTypeName(method.name);

			final methodMeta:Metadata = [makeNativeNameMeta(method.name)];

			final access = method.isStatic ? fieldAccess.concat([AStatic]) : fieldAccess;

			fields.push({
				name: haxeName,
				pos: Util.makeEmptyPosition(),
				access: access,
				kind: FFun({
					args: args,
					ret: method.returnType != null ? gdTypeToHaxe(method.returnType) : macro :Void,
					expr: null
				}),
				meta: methodMeta,
				doc: method.description
			});
		}

		// Build class metadata
		final meta:Metadata = [
			{
				name: ":generated_godot_addon",
				pos: Util.makeEmptyPosition(),
				params: []
			},
			makeNativeNameMeta(cls.name),
			{
				name: ":gdscript_path",
				pos: Util.makeEmptyPosition(),
				params: [{expr: EConst(CString(cls.filePath)), pos: Util.makeEmptyPosition()}]
			}
		];

		// Determine parent class
		final parentType = if (cls.extends_ != null) {
			Util.getTypePathFromComplex(makeGodotType(cls.extends_));
		} else {
			null;
		};

		return {
			name: Util.processTypeName(cls.name),
			pack: [basePackage],
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDClass(parentType, null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: 'GDScript class from: ${cls.filePath}'
		};
	}

	/**
		Creates a native name metadata entry.
	**/
	static function makeNativeNameMeta(name:String):MetadataEntry {
		return {
			name: nativeNameMeta,
			pos: Util.makeEmptyPosition(),
			params: [{expr: EConst(CString(name)), pos: Util.makeEmptyPosition()}]
		};
	}

	/**
		Convert GDScript type to Haxe ComplexType.
	**/
	static function gdTypeToHaxe(gdType:String):ComplexType {
		final trimmed = gdType.trim();

		// Handle typed arrays: Array[String] -> Array<String>
		if (trimmed.indexOf("[") != -1 && trimmed.indexOf("]") != -1) {
			final bracketStart = trimmed.indexOf("[");
			final bracketEnd = trimmed.lastIndexOf("]");
			final baseType = trimmed.substr(0, bracketStart);
			final innerType = trimmed.substring(bracketStart + 1, bracketEnd);

			if (baseType == "Array") {
				// Convert inner type recursively
				final innerHaxeType = gdTypeToHaxe(innerType);
				return TPath({
					pack: [],
					name: "Array",
					params: [TPType(innerHaxeType)],
					sub: null
				});
			}
		}

		return switch (trimmed) {
			case "int": macro :Int;
			case "float": macro :Float;
			case "bool": macro :Bool;
			case "String" | "StringName": macro :String;
			case "void": macro :Void;
			case "Array": macro :Array<Dynamic>;
			case "Dictionary": macro :Dynamic;
			case "Variant": macro :Dynamic;
			case "Error": macro :Int; // GDScript Error is an enum/int
			case _:
				// Assume it's a Godot type or class
				makeGodotType(trimmed);
		};
	}

	static function makeGodotType(name:String):ComplexType {
		return TPath({
			pack: ["godot"],
			name: name,
			params: null,
			sub: null
		});
	}
}
