package godot.gdscript;

import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
	Parsed GDScript class information.
**/
typedef GDScriptClass = {
	name:String,
	extends_:Null<String>,
	filePath:String,
	signals:Array<GDScriptSignal>,
	methods:Array<GDScriptMethod>,
	properties:Array<GDScriptProperty>,
	constants:Array<GDScriptConstant>
}

typedef GDScriptSignal = {
	name:String,
	arguments:Array<GDScriptArg>,
	description:Null<String>
}

typedef GDScriptMethod = {
	name:String,
	arguments:Array<GDScriptArg>,
	returnType:Null<String>,
	isStatic:Bool,
	description:Null<String>
}

typedef GDScriptArg = {
	name:String,
	type:Null<String>,
	defaultValue:Null<String>
}

typedef GDScriptProperty = {
	name:String,
	type:Null<String>,
	defaultValue:Null<String>,
	isExport:Bool,
	isConst:Bool,
	description:Null<String>
}

typedef GDScriptConstant = {
	name:String,
	type:Null<String>,
	value:Null<String>,
	description:Null<String>
}

/**
	Simple GDScript parser to extract class information from .gd files.
**/
class GDScriptParser {
	/**
		Parse all .gd files in a directory recursively.
	**/
	public static function parseDirectory(path:String):Array<GDScriptClass> {
		final results:Array<GDScriptClass> = [];

		if (!FileSystem.exists(path)) {
			throw 'Directory not found: $path';
		}

		function scanDir(dir:String) {
			for (entry in FileSystem.readDirectory(dir)) {
				final fullPath = haxe.io.Path.join([dir, entry]);
				if (FileSystem.isDirectory(fullPath)) {
					// Skip hidden directories and common non-source folders
					if (!entry.startsWith(".") && entry != "addons" && entry != ".godot") {
						scanDir(fullPath);
					}
				} else if (entry.endsWith(".gd")) {
					final parsed = parseFile(fullPath);
					if (parsed != null) {
						results.push(parsed);
					}
				}
			}
		}

		scanDir(path);
		return results;
	}

	/**
		Parse a single .gd file.
	**/
	public static function parseFile(filePath:String):Null<GDScriptClass> {
		if (!FileSystem.exists(filePath)) {
			return null;
		}

		final content = File.getContent(filePath);
		return parseContent(content, filePath);
	}

	/**
		Join multi-line function declarations into single lines.
		GDScript allows function signatures to span multiple lines.
	**/
	static function joinMultilineDeclarations(content:String):String {
		final lines = content.split("\n");
		final result:Array<String> = [];
		var pendingLine:Null<String> = null;
		var openParens = 0;

		for (line in lines) {
			if (pendingLine != null) {
				// Continue accumulating until parens are balanced and we find ":"
				pendingLine += " " + line.trim();

				for (i in 0...line.length) {
					final c = line.charAt(i);
					if (c == "(")
						openParens++;
					else if (c == ")")
						openParens--;
				}

				// Check if declaration is complete (balanced parens and ends with :)
				if (openParens <= 0 && pendingLine.indexOf(":") != -1) {
					result.push(pendingLine);
					pendingLine = null;
					openParens = 0;
				}
			} else {
				final trimmed = line.trim();
				// Check if this is a func declaration that might span multiple lines
				if ((trimmed.startsWith("func ") || trimmed.startsWith("static func "))
					&& trimmed.indexOf("(") != -1
					&& !trimmed.endsWith(":")) {
					pendingLine = line;
					openParens = 0;
					for (i in 0...line.length) {
						final c = line.charAt(i);
						if (c == "(")
							openParens++;
						else if (c == ")")
							openParens--;
					}
					// If parens are balanced and has colon, it's complete
					if (openParens <= 0 && trimmed.indexOf(":") != -1) {
						result.push(line);
						pendingLine = null;
						openParens = 0;
					}
				} else {
					result.push(line);
				}
			}
		}

		// Add any remaining pending line
		if (pendingLine != null) {
			result.push(pendingLine);
		}

		return result.join("\n");
	}

	/**
		Parse GDScript content string.
	**/
	public static function parseContent(content:String, filePath:String):Null<GDScriptClass> {
		// Pre-process: join multi-line function declarations
		final processedContent = joinMultilineDeclarations(content);
		final lines = processedContent.split("\n");

		var className:Null<String> = null;
		var extends_:Null<String> = null;
		final signals:Array<GDScriptSignal> = [];
		final methods:Array<GDScriptMethod> = [];
		final properties:Array<GDScriptProperty> = [];
		final constants:Array<GDScriptConstant> = [];

		var lastComment:Null<String> = null;
		var isExportNext = false;
		var insideFunction = false;

		for (line in lines) {
			final trimmed = line.trim();

			// Check indentation - class level declarations have no indentation
			final isClassLevel = line.length > 0 && (line.charAt(0) != "\t" && line.charAt(0) != " ");

			// Track if we're inside a function
			if (isClassLevel && (trimmed.startsWith("func ") || trimmed.startsWith("static func "))) {
				insideFunction = true;
			} else if (isClassLevel && trimmed.length > 0 && !trimmed.startsWith("#") && !trimmed.startsWith("@")) {
				// Any other class-level non-comment, non-annotation line means we're out of func
				insideFunction = false;
			}

			// Skip empty lines
			if (trimmed.length == 0) {
				lastComment = null;
				isExportNext = false;
				continue;
			}

			// Only process class-level declarations
			if (!isClassLevel) {
				continue;
			}

			// Capture comments for documentation
			if (trimmed.startsWith("##")) {
				// Doc comment
				lastComment = trimmed.substr(2).trim();
				continue;
			} else if (trimmed.startsWith("#")) {
				// Regular comment - could be doc
				if (lastComment == null) {
					lastComment = trimmed.substr(1).trim();
				}
				continue;
			}

			// Check for @export annotation
			if (trimmed.startsWith("@export")) {
				// Check if it's inline: @export var name
				if (trimmed.indexOf(" var ") != -1) {
					// Extract the var part and parse it
					final varPart = trimmed.substr(trimmed.indexOf("var "));
					final prop = parseProperty(varPart, true, lastComment);
					if (prop != null) {
						// Check for duplicates
						var isDuplicate = false;
						for (existing in properties) {
							if (existing.name == prop.name) {
								isDuplicate = true;
								break;
							}
						}
						if (!isDuplicate) {
							properties.push(prop);
						}
					}
					lastComment = null;
					isExportNext = false;
				} else {
					// @export on its own line, next line should be var
					isExportNext = true;
				}
				continue;
			}

			// Parse class_name (may include inline extends)
			if (trimmed.startsWith("class_name ")) {
				final rest = trimmed.substr("class_name ".length).trim();
				// Handle: class_name MyClass extends BaseClass
				if (rest.indexOf(" extends ") != -1) {
					final parts = rest.split(" extends ");
					className = parts[0].trim();
					extends_ = parts[1].trim();
				} else {
					className = rest;
				}
				lastComment = null;
				continue;
			}

			// Parse extends
			if (trimmed.startsWith("extends ")) {
				extends_ = trimmed.substr("extends ".length).trim();
				lastComment = null;
				continue;
			}

			// Parse signal
			if (trimmed.startsWith("signal ")) {
				final signal = parseSignal(trimmed, lastComment);
				if (signal != null) {
					signals.push(signal);
				}
				lastComment = null;
				continue;
			}

			// Parse const
			if (trimmed.startsWith("const ")) {
				final constant = parseConstant(trimmed, lastComment);
				if (constant != null) {
					constants.push(constant);
				}
				lastComment = null;
				continue;
			}

			// Parse var (only at class level, not inside functions)
			if (trimmed.startsWith("var ") || (isExportNext && trimmed.startsWith("var "))) {
				final prop = parseProperty(trimmed, isExportNext, lastComment);
				if (prop != null) {
					// Check for duplicates
					var isDuplicate = false;
					for (existing in properties) {
						if (existing.name == prop.name) {
							isDuplicate = true;
							break;
						}
					}
					if (!isDuplicate) {
						properties.push(prop);
					}
				}
				lastComment = null;
				isExportNext = false;
				continue;
			}

			// Parse func
			if (trimmed.startsWith("func ") || trimmed.startsWith("static func ")) {
				final method = parseMethod(trimmed, lastComment);
				if (method != null) {
					methods.push(method);
				}
				lastComment = null;
				insideFunction = true;
				continue;
			}

			// Reset state for other lines
			if (!trimmed.startsWith("@")) {
				isExportNext = false;
			}
		}

		// If no class_name, derive from filename
		if (className == null) {
			final filename = haxe.io.Path.withoutDirectory(filePath);
			className = haxe.io.Path.withoutExtension(filename);
			// Convert snake_case to PascalCase
			className = snakeToPascal(className);
		}

		return {
			name: className,
			extends_: extends_,
			filePath: filePath,
			signals: signals,
			methods: methods,
			properties: properties,
			constants: constants
		};
	}

	static function parseSignal(line:String, comment:Null<String>):Null<GDScriptSignal> {
		// signal my_signal
		// signal my_signal(arg1, arg2: int)
		final withoutSignal = line.substr("signal ".length).trim();

		final parenPos = withoutSignal.indexOf("(");
		if (parenPos == -1) {
			// No arguments
			return {
				name: withoutSignal,
				arguments: [],
				description: comment
			};
		}

		final name = withoutSignal.substr(0, parenPos).trim();
		final argsStr = withoutSignal.substring(parenPos + 1, withoutSignal.lastIndexOf(")"));
		final args = parseArguments(argsStr);

		return {
			name: name,
			arguments: args,
			description: comment
		};
	}

	static function parseMethod(line:String, comment:Null<String>):Null<GDScriptMethod> {
		// func my_func():
		// func my_func(arg1: int) -> String:
		// static func my_func():

		final isStatic = line.startsWith("static ");
		final withoutStatic = isStatic ? line.substr("static ".length).trim() : line;
		final withoutFunc = withoutStatic.substr("func ".length).trim();

		// Remove trailing colon
		var cleaned = withoutFunc;
		if (cleaned.endsWith(":")) {
			cleaned = cleaned.substr(0, cleaned.length - 1);
		}

		final parenPos = cleaned.indexOf("(");
		if (parenPos == -1) {
			return null;
		}

		final name = cleaned.substr(0, parenPos).trim();

		final closeParenPos = cleaned.indexOf(")");
		final argsStr = cleaned.substring(parenPos + 1, closeParenPos);
		final args = parseArguments(argsStr);

		// Check for return type
		var returnType:Null<String> = null;
		final arrowPos = cleaned.indexOf("->");
		if (arrowPos != -1) {
			returnType = cleaned.substr(arrowPos + 2).trim();
		}

		return {
			name: name,
			arguments: args,
			returnType: returnType,
			isStatic: isStatic,
			description: comment
		};
	}

	static function parseProperty(line:String, isExport:Bool, comment:Null<String>):Null<GDScriptProperty> {
		// var my_var
		// var my_var: int
		// var my_var: int = 5
		// var my_var = 5

		final withoutVar = line.substr("var ".length).trim();

		var name:String;
		var type:Null<String> = null;
		var defaultValue:Null<String> = null;

		final colonPos = withoutVar.indexOf(":");
		final equalsPos = withoutVar.indexOf("=");

		if (colonPos != -1 && (equalsPos == -1 || colonPos < equalsPos)) {
			name = withoutVar.substr(0, colonPos).trim();
			if (equalsPos != -1) {
				type = withoutVar.substring(colonPos + 1, equalsPos).trim();
				defaultValue = withoutVar.substr(equalsPos + 1).trim();
			} else {
				type = withoutVar.substr(colonPos + 1).trim();
			}
		} else if (equalsPos != -1) {
			name = withoutVar.substr(0, equalsPos).trim();
			defaultValue = withoutVar.substr(equalsPos + 1).trim();
		} else {
			name = withoutVar;
		}

		// Skip private vars
		if (name.startsWith("_")) {
			return null;
		}

		return {
			name: name,
			type: type,
			defaultValue: defaultValue,
			isExport: isExport,
			isConst: false,
			description: comment
		};
	}

	static function parseConstant(line:String, comment:Null<String>):Null<GDScriptConstant> {
		// const MY_CONST = 5
		// const MY_CONST: int = 5

		final withoutConst = line.substr("const ".length).trim();

		var name:String;
		var type:Null<String> = null;
		var value:Null<String> = null;

		final colonPos = withoutConst.indexOf(":");
		final equalsPos = withoutConst.indexOf("=");

		if (colonPos != -1 && equalsPos != -1 && colonPos < equalsPos) {
			name = withoutConst.substr(0, colonPos).trim();
			type = withoutConst.substring(colonPos + 1, equalsPos).trim();
			value = withoutConst.substr(equalsPos + 1).trim();
		} else if (equalsPos != -1) {
			name = withoutConst.substr(0, equalsPos).trim();
			value = withoutConst.substr(equalsPos + 1).trim();
		} else {
			name = withoutConst;
		}

		return {
			name: name,
			type: type,
			value: value,
			description: comment
		};
	}

	static function parseArguments(argsStr:String):Array<GDScriptArg> {
		if (argsStr.trim().length == 0) {
			return [];
		}

		final args:Array<GDScriptArg> = [];
		final parts = argsStr.split(",");

		for (part in parts) {
			final trimmed = part.trim();
			if (trimmed.length == 0)
				continue;

			var name:String;
			var type:Null<String> = null;
			var defaultValue:Null<String> = null;

			final colonPos = trimmed.indexOf(":");
			final equalsPos = trimmed.indexOf("=");

			if (colonPos != -1) {
				name = trimmed.substr(0, colonPos).trim();
				if (equalsPos != -1 && equalsPos > colonPos) {
					type = trimmed.substring(colonPos + 1, equalsPos).trim();
					defaultValue = trimmed.substr(equalsPos + 1).trim();
				} else {
					type = trimmed.substr(colonPos + 1).trim();
				}
			} else if (equalsPos != -1) {
				name = trimmed.substr(0, equalsPos).trim();
				defaultValue = trimmed.substr(equalsPos + 1).trim();
			} else {
				name = trimmed;
			}

			args.push({
				name: name,
				type: type,
				defaultValue: defaultValue
			});
		}

		return args;
	}

	static function snakeToPascal(s:String):String {
		final parts = s.split("_");
		return parts.map(p -> p.length > 0 ? p.charAt(0).toUpperCase() + p.substr(1) : "").join("");
	}
}
