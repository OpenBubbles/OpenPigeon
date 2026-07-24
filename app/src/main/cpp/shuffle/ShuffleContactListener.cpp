#include "ShuffleContactListener.h"
#include "ShuffleData.h"
#include "ShufflePuck.h"

#include <android/log.h>
#include <cstdarg>
#include <cmath>
#include <string>

extern bool gShuffleDebugLoggingEnabled;

namespace {
    constexpr float BUMPER_BOUNCE_VELOCITY = 550.0f;

    void shuffleNativeLogPrint(int priority, const char *tag, const char *format, ...) {
        if (!gShuffleDebugLoggingEnabled) {
            return;
        }

        va_list args;
        va_start(args, format);
        __android_log_vprint(priority, tag, format, args);
        va_end(args);
    }

    ShuffleData *dataForFixture(b2Fixture *fixture) {
        if (!fixture) {
            return nullptr;
        }

        b2Body *body = fixture->GetBody();

        if (!body) {
            return nullptr;
        }

        return static_cast<ShuffleData *>(
                body->GetUserData());
    }

    const char *typeName(const ShuffleData *data) {
        if (!data) {
            return "null";
        }

        switch (data->type) {
            case ShuffleData::Type::Puck:
                return "puck";

            case ShuffleData::Type::Wall:
                return "wall";

            case ShuffleData::Type::Bumper:
                return "bumper";

            default:
                return "unknown";
        }
    }

    bool isPuck(const ShuffleData *data) {
        return data && data->type == ShuffleData::Type::Puck;
    }

    bool isWall(const ShuffleData *data) {
        return data && data->type == ShuffleData::Type::Wall;
    }

    bool isBumper(const ShuffleData *data) {
        return data && data->type == ShuffleData::Type::Bumper;
    }

    bool isPuckInvolved(const ShuffleData *dataA, const ShuffleData *dataB) {
        return isPuck(dataA) || isPuck(dataB);
    }

    ShufflePuck *puckForData(ShuffleData *data) {
        if (!isPuck(data)) {
            return nullptr;
        }

        return static_cast<ShufflePuck *>(
                data->data
        );
    }

    b2Vec2 negate(const b2Vec2 &value) {
        return {-value.x, -value.y};
    }
}

void ShuffleContactListener::setTraceContext(const char *runId, int shotIndex, int frame,
                                             const char *phase) {
    traceRunId = runId ? runId : "";

    traceShotIndex = shotIndex;

    traceFrame = frame;

    tracePhase = phase ? phase : "";
}

void ShuffleContactListener::clearTraceContext() {
    traceRunId.clear();
    traceShotIndex = -1;
    traceFrame = -1;
    tracePhase.clear();
}

void ShuffleContactListener::BeginContact(b2Contact *contact) {
    if (!contact) {
        return;
    }

    b2Fixture *fixtureA = contact->GetFixtureA();

    b2Fixture *fixtureB = contact->GetFixtureB();

    ShuffleData *dataA = dataForFixture(fixtureA);

    ShuffleData *dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB || !isPuckInvolved(dataA, dataB)) {
        return;
    }

    b2Body *bodyA = fixtureA ? fixtureA->GetBody() : nullptr;

    b2Body *bodyB = fixtureB ? fixtureB->GetBody() : nullptr;

    const b2Vec2 positionA = bodyA ? bodyA->GetPosition() : b2Vec2_zero;

    const b2Vec2 positionB = bodyB ? bodyB->GetPosition() : b2Vec2_zero;

    const b2Vec2 velocityBeforeA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2_zero;

    const b2Vec2 velocityBeforeB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2_zero;

    b2WorldManifold worldManifold;
    contact->GetWorldManifold(&worldManifold);

    const b2Manifold *manifold = contact->GetManifold();

    const int pointCount = manifold ? manifold->pointCount : 0;

    const b2Vec2 contactPoint = pointCount > 0 ? worldManifold.points[0] : b2Vec2_zero;

    const bool aPuckBBumper = isPuck(dataA) && isBumper(dataB);

    const bool aBumperBPuck = isBumper(dataA) && isPuck(dataB);

    bool usedBumperRewrite = false;

    if (aPuckBBumper || aBumperBPuck) {
        ShufflePuck *puck = puckForData(aPuckBBumper ? dataA : dataB);

        b2Body *bumperBody = aPuckBBumper ? bodyB : bodyA;

        if (puck && puck->body && bumperBody) {
            b2Vec2 awayFromBumper = puck->body->GetPosition() - bumperBody->GetPosition();

            if (awayFromBumper.LengthSquared() <= 0.000001f) {
                awayFromBumper.Set(1.0f, 0.0f);
            } else {
                awayFromBumper.Normalize();
            }

            const b2Vec2 velocityBefore = puck->body->GetLinearVelocity();

            const b2Vec2 rewrittenVelocity =
                    velocityBefore + BUMPER_BOUNCE_VELOCITY * awayFromBumper;

            puck->body->SetAwake(true);

            puck->body->SetLinearVelocity(rewrittenVelocity);

            usedBumperRewrite = true;
        }
    }

    const b2Vec2 velocityAfterA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2_zero;

    const b2Vec2 velocityAfterB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2_zero;

    const float restitutionA = fixtureA ? fixtureA->GetRestitution() : 0.0f;

    const float restitutionB = fixtureB ? fixtureB->GetRestitution() : 0.0f;

    const float frictionA = fixtureA ? fixtureA->GetFriction() : 0.0f;

    const float frictionB = fixtureB ? fixtureB->GetFriction() : 0.0f;

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_CONTACT={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"phase\":\"%s\","
                                                             "\"aType\":\"%s\","
                                                             "\"aPlayer\":%d,"
                                                             "\"bType\":\"%s\","
                                                             "\"bPlayer\":%d,"
                                                             "\"touching\":%s,"
                                                             "\"pointCount\":%d,"
                                                             "\"normal\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"point\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aPosition\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"bPosition\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aVelocityBefore\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"bVelocityBefore\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aVelocityAfterBegin\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"bVelocityAfterBegin\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aRestitution\":%.9f,"
                                                             "\"bRestitution\":%.9f,"
                                                             "\"contactRestitution\":%.9f,"
                                                             "\"aFriction\":%.9f,"
                                                             "\"bFriction\":%.9f,"
                                                             "\"contactFriction\":%.9f,"
                                                             "\"usedBumperRewrite\":%s,"
                                                             "\"bumperVelocityDelta\":%.9f"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, tracePhase.c_str(), typeName(dataA),
                          dataA->player, typeName(dataB), dataB->player,
                          contact->IsTouching() ? "true" : "false", pointCount,
                          worldManifold.normal.x, worldManifold.normal.y, contactPoint.x,
                          contactPoint.y, positionA.x, positionA.y, positionB.x, positionB.y,
                          velocityBeforeA.x, velocityBeforeA.y, velocityBeforeB.x,
                          velocityBeforeB.y, velocityAfterA.x, velocityAfterA.y, velocityAfterB.x,
                          velocityAfterB.y, restitutionA, restitutionB, contact->GetRestitution(),
                          frictionA, frictionB, contact->GetFriction(),
                          usedBumperRewrite ? "true" : "false",
                          usedBumperRewrite ? BUMPER_BOUNCE_VELOCITY : 0.0f);
}

void ShuffleContactListener::PreSolve(b2Contact *contact, const b2Manifold *oldManifold) {
    if (!contact) {
        return;
    }

    b2Fixture *fixtureA = contact->GetFixtureA();

    b2Fixture *fixtureB = contact->GetFixtureB();

    ShuffleData *dataA = dataForFixture(fixtureA);

    ShuffleData *dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB) {
        return;
    }

    const bool aPuckBWall = isPuck(dataA) && isWall(dataB);

    const bool aWallBPuck = isWall(dataA) && isPuck(dataB);

    if (!aPuckBWall && !aWallBPuck) {
        return;
    }

    ShuffleData *puckData = aPuckBWall ? dataA : dataB;

    ShuffleData *wallData = aPuckBWall ? dataB : dataA;

    ShufflePuck *puck = puckForData(puckData);

    if (!puck || !puck->body) {
        return;
    }

    const bool shouldDisable =
            wallData->player != 0 && puck->player == wallData->player && !puck->ingame;

    if (!shouldDisable) {
        return;
    }

    contact->SetEnabled(false);

    const b2Vec2 position = puck->body->GetPosition();

    const b2Vec2 velocity = puck->body->GetLinearVelocity();

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_GATE_FILTER={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"phase\":\"%s\","
                                                             "\"puckTraceId\":%d,"
                                                             "\"puckPlayer\":%d,"
                                                             "\"wallPlayer\":%d,"
                                                             "\"ingame\":false,"
                                                             "\"oldPointCount\":%d,"
                                                             "\"position\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"velocity\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"contactEnabled\":false"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, tracePhase.c_str(), puck->traceId,
                          puck->player, wallData->player, oldManifold ? oldManifold->pointCount : 0,
                          position.x, position.y, velocity.x, velocity.y);
}

void ShuffleContactListener::PostSolve(b2Contact *contact, const b2ContactImpulse *impulse) {
    if (!contact || !impulse) {
        return;
    }

    b2Fixture *fixtureA = contact->GetFixtureA();

    b2Fixture *fixtureB = contact->GetFixtureB();

    ShuffleData *dataA = dataForFixture(fixtureA);

    ShuffleData *dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB || !isPuckInvolved(dataA, dataB)) {
        return;
    }

    const b2Manifold *manifold = contact->GetManifold();

    const int pointCount = manifold ? manifold->pointCount : 0;

    float normalImpulse0 = 0.0f;
    float normalImpulse1 = 0.0f;
    float tangentImpulse0 = 0.0f;
    float tangentImpulse1 = 0.0f;

    if (pointCount > 0) {
        normalImpulse0 = impulse->normalImpulses[0];

        tangentImpulse0 = impulse->tangentImpulses[0];
    }

    if (pointCount > 1) {
        normalImpulse1 = impulse->normalImpulses[1];

        tangentImpulse1 = impulse->tangentImpulses[1];
    }

    const bool hasImpulse =
            normalImpulse0 != 0.0f || normalImpulse1 != 0.0f || tangentImpulse0 != 0.0f ||
            tangentImpulse1 != 0.0f;

    if (!hasImpulse) {
        return;
    }

    b2WorldManifold worldManifold;
    contact->GetWorldManifold(&worldManifold);

    b2Body *bodyA = fixtureA ? fixtureA->GetBody() : nullptr;

    b2Body *bodyB = fixtureB ? fixtureB->GetBody() : nullptr;

    const b2Vec2 positionA = bodyA ? bodyA->GetPosition() : b2Vec2_zero;

    const b2Vec2 positionB = bodyB ? bodyB->GetPosition() : b2Vec2_zero;

    const b2Vec2 velocityA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2_zero;

    const b2Vec2 velocityB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2_zero;

    const float angularVelocityA = bodyA ? bodyA->GetAngularVelocity() : 0.0f;

    const float angularVelocityB = bodyB ? bodyB->GetAngularVelocity() : 0.0f;

    const b2Vec2 contactPoint = pointCount > 0 ? worldManifold.points[0] : b2Vec2_zero;

    shuffleNativeLogPrint(ANDROID_LOG_INFO, "ShuffleNative", "SHUFFLE_NATIVE_IMPULSE={"
                                                             "\"runId\":\"%s\","
                                                             "\"shotIndex\":%d,"
                                                             "\"frame\":%d,"
                                                             "\"phase\":\"%s\","
                                                             "\"aType\":\"%s\","
                                                             "\"aPlayer\":%d,"
                                                             "\"bType\":\"%s\","
                                                             "\"bPlayer\":%d,"
                                                             "\"pointCount\":%d,"
                                                             "\"normal\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"point\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"normalImpulse0\":%.9f,"
                                                             "\"normalImpulse1\":%.9f,"
                                                             "\"tangentImpulse0\":%.9f,"
                                                             "\"tangentImpulse1\":%.9f,"
                                                             "\"aPosition\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"bPosition\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aVelocity\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"bVelocity\":{\"x\":%.9f,\"y\":%.9f},"
                                                             "\"aAngularVelocity\":%.9f,"
                                                             "\"bAngularVelocity\":%.9f"
                                                             "}", traceRunId.c_str(),
                          traceShotIndex, traceFrame, tracePhase.c_str(), typeName(dataA),
                          dataA->player, typeName(dataB), dataB->player, pointCount,
                          worldManifold.normal.x, worldManifold.normal.y, contactPoint.x,
                          contactPoint.y, normalImpulse0, normalImpulse1, tangentImpulse0,
                          tangentImpulse1, positionA.x, positionA.y, positionB.x, positionB.y,
                          velocityA.x, velocityA.y, velocityB.x, velocityB.y, angularVelocityA,
                          angularVelocityB);
}