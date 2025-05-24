//
// Created by taeha on 5/17/2025.
//

#ifndef OPENBUBBLES_SAMPLE_EXTENSION_POOLDATA_H
#define OPENBUBBLES_SAMPLE_EXTENSION_POOLDATA_H

struct PoolData {
    enum Type {
        Ball,
        Wall,
    };
    Type type;
    void* data;
};

#endif //OPENBUBBLES_SAMPLE_EXTENSION_POOLDATA_H
