//
// Created by taeha on 5/17/2025.
//

#include <android/log.h>
#include "PoolContactListener.h"
#include "PoolData.h"
#include "PoolBall.h"
#include "PoolTable.h"

void set_custom_slop(float32 slop);

void PoolContactListener::PreSolve(b2Contact *contact, const b2Manifold *oldManifold) {
    auto data1 = (PoolData*) contact->GetFixtureA()->GetBody()->GetUserData();
    auto data2 = (PoolData*) contact->GetFixtureB()->GetBody()->GetUserData();

    if (data1 == nullptr || data2 == nullptr) {
        return;
    }

    if (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Ball) {
        auto ball1 = (PoolBall*)data1->data;
        auto ball2 = (PoolBall*)data2->data;

        if (ball1 == nullptr || ball2 == nullptr) {
            return;
        }

        if (ball1->hole.x != -1.0f || ball2->hole.x != -1.0f) {
            contact->SetEnabled(false);
        }
    }
}

void PoolContactListener::PostSolve(b2Contact *contact, const b2ContactImpulse *impulse) {
    auto data1 = (PoolData*) contact->GetFixtureA()->GetBody()->GetUserData();
    auto data2 = (PoolData*) contact->GetFixtureB()->GetBody()->GetUserData();

    if (data1 == nullptr || data2 == nullptr || impulse == nullptr || impulse->count <= 0) {
        return;
    }

    float normalImpulse = impulse->normalImpulses[0];
    float tangentImpulse = impulse->tangentImpulses[0];

    if (normalImpulse == 0.0f && tangentImpulse == 0.0f) {
        return;
    }

    PoolTable* table = nullptr;
    int ballA = -99;
    int ballB = -99;

    if (data1->type == PoolData::Type::Ball) {
        auto ball = (PoolBall*)data1->data;
        if (ball != nullptr) {
            table = ball->table;
            ballA = ball->number;
        }
    }

    if (data2->type == PoolData::Type::Ball) {
        auto ball = (PoolBall*)data2->data;
        if (ball != nullptr) {
            table = ball->table;
            ballB = ball->number;
        }
    }

    if (table == nullptr || !table->debugTraceEnabled) {
        return;
    }

    b2WorldManifold manifold;
    contact->GetWorldManifold(&manifold);

    auto holeA = (b2Vec2*)contact->GetFixtureA()->GetUserData();
    auto holeB = (b2Vec2*)contact->GetFixtureB()->GetUserData();

    __android_log_print(
            ANDROID_LOG_VERBOSE,
            "PoolContact",
            "post_solve frame=%u typeA=%d typeB=%d ballA=%d ballB=%d normal=%.6f tangent=%.6f nx=%.6f ny=%.6f px=%.6f py=%.6f holeA=%.6f,%.6f holeB=%.6f,%.6f",
            table->frame,
            (int)data1->type,
            (int)data2->type,
            ballA,
            ballB,
            normalImpulse,
            tangentImpulse,
            manifold.normal.x,
            manifold.normal.y,
            manifold.points[0].x,
            manifold.points[0].y,
            holeA != nullptr ? holeA->x : -1.0f,
            holeA != nullptr ? holeA->y : -1.0f,
            holeB != nullptr ? holeB->x : -1.0f,
            holeB != nullptr ? holeB->y : -1.0f
    );
}

void PoolContactListener::BeginContact(b2Contact *contact) {
    auto data1 = (PoolData*) contact->GetFixtureA()->GetBody()->GetUserData();
    auto data2 = (PoolData*) contact->GetFixtureB()->GetBody()->GetUserData();

    if (data1 == nullptr || data2 == nullptr) {
        return;
    }

    if (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Ball) {
        auto ball1 = (PoolBall*)data1->data;
        auto ball2 = (PoolBall*)data2->data;

        if (ball1 == nullptr || ball2 == nullptr) {
            return;
        }

        if (ball1->hole.x != -1.0f || ball2->hole.x != -1.0f) {
            contact->SetEnabled(false);
            return;
        }

        if (ball1->numberHit == -1) {
            ball1->numberHit = ball2->number;
        }

        if (ball2->numberHit == -1) {
            ball2->numberHit = ball1->number;
        }

        if (ball1->number != 0 && ball2->number != 0) {
            contact->SetFriction(0.5f);
            contact->SetRestitution(1.0f);
        } else if (
                (ball1->number == 0 && ball2->number != 0) ||
                (ball1->number != 0 && ball2->number == 0)
                ) {
            contact->SetFriction(0.0f);
            contact->SetRestitution(1.0f);

            PoolTable* table = ball1->table != nullptr ? ball1->table : ball2->table;

            if (table != nullptr && table->cueDelay == -1) {
                table->cueDelay = 0;

                if (table->isFirst) {
                    set_custom_slop(0.9f);
                }
            }
        }

        return;
    }

    if (
            (data1->type == PoolData::Type::Wall && data2->type == PoolData::Type::Ball) ||
            (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Wall)
            ) {
        PoolBall* ball = nullptr;
        b2Vec2* hole = nullptr;

        if (data1->type == PoolData::Type::Wall) {
            hole = (b2Vec2*)contact->GetFixtureA()->GetUserData();
            ball = (PoolBall*)data2->data;
        } else {
            hole = (b2Vec2*)contact->GetFixtureB()->GetUserData();
            ball = (PoolBall*)data1->data;
        }

        if (ball == nullptr) {
            return;
        }

        if (hole != nullptr) {
            ball->hitHole = *hole;

            contact->SetFriction(0.5f);

            contact->SetRestitution(0.50f);

            if (ball->table != nullptr && ball->table->debugTraceEnabled) {
                __android_log_print(
                        ANDROID_LOG_VERBOSE,
                        "PoolContact",
                        "pocket_wall_contact frame=%u ball=%d hole=(%.6f,%.6f) ballHole=(%.6f,%.6f)",
                        ball->table->frame,
                        ball->number,
                        hole->x,
                        hole->y,
                        ball->hole.x,
                        ball->hole.y
                );
            }

            return;
        }

        contact->SetFriction(0.5f);
        contact->SetRestitution(0.75f);

        return;
    }
}