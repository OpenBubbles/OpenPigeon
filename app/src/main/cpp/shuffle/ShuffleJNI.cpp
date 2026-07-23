#include <jni.h>
#include "ShuffleTable.h"

static ShuffleTable* tableFrom(
        jlong pointer
) {
    return reinterpret_cast<ShuffleTable*>(
            pointer
    );
}

bool gShuffleDebugLoggingEnabled =
        false;

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_setShuffleDebugLogging(
        JNIEnv*,
        jobject,
        jboolean enabled
) {
    gShuffleDebugLoggingEnabled =
            enabled == JNI_TRUE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_createShuffleTable(
        JNIEnv*,
        jobject
) {
    return reinterpret_cast<jlong>(
            new ShuffleTable()
    );
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_destroyShuffleTable(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    delete tableFrom(
            tablePtr
    );
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_clearShufflePucks(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->clearPucks();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_setShuffleMode(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jint mode
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->setMode(
                static_cast<int>(
                        mode
                )
        );
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_makeShufflePuck(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jfloat x,
        jfloat y,
        jfloat angle,
        jint traceId,
        jint player,
        jobject outputsBuffer
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (!table) {
        return;
    }

    auto* outputs =
            static_cast<float*>(
                    env->GetDirectBufferAddress(
                            outputsBuffer
                    )
            );

    table->makePuck(
            x,
            y,
            angle,
            static_cast<int>(
                    traceId
            ),
            static_cast<int>(
                    player
            ),
            outputs
    );
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_moveShufflePuck(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jint traceId,
        jfloat x,
        jfloat y,
        jfloat angle
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->movePuck(
                static_cast<int>(
                        traceId
                ),
                x,
                y,
                angle
        );
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_fireShufflePuck(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jint traceId,
        jfloat shootDirRadians,
        jfloat dist
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->firePuck(
                static_cast<int>(
                        traceId
                ),
                shootDirRadians,
                dist
        );
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_updateShuffle(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (!table) {
        return JNI_FALSE;
    }

    return table->update()
           ? JNI_TRUE
           : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_refreshShuffleOutputs(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->refreshOutputs();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_setShuffleTraceContext(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jstring runIdString,
        jint shotIndex,
        jint frame,
        jstring phaseString
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (!table) {
        return;
    }

    const char* runId =
            runIdString
            ? env->GetStringUTFChars(
                    runIdString,
                    nullptr
            )
            : "";

    const char* phase =
            phaseString
            ? env->GetStringUTFChars(
                    phaseString,
                    nullptr
            )
            : "";

    table->setTraceContext(
            runId
            ? runId
            : "",
            static_cast<int>(
                    shotIndex
            ),
            static_cast<int>(
                    frame
            ),
            phase
            ? phase
            : ""
    );

    if (
            phaseString &&
            phase
            ) {
        env->ReleaseStringUTFChars(
                phaseString,
                phase
        );
    }

    if (
            runIdString &&
            runId
            ) {
        env->ReleaseStringUTFChars(
                runIdString,
                runId
        );
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_clearShuffleTraceContext(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    ShuffleTable* table =
            tableFrom(
                    tablePtr
            );

    if (table) {
        table->clearTraceContext();
    }
}