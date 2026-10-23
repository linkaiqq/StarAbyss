class_name SentinelController
extends CharacterBody3D
## Motor and graybox status view; no enemy state decisions or damage calculations.

var _gravity: float = 18.0
var _corpse_elapsed: float = 0.0
## Display-only translation of the FSM state name (STORY_BIBLE §10.6 row 1). EnemyBrain keeps
## returning the English names: state_changed listeners and several tests depend on them, so
## only the floating label above the sentinel is localised here.
const STATE_LABELS: Dictionary = {
	"Idle": "巡守",
	"Chase": "寻敌",
	"Telegraph": "蓄势",
	"Attack": "出击",
	"Recover": "收势",
	"Return": "归位",
	"Hurt": "受创",
	"Dead": "已毁",
}
@onready var brain: EnemyBrain = $EnemyBrain
@onready var health: HealthComponent = $Health
@onready var feedback: CombatFeedback = $Feedback
@onready var visual: Node3D = $Visual
@onready var status_label: Label3D = $Status


func _enter_tree() -> void:
	# Configure before the shared HealthComponent's _ready initializes HP.
	var settings: SentinelSettings = (get_node("EnemyBrain") as EnemyBrain).settings
	var health_node: HealthComponent = get_node("Health") as HealthComponent
	health_node.max_health = settings.max_health
	health_node.stagger_duration = settings.stagger_duration
	health_node.post_hit_protection = 0.0


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	health.died.connect(_on_died)
	$Visual/Hitbox.hit_confirmed.connect(_on_hit_confirmed)


func _physics_process(delta: float) -> void:
	brain.tick_cooldowns(delta)
	if feedback.freeze_remaining > 0.0 and health.is_alive():
		return
	brain.physics_step(delta)
	var target_velocity: Vector3 = brain.desired_direction * brain.settings.move_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0, velocity.z).move_toward(target_velocity, brain.settings.acceleration * delta)
	if brain.movement_locked:
		horizontal = Vector3.ZERO
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = maxf(velocity.y - _gravity * delta, -40.0)
	if brain.look_direction.length_squared() > 0.001 and health.is_alive():
		var yaw: float = atan2(-brain.look_direction.x, -brain.look_direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-brain.settings.turn_speed * delta))
	var previous: Vector3 = global_position
	move_and_slide()
	brain.report_motion(Vector2(global_position.x - previous.x, global_position.z - previous.z).length(), delta)
	var state_english: String = brain.get_state_name()
	var state_label: String = STATE_LABELS.get(state_english, state_english)
	status_label.text = "%s\n%d / %d · %s" % [brain.settings.display_name, health.current_health, health.max_health, state_label]
	if not health.is_alive():
		_corpse_elapsed += delta
		if _corpse_elapsed >= brain.settings.corpse_duration:
			queue_free()


func _on_died(_info: DamageInfo) -> void:
	$Collision.set_deferred("disabled", true)
	$Hurtbox.set_deferred("monitorable", false)
	if not visual.has_node("ActorPresentation"):
		visual.rotation.z = -1.3


func _on_hit_confirmed(_target: Hurtbox, _damage: int) -> void:
	feedback.start_hit_stop(feedback.hit_stop_duration)
