package;

function main() {
	var jsonPath = "extension_api.json";
	var outputDir = "godot_bindings";

	final args = Sys.args();
	switch(args) {
		case ["help", _]: {
			help();
			return;
		}
		case [_]: {
		}
		case [_jsonPath, _]: {
			jsonPath = _jsonPath;
		}
		case [_jsonPath, _outputDir, _]: {
			jsonPath = _jsonPath;
			outputDir = _outputDir;
		}
		case _: {
			Sys.println("** Invalid arguments. **\n");
			help();
			return;
		}
	}

	// try {
		final typeDefinitions = godot.Bindings.generate(jsonPath);
		trace(jsonPath, outputDir);
		trace(typeDefinitions.length);
		godot.Bindings.output(outputDir, typeDefinitions);
	// } catch(e) {
	// 	Sys.println('ERROR:\n${e.message}');
	// }
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
