//
// Created by taeha on 5/16/2025.
//

#include "PoolTable.h"
#include "PoolBall.h"
#include <chrono>
#include <cstdint>
#include <iostream>
#include <android/log.h>
#include <inttypes.h>

PoolTable::PoolTable()
    : world(b2Vec2_zero),
      wallData({
          .type = PoolData::Type::Wall,
          .data = nullptr,
      }){

    world.SetContactListener(&contactListener);

    struct WallLine {
        b2Vec2 start;
        b2Vec2 end;
    } walls[] = {
            {b2Vec2(370, 50), b2Vec2(75, 50)},
            {b2Vec2(75, 50), b2Vec2(370, 50)},
            {b2Vec2(414, 50), b2Vec2(709, 50)},
            {b2Vec2(75, 50), b2Vec2(63.130043029785156, 33.903289794921875)},
            {b2Vec2(63.130043029785156, 33.903289794921875), b2Vec2(54.45692443847656, 19.282175064086914)},
            {b2Vec2(54.45692443847656, 19.282175064086914), b2Vec2(27.07282257080078, 9.736966133117676)},
            {b2Vec2(50, 75), b2Vec2(33.903289794921875, 63.130043029785156)},
            {b2Vec2(33.903289794921875, 63.130043029785156), b2Vec2(19.282175064086914, 54.45692443847656)},
            {b2Vec2(19.282175064086914, 54.45692443847656), b2Vec2(9.736966133117676, 27.07282257080078)},
            {b2Vec2(27.07282257080078, 9.736966133117676), b2Vec2(9.736966133117676, 27.07282257080078)},
            {b2Vec2(709, 50), b2Vec2(720.8699340820312, 33.903289794921875)},
            {b2Vec2(720.8699340820312, 33.903289794921875), b2Vec2(729.5430297851562, 19.282176971435547)},
            {b2Vec2(729.5430297851562, 19.282176971435547), b2Vec2(756.9271240234375, 9.736967086791992)},
            {b2Vec2(775, 75), b2Vec2(750.0966796875, 63.13003921508789)},
            {b2Vec2(750.0966796875, 63.13003921508789), b2Vec2(764.7177734375, 54.45691680908203)},
            {b2Vec2(764.7177734375, 54.45691680908203), b2Vec2(774.2630004882812, 27.072816848754883)},
            {b2Vec2(756.9271240234375, 9.736967086791992), b2Vec2(774.2630004882812, 27.072816848754883)},
            {b2Vec2(709, 390), b2Vec2(720.8699340820312, 406.0967102050781)},
            {b2Vec2(720.8699340820312, 406.0967102050781), b2Vec2(729.5430297851562, 420.71783447265625)},
            {b2Vec2(729.5430297851562, 420.71783447265625), b2Vec2(756.9271240234375, 430.2630310058594)},
            {b2Vec2(734, 365), b2Vec2(750.0966796875, 376.8699645996094)},
            {b2Vec2(750.0966796875, 376.8699645996094), b2Vec2(764.7177734375, 385.5430908203125)},
            {b2Vec2(764.7177734375, 385.5430908203125), b2Vec2(774.2630004882812, 412.9271850585938)},
            {b2Vec2(756.9271240234375, 430.2630310058594), b2Vec2(774.2630004882812, 412.9271850585938)},
            {b2Vec2(75, 390), b2Vec2(63.130043029785156, 406.0967102050781)},
            {b2Vec2(63.130043029785156, 406.0967102050781), b2Vec2(54.45692443847656, 420.71783447265625)},
            {b2Vec2(54.45692443847656, 420.71783447265625), b2Vec2(27.07282257080078, 430.2630310058594)},
            {b2Vec2(50, 365), b2Vec2(33.903289794921875, 376.8699645996094)},
            {b2Vec2(33.903289794921875, 376.8699645996094), b2Vec2(19.282175064086914, 385.5430908203125)},
            {b2Vec2(19.282175064086914, 385.5430908203125), b2Vec2(9.736966133117676, 412.9271850585938)},
            {b2Vec2(27.07282257080078, 430.2630310058594), b2Vec2(9.736966133117676, 412.9271850585938)},
            {b2Vec2(370, 50), b2Vec2(376.16009521484375, 34.15533447265625)},
            {b2Vec2(376.16009521484375, 34.15533447265625), b2Vec2(370.34088134765625, 17.121932983398438)},
            {b2Vec2(370.34088134765625, 17.121932983398438), b2Vec2(392, 0)},
            {b2Vec2(414, 50), b2Vec2(408.50408935546875, 33.912899017333984)},
            {b2Vec2(408.50408935546875, 33.912899017333984), b2Vec2(415.0265197753907, 17.13619613647461)},
            {b2Vec2(415.0265197753907, 17.13619613647461), b2Vec2(392, 0)},
            {b2Vec2(370, 390), b2Vec2(376.16009521484375, 405.84466552734375)},
            {b2Vec2(376.16009521484375, 405.84466552734375), b2Vec2(370.34088134765625, 422.8780517578125)},
            {b2Vec2(370.34088134765625, 422.8780517578125), b2Vec2(392, 440)},
            {b2Vec2(414, 390), b2Vec2(408.50408935546875, 406.08709716796875)},
            {b2Vec2(408.50408935546875, 406.08709716796875), b2Vec2(415.0265197753907, 422.8638000488282)},
            {b2Vec2(415.0265197753907, 422.8638000488282), b2Vec2(392, 440)},
            {b2Vec2(75, 390), b2Vec2(370, 390)},
            {b2Vec2(414, 390), b2Vec2(709, 390)},
            {b2Vec2(50, 75), b2Vec2(50, 365)},
            {b2Vec2(734, 75), b2Vec2(734, 365)},
    };

    b2BodyDef def;

    def.userData = &wallData;

    b2Body* body = world.CreateBody(&def);

    b2EdgeShape shape;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    fixtureDef.friction = 0.5;
    fixtureDef.restitution = 0.75;
    fixtureDef.density = 1.0;

    unsigned i = 0;
    for (auto wall :walls ) {
        shape.Set(wall.start, wall.end);
        fixtureDef.userData = wallHoles[i] ? &*wallHoles[i] : nullptr;
        body->CreateFixture(&fixtureDef);
        i++;
    }
}

void PoolTable::makeBall(b2Vec2 pos, float rot, float density, int number, int shouldGoIn, float* outputs) {
    b2BodyDef def;
    def.type = b2BodyType::b2_dynamicBody;
    def.position = pos;
    def.angle = rot;
    def.bullet = true;
    b2Body* body = world.CreateBody(&def);

    b2FixtureDef fixtureDef;
    fixtureDef.friction = 0;
    fixtureDef.restitution = 1;
    fixtureDef.density = density;

    b2CircleShape shape;
    shape.m_radius = 10;

    fixtureDef.shape = &shape;

    body->CreateFixture(&fixtureDef);
    body->SetAngularDamping(0.5);

    auto* ball = new PoolBall(this, body, number, shouldGoIn, outputs);
    balls.push_back(ball);
}

void PoolTable::hitBall(int number, float dir, float power, float spinX, float spinY, bool first) {
    // clean up old balls
    balls.erase(remove_if(balls.begin(), balls.end(), [](PoolBall* n){
        if (n->sunkOrder != -1) {
            delete n;
            return true;
        }
        return false;
    }), balls.end());
    isFirst = first;
    for (auto ball : balls) {
        ball->numberHit = -1;
        if (ball->number != number)
            continue;
        ball->hit(dir, power, spinX, spinY);
        break;
    }
}

void PoolTable::moveBall(int number, b2Vec2 position, float rot) {
    for (auto ball : balls) {
        if (ball->number != number)
            continue;
        ball->body->SetTransform(position, rot);
        break;
    }
}

uint64_t timeSinceEpochMillisec() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

bool PoolTable::update() {
    static uint64_t startTime = 0;
    static int startFrame = 0;
    using namespace std::chrono;
    if (startTime == 0) {
        startTime = timeSinceEpochMillisec();
        startFrame = 0;
    }

    startFrame += 1;
    if (startFrame == 60) {
        __android_log_print(ANDROID_LOG_VERBOSE, "Me", "Frames %" PRIu64, timeSinceEpochMillisec() - startTime);
    }

    world.Step(1.f / 60, 60, 60);

    // # of frames since cueball hit something
    if (cueDelay != -1 && cueDelay <= 2) {
        cueDelay += 1;
    }

    bool moving = false;
    for (auto ball : balls) {
        if (ball->step())
            moving = true;
    }

    return moving;
}

void PoolTable::clearBalls() {
    for (auto ball : balls) {
        delete ball;
    }
    balls.clear();
}
