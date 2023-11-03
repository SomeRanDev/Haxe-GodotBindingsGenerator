# Godot Bindings Generator for Haxe

_Generates target-agnostic Godot bindings for Haxe._

Most Godot binding generators for Haxe are built for a specific Haxe target (Haxe/C++, Haxe/C#, etc.) The goal of this project is to create generic bindings that can work as a *base* for other projects to avoid reinventing the wheel.

This is achieved by converting Godot's `extension_api.json` data to [`TypeDefinition`](https://api.haxe.org/haxe/macro/TypeDefinition.html) representations of the generated Haxe types. From there, one can manipulate the `TypeDefinition`s to work best for their desired Haxe target. This project will then take care of generating the `.hx` files.

If you just want un-modified, basic Godot bindings, you can do that too!

&nbsp;

## Installation Table of Epicness
| # | What to do | What to write |
| - | ------ | ------ |
| 1 | Install via haxelib. | <pre>haxelib install godot-api-generator</pre> |
| 2 | Add the lib to your `.hxml` file or compile command. | <pre lang="hxml">-lib godot-api-generator</pre> |
| 3a | Generate bindings using `extension_api.json`. | <pre>haxelib run godot-api-generator [path-to-json] [output-dir]</pre> |
| 3b | OR use in your own generator. | <pre lang="haxe">final haxeTypes: Array&lt;TypeDefinition&gt; = godot.Bindings.generate("path-to-json");</pre> |
