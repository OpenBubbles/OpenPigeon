#include "KnockoutContactListener.h"

void KnockoutContactListener::BeginContact(b2Contact* contact) {
    (void)contact;
}

void KnockoutContactListener::PreSolve(b2Contact* contact, const b2Manifold* oldManifold) {
    (void)contact;
    (void)oldManifold;
}

void KnockoutContactListener::PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) {
    (void)contact;
    (void)impulse;
}
