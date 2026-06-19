#ifndef OPENBUBBLES_KNOCKOUT_TABLE_H
#define OPENBUBBLES_KNOCKOUT_TABLE_H

#include <Box2D/Box2D.h>
#include <vector>
#include "KnockoutPiece.h"
#include "KnockoutContactListener.h"

class KnockoutTable {
public:
    KnockoutTable();
    ~KnockoutTable();

    void clearPieces();
    void makePiece(float x, float y, float angle, int traceId, int player, float* outputs);
    void firePiece(int traceId, float shootDirRadians, float power);
    void movePiece(int traceId, float x, float y, float angle);
    bool update();

    void destroyBody(b2Body* body);

    void refreshOutputs();

private:
    KnockoutPiece* findPiece(int traceId);

    b2World world;
    KnockoutContactListener contactListener;
    std::vector<KnockoutPiece*> pieces;
};

#endif
