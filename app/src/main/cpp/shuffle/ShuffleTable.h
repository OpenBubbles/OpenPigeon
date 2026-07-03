#ifndef OPENBUBBLES_SHUFFLE_TABLE_H
#define OPENBUBBLES_SHUFFLE_TABLE_H

#include <Box2D/Box2D.h>
#include <vector>
#include "ShufflePuck.h"
#include "ShuffleContactListener.h"
#include "ShuffleData.h"

class ShuffleTable {
public:
    ShuffleTable();
    ~ShuffleTable();

    void clearPucks();

    void makePuck(
            float x,
            float y,
            float angle,
            int traceId,
            int player,
            float* outputs
    );

    void movePuck(
            int traceId,
            float x,
            float y,
            float angle
    );

    void firePuck(
            int traceId,
            float shootDirRadians,
            float dist
    );

    void setMode(int mode);

    bool update();
    void refreshOutputs();

    void destroyBody(b2Body* body);

private:
    ShufflePuck* findPuck(int traceId);

    void clearStaticBodies();
    void rebuildStaticBodies();

    void addEdgeWall(
            const b2Vec2& a,
            const b2Vec2& b,
            int player
    );

    void addBumper();

    b2World world;
    ShuffleContactListener contactListener;

    std::vector<ShufflePuck*> pucks;
    std::vector<b2Body*> staticBodies;
    std::vector<ShuffleData> staticData;

    int mode = 1;
};

#endif