#ifndef OPENBUBBLES_GOLF_DATA_H
#define OPENBUBBLES_GOLF_DATA_H

struct GolfData {
    enum Type {
        Ball,
        Wall,
        Obstacle
    };

    Type type;
    int kind;
    void* data;
};

#endif
