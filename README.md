# Godot Bindings Generator for Haxe

_Generates target-agnostic Godot bindings for Haxe._

Most Godot binding generators for Haxe are built for a specific Haxe target (Haxe/C++, Haxe/C#, etc.) The goal of this project is to create generic bindings that can work as a *base* for other projects to avoid reinventing the wheel.

This is achieved by converting Godot's `extension_api.json` data to [`TypeDefinition`](https://api.haxe.org/haxe/macro/TypeDefinition.html) representations of the generated Haxe types. From there, one can manipulate the `TypeDefinition`s to work best for their desired Haxe target. This project will then take care of generating the `.hx` files.

If you just want un-modified, basic Godot bindings, you can do that too!

&nbsp;

## Installation Table of Epicness

First intall via haxelib.
```
haxelib install godot-api-generator
```

&nbsp;

Next you can either generate basic bindings...
```
haxelib run godot-api-generator [path-to-json] [output-dir]
```

&nbsp;

Or you can install the library and create your own generator.

| # | What to do | What to write |
| - | ------ | ------ |
| 1 | Add the lib to your `.hxml` file or compile command. | <pre lang="hxml">-lib godot-api-generator</pre> |
| 2 | Get the `TypeDefinition`s and modify to your liking. | <pre lang="haxe">final haxeTypes: Array&lt;TypeDefinition&gt; = godot.Bindings.generate("path-to-json");</pre> |
| 3 | Output the bindings to a folder. | <pre lang="haxe">godot.Bindings.output("output-folder", haxeTypes);</pre> |

&nbsp;

## Godot-CPP Data

If you wish to include additional [`godot-cpp`](https://github.com/godotengine/godot-cpp) binding information such as `@:include`s and `@:native`s, add the `--cpp` flag or `cpp` option.

#### Command Line
```
haxelib run godot-api-generator [path-to-json] [output-dir] --cpp
```

#### Haxe
```haxe
godot.Bindings.generate("path-to-json", { cpp: true });
```
