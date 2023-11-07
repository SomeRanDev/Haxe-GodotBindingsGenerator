package godot.bindings;

/**
	Quick helper to force null-checker to comply.
**/
extern inline function trustMe<T>(v: Null<T>): T {
	if(v == null) {
		throw "I TRUSTED YOU T_T";
	}
	return v;
}
