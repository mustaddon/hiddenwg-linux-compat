#ifdef COMPAT_HAS_CPU_DEVICE_ID_HEADER
#include <asm/cpu_device_id.h>
#endif

#ifndef INTEL_FAM6_SKYLAKE_X
#ifdef INTEL_SKYLAKE_X
#define INTEL_FAM6_SKYLAKE_X INTEL_SKYLAKE_X
#endif
#endif
