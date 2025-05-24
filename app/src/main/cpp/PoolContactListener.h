//
// Created by taeha on 5/17/2025.
//

#include <Box2D/Box2D.h>

#ifndef OPENBUBBLES_SAMPLE_EXTENSION_POOLCONTACTLISTENER_H
#define OPENBUBBLES_SAMPLE_EXTENSION_POOLCONTACTLISTENER_H


class PoolContactListener : public b2ContactListener {
    void BeginContact(b2Contact* contact) override;
    void PreSolve(b2Contact* contact, const b2Manifold* oldManifold) override;
};


#endif //OPENBUBBLES_SAMPLE_EXTENSION_POOLCONTACTLISTENER_H
