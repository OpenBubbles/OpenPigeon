package com.example.openbubblesextension;

import android.os.Bundle;
import com.example.openbubblesextension.IUpdateGameSessionCallback;

interface IGameSession {
    Bundle getCurrentMessage(String id);
    void updateSession(in Bundle updates, String mySession, IUpdateGameSessionCallback callback);
}