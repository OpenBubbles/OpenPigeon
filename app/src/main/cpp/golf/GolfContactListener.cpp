#include "GolfContactListener.h"
#include "GolfData.h"

#include <android/log.h>

namespace {
    static GolfData* dataForFixture(b2Fixture* fixture) {
        if (!fixture) {
            return nullptr;
        }

        b2Body* body = fixture->GetBody();
        if (!body) {
            return nullptr;
        }

        return static_cast<GolfData*>(body->GetUserData());
    }

    static const char* typeName(const GolfData* data) {
        if (!data) return "null";

        switch (data->type) {
            case GolfData::Type::Ball:
                return "ball";
            case GolfData::Type::Wall:
                return "wall";
            case GolfData::Type::Obstacle:
                return "obstacle";
            default:
                return "unknown";
        }
    }

    static bool isBallInvolved(const GolfData* dataA, const GolfData* dataB) {
        if (!dataA || !dataB) {
            return false;
        }

        return dataA->type == GolfData::Type::Ball ||
               dataB->type == GolfData::Type::Ball;
    }
}

void GolfContactListener::setTraceContext(
        const char* runId,
        int shotIndex,
        int frame,
        const char* phase
) {
    traceRunId = runId ? runId : "";
    traceShotIndex = shotIndex;
    traceFrame = frame;
    tracePhase = phase ? phase : "";
}

void GolfContactListener::clearTraceContext() {
    traceRunId.clear();
    traceShotIndex = -1;
    traceFrame = -1;
    tracePhase.clear();
}

void GolfContactListener::BeginContact(b2Contact* contact) {
    if (!contact) {
        return;
    }

    b2Fixture* fixtureA = contact->GetFixtureA();
    b2Fixture* fixtureB = contact->GetFixtureB();

    GolfData* dataA = dataForFixture(fixtureA);
    GolfData* dataB = dataForFixture(fixtureB);

    if (!isBallInvolved(dataA, dataB)) {
        return;
    }

    b2WorldManifold manifold;
    contact->GetWorldManifold(&manifold);

    const b2Manifold* localManifold = contact->GetManifold();
    const int pointCount = localManifold ? localManifold->pointCount : 0;

    b2Body* bodyA = fixtureA ? fixtureA->GetBody() : nullptr;
    b2Body* bodyB = fixtureB ? fixtureB->GetBody() : nullptr;

    const b2Vec2 posA = bodyA ? bodyA->GetPosition() : b2Vec2_zero;
    const b2Vec2 posB = bodyB ? bodyB->GetPosition() : b2Vec2_zero;
    const b2Vec2 velA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2_zero;
    const b2Vec2 velB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2_zero;

    const b2Vec2 point =
            pointCount > 0 ? manifold.points[0] : b2Vec2_zero;

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_NATIVE_CONTACT={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"aType\":%d,"
            "\"aTypeName\":\"%s\","
            "\"aKind\":%d,"
            "\"bType\":%d,"
            "\"bTypeName\":\"%s\","
            "\"bKind\":%d,"
            "\"pointCount\":%d,"
            "\"normal\":{\"x\":%.6f,\"y\":%.6f},"
            "\"point\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aVel\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bVel\":{\"x\":%.6f,\"y\":%.6f}"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            static_cast<int>(dataA->type),
            typeName(dataA),
            dataA->kind,
            static_cast<int>(dataB->type),
            typeName(dataB),
            dataB->kind,
            pointCount,
            manifold.normal.x,
            manifold.normal.y,
            point.x,
            point.y,
            posA.x,
            posA.y,
            posB.x,
            posB.y,
            velA.x,
            velA.y,
            velB.x,
            velB.y
    );
}

void GolfContactListener::PreSolve(b2Contact* contact, const b2Manifold* oldManifold) {
    (void) oldManifold;

    if (!contact) {
        return;
    }

    GolfData* dataA = dataForFixture(contact->GetFixtureA());
    GolfData* dataB = dataForFixture(contact->GetFixtureB());

    if (!dataA || !dataB) {
        return;
    }

    const bool ballBall =
            dataA->type == GolfData::Type::Ball &&
            dataB->type == GolfData::Type::Ball;

    if (ballBall) {
        contact->SetEnabled(false);
    }
}

void GolfContactListener::PostSolve(
        b2Contact* contact,
        const b2ContactImpulse* impulse
) {
    if (!contact || !impulse) {
        return;
    }

    b2Fixture* fixtureA = contact->GetFixtureA();
    b2Fixture* fixtureB = contact->GetFixtureB();

    GolfData* dataA = dataForFixture(fixtureA);
    GolfData* dataB = dataForFixture(fixtureB);

    if (!isBallInvolved(dataA, dataB)) {
        return;
    }

    b2WorldManifold manifold;
    contact->GetWorldManifold(&manifold);

    const b2Manifold* localManifold = contact->GetManifold();
    const int pointCount = localManifold ? localManifold->pointCount : 0;

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

    b2Body* bodyA = fixtureA ? fixtureA->GetBody() : nullptr;
    b2Body* bodyB = fixtureB ? fixtureB->GetBody() : nullptr;

    const b2Vec2 posA = bodyA ? bodyA->GetPosition() : b2Vec2_zero;
    const b2Vec2 posB = bodyB ? bodyB->GetPosition() : b2Vec2_zero;
    const b2Vec2 velA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2_zero;
    const b2Vec2 velB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2_zero;

    const b2Vec2 point =
            pointCount > 0 ? manifold.points[0] : b2Vec2_zero;

    __android_log_print(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_NATIVE_IMPULSE={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"aType\":%d,"
            "\"aTypeName\":\"%s\","
            "\"aKind\":%d,"
            "\"bType\":%d,"
            "\"bTypeName\":\"%s\","
            "\"bKind\":%d,"
            "\"pointCount\":%d,"
            "\"normal\":{\"x\":%.6f,\"y\":%.6f},"
            "\"point\":{\"x\":%.6f,\"y\":%.6f},"
            "\"normalImpulse0\":%.6f,"
            "\"normalImpulse1\":%.6f,"
            "\"tangentImpulse0\":%.6f,"
            "\"tangentImpulse1\":%.6f,"
            "\"aPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aVel\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bVel\":{\"x\":%.6f,\"y\":%.6f}"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            static_cast<int>(dataA->type),
            typeName(dataA),
            dataA->kind,
            static_cast<int>(dataB->type),
            typeName(dataB),
            dataB->kind,
            pointCount,
            manifold.normal.x,
            manifold.normal.y,
            point.x,
            point.y,
            normalImpulse0,
            normalImpulse1,
            tangentImpulse0,
            tangentImpulse1,
            posA.x,
            posA.y,
            posB.x,
            posB.y,
            velA.x,
            velA.y,
            velB.x,
            velB.y
    );
}