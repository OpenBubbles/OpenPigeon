#include "GolfTable.h"
#include "GolfBall.h"

#include <algorithm>
#include <android/log.h>
#include <cmath>

static constexpr float BALL_RADIUS = 4.0f;
static constexpr float BALL_DENSITY = 1.0f;
static constexpr float BALL_FRICTION = 0.0f;
static constexpr float BALL_RESTITUTION = 0.50f;

static constexpr float BALL_LINEAR_DAMPING = 1.0f;
static constexpr float BALL_ANGULAR_DAMPING = 0.0f;

static constexpr float IOS_FIXTURE_DENSITY = 1.0f;
static constexpr float IOS_FIXTURE_FRICTION = 0.0f;
static constexpr float IOS_FIXTURE_RESTITUTION = 0.50f;

static constexpr float WALL_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float WALL_FRICTION = IOS_FIXTURE_FRICTION;

static constexpr float OBSTACLE_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float BOUNCY_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float OBSTACLE_FRICTION = IOS_FIXTURE_FRICTION;

static constexpr float BAR_RESTITUTION = IOS_FIXTURE_RESTITUTION;
static constexpr float BAR2_RESTITUTION = IOS_FIXTURE_RESTITUTION;

static constexpr float ROUND2_PHYSICS_HALF_WIDTH_SCALE = 1.0f;
static constexpr float ROUND2_PHYSICS_HALF_HEIGHT_SCALE = 1.0f;

static constexpr float STEP_DT = 1.0f / 60.0f;
static constexpr int VELOCITY_ITERATIONS = 60;
static constexpr int POSITION_ITERATIONS = 60;

static constexpr float PI_F = 3.14159265358979323846f;
static constexpr float DIAGONAL_WALL_THICKNESS = 6.0f;

static constexpr int CELL_OPEN = 0;
static constexpr int CELL_BLOCKED = 1;
static constexpr int CELL_SPECIAL_3 = 3;

static constexpr float SLOPE_VELOCITY_DELTA_PER_STEP = 2.0f;
static constexpr float SLOPE_RECT_WIDTH = 65.0f;
static constexpr float SLOPE_RECT_HEIGHT = 52.0f;

static constexpr float IOS_STOP_LINEAR_SPEED = 1.0f;
static constexpr float IOS_STOP_ANGULAR_SPEED = 0.08f;

static constexpr float SMALL_BAR_PHYSICS_WIDTH = 46.0f;
static constexpr float SMALL_BAR_PHYSICS_HEIGHT = 6.0f;

static constexpr float LARGE_BAR_PHYSICS_WIDTH = 95.0f;
static constexpr float LARGE_BAR_PHYSICS_HEIGHT = 6.0f;

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

static void logFixtureMaterial(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase,
        const char* source,
        int kind,
        const b2FixtureDef& fixtureDef
) {
    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_FIXTURE_MATERIAL={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"%s\","
            "\"kind\":%d,"
            "\"restitution\":%.6f,"
            "\"friction\":%.6f,"
            "\"density\":%.6f,"
            "\"isSensor\":%s,"
            "\"categoryBits\":%u,"
            "\"maskBits\":%u,"
            "\"groupIndex\":%d"
            "}",
            runId ? runId : "",
            shotIndex,
            frame,
            phase ? phase : "",
            source ? source : "",
            kind,
            fixtureDef.restitution,
            fixtureDef.friction,
            fixtureDef.density,
            fixtureDef.isSensor ? "true" : "false",
            static_cast<unsigned>(fixtureDef.filter.categoryBits),
            static_cast<unsigned>(fixtureDef.filter.maskBits),
            static_cast<int>(fixtureDef.filter.groupIndex)
    );
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

static bool nativeCellIsOpenRaw(
        const int* openMask,
        int rows,
        int cols,
        int row,
        int col
) {
    if (!openMask) {
        return false;
    }

    if (row < 0 || row >= rows || col < 0 || col >= cols) {
        return false;
    }

    const int value = openMask[row * cols + col];
    return value == CELL_OPEN || value == CELL_SPECIAL_3;
}

static int nativeCellValueRaw(
        const int* openMask,
        int rows,
        int cols,
        int row,
        int col
) {
    if (!openMask) {
        return CELL_BLOCKED;
    }

    if (row < 0 || row >= rows || col < 0 || col >= cols) {
        return CELL_BLOCKED;
    }

    return openMask[row * cols + col];
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
                const int cellValue = nativeCellValueRaw(openMask, rows, cols, row, col);

                switch (cellValue) {
                    case CELL_BLOCKED:
                        createBlockedCellWall(row, col);
                        break;

                    case CELL_SPECIAL_3:
                        createDiagonalCellWall(row, col, cellValue);
                        break;

                    case CELL_OPEN:
                    default:
                        break;
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

void GolfTable::createDiagonalCellWall(int row, int col, int cellValue) {
    const float x = static_cast<float>(col) * tileSize;
    const float y = static_cast<float>(row) * tileSize;

    /*
     * iOS diagonal/shuffle wall is a polygon fixture, not an edge.
     * The old Android version that worked used a thin rotated box.
     *
     * Raw cell value 3 maps to the old CELL_DIAGONAL_B direction,
     * which used -45 degrees.
     */
    const float halfLength = tileSize * 0.5f * std::sqrt(2.0f);
    const float halfThickness = DIAGONAL_WALL_THICKNESS * 0.5f;
    const float angle = -PI_F * 0.25f;

    createStaticBox(
            x,
            y,
            halfLength,
            halfThickness,
            angle,
            -2,
            WALL_RESTITUTION,
            WALL_FRICTION,
            false
    );

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_DIAGONAL_WALL={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"createDiagonalCellWall_iOSPolygonStrip\","
            "\"row\":%d,"
            "\"col\":%d,"
            "\"cellValue\":%d,"
            "\"shape\":\"rotatedBox\","
            "\"center\":{\"x\":%.6f,\"y\":%.6f},"
            "\"halfLength\":%.6f,"
            "\"halfThickness\":%.6f,"
            "\"angle\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            row,
            col,
            cellValue,
            x,
            y,
            halfLength,
            halfThickness,
            angle
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

void GolfTable::createStaticCircle(
        float x,
        float y,
        float radius,
        int kind,
        float restitution,
        float friction,
        bool bouncy
) {
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
    fixtureDef.density = IOS_FIXTURE_DENSITY;

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

    logFixtureMaterial(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticCircle",
            kind,
            fixtureDef
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{
            kind < 0 ? GolfData::Type::Wall : GolfData::Type::Obstacle,
            kind,
            body,
            bouncy
    };

    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createWallTriangle(
        const char* source,
        int row,
        int col,
        int cellValue,
        const b2Vec2& a,
        const b2Vec2& b,
        const b2Vec2& c
) {
    b2Vec2 vertices[3] = {a, b, c};

    b2BodyDef bodyDef;
    applyIosBodyDefaults(bodyDef);
    bodyDef.type = b2_staticBody;
    bodyDef.position.Set(0.0f, 0.0f);

    b2Body* body = world.CreateBody(&bodyDef);

    b2PolygonShape shape;
    shape.Set(vertices, 3);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.restitution = WALL_RESTITUTION;
    fixtureDef.friction = WALL_FRICTION;
    fixtureDef.density = IOS_FIXTURE_DENSITY;

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_DIAGONAL_WALL={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"source\":\"%s\","
            "\"row\":%d,"
            "\"col\":%d,"
            "\"cellValue\":%d,"
            "\"shape\":\"triangle\","
            "\"vertices\":["
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f},"
            "{\"x\":%.6f,\"y\":%.6f}"
            "]"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            source ? source : "",
            row,
            col,
            cellValue,
            vertices[0].x,
            vertices[0].y,
            vertices[1].x,
            vertices[1].y,
            vertices[2].x,
            vertices[2].y
    );

    logFixtureMaterial(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            source ? source : "createWallTriangle",
            -2,
            fixtureDef
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData(
            GolfData::Type::Wall,
            -2,
            body,
            false
    );

    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createSpecialValue3Cut(const int* openMask, int row, int col) {
    const float x = static_cast<float>(col) * tileSize;
    const float y = static_cast<float>(row) * tileSize;
    const float h = tileSize * 0.5f;

    const b2Vec2 topLeft(x - h, y - h);
    const b2Vec2 topRight(x + h, y - h);
    const b2Vec2 bottomRight(x + h, y + h);
    const b2Vec2 bottomLeft(x - h, y + h);

    const bool topBlocked = !nativeCellIsOpenRaw(openMask, rows, cols, row - 1, col);
    const bool bottomBlocked = !nativeCellIsOpenRaw(openMask, rows, cols, row + 1, col);
    const bool leftBlocked = !nativeCellIsOpenRaw(openMask, rows, cols, row, col - 1);
    const bool rightBlocked = !nativeCellIsOpenRaw(openMask, rows, cols, row, col + 1);

    if (topBlocked && leftBlocked) {
        createWallTriangle(
                "specialValue3Cut_TOP_LEFT",
                row,
                col,
                CELL_SPECIAL_3,
                topLeft,
                topRight,
                bottomLeft
        );
    } else if (topBlocked && rightBlocked) {
        createWallTriangle(
                "specialValue3Cut_TOP_RIGHT",
                row,
                col,
                CELL_SPECIAL_3,
                topLeft,
                topRight,
                bottomRight
        );
    } else if (bottomBlocked && leftBlocked) {
        createWallTriangle(
                "specialValue3Cut_BOTTOM_LEFT",
                row,
                col,
                CELL_SPECIAL_3,
                topLeft,
                bottomLeft,
                bottomRight
        );
    } else if (bottomBlocked && rightBlocked) {
        createWallTriangle(
                "specialValue3Cut_BOTTOM_RIGHT",
                row,
                col,
                CELL_SPECIAL_3,
                topRight,
                bottomRight,
                bottomLeft
        );
    } else {
        createWallTriangle(
                "specialValue3Cut_FALLBACK_BOTTOM_LEFT",
                row,
                col,
                CELL_SPECIAL_3,
                topLeft,
                bottomLeft,
                bottomRight
        );
    }
}

void GolfTable::createImplicitDiagonalCornerCut(const int* openMask, int row, int col) {
    const bool tl = nativeCellIsOpenRaw(openMask, rows, cols, row, col);
    const bool tr = nativeCellIsOpenRaw(openMask, rows, cols, row, col + 1);
    const bool bl = nativeCellIsOpenRaw(openMask, rows, cols, row + 1, col);
    const bool br = nativeCellIsOpenRaw(openMask, rows, cols, row + 1, col + 1);

    const b2Vec2 tlCenter(
            static_cast<float>(col) * tileSize,
            static_cast<float>(row) * tileSize
    );

    const b2Vec2 trCenter(
            static_cast<float>(col + 1) * tileSize,
            static_cast<float>(row) * tileSize
    );

    const b2Vec2 blCenter(
            static_cast<float>(col) * tileSize,
            static_cast<float>(row + 1) * tileSize
    );

    const b2Vec2 brCenter(
            static_cast<float>(col + 1) * tileSize,
            static_cast<float>(row + 1) * tileSize
    );

    const b2Vec2 shared(
            (tlCenter.x + trCenter.x + blCenter.x + brCenter.x) * 0.25f,
            (tlCenter.y + trCenter.y + blCenter.y + brCenter.y) * 0.25f
    );

    if (!tl) {
        createWallTriangle(
                "implicitDiagonalCut_missing_TL",
                row,
                col,
                -3,
                trCenter,
                shared,
                blCenter
        );
    } else if (!tr) {
        createWallTriangle(
                "implicitDiagonalCut_missing_TR",
                row,
                col,
                -3,
                tlCenter,
                shared,
                brCenter
        );
    } else if (!bl) {
        createWallTriangle(
                "implicitDiagonalCut_missing_BL",
                row,
                col,
                -3,
                tlCenter,
                shared,
                brCenter
        );
    } else if (!br) {
        createWallTriangle(
                "implicitDiagonalCut_missing_BR",
                row,
                col,
                -3,
                trCenter,
                shared,
                blCenter
        );
    }
}

void GolfTable::createStaticBox(
        float x,
        float y,
        float halfW,
        float halfH,
        float angle,
        int kind,
        float restitution,
        float friction,
        bool bouncy
) {
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
    fixtureDef.density = IOS_FIXTURE_DENSITY;

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

    logFixtureMaterial(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticBox",
            kind,
            fixtureDef
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{
            kind < 0 ? GolfData::Type::Wall : GolfData::Type::Obstacle,
            kind,
            body,
            bouncy
    };

    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createStaticTriangle(
        float x,
        float y,
        float width,
        float height,
        float angle,
        int kind,
        float restitution,
        float friction,
        bool bouncy
) {
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
    bodyDef.position.Set(0.0f, 0.0f);

    b2Body* body = world.CreateBody(&bodyDef);

    b2PolygonShape shape;
    shape.Set(worldVertices, 3);

    b2FixtureDef fixtureDef;
    fixtureDef.shape = &shape;
    applyIosFixtureDefaults(fixtureDef);
    fixtureDef.restitution = restitution;
    fixtureDef.friction = friction;
    fixtureDef.density = IOS_FIXTURE_DENSITY;

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

    logFixtureMaterial(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "createStaticTriangle",
            kind,
            fixtureDef
    );

    body->CreateFixture(&fixtureDef);

    auto* data = new GolfData{
            GolfData::Type::Obstacle,
            kind,
            body,
            bouncy
    };

    body->SetUserData(data);
    staticBodies.push_back({body, data});
}

void GolfTable::createCross(
        float x,
        float y,
        float width,
        float height,
        float angle,
        int kind,
        float restitution,
        float friction,
        bool bouncy
) {
    const float armLength = width;
    const float armThickness = height * 0.25f;

    createStaticBox(
            x,
            y,
            armLength * 0.5f,
            armThickness * 0.5f,
            angle,
            kind,
            restitution,
            friction,
            bouncy
    );

    createStaticBox(
            x,
            y,
            armLength * 0.5f,
            armThickness * 0.5f,
            angle + PI_F * 0.5f,
            kind,
            restitution,
            friction,
            bouncy
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
            createStaticCircle(
                    obstacle.x,
                    obstacle.y,
                    std::min(width, height) * 0.5f,
                    obstacle.kind,
                    restitution,
                    friction,
                    obstacle.bouncy
            );
            break;

        case Round2:
            createStaticBox(
                    obstacle.x,
                    obstacle.y,
                    width * 0.5f * ROUND2_PHYSICS_HALF_WIDTH_SCALE,
                    height * 0.5f * ROUND2_PHYSICS_HALF_HEIGHT_SCALE,
                    obstacle.rotation,
                    obstacle.kind,
                    restitution,
                    friction,
                    obstacle.bouncy
            );
            break;

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
                    friction,
                    obstacle.bouncy
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
                    friction,
                    obstacle.bouncy
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
                    friction,
                    obstacle.bouncy
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

    logFixtureMaterial(
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            "makeBall",
            0,
            fixtureDef
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

bool GolfTable::applySlopesPostStep(const b2Vec2& slopeSamplePos) {
    if (!ball || !ball->body) {
        return false;
    }

    bool onSlope = false;

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

        onSlope = true;

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

    return onSlope;
}

void GolfTable::stopSmallMotion(bool onSlope) {
    if (!ball || !ball->body) {
        return;
    }

    if (onSlope) {
        ball->body->SetAwake(true);
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

    const bool onSlope = applySlopesPostStep(beforePos);
    stopSmallMotion(onSlope);

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
            "\"speed\":%.6f,"
            "\"onSlope\":%s"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            afterPos.x,
            afterPos.y,
            afterVel.x,
            afterVel.y,
            afterVel.Length(),
            onSlope ? "true" : "false"
    );

    const bool moving = ball->step();

    return moving || onSlope;
}


void GolfTable::refreshOutputs() {
    if (ball) {
        ball->step();
    }
}
