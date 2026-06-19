#include "KnockoutTable.h"
#include <algorithm>
#include <android/log.h>
#include <cmath>

static constexpr float PIECE_RADIUS = 12.5f;
static constexpr float PIECE_DENSITY = 1.0f;
static constexpr float PIECE_FRICTION = 1.0f;
static constexpr float PIECE_RESTITUTION = 1.0f;
static constexpr float LINEAR_DAMPING = 1.35f;
static constexpr float ANGULAR_DAMPING = 2.0f;
static constexpr float STEP_DT = 1.0f / 60.0f;
static constexpr int VELOCITY_ITERATIONS = 60;
static constexpr int POSITION_ITERATIONS = 60;
static constexpr float SHROOM_CENTER_BASE = 100.0f;
static constexpr float SHROOM_RADIUS_BASE = 22.5f;
static constexpr float SHROOM_RESTITUTION = 1.0f;
static constexpr float SHROOM_FRICTION = 1.0f;
static constexpr float SHROOM_BOUNCE_VELOCITY = 450.0f;
static constexpr float MAP_SCALE_EPS = 0.001f;

KnockoutTable::KnockoutTable()
        : world(b2Vec2_zero) {
    world.SetContactListener(&contactListener);
}

KnockoutTable::~KnockoutTable() {
    clearPieces();
    clearObstacles();
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

void KnockoutTable::clearObstacles() {
    for (auto* body : obstacles) {
        if (body) {
            world.DestroyBody(body);
        }
    }

    obstacles.clear();
    obstacleData.clear();
    mushroomHitMask = 0;
}

void KnockoutTable::setMap(int newMapMode, float newBoardScale) {
    newBoardScale = std::max(0.3f, newBoardScale);

    if (
            mapMode == newMapMode &&
            std::fabs(boardScale - newBoardScale) < MAP_SCALE_EPS
            ) {
        return;
    }

    mapMode = newMapMode;
    boardScale = newBoardScale;

    rebuildObstacles();
}

void KnockoutTable::rebuildObstacles() {
    clearObstacles();

    if (mapMode != 3) {
        return;
    }

    obstacleData.reserve(4);

    const float c = SHROOM_CENTER_BASE * boardScale;
    const float r = SHROOM_RADIUS_BASE * boardScale;

    const b2Vec2 positions[4] = {
            b2Vec2(-c, -c),
            b2Vec2( c, -c),
            b2Vec2(-c,  c),
            b2Vec2( c,  c),
    };

    for (const b2Vec2& pos : positions) {
        b2BodyDef bodyDef;
        bodyDef.type = b2_staticBody;
        bodyDef.position = pos;
        bodyDef.angle = 0.0f;

        b2Body* body = world.CreateBody(&bodyDef);

        b2CircleShape shape;
        shape.m_radius = r;

        b2FixtureDef fixtureDef;
        fixtureDef.shape = &shape;
        fixtureDef.density = 0.0f;
        fixtureDef.friction = SHROOM_FRICTION;
        fixtureDef.restitution = SHROOM_RESTITUTION;

        body->CreateFixture(&fixtureDef);

        obstacleData.push_back({KnockoutData::Type::Shroom, body});
        body->SetUserData(&obstacleData.back());

        obstacles.push_back(body);
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "KnockoutNative",
            "map3 mushrooms rebuilt scale=%f center=%f radius=%f",
            boardScale,
            c,
            r
    );
}

void KnockoutTable::registerMushroomHit(const b2Vec2& shroomPos) {
    if (mapMode != 3) return;

    const float c = SHROOM_CENTER_BASE * boardScale;

    const b2Vec2 positions[4] = {
            b2Vec2(-c, -c),
            b2Vec2( c, -c),
            b2Vec2(-c,  c),
            b2Vec2( c,  c),
    };

    int bestIndex = 0;
    float bestDist2 = 999999999.0f;

    for (int i = 0; i < 4; ++i) {
        const float dx = shroomPos.x - positions[i].x;
        const float dy = shroomPos.y - positions[i].y;
        const float d2 = dx * dx + dy * dy;

        if (d2 < bestDist2) {
            bestDist2 = d2;
            bestIndex = i;
        }
    }

    mushroomHitMask |= (1 << bestIndex);
}

int KnockoutTable::consumeMushroomHits() {
    const int mask = mushroomHitMask;
    mushroomHitMask = 0;
    return mask;
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
