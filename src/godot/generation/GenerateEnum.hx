package godot.generation;

import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.Enums.AnyEnum;

// ---

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

@:access(godot.Bindings)
class GenerateEnum {
	public static function generate(data: ExtensionApi, bindings: Bindings, result: Array<TypeDefinition>) {
		for(e in data.global_enums) {
			result.push(generateGlobalEnum(e, bindings));
			bindings.globalEnums.set(e.name, e);
		}
	}

	/**
		Generates the `TypeDefinition` from a "global_enums" object from `extension_api.json`.
	**/
	public static function generateGlobalEnum(globalEnum: AnyEnum, bindings: Bindings, wrapperClassName: Null<String> = null): TypeDefinition {
		final options = bindings.options;

		final meta = Util.makeMetadata(
			#if eval
				#if (haxe < version("4.3.2"))
				macro ":enum"(),
				#end
				macro cppEnum,
				macro generated_godot_api,
				macro bindings_api_type("global_enum"),
				macro "#if gdscript :native"($v{
					(wrapperClassName != null ? (wrapperClassName + ".") : "") + globalEnum.name
				})
			#end
		);

		// Global and class enums have a `is_bitfield` field we need to account for
		if(Reflect.hasField(globalEnum, "is_bitfield")) {
			#if eval
			meta.push(Util.makeMetadataEntry(macro is_bitfield($v{Reflect.field(globalEnum, "is_bitfield")})));
			#end
		}

		final uniqueName = (wrapperClassName != null ? (wrapperClassName + "_") : "") + globalEnum.name;
		final name = Util.processTypeName(uniqueName);

		if(options.cpp) {
			#if eval
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}("godot_cpp/classes/global_constants_binds.hpp")));
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} :native'}($v{
				"godot::" + (wrapperClassName != null ? (wrapperClassName + "::") : "") + globalEnum.name
			})));
			#end
		}

		return {
			name: name,
			pack: bindings.getPack(),
			pos: Util.makeEmptyPosition(),
			fields: globalEnum.values.map(function(godotEnumValue): Field {
				return {
					name: Util.processIdentifier(godotEnumValue.name),
					pos: Util.makeEmptyPosition(),
					access: [APublic, AStatic],
					kind: FFun({
						args: [],
						ret: null,
						expr: null,
						params: null
					}),
					doc: Util.processDescription(godotEnumValue.description)
				}
			}),
			meta: meta,
			isExtern: true,
			kind: TDEnum
		}

		// return {
		// 	name: name,
		// 	pack: getPack(),
		// 	pos: Util.makeEmptyPosition(),
		// 	fields: globalEnum.values.map(function(godotEnumValue): Field {
		// 		return {
		// 			name: Util.processIdentifier(godotEnumValue.name),
		// 			pos: Util.makeEmptyPosition(),
		// 			access: [APublic, AStatic],
		// 			kind: FVar(macro : Int, #if eval macro $v{godotEnumValue.value} #end),
		// 			doc: Util.processDescription(godotEnumValue.description)
		// 			// meta: Util.makeMetadata(#if eval macro "#if cxx :native"($v{
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
}
