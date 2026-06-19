#include "KnockoutContactListener.h"
#include "KnockoutData.h"
#include "KnockoutPiece.h"
#include "KnockoutTable.h"

static constexpr float SHROOM_BOUNCE_VELOCITY = 450.0f;

static KnockoutData* dataForFixture(b2Fixture* fixture) {
    if (!fixture) return nullptr;

    b2Body* body = fixture->GetBody();
    if (!body) return nullptr;

    return static_cast<KnockoutData*>(body->GetUserData());
}

void KnockoutContactListener::BeginContact(b2Contact* contact) {
    if (!contact) return;

    b2Fixture* fixtureA = contact->GetFixtureA();
    b2Fixture* fixtureB = contact->GetFixtureB();

    KnockoutData* dataA = dataForFixture(fixtureA);
    KnockoutData* dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB) return;

    const bool aPieceBShroom =
            dataA->type == KnockoutData::Type::Piece &&
            dataB->type == KnockoutData::Type::Shroom;

    const bool aShroomBPiece =
            dataA->type == KnockoutData::Type::Shroom &&
            dataB->type == KnockoutData::Type::Piece;

    if (!aPieceBShroom && !aShroomBPiece) return;

    KnockoutPiece* piece = static_cast<KnockoutPiece*>(
            aPieceBShroom ? dataA->data : dataB->data
    );

    b2Body* shroomBody = aPieceBShroom
                         ? static_cast<b2Body*>(dataB->data)
                         : static_cast<b2Body*>(dataA->data);

    if (!piece || !piece->body || !shroomBody) return;

    b2WorldManifold manifold;
    contact->GetWorldManifold(&manifold);

    b2Vec2 awayFromShroom = manifold.normal;

    // Box2D normal points from fixture A to fixture B.
    // If A is the piece and B is the shroom, invert it so the piece is pushed away.
    if (aPieceBShroom) {
        awayFromShroom = -awayFromShroom;
    }

    if (awayFromShroom.LengthSquared() <= 0.000001f) {
        awayFromShroom = piece->body->GetPosition() - shroomBody->GetPosition();

        if (awayFromShroom.LengthSquared() <= 0.000001f) {
            awayFromShroom.Set(1.0f, 0.0f);
        } else {
            awayFromShroom.Normalize();
        }
    }

    const b2Vec2 currentVelocity = piece->body->GetLinearVelocity();
    const b2Vec2 boostedVelocity =
            currentVelocity + SHROOM_BOUNCE_VELOCITY * awayFromShroom;

    piece->body->SetAwake(true);
    piece->body->SetLinearVelocity(boostedVelocity);

    if (piece->table) {
        piece->table->registerMushroomHit(shroomBody->GetPosition());
    }
}

void KnockoutContactListener::PreSolve(b2Contact* contact, const b2Manifold* oldManifold) {
    (void)contact;
    (void)oldManifold;
}

void KnockoutContactListener::PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) {
    (void)contact;
    (void)impulse;
}