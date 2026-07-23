#include "ShuffleTable.h"

#include <algorithm>
#include <android/log.h>
#include <cmath>
#include <cstdarg>

extern bool gShuffleDebugLoggingEnabled;

namespace {
    constexpr float PUCK_RADIUS = 15.0f;

    constexpr float PUCK_DENSITY = 1.0f;

    constexpr float PUCK_FRICTION = 1.0f;

    constexpr float PUCK_RESTITUTION = 1.0f;

    constexpr float LINEAR_DAMPING = 1.5f;

    constexpr float ANGULAR_DAMPING = 2.0f;

    constexpr float STEP_DT = 1.0f / 60.0f;

    constexpr int VELOCITY_ITERATIONS = 60;

    constexpr int POSITION_ITERATIONS = 60;

    constexpr float WALL_X = 178.0f;

    constexpr float WALL_Y = 193.0f;

    constexpr float WALL_DENSITY = 1.0f;

    constexpr float WALL_FRICTION = 0.5f;

    constexpr float WALL_RESTITUTION = 0.75f;

    constexpr float BUMPER_RADIUS = 26.5f;

    constexpr float BUMPER_DENSITY = 1.0f;

    constexpr float BUMPER_FRICTION = 0.20f;

    constexpr float BUMPER_RESTITUTION = 1.0f;

    void shuffleNativeLogPrint(int priority, const char *tag, const char *format, ...) {
        if (!gShuffleDebugLoggingEnabled) {
            return;
        }

        va_list args;
        va_start(args, format);

        __android_log_vprint(priority, tag, format, args);

        va_end(args);
    }

    void applyStaticBodyDefaults(b2BodyDef &bodyDef) {
        bodyDef.type = b2_staticBody;

        bodyDef.position.Set(0.0f, 0.0f);

        bodyDef.angle = 0.0f;

        bodyDef.linearVelocity.Set(0.0f, 0.0f);

        bodyDef.angularVelocity = 0.0f;

        bodyDef.linearDamping = 0.0f;

        bodyDef.angularDamping = 2.0f;

        bodyDef.allowSleep = true;

        bodyDef.awake = true;

        bodyDef.fixedRotation = false;

        bodyDef.bullet = false;

        bodyDef.active = true;

        bodyDef.gravityScale = 1.0f;
    }

    void applyPuckBodyDefaults(b2BodyDef &bodyDef) {
        bodyDef.type = b2_dynamicBody;

        bodyDef.position.Set(0.0f, 0.0f);

        bodyDef.angle = 0.0f;

        bodyDef.linearVelocity.Set(0.0f, 0.0f);

        bodyDef.angularVelocity = 0.0f;

        bodyDef.linearDamping = LINEAR_DAMPING;

        bodyDef.angularDamping = ANGULAR_DAMPING;

        bodyDef.allowSleep = false;

        bodyDef.awake = true;

        bodyDef.fixedRotation = false;

        bodyDef.bullet = true;

        bodyDef.active = true;

        bodyDef.gravityScale = 1.0f;
    }

    void applyFilter(b2FixtureDef &fixtureDef) {
        fixtureDef.isSensor = false;

        fixtureDef.filter.categoryBits = 0x0001;

        fixtureDef.filter.maskBits = 0xffff;

        fixtureDef.filter.groupIndex = 0;
    }

    void logPuckFrame(const char *runId, int shotIndex, int frame, const char *contextPhase,
                      const char *framePhase, const ShufflePuck *puck) {
        if (!puck || !puck->body) {
            return;
        }

        const b2Vec2 position = puck->body->GetPosition();

        const b2Vec2 velocity = puck->body->GetLinearVelocity();

        shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_FRAME={"
                                                                 "\"runId\":\"%s\","
                                                                 "\"shotIndex\":%d,"
                                                                 "\"frame\":%d,"
                                                                 "\"contextPhase\":\"%s\","
                                                                 "\"phase\":\"%s\","
                                                                 "\"traceId\":%d,"
                                                                 "\"player\":%d,"
                                                                 "\"ingame\":%s,"
                                                                 "\"position\":{\"x\":%.9f,\"y\":%.9f},"
                                                                 "\"angle\":%.9f,"
                                                                 "\"velocity\":{\"x\":%.9f,\"y\":%.9f},"
                                                                 "\"speed\":%.9f,"
                                                                 "\"angularVelocity\":%.9f,"
                                                                 "\"awake\":%s"
                                                                 "}", runId ? runId : "", shotIndex,
                              frame, contextPhase ? contextPhase : "", framePhase ? framePhase : "",
                              puck->traceId, puck->player, puck->ingame ? "true" : "false",
                              position.x, position.y, puck->body->GetAngle(), velocity.x,
                              velocity.y, velocity.Length(), puck->body->GetAngularVelocity(),
                              puck->body->IsAwake() ? "true" : "false");
    }
}

ShuffleTable::ShuffleTable() : world(b2Vec2_zero) {
    world.SetContactListener(&contactListener);

    rebuildStaticBodies();
}

ShuffleTable::~ShuffleTable() {
    clearPucks();
    clearStaticBodies();
}

void ShuffleTable::setTraceContext(const char *runId, int shotIndex, int frame, const char *phase) {
    traceRunId = runId ? runId : "";

    traceShotIndex = shotIndex;

    traceFrame = frame;

    tracePhase = phase ? phase : "";

    contactListener.setTraceContext(traceRunId.c_str(), traceShotIndex, traceFrame,
                                    tracePhase.c_str());
}

void ShuffleTable::clearTraceContext() {
    traceRunId.clear();
    traceShotIndex = -1;
    traceFrame = -1;
    tracePhase.clear();

    contactListener.clearTraceContext();
}

void ShuffleTable::destroyBody(b2Body *body) {
    if (body) {
        world.DestroyBody(body);
    }
}

void ShuffleTable::clearPucks() {
    for (ShufflePuck *puck: pucks) {
        delete puck;
    }

    pucks.clear();
}

void ShuffleTable::clearStaticBodies() {
    for (b2Body *body: staticBodies) {
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

    addEdgeWall(b2Vec2(WALL_X, WALL_Y), b2Vec2(WALL_X, -WALL_Y), 0);

    addEdgeWall(b2Vec2(-WALL_X, WALL_Y), b2Vec2(-WALL_X, -WALL_Y), 0);

    addEdgeWall(b2Vec2(-WALL_X, -WALL_Y), b2Vec2(WALL_X, -WALL_Y), 1);

    addEdgeWall(b2Vec2(-WALL_X, WALL_Y), b2Vec2(WALL_X, WALL_Y), 2);

    if (mode == 2) {
        addBumper();
    }

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_TABLE={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"phase\":\"rebuildStaticBodies\","
                                                             "\"mode\":%d,"
                                                             "\"wallX\":%.9f,"
                                                             "\"wallY\":%.9f,"
                                                             "\"staticBodyCount\":%zu"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, mode, WALL_X, WALL_Y, staticBodies.size());
}

void ShuffleTable::addEdgeWall(const b2Vec2 &a, const b2Vec2 &b, int player) {
    b2BodyDef bodyDef;
    applyStaticBodyDefaults(bodyDef);

    b2Body *body = world.CreateBody(&bodyDef);

    b2EdgeShape edge;
    edge.Set(a, b);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &edge;

    fixtureDef.density = WALL_DENSITY;

    fixtureDef.friction = WALL_FRICTION;

    fixtureDef.restitution = WALL_RESTITUTION;

    applyFilter(fixtureDef);

    body->CreateFixture(&fixtureDef);

    staticData.push_back({ShuffleData::Type::Wall, body, player});

    body->SetUserData(&staticData.back());

    staticBodies.push_back(body);

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_FIXTURE={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"ownerType\":\"wall\","
                                                             "\"player\":%d,"
                                                             "\"shape\":\"edge\","
                                                             "\"vertex1\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"vertex2\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"density\":%.9f,"
                                                             "\"friction\":%.9f,"
                                                             "\"restitution\":%.9f,"
                                                             "\"categoryBits\":%u,"
                                                             "\"maskBits\":%u,"
                                                             "\"groupIndex\":%d"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, player, a.x, a.y, b.x, b.y,
                          fixtureDef.density, fixtureDef.friction, fixtureDef.restitution,
                          static_cast<unsigned>(
                                  fixtureDef.filter.categoryBits
                          ), static_cast<unsigned>(
                                  fixtureDef.filter.maskBits
                          ), static_cast<int>(
                                  fixtureDef.filter.groupIndex
                          ));
}

void ShuffleTable::addBumper() {
    b2BodyDef bodyDef;
    applyStaticBodyDefaults(bodyDef);

    bodyDef.position.Set(0.0f, 0.0f);

    b2Body *body = world.CreateBody(&bodyDef);

    b2CircleShape circle;
    circle.m_radius = BUMPER_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &circle;

    fixtureDef.density = BUMPER_DENSITY;

    fixtureDef.friction = BUMPER_FRICTION;

    fixtureDef.restitution = BUMPER_RESTITUTION;

    applyFilter(fixtureDef);

    body->CreateFixture(&fixtureDef);

    staticData.push_back({ShuffleData::Type::Bumper, body, 0});

    body->SetUserData(&staticData.back());

    staticBodies.push_back(body);

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_FIXTURE={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"ownerType\":\"bumper\","
                                                             "\"shape\":\"circle\","
                                                             "\"center\":{\"x\":0.000000000,\"y\":0.000000000},"
                                                             "\"radius\":%.9f,"
                                                             "\"density\":%.9f,"
                                                             "\"friction\":%.9f,"
                                                             "\"restitution\":%.9f,"
                                                             "\"provisional\":true"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, BUMPER_RADIUS, fixtureDef.density,
                          fixtureDef.friction, fixtureDef.restitution);
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
    applyPuckBodyDefaults(
            bodyDef
    );

    b2Body* body =
            world.CreateBody(
                    &bodyDef
            );

    body->SetLinearDamping(
            LINEAR_DAMPING
    );

    body->SetAngularDamping(
            ANGULAR_DAMPING
    );

    b2CircleShape circle;
    circle.m_radius =
            PUCK_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape =
            &circle;

    fixtureDef.density =
            PUCK_DENSITY;

    fixtureDef.friction =
            PUCK_FRICTION;

    fixtureDef.restitution =
            PUCK_RESTITUTION;

    applyFilter(
            fixtureDef
    );

    body->CreateFixture(
            &fixtureDef
    );

    auto* puck =
            new ShufflePuck(
                    this,
                    body,
                    traceId,
                    player,
                    outputs
            );

    body->SetTransform(
            b2Vec2(
                    x,
                    y
            ),
            angle
    );

    body->SetAwake(
            true
    );

    puck->updateInGameState();
    puck->writeOutputs();

    pucks.push_back(
            puck
    );

    shuffleNativeLogPrint(
            ANDROID_LOG_INFO,
            "ShuffleNative",
            "SHUFFLE_NATIVE_PUCK_CREATED={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"traceId\":%d,"
            "\"player\":%d,"
            "\"position\":{\"x\":%.9f,\"y\":%.9f},"
            "\"angle\":%.9f,"
            "\"radius\":%.9f,"
            "\"density\":%.9f,"
            "\"friction\":%.9f,"
            "\"restitution\":%.9f,"
            "\"linearDamping\":%.9f,"
            "\"angularDamping\":%.9f,"
            "\"allowSleep\":%s,"
            "\"fixedRotation\":%s,"
            "\"bullet\":%s,"
            "\"mass\":%.9f,"
            "\"inertia\":%.9f,"
            "\"ingame\":%s"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            traceId,
            player,
            x,
            y,
            angle,
            PUCK_RADIUS,
            fixtureDef.density,
            fixtureDef.friction,
            fixtureDef.restitution,

            body->GetLinearDamping(),
            body->GetAngularDamping(),

            body->IsSleepingAllowed()
            ? "true"
            : "false",

            body->IsFixedRotation()
            ? "true"
            : "false",

            body->IsBullet()
            ? "true"
            : "false",

            body->GetMass(),
            body->GetInertia(),

            puck->ingame
            ? "true"
            : "false"
    );
}

ShufflePuck *ShuffleTable::findPuck(int traceId) {
    for (ShufflePuck *puck: pucks) {
        if (puck && puck->traceId == traceId) {
            return puck;
        }
    }

    return nullptr;
}

void ShuffleTable::movePuck(int traceId, float x, float y, float angle) {
    ShufflePuck *puck = findPuck(traceId);

    if (!puck) {
        return;
    }

    puck->setTransform(x, y, angle);
}

void ShuffleTable::firePuck(int traceId, float shootDirRadians, float dist) {
    ShufflePuck *puck = findPuck(traceId);

    if (!puck || !puck->body) {
        return;
    }

    const b2Vec2 velocityBefore = puck->body->GetLinearVelocity();

    puck->fire(shootDirRadians, dist);

    const b2Vec2 velocityAfter = puck->body->GetLinearVelocity();

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_FIRE={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"traceId\":%d,"
                                                             "\"player\":%d,"
                                                             "\"direction\":%.9f,"
                                                             "\"distance\":%.9f,"
                                                             "\"velocityBefore\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"velocityAfter\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"angleAfter\":%.9f"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, puck->traceId, puck->player, shootDirRadians,
                          dist, velocityBefore.x, velocityBefore.y, velocityAfter.x,
                          velocityAfter.y, puck->body->GetAngle());
}

bool ShuffleTable::update() {
    world.Step(STEP_DT, VELOCITY_ITERATIONS, POSITION_ITERATIONS);

    bool anyMotion = false;

    for (ShufflePuck *puck: pucks) {
        if (!puck || !puck->body) {
            continue;
        }

        puck->updateInGameState();

        logPuckFrame(traceRunId.c_str(), traceShotIndex, traceFrame, tracePhase.c_str(),
                     "afterWorldStep", puck);

        puck->stopSmallMotion();
        puck->writeOutputs();

        if (puck->isMoving()) {
            anyMotion = true;
        }
    }

    return anyMotion;
}

void ShuffleTable::refreshOutputs() {
    for (ShufflePuck *puck: pucks) {
        if (puck) {
            puck->updateInGameState();
            puck->writeOutputs();
        }
    }
}