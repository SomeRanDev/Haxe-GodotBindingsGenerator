package;

function main() {
	var jsonPath = "extension_api.json";
	var outputDir = "godot_bindings";

	final args = Sys.args();
	final cwd = switch(args) {
		case ["help", _]: {
			help();
			return;
		}
		case [cwd]: {
			cwd;
		}
		case [_jsonPath, cwd]: {
			jsonPath = _jsonPath;
			cwd;
		}
		case [_jsonPath, _outputDir, cwd]: {
			jsonPath = _jsonPath;
			outputDir = _outputDir;
			cwd;
		}
		case _: {
			Sys.println("** Invalid arguments. **\n");
			help();
			return;
		}
	}

	Sys.setCwd(cwd);

	try {
		final typeDefinitions = godot.Bindings.generate(jsonPath);
		godot.Bindings.output(outputDir, typeDefinitions);
	} catch(e) {
		Sys.println('ERROR:\n${e.message}');
	}
}

function help() {
	Sys.println("====================================
* Godot Bindings Generator for Haxe
====================================
godot-api-generator [json-path] [output-directory]

[Default arguments]
godot-api-generator ./extension_api.json ./godot_bindings

[Print this help message]
godot-api-generator help
====================================");
}
