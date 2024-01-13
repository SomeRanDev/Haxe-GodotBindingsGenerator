package;

import sys.FileSystem;
import sys.io.Process;

function main() {
	var jsonPath = null;
	var outputDir = null;

	final args = Sys.args();

	// Check for --cpp
	final isCpp = if(args.contains("--cpp")) {
		args.remove("--cpp");
		true;
	} else false;

	// Check for --nativeName
	final nativeMeta = if(args.contains("--nativeName")) {
		args.remove("--nativeName");
		":nativeName";
	} else ":native";

	// Check for --godotVariantType
	final variantType = if(args.contains("--godotVariantType")) {
		args.remove("--godotVariantType");
		macro : GodotVariant;
	} else macro : Dynamic;

	final cwd = switch(args) {
		case ["help", _]: {
			help();
			return;
		}
		case [cwd]: {
			cwd;
		}
		case [_outputDir, cwd]: {
			outputDir = _outputDir;
			cwd;
		}
		case [_outputDir, _jsonPath, cwd]: {
			outputDir = _outputDir;
			jsonPath = _jsonPath;
			cwd;
		}
		case _: {
			Sys.println("** Invalid arguments. **\n");
			help();
			return;
		}
	}

	// Ensure we use current directory of haxelib run call.
	if(cwd != null) {
		Sys.setCwd(cwd);
	}

	// Check output directory
	if(outputDir == null) {
		Sys.println("No output directory defined, using \"godot/\".");
		outputDir = "godot";
	}

	// Check json path
	final shouldGenerate = if(jsonPath == null && !FileSystem.exists("extension_api.json")) {
		Sys.println("No `extension_api.json` found, let's generated them!");
		true;
	} else {
		false;
	}

	// Generate extension_api.json
	if(shouldGenerate) {
		jsonPath = "extension_api.json";
		generateJson();
	}

	// Generate and output type definitions
	final typeDefinitions = godot.Bindings.generate(jsonPath, {
		cpp: isCpp,
		nativeNameMeta: nativeMeta,
		godotVariantType: variantType
	});
	godot.Bindings.output(outputDir, typeDefinitions);

	// We done!!
	Sys.println("Done!");
}

function help() {
	Sys.println("====================================
* Godot Bindings Generator for Haxe
====================================
godot-api-generator [output-directory=godot_bindings] [json-path] 

If no \"json-path\" is given, the bindings will be generated automatically.

[Print this help message]
godot-api-generator help

[Add C++ Information]
--cpp
====================================");
}

/**
	Generates the `extension_api.json` file by asking for Godot path.
**/
function generateJson() {
	// We start!!
	Sys.println("Generating Godot bindings...");

	// Check for godot executable
	var godotVersion = "";
	var godotPath: Null<String> = Sys.getEnv("GODOT_PATH");
	if(godotPath == null) {
		godotPath = try {
			final process = new Process("godot", ["--version"]);
			if(process.exitCode(true) == 0) {
				"godot";
			} else {
				null;
			}
		} catch(e) {
			null;
		}
	}

	// Request path to godot executable if not found
	if(godotPath == null) {
		Sys.println("'godot' could not be found, please enter the path to the executable:");
		Sys.print("> ");

		while(true) {
			final path = Sys.stdin().readLine().toString();

			godotPath = if(FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
				try {
					final process = new Process(path, ["--version"]);
					if(process.exitCode(true) == 0) {
						godotVersion = process.stdout.readAll().toString();
						path;
					} else {
						null;
					}
					
				} catch(e) {
					null;
				}
			} else {
				null;
			}

			if(godotPath == null) {
				Sys.println("'" + path + "' could not be found, please try again:");
				Sys.print("> ");
			} else {
				break;
			}
		}
	}

	final versionArray = godotVersion.split(".");
	final is4_2orAbove = Std.parseInt(versionArray[0]) >= 4 && Std.parseInt(versionArray[1]) >= 2;

	final dumpType = is4_2orAbove ? "--dump-extension-api-with-docs" : "--dump-extension-api";

	// Generate `extension_api.json`
	Sys.println('>> ${godotPath} ${dumpType} --headless');
	final process = new Process(godotPath, [dumpType, "--headless"]);
	process.exitCode(true);
}
