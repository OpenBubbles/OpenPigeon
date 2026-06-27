#include "GolfBall.h"
#include "GolfTable.h"

#include <Box2D/Box2D.h>
#include <cmath>

static constexpr float POWER_TO_VELOCITY = 1.0f;
static constexpr float STOP_LINEAR_SPEED = 1.0f;
static constexpr float STOP_ANGULAR_SPEED = 0.05f;
static constexpr float READY_POWER_EPS = 0.01f;

GolfBall::GolfBall(GolfTable* table, b2Body* body, float* outputs)
        : body(body),
          table(table),
          outputs(outputs),
          data(GolfData::Type::Ball, 0, body, false) {
    if (body) {
        body->SetUserData(&data);
    }
}

GolfBall::~GolfBall() {
    if (table && body) {
        table->destroyBody(body);
        body = nullptr;
    }
}

bool GolfBall::step() {
    if (!body || !outputs) {
        return false;
    }

    const b2Vec2 vel = body->GetLinearVelocity();
    const float ang = body->GetAngularVelocity();

    const float speed = vel.Length();
    const bool linMoving = speed > STOP_LINEAR_SPEED;
    const bool angMoving = std::fabs(ang) > STOP_ANGULAR_SPEED;

    const b2Vec2 pos = body->GetPosition();

    outputs[0] = pos.x;
    outputs[1] = pos.y;
    outputs[2] = body->GetAngle();
    outputs[3] = vel.x;
    outputs[4] = vel.y;
    outputs[5] = ang;
    outputs[6] = linMoving || angMoving ? 1.0f : 0.0f;
    outputs[7] = 0.0f;

    return linMoving || angMoving;
}

void GolfBall::setState(float x, float y, float vx, float vy) {
    if (!body) {
        return;
    }

    body->SetTransform(b2Vec2(x, y), body->GetAngle());
    body->SetAwake(true);
    body->SetLinearVelocity(b2Vec2(vx, vy));
    body->SetAngularVelocity(0.0f);
}

void GolfBall::fire(float directionRadians, float power) {
    if (!body || power <= READY_POWER_EPS) {
        return;
    }

    const b2Vec2 vel(
            std::cos(directionRadians) * power * POWER_TO_VELOCITY,
            std::sin(directionRadians) * power * POWER_TO_VELOCITY
    );

    body->SetAwake(true);
    body->SetAngularVelocity(0.0f);
    body->SetLinearVelocity(vel);
}