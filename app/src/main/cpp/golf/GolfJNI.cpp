#include <jni.h>
#include <algorithm>
#include <vector>
#include "GolfTable.h"

static GolfTable* tableFrom(jlong ptr) {
    return reinterpret_cast<GolfTable*>(ptr);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_createGolfTable(JNIEnv*, jobject) {
    return reinterpret_cast<jlong>(new GolfTable());
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_destroyGolfTable(JNIEnv*, jobject, jlong tablePtr) {
    delete tableFrom(tablePtr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_configureGolfTable(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jfloat tileSize,
        jfloat mapSize,
        jint rows,
        jint cols,
        jintArray openMaskArray,
        jfloatArray obstacleDataArray,
        jintArray obstacleKindArray,
        jbooleanArray obstacleBouncyArray,
        jfloatArray slopeDataArray
) {
    auto* table = tableFrom(tablePtr);
    if (!table) return;

    jint* openMask = nullptr;
    jfloat* obstacleData = nullptr;
    jint* obstacleKinds = nullptr;
    jboolean* obstacleBouncy = nullptr;
    jfloat* slopeData = nullptr;

    const int openMaskLen = openMaskArray ? env->GetArrayLength(openMaskArray) : 0;
    const int obstacleFloatLen = obstacleDataArray ? env->GetArrayLength(obstacleDataArray) : 0;
    const int obstacleKindLen = obstacleKindArray ? env->GetArrayLength(obstacleKindArray) : 0;
    const int obstacleBouncyLen = obstacleBouncyArray ? env->GetArrayLength(obstacleBouncyArray) : 0;
    const int slopeFloatLen = slopeDataArray ? env->GetArrayLength(slopeDataArray) : 0;

    if (openMaskArray && openMaskLen > 0) {
        openMask = env->GetIntArrayElements(openMaskArray, nullptr);
    }

    if (obstacleDataArray && obstacleFloatLen > 0) {
        obstacleData = env->GetFloatArrayElements(obstacleDataArray, nullptr);
    }

    if (obstacleKindArray && obstacleKindLen > 0) {
        obstacleKinds = env->GetIntArrayElements(obstacleKindArray, nullptr);
    }

    if (obstacleBouncyArray && obstacleBouncyLen > 0) {
        obstacleBouncy = env->GetBooleanArrayElements(obstacleBouncyArray, nullptr);
    }

    if (slopeDataArray && slopeFloatLen > 0) {
        slopeData = env->GetFloatArrayElements(slopeDataArray, nullptr);
    }

    const int obstacleCount = std::min(obstacleFloatLen / 4, std::min(obstacleKindLen, obstacleBouncyLen));
    std::vector<GolfObstacleInput> obstacles;
    obstacles.reserve(std::max(0, obstacleCount));

    for (int i = 0; i < obstacleCount; ++i) {
        obstacles.push_back({
            obstacleData[i * 4 + 0],
            obstacleData[i * 4 + 1],
            obstacleData[i * 4 + 2],
            obstacleData[i * 4 + 3],
            static_cast<int>(obstacleKinds[i]),
            obstacleBouncy[i] == JNI_TRUE
        });
    }

    const int slopeCount = slopeFloatLen / 5;
    std::vector<GolfSlopeInput> slopes;
    slopes.reserve(std::max(0, slopeCount));

    for (int i = 0; i < slopeCount; ++i) {
        slopes.push_back({
            slopeData[i * 5 + 0],
            slopeData[i * 5 + 1],
            slopeData[i * 5 + 2],
            slopeData[i * 5 + 3],
            slopeData[i * 5 + 4]
        });
    }

    table->configureMap(
            tileSize,
            mapSize,
            rows,
            cols,
            openMask,
            obstacles.empty() ? nullptr : obstacles.data(),
            static_cast<int>(obstacles.size()),
            slopes.empty() ? nullptr : slopes.data(),
            static_cast<int>(slopes.size())
    );

    if (slopeData) {
        env->ReleaseFloatArrayElements(slopeDataArray, slopeData, JNI_ABORT);
    }

    if (obstacleBouncy) {
        env->ReleaseBooleanArrayElements(obstacleBouncyArray, obstacleBouncy, JNI_ABORT);
    }

    if (obstacleKinds) {
        env->ReleaseIntArrayElements(obstacleKindArray, obstacleKinds, JNI_ABORT);
    }

    if (obstacleData) {
        env->ReleaseFloatArrayElements(obstacleDataArray, obstacleData, JNI_ABORT);
    }

    if (openMask) {
        env->ReleaseIntArrayElements(openMaskArray, openMask, JNI_ABORT);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_makeGolfBall(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jfloat x,
        jfloat y,
        jobject outputsBuffer
) {
    auto* table = tableFrom(tablePtr);
    if (!table) return;

    auto* outputs = static_cast<float*>(env->GetDirectBufferAddress(outputsBuffer));
    table->makeBall(x, y, outputs);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_setGolfBallState(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jfloat x,
        jfloat y,
        jfloat vx,
        jfloat vy
) {
    if (auto* table = tableFrom(tablePtr)) {
        table->setBallState(x, y, vx, vy);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_fireGolfBall(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jfloat directionRadians,
        jfloat power
) {
    if (auto* table = tableFrom(tablePtr)) {
        table->fireBall(directionRadians, power);
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_updateGolfTable(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jfloat dtSeconds
) {
    auto* table = tableFrom(tablePtr);
    if (!table) return JNI_FALSE;
    return table->update(dtSeconds) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_refreshGolfOutputs(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    if (auto* table = tableFrom(tablePtr)) {
        table->refreshOutputs();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_setGolfTraceContext(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jstring runIdString,
        jint shotIndex,
        jint frame,
        jstring phaseString
) {
    auto* table = tableFrom(tablePtr);
    if (!table) return;

    const char* runId = runIdString
                        ? env->GetStringUTFChars(runIdString, nullptr)
                        : "";

    const char* phase = phaseString
                        ? env->GetStringUTFChars(phaseString, nullptr)
                        : "";

    table->setTraceContext(
            runId ? runId : "",
            static_cast<int>(shotIndex),
            static_cast<int>(frame),
            phase ? phase : ""
    );

    if (phaseString && phase) {
        env->ReleaseStringUTFChars(phaseString, phase);
    }

    if (runIdString && runId) {
        env->ReleaseStringUTFChars(runIdString, runId);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_golf_GolfNativePhysics_clearGolfTraceContext(
        JNIEnv*,
        jobject,
        jlong tablePtr
) {
    auto* table = tableFrom(tablePtr);
    if (!table) return;

    table->clearTraceContext();
}
