#ifndef OPENBUBBLES_GOLF_DATA_H
#define OPENBUBBLES_GOLF_DATA_H

#include <Box2D/Box2D.h>

struct GolfData {
    enum class Type {
        Ball = 0,
        Wall = 1,
        Obstacle = 2
    };

    Type type = Type::Obstacle;
    int kind = 0;
    b2Body* body = nullptr;
    bool bouncy = false;

    GolfData() = default;

    GolfData(Type type, int kind, b2Body* body, bool bouncy = false)
            : type(type),
              kind(kind),
              body(body),
              bouncy(bouncy) {
    }
};

#endif