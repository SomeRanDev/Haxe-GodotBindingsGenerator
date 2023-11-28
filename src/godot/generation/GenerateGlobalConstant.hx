package godot.generation;

import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.GlobalConstant;

// ---

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

class GenerateGlobalConstant {
	/**
		Generates the `TypeDefinition` from a "global_constants" object from `extension_api.json`.
	**/
	public static function generate(globalConstant: GlobalConstant, bindings: Bindings): Field {
		return {
			name: Util.processIdentifier(globalConstant.name),
			pos: Util.makeEmptyPosition(),
			access: [APublic, AStatic, AExtern],
			kind: FVar(macro : Int, null), // not sure if always typing as `Int` is correct?
			meta: Util.makeMetadata(
				#if eval
				macro generated_godot_api,
				macro bindings_api_type("global_constant"),
				macro is_bitfield($v{globalConstant.is_bitfield})
				#end
			),
			doc: Util.processDescription(globalConstant.description)
		}
	}
}
