# Godot Bindings Generator for Haxe

- For Spanish version, see [README.es.md](README.es.md)
  _Generates target-agnostic Godot bindings for Haxe._

Most Godot binding generators for Haxe are built for a specific Haxe target (Haxe/C++, Haxe/C#, etc.) The goal of this project is to create generic bindings that can work as a _base_ for other projects to avoid reinventing the wheel.

This is achieved by converting Godot's `extension_api.json` data to [`TypeDefinition`](https://api.haxe.org/haxe/macro/TypeDefinition.html) representations of the generated Haxe types. From there, one can manipulate the `TypeDefinition`s to work best for their desired Haxe target. This project will then take care of generating the `.hx` files.

If you just want un-modified, basic Godot bindings, you can do that too!

&nbsp;

## GDScript Addon Bindings

When working with Haxe in Godot, you often need to interact with GDScript-based addons (like dialogue systems, state machines, etc.). Normally this requires manually writing `@:native` metadata or using `untyped __gdscript__` calls, which is tedious and error-prone.

> NOTE: This feature requires an enviroment of Haxe → GDScript, maybe using Haxe → C++ → (godot-cpp) may work, but is untested!!! - Johanna

The `--addon` option solves this by automatically parsing `.gd` files and generating type-safe Haxe bindings for GDScript addons.

### Usage

```bash
haxelib run godot-api-generator --addon path/to/addon/ [output-dir]
```

### Example

Given a GDScript addon at `addons/my_addon/`:

```gdscript
# addons/my_addon/my_class.gd
class_name MyClass extends Node

signal health_changed(old_value: int, new_value: int)

var health: int = 100
@export var max_health: int = 100

func take_damage(amount: int) -> void:
    health -= amount
```

Running:

```bash
haxelib run godot-api-generator --addon addons/my_addon/ source/
```

Generates `source/my_addon/MyClass.hx`:

```haxe
package my_addon;

@:native("MyClass") extern class MyClass extends godot.Node {
    public function new();

    @:native("health_changed") @:signal
    public var health_changed:godot.Signal;

    public var health:Int;
    @:export public var max_health:Int;

    @:native("take_damage")
    public function take_damage(amount:Int):Void;
}
```

Now you can use the addon with full type safety:

```haxe
var myClass = new MyClass();
myClass.health_changed.connect((old, new) -> trace('Health: $old -> $new'));
myClass.take_damage(25);
```

### What Gets Parsed

- `class_name` and `extends` declarations
- `signal` declarations with arguments
- `func` methods with arguments and return types
- `var` properties with types
- `const` constants
- `@export` annotations
- Multi-line function declarations

### Options

Use with `--nativeName` to use `@:nativeName` instead of `@:native`:

```bash
haxelib run godot-api-generator --nativeName --addon addons/my_addon/
```

&nbsp;

## Installation Table of Epicness

First install via git.

```
haxelib git godot-api-generator https://github.com/SomeRanDev/Haxe-GodotBindingsGenerator
```

&nbsp;

Next you can either generate basic bindings...

```
haxelib run godot-api-generator [path-to-json] [output-dir]
```

&nbsp;

Or you can install the library and create your own generator.

| #   | What to do                                           | What to write                                                                                                  |
| --- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| 1   | Add the lib to your `.hxml` file or compile command. | <pre lang="hxml">-lib godot-api-generator</pre>                                                                |
| 2   | Get the `TypeDefinition`s and modify to your liking. | <pre lang="haxe">final haxeTypes: Array&lt;TypeDefinition&gt; = godot.Bindings.generate("path-to-json");</pre> |
| 3   | Output the bindings to a folder.                     | <pre lang="haxe">godot.Bindings.output("output-folder", haxeTypes);</pre>                                      |

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
