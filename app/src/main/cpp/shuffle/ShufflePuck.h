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

    [[nodiscard]] bool isMoving() const;
    void updateInGameState();
    void stopSmallMotion() const;
    void writeOutputs();

    void fire(
            float shootDirRadians,
            float dist
    ) const;

    void setTransform(
            float x,
            float y,
            float angle
    );

    int traceId;
    int player;

    bool ingame = false;

    b2Body* body;
    ShuffleTable* table;

private:
    float* outputs;
    ShuffleData data;
};

#endif