//
// Created by taeha on 5/16/2025.
//

#include "PoolBall.h"
#include "PoolTable.h"
#include <android/log.h>

// defined in b2TimeOfImpact.cpp
void set_custom_slop(float32 slop);

PoolBall::PoolBall(PoolTable *table, b2Body *body, int number, int shouldGoIn, float* outputs)
    : table(table),
      body(body),
      number(number),
      outputs(outputs),
      hole(-1, -1),
      hitHole(-1, -1),
      shouldGoIn(shouldGoIn),
      data({
            .type = PoolData::Type::Ball,
            .data = this,
    })
{
    body->SetUserData(&data);
}

bool PoolBall::step() {
    outputs[0] = body->GetPosition().x;
    outputs[1] = body->GetPosition().y;
    outputs[2] = body->GetAngle();
    outputs[3] = (float)sunkOrder;
    outputs[4] = (float)numberHit;
    outputs[5] = hole.x;
    outputs[6] = hole.y;

    // spin fast, just don't spin slow...
    if (std::abs(body->GetAngularVelocity()) < 3.0f) {
        float adjustedVelocity = body->GetAngularVelocity() * 0.8f;
        body->SetAngularVelocity(adjustedVelocity);
    }

    // gamepigeon has custom drag...
    b2Vec2 currentVel = body->GetLinearVelocity();

    if (currentVel.LengthSquared() > 0) {
        float speed = currentVel.Length();
        float fric1 = 0.99375;
        float fric2 = 0.425;

        float new_speed = (speed - fric2) * fric1;
        if (new_speed < 2) {
            new_speed = 0;
        }

        currentVel *= new_speed / speed;
        body->SetLinearVelocity(currentVel);

        if (number == 0) {
            auto transform = body->GetTransform();
            __android_log_print(ANDROID_LOG_VERBOSE, "Me", "Test %f %f %f %f", transform.p.x, transform.p.y, transform.q.s, transform.q.c);
        }
    }

    if (abs(body->GetAngularVelocity()) < 0.1) {
        body->SetAngularVelocity(0);
    }

    for (auto& tableHole : table->holes) {
        b2Vec2 holeVector = tableHole - body->GetPosition();
        float dist = holeVector.Length();
        float hole_radius = 20;
        float hole_sink = hole_radius * 0.5f;

        // box2d is not deterministic across platforms and binaries
        // so we have to "cheat"
        if (shouldGoIn == SHOULD_GO_IN) {
            hole_sink *= 2.0f;
        }
        if (shouldGoIn == SHOULD_NOT_GO_IN) {
            hole_sink = 0;
        }

        if (hole_sink > dist || hole == tableHole || hitHole == tableHole) {
            if (hole.x == -1) {
                __android_log_print(ANDROID_LOG_VERBOSE, "Ball", "Ball fell in");
                // we fell in, do more logic here...

                // push to the metaphorical "collection bay"
                b2Vec2 offsetToPoint = b2Vec2(392, 220) - body->GetPosition();
                offsetToPoint.Normalize();
                offsetToPoint *= 4.0f;
                offsetToPoint += body->GetLinearVelocity();
                body->SetLinearVelocity(offsetToPoint);

                sunkOrder = table->pocketNumber;
                table->pocketNumber++;
            }
            hole = tableHole;
            outputs[3] = (float)sunkOrder;

        } else if (hole_radius > dist) {
            // "nudge" into hole
            holeVector *= 5.0f;
            holeVector += body->GetLinearVelocity();
            body->SetLinearVelocity(holeVector);
        }
    }

    if (table->cueDelay >= 3) {
        body->GetFixtureList()->SetDensity(1);
        body->ResetMassData();
        set_custom_slop(0.005f);
    }

    if (number == 0) {

        // cue ball only (spin)
        // reduce spin power
        spinPower *= 0.94f;

        if (table->cueDelay >= 3 && body->GetLinearVelocity().LengthSquared() > 0 && spinPower > 0.1f) {
            b2Vec2 mySpin(spinDir);
            mySpin *= spinPower;
            mySpin += body->GetLinearVelocity();
            body->SetLinearVelocity(mySpin);
        }
    }
    return (body->GetAngularVelocity() > 0 || body->GetLinearVelocity().LengthSquared() > 0) && hole.x == -1;
}

void PoolBall::hit(float dir, float power, float spinX, float spinY) {

    table->cueDelay = -1;
    table->pocketNumber = 0;

    b2Vec2 vel(std::cos(dir), std::sin(dir));
    vel *= power;
    body->SetLinearVelocity(vel);

    float powerFrac = power / 2000;

    spinPower = powerFrac * std::abs(spinY);
    spinDir = b2Vec2(std::cos(dir), std::sin(dir));
    if (spinY < 0) {
        spinDir *= -1;
    }

    auto transform = body->GetTransform();
    __android_log_print(ANDROID_LOG_VERBOSE, "Me", "Here %f %f %f %f", transform.p.x, transform.p.y, transform.q.s, transform.q.c);


    float angularVel = powerFrac * spinX;
    if (std::abs(angularVel) < 50) {
        angularVel = 0;
    }
    body->SetAngularVelocity(angularVel);
}

PoolBall::~PoolBall() {
    table->world.DestroyBody(body);
}