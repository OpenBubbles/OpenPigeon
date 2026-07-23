#include "ShufflePuck.h"
#include "ShuffleTable.h"

#include <cmath>

namespace {
    constexpr float SHOT_VELOCITY_SCALE = 1.55f;

    constexpr float STOP_LINEAR_SPEED = 1.0f;

    constexpr float STOP_ANGULAR_SPEED = 0.08f;

    constexpr float BOARD_HALF_HEIGHT = 193.0f;
}

ShufflePuck::ShufflePuck(ShuffleTable *table, b2Body *body, int traceId, int player, float *outputs)
        : traceId(traceId), player(player), body(body), table(table), outputs(outputs),
          data({ShuffleData::Type::Puck, this, player}) {
    if (body) {
        body->SetUserData(&data);
    }
}

ShufflePuck::~ShufflePuck() {
    if (table && body) {
        table->destroyBody(body);

        body = nullptr;
    }
}

bool ShufflePuck::isMoving() const {
    if (!body) {
        return false;
    }

    const bool linearMoving = body->GetLinearVelocity().LengthSquared() > 0.0f;

    const bool angularMoving = std::fabs(body->GetAngularVelocity()) > 0.0f;

    return (linearMoving || angularMoving);
}

void ShufflePuck::updateInGameState() {
    if (!body || ingame) {
        return;
    }

    const float y = body->GetPosition().y;

    if (y > -BOARD_HALF_HEIGHT && y < BOARD_HALF_HEIGHT) {
        ingame = true;
    }
}

void ShufflePuck::stopSmallMotion() const {
    if (!body) {
        return;
    }

    const b2Vec2 linearVelocity = body->GetLinearVelocity();

    if (linearVelocity.LengthSquared() < STOP_LINEAR_SPEED * STOP_LINEAR_SPEED) {
        body->SetLinearVelocity(b2Vec2_zero);
    }

    const float angularVelocity = body->GetAngularVelocity();

    if (std::fabs(angularVelocity) < STOP_ANGULAR_SPEED) {
        body->SetAngularVelocity(0.0f);
    }

    const bool linearStopped = body->GetLinearVelocity().LengthSquared() == 0.0f;

    const bool angularStopped = body->GetAngularVelocity() == 0.0f;

    if (linearStopped && angularStopped) {
        body->SetAwake(false);
    }
}

void ShufflePuck::writeOutputs() {
    if (!body || !outputs) {
        return;
    }

    const b2Vec2 position = body->GetPosition();

    const b2Vec2 velocity = body->GetLinearVelocity();

    outputs[0] = position.x;

    outputs[1] = position.y;

    outputs[2] = body->GetAngle();

    outputs[3] = velocity.x;

    outputs[4] = velocity.y;

    outputs[5] = body->GetAngularVelocity();

    outputs[6] = static_cast<float>(
            player
    );

    outputs[7] = static_cast<float>(
            traceId
    );
}

bool ShufflePuck::step() {
    if (!body) {
        return false;
    }

    updateInGameState();
    stopSmallMotion();
    writeOutputs();

    return isMoving();
}

void ShufflePuck::fire(float shootDirRadians, float dist) const {
    if (!body || dist <= 0.5f) {
        return;
    }

    const b2Vec2 velocity(std::cos(shootDirRadians) * dist * SHOT_VELOCITY_SCALE,

                          std::sin(shootDirRadians) * dist * SHOT_VELOCITY_SCALE);

    const b2Vec2 position = body->GetPosition();

    body->SetTransform(position, shootDirRadians + static_cast<float>(
            M_PI * 0.5
    ));

    body->SetAwake(true);

    body->SetAngularVelocity(0.0f);

    body->SetLinearVelocity(velocity);
}

void ShufflePuck::setTransform(float x, float y, float angle) {
    if (!body) {
        return;
    }

    body->SetTransform(b2Vec2(x, y), angle);

    body->SetLinearVelocity(b2Vec2_zero);

    body->SetAngularVelocity(0.0f);

    ingame = y > -BOARD_HALF_HEIGHT && y < BOARD_HALF_HEIGHT;

    writeOutputs();
}