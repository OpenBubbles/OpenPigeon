extends Panel
class_name ArcheryScoreBox

@export var set_label: RichTextLabel
@export var score_label: RichTextLabel
@export var you_set_wins_label: RichTextLabel
@export var opp_set_wins_label: RichTextLabel

var set_num: int = 1

var you_score: int = 0
var opp_score: int = 0

var you_set_wins: int = 0
var opp_set_wins: int = 0 

func update_set_number(set_num: int):
	self.set_num = set_num
	set_label.text = str("[center][b]SET ",set_num,"[/b][/center]")

func set_you_score(score: int):
	you_score = score
	_update_score_label()
	
func set_opp_score(score: int):
	opp_score = score
	_update_score_label()
	
func set_opp_set_wins(score: int):
	opp_set_wins = score
	opp_set_wins_label.text = str("[center]",score,"[center]")
	if score > 0:
		opp_set_wins_label.get_parent().visible = true
	else:
		opp_set_wins_label.get_parent().visible = false
		
func set_you_set_wins(score: int):
	you_set_wins = score
	you_set_wins_label.text = str("[center]",score,"[center]")
	if score > 0:
		you_set_wins_label.get_parent().visible = true
	else:
		you_set_wins_label.get_parent().visible = false

func _update_score_label():
	score_label.text = str("[center]",you_score,"[b] - [/b]",opp_score,"[/center]")
