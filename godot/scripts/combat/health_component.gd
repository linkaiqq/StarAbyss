class_name HealthComponent
extends Node
## HP, stagger and independent invulnerability reasons. Shared by player and targets.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int, info: DamageInfo)
signal died(info: DamageInfo)
## A contact that landed while invulnerable. Emitted instead of damaged(); the return value
## and every downstream rule (stagger, post-hit protection) stay exactly as before, so this
## is purely a confirmation channel for feedback (GAMEPLAY_DESIGN G-04A).
signal blocked(info: DamageInfo)

@export_range(1, 10000, 1) var max_health: int = 100
@export_range(0.0, 10.0, 0.05) var damage_taken_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.01) var post_hit_protection: float = 0.5
@export_range(0.0, 3.0, 0.01) var stagger_duration: float = 0.25

var current_health: int = 0
var protection_remaining: float = 0.0
var stagger_remaining: float = 0.0
var _invulnerability_reasons: Dictionary[StringName, bool] = {}
var _resolved_ids: Dictionary[int, bool] = {}
var _resolved_order: Array[int] = []


func _ready() -> void:
	process_physics_priority = -30
	current_health = max_health
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	protection_remaining = maxf(0.0, protection_remaining - delta)
	stagger_remaining = maxf(0.0, stagger_remaining - delta)


func is_alive() -> bool:
	return current_health > 0


func is_invulnerable() -> bool:
	return protection_remaining > 0.0 or not _invulnerability_reasons.is_empty()


func has_invulnerability_reason(reason: StringName) -> bool:
	# Lets feedback distinguish a deliberate dodge i-frame from post-hit protection.
	return _invulnerability_reasons.has(reason)


func set_invulnerable(reason: StringName, enabled: bool) -> void:
	if enabled:
		_invulnerability_reasons[reason] = true
	else:
		_invulnerability_reasons.erase(reason)


func receive_damage(amount: int, info: DamageInfo) -> int:
	if not is_alive() or info == null or _resolved_ids.has(info.attack_id):
		return 0
	# Remember even blocked contacts: one attack must never hit again after i-frames expire.
	_resolved_ids[info.attack_id] = true
	_resolved_order.append(info.attack_id)
	if _resolved_order.size() > 256:
		_resolved_ids.erase(_resolved_order.pop_front())
	if is_invulnerable() or amount <= 0:
		# Feedback only: the block itself is already resolved (attack id recorded above),
		# so the shield behaves identically with or without listeners. G-04A.
		if amount > 0 and is_invulnerable():
			blocked.emit(info)
		return 0
	var applied: int = mini(current_health, amount)
	current_health -= applied
	protection_remaining = post_hit_protection
	stagger_remaining = stagger_duration
	health_changed.emit(current_health, max_health)
	damaged.emit(applied, info)
	if current_health == 0:
		died.emit(info)
	return applied


func heal(amount: int) -> int:
	if not is_alive() or amount <= 0:
		return 0
	var restored: int = mini(amount, max_health - current_health)
	current_health += restored
	if restored > 0:
		health_changed.emit(current_health, max_health)
	return restored
