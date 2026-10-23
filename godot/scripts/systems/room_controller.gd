class_name RoomController
extends Node3D
## Owns one fixed encounter, its enemies and exit. No blessing or run-state decisions.

signal enemy_defeated(info: DamageInfo)
signal enemies_changed(remaining: int, total: int)
signal cleared
signal exit_requested
signal boss_defeated(info: DamageInfo)

const SENTINEL: PackedScene = preload("res://scenes/enemies/sentinel.tscn")
const GUARDIAN: PackedScene = preload("res://scenes/boss/core_guardian.tscn")
var definition: RoomDefinition
var player: PlayerController
var run_seed: int = 0
var boss: SentinelController
var is_cleared: bool = false
var enemies: Array[SentinelController] = []
var _living: Dictionary[HealthComponent, bool] = {}
@onready var gate: RoomGate = $ExitGate
@onready var coordinator: AttackCoordinator = $AttackCoordinator


func _ready() -> void:
	gate.configure(player)
	gate.crossed.connect(func() -> void: exit_requested.emit())
	$NavigationRegion3D/Geometry/NorthLabel.text = definition.display_name
	$NavigationRegion3D/Geometry/NorthLabel.position.y = 8.2
	if definition.boss_room:
		$NavigationRegion3D.navigation_mesh = load("res://resources/navigation/guardian_arena_navmesh.tres") as NavigationMesh
		boss = GUARDIAN.instantiate() as SentinelController
		var brain: GuardianBrain = boss.get_node("EnemyBrain") as GuardianBrain
		brain.target_path = player.get_path()
		brain.coordinator_path = coordinator.get_path()
		brain.initialize_seed(run_seed)
		boss.position = definition.boss_spawn
		$Enemies.add_child(boss)
		boss.health.died.connect(_on_boss_died)
		gate.caption.text = "晶核封印 · 旧誓仍守此门"
		return
	if definition.boss_staging:
		gate.caption.text = "晶核封印 · 本次试炼终点"
		return
	for location: Vector3 in definition.enemy_spawns:
		var sentinel: SentinelController = SENTINEL.instantiate() as SentinelController
		var brain: EnemyBrain = sentinel.get_node("EnemyBrain") as EnemyBrain
		brain.target_path = player.get_path()
		brain.coordinator_path = coordinator.get_path()
		sentinel.position = location
		$Enemies.add_child(sentinel)
		enemies.append(sentinel)
		_living[sentinel.health] = true
		sentinel.health.died.connect(_on_enemy_died.bind(sentinel.health))
	enemies_changed.emit(_living.size(), enemies.size())


func _on_enemy_died(info: DamageInfo, health: HealthComponent) -> void:
	if not _living.has(health):
		return
	_living.erase(health)
	enemy_defeated.emit(info)
	enemies_changed.emit(_living.size(), enemies.size())
	if _living.is_empty() and not is_cleared:
		is_cleared = true
		gate.set_open(true)
		cleared.emit()


func get_living_enemy_count() -> int:
	return _living.size() + (1 if is_instance_valid(boss) and boss.health.is_alive() else 0)


func _on_boss_died(info: DamageInfo) -> void:
	if not is_cleared:
		is_cleared = true
		gate.set_open(true)
		gate.caption.text = "晶核已稳定 · 黎明已至"
		boss_defeated.emit(info)
