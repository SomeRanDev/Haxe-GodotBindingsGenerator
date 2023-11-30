package godot.generation;

import haxe.macro.Context;
import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.BuiltinClass;
import godot.generation.GenerateEnum;

// ---

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

/**
	Generates the `TypeDefinition`s from a "builtin_classes" object from `extension_api.json`.
**/
@:access(godot.Bindings)
class GenerateBuiltinClass {
	/**
		Generates and adds all type definitions from `builtin_classes`.
	**/
	public static function generate(data: ExtensionApi, bindings: Bindings, result: Array<TypeDefinition>) {
		for(builtin in data.builtin_classes) {
			if(builtin.name == "bool" || builtin.name == "int" || builtin.name == "float") {
				continue;
			}

			result.push(generateBuiltinClass(builtin, bindings));

			bindings.builtinClasses.set(builtin.name, builtin);

			for(e in builtin.enums.denullify()) {
				result.push(GenerateEnum.generateGlobalEnum(e, bindings, Util.processTypeName(builtin.name)));
			}
		}
	}

	/**
		Generates a single `TypeDefinition` for the `BuiltinClass`.
	**/
	static function generateBuiltinClass(cls: BuiltinClass, bindings: Bindings): TypeDefinition {
		final fields: Array<Field> = [];
		final fieldAccess = [APublic];

		if(!bindings.options.staticFunctionConstructors) {
			final constructorOverloadMeta = [];

			final constructors = cls.constructors.denullify();

			for(i in 1...constructors.length) {
				final args = constructors[i].arguments.maybeMap(function(arg): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getType(arg.type)
					}
				});

				constructorOverloadMeta.push({
					name: ":overload",
					params: [{
						expr: EFunction(FAnonymous, { args: args, ret: macro : Void, expr: macro {} }),
						pos: Util.makeEmptyPosition()
					}],
					pos: Util.makeEmptyPosition()
				});
			}

			if(constructors.length > 0) {
				final args = constructors[0].arguments.maybeMap(function(arg): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getType(arg.type)
					}
				});

				fields.push({
					name: "new",
					pos: Util.makeEmptyPosition(),
					access: fieldAccess,
					kind: FFun({ args: args, ret: null }),
					meta: constructorOverloadMeta,
					doc: Util.processDescription(constructors[0].description)
				});
			}
			

		} else {
			for(constructor in cls.constructors.denullify()) {
				final args = constructor.arguments.maybeMap(function(arg): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getType(arg.type)
					}
				});

				// bindings.options.staticFunctionConstructors == `true`
				if(constructor.arguments?.length == 0 || cls.constructors?.length == 1) {
					fields.push({
						name: "new",
						pos: Util.makeEmptyPosition(),
						access: fieldAccess,
						kind: FFun({ args: args, ret: null }),
						meta: [],
						doc: Util.processDescription(constructor.description)
					});
				} else {
					fields.push({
						name: "make",
						pos: Util.makeEmptyPosition(),
						access: fieldAccess.concat([AStatic, AOverload]),
						kind: FFun({ args: args, ret: bindings.getType(Util.processTypeName(cls.name)) }),
						meta: Util.makeMetadata(
							macro constructor
						),
						doc: Util.processDescription(constructor.description)
					});
				}
			}
		}

		for(member in cls.members.denullify()) {
			fields.push({
				name: Util.processIdentifier(member.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(bindings.getType(member.type), null),
				meta: [],
				doc: Util.processDescription(member.description)
			});
		}

		for(constant in cls.constants.denullify()) {
			fields.push({
				name: Util.processIdentifier(constant.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(bindings.getType(constant.type), null),
				meta: Util.makeMetadata(
					#if eval
					macro value($v{constant.value})
					#end
				),
				doc: Util.processDescription(constant.description)
			});
		}

		for(method in cls.methods.denullify()) {
			fields.push({
				name: Util.processIdentifier(method.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FFun({
					args: method.arguments.maybeMap(function(arg): FunctionArg {
						return {
							name: Util.processIdentifier(arg.name),
							type: bindings.getType(arg.type),
							opt: arg.default_value != null,
							meta: Util.makeMetadata(
								#if eval
								macro default_value($v{arg.default_value})
								#end
							),
							// value: Null<Expr>
						}
					}),
					ret: bindings.getReturnType(method.return_type)
				}),
				meta: Util.makeMetadata(
					#if eval
					macro is_vararg($v{method.is_vararg}),
					macro is_const($v{method.is_const}),
					macro is_static($v{method.is_static}),
					macro hash($v{method.hash})
					#end
				),
				doc: Util.processDescription(method.description)
			});
		}

		/**
			TODO: operators

			operators: MaybeArray<{
				name: String,
				right_type: Null<String>,
				return_type: String,
				description: Null<String>
			}>,
		**/

		final meta = Util.makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("builtin_classes"),
			macro indexing_return_type($v{cls.indexing_return_type}),
			macro is_keyed($v{cls.is_keyed}),
			macro has_destructor($v{cls.has_destructor}),
			macro avoid_temporaries // TODO: should this be optional?
			#end
		);

		if(bindings.options.cpp) {
			#if eval
			final p = "godot_cpp/variant/" + Util.camelToSnake(cls.name) + ".hpp";
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${bindings.options.cppDefine} :include'}($v{p})));
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${bindings.options.cppDefine} :valueType'}));
			#end
		}

		return {
			name: Util.processTypeName(cls.name),
			pack: bindings.getPack(),
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: Util.processDescription(cls.description)
		}
	}
}
