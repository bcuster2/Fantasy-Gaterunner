class_name NodePool
extends RefCounted
## Reuses nodes instead of instancing/freeing during play. Released nodes stay in the tree, hidden.

var _free: Array[Node] = []
var _factory: Callable
var _parent: Node


func _init(parent: Node, factory: Callable, prewarm := 0) -> void:
	_parent = parent
	_factory = factory
	for i in prewarm:
		var node: Node = _factory.call()
		_parent.add_child(node)
		_hide(node)
		_free.append(node)


func acquire() -> Node:
	if not _free.is_empty():
		return _free.pop_back()
	var node: Node = _factory.call()
	_parent.add_child(node)
	return node


func release(node: Node) -> void:
	_hide(node)
	_free.append(node)


func _hide(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = false
