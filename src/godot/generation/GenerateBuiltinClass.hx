package godot.generation;

import haxe.macro.Context;
import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.BuiltinClass;
import godot.generation.GenerateEnum;

// ---

using StringTools;
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

			final fieldsTypeDef: TypeDefinition = generateBuiltinClass(builtin, bindings);
			result.push(fieldsTypeDef);

			// Operators abstract
			result.push(generateBuiltinAbstract(fieldsTypeDef, builtin, bindings));

			bindings.builtinClasses.set(builtin.name, builtin);

			for(e in builtin.enums.denullify()) {
				result.push(GenerateEnum.generateGlobalEnum(e, bindings, Util.processTypeName(builtin.name), "godot_cpp/variant/" + Util.camelToSnake(builtin.name) + ".hpp"));
			}
		}
	}

	/**
		Get the key type for array access.
	**/
	static function indexKeyType(name: String) {
		return switch(name) {
			case "Dictionary": macro : String;
			case _: macro : Int;
		}
	}

	/**
		Generates the abstract wrapper containing the operator overloads.
	**/
	static function generateBuiltinAbstract(fieldsTypeDef: TypeDefinition, cls: BuiltinClass, bindings: Bindings): TypeDefinition {
		final options = bindings.options;
		final name = Util.processTypeName(cls.name);
		
		final fieldsClassCt = ComplexType.TPath({
			name: fieldsTypeDef.name,
			pack: bindings.getPack()
		});

		final selAbstractCt = ComplexType.TPath({
			name: name,
			pack: bindings.getPack()
		});

		final fields: Array<Field> = [];

		if(cls.indexing_return_type != null) {
			final valueType = bindings.getType(cls.indexing_return_type);
			final keyType = indexKeyType(name);

			final injectGet = Util.generateInjectionExpr('${options.injectFunction}("({0}[{1}])", this, key)');
			final injectSet = Util.generateInjectionExpr('${options.injectFunction}("({0}[{1}] = {2})", this, key, value)');

			final arrayAccessFields = macro class {
				@:arrayAccess
				public inline function arrayAccessGet(key: $keyType): $valueType {
					return $injectGet;
				}

				@:arrayAccess
				public inline function arrayAccessSet(key: $keyType, value: $valueType): $valueType {
					$injectSet;
					return value;
				}
			}

			for(f in arrayAccessFields.fields) {
				fields.push(f);
			}
		}

		final nameCounter: Map<String, Int> = [];
		for(op in cls.operators.denullify()) {
			final opExpr = switch(op.name) {
				case "not": macro !A;
				case "unary-": macro -A;
				case "unary+": continue; // +A not supported
				case "and": macro A & B;
				case "or": macro A | B;
				case "xor": macro A ^ B;
				case op: {
					#if eval
					Context.parse("A " + op + " B", Context.currentPos());
					#else
					throw "Impossible";
					#end
				}
			}

			final opInject = switch(op.name) {
				case "not": "!{0}";
				case "unary-": "-{0}";
				case "unary+": continue; // +A not supported
				case op: "{0} " + op + " {1}";
			}

			final opName = switch(opExpr.expr) {
				case EUnop(op, _, _): Std.string(op);
				case EBinop(op, _, _): Std.string(op);
				case _: null;
			}

			if(opName == null) continue;

			// Generate name for field
			var opFieldName = opName.substr(2, 1).toLowerCase() + opName.substr(3);
			if(opFieldName == "in") opFieldName += "Op";

			// Make sure the name is unique.
			// TODO: Maybe use overload instead?
			if(!nameCounter.exists(opFieldName)) nameCounter.set(opFieldName, 1);
			else {
				final ogName = opFieldName;
				final count = (nameCounter.get(ogName) ?? 0) + 1;
				opFieldName += count;
				nameCounter.set(ogName, count);
			}

			final args = [
				{ name: "self", type: selAbstractCt }
			];

			if(op.right_type != null) {
				args.push({
					name: "other",
					type: bindings.getArgumentType(op.right_type)
				});
			}
			
			final injectExpr = Util.generateInjectionExpr('${options.injectFunction}("(${opInject})", ${args.map(a -> a.name).join(", ")})');

			fields.push({
				name: opFieldName,
				doc: Util.processDescription(op.description),
				access: [APublic, AStatic, AInline],
				kind: FFun({
					args: args,
					ret: bindings.getReturnType(op.return_type),
					expr: macro {
						return $injectExpr;
					}
				}),
				pos: Util.makeEmptyPosition(),
				meta: [
					{ name: ":op", params: [opExpr], pos: Util.makeEmptyPosition() }
				]
			});
		}

		// Let's manually add some nice auto-conversions
		//
		// TODO: Could we make this less hardcoded? Maybe find all built-in
		//       types with "one-argument" constructors and turn them into auto-conversions?
		switch(cls.name) {
			case "StringName" | "NodePath": {
				final selfCt: TypePath = { name: cls.name, pack: bindings.getPack() };
				fields.push({
					name: "fromString",
					access: [APublic, AStatic, AInline, AExtern],
					kind: FFun({
						args: [ { name: "s", type: macro : String } ],
						ret: TPath(selfCt),
						expr: macro return new $selfCt(s)
					}),
					pos: Util.makeEmptyPosition(),
					meta: Util.makeMetadata(macro from)
				});
			}
			case _:
		}

		return {
			name: name,
			pack: bindings.getPack(),
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDAbstract(fieldsClassCt),
			isExtern: true,
			meta: Util.makeMetadata(macro forward, macro ":forward.new", macro forwardStatics, macro copyType),
			doc: Util.processDescription(cls.description)
		};
	}

	/**
		Generates a single `TypeDefinition` for the `BuiltinClass`.
	**/
	static function generateBuiltinClass(cls: BuiltinClass, bindings: Bindings): TypeDefinition {
		final fields: Array<Field> = [];
		final fieldAccess = [APublic];

		final constructors = cls.constructors.denullify();

		// For some reason, constructors using all the members exists in both GDScript and Godot-CPP,
		// but they are not shown in `extension_api.json`.
		//
		// We need these for some getter constants, so let's make them exist.
		switch(cls.name) {
			case "Basis" | "Projection" | "Transform2D" | "Transform3D": {
				constructors.push({
					index: -1,
					arguments: {
						final result = [];
						for(m in cls.members.denullify()) {
							function addMember(name, type) {
								switch(type) {
									case "float": result.push({ name: name, type: "float" });
									case "Vector2": for(f in ["x", "y"]) addMember(name + f, "float");
									case "Vector3": for(f in ["x", "y", "z"]) addMember(name + f, "float");
									case "Vector4": for(f in ["x", "y", "z", "w"]) addMember(name + f, "float");
									case "Basis": for(f in ["x", "y", "z"]) addMember(name + f, "Vector3");
									case a: throw a;
								}
							}
							addMember(m.name, m.type);
						}
						result;
					},
					description: null
				});
			}
			case _:
		}

		if(!bindings.options.staticFunctionConstructors) {
			final constructorOverloadMeta = [];

			for(i in 1...constructors.length) {
				final args = constructors[i].arguments.maybeMap(function(arg, _): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getArgumentType(arg.type)
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
				final args = constructors[0].arguments.maybeMap(function(arg, _): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getArgumentType(arg.type)
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
			for(constructor in constructors) {
				final args = constructor.arguments.maybeMap(function(arg, _): FunctionArg {
					return {
						name: Util.processIdentifier(arg.name),
						type: bindings.getArgumentType(arg.type)
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

		final isBasis = cls.name == "Basis";
		for(member in cls.members.denullify()) {
			// Handle basis x/y/z for C++
			final meta = if(bindings.options.cpp && isBasis) {
				final name = switch(member.name) {
					case "x": "get_column(0)";
					case "y": "get_column(1)";
					case "z": "get_column(2)";
					case _: null;
				}

				name == null ? [] : Util.makeMetadata(
					#if eval
					macro $v{'#if ${bindings.options.cppDefine} :nativeName'}($v{name})
					#end
				);
			} else {
				[];
			}

			fields.push({
				name: Util.processIdentifier(member.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FVar(bindings.getType(member.type), null),
				meta: meta,
				doc: Util.processDescription(member.description)
			});
		}

		for(constant in cls.constants.denullify()) {
			final haxeExprString = switch(constant.type) {
				case "bool" | "int" | "float": constant.value;
				case "String": constant.value; // TODO: wrap in quotes??
				case "Array" | "Variant": null;
				case _ if(constant.value.startsWith(constant.type)): {
					if(constant.value.contains("inf")) {
						null;
					} else {
						"new " + constant.value;
					}
				}
				case _: null;
			}

			// GDScript constant (just extern)
			{
				final meta = Util.makeMetadata(
					#if eval
					macro value($v{constant.value}),
					macro godot_bindings_gen_prepend($v{'#if gdscript'}),
					#end
				);

				// Do #else if possible to generate static getter
				final append = haxeExprString != null ? '#else' : '#end';
				#if eval meta.push(Util.makeMetadataEntry( macro godot_bindings_gen_append($v{append}))); #end

				fields.push({
					name: Util.processIdentifier(constant.name),
					pos: Util.makeEmptyPosition(),
					access: fieldAccess.concat([AStatic]),
					kind: FVar(bindings.getType(constant.type), null),
					meta: meta,
					doc: Util.processDescription(constant.description)
				});
			}

			// Other constant (use static getter if possible)
			if(haxeExprString != null) {
				fields.push({
					name: Util.processIdentifier(constant.name),
					pos: Util.makeEmptyPosition(),
					access: fieldAccess.concat([AStatic]),
					kind: FProp("get", "never", bindings.getType(constant.type)),
					meta: Util.makeMetadata(
						#if eval
						macro value($v{constant.value})
						#end
					),
					doc: Util.processDescription(constant.description)
				});

				fields.push({
					name: "get_" + Util.processIdentifier(constant.name),
					pos: Util.makeEmptyPosition(),
					access: fieldAccess.concat([AStatic, AExtern, AInline]),
					kind: FFun({
						args: [],
						expr: macro return ${Util.generateInjectionExpr(haxeExprString)}
					}),
					meta: Util.makeMetadata(
						#if eval
						macro godot_bindings_gen_append($v{'#end'})
						#end
					)
				});
			}
		}

		for(method in cls.methods.denullify()) {
			fields.push({
				name: Util.processIdentifier(method.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess,
				kind: FFun({
					args: method.arguments.maybeMap(function(arg, _): FunctionArg {
						return {
							name: Util.processIdentifier(arg.name),
							type: bindings.getArgumentType(arg.type),
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

		final meta = Util.makeMetadata(
			#if eval
			macro generated_godot_api,
			macro bindings_api_type("builtin_classes"),
			macro indexing_return_type($v{cls.indexing_return_type}),
			macro is_keyed($v{cls.is_keyed}),
			macro has_destructor($v{cls.has_destructor}),
			macro copyType,
			macro noCompletion,
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

		var nativeName = Util.processTypeName(cls.name);
		final fieldsClassName = nativeName + "_Fields";

		// Remove "Godot" prefix for String and Array @:nativeName
		switch(nativeName) {
			case "GodotArray" | "GodotString": nativeName = nativeName.substr("Godot".length);
			case _:
		}

		#if eval
		meta.push(Util.makeMetadataEntry(macro nativeName($v{nativeName})));
		#end 

		return {
			name: fieldsClassName,
			pack: bindings.getPack(),
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDClass(null, null, false, false, false),
			isExtern: true,
			meta: meta,
			// doc is applied on abstract
			// doc: Util.processDescription(cls.description)
		}
	}
}
