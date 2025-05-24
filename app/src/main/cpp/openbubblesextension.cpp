

#include <jni.h>
#include <Box2D/Box2D.h>
#include "PoolTable.h"

extern "C"
JNIEXPORT jlong JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_createPoolTable(JNIEnv *env, jobject thiz) {
    return (jlong)new PoolTable();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_destroyPoolTable(JNIEnv *env, jobject thiz,
                                                                         jlong table) {
    delete (PoolTable*)table;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_makeBall(JNIEnv *env, jobject thiz,
                                                                 jlong table, jfloat x, jfloat y,
                                                                 jfloat rot, jfloat density, jint number,
                                                                 jint shouldGoIn, jobject outputs) {
    auto* t = (PoolTable*) table;
    auto* outputAddress = static_cast<float*>(env->GetDirectBufferAddress(outputs));
    t->makeBall(b2Vec2(x, y), rot, density, number, shouldGoIn, outputAddress);
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_openbubblesextension_pool_PoolRenderer_update(JNIEnv *env, jobject thiz,
                                                               jlong table) {
    auto* t = (PoolTable*) table;
    return t->update();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_hitBall(JNIEnv *env, jobject thiz,
                                                                jlong table, jint number,
                                                                jfloat dir, jfloat power,
                                                                jfloat spinX, jfloat spinY,
                                                                jboolean first) {
    auto* t = (PoolTable*) table;
    t->hitBall(number, dir, power, spinX, spinY, first);
}
extern "C"
JNIEXPORT void JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_clearBalls(JNIEnv *env, jobject thiz,
                                                                   jlong table) {
    auto* t = (PoolTable*) table;
    t->clearBalls();
}
extern "C"
JNIEXPORT void JNICALL
Java_com_example_openbubblesextension_pool_PoolActivity_moveBall(JNIEnv *env, jobject thiz,
                                                                 jlong table, jint number, jfloat x,
                                                                 jfloat y, jfloat rot) {
    auto* t = (PoolTable*) table;
    t->moveBall(number, b2Vec2(x, y), rot);
}