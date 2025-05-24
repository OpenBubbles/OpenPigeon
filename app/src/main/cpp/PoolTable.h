//
// Created by taeha on 5/16/2025.
//

#include <Box2D/Box2D.h>
#include <vector>

#ifndef OPENBUBBLES_SAMPLE_EXTENSION_POOLTABLE_H
#define OPENBUBBLES_SAMPLE_EXTENSION_POOLTABLE_H

#include "PoolBall.h"
#include "PoolData.h"
#include "PoolContactListener.h"

class PoolTable {
public:
    PoolTable();
    void makeBall(b2Vec2 position, float rot, float density, int number, int shouldGoIn, float* outputs);
    void clearBalls();
    bool update();
    void hitBall(int number, float dir, float power, float spinX, float spinY, bool first);
    void moveBall(int number, b2Vec2 position, float rot);
    int cueDelay = -1;
    int pocketNumber = 0;

    bool isFirst;

    b2Vec2 holes[6] = {
            {40, 40},
            {744, 40},
            {40, 400},
            {744, 400},
            {392, 28},
            {392, 412}
    };

    std::optional<b2Vec2> wallHoles[47] = {
            std::nullopt,
            std::nullopt,
            std::nullopt,
            std::nullopt,
            std::optional(b2Vec2(40, 40)),
            std::optional(b2Vec2(40, 40)),
            std::nullopt,
            std::optional(b2Vec2(40, 40)),
            std::optional(b2Vec2(40, 40)),
            std::optional(b2Vec2(40, 40)),
            std::nullopt,
            std::optional(b2Vec2(744, 40)),
            std::optional(b2Vec2(744, 40)),
            std::nullopt,
            std::optional(b2Vec2(744, 40)),
            std::optional(b2Vec2(744, 40)),
            std::optional(b2Vec2(744, 40)),
            std::nullopt,
            std::optional(b2Vec2(744, 400)),
            std::optional(b2Vec2(744, 400)),
            std::nullopt,
            std::optional(b2Vec2(744, 400)),
            std::optional(b2Vec2(744, 400)),
            std::optional(b2Vec2(744, 400)),
            std::nullopt,
            std::optional(b2Vec2(40, 400)),
            std::optional(b2Vec2(40, 400)),
            std::nullopt,
            std::optional(b2Vec2(40, 400)),
            std::optional(b2Vec2(40, 400)),
            std::optional(b2Vec2(40, 400)),
            std::nullopt,
            std::optional(b2Vec2(392, 28)),
            std::optional(b2Vec2(392, 28)),
            std::nullopt,
            std::optional(b2Vec2(392, 28)),
            std::optional(b2Vec2(392, 28)),
            std::nullopt,
            std::optional(b2Vec2(392, 412)),
            std::optional(b2Vec2(392, 412)),
            std::nullopt,
            std::optional(b2Vec2(392, 412)),
            std::optional(b2Vec2(392, 412)),
            std::nullopt,
            std::nullopt,
            std::nullopt,
            std::nullopt
    };
private:
    friend class PoolBall;
    b2World world;
    std::vector<PoolBall*> balls;
    PoolData wallData;
    PoolContactListener contactListener;
};


#endif //OPENBUBBLES_SAMPLE_EXTENSION_POOLTABLE_H
