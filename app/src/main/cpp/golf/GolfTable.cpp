#include "GolfTable.h"
#include <algorithm>
#include <android/log.h>
#include <cmath>

static constexpr float BALL_RADIUS = 4.0f;
static constexpr float BALL_DENSITY = 1.0f;
static constexpr float BALL_FRICTION = 0.0f;
static constexpr float BALL_RESTITUTION = 0.50f;

// iOS b2BodyDef shows linearDamping = 1.0f for the ball path.
static constexpr float BALL_LINEAR_DAMPING = 1.0f;
static constexpr float BALL_ANGULAR_DAMPING = 0.0f;

// iOS makeFixture / makeFixture2 / makeFixture3 all show this:
// friction = 0.0
// restitution = 0.5
// density = 1.0
// isSensor = false
static constexpr float IOS_FIXTURE_DENSITY = 1.0f;
static constexpr float IOS_FIXTURE_FRICTION = 0.0f;
static constexpr float IOS_FIXTURE_RESTITUTION = 0.50f;

static constexpr float WALL_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float WALL_FRICTION = IOS_FIXTURE_FRICTION;

static constexpr float OBSTACLE_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float OBSTACLE_FRICTION = IOS_FIXTURE_FRICTION;

// Keep bouncy at iOS fixture default until we prove GolfBouncy has a different fixture path.
static constexpr float BOUNCY_RESTITUTION = IOS_FIXTURE_RESTITUTION;

// Bars are NOT special restitution-wise. The binary fixture helpers show 0.5.
static constexpr float BAR_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float BAR2_RESTITUTION = IOS_FIXTURE_RESTITUTION;

static constexpr float STEP_DT = 1.0f / 60.0f;
static constexpr int VELOCITY_ITERATIONS = 60;
static constexpr int POSITION_ITERATIONS = 60;

/*
 * iOS update order:
 *   1. b2World::Step(1/60, 60, 60)
 *   2. check slopes
 *   3. directly add slope vector * 2.0 to the body's velocity
 *
 * Do not apply slopes as a pre-step Box2D force.
 */
static constexpr float SLOPE_VELOCITY_DELTA_PER_STEP = 2.0f;
static constexpr float SLOPE_RECT_WIDTH = 65.0f;
static constexpr float SLOPE_RECT_HEIGHT = 52.0f;

/*
 * iOS clears tiny motion after frame rules.
 */
static constexpr float IOS_STOP_LINEAR_SPEED = 1.0f;
static constexpr float IOS_STOP_ANGULAR_SPEED = 0.08f;

static constexpr float SMALL_BAR_PHYSICS_WIDTH = 46.0f;
static constexpr float SMALL_BAR_PHYSICS_HEIGHT = 6.0f;

static constexpr float LARGE_BAR_PHYSICS_WIDTH = 95.0f;
static constexpr float LARGE_BAR_PHYSICS_HEIGHT = 6.0f;

static constexpr float ROUND2_PHYSICS_HALF_WIDTH_SCALE = 1.0f;
static constexpr float ROUND2_PHYSICS_HALF_HEIGHT_SCALE = 1.0f;

static constexpr float OUTER_WALL_THICKNESS = 65.0f;

static void applyIosBodyDefaults(b2BodyDef& def) {
    def.position.Set(0.0f, 0.0f);
    def.angle = 0.0f;
    def.linearVelocity.Set(0.0f, 0.0f);
    def.angularVelocity = 0.0f;
    def.linearDamping = BALL_LINEAR_DAMPING;
    def.angularDamping = BALL_ANGULAR_DAMPING;
    def.allowSleep = false;
    def.awake = true;
    def.fixedRotation = true;
    def.bullet = true;
    def.active = true;
}

static void applyIosFixtureDefaults(b2FixtureDef& fixtureDef) {
    fixtureDef.density = IOS_FIXTURE_DENSITY;
    fixtureDef.friction = IOS_FIXTURE_FRICTION;
    fixtureDef.restitution = IOS_FIXTURE_RESTITUTION;
    fixtureDef.isSensor = false;

    fixtureDef.filter.categoryBits = 0x0001;
    fixtureDef.filter.maskBits = 0xffff;
    fixtureDef.filter.groupIndex = 0;
}

static const char* ownerTypeForKind(int kind) {
    return kind < 0 ? "wall" : "obstacle";
}

static void logBoxFixture(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase,
        const char* source,
        const char* ownerType,
        float x,
        float y,
        float halfW,
        float halfH,
        float angle,
        int kind
) {
    const float c = std::cos(angle);
    const float s = std::sin(angle);

    const float localX[4] = {-halfW, halfW, halfW, -halfW};
    const float localY[4] = {-halfH, -halfH, halfH, halfH};

    float vx[4];
    float vy[4];

    for (int i = 0; i < 4; ++i) {
        vx[i] = x + localX[i] * c - localY[i] * s;
        vy[i] = y + localX[i] * s + localY[i] * c;
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_FIXTURE={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"%s\","
            "\"shape\":\"box\","
            "\"ownerType\":\"%s\","
            "\"kind\":%d,"
            "\"center\":{\"x\":%.6f,\"y\":%.6f},"
            "\"halfW\":%.6f,"
            "\"halfH\":%.6f,"
            "\"width\":%.6f,"
            "\"height\":%.6f,"
            "\"angle\":%.6f,"
            "\"vertices\":["
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f}"
            "]"
            "}",
            runId ? runId : "",
            shotIndex,
            frame,
            phase ? phase : "",
            source ? source : "",
            ownerType ? ownerType : "",
            kind,
            x,
            y,
            halfW,
            halfH,
            halfW * 2.0f,
            halfH * 2.0f,
            angle,
            vx[0], vy[0],
            vx[1], vy[1],
            vx[2], vy[2],
            vx[3], vy[3]
    );
}

static void logCircleFixture(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase,
        const char* source,
        const char* ownerType,
        float x,
        float y,
        float radius,
        int kind
) {
    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_FIXTURE={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"%s\","
            "\"shape\":\"circle\","
            "\"ownerType\":\"%s\","
            "\"kind\":%d,"
            "\"center\":{\"x\":%.6f,\"y\":%.6f},"
            "\"radius\":%.6f"
            "}",
            runId ? runId : "",
            shotIndex,
            frame,
            phase ? phase : "",
            source ? source : "",
            ownerType ? ownerType : "",
            kind,
            x,
            y,
            radius
    );
}

static void logTriangleFixture(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase,
        const char* source,
        float x,
        float y,
        float width,
        float height,
        float angle,
        int kind,
        const b2Vec2* vertices
) {
    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_FIXTURE={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"%s\","
            "\"shape\":\"triangle\","
            "\"ownerType\":\"obstacle\","
            "\"kind\":%d,"
            "\"center\":{\"x\":%.6f,\"y\":%.6f},"
            "\"width\":%.6f,"
            "\"height\":%.6f,"
            "\"angle\":%.6f,"
            "\"vertices\":["
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f}"
            "]"
            "}",
            runId ? runId : "",
            shotIndex,
            frame,
            phase ? phase : "",
            source ? source : "",
            kind,
            x,
            y,
            width,
            height,
            angle,
            vertices[0].x, vertices[0].y,
            vertices[1].x, vertices[1].y,
            vertices[2].x, vertices[2].y
    );
}

GolfTable::GolfTable()
        : world(b2Vec2_zero) {
    world.SetContactListener(&contactListener);
}

GolfTable::~GolfTable() {
    clearBall();
    clearStaticBodies();
}

void GolfTable::setTraceContext(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase
) {
    traceRunId = runId ? runId : "";
    traceShotIndex = shotIndex;
    traceFrame = frame;
    tracePhase = phase ? phase : "";

    contactListener.setTraceContext(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str()
    );
}

void GolfTable::clearTraceContext() {
    traceRunId.clear();
    traceShotIndex = -1;
    traceFrame = -1;
    tracePhase.clear();

    contactListener.clearTraceContext();
}

void GolfTable::destroyBody(b2Body* body) {
    if (body) {
        world.DestroyBody(body);
    }
}

void GolfTable::clearBall() {
    delete ball;
    ball = nullptr;
}

void GolfTable::clearStaticBodies() {
    for (const StaticBodyRecord& record : staticBodies) {
        if (record.body) {
            world.DestroyBody(record.body);
        }
        delete record.data;
    }

    staticBodies.clear();
}

void GolfTable::configureMap(
        float newTileSize,
        float newMapSize,
        int newRows,
        int newCols,
        const int* openMask,
        const GolfObstacleInput* obstacles,
        int obstacleCount,
        const GolfSlopeInput* slopeInputs,
        int slopeCount
) {
    tileSize = newTileSize > 0.0f ? newTileSize : 65.0f;
    mapSize = newMapSize > 0.0f ? newMapSize : tileSize * std::max(newRows, newCols);
    rows = std::max(0, newRows);
    cols = std::max(0, newCols);

    clearStaticBodies();
    slopes.clear();

    if (openMask && rows > 0 && cols > 0) {
        for (int row = 0; row < rows; ++row) {
            for (int col = 0; col < cols; ++col) {
                const int open = openMask[row * cols + col];
                if (open == 0) {
                    createBlockedCellWall(row, col);
                }
            }
        }
    }

    createBoundaryWalls();

    for (int i = 0; i < obstacleCount; ++i) {
        createObstacle(obstacles[i]);
    }

    slopes.reserve(std::max(0, slopeCount));
    for (int i = 0; i < slopeCount; ++i) {
        slopes.push_back({
            slopeInputs[i].x,
            slopeInputs[i].y,
            slopeInputs[i].vx,
            slopeInputs[i].vy,
            slopeInputs[i].rotation
        });
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "configureMap rows=%d cols=%d obstacles=%d slopes=%d tile=%f mapSize=%f",
            rows,
            cols,
            obstacleCount,
            slopeCount,
            tileSize,
            mapSize
    );
}

void GolfTable::createBlockedCellWall(int row, int col) {
    const float x = static_cast<float>(col) * tileSize;
    const float y = static_cast<float>(row) * tileSize;

    createStaticBox(
            x,
            y,
            tileSize * 0.5f,
            tileSize * 0.5f,
            0.0f,
            -1,
            WALL_RESTITUTION,
            WALL_FRICTION
    );
}

void GolfTable::createBoundaryWalls() {
    const float halfTile = tileSize * 0.5f;

    const float minX = -halfTile;
    const float maxX =
            cols > 0
            ? (static_cast<float>(cols - 1) * tileSize) + halfTile
            : mapSize + halfTile;

    const float minY = -halfTile;
    const float maxY =
            rows > 0
            ? (static_cast<float>(rows - 1) * tileSize) + halfTile
            : mapSize + halfTile;

    const float centerX = (minX + maxX) * 0.5f;
    const float centerY = (minY + maxY) * 0.5f;

    const float halfW = (maxX - minX) * 0.5f;
    const float halfH = (maxY - minY) * 0.5f;

    const float t = OUTER_WALL_THICKNESS;

    createStaticBox(
            centerX,
            minY - t,
            halfW + t * 2.0f,
            t,
            0.0f,
            -1,
            WALL_RESTITUTION,
            WALL_FRICTION
    );

    createStaticBox(
            centerX,
            maxY + t,
            halfW + t * 2.0f,
            t,
            0.0f,
            -1,
            WALL_RESTITUTION,
            WALL_FRICTION
    );

    createStaticBox(
            minX - t,
            centerY,
            t,
            halfH + t * 2.0f,
            0.0f,
            -1,
            WALL_RESTITUTION,
            WALL_FRICTION
    );

    createStaticBox(
            maxX + t,
            centerY,
            t,
            halfH + t * 2.0f,
            0.0f,
            -1,
            WALL_RESTITUTION,
            WALL_FRICTION
    );
}

void GolfTable::createStaticCircle(float x, float y, float radius, int kind, float restitution, float friction) {
    b2BodyDef bodyDef;
    applyIosBodyDefaults(bodyDef);
    bodyDef.type = b2_staticBody;
    bodyDef.position.Set(x, y);

    b2Body* body = world.CreateBody(&bodyDef);

    b2CircleShape shape;
    shape.m_radius = radius;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.restitution = restitution;
    fixtureDef.friction = friction;

    logCircleFixture(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticCircle",
            ownerTypeForKind(kind),
            x,
            y,
            radius,
            kind
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{GolfData::Type::Obstacle, kind, body};
    body->SetUserData(data);

    staticBodies.push_back({body, data});
}

void GolfTable::createStaticBox(float x, float y, float halfW, float halfH, float angle, int kind, float restitution, float friction) {
    b2BodyDef bodyDef;
    applyIosBodyDefaults(bodyDef);
    bodyDef.type = b2_staticBody;
    bodyDef.position.Set(0.0f, 0.0f);

    b2Body* body = world.CreateBody(&bodyDef);

    b2PolygonShape shape;
    shape.SetAsBox(halfW, halfH, b2Vec2(x, y), angle);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.restitution = restitution;
    fixtureDef.friction = friction;

    logBoxFixture(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticBox",
            ownerTypeForKind(kind),
            x,
            y,
            halfW,
            halfH,
            angle,
            kind
    );

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_FIXTURE_MATERIAL={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"createStaticBox\","
            "\"kind\":%d,"
            "\"restitution\":%.6f,"
            "\"friction\":%.6f,"
            "\"density\":%.6f,"
            "\"isSensor\":%s,"
            "\"categoryBits\":%u,"
            "\"maskBits\":%u,"
            "\"groupIndex\":%d"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            kind,
            fixtureDef.restitution,
            fixtureDef.friction,
            fixtureDef.density,
            fixtureDef.isSensor ? "true" : "false",
            fixtureDef.filter.categoryBits,
            fixtureDef.filter.maskBits,
            fixtureDef.filter.groupIndex
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{
            kind < 0 ? GolfData::Type::Wall : GolfData::Type::Obstacle,
            kind,
            body
    };

    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createStaticTriangle(float x, float y, float width, float height, float angle, int kind, float restitution, float friction) {
    const float halfW = width * 0.5f;
    const float halfH = height * 0.5f;

    b2Vec2 local[3] = {
            b2Vec2(-halfW, -halfH),
            b2Vec2( halfW,  halfH),
            b2Vec2( halfW, -halfH)
    };

    const float c = std::cos(angle);
    const float s = std::sin(angle);

    b2Vec2 worldVertices[3];
    for (int i = 0; i < 3; ++i) {
        const float lx = local[i].x;
        const float ly = local[i].y;
        worldVertices[i].Set(
                x + lx * c - ly * s,
                y + lx * s + ly * c
        );
    }

    b2BodyDef bodyDef;
    applyIosBodyDefaults(bodyDef);
    bodyDef.type = b2_staticBody;

    b2Body* body = world.CreateBody(&bodyDef);

    b2PolygonShape shape;
    shape.Set(worldVertices, 3);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.restitution = restitution;
    fixtureDef.friction = friction;

    logTriangleFixture(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticTriangle",
            x,
            y,
            width,
            height,
            angle,
            kind,
            worldVertices
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{GolfData::Type::Obstacle, kind, body};
    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createCross(float x, float y, float width, float height, float angle, int kind, float restitution, float friction) {
    const float minSide = std::min(width, height);
    const float armThickness = std::max(12.0f, std::min(18.0f, minSide * 0.17f));

    createStaticBox(
            x,
            y,
            width * 0.5f,
            armThickness * 0.5f,
            angle,
            kind,
            restitution,
            friction
    );

    createStaticBox(
            x,
            y,
            armThickness * 0.5f,
            height * 0.5f,
            angle,
            kind,
            restitution,
            friction
    );
}

void GolfTable::createObstacle(const GolfObstacleInput& obstacle) {
    float width = 30.0f;
    float height = 30.0f;

    switch (obstacle.kind) {
        case Square:
            width = 30.0f;
            height = 30.0f;
            break;

        case Square2:
            width = 70.0f;
            height = 70.0f;
            break;

        case Bar:
            width = SMALL_BAR_PHYSICS_WIDTH;
            height = SMALL_BAR_PHYSICS_HEIGHT;
            break;

        case Bar2:
            width = LARGE_BAR_PHYSICS_WIDTH;
            height = LARGE_BAR_PHYSICS_HEIGHT;
            break;

        case Round:
            width = 37.0f;
            height = 37.0f;
            break;

        case Round2:
            width = 72.0f;
            height = 72.0f;
            break;

        case Triangle:
            width = 30.0f;
            height = 30.0f;
            break;

        case Triangle2:
            width = 70.0f;
            height = 70.0f;
            break;

        case Cross:
            width = 95.0f;
            height = 95.0f;
            break;

        default:
            width = 30.0f;
            height = 30.0f;
            break;
    }

    width *= obstacle.scale;
    height *= obstacle.scale;

    float restitution = obstacle.bouncy
                        ? BOUNCY_RESTITUTION
                        : OBSTACLE_RESTITUTION;

    float friction = OBSTACLE_FRICTION;

    switch (obstacle.kind) {
        case Bar:
            restitution = BAR_RESTITUTION;
            break;

        case Bar2:
            restitution = BAR2_RESTITUTION;
            break;

        default:
            break;
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_OBSTACLE_FIXTURE_INPUT={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"kind\":%d,"
            "\"bouncy\":%s,"
            "\"x\":%.6f,"
            "\"y\":%.6f,"
            "\"rotation\":%.6f,"
            "\"scale\":%.6f,"
            "\"width\":%.6f,"
            "\"height\":%.6f,"
            "\"restitution\":%.6f,"
            "\"friction\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            obstacle.kind,
            obstacle.bouncy ? "true" : "false",
            obstacle.x,
            obstacle.y,
            obstacle.rotation,
            obstacle.scale,
            width,
            height,
            restitution,
            friction
    );

    switch (obstacle.kind) {
        case Round:
            createStaticBox(
                    obstacle.x,
                    obstacle.y,
                    width * 0.5f,
                    height * 0.5f,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction
            );
            break;

        case Round2: {
            const float halfW =
                    width * 0.5f * ROUND2_PHYSICS_HALF_WIDTH_SCALE;

            const float halfH =
                    height * 0.5f * ROUND2_PHYSICS_HALF_HEIGHT_SCALE;

            createStaticBox(
                    obstacle.x,
                    obstacle.y,
                    halfW,
                    halfH,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction
            );

            __android_log_print(
                    ANDROID_LOG_INFO,
                    "GolfNative",
                    "GOLF_NATIVE_ROUND2_FIXTURE={"
                    "\"x\":%.6f,"
                    "\"y\":%.6f,"
                    "\"visualRotation\":%.6f,"
                    "\"halfW\":%.6f,"
                    "\"halfH\":%.6f,"
                    "\"restitution\":%.6f,"
                    "\"friction\":%.6f"
                    "}",
                    obstacle.x,
                    obstacle.y,
                    obstacle.rotation,
                    halfW,
                    halfH,
                    restitution,
                    friction
            );

            break;
        }

        case Triangle:
        case Triangle2:
            createStaticTriangle(
                    obstacle.x,
                    obstacle.y,
                    width,
                    height,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction
            );
            break;

        case Cross:
            createCross(
                    obstacle.x,
                    obstacle.y,
                    width,
                    height,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction
            );
            break;

        default:
            createStaticBox(
                    obstacle.x,
                    obstacle.y,
                    width * 0.5f,
                    height * 0.5f,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction
            );
            break;
    }
}

void GolfTable::makeBall(float x, float y, float* outputs) {

    clearBall();

    b2BodyDef def;
    applyIosBodyDefaults(def);
    def.type = b2_dynamicBody;
    def.position.Set(0.0f, 0.0f);

    b2Body* body = world.CreateBody(&def);

    b2CircleShape shape;
    shape.m_radius = BALL_RADIUS;

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.density = BALL_DENSITY;
    fixtureDef.friction = BALL_FRICTION;
    fixtureDef.restitution = BALL_RESTITUTION;

    logCircleFixture(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "makeBall",
            "ball",
            x,
            y,
            BALL_RADIUS,
            0
    );

    body->CreateFixture(&fixtureDef);

    ball = new GolfBall(this, body, outputs);
    body->SetTransform(b2Vec2(x, y), 0.0f);
    body->SetAwake(true);
    ball->step();

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "makeBall x=%f y=%f radius=%f mass=%f inertia=%f",
            x,
            y,
            BALL_RADIUS,
            body->GetMass(),
            body->GetInertia()
    );
}

void GolfTable::setBallState(float x, float y, float vx, float vy) {

    if (!ball) {
        return;
    }

    ball->setState(x, y, vx, vy);
}

void GolfTable::fireBall(float directionRadians, float power) {

    if (!ball) {
        return;
    }

    ball->fire(directionRadians, power);
}

void GolfTable::applySlopesPostStep(const b2Vec2& slopeSamplePos) {
    if (!ball || !ball->body) {
        return;
    }

    /*
     * iOS checks slope overlap using the visual/body position from before
     * this frame refresh, then writes velocity after b2World::Step.
     */
    for (const SlopeRecord& slope : slopes) {
        const float dx = slopeSamplePos.x - slope.x;
        const float dy = slopeSamplePos.y - slope.y;

        const float c = std::cos(slope.rotation);
        const float s = std::sin(slope.rotation);

        const float localX = dx * c + dy * s;
        const float localY = -dx * s + dy * c;

        const float halfW = SLOPE_RECT_WIDTH * 0.5f;
        const float halfH = SLOPE_RECT_HEIGHT * 0.5f;

        if (std::fabs(localX) > halfW || std::fabs(localY) > halfH) {
            continue;
        }

        const b2Vec2 oldVel = ball->body->GetLinearVelocity();

        const b2Vec2 delta(
                slope.vx * SLOPE_VELOCITY_DELTA_PER_STEP,
                slope.vy * SLOPE_VELOCITY_DELTA_PER_STEP
        );

        const b2Vec2 newVel = oldVel + delta;

        __android_log_print(
                ANDROID_LOG_INFO,
                "GolfNative",
                "GOLF_ANDROID_SLOPE={"
                "\"runId\":\"%s\","
                "\"shotIndex\":%d,"
                "\"frame\":%d,"
                "\"phase\":\"postWorldStep\","
                "\"timing\":\"postWorldStep\","
                "\"slopeCenter\":{\"x\":%.6f,\"y\":%.6f},"
                "\"slopeVector\":{\"x\":%.6f,\"y\":%.6f},"
                "\"rotation\":%.6f,"
                "\"samplePos\":{\"x\":%.6f,\"y\":%.6f},"
                "\"local\":{\"x\":%.6f,\"y\":%.6f},"
                "\"halfW\":%.6f,"
                "\"halfH\":%.6f,"
                "\"oldVel\":{\"x\":%.6f,\"y\":%.6f},"
                "\"velocityDelta\":{\"x\":%.6f,\"y\":%.6f},"
                "\"newVel\":{\"x\":%.6f,\"y\":%.6f}"
                "}",
                traceRunId.c_str(),
                traceShotIndex,
                traceFrame,
                slope.x,
                slope.y,
                slope.vx,
                slope.vy,
                slope.rotation,
                slopeSamplePos.x,
                slopeSamplePos.y,
                localX,
                localY,
                halfW,
                halfH,
                oldVel.x,
                oldVel.y,
                delta.x,
                delta.y,
                newVel.x,
                newVel.y
        );

        ball->body->SetAwake(true);
        ball->body->SetLinearVelocity(newVel);
    }
}

void GolfTable::stopSmallMotion() {
    if (!ball || !ball->body) {
        return;
    }

    const b2Vec2 vel = ball->body->GetLinearVelocity();

    if (vel.Length() < IOS_STOP_LINEAR_SPEED) {
        ball->body->SetLinearVelocity(b2Vec2_zero);
    }

    const float angularVelocity = ball->body->GetAngularVelocity();

    if (std::fabs(angularVelocity) < IOS_STOP_ANGULAR_SPEED) {
        ball->body->SetAngularVelocity(0.0f);
    }
}

bool GolfTable::update(float dtSeconds) {
    (void) dtSeconds;

    if (!ball || !ball->body) {
        return false;
    }

    /*
     * iOS uses fixed stepping:
     *   dt = 1/60
     *   velocityIterations = 60
     *   positionIterations = 60
     */
    const b2Vec2 beforePos = ball->body->GetPosition();
    const b2Vec2 beforeVel = ball->body->GetLinearVelocity();

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_NATIVE_STEP={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"beforeNativeStep\","
            "\"pos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"vel\":{\"x\":%.6f,\"y\":%.6f},"
            "\"speed\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            beforePos.x,
            beforePos.y,
            beforeVel.x,
            beforeVel.y,
            beforeVel.Length()
    );

    world.Step(STEP_DT, VELOCITY_ITERATIONS, POSITION_ITERATIONS);

    const b2Vec2 afterWorldPos = ball->body->GetPosition();
    const b2Vec2 afterWorldVel = ball->body->GetLinearVelocity();

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_NATIVE_STEP={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"afterWorldStep\","
            "\"pos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"vel\":{\"x\":%.6f,\"y\":%.6f},"
            "\"speed\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            afterWorldPos.x,
            afterWorldPos.y,
            afterWorldVel.x,
            afterWorldVel.y,
            afterWorldVel.Length()
    );

    /*
     * iOS slope behavior happens after b2World::Step.
     * Use beforePos as the visual/sample position for this frame.
     */
    applySlopesPostStep(beforePos);

    /*
     * iOS zeroes tiny velocities after frame logic.
     */
    stopSmallMotion();

    const b2Vec2 afterPos = ball->body->GetPosition();
    const b2Vec2 afterVel = ball->body->GetLinearVelocity();

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_NATIVE_STEP={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"afterNativeStep\","
            "\"pos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"vel\":{\"x\":%.6f,\"y\":%.6f},"
            "\"speed\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            afterPos.x,
            afterPos.y,
            afterVel.x,
            afterVel.y,
            afterVel.Length()
    );

    return ball->step();
}

void GolfTable::refreshOutputs() {
    if (ball) {
        ball->step();
    }
}
