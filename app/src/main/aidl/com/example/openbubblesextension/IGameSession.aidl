package com.example.openbubblesextension;

import android.os.Bundle;
import com.example.openbubblesextension.IUpdateGameSessionCallback;
import com.example.openbubblesextension.IMessageUpdatedCallback;

interface IGameSession {
    Bundle getCurrentMessage(String id);
    void updateSession(in Bundle updates, String mySession, IUpdateGameSessionCallback callback);
    void registerCallback(String id, IMessageUpdatedCallback callback);
    String getSenderUUID(String id);

    void setSuppressNotifications(String id, boolean suppress);

    void lockMsgHandle(String id);
    void unlockMsgHandle(String id);
}