#ifndef OPENBUBBLES_KNOCKOUT_TABLE_H
#define OPENBUBBLES_KNOCKOUT_TABLE_H

#include <Box2D/Box2D.h>
#include <vector>
#include "KnockoutPiece.h"
#include "KnockoutContactListener.h"
#include "KnockoutData.h"

class KnockoutTable {
public:
    KnockoutTable();
    ~KnockoutTable();

    void clearPieces();
    void makePiece(float x, float y, float angle, int traceId, int player, float* outputs);
    void firePiece(int traceId, float shootDirRadians, float power);
    void movePiece(int traceId, float x, float y, float angle);
    void setMap(int mapMode, float boardScale);
    int consumeMushroomHits();
    void registerMushroomHit(const b2Vec2& shroomPos);
    bool update();

    void destroyBody(b2Body* body);

    void refreshOutputs();

private:
    KnockoutPiece* findPiece(int traceId);

    void clearObstacles();
    void rebuildObstacles();

    b2World world;
    KnockoutContactListener contactListener;
    std::vector<KnockoutPiece*> pieces;
    std::vector<b2Body*> obstacles;
    std::vector<KnockoutData> obstacleData;

    int mapMode = 1;
    float boardScale = 1.0f;
    int mushroomHitMask = 0;
};

#endif
