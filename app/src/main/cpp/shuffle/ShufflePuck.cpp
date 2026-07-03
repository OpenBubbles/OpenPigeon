#include "ShufflePuck.h"
#include "ShuffleTable.h"
#include <cmath>

static constexpr float SHOT_VELOCITY_SCALE = 1.55f;
static constexpr float STOP_LINEAR_SPEED = 0.45f;
static constexpr float STOP_ANGULAR_SPEED = 0.04f;

ShufflePuck::ShufflePuck(
        ShuffleTable* table,
        b2Body* body,
        int traceId,
        int player,
        float* outputs
)
        : traceId(traceId),
          player(player),
          body(body),
          table(table),
          outputs(outputs),
          data({ShuffleData::Type::Puck, this, player}) {
    body->SetUserData(&data);
}

ShufflePuck::~ShufflePuck() {
    if (table && body) {
        table->destroyBody(body);
        body = nullptr;
    }
}

bool ShufflePuck::step() {
    if (!body || !outputs) return false;

    b2Vec2 vel = body->GetLinearVelocity();
    float angularVelocity = body->GetAngularVelocity();

    const float speed = vel.Length();
    const bool linearMoving = speed > STOP_LINEAR_SPEED;
    const bool angularMoving = std::fabs(angularVelocity) > STOP_ANGULAR_SPEED;

    if (!linearMoving) {
        body->SetLinearVelocity(b2Vec2_zero);
        vel.SetZero();
    }

    if (!angularMoving) {
        body->SetAngularVelocity(0.0f);
        angularVelocity = 0.0f;
    }

    const b2Vec2 pos = body->GetPosition();

    outputs[0] = pos.x;
    outputs[1] = pos.y;
    outputs[2] = body->GetAngle();
    outputs[3] = vel.x;
    outputs[4] = vel.y;
    outputs[5] = angularVelocity;
    outputs[6] = static_cast<float>(player);
    outputs[7] = static_cast<float>(traceId);

    return linearMoving || angularMoving;
}

void ShufflePuck::fire(float shootDirRadians, float dist) {
    if (!body || dist <= 0.5f) return;

    const b2Vec2 velocity(
            std::cos(shootDirRadians) * dist * SHOT_VELOCITY_SCALE,
            std::sin(shootDirRadians) * dist * SHOT_VELOCITY_SCALE
    );

    const b2Vec2 pos = body->GetPosition();

    // iOS rotates the puck body to align with the shot direction before applying velocity.
    body->SetTransform(pos, shootDirRadians + static_cast<float>(M_PI));

    body->SetAwake(true);
    body->SetAngularVelocity(0.0f);
    body->SetLinearVelocity(velocity);
}

void ShufflePuck::setTransform(float x, float y, float angle) {
    if (!body) return;

    body->SetTransform(b2Vec2(x, y), angle);
    body->SetLinearVelocity(b2Vec2_zero);
    body->SetAngularVelocity(0.0f);
}