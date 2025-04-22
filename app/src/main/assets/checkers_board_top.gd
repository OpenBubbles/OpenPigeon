extends Sprite2D
class_name CheckersBoardTop

var black_king_texture = preload("res://checker_black_king.png")
var red_king_texture = preload("res://checker_red_king.png")
var black_normal_texture = preload("res://checker_black.png")
var red_normal_texture = preload("res://checker_red.png")

var replay = null
var redPiece: Sprite2D

var boardHighlight: BoardHighlight
var highlights: Array[BoardHighlight]

var clicked_piece: Sprite2D

var moves: Array[Vector2]
var has_moved: bool = false
var prev_moves: Array[Vector2]
var prev_jumps: Array[Sprite2D]

var has_connected = false

var player = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("App plugin is available")
		if not has_connected:
			appPlugin.connect("set_replay", _set_replay)
			has_connected = true
	else:
		print("App plugin is not available")
		if replay == null or player == null:
			_set_replay("player:1,board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,0,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,2,0,0,0,0,1,0,0,0,1,1,0,0,0,1,0,0,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,0,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,2,0,0,0,0,1,0,1,0,1,1,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0")
	
	if replay == null or player == null:
		return
		
	get_node("P" + str(player) + "Label").set_text("You")
		
	redPiece = get_node("CheckerPieceRed")
	var blackPiece: Sprite2D = get_node("CheckerPieceBlack")
	boardHighlight = get_node("BoardHighlight")
	
	var prevBoard = null
	var nextBoard = null
	
	var replayMoves = Array()
	
	for elem in replay.split('|'):
		var spl = elem.split(':')
		if spl[0] == 'move' || spl[0] == 'attack':
			replayMoves.append(elem)
		if spl[0] == 'board':
			if prevBoard == null:
				prevBoard = spl[1].split(',')
			else:
				nextBoard = spl[1].split(',')
	
	# WTF gamepigeon, sometimes you just don't send the moves????
	if len(replayMoves) == 0 && prevBoard != nextBoard:
		prevBoard = nextBoard
	
	for y in range(0, 8):
		for x in range(0, 8):
			var val = prevBoard[(7 - y) * 8 + x];
			var newPiece: Sprite2D = null;
			if val == "2":
				newPiece = blackPiece.duplicate()
			elif val == "1":
				newPiece = redPiece.duplicate();
				
			if newPiece != null:
				newPiece.position = Vector2(redPiece.position.x + (135 * x), redPiece.position.y + (135 * y));
				newPiece.name = str(x) + "," + str(7-y)
				newPiece.visible = true
				add_child(newPiece)
				print(newPiece.name, " : ", newPiece.position)
				
	if len(replayMoves) > 0:
		var firstMovePos = replayMoves[0].split(':')[1].split(',')
		var movedPiece = get_node_or_null(firstMovePos[0] + ',' + firstMovePos[1])
		if movedPiece != null:
			var tween = movedPiece.get_tree().create_tween()
			for i in range(len(replayMoves)):
				var moveType = replayMoves[i].split(':')[0]
				var movePos = replayMoves[i].split(':')[1].split(',')
				var newPos = Vector2(redPiece.position.x + (135 * int(movePos[2])), redPiece.position.y + (135 * (7 - int(movePos[3]))))
				tween.tween_property(movedPiece, "position", newPos, 0.5).set_trans(Tween.TRANS_SINE)
				movedPiece.name = movePos[2] + "," + movePos[3];
				var color = get_piece_color(movedPiece)
				if (color == "black" and int(movePos[3]) == 7) or (color == "red" and int(movePos[3]) == 0):
					tween.tween_callback(set_checker_king.bind(movedPiece, color))
				if moveType == "attack":
					jump_piece(int(movePos[0]), int(movePos[1]), int(movePos[2]), int(movePos[3]), i*0.5)

func _set_replay(new_replay: String):
	#player = int(new_replay.substr(7, 1))
	#replay = new_replay.substr(9)
	player = 2
	replay = "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,2,0,2,0,2,0,2,2,0,2,0,0,0,0,0,0,0,0,1,0,1,0,1,1,0,0,0,1,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0|move:5,4,6,3|board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,2,0,2,0,2,0,2,2,0,2,0,0,0,1,0,0,0,0,1,0,0,0,1,1,0,0,0,1,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0"
	_ready()

func export_replay() -> String:
	var board: Array[String]
	for i in range(0, 64):
		board.append("0")
	
	for y in range(0, 8):
		for x in range(0, 8):
			var piece: Sprite2D = get_node_or_null(str(x) + "," + str(7-y))
			if piece != null:
				var color = get_piece_color(piece)
				if color == "red":
					if is_checker_king(piece):
						board[(7 - y) * 8 + x] = "3"
					else:
						board[(7 - y) * 8 + x] = "1"
				elif color == "black":
					if is_checker_king(piece):
						board[(7 - y) * 8 + x] = "4"
					else:
						board[(7 - y) * 8 + x] = "2"
	
	var boardStr: String
	for val in board:
		boardStr += val + ","
	
	var move_str = "|"
	for i in range(0, len(prev_moves), 2):
		var moveType = "move"
		if abs(prev_moves[i].x - prev_moves[i+1].x) > 1:
			moveType = "attack"
		move_str += moveType + ":" + str(prev_moves[i].x) + "," + str(prev_moves[i].y) + "," + str(prev_moves[i+1].x) + "," + str(prev_moves[i+1].y) + "|"
	
	return replay.split('|')[-1] + move_str + "board:" + boardStr.substr(0, boardStr.length()-1)
	
func jump_piece(prevX: int, prevY: int, newX: int, newY: int, anim_delay: float = 0.0):
	var x_step = 1 if newX > prevX else -1
	var y_step = 1 if newY > prevY else -1
	var jumpedPiece: Sprite2D = get_node_or_null(str(prevX + x_step) + "," + str(prevY + y_step))
	if jumpedPiece != null:
		var tween = jumpedPiece.get_tree().create_tween()
		var modulate_color = jumpedPiece.self_modulate
		modulate_color.a = 0.0
		tween.tween_interval(anim_delay)
		tween.tween_property(jumpedPiece, "self_modulate", modulate_color, 0.5).set_trans(Tween.TRANS_LINEAR)
		jumpedPiece.name = str(prevX + x_step) + "," + str(prevY + y_step) + "_jumped"
		prev_jumps.append(jumpedPiece)

func move_piece(piece: Sprite2D, x: int, y: int, anim_delay: float = 0.0):
	var newPos = Vector2(redPiece.position.x + (135 * x), redPiece.position.y + (135 * y))
	var tween = piece.get_tree().create_tween()
	tween.tween_interval(anim_delay)
	tween.tween_property(piece, "position", newPos, 0.5).set_trans(Tween.TRANS_SINE)
	var color = get_piece_color(piece)
	if (color == "black" and (7-y) == 7) or (color == "red" and (7-y) == 0):
		tween.tween_callback(set_checker_king.bind(piece, color))
	piece.name = str(x) + "," + str(7-y)

func set_checker_king(piece: Sprite2D, color: String, undo: bool = false):
	if color == "red":
		piece.texture = red_normal_texture if undo else red_king_texture
	elif color == "black":
		piece.texture = black_normal_texture if undo else black_king_texture
		
func is_checker_king(piece: Sprite2D) -> bool:
	if piece.texture.resource_path.contains("king"):
		return true
	return false
	
func getPiecePos(piece: Sprite2D) -> Vector2:
	var posStr = piece.name.split(',')
	return Vector2(int(posStr[0]), int(posStr[1]))

func add_highlight(x: int, y: int):
	var newHighlight: BoardHighlight = boardHighlight.duplicate()
	highlights.append(newHighlight)
	add_child(newHighlight)
	var basePos: Vector2 = boardHighlight.get_meta("Position")
	var newPos = Vector2(basePos.x + (81 * x), basePos.y + (81 * y))
	newHighlight.set_meta("Position", newPos)
	newHighlight.set_meta("Visible", true);
	print("Highlighting: ", x, ",", y);


func clear_highlights():
	for highlight in highlights:
		highlight.free()
	highlights.clear()

func get_piece_color(piece: Sprite2D) -> String:
	if piece.texture.resource_path.contains("red"):
		return "red"
	elif piece.texture.resource_path.contains("black"):
		return "black"
	return "unknown"

func gen_moves():
	moves.clear()
	var diagonals: Array[Vector2]
	var color = get_piece_color(clicked_piece)
	var isKing = is_checker_king(clicked_piece)
	if color == "black" or isKing:
		diagonals.append(Vector2(-1, 1))
		diagonals.append(Vector2(1, 1))
	elif color == "red" or isKing:
		diagonals.append(Vector2(1, -1));
		diagonals.append(Vector2(-1, -1));
		
	for diagonal in diagonals:
		var clickedPiecePos = getPiecePos(clicked_piece)
		var pos = Vector2(clickedPiecePos.x + diagonal.x, clickedPiecePos.y + diagonal.y)
		if pos.y <= 7 and pos.y >= 0:
			var piece = get_node_or_null(str(pos.x) + "," + str(pos.y))
			if piece == null:
				if len(prev_moves) > 0:
					continue
				moves.append(pos)
				add_highlight(pos.x, 7 - pos.y)
			elif !check_player(piece) and len(prev_moves)/2 == len(prev_jumps): #only allow jump if the last move was a jump
				var x_step = 1 if pos.x > clickedPiecePos.x else -1
				var y_step = 1 if pos.y > clickedPiecePos.y else -1
				var newPos = Vector2(pos.x + x_step, pos.y + y_step)
				if get_node_or_null(str(newPos.x) + "," + str(newPos.y)) == null:
					moves.append(newPos)
					add_highlight(newPos.x, 7 - newPos.y)


func undo_move():
	clear_highlights()
	for i in range(len(prev_moves), 0, -2):
		move_piece(clicked_piece, prev_moves[i-2].x, abs(prev_moves[i-2].y - 7), (len(prev_moves)-i)*0.25)
	
	var color = get_piece_color(clicked_piece)
	if (color == "black" and prev_moves[-1].y == 7) or (color == "red" and prev_moves[-1].y == 0):
		set_checker_king(clicked_piece, color, true)
		
	for i in range(len(prev_jumps)-1, -1, -1):
		var prev_jump = prev_jumps[i]
		var tween = prev_jump.get_tree().create_tween()
		var modulate_color = prev_jump.self_modulate
		modulate_color.a = 1.0
		tween.tween_interval((len(prev_jumps)-1-i)*0.5)
		tween.tween_property(prev_jump, "self_modulate", modulate_color, 0.5).set_trans(Tween.TRANS_LINEAR)
		prev_jump.name = prev_jump.name.split("_")[0]
	clicked_piece = null
	has_moved = false
	prev_jumps.clear()
	prev_moves.clear()
	(get_node("../UndoButton") as Button).disabled = true
	(get_node("../SendButton") as Button).disabled = true

func check_player(piece: Sprite2D) -> bool:
	var color = get_piece_color(piece)
	if player == 2 and color == "black":
		return true
	elif player == 1 and color == "red":
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == 1:
			var x: int = ceil(event.position.x / 80) - 1;
			var y: int = ceil(event.position.y / 80) - 4;
			print("board position at ", x, ",", 7-y, " clicked")
			
			var clickedPiece: Sprite2D = get_node_or_null(str(x) + "," + str(7-y))
			if clickedPiece != null and (clicked_piece == null or has_moved == false):
				if check_player(clickedPiece):
					clear_highlights()
					clicked_piece = clickedPiece
					add_highlight(x, y)
					gen_moves()
			elif clicked_piece != null and moves.has(Vector2(x, 7-y)):
				var prevPiecePos = getPiecePos(clicked_piece)
				move_piece(clicked_piece, x, y)
				clear_highlights()
				has_moved = true
				prev_moves.append(prevPiecePos)
				prev_moves.append(Vector2(x, 7-y))
				if abs(prev_moves[-2].x - prev_moves[-1].x) > 1:
					jump_piece(prev_moves[-2].x, prev_moves[-2].y, prev_moves[-1].x, prev_moves[-1].y)
				gen_moves()
				(get_node("../UndoButton") as Button).disabled = false
				(get_node("../SendButton") as Button).disabled = false
				
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
