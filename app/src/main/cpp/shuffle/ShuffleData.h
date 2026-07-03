#ifndef OPENBUBBLES_SHUFFLE_DATA_H
#define OPENBUBBLES_SHUFFLE_DATA_H

struct ShuffleData {
    enum Type {
        Puck,
        Wall,
        Bumper
    };

    Type type;
    void* data;
    int player;
};

#endif