#ifndef OPENBUBBLES_GOLF_CONTACT_LISTENER_H
#define OPENBUBBLES_GOLF_CONTACT_LISTENER_H

#include <Box2D/Box2D.h>
#include <string>

class GolfContactListener : public b2ContactListener {
public:
    void setTraceContext(
            const char* runId,
            int shotIndex,
            int frame,
            const char* phase
    );

    void clearTraceContext();

    void BeginContact(b2Contact* contact) override;
    void PreSolve(b2Contact* contact, const b2Manifold* oldManifold) override;
    void PostSolve(b2Contact* contact, const b2ContactImpulse* impulse) override;

private:
    std::string traceRunId;
    int traceShotIndex = -1;
    int traceFrame = -1;
    std::string tracePhase;
};

#endif