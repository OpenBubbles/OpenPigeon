//
// Created by taeha on 5/16/2025.
//


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
    float spinPower;
    b2Vec2 spinDir;
};


#endif //OPENBUBBLES_SAMPLE_EXTENSION_POOLBALL_H
