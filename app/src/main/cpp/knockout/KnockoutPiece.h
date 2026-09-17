#ifndef OPENBUBBLES_KNOCKOUT_PIECE_H
#define OPENBUBBLES_KNOCKOUT_PIECE_H

#include <Box2D/Box2D.h>
#include "KnockoutData.h"

class KnockoutTable;

class KnockoutPiece {
public:
    KnockoutPiece(KnockoutTable* table, b2Body* body, int traceId, int player, float* outputs);
    ~KnockoutPiece();

    bool step();
    void recordPieceHit();
    void fire(float shootDirRadians, float power);
    void setTransform(float x, float y, float angle);

    int traceId;
    int player;
    b2Body* body;
    KnockoutTable* table;

private:
    float* outputs;
    KnockoutData data;
    int pendingPieceHitCount = 0;
};

#endif
