#include "ShuffleTable.h"
#include <algorithm>
#include <android/log.h>
#include <cmath>

static constexpr float PUCK_RADIUS = 16.0f;
static constexpr float PUCK_DENSITY = 1.0f;
static constexpr float PUCK_FRICTION = 0.22f;
static constexpr float PUCK_RESTITUTION = 0.92f;

static constexpr float LINEAR_DAMPING = 0.72f;
static constexpr float ANGULAR_DAMPING = 1.60f;

static constexpr float STEP_DT = 1.0f / 60.0f;
static constexpr int VELOCITY_ITERATIONS = 60;
static constexpr int POSITION_ITERATIONS = 60;

static constexpr float WALL_X = 190.0f;
static constexpr float WALL_Y = 230.0f;
static constexpr float WALL_FRICTION = 0.20f;
static constexpr float WALL_RESTITUTION = 0.92f;

static constexpr float BUMPER_RADIUS = 26.5f;
static constexpr float BUMPER_FRICTION = 0.20f;
static constexpr float BUMPER_RESTITUTION = 1.0f;

ShuffleTable::ShuffleTable()
        : world(b2Vec2_zero) {
    world.SetContactListener(&contactListener);
    rebuildStaticBodies();
}

ShuffleTable::~ShuffleTable() {
    clearPucks();
    clearStaticBodies();
}

void ShuffleTable::destroyBody(b2Body* body) {
    if (body) {
        world.DestroyBody(body);
    }
}

void ShuffleTable::clearPucks() {
    for (auto* puck : pucks) {
        delete puck;
    }

    pucks.clear();
}

void ShuffleTable::clearStaticBodies() {
    for (auto* body : staticBodies) {
        if (body) {
            world.DestroyBody(body);
        }
    }

    staticBodies.clear();
    staticData.clear();
}

void ShuffleTable::setMode(int newMode) {
    newMode = std::max(1, std::min(3, newMode));

    if (mode == newMode) {
        return;
    }

    mode = newMode;
    rebuildStaticBodies();
}

void ShuffleTable::rebuildStaticBodies() {
    clearStaticBodies();

    staticData.reserve(8);

    // iOS creates three ShuffleWall objects. For Android, keep the physical
    // envelope explicit: left/right rails plus top/bottom backstops outside
    // the visible board so the ready pucks can sit at +/-215.
    addEdgeWall(
            b2Vec2(-WALL_X, -WALL_Y),
            b2Vec2(-WALL_X, WALL_Y),
            0
    );

    addEdgeWall(
            b2Vec2(WALL_X, -WALL_Y),
            b2Vec2(WALL_X, WALL_Y),
            0
    );

    addEdgeWall(
            b2Vec2(-WALL_X, WALL_Y),
            b2Vec2(WALL_X, WALL_Y),
            2
    );

    addEdgeWall(
            b2Vec2(-WALL_X, -WALL_Y),
            b2Vec2(WALL_X, -WALL_Y),
            1
    );

    if (mode == 2) {
        addBumper();
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "ShuffleNative",
            "rebuildStaticBodies mode=%d staticBodies=%zu",
            mode,
            staticBodies.size()
    );
}

void ShuffleTable::addEdgeWall(
        const b2Vec2& a,
        const b2Vec2& b,
        int player
) {
    b2BodyDef bodyDef;
    bodyDef.type = b2_staticBody;
    bodyDef.position.Set(0.0f, 0.0f);
    bodyDef.angle = 0.0f;

    b2Body* body = world.CreateBody(&bodyDef);

    b2EdgeShape edge;
    edge.Set(a, b);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &edge;
    fixtureDef.density = 0.0f;
    fixtureDef.friction = WALL_FRICTION;
    fixtureDef.restitution = WALL_RESTITUTION;

    body->CreateFixture(&fixtureDef);

    staticData.push_back({ShuffleData::Type::Wall, body, player});
    body->SetUserData(&staticData.back());

    staticBodies.push_back(body);
}

void ShuffleTable::addBumper() {
    b2BodyDef bodyDef;
    bodyDef.type = b2_staticBody;
    bodyDef.position.Set(0.0f, 0.0f);
    bodyDef.angle = 0.0f;

    b2Body* body = world.CreateBody(&bodyDef);

    b2CircleShape circle;
    circle.m_radius = BUMPER_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &circle;
    fixtureDef.density = 0.0f;
    fixtureDef.friction = BUMPER_FRICTION;
    fixtureDef.restitution = BUMPER_RESTITUTION;

    body->CreateFixture(&fixtureDef);

    staticData.push_back({ShuffleData::Type::Bumper, body, 0});
    body->SetUserData(&staticData.back());

    staticBodies.push_back(body);
}

void ShuffleTable::makePuck(
        float x,
        float y,
        float angle,
        int traceId,
        int player,
        float* outputs
) {
    b2BodyDef bodyDef;
    bodyDef.type = b2_dynamicBody;
    bodyDef.position.Set(x, y);
    bodyDef.angle = angle;
    bodyDef.bullet = true;
    bodyDef.linearDamping = LINEAR_DAMPING;
    bodyDef.angularDamping = ANGULAR_DAMPING;
    bodyDef.allowSleep = false;

    b2Body* body = world.CreateBody(&bodyDef);

    b2CircleShape circle;
    circle.m_radius = PUCK_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &circle;
    fixtureDef.density = PUCK_DENSITY;
    fixtureDef.friction = PUCK_FRICTION;
    fixtureDef.restitution = PUCK_RESTITUTION;

    body->CreateFixture(&fixtureDef);

    auto* puck = new ShufflePuck(
            this,
            body,
            traceId,
            player,
            outputs
    );

    pucks.push_back(puck);

    if (outputs) {
        puck->step();
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "ShuffleNative",
            "makePuck id=%d player=%d x=%f y=%f angle=%f mass=%f inertia=%f",
            traceId,
            player,
            x,
            y,
            angle,
            body->GetMass(),
            body->GetInertia()
    );
}

ShufflePuck* ShuffleTable::findPuck(int traceId) {
    for (auto* puck : pucks) {
        if (puck->traceId == traceId) {
            return puck;
        }
    }

    return nullptr;
}

void ShuffleTable::movePuck(
        int traceId,
        float x,
        float y,
        float angle
) {
    auto* puck = findPuck(traceId);
    if (!puck) return;

    puck->setTransform(x, y, angle);
}

void ShuffleTable::firePuck(
        int traceId,
        float shootDirRadians,
        float dist
) {
    auto* puck = findPuck(traceId);
    if (!puck) return;

    puck->fire(shootDirRadians, dist);
}

bool ShuffleTable::update() {
    world.Step(
            STEP_DT,
            VELOCITY_ITERATIONS,
            POSITION_ITERATIONS
    );

    bool moving = false;

    for (auto* puck : pucks) {
        if (puck->step()) {
            moving = true;
        }
    }

    return moving;
}

void ShuffleTable::refreshOutputs() {
    for (auto* puck : pucks) {
        puck->step();
    }
}