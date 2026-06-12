package com.openbubbles.openpigeon.crazy8

import android.content.Context
import com.openbubbles.openpigeon.util.OpenPigeonLog
import com.openbubbles.openpigeon.Game
import com.openbubbles.openpigeon.R
import com.openbubbles.openpigeon.settings.AvatarData
import com.openbubbles.openpigeon.settings.AvatarView
import java.util.UUID
import kotlin.random.Random

class Crazy8Game : Game {
    override fun getVersion(): String {
        return "5"
    }

    override fun getName(): String {
        return "crazy"
    }

    override fun displayName(): String {
        return "CRAZY 8"
    }

    override fun minPlayerRequirement(): Int {
        return 3
    }

    override fun gameClass(): Class<*> {
        return Crazy8Activity::class.java
    }

    override fun gamePoster(config: Map<String, String>?): Int {
        return R.drawable.crazy8thumb
    }

    override fun getNewGameData(context: Context): MutableMap<String, String>? {
        AvatarData.init(context)
        var data = super.getNewGameData(context)?.apply {
            val id = UUID.randomUUID().toString()
            val randBytes = ByteArray(6)
            Random.nextBytes(randBytes)
            var annendum = android.util.Base64.encodeToString(randBytes, android.util.Base64.DEFAULT)
            put("room", "$id${annendum}")
            put("avatar2", AvatarView.buildAvatarString())
        }
        OpenPigeonLog.i("Crazy8", "new_game_data roomPresent=${data?.containsKey("room") == true} avatar2=${data?.containsKey("avatar2") == true}")
        return data
    }

    override fun getDefaultReplay(): String {
        return ""
    }
}