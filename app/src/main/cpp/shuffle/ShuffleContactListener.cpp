#include "ShuffleContactListener.h"
#include "ShuffleData.h"
#include "ShufflePuck.h"

static constexpr float BUMPER_BOUNCE_VELOCITY = 550.0f;

static ShuffleData* dataForFixture(b2Fixture* fixture) {
    if (!fixture) return nullptr;

    b2Body* body = fixture->GetBody();
    if (!body) return nullptr;

    return static_cast<ShuffleData*>(body->GetUserData());
}

static bool isPuck(const ShuffleData* data) {
    return data && data->type == ShuffleData::Type::Puck;
}

static bool isBumper(const ShuffleData* data) {
    return data && data->type == ShuffleData::Type::Bumper;
}

void ShuffleContactListener::BeginContact(b2Contact* contact) {
    if (!contact) return;

    b2Fixture* fixtureA = contact->GetFixtureA();
    b2Fixture* fixtureB = contact->GetFixtureB();

    ShuffleData* dataA = dataForFixture(fixtureA);
    ShuffleData* dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB) return;

    const bool aPuckBBumper = isPuck(dataA) && isBumper(dataB);
    const bool aBumperBPuck = isBumper(dataA) && isPuck(dataB);

    if (!aPuckBBumper && !aBumperBPuck) {
        return;
    }

    ShufflePuck* puck = static_cast<ShufflePuck*>(
            aPuckBBumper ? dataA->data : dataB->data
    );

    b2Body* bumperBody = static_cast<b2Body*>(
            aPuckBBumper ? dataB->data : dataA->data
    );

    if (!puck || !puck->body || !bumperBody) return;

    b2WorldManifold manifold;
    contact->GetWorldManifold(&manifold);

    b2Vec2 awayFromBumper = manifold.normal;

    // Box2D normal points from fixture A to fixture B.
    // If A is the puck and B is the bumper, invert so the puck is pushed away.
    if (aPuckBBumper) {
        awayFromBumper = -awayFromBumper;
    }

    if (awayFromBumper.LengthSquared() <= 0.000001f) {
        awayFromBumper = puck->body->GetPosition() - bumperBody->GetPosition();

        if (awayFromBumper.LengthSquared() <= 0.000001f) {
            awayFromBumper.Set(1.0f, 0.0f);
        } else {
            awayFromBumper.Normalize();
        }
    }

    const b2Vec2 currentVelocity = puck->body->GetLinearVelocity();
    const b2Vec2 boostedVelocity =
            currentVelocity + BUMPER_BOUNCE_VELOCITY * awayFromBumper;

    puck->body->SetAwake(true);
    puck->body->SetLinearVelocity(boostedVelocity);
}

void ShuffleContactListener::PreSolve(
        b2Contact* contact,
        const b2Manifold* oldManifold
) {
    (void)contact;
    (void)oldManifold;
}

void ShuffleContactListener::PostSolve(
        b2Contact* contact,
        const b2ContactImpulse* impulse
) {
    (void)contact;
    (void)impulse;
}