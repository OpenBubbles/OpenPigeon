#ifndef OPENBUBBLES_SAMPLE_EXTENSION_POOLBALL_H
#define OPENBUBBLES_SAMPLE_EXTENSION_POOLBALL_H

class PoolTable;

#include "PoolData.h"
#include <Box2D/Box2D.h>

#define COULD_GO_IN 0
#define SHOULD_GO_IN 1
#define SHOULD_NOT_GO_IN 2

class PoolBall {
public:
    PoolBall(PoolTable* table, b2Body* body, int number, int shouldGoIn, float* outputs);

    bool step();
    void hit(float dir, float power, float spinX, float spinY);
    void writeOutputs();

    ~PoolBall();

    int number;
    b2Body* body;
    PoolTable* table;

    b2Vec2 hole;
    b2Vec2 hitHole;
    int numberHit = -1;
    int sunkOrder = -1;
    int shouldGoIn;

private:
    float* outputs;
    PoolData data;
    float spinPower = 0.0f;
    b2Vec2 spinDir = b2Vec2_zero;
    int pocketFrames = -1;
    bool pocketBodyRemoved = false;

    void markSunk(const b2Vec2& tableHole, const char* reason);
    void stepPocketedBall();
    bool isInsidePocketKillBounds() const;
    void assignSunkOrder(const char* reason);
    void keepOutOfPocket(const b2Vec2& tableHole, float dist);
};

#endif