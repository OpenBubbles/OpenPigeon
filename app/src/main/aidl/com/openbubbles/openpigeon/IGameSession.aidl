package com.openbubbles.openpigeon;

import android.os.Bundle;
import com.openbubbles.openpigeon.IUpdateGameSessionCallback;
import com.openbubbles.openpigeon.IMessageUpdatedCallback;

interface IGameSession {
    Bundle getCurrentMessage(String id);
    void updateSession(in Bundle updates, String mySession, IUpdateGameSessionCallback callback);
    void registerCallback(String id, IMessageUpdatedCallback callback);
    String getSenderUUID(String id);

    void setSuppressNotifications(String id, boolean suppress);

    void lockMsgHandle(String id);
    void unlockMsgHandle(String id);
}