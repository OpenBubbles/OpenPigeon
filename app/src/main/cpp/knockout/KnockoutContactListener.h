#ifndef OPENBUBBLES_KNOCKOUT_CONTACT_LISTENER_H
#define OPENBUBBLES_KNOCKOUT_CONTACT_LISTENER_H

#include <Box2D/Box2D.h>

class KnockoutContactListener : public b2ContactListener {
public:
    void BeginContact(b2Contact* contact) override;
    void PreSolve(b2Contact* contact, const b2Manifold* oldManifold) override;
    void PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) override;
};

#endif
