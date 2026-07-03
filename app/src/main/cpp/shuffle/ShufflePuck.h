#ifndef OPENBUBBLES_SHUFFLE_PUCK_H
#define OPENBUBBLES_SHUFFLE_PUCK_H

#include <Box2D/Box2D.h>
#include "ShuffleData.h"

class ShuffleTable;

class ShufflePuck {
public:
    ShufflePuck(
            ShuffleTable* table,
            b2Body* body,
            int traceId,
            int player,
            float* outputs
    );

    ~ShufflePuck();

    bool step();
    void fire(float shootDirRadians, float dist);
    void setTransform(float x, float y, float angle);

    int traceId;
    int player;
    b2Body* body;
    ShuffleTable* table;

private:
    float* outputs;
    ShuffleData data;
};

#endif