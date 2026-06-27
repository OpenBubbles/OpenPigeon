#ifndef OPENBUBBLES_GOLF_BALL_H
#define OPENBUBBLES_GOLF_BALL_H

#include <Box2D/Box2D.h>
#include "GolfData.h"

class GolfTable;

class GolfBall {
public:
    GolfBall(GolfTable* table, b2Body* body, float* outputs);
    ~GolfBall();

    bool step();

    void setState(float x, float y, float vx, float vy);
    void fire(float directionRadians, float power);

    b2Body* body = nullptr;

private:
    GolfTable* table = nullptr;
    float* outputs = nullptr;
    GolfData data;
};

#endif