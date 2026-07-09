#include "PoolBall.h"
#include "PoolTable.h"
#include <android/log.h>
#include <cmath>

void set_custom_slop(float32 slop);

namespace {
    constexpr float POCKET_RADIUS = 20.0f;
    constexpr float POCKET_SINK_FACTOR = 0.5f;
    constexpr float POCKET_CAPTURE_RADIUS = POCKET_RADIUS * POCKET_SINK_FACTOR;
    constexpr float REPLAY_KEEP_OUT_RADIUS = 24.0f;
    constexpr float REPLAY_KEEP_OUT_MIN_SPEED_SQ = 4.0f;

    constexpr int CUE_POCKET_RESET_FRAMES = 75;
    constexpr int CUE_MIDDLE_POCKET_RESET_FRAMES = 12;
    constexpr int OBJECT_POCKET_REMOVE_MIN_FRAMES = 70;
    constexpr float POCKET_PULL_SPEED = 4.0f;
    constexpr float POCKET_KILL_MIN_X = 100.0f;
    constexpr float POCKET_KILL_MAX_X = 684.0f;
    constexpr float POCKET_KILL_MIN_Y = 100.0f;
    constexpr float POCKET_KILL_MAX_Y = 340.0f;
    constexpr float POCKET_PULL_Y_SCALE = 0.50f;
    constexpr float OBJECT_POCKET_HOLD_EPSILON = 0.05f;
}

PoolBall::PoolBall(PoolTable *table, b2Body *body, int number, int shouldGoIn, float* outputs)
        : table(table),
          body(body),
          number(number),
          outputs(outputs),
          hole(-1, -1),
          hitHole(-1, -1),
          shouldGoIn(shouldGoIn),
          data({
                       .type = PoolData::Type::Ball,
                       .data = this,
               })
{
    body->SetUserData(&data);
}

void PoolBall::writeOutputs() {
    if (outputs == nullptr) {
        return;
    }

    if (body != nullptr) {
        outputs[0] = body->GetPosition().x;
        outputs[1] = body->GetPosition().y;
        outputs[2] = body->GetAngle();
        outputs[7] = body->GetAngularVelocity();
    }

    outputs[3] = (float)sunkOrder;
    outputs[4] = (float)numberHit;
    outputs[5] = hole.x;
    outputs[6] = hole.y;
}

void PoolBall::markSunk(const b2Vec2& tableHole, const char* reason) {
    if (hole.x == -1.0f) {
        hole = tableHole;
        pocketFrames = 0;
        pocketBodyRemoved = false;

        b2Vec2 pos = body->GetPosition();
        b2Vec2 toHole = tableHole - pos;
        float dist = toHole.Length();

        __android_log_print(
                ANDROID_LOG_VERBOSE,
                "PoolPocket",
                "pocket_enter number=%d frame=%u x=%.6f y=%.6f dist=%.6f threshold=%.6f hole=(%.6f,%.6f) reason=%s",
                number,
                table->frame,
                pos.x,
                pos.y,
                dist,
                POCKET_CAPTURE_RADIUS,
                tableHole.x,
                tableHole.y,
                reason
        );
    }

    writeOutputs();
}

void PoolBall::assignSunkOrder(const char* reason) {
    if (number == 0 || sunkOrder != -1) {
        return;
    }

    sunkOrder = table->pocketNumber;
    table->pocketNumber++;

    __android_log_print(
            ANDROID_LOG_VERBOSE,
            "PoolPocket",
            "ball_sunk number=%d order=%d frames=%d reason=%s",
            number,
            sunkOrder,
            pocketFrames,
            reason
    );
}

bool PoolBall::isInsidePocketKillBounds() const {
    b2Vec2 pos = body->GetPosition();
    return (
            pos.x > POCKET_KILL_MIN_X &&
            pos.x < POCKET_KILL_MAX_X &&
            pos.y > POCKET_KILL_MIN_Y &&
            pos.y < POCKET_KILL_MAX_Y
    );
}

void PoolBall::stepPocketedBall() {
    if (pocketBodyRemoved || body == nullptr) {
        return;
    }

    pocketFrames += 1;

    b2Vec2 towardCenter(392.0f, 220.0f);
    towardCenter -= body->GetPosition();

    if (towardCenter.LengthSquared() > 0.0001f) {
        towardCenter.Normalize();

        towardCenter.x *= POCKET_PULL_SPEED;
        towardCenter.y *= POCKET_PULL_SPEED * POCKET_PULL_Y_SCALE;

        towardCenter += body->GetLinearVelocity();
        body->SetLinearVelocity(towardCenter);
    }

    bool insideKill = isInsidePocketKillBounds();

    if (
            number != 0 &&
            insideKill &&
            pocketFrames < OBJECT_POCKET_REMOVE_MIN_FRAMES &&
            hole.y != -1.0f
            ) {
        b2Vec2 pos = body->GetPosition();
        b2Vec2 vel = body->GetLinearVelocity();

        if (hole.y > 220.0f) {
            pos.y = POCKET_KILL_MAX_Y - OBJECT_POCKET_HOLD_EPSILON;

            if (vel.y < 0.0f) {
                vel.y = 0.0f;
            }
        } else {
            pos.y = POCKET_KILL_MIN_Y + OBJECT_POCKET_HOLD_EPSILON;

            if (vel.y > 0.0f) {
                vel.y = 0.0f;
            }
        }

        body->SetTransform(pos, body->GetAngle());
        body->SetLinearVelocity(vel);

        insideKill = isInsidePocketKillBounds();
    }

    if (pocketFrames % 5 == 0 || insideKill) {
        b2Vec2 pos = body->GetPosition();
        b2Vec2 vel = body->GetLinearVelocity();

        __android_log_print(
                ANDROID_LOG_VERBOSE,
                "PoolPocket",
                "pocket_roll number=%d frames=%d x=%.6f y=%.6f vx=%.6f vy=%.6f av=%.6f insideKill=%d",
                number,
                pocketFrames,
                pos.x,
                pos.y,
                vel.x,
                vel.y,
                body->GetAngularVelocity(),
                insideKill ? 1 : 0
        );
    }

    if (number == 0) {
        bool middlePocket =
                hole.x > 391.5f &&
                hole.x < 392.5f;

        int cueResetFrames =
                middlePocket
                ? CUE_MIDDLE_POCKET_RESET_FRAMES
                : CUE_POCKET_RESET_FRAMES;

        if (pocketFrames >= cueResetFrames) {
            body->SetTransform(b2Vec2(392.0f, 220.0f), body->GetAngle());
            body->SetLinearVelocity(b2Vec2_zero);
            body->SetAngularVelocity(0.0f);
            body->SetAwake(false);

            hole = b2Vec2(-1.0f, -1.0f);
            hitHole = b2Vec2(-1.0f, -1.0f);
            pocketFrames = -1;

            writeOutputs();

            __android_log_print(
                    ANDROID_LOG_VERBOSE,
                    "PoolPocket",
                    "cue_pocket_reset frame=%u frames=%d middle=%d x=392.000000 y=220.000000",
                    table->frame,
                    cueResetFrames,
                    middlePocket ? 1 : 0
            );
        }

        return;
    }

    if (!insideKill || pocketFrames < OBJECT_POCKET_REMOVE_MIN_FRAMES) {
        return;
    }

    assignSunkOrder("kill_zone");

    b2Vec2 removedPos = body->GetPosition();

    body->SetLinearVelocity(b2Vec2_zero);
    body->SetAngularVelocity(0.0f);
    body->SetAwake(false);
    writeOutputs();

    table->world.DestroyBody(body);
    body = nullptr;
    pocketBodyRemoved = true;

    __android_log_print(
            ANDROID_LOG_VERBOSE,
            "PoolPocket",
            "pocket_body_removed number=%d order=%d frames=%d x=%.6f y=%.6f",
            number,
            sunkOrder,
            pocketFrames,
            removedPos.x,
            removedPos.y
    );
}

void PoolBall::keepOutOfPocket(const b2Vec2& tableHole, float dist) {
    b2Vec2 away = body->GetPosition() - tableHole;
    if (away.LengthSquared() < 0.0001f) {
        away = b2Vec2(1.0f, 0.0f);
    } else {
        away.Normalize();
    }

    b2Vec2 safeOffset = away;
    safeOffset *= REPLAY_KEEP_OUT_RADIUS;
    b2Vec2 safePos = tableHole + safeOffset;

    body->SetTransform(safePos, body->GetAngle());

    b2Vec2 velocity = body->GetLinearVelocity();
    if (velocity.LengthSquared() > 0.0f) {
        b2Vec2 towardHole = tableHole - safePos;
        towardHole.Normalize();

        float towardSpeed = b2Dot(velocity, towardHole);
        if (towardSpeed > 0.0f) {
            b2Vec2 correction = towardHole;
            correction *= towardSpeed * 1.35f;
            velocity -= correction;
        }
    }

    velocity *= 0.35f;

    if (velocity.LengthSquared() < REPLAY_KEEP_OUT_MIN_SPEED_SQ) {
        velocity = b2Vec2_zero;
    }

    body->SetLinearVelocity(velocity);
    body->SetAngularVelocity(body->GetAngularVelocity() * 0.35f);

    hitHole = b2Vec2(-1.0f, -1.0f);

    __android_log_print(
            ANDROID_LOG_VERBOSE,
            "PoolPocket",
            "replay_keep_out number=%d shouldGoIn=%d dist=%.6f hole=(%.6f,%.6f) pos=(%.6f,%.6f)",
            number,
            shouldGoIn,
            dist,
            tableHole.x,
            tableHole.y,
            safePos.x,
            safePos.y
    );
}

bool PoolBall::step() {
    if (body == nullptr) {
        writeOutputs();
        return false;
    }

    writeOutputs();

    if (hole.x != -1.0f) {
        stepPocketedBall();
        writeOutputs();
        return !pocketBodyRemoved && pocketFrames != -1;
    }

    if (sunkOrder != -1) {
        body->SetLinearVelocity(b2Vec2_zero);
        body->SetAngularVelocity(0.0f);
        body->SetAwake(false);
        writeOutputs();
        return false;
    }

    if (std::abs(body->GetAngularVelocity()) < 3.0f) {
        float adjustedVelocity = body->GetAngularVelocity() * 0.8f;
        body->SetAngularVelocity(adjustedVelocity);
    }

    b2Vec2 currentVel = body->GetLinearVelocity();

    if (currentVel.LengthSquared() > 0.0f) {
        float speed = currentVel.Length();
        float fric1 = 0.99375f;
        float fric2 = 0.425f;

        float newSpeed = (speed - fric2) * fric1;
        if (newSpeed < 2.0f) {
            newSpeed = 0.0f;
        }

        if (speed > 0.0f) {
            currentVel *= newSpeed / speed;
            body->SetLinearVelocity(currentVel);
        }

        if (number == 0 && table->debugTraceEnabled) {
            auto transform = body->GetTransform();
            __android_log_print(
                    ANDROID_LOG_VERBOSE,
                    "PoolCue",
                    "cue_state frame=%u x=%.6f y=%.6f qs=%.6f qc=%.6f vx=%.6f vy=%.6f av=%.6f",
                    table->frame,
                    transform.p.x,
                    transform.p.y,
                    transform.q.s,
                    transform.q.c,
                    body->GetLinearVelocity().x,
                    body->GetLinearVelocity().y,
                    body->GetAngularVelocity()
            );
        }
    }

    if (std::abs(body->GetAngularVelocity()) < 0.1f) {
        body->SetAngularVelocity(0.0f);
    }

    for (auto& tableHole : table->holes) {
        b2Vec2 holeVector = tableHole - body->GetPosition();
        float dist = holeVector.Length();

        bool touchedPocketWall =
                hitHole.x == tableHole.x &&
                hitHole.y == tableHole.y;

        bool replayMustStayOut =
                number != 0 &&
                shouldGoIn == SHOULD_NOT_GO_IN;

        if (replayMustStayOut) {
            if (dist < REPLAY_KEEP_OUT_RADIUS || (touchedPocketWall && dist < POCKET_RADIUS * 1.75f)) {
                keepOutOfPocket(tableHole, dist);
            }
            continue;
        }

        bool captureByRadius = dist < POCKET_CAPTURE_RADIUS;
        bool captureByWall = touchedPocketWall;

        bool replayPocketAssist =
                number != 0 &&
                shouldGoIn == SHOULD_GO_IN &&
                touchedPocketWall &&
                dist < POCKET_RADIUS * 1.75f;

        if (captureByRadius || captureByWall || replayPocketAssist) {
            markSunk(
                    tableHole,
                    captureByWall ? "wall_contact" : (replayPocketAssist ? "replay_wall_contact" : "radius")
            );
            break;
        }

        if (dist < POCKET_RADIUS) {
            holeVector *= 5.0f;
            holeVector += body->GetLinearVelocity();
            body->SetLinearVelocity(holeVector);
        }
    }

    if (table->cueDelay >= 3) {
        body->GetFixtureList()->SetDensity(1.0f);
        body->ResetMassData();
        set_custom_slop(0.005f);
    }

    if (number == 0) {
        spinPower *= 0.94f;

        if (table->cueDelay >= 3 && body->GetLinearVelocity().LengthSquared() > 0.0f && spinPower > 0.1f) {
            b2Vec2 mySpin(spinDir);
            mySpin *= spinPower;
            mySpin += body->GetLinearVelocity();
            body->SetLinearVelocity(mySpin);
        }
    }

    writeOutputs();

    if (hole.x != -1.0f) {
        return true;
    }

    return (
            body->GetAngularVelocity() != 0.0f ||
            body->GetLinearVelocity().LengthSquared() > 0.0f
    );
}

void PoolBall::hit(float dir, float power, float spinX, float spinY) {
    table->cueDelay = -1;
    table->pocketNumber = 0;

    hole = b2Vec2(-1.0f, -1.0f);
    hitHole = b2Vec2(-1.0f, -1.0f);
    pocketFrames = -1;
    pocketBodyRemoved = false;

    b2Vec2 vel(std::cos(dir), std::sin(dir));
    vel *= power;
    body->SetLinearVelocity(vel);
    body->SetAwake(true);
    body->SetActive(true);

    float powerFrac = power / 2000.0f;

    spinPower = powerFrac * std::abs(spinY);
    spinDir = b2Vec2(std::cos(dir), std::sin(dir));
    if (spinY < 0.0f) {
        spinDir *= -1.0f;
    }

    auto transform = body->GetTransform();
    __android_log_print(
            ANDROID_LOG_VERBOSE,
            "PoolHit",
            "hit number=%d dir=%.6f power=%.6f spinX=%.6f spinY=%.6f x=%.6f y=%.6f qs=%.6f qc=%.6f shouldGoIn=%d",
            number,
            dir,
            power,
            spinX,
            spinY,
            transform.p.x,
            transform.p.y,
            transform.q.s,
            transform.q.c,
            shouldGoIn
    );

    float angularVel = powerFrac * spinX;
    if (std::abs(angularVel) < 50.0f) {
        angularVel = 0.0f;
    }

    body->SetAngularVelocity(angularVel);
}

PoolBall::~PoolBall() {
    if (body != nullptr) {
        table->world.DestroyBody(body);
        body = nullptr;
    }
}