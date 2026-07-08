#include <jni.h>
#include <Box2D/Box2D.h>
#include "PoolTable.h"
#include <string>

extern "C"
JNIEXPORT jlong JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_createPoolTable(
        JNIEnv *env,
        jobject thiz
) {
    return reinterpret_cast<jlong>(new PoolTable());
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_destroyPoolTable(
        JNIEnv *env,
        jobject thiz,
        jlong table
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    delete t;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_makeBall(
        JNIEnv *env,
        jobject thiz,
        jlong table,
        jfloat x,
        jfloat y,
        jfloat rot,
        jfloat density,
        jint number,
        jint shouldGoIn,
        jobject outputs
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr || outputs == nullptr) {
        return;
    }

    auto* outputAddress = static_cast<float*>(env->GetDirectBufferAddress(outputs));
    if (outputAddress == nullptr) {
        return;
    }

    t->makeBall(b2Vec2(x, y), rot, density, number, shouldGoIn, outputAddress);
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_openbubbles_openpigeon_pool_PoolRenderer_update(
        JNIEnv *env,
        jobject thiz,
        jlong table
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return JNI_FALSE;
    }

    return t->update() ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_hitBall(
        JNIEnv *env,
        jobject thiz,
        jlong table,
        jint number,
        jfloat dir,
        jfloat power,
        jfloat spinX,
        jfloat spinY,
        jboolean first
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return;
    }

    t->hitBall(number, dir, power, spinX, spinY, first == JNI_TRUE);
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_clearBalls(
        JNIEnv *env,
        jobject thiz,
        jlong table
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return;
    }

    t->clearBalls();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_moveBall(
        JNIEnv *env,
        jobject thiz,
        jlong table,
        jint number,
        jfloat x,
        jfloat y,
        jfloat rot
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return;
    }

    t->moveBall(number, b2Vec2(x, y), rot);
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_dumpPoolTable(
        JNIEnv* env,
        jobject thiz,
        jlong table
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return env->NewStringUTF("");
    }

    std::string state = t->dumpState();
    return env->NewStringUTF(state.c_str());
}

extern "C"
JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_pool_PoolActivity_setPoolDebugTrace(
        JNIEnv* env,
        jobject thiz,
        jlong table,
        jboolean enabled,
        jint everyFrames
) {
    auto* t = reinterpret_cast<PoolTable*>(table);
    if (t == nullptr) {
        return;
    }

    t->setDebugTrace(enabled == JNI_TRUE, everyFrames);
}