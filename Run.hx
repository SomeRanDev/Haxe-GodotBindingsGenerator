package;

import sys.FileSystem;
import sys.io.Process;
import godot.gdscript.GDScriptParser;
import godot.gdscript.GDScriptBindings;

using StringTools;

function main() {
	var jsonPath = null;
	var outputDir = null;
	var addonPath:Null<String> = null;

	final args = Sys.args();

	// Show help if requested
	if (args.contains("help") || args.contains("--help") || args.contains("-h")) {
		help();
		return;
	}

	// Print header
	Sys.println("");
	Sys.println("╔════════════════════════════════════════════════════╗");
	Sys.println("║     Godot Bindings Generator for Haxe              ║");
	Sys.println("║     https://github.com/SomeRanDev/                 ║");
	Sys.println("║            Haxe-GodotBindingsGenerator             ║");
	Sys.println("╚════════════════════════════════════════════════════╝");
	Sys.println("");

	// Parse flags
	Sys.println("[1/4] Parsing command-line options...");

	// Check for --cpp
	final isCpp = if (args.contains("--cpp")) {
		args.remove("--cpp");
		true;
	} else false;

	// Check for --nativeName
	final nativeMeta = if (args.contains("--nativeName")) {
		args.remove("--nativeName");
		":nativeName";
	} else ":native";

	// Check for --godotVariantType
	final variantType = if (args.contains("--godotVariantType")) {
		args.remove("--godotVariantType");
		macro :GodotVariant;
	} else macro :Dynamic;

	// Check for --useGodotTypedArray
	final typedArrayType = if (args.contains("--useGodotTypedArray")) {
		args.remove("--useGodotTypedArray");
		{pack: [], name: "GodotTypedArray"}
	} else ({pack: [], name: "Array"});

	// Check for --addon <path>
	if (args.contains("--addon")) {
		final idx = args.indexOf("--addon");
		args.remove("--addon");
		if (idx < args.length) {
			addonPath = args[idx];
			args.splice(idx, 1);
		}
	}

	final cwd = switch (args) {
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
				Sys.println("");
				Sys.println("ERROR: Invalid arguments provided.");
				Sys.println("");
				help();
				return;
			}
	}

	// Print active configuration
	Sys.println("");
	Sys.println("  Active Configuration:");
	Sys.println("  ─────────────────────────────────────────────────");
	Sys.println('  • C++ mode:            ${isCpp ? "ENABLED" : "disabled"}');
	Sys.println('  • Native meta:         ${nativeMeta}');
	Sys.println('  • Variant type:        ${isCpp ? "GodotVariant" : "Dynamic"}');
	Sys.println('  • TypedArray type:     ${typedArrayType.name}');
	if (addonPath != null) {
		Sys.println('  • Addon mode:          ENABLED');
		Sys.println('  • Addon path:          ${addonPath}');
	}
	Sys.println("  ─────────────────────────────────────────────────");
	Sys.println("");

	// Ensure we use current directory of haxelib run call
	if (cwd != null) {
		Sys.setCwd(cwd);
	}

	// Check output directory
	if (outputDir == null) {
		outputDir = "godot";
		Sys.println('  → Output directory not specified, using default: "$outputDir/"');
	} else {
		Sys.println('  → Output directory: "$outputDir/"');
	}

	// ═══════════════════════════════════════════════════════════════════
	// ADDON MODE: Generate bindings from GDScript files
	// ═══════════════════════════════════════════════════════════════════
	if (addonPath != null) {
		generateAddonBindings(addonPath, outputDir, nativeMeta);
		return;
	}

	// ═══════════════════════════════════════════════════════════════════
	// GODOT API MODE: Generate bindings from extension_api.json
	// ═══════════════════════════════════════════════════════════════════

	// Check json path
	Sys.println("");
	Sys.println("[2/4] Locating extension_api.json...");

	final shouldGenerate = if (jsonPath == null && !FileSystem.exists("extension_api.json")) {
		Sys.println("  → No extension_api.json found in current directory.");
		Sys.println("  → Will generate it automatically using Godot.");
		true;
	} else {
		if (jsonPath == null) {
			jsonPath = "extension_api.json";
		}
		Sys.println('  → Using: "$jsonPath"');
		false;
	}

	// Generate extension_api.json if needed
	if (shouldGenerate) {
		Sys.println("");
		jsonPath = "extension_api.json";
		generateJson();
	}

	if (jsonPath == null) {
		Sys.println("");
		Sys.println("ERROR: extension_api.json path not found. Aborting.");
		Sys.println("");
		Sys.println("HINT: You can generate this file manually by running:");
		Sys.println("      godot --dump-extension-api-with-docs --headless");
		return;
	}

	// Generate and output type definitions
	Sys.println("");
	Sys.println("[3/4] Generating Haxe type definitions...");
	Sys.println('  → Reading API from: "$jsonPath"');

	final typeDefinitions = godot.Bindings.generate(jsonPath, {
		cpp: isCpp,
		nativeNameMeta: nativeMeta,
		godotVariantType: variantType,
		typedArrayType: typedArrayType
	});

	Sys.println('  → Generated ${typeDefinitions.length} type definitions.');

	Sys.println("");
	Sys.println("[4/4] Writing output files...");
	Sys.println('  → Writing to: "$outputDir/"');

	godot.Bindings.output(outputDir, typeDefinitions);

	Sys.println('  → Wrote ${typeDefinitions.length} files.');

	// Success!
	Sys.println("");
	Sys.println("╔════════════════════════════════════════════════════╗");
	Sys.println("║  ✓ Generation complete!                            ║");
	Sys.println("╚════════════════════════════════════════════════════╝");
	Sys.println("");
	Sys.println('Add "-cp $outputDir" to your .hxml file to use the bindings.');
	Sys.println("");
}

/**
	Generates Haxe bindings from GDScript addon files.
**/
function generateAddonBindings(addonPath:String, outputDir:String, nativeMeta:String) {
	Sys.println("");
	Sys.println("[2/3] Scanning GDScript files...");

	if (!FileSystem.exists(addonPath)) {
		Sys.println("");
		Sys.println('  ERROR: Addon path "$addonPath" does not exist.');
		return;
	}

	Sys.println('  → Scanning: "$addonPath"');

	final classes = GDScriptParser.parseDirectory(addonPath);

	if (classes.length == 0) {
		Sys.println("");
		Sys.println("  WARNING: No GDScript classes with 'class_name' found.");
		Sys.println("  → Only scripts with 'class_name' declaration are processed.");
		Sys.println("  → Anonymous scripts (without class_name) are skipped.");
		return;
	}

	Sys.println('  → Found ${classes.length} class(es):');
	for (cls in classes) {
		final methodCount = cls.methods.length;
		final propCount = cls.properties.length;
		final signalCount = cls.signals.length;
		Sys.println('      • ${cls.name} (${methodCount} methods, ${propCount} properties, ${signalCount} signals)');
	}

	Sys.println("");
	Sys.println("[3/3] Generating Haxe type definitions...");

	// Set the native name metadata
	GDScriptBindings.nativeNameMeta = nativeMeta;

	// Determine package name from addon path (use last folder name)
	final normalizedPath = addonPath.replace("\\", "/");
	final pathParts = normalizedPath.split("/").filter(p -> p.length > 0);
	final basePackage = if (pathParts.length > 0) {
		// Use the last folder name as package, sanitized
		final lastPart = pathParts[pathParts.length - 1];
		StringTools.replace(lastPart, "-", "_").toLowerCase();
	} else {
		"addon";
	};

	Sys.println('  → Package: $basePackage');

	final typeDefinitions = GDScriptBindings.generateFromClasses(classes, basePackage);

	Sys.println('  → Generated ${typeDefinitions.length} type definition(s).');

	Sys.println('  → Writing to: "$outputDir/$basePackage/"');

	godot.Bindings.output(outputDir, typeDefinitions);

	Sys.println('  → Wrote ${typeDefinitions.length} file(s).');

	// Success!
	Sys.println("");
	Sys.println("╔════════════════════════════════════════════════════╗");
	Sys.println("║  ✓ Addon bindings generated!                       ║");
	Sys.println("╚════════════════════════════════════════════════════╝");
	Sys.println("");
	Sys.println('Add "-cp $outputDir" to your .hxml file to use the addon bindings.');
	Sys.println('Import classes with: import $basePackage.ClassName;');
	Sys.println("");
}

function help() {
	Sys.println("
╔════════════════════════════════════════════════════════════════════════╗
║                  Godot Bindings Generator for Haxe                     ║
╚════════════════════════════════════════════════════════════════════════╝

USAGE:
  haxelib run godot-api-generator [OPTIONS] [OUTPUT_DIR] [JSON_PATH]

ARGUMENTS:
  OUTPUT_DIR    Directory where Haxe files will be generated.
                Default: \"godot/\"

  JSON_PATH     Path to Godot's extension_api.json file.
                If not provided and file doesn't exist, it will be
                generated automatically (requires Godot in PATH or
                GODOT_PATH environment variable).

OPTIONS:
  --cpp                  Enable C++ mode. Adds @:include metadata for
                         godot-cpp headers and wraps types with Ref<T>
                         and pointer types where appropriate.

  --nativeName           Use @:nativeName instead of @:native for
                         field renaming metadata.

  --godotVariantType     Use 'GodotVariant' type instead of 'Dynamic'
                         for Godot's Variant type.

  --useGodotTypedArray   Use 'GodotTypedArray<T>' instead of 'Array<T>'
                         for typed arrays.

  --addon <PATH>         Generate Haxe bindings from GDScript addon files.
                         Parses .gd files in the given directory and generates
                         type definitions for classes with 'class_name'.
                         Extracts: signals, methods, properties, constants.

  help, --help, -h       Show this help message.

EXAMPLES:
  # Basic usage (auto-detect extension_api.json)
  haxelib run godot-api-generator

  # Specify output directory
  haxelib run godot-api-generator my_bindings/

  # Specify both output and json path
  haxelib run godot-api-generator bindings/ path/to/extension_api.json

  # Enable C++ mode
  haxelib run godot-api-generator --cpp

  # Full example with all options
  haxelib run godot-api-generator --cpp --nativeName --godotVariantType bindings/

  # Generate bindings from a GDScript addon
  haxelib run godot-api-generator --addon addons/my_addon/ addon_bindings/

  # Generate from addon with default output directory
  haxelib run godot-api-generator --addon path/to/addon/

ENVIRONMENT VARIABLES:
  GODOT_PATH    Path to Godot executable (used when generating
                extension_api.json automatically).

MORE INFO:
  https://github.com/SomeRanDev/Haxe-GodotBindingsGenerator
");
}

/**
	Generates the `extension_api.json` file by locating or asking for Godot path.
**/
function generateJson() {
	Sys.println("[2/4] Auto-generating extension_api.json...");

	// Check for godot executable
	var godotVersion = "";
	var godotPath:Null<String> = Sys.getEnv("GODOT_PATH");

	if (godotPath != null) {
		Sys.println('  → Found GODOT_PATH environment variable: "$godotPath"');
	}

	if (godotPath == null) {
		Sys.println("  → Checking if 'godot' is available in PATH...");
		godotPath = try {
			final process = new Process("godot", ["--version"]);
			if (process.exitCode(true) == 0) {
				godotVersion = process.stdout.readAll().toString().split("\n")[0];
				Sys.println('  → Found Godot in PATH (version: $godotVersion)');
				"godot";
			} else {
				null;
			}
		} catch (e) {
			null;
		}
	}

	// Request path to godot executable if not found
	if (godotPath == null) {
		Sys.println("");
		Sys.println("  ┌─────────────────────────────────────────────────────────┐");
		Sys.println("  │  Godot executable not found!                            │");
		Sys.println("  │                                                         │");
		Sys.println("  │  Please enter the full path to your Godot executable:   │");
		Sys.println("  │  (e.g., C:\\Godot\\godot.exe or /usr/bin/godot)           │");
		Sys.println("  └─────────────────────────────────────────────────────────┘");
		Sys.println("");
		Sys.print("  Path> ");

		while (true) {
			final path = Sys.stdin().readLine().toString();

			if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
				godotPath = path;
				Sys.println('  → Using: "$path"');
				Sys.println("  → Skipping version check (assuming Godot 4.2+)");
				break;
			} else {
				Sys.println('  → ERROR: Could not find "$path"');
				Sys.println("  → Please try again:");
				Sys.print("  Path> ");
			}
		}
	}

	// Determine which dump command to use based on version
	// Default to newer format (4.2+) since most users will have recent Godot
	final versionArray = godotVersion.split(".");
	final majorVersion = Std.parseInt(versionArray[0]) ?? 4;
	final minorVersion = Std.parseInt(versionArray[1]) ?? 2;
	final is4_2orAbove = majorVersion >= 4 && minorVersion >= 2;

	// Always use --dump-extension-api-with-docs for 4.2+, otherwise fall back
	final dumpType = is4_2orAbove ? "--dump-extension-api-with-docs" : "--dump-extension-api";

	Sys.println("");
	Sys.println("  → Running Godot to generate extension_api.json...");
	Sys.println('  → Command: $godotPath $dumpType --headless');
	Sys.println("");
	Sys.println("  (This may take a few seconds...)");
	Sys.println("");

	// Generate `extension_api.json` using Sys.command for better compatibility
	final exitCode = Sys.command('"$godotPath" $dumpType --headless');

	if (exitCode == 0 && FileSystem.exists("extension_api.json")) {
		Sys.println("  → extension_api.json generated successfully!");
	} else {
		Sys.println("");
		Sys.println("  ┌─────────────────────────────────────────────────────────┐");
		Sys.println("  │  WARNING: Godot may not have generated the file.        │");
		Sys.println("  │                                                         │");
		Sys.println("  │  If extension_api.json was not created, run manually:   │");
		Sys.println("  │    godot --dump-extension-api-with-docs --headless      │");
		Sys.println("  └─────────────────────────────────────────────────────────┘");
	}
}
