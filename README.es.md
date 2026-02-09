# Generador de Bindings de Godot para Haxe

_Genera bindings de Godot agnósticos al target para Haxe._

La mayoría de los generadores de bindings de Godot para Haxe están diseñados para un target específico (Haxe/C++, Haxe/C#, etc.). El objetivo de este proyecto es crear bindings genéricos que puedan servir como _base_ para otros proyectos y evitar reinventar la rueda.

Esto se logra convirtiendo los datos de `extension_api.json` de Godot a representaciones [`TypeDefinition`](https://api.haxe.org/haxe/macro/TypeDefinition.html) de los tipos Haxe generados. Desde ahí, puedes manipular los `TypeDefinition`s para que funcionen mejor con tu target de Haxe deseado. Este proyecto se encargará de generar los archivos `.hx`.

¡Si solo quieres bindings básicos de Godot sin modificar, también puedes hacerlo!

&nbsp;

## Bindings para Addons de GDScript

Cuando trabajas con Haxe en Godot, frecuentemente necesitas interactuar con addons basados en GDScript (como sistemas de diálogos, máquinas de estado, etc.). Normalmente esto requiere escribir metadata `@:native` manualmente o usar llamadas `untyped __gdscript__`, lo cual es tedioso y propenso a errores.

> NOTA: Esta funcionalidad requiere un entorno de Haxe → GDScript. Podría funcionar con Haxe → C++ → (godot-cpp), ¡pero no está probado! - Johanna

La opción `--addon` resuelve esto parseando automáticamente archivos `.gd` y generando bindings de Haxe con tipado seguro para addons de GDScript.

### Uso

```bash
haxelib run godot-api-generator --addon ruta/al/addon/ [directorio-salida]
```

### Ejemplo

Dado un addon de GDScript en `addons/mi_addon/`:

```gdscript
# addons/mi_addon/mi_clase.gd
class_name MiClase extends Node

signal vida_cambio(valor_anterior: int, valor_nuevo: int)

var vida: int = 100
@export var vida_maxima: int = 100

func recibir_danio(cantidad: int) -> void:
    vida -= cantidad
```

Ejecutando:

```bash
haxelib run godot-api-generator --addon addons/mi_addon/ source/
```

Genera `source/mi_addon/MiClase.hx`:

```haxe
package mi_addon;

@:native("MiClase") extern class MiClase extends godot.Node {
    public function new();

    @:native("vida_cambio") @:signal
    public var vida_cambio:godot.Signal;

    public var vida:Int;
    @:export public var vida_maxima:Int;

    @:native("recibir_danio")
    public function recibir_danio(cantidad:Int):Void;
}
```

Ahora puedes usar el addon con tipado seguro:

```haxe
var miClase = new MiClase();
miClase.vida_cambio.connect((anterior, nuevo) -> trace('Vida: $anterior -> $nuevo'));
miClase.recibir_danio(25);
```

### Qué se Parsea

- Declaraciones `class_name` y `extends`
- Declaraciones `signal` con argumentos
- Métodos `func` con argumentos y tipos de retorno
- Propiedades `var` con tipos
- Constantes `const`
- Anotaciones `@export`
- Declaraciones de funciones multi-línea

### Opciones

Usa con `--nativeName` para usar `@:nativeName` en vez de `@:native`:

```bash
haxelib run godot-api-generator --nativeName --addon addons/mi_addon/
```

&nbsp;

## Tabla de Instalación very Epica muy wind ding gaster

Primero instala via git.

```
haxelib git godot-api-generator https://github.com/SomeRanDev/Haxe-GodotBindingsGenerator
```

&nbsp;

Luego puedes generar bindings básicos...

```
haxelib run godot-api-generator [ruta-al-json] [directorio-salida]
```

&nbsp;

O puedes instalar la librería y crear tu propio generador.

| #   | Qué hacer                                                    | Qué escribir                                                                                                   |
| --- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| 1   | Agrega la lib a tu archivo `.hxml` o comando de compilación. | <pre lang="hxml">-lib godot-api-generator</pre>                                                                |
| 2   | Obtén los `TypeDefinition`s y modifícalos a tu gusto.        | <pre lang="haxe">final haxeTypes: Array&lt;TypeDefinition&gt; = godot.Bindings.generate("ruta-al-json");</pre> |
| 3   | Genera los bindings a una carpeta.                           | <pre lang="haxe">godot.Bindings.output("carpeta-salida", haxeTypes);</pre>                                     |

&nbsp;

## Datos de Godot-CPP

Si deseas incluir información adicional de bindings de [`godot-cpp`](https://github.com/godotengine/godot-cpp) como `@:include`s y `@:native`s, agrega la flag `--cpp` o la opción `cpp`.

#### Línea de Comandos

```
haxelib run godot-api-generator [ruta-al-json] [directorio-salida] --cpp
```

#### Haxe

```haxe
godot.Bindings.generate("ruta-al-json", { cpp: true });
```
