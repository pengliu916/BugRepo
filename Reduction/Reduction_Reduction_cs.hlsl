StructuredBuffer<TYPE> buf_srvInput : register(t0);
#if ATOMIC_ACCU
RWByteAddressBuffer buf_uavOutput : register(u0);
#else
RWStructuredBuffer<TYPE> buf_uavOutput : register(u0);
#endif

cbuffer CBdata : register(b0)
{
    uint uSize;
    uint uResultOffset;
    uint uFinalResult;
}

#if ATOMIC_ACCU
void interlockedAddFloat(uint addr, float value)
{
    uint comp, orig = buf_uavOutput.Load(addr);
    [allow_uav_condition]
    do {
        buf_uavOutput.InterlockedCompareExchange(
            addr, comp = orig, asuint(asfloat(orig) + value), orig);
    } while (orig != comp);
}
#endif

groupshared TYPE sharedMem[THREAD];

[numthreads(THREAD, 1, 1)]
void main(uint3 Gid : SV_GroupID, uint3 DTid : SV_DispatchThreadID,
    uint GI : SV_GroupIndex)
{
    uint uIdx = DTid.x * FETCH_COUNT;
    if (uIdx < uSize) {
        sharedMem[GI] = buf_srvInput[uIdx];
    } else {
        sharedMem[GI] = 0;
    }
    [unroll(FETCH_COUNT - 1)]
    for (int i = 1; i < FETCH_COUNT; ++i) {
        if (uIdx + i < uSize) {
            sharedMem[GI] += buf_srvInput[uIdx + i];
        }
    }
    GroupMemoryBarrierWithGroupSync();
#if THREAD >=1024
    if (GI < 512) sharedMem[GI] += sharedMem[GI + 512];
    GroupMemoryBarrierWithGroupSync();
#endif
#if THREAD >= 512
    if (GI < 256) sharedMem[GI] += sharedMem[GI + 256];
    GroupMemoryBarrierWithGroupSync();
#endif
#if THREAD >= 256
    if (GI < 128) sharedMem[GI] += sharedMem[GI + 128];
    GroupMemoryBarrierWithGroupSync();
#endif
#if THREAD >= 128
    if (GI < 64) sharedMem[GI] += sharedMem[GI + 64];
    GroupMemoryBarrierWithGroupSync();
#endif
#if THREAD >= 64
    if (GI < 32) sharedMem[GI] += sharedMem[GI + 32];
#endif
#if THREAD >= 32
    if (GI < 16) sharedMem[GI] += sharedMem[GI + 16];
#endif
    if (GI < 8) sharedMem[GI] += sharedMem[GI + 8];
    if (GI < 4) sharedMem[GI] += sharedMem[GI + 4];
    if (GI < 2) sharedMem[GI] += sharedMem[GI + 2];
    if (GI < 1) sharedMem[GI] += sharedMem[GI + 1];

    if (GI == 0) {
#if ATOMIC_ACCU
#   if DATAWIDTH == 4
        interlockedAddFloat(uResultOffset + 0, sharedMem[0].x);
        interlockedAddFloat(uResultOffset + 4, sharedMem[0].y);
        interlockedAddFloat(uResultOffset + 8, sharedMem[0].z);
        interlockedAddFloat(uResultOffset + 12, sharedMem[0].w);
#   else
        interlockedAddFloat(uResultOffset, sharedMem[0]);
#   endif
#else
        buf_uavOutput[uFinalResult ? uResultOffset : Gid.x] = sharedMem[0];
#endif
    }
}