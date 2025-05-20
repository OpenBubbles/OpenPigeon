extends Panel

var text_anim: Timer
var label: RichTextLabel

var anim_stages: Array[String] = [
	"[center]WAITING FOR OPPONENT.[/center]",
	"[center]WAITING FOR OPPONENT..[/center]",
	"[center]WAITING FOR OPPONENT...[/center]"
]

var curr_anim_stage = 0

func _ready():
	label = get_child(0)
	text_anim = Timer.new()
	text_anim.wait_time = 0.5
	text_anim.one_shot = false
	text_anim.timeout.connect(animate_text)
	add_child(text_anim)
	text_anim.start()
	
func animate_text():
	label.text = anim_stages[curr_anim_stage]
	curr_anim_stage = curr_anim_stage + 1 if curr_anim_stage < 2 else 0
