package godot.generation;

import haxe.macro.Expr;

import godot.BindingsUtil as Util;
import godot.extension_api.Class as GodotClass;
import godot.generation.GenerateEnum;

// ---

using godot.bindings.NullableArrayTools;
using godot.bindings.NullTools;

/**
	Generates the `TypeDefinition`s from a "classes" object from `extension_api.json`.
**/
@:access(godot.Bindings)
class GenerateClass {
	/**
		Names of the loaded Godot singletons.
	**/
	static var singletons: Map<String, Bool> = [];

	/**
		Generates and adds all type definitions from `classes`.
	**/
	public static function generate(data: ExtensionApi, bindings: Bindings, result: Array<TypeDefinition>) {
		final options = bindings.options;

		// Figure out which classes should be Ref<T> or T*
		final typeType = bindings.typeType;
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
		singletons = [];
		if(data.singletons != null) {
			for(singleton in data.singletons.denullify()) {
				singletons.set(singleton.name, true);
			}
		}

		for(cls in data.classes) {
			for(e in cls.enums.denullify()) {
				bindings.globalEnums.set(cls.name + "_" + e.name, e);
			}
		}

		// Generate bindings for "classes"
		final hierarchyData = options.generateHierarchyMeta.length > 0 ? bindings.generateHierarchyData(data.classes) : null;
		for(cls in data.classes) {
			final typeDefinition = generateClass(cls, bindings);

			// Generate additional metadata from `generateHierarchyMeta`
			if(hierarchyData != null && hierarchyData.exists(cls.name)) {
				for(className => inherits in hierarchyData.get(cls.name).trustMe()) {
					final m = typeDefinition.meta ?? [];
					m.push({
						name: ":is_" + className.toLowerCase(),
						params: [#if eval macro $v{inherits} #end],
						pos: Util.makeEmptyPosition()
					});
					typeDefinition.meta = m;
				}
			}

			result.push(typeDefinition);

			for(e in cls.enums.denullify()) {
				result.push(GenerateEnum.generateGlobalEnum(e, bindings, Util.processTypeName(cls.name)));
			}
		}
	}

	/**
		Generates a single `TypeDefinition` for the `Class`.
	**/
	static function generateClass(cls: GodotClass, bindings: Bindings): TypeDefinition {
		final options = bindings.options;

		final fields = [];
		final fieldAccess = [APublic];

		final isSingleton = singletons.exists(cls.name);

		for(constant in cls.constants.denullify()) {
			fields.push({
				name: Util.processIdentifier(constant.name),
				pos: Util.makeEmptyPosition(),
				access: fieldAccess.concat([AStatic]),
				kind: FVar(macro : Int,
					// Cannot have value on extern, but if we could we'd use: macro $v{constant.value}),
					null
				),
				meta: [],
				doc: Util.processDescription(constant.description)
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

			final name = Util.processIdentifier(property.name);

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
					meta: !options.cpp ? [] : Util.makeMetadata(
						#if eval
						macro godot_bindings_gen_prepend($v{'#if !${Util.cxxInlineSingletonsCondition}'}),
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
					final typeString = haxe.macro.ComplexTypeTools.toString(bindings.getType(property.type));

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

						var enumObj = bindings.globalEnums.get(enumHaxeName);

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

					propertyMeta = Util.makeMetadata(
						#if eval
						macro godot_bindings_gen_prepend($v{'$getter\n$setter'}),
						#end
					);
				}

				fields.push({
					name: name,
					pos: Util.makeEmptyPosition(),
					access: data.access,
					kind: FProp("get", property.setter == null ? "never" : "set", bindings.getType(property.type)),
					meta: Util.makeMetadata(
						#if eval
						macro index($v{property.index}),
						macro getter($v{property.getter}),
						macro setter($v{property.setter}),
						macro godot_bindings_gen_prepend($v{'#if use_properties'}),
						macro godot_bindings_gen_append("#else")
						#end
					).concat(data.meta).concat(propertyMeta),
					doc: Util.processDescription(property.description)
				});

				// Let's add #end to normal field
				data.meta.push(Util.makeMetadataEntry(macro godot_bindings_gen_append("#end")));
			} else {
				// If ignoring property, let's still wrap the normal variable
				#if eval
				data.meta.push(Util.makeMetadataEntry(macro godot_bindings_gen_prepend($v{'#if !use_properties'})));
				data.meta.push(Util.makeMetadataEntry(macro godot_bindings_gen_append("#end")));
				#end
			}

			fields.push({
				name: name,
				pos: Util.makeEmptyPosition(),
				access: data.access,
				kind: FVar(bindings.getType(property.type)),
				meta: Util.makeMetadata(
					#if eval
					macro index($v{property.index}),
					macro getter($v{property.getter}),
					macro setter($v{property.setter})
					#end
				).concat(data.meta),
				doc: Util.processDescription(property.description)
			});
		}

		for(method in cls.methods.denullify()) {
			final metadata = Util.makeMetadata(
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
					Util.makeMetadata(
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

			var name = Util.processIdentifier(method.name);
			final originalName = name;

			final setterType = setters.get(name);

			final nativeMeta = if(propertyRenames.exists(name)) {
				final result = Util.makeMetadata(#if eval macro $v{'#if use_properties ${options.nativeNameMeta}'}($v{name}) #end);
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
					pos: Util.makeEmptyPosition(),
					access: additionalAccess == null ? fieldAccess : (fieldAccess.concat(additionalAccess)),
					kind: FFun({
						args: method.arguments.maybeMap(function(godotArg): FunctionArg {
							return {
								name: Util.processIdentifier(godotArg.name),
								type: bindings.getType(godotArg.type),
								meta: Util.makeMetadata(
									#if eval
									macro meta($v{godotArg.meta}),
									macro default_value($v{godotArg.default_value}),
									#end
								).concat(nativeMeta),
								value: Util.getValue(godotArg)
							}
						}),
						ret: bindings.getReturnType(method.return_value?.type),
						expr: expr
					}),
					meta: extraMetadata == null ? metadata : metadata.concat(extraMetadata),
					doc: Util.processDescription(method.description)
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
						[macro $v{call}].concat(margs.map(a -> macro $i{Util.processIdentifier(a.name)}))
						#else
						[]
						#end;
					}
					
					addField(
						null,
						Util.makeMetadata(
							#if eval
							macro godot_bindings_gen_prepend($v{'#if ${Util.cxxInlineSingletonsCondition}'}),
							macro godot_bindings_gen_append("\n#else")
							#end
						),
						[AStatic, AExtern, AInline],
						#if eval macro {
							untyped __include__($v{"godot_cpp/classes/" + Util.camelToSnake(cls.name) + ".hpp"});
							return untyped __cpp__($a{totalArgs});
						} #else null #end
					);
				}

				// -----------------------
				// Normal static call
				addField(
					null,
					!options.cpp ? [] : Util.makeMetadata(
						#if eval
						macro godot_bindings_gen_append("#end")
						#end
					),
					[AStatic]
				);
			} else {

				var baseFieldMetadata = [];

				if(setterType != null) {
					final t = haxe.macro.ComplexTypeTools.toString(bindings.getReturnType(setterType));
					addField(
						null,
						Util.makeMetadata(
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


					baseFieldMetadata = Util.makeMetadata(
						#if eval
						macro godot_bindings_gen_append("\n#end")
						#end
					);
				}

				// Special case to deal with Godot-CPP's `get_node<T>`.
				// To get the behavior expected for GDScript's `get_node`, `get_node_internal` should be used.
				if(options.cpp && cls.name == "Node" && originalName == "get_node") {
					#if eval
					baseFieldMetadata.push(Util.makeMetadataEntry(macro $v{'#if ${Util.cxxFixGetNode} ${options.nativeNameMeta}'}("get_node_internal")));
					#end
				} else if(preimplName != originalName) {
					#if eval
					baseFieldMetadata.push(Util.makeMetadataEntry(macro $v{options.nativeNameMeta}($v{originalName})));
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

		final meta = Util.makeMetadata(
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
			final p = "godot_cpp/classes/" + Util.camelToSnake(cls.name) + ".hpp";
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} :include'}($v{p})));
			meta.push(Util.makeMetadataEntry(macro $v{'#if ${options.cppDefine} :valueType'}));
			#end
		}

		return {
			name: Util.processTypeName(cls.name),
			pack: bindings.getPack(),
			pos: Util.makeEmptyPosition(),
			fields: fields,
			kind: TDClass((cls.inherits == null ? null : Util.getTypePathFromComplex(bindings.getType(cls.inherits, true))), null, false, false, false),
			isExtern: true,
			meta: meta,
			doc: Util.processDescription(cls.description)
		}
	}
}