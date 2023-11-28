package godot.generation;

import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.UtilityFunction;
import godot.generation.GenerateEnum;

// ---

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

@:access(godot.Bindings)
class GenerateUtilityFunction {
	/**
		Generates the `TypeDefinition` from a "utility_functions" object from `extension_api.json`.
	**/
	public static function generate(utilityFunction: UtilityFunction, bindings: Bindings): Field {
		final options = bindings.options;

		final meta = Util.makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("utility_function"),
			macro godot_name($v{utilityFunction.name}),
			macro category($v{utilityFunction.category}),
			macro is_vararg($v{utilityFunction.is_vararg}),
			macro hash($v{utilityFunction.hash}),
			macro $v{'#if gdscript ${options.nativeReplaceMeta}'}($v{Util.processIdentifier(utilityFunction.name)})
			#end
		);

		if(options.cpp) {
			#if eval
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}("godot_cpp/variant/utility_functions.hpp")));
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} ${options.nativeReplaceMeta}'}($v{"godot::UtilityFunctions::" + utilityFunction.name})));
			#end
		}

		return {
			name: Util.processIdentifier(utilityFunction.name),
			pos: Util.makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FFun({
				ret: bindings.getReturnType(utilityFunction.return_type),
				args: utilityFunction.arguments.maybeMap(t -> ({
					name: Util.processIdentifier(t.name),
					type: bindings.getType(t.type)
				} : FunctionArg))
			}),
			meta: meta,
			doc: Util.processDescription(utilityFunction.description)
		}
	}
}
