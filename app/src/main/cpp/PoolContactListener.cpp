//
// Created by taeha on 5/17/2025.
//

#include <android/log.h>
#include "PoolContactListener.h"
#include "PoolData.h"
#include "PoolBall.h"
#include "PoolTable.h"

// defined in b2TimeOfImpact.cpp
void set_custom_slop(float32 slop);

void PoolContactListener::PreSolve(b2Contact *contact, const b2Manifold *oldManifold) {
    auto data1 = (PoolData*) contact->GetFixtureA()->GetBody()->GetUserData();
    auto data2 = (PoolData*) contact->GetFixtureB()->GetBody()->GetUserData();
    if (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Ball) {
        // ball-to-ball collision
        auto ball1 = (PoolBall*)data1->data;
        auto ball2 = (PoolBall*)data2->data;

        if (ball1->hole.x != -1 || ball2->hole.x != -1) {
            contact->SetEnabled(false);
        }
    }
}

void PoolContactListener::BeginContact(b2Contact *contact) {
    auto data1 = (PoolData*) contact->GetFixtureA()->GetBody()->GetUserData();
    auto data2 = (PoolData*) contact->GetFixtureB()->GetBody()->GetUserData();

    if (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Ball) {
        // ball-to-ball collision
        auto ball1 = (PoolBall*)data1->data;
        auto ball2 = (PoolBall*)data2->data;




        // here gamepigeon discards collisions between sunk balls
        if (ball1->hole.x != -1 || ball2->hole.x != -1) {
            contact->SetEnabled(false);
        } else {
            if (ball1->numberHit == -1) {
                ball1->numberHit = ball2->number;
            }
            if (ball2->numberHit == -1) {
                ball2->numberHit = ball1->number;
            }
        }

        if (ball1->number != 0 && ball2->number != 0) {
            // colored-on-colored hit
            contact->SetFriction(0.5);
            contact->SetRestitution(1);
        }
        if ((ball1->number == 0 && ball2->number != 0) || (ball1->number != 0 && ball2->number == 0)) {
            // colored-on-white hit
            contact->SetFriction(0);
            contact->SetRestitution(1);
            if (ball1->table->cueDelay == -1) {
                ball1->table->cueDelay = 0;
                if (ball1->table->isFirst) {
                    set_custom_slop(0.9f);
                }
            }
        }
        // start timer if stopped, and first != null ? also set slop
    }

    if ((data1->type == PoolData::Type::Wall && data2->type == PoolData::Type::Ball) || (data1->type == PoolData::Type::Ball && data2->type == PoolData::Type::Wall)) {

        if (data1->type == PoolData::Type::Wall) {
            auto hole = (b2Vec2 *) contact->GetFixtureA()->GetUserData();
            if (hole != nullptr) {
                auto ball = (PoolBall*)data2->data;
                __android_log_print(ANDROID_LOG_VERBOSE, "Ball", "Ball hit hole");
                ball->hitHole = *hole;
            }
        }
        if (data2->type == PoolData::Type::Wall) {
            auto hole = (b2Vec2*)contact->GetFixtureB()->GetUserData();
            if (hole != nullptr) {
                auto ball = (PoolBall*)data1->data;
                __android_log_print(ANDROID_LOG_VERBOSE, "Ball", "Ball hit hole");
                ball->hitHole = *hole;
            }
        }

        contact->SetFriction(0.5);
        contact->SetRestitution(0.75);
    }
}
