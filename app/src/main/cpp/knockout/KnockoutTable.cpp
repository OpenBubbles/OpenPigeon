#include "KnockoutTable.h"
#include <algorithm>
#include <android/log.h>

static constexpr float PIECE_RADIUS = 12.5f;
static constexpr float PIECE_DENSITY = 1.0f;
static constexpr float PIECE_FRICTION = 1.0f;
static constexpr float PIECE_RESTITUTION = 1.0f;
static constexpr float LINEAR_DAMPING = 1.35f;
static constexpr float ANGULAR_DAMPING = 2.0f;
static constexpr float STEP_DT = 1.0f / 60.0f;
static constexpr int VELOCITY_ITERATIONS = 60;
static constexpr int POSITION_ITERATIONS = 60;

KnockoutTable::KnockoutTable()
        : world(b2Vec2_zero) {
    world.SetContactListener(&contactListener);
}

KnockoutTable::~KnockoutTable() {
    clearPieces();
}

void KnockoutTable::destroyBody(b2Body* body) {
    if (body) {
        world.DestroyBody(body);
    }
}

void KnockoutTable::clearPieces() {
    for (auto* piece : pieces) {
        delete piece;
    }
    pieces.clear();
}

void KnockoutTable::makePiece(float x, float y, float angle, int traceId, int player, float* outputs) {
    b2BodyDef def;
    def.type = b2_dynamicBody;
    def.position.Set(x, y);
    def.angle = angle;
    def.bullet = true;
    def.linearDamping = LINEAR_DAMPING;
    def.angularDamping = ANGULAR_DAMPING;
    def.allowSleep = false;

    b2Body* body = world.CreateBody(&def);

    b2CircleShape shape;
    shape.m_radius = PIECE_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    fixtureDef.density = PIECE_DENSITY;
    fixtureDef.friction = PIECE_FRICTION;
    fixtureDef.restitution = PIECE_RESTITUTION;

    body->CreateFixture(&fixtureDef);

    auto* piece = new KnockoutPiece(this, body, traceId, player, outputs);
    pieces.push_back(piece);

    if (outputs) {
        piece->step();
    }

    __android_log_print(ANDROID_LOG_INFO, "KnockoutNative",
                        "makePiece id=%d player=%d x=%f y=%f angle=%f mass=%f inertia=%f ratio=%f",
                        traceId, player, x, y, angle, body->GetMass(), body->GetInertia(),
                        body->GetInertia() / body->GetMass());
}

KnockoutPiece* KnockoutTable::findPiece(int traceId) {
    for (auto* piece : pieces) {
        if (piece->traceId == traceId) return piece;
    }
    return nullptr;
}

void KnockoutTable::firePiece(int traceId, float shootDirRadians, float power) {
    auto* piece = findPiece(traceId);
    if (!piece) return;
    piece->fire(shootDirRadians, power);
}

void KnockoutTable::movePiece(int traceId, float x, float y, float angle) {
    auto* piece = findPiece(traceId);
    if (!piece) return;
    piece->setTransform(x, y, angle);
}

bool KnockoutTable::update() {
    world.Step(STEP_DT, VELOCITY_ITERATIONS, POSITION_ITERATIONS);

    bool moving = false;
    for (auto* piece : pieces) {
        if (piece->step()) moving = true;
    }
    return moving;
}

void KnockoutTable::refreshOutputs() {
    for (auto* piece : pieces) {
        piece->step();
    }
}
