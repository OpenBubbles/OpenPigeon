#ifndef OPENBUBBLES_GOLF_TABLE_H
#define OPENBUBBLES_GOLF_TABLE_H

#include <Box2D/Box2D.h>
#include <string>
#include <vector>

#include "GolfContactListener.h"
#include "GolfData.h"

class GolfBall;

struct GolfObstacleInput {
    float x;
    float y;
    float rotation;
    float scale;
    int kind;
    bool bouncy;
};

struct GolfSlopeInput {
    float x;
    float y;
    float vx;
    float vy;
    float rotation;
};

class GolfTable {
public:
    enum ObstacleKind {
        Square = 0,
        Square2 = 1,
        Bar = 2,
        Bar2 = 3,
        Round = 4,
        Round2 = 5,
        Triangle = 6,
        Triangle2 = 7,
        Cross = 8
    };

    GolfTable();
    ~GolfTable();

    void configureMap(
            float tileSize,
            float mapSize,
            int rows,
            int cols,
            const int* openMask,
            const GolfObstacleInput* obstacles,
            int obstacleCount,
            const GolfSlopeInput* slopes,
            int slopeCount
    );

    void makeBall(float x, float y, float* outputs);
    void setBallState(float x, float y, float vx, float vy);
    void fireBall(float directionRadians, float power);
    bool update(float dtSeconds);

    void refreshOutputs();
    void destroyBody(b2Body* body);

    void setTraceContext(
            const char* runId,
            int shotIndex,
            int frame,
            const char* phase
    );

    void clearTraceContext();

private:
    struct StaticBodyRecord {
        b2Body* body;
        GolfData* data;
    };

    struct SlopeRecord {
        float x;
        float y;
        float vx;
        float vy;
        float rotation;
    };

    void clearBall();
    void clearStaticBodies();

    void createBlockedCellWall(int row, int col);
    void createBoundaryWalls();
    void createDiagonalCellWall(int row, int col, int cellValue);

    void createSpecialValue3Cut(const int* openMask, int row, int col);
    void createImplicitDiagonalCornerCut(const int* openMask, int row, int col);

    void createWallTriangle(
            const char* source,
            int row,
            int col,
            int cellValue,
            const b2Vec2& a,
            const b2Vec2& b,
            const b2Vec2& c
    );

    void createStaticCircle(
            float x,
            float y,
            float radius,
            int kind,
            float restitution,
            float friction,
            bool bouncy = false
    );

    void createStaticBox(
            float x,
            float y,
            float halfW,
            float halfH,
            float angle,
            int kind,
            float restitution,
            float friction,
            bool bouncy = false
    );

    void createStaticTriangle(
            float x,
            float y,
            float width,
            float height,
            float angle,
            int kind,
            float restitution,
            float friction,
            bool bouncy = false
    );

    void createCross(
            float x,
            float y,
            float width,
            float height,
            float angle,
            int kind,
            float restitution,
            float friction,
            bool bouncy = false
    );

    void createObstacle(const GolfObstacleInput& obstacle);

    bool applySlopesPostStep(const b2Vec2& slopeSamplePos);
    void stopSmallMotion(bool onSlope);

    b2World world;
    GolfContactListener contactListener;

    GolfBall* ball = nullptr;
    std::vector<StaticBodyRecord> staticBodies;
    std::vector<SlopeRecord> slopes;

    float tileSize = 65.0f;
    float mapSize = 390.0f;
    int rows = 0;
    int cols = 0;

    std::string traceRunId;
    int traceShotIndex = -1;
    int traceFrame = -1;
    std::string tracePhase;
};

#endif