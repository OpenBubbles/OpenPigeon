#include "KnockoutPiece.h"
#include "KnockoutTable.h"
#include <cmath>

static constexpr float POWER_TO_VELOCITY = 2.0f;
static constexpr float STOP_LINEAR_SPEED = 1.0f;
static constexpr float STOP_ANGULAR_SPEED = 0.08f;

KnockoutPiece::KnockoutPiece(KnockoutTable* table, b2Body* body, int traceId, int player, float* outputs)
        : traceId(traceId),
          player(player),
          body(body),
          table(table),
          outputs(outputs),
          data({KnockoutData::Type::Piece, this}) {
    body->SetUserData(&data);
}

KnockoutPiece::~KnockoutPiece() {
    if (table && body) {
        table->destroyBody(body);
        body = nullptr;
    }
}

bool KnockoutPiece::step() {
    if (!body || !outputs) return false;

    b2Vec2 vel = body->GetLinearVelocity();
    float ang = body->GetAngularVelocity();

    const float speed = vel.Length();
    const bool linMoving = speed > STOP_LINEAR_SPEED;            // 1.0
    const bool angMoving = std::fabs(ang) > STOP_ANGULAR_SPEED;  // 0.08

    if (!linMoving) { body->SetLinearVelocity(b2Vec2_zero); vel.SetZero(); }
    if (!angMoving) { body->SetAngularVelocity(0.0f); ang = 0.0f; }

    const b2Vec2 pos = body->GetPosition();
    outputs[0] = pos.x;
    outputs[1] = pos.y;
    outputs[2] = body->GetAngle();
    outputs[3] = vel.x;
    outputs[4] = vel.y;
    outputs[5] = ang;
    outputs[6] = static_cast<float>(player);
    outputs[7] = static_cast<float>(traceId);

    return linMoving || angMoving;
}

void KnockoutPiece::fire(float shootDirRadians, float power) {
    if (!body || power <= 0.5f) return;

    const b2Vec2 vel(std::cos(shootDirRadians) * power * POWER_TO_VELOCITY,
                     std::sin(shootDirRadians) * power * POWER_TO_VELOCITY);

    body->SetAwake(true);
    body->SetAngularVelocity(0.0f);
    body->SetLinearVelocity(vel);
}

void KnockoutPiece::setTransform(float x, float y, float angle) {
    if (!body) return;
    body->SetTransform(b2Vec2(x, y), angle);
    body->SetLinearVelocity(b2Vec2_zero);
    body->SetAngularVelocity(0.0f);
}
