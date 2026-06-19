#ifndef OPENBUBBLES_KNOCKOUT_DATA_H
#define OPENBUBBLES_KNOCKOUT_DATA_H

struct KnockoutData {
    enum Type {
        Piece,
        Shroom
    };

    Type type;
    void* data;
};

#endif