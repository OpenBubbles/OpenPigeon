#include <jni.h>
#include "ShuffleTable.h"

static ShuffleTable* tableFrom(jlong ptr) {
    return reinterpret_cast<ShuffleTable*>(ptr);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_createShuffleTable(
        JNIEnv*,
        jobject
) {
    return reinterpret_cast<jlong>(new ShuffleTable());
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_destroyShuffleTable(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    delete tableFrom(tablePtr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_clearShufflePucks(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    if (auto* table = tableFrom(tablePtr)) {
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
    if (auto* table = tableFrom(tablePtr)) {
        table->setMode(static_cast<int>(mode));
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
    auto* table = tableFrom(tablePtr);
    if (!table) return;

    auto* outputs = static_cast<float*>(
            env->GetDirectBufferAddress(outputsBuffer)
    );

    table->makePuck(
            x,
            y,
            angle,
            static_cast<int>(traceId),
            static_cast<int>(player),
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
    if (auto* table = tableFrom(tablePtr)) {
        table->movePuck(
                static_cast<int>(traceId),
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
    if (auto* table = tableFrom(tablePtr)) {
        table->firePuck(
                static_cast<int>(traceId),
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
    auto* table = tableFrom(tablePtr);
    if (!table) return JNI_FALSE;

    return table->update() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_shuffle_ShuffleNativePhysics_refreshShuffleOutputs(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    if (auto* table = tableFrom(tablePtr)) {
        table->refreshOutputs();
    }
}