#include "GolfContactListener.h"
#include "GolfData.h"

#include <android/log.h>
#include <cstdarg>
#include <string>

namespace {
    GolfData* dataForFixture(b2Fixture* fixture) {
        if (!fixture) {
            return nullptr;
        }

        b2Body* body = fixture->GetBody();
        if (!body) {
            return nullptr;
        }

        return static_cast<GolfData*>(body->GetUserData());
    }

    const char* golfDataTypeName(const GolfData* data) {
        if (!data) {
            return "null";
        }

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

    bool isBall(const GolfData* data) {
        return data && data->type == GolfData::Type::Ball;
    }

    bool isBallBallContact(const GolfData* dataA, const GolfData* dataB) {
        return isBall(dataA) && isBall(dataB);
    }

    float lengthSquared(const b2Vec2& v) {
        return v.x * v.x + v.y * v.y;
    }

    b2Vec2 iosReflectVelocity(const b2Vec2& velocity, const b2Vec2& normal) {
        const float dot = velocity.x * normal.x + velocity.y * normal.y;

        b2Vec2 reflected(
                velocity.x - 2.0f * dot * normal.x,
                velocity.y - 2.0f * dot * normal.y
        );

        reflected *= 0.95f;
        return reflected;
    }

    void setBodyVelocityLikeIos(b2Body* body, const b2Vec2& velocity) {
        if (!body) {
            return;
        }

        if (lengthSquared(velocity) <= 0.0f) {
            body->SetLinearVelocity(velocity);
            return;
        }

        body->SetAwake(true);
        body->SetLinearVelocity(velocity);
    }

    const char* typeName(const GolfData* data) {
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

    bool isBallInvolved(const GolfData* dataA, const GolfData* dataB) {
        if (!dataA || !dataB) {
            return false;
        }

        return dataA->type == GolfData::Type::Ball ||
               dataB->type == GolfData::Type::Ball;
    }
}

extern bool gGolfDebugLoggingEnabled;

static void golfNativeLogPrint(
        int priority,
        const char* tag,
        const char* format,
        ...
) {
    if (!gGolfDebugLoggingEnabled) {
        return;
    }

    va_list args;
    va_start(args, format);
    __android_log_vprint(priority, tag, format, args);
    va_end(args);
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

static constexpr float IOS_BOUNCY_VELOCITY_DELTA = 750.0f;

static bool isBouncyObstacle(const GolfData* data) {
    return data &&
           data->type == GolfData::Type::Obstacle &&
           data->bouncy;
}

static bool isBouncyContact(const GolfData* dataA, const GolfData* dataB) {
    return isBouncyObstacle(dataA) || isBouncyObstacle(dataB);
}

static b2Vec2 negateVec(const b2Vec2& v) {
    return b2Vec2(-v.x, -v.y);
}

static b2Vec2 normalAwayFromOtherBody(bool ballIsA, const b2Vec2& worldNormal) {
    return ballIsA ? negateVec(worldNormal) : worldNormal;
}

static b2Vec2 normalTowardOtherBody(bool ballIsA, const b2Vec2& worldNormal) {
    return ballIsA ? worldNormal : negateVec(worldNormal);
}

static float safeBodyMass(const b2Body* body) {
    if (!body) {
        return 1.0f;
    }

    const float mass = body->GetMass();
    return mass > 0.000001f ? mass : 1.0f;
}

static b2Vec2 iosBouncyVelocity(
        const b2Vec2& velocity,
        const b2Vec2& normalTowardBouncy
) {
    return b2Vec2(
            velocity.x + normalTowardBouncy.x * IOS_BOUNCY_VELOCITY_DELTA,
            velocity.y + normalTowardBouncy.y * IOS_BOUNCY_VELOCITY_DELTA
    );
}

static void logBouncyValidation(
        const std::string& traceRunId,
        int traceShotIndex,
        int traceFrame,
        const std::string& tracePhase,
        const char* ballSlot,
        const b2Body* body,
        const b2Vec2& beforeVelocity,
        const b2Vec2& normalTowardBouncy,
        const b2Vec2& afterVelocity
) {
    const float bodyMass = safeBodyMass(body);
    const float deltaVelocity = IOS_BOUNCY_VELOCITY_DELTA;

    const b2Vec2 expected = iosBouncyVelocity(
            beforeVelocity,
            normalTowardBouncy
    );

    const float errorX = afterVelocity.x - expected.x;
    const float errorY = afterVelocity.y - expected.y;

    golfNativeLogPrint(
            ANDROID_LOG_INFO,
            "GolfNative",
            "GOLF_ANDROID_BUMPER_VALIDATE={"
            "\"runId\":\"%s\","
            "\"shotIndex\":%d,"
            "\"frame\":%d,"
            "\"phase\":\"%s\","
            "\"ballSlot\":\"%s\","
            "\"bouncyVelocityDelta\":%.6f,"
            "\"bodyMassDiagnostic\":%.6f,"
            "\"bouncyDelta\":%.6f,"
            "\"before\":{\"x\":%.6f,\"y\":%.6f},"
            "\"normalTowardBouncy\":{\"x\":%.6f,\"y\":%.6f},"
            "\"expectedAfterBeginContact\":{\"x\":%.6f,\"y\":%.6f},"
            "\"actualAfterBeginContact\":{\"x\":%.6f,\"y\":%.6f},"
            "\"error\":{\"x\":%.6f,\"y\":%.6f}"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            ballSlot,
            IOS_BOUNCY_VELOCITY_DELTA,
            bodyMass,
            deltaVelocity,
            beforeVelocity.x,
            beforeVelocity.y,
            normalTowardBouncy.x,
            normalTowardBouncy.y,
            expected.x,
            expected.y,
            afterVelocity.x,
            afterVelocity.y,
            errorX,
            errorY
    );
}

void GolfContactListener::BeginContact(b2Contact* contact) {
    if (!contact) {
        return;
    }

    b2Fixture* fixtureA = contact->GetFixtureA();
    b2Fixture* fixtureB = contact->GetFixtureB();

    GolfData* dataA = dataForFixture(fixtureA);
    GolfData* dataB = dataForFixture(fixtureB);

    if (!dataA || !dataB) {
        return;
    }

    const bool ballInvolved = isBall(dataA) || isBall(dataB);
    if (!ballInvolved) {
        return;
    }

    b2Body* bodyA = fixtureA ? fixtureA->GetBody() : nullptr;
    b2Body* bodyB = fixtureB ? fixtureB->GetBody() : nullptr;

    const b2Vec2 posA = bodyA ? bodyA->GetPosition() : b2Vec2(0.0f, 0.0f);
    const b2Vec2 posB = bodyB ? bodyB->GetPosition() : b2Vec2(0.0f, 0.0f);
    const b2Vec2 velA = bodyA ? bodyA->GetLinearVelocity() : b2Vec2(0.0f, 0.0f);
    const b2Vec2 velB = bodyB ? bodyB->GetLinearVelocity() : b2Vec2(0.0f, 0.0f);

    b2WorldManifold worldManifold;
    contact->GetWorldManifold(&worldManifold);

    const b2Manifold* localManifold = contact->GetManifold();
    const int pointCount = localManifold ? localManifold->pointCount : 0;

    const b2Vec2 contactPoint =
            pointCount > 0
            ? worldManifold.points[0]
            : b2Vec2(0.0f, 0.0f);

    const float restitutionA = fixtureA ? fixtureA->GetRestitution() : 0.0f;
    const float restitutionB = fixtureB ? fixtureB->GetRestitution() : 0.0f;
    const float contactRestitution = contact->GetRestitution();

    const float frictionA = fixtureA ? fixtureA->GetFriction() : 0.0f;
    const float frictionB = fixtureB ? fixtureB->GetFriction() : 0.0f;
    const float contactFriction = contact->GetFriction();

    b2Vec2 rewrittenVelA = velA;
    b2Vec2 rewrittenVelB = velB;

    bool rewroteA = false;
    bool rewroteB = false;
    bool usedBouncyRewrite = false;
    bool usedNormalRewrite = false;

    if (contact->IsTouching()) {
        const b2Vec2 normal = worldManifold.normal;

        if (isBouncyContact(dataA, dataB)) {
            usedBouncyRewrite = true;

            if (isBall(dataA) && bodyA && bodyA->GetType() == b2_dynamicBody) {
                const b2Vec2 towardBouncy = normalTowardOtherBody(true, normal);

                rewrittenVelA = iosBouncyVelocity(velA, towardBouncy);
                setBodyVelocityLikeIos(bodyA, rewrittenVelA);
                rewroteA = true;

                logBouncyValidation(
                        traceRunId,
                        traceShotIndex,
                        traceFrame,
                        tracePhase,
                        "A",
                        bodyA,
                        velA,
                        towardBouncy,
                        rewrittenVelA
                );
            }

            if (isBall(dataB) && bodyB && bodyB->GetType() == b2_dynamicBody) {
                const b2Vec2 towardBouncy = normalTowardOtherBody(false, normal);

                rewrittenVelB = iosBouncyVelocity(velB, towardBouncy);
                setBodyVelocityLikeIos(bodyB, rewrittenVelB);
                rewroteB = true;

                logBouncyValidation(
                        traceRunId,
                        traceShotIndex,
                        traceFrame,
                        tracePhase,
                        "B",
                        bodyB,
                        velB,
                        towardBouncy,
                        rewrittenVelB
                );
            }
        }

        if (!usedBouncyRewrite && !isBallBallContact(dataA, dataB)) {
            usedNormalRewrite = true;

            if (isBall(dataA) && bodyA && bodyA->GetType() == b2_dynamicBody) {
                const b2Vec2 away = normalAwayFromOtherBody(true, normal);
                rewrittenVelA = iosReflectVelocity(velA, away);
                setBodyVelocityLikeIos(bodyA, rewrittenVelA);
                rewroteA = true;
            }

            if (isBall(dataB) && bodyB && bodyB->GetType() == b2_dynamicBody) {
                const b2Vec2 away = normalAwayFromOtherBody(false, normal);
                rewrittenVelB = iosReflectVelocity(velB, away);
                setBodyVelocityLikeIos(bodyB, rewrittenVelB);
                rewroteB = true;
            }
        }
    }

    golfNativeLogPrint(
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
            "\"aBouncy\":%s,"
            "\"bType\":%d,"
            "\"bTypeName\":\"%s\","
            "\"bKind\":%d,"
            "\"bBouncy\":%s,"
            "\"aRestitution\":%.6f,"
            "\"bRestitution\":%.6f,"
            "\"contactRestitution\":%.6f,"
            "\"aFriction\":%.6f,"
            "\"bFriction\":%.6f,"
            "\"contactFriction\":%.6f,"
            "\"pointCount\":%d,"
            "\"touching\":%s,"
            "\"normal\":{\"x\":%.6f,\"y\":%.6f},"
            "\"point\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bPos\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aVelBefore\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bVelBefore\":{\"x\":%.6f,\"y\":%.6f},"
            "\"aVelAfter\":{\"x\":%.6f,\"y\":%.6f},"
            "\"bVelAfter\":{\"x\":%.6f,\"y\":%.6f},"
            "\"rewroteA\":%s,"
            "\"rewroteB\":%s,"
            "\"iosContactRewrite\":true,"
            "\"usedNormalRewrite\":%s,"
            "\"usedBouncyRewrite\":%s,"
            "\"bouncyDelta\":%.6f"
            "}",
            traceRunId.c_str(),
            traceShotIndex,
            traceFrame,
            tracePhase.c_str(),
            static_cast<int>(dataA->type),
            golfDataTypeName(dataA),
            dataA->kind,
            dataA->bouncy ? "true" : "false",
            static_cast<int>(dataB->type),
            golfDataTypeName(dataB),
            dataB->kind,
            dataB->bouncy ? "true" : "false",
            restitutionA,
            restitutionB,
            contactRestitution,
            frictionA,
            frictionB,
            contactFriction,
            pointCount,
            contact->IsTouching() ? "true" : "false",
            worldManifold.normal.x,
            worldManifold.normal.y,
            contactPoint.x,
            contactPoint.y,
            posA.x,
            posA.y,
            posB.x,
            posB.y,
            velA.x,
            velA.y,
            velB.x,
            velB.y,
            rewrittenVelA.x,
            rewrittenVelA.y,
            rewrittenVelB.x,
            rewrittenVelB.y,
            rewroteA ? "true" : "false",
            rewroteB ? "true" : "false",
            usedNormalRewrite ? "true" : "false",
            usedBouncyRewrite ? "true" : "false",
            isBouncyContact(dataA, dataB)
            ? IOS_BOUNCY_VELOCITY_DELTA
            : 0.0f
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
    const float restitutionA = fixtureA ? fixtureA->GetRestitution() : 0.0f;
    const float restitutionB = fixtureB ? fixtureB->GetRestitution() : 0.0f;
    const float contactRestitution = contact->GetRestitution();

    const float frictionA = fixtureA ? fixtureA->GetFriction() : 0.0f;
    const float frictionB = fixtureB ? fixtureB->GetFriction() : 0.0f;
    const float contactFriction = contact->GetFriction();

    const bool hasNonZeroImpulse =
            normalImpulse0 != 0.0f ||
            normalImpulse1 != 0.0f ||
            tangentImpulse0 != 0.0f ||
            tangentImpulse1 != 0.0f;

    if (isBouncyContact(dataA, dataB) && hasNonZeroImpulse) {
        golfNativeLogPrint(
                ANDROID_LOG_INFO,
                "GolfNative",
                "GOLF_ANDROID_BUMPER_POSTSOLVE={"
                "\"runId\":\"%s\","
                "\"shotIndex\":%d,"
                "\"frame\":%d,"
                "\"phase\":\"%s\","
                "\"aTypeName\":\"%s\","
                "\"aKind\":%d,"
                "\"aBouncy\":%s,"
                "\"bTypeName\":\"%s\","
                "\"bKind\":%d,"
                "\"bBouncy\":%s,"
                "\"normal\":{\"x\":%.6f,\"y\":%.6f},"
                "\"normalImpulse0\":%.6f,"
                "\"tangentImpulse0\":%.6f,"
                "\"aVelPostSolve\":{\"x\":%.6f,\"y\":%.6f},"
                "\"bVelPostSolve\":{\"x\":%.6f,\"y\":%.6f}"
                "}",
                traceRunId.c_str(),
                traceShotIndex,
                traceFrame,
                tracePhase.c_str(),
                typeName(dataA),
                dataA->kind,
                dataA->bouncy ? "true" : "false",
                typeName(dataB),
                dataB->kind,
                dataB->bouncy ? "true" : "false",
                manifold.normal.x,
                manifold.normal.y,
                normalImpulse0,
                tangentImpulse0,
                velA.x,
                velA.y,
                velB.x,
                velB.y
        );
    }

    const b2Vec2 point =
            pointCount > 0 ? manifold.points[0] : b2Vec2_zero;

    if (hasNonZeroImpulse) {
        golfNativeLogPrint(
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
                "\"aRestitution\":%.6f,"
                "\"bRestitution\":%.6f,"
                "\"contactRestitution\":%.6f,"
                "\"aFriction\":%.6f,"
                "\"bFriction\":%.6f,"
                "\"contactFriction\":%.6f,"
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
                restitutionA,
                restitutionB,
                contactRestitution,
                frictionA,
                frictionB,
                contactFriction,
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
}