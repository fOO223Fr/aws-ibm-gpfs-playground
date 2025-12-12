# OCPNAS-312 Validation Summary - Veritas InfoScale 9.1.0

## Executive Summary

**Objective:** Validate that Veritas InfoScale 9.1.0 resolves the PV provisioning race condition (OCPNAS-312) when cloning large batches of virtual machines, specifically testing the ability to successfully provision 200 VMs concurrently without coordination mechanisms (sleep calls) that were required in version 8.0.400.

**Result:** ✅ **VALIDATION SUCCESSFUL**

InfoScale 9.1.0 successfully provisions 200 VMs concurrently without race conditions or stuck PVs. The target requirement is met, and the solution demonstrates production-ready stability.

---

## Test Environment

**Infrastructure:**
- **Platform:** OpenShift Container Platform on AWS
- **Worker Nodes:** 3× bare metal instances (c5n.metal)
- **InfoScale Version:** 9.1.0 (upgraded from 8.0.400)
- **Storage Configuration:** Multi-attach io2 EBS volumes, shared storage enabled

**Test Baseline Configuration:**
- **InfoScale Pool:** 1× 500GB disk (concat mode, default)
- **VM Storage:** 1GB per VM (Cirros image)
- **Clone Method:** CSI full-copy clone via OpenShift Virtualization DataVolumes

**Note:** This environment mirrors the original 8.0.400 testing conditions where even 50 VMs could not be successfully provisioned.

---

## Validation Results

### Primary Test Cases (Default Configuration - 1× 500GB Disk)

| VM Count | Result | Success Rate | Notes |
|----------|--------|--------------|-------|
| **50 VMs** | ✅ Success | 100% | Provisions smoothly, ~10s per VM |
| **100 VMs** | ✅ Success | 100% | Provisions smoothly, ~10s per VM |
| **200 VMs** | ✅ **Success** | **100%** | **OCPNAS-312 requirement met** ✓ |
| **400 VMs** | ⚠️ Partial | 99.75% | Capacity-constrained (see analysis below) |

### Key Finding: 200 VM Requirement

✅ **The core OCPNAS-312 requirement (200 concurrent VMs) is validated successfully.**

InfoScale 9.1.0 provisions all 200 VMs without:
- PVs getting stuck during provisioning
- Race conditions requiring coordination mechanisms
- Manual intervention or workarounds
- Artificial sleep calls between operations

---

## 400 VM Test Case Analysis

### Observed Behavior

**Test Run 1 (Extended Duration):**
- Duration: 6 hours 32 minutes
- Result: 399/400 VMs running (99.75% success)
- Average: 59 seconds per VM

**Test Run 2:**
- Result: Lower success rate
- Cause: Hit design limits faster

### Root Cause: Temporary Storage Overhead

**OpenShift Virtualization Clone Behavior:**

When cloning VMs using CSI full-copy clone, the system creates:
1. **Temporary PVC** - Used during cloning process
2. **Permanent PVC** - Attached to the VM

The temporary PVC is deleted only after the VM reaches Running state.

**Capacity Impact:**
- **Expected:** 400 VMs × 1GB = 400GB needed
- **Actual:** 400 VMs × 2GB = **800GB needed during provisioning**
- **Available:** 500GB storage pool
- **Result:** Capacity exhaustion causes provisioning delays/failures

**Design Constraint Hit:**
- InfoScale has a design limit for concurrent snapshot/clone operations from a single source
- Default limit: ~32 snapshot flex clones
- When capacity is constrained AND limit is reached, some VMs fail to provision

### Assessment

The 400 VM partial success is **not an InfoScale 9.1.0 deficiency** but rather:
1. **Insufficient capacity** for the workload (need 800GB, have 500GB)
2. **Temporary PVC accumulation** when capacity is tight
3. **Design limits** being reached under extreme capacity pressure

**Recommendation:** For batch cloning of N VMs, provision storage capacity of **2× N GB** to account for temporary PVC overhead during provisioning.

---

## Performance Optimization Tests

### Stripe Mode Configuration

Following recommendations from InfoScale engineering, additional tests were conducted using **stripe layout** across multiple disks.

**Test Configuration A: 2× 250GB Disks (Stripe Mode)**
- Total Capacity: 500GB
- Layout: RAID 0 stripe across 2 disks
- nstripe: 2

**Results:**
- **400 VMs:** 399/400 running (99.75%)
- **Duration:** 2 hours 51 minutes
- **Average:** ~26 seconds per VM
- **Consistent success** across multiple runs

**Performance Improvement:**
- **2.3× faster** than single disk (26s vs 59s per VM)
- Temporary PVCs released more quickly
- Did not hit snapshot flex clone limit
- Better parallel I/O throughput

**Test Configuration B: 2× 300GB Disks (Concat Mode)**
- Total Capacity: 600GB
- Layout: Concat (default, no striping)

**Results:**
- Performance between single disk and stripe configurations
- Adequate capacity but suboptimal I/O patterns

### Key Insight

**Stripe layout provides significant performance benefits:**
- ✅ Faster parallel I/O across multiple disks
- ✅ Better temporary PVC management
- ✅ Improved provisioning throughput
- ✅ More consistent behavior under load

**Recommendation:** Use stripe layout with multiple disks for production VM cloning workloads.

---

## Conclusion

### OCPNAS-312 Validation: ✅ PASSED

Veritas InfoScale 9.1.0 successfully resolves the PV provisioning race condition documented in OCPNAS-141/OCPNAS-312.

**Key Achievements:**
1. ✅ **200 VMs provision successfully** without race conditions or stuck PVs
2. ✅ **No coordination mechanisms required** (no sleep calls, no manual intervention)
3. ✅ **Consistent performance** across multiple test runs
4. ✅ **Zero PV failures** during provisioning for target workload
