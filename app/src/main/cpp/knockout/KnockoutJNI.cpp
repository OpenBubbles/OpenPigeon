#include <jni.h>
#include "KnockoutTable.h"

static KnockoutTable* tableFrom(jlong ptr) {
    return reinterpret_cast<KnockoutTable*>(ptr);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_createKnockoutTable(JNIEnv*, jobject) {
    return reinterpret_cast<jlong>(new KnockoutTable());
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_destroyKnockoutTable(JNIEnv*, jobject, jlong tablePtr) {
    delete tableFrom(tablePtr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_clearKnockoutPieces(JNIEnv*, jobject, jlong tablePtr) {
    if (auto* table = tableFrom(tablePtr)) table->clearPieces();
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_makeKnockoutPiece(
        JNIEnv* env,
        jobject,
        jlong tablePtr,
        jfloat x,
        jfloat y,
        jfloat angle,
        jint traceId,
        jint player,
        jobject outputsBuffer) {
    auto* table = tableFrom(tablePtr);
    if (!table) return;
    auto* outputs = static_cast<float*>(env->GetDirectBufferAddress(outputsBuffer));
    table->makePiece(x, y, angle, traceId, player, outputs);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_fireKnockoutPiece(
        JNIEnv*, jobject, jlong tablePtr, jint traceId, jfloat shootDirRadians, jfloat power) {
    if (auto* table = tableFrom(tablePtr)) table->firePiece(traceId, shootDirRadians, power);
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_moveKnockoutPiece(
        JNIEnv*, jobject, jlong tablePtr, jint traceId, jfloat x, jfloat y, jfloat angle) {
    if (auto* table = tableFrom(tablePtr)) table->movePiece(traceId, x, y, angle);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutRenderer_update(JNIEnv*, jobject, jlong tablePtr) {
    auto* table = tableFrom(tablePtr);
    if (!table) return JNI_FALSE;
    return table->update() ? JNI_TRUE : JNI_FALSE;
}

#include <string>
#include <sstream>
#include <cmath>
#include "KnockoutPiece.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutHarness_runTrace(JNIEnv* env, jobject, jint frames) {
    // 8 start-states from the setBoard dump, in body-list order (index 0..7).
    struct Seed { float x, y, r; int player; float dist, ar; };
    const Seed seeds[8] = {
            { -11.571605f,  -77.093292f, 4.363205f, 1,  74.957451f,  1.377353f },
            { 137.637360f,   28.678921f, 3.174611f, 1,  95.217552f, -2.906276f },
            { 132.783569f,  148.856461f, 5.450114f, 1, 118.885262f, -2.091799f },
            { -119.787865f, 124.894798f, 5.766389f, 1, 105.691200f, -0.569217f },
            {  50.132240f,   96.064453f, 5.987299f, 2,  63.950443f, -2.484452f },
            { -117.397438f, -23.882458f, 5.534649f, 2,  76.163383f,  0.424693f },
            {  60.939785f, -115.408684f, 2.428249f, 2, 106.148888f,  1.886323f },
            { 139.728958f,  -64.253662f, 5.547100f, 2, 106.068161f,  2.372697f },
    };

    KnockoutTable table;
    static float outbuf[8][8];
    for (int i = 0; i < 8; ++i) {
        table.makePiece(seeds[i].x, seeds[i].y, seeds[i].r, i, seeds[i].player, outbuf[i]);
    }

    // Fire exactly as firePreparedBoard: body angle = ar + PI/2, velocity = 2*dist along ar.
    const float HALF_PI = 1.5707963267948966f;
    for (int i = 0; i < 8; ++i) {
        table.movePiece(i, seeds[i].x, seeds[i].y, seeds[i].ar + HALF_PI);
        table.firePiece(i, seeds[i].ar, seeds[i].dist);
    }

    std::ostringstream out;
    out << "frame,index,player,x,y,angle,vx,vy,av,speed,dist,arrowRot\n";
    out.setf(std::ios::fixed);
    out.precision(6);

    auto emit = [&](int frame) {
        for (int i = 0; i < 8; ++i) {
            const float* o = outbuf[i];
            const float vx = o[3], vy = o[4];
            const float speed = std::sqrt(vx * vx + vy * vy);
            out << frame << ',' << i << ',' << seeds[i].player << ','
                << o[0] << ',' << o[1] << ',' << o[2] << ','
                << vx << ',' << vy << ',' << o[5] << ',' << speed << ','
                << seeds[i].dist << ',' << seeds[i].ar << '\n';
        }
    };

    // Frame 0 = post-fire, pre-step (matches "AFTER ShootShoot frame=0").
    table.refreshOutputs();
    emit(0);

    for (int f = 1; f <= frames; ++f) {
        table.update();
        emit(f);
    }

    return env->NewStringUTF(out.str().c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutHarness_runIosSeedTrace(
        JNIEnv* env,
        jobject,
        jint frames
) {
    struct Seed {
        float x;
        float y;
        float bodyAngle;
        int player;
        float dist;
        float arrowRot;
    };

    // Exact frame-0 iOS rows from the Frida output.
    // bodyAngle is already arrowRot + PI/2.
    const Seed seeds[8] = {
            {  36.812302f,  127.129150f, -0.276645f, 2,  89.013733f, -1.847441f },
            { -13.310945f,  -22.520950f,  3.013025f, 2,  72.620285f,  1.442229f },
            { 115.084091f, -111.350594f,  3.944860f, 2, 127.960571f,  2.374064f },
            {  -1.719931f,  -87.141403f,  3.235581f, 2,  93.554291f,  1.664785f },
            { -66.822449f,   19.129868f,  1.159217f, 1,  74.809265f, -0.411579f },
            { -59.121273f,  112.383148f,  0.542657f, 1, 107.392975f, -1.028139f },
            {-144.139740f,   14.509001f,  1.216885f, 1, 104.179062f, -0.353911f },
            { 121.709442f,   93.086998f, -0.647541f, 1, 145.760193f, -2.218337f },
    };

    KnockoutTable table;
    static float outbuf[8][8];

    for (int i = 0; i < 8; ++i) {
        table.makePiece(
                seeds[i].x,
                seeds[i].y,
                seeds[i].bodyAngle,
                i,
                seeds[i].player,
                outbuf[i]
        );
    }

    for (int i = 0; i < 8; ++i) {
        table.firePiece(i, seeds[i].arrowRot, seeds[i].dist);
    }

    std::ostringstream out;
    out << "config,PIECE_RADIUS,12.5\n";
    out << "config,POWER_TO_VELOCITY,2.0\n";
    out << "config,LINEAR_DAMPING,1.35\n";
    out << "config,ANGULAR_DAMPING,0.0\n";
    out << "config,VELOCITY_ITERATIONS,60\n";
    out << "config,POSITION_ITERATIONS,60\n";
    out << "frame,index,player,x,y,angle,vx,vy,av,speed,dist,arrowRot\n";

    out.setf(std::ios::fixed);
    out.precision(6);

    auto emit = [&](int frame) {
        table.refreshOutputs();

        for (int i = 0; i < 8; ++i) {
            const float* o = outbuf[i];
            const float vx = o[3];
            const float vy = o[4];
            const float speed = std::sqrt(vx * vx + vy * vy);

            out << frame << ','
                << i << ','
                << seeds[i].player << ','
                << o[0] << ','
                << o[1] << ','
                << o[2] << ','
                << vx << ','
                << vy << ','
                << o[5] << ','
                << speed << ','
                << seeds[i].dist << ','
                << seeds[i].arrowRot
                << '\n';
        }
    };

    // Frame 0 = post-fire, pre-step.
    emit(0);

    for (int f = 1; f <= frames; ++f) {
        table.update();
        emit(f);
    }

    return env->NewStringUTF(out.str().c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_setKnockoutMap(
        JNIEnv*,
        jobject,
        jlong tablePtr,
        jint mapMode,
        jfloat boardScale) {
    if (auto* table = tableFrom(tablePtr)) {
        table->setMap(static_cast<int>(mapMode), boardScale);
    }
}

extern "C" JNIEXPORT jint JNICALL
Java_com_openbubbles_openpigeon_knockout_KnockoutActivity_consumeKnockoutMushroomHits(
        JNIEnv*,
        jobject,
        jlong tablePtr) {
    if (auto* table = tableFrom(tablePtr)) {
        return table->consumeMushroomHits();
    }

    return 0;
}