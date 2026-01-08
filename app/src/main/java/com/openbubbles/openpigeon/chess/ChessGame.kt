package com.openbubbles.openpigeon.chess

import android.content.Context
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.godot.GodotGameActivity

class ChessGame : Game {
    override fun getVersion(): String = "1"
    override fun getName(): String = "chess"
    override fun displayName(): String = "Chess"

    override fun gameClass(): Class<*> = GodotGameActivity::class.java

    // Use a dedicated chess icon drawable for the poster shown in pickers/menus.
    override fun gamePoster(config: Map<String, String>?): Int = R.drawable.chess
    
    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        return super.getNewGameData(context)!!.apply {
            put("replay", getDefaultReplay())
        }
    }
    
    override fun getDefaultReplay(): String {
        // Initial chess position in GamePigeon format
        // Board representation: 64-element flat array (index = file + rank*8)
        // Piece encoding: 0=empty, white: 11=P,12=R,13=N,14=B,15=Q,16=K, black: 21=P,22=R,23=N,24=B,25=Q,26=K
        // Rank 1: white back row (R,N,B,Q,K,B,N,R)
        // Rank 2: white pawns
        // Ranks 3-6: empty
        // Rank 7: black pawns
        // Rank 8: black back row (r,n,b,q,k,b,n,r)
        return "board:12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22"
    }
}