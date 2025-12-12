# Veritas InfoScale (Arctera) - Complete Guide

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Available Operations](#available-operations)
- [Installation](#installation)
- [Cluster Management](#cluster-management)
- [Operations & Maintenance](#operations--maintenance)
- [Testing & Verification](#testing--verification)
- [Performance Testing (OCPNAS-312)](#performance-testing-ocpnas-312)
- [StorageClass Configuration](#storageclass-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers Veritas InfoScale 9.1.0 deployment, management, and testing on OpenShift Container Platform. InfoScale provides enterprise-grade storage management with features like volume management, snapshots, and high availability.

**Key Features:**
- Dynamic disk management with VxVM
- Multiple storage layouts (stripe, mirror, RAID 10, etc.)
- CSI driver for Kubernetes integration
- KubeVirt virtual machine storage support
- Concurrent PVC provisioning (OCPNAS-312 fix validated)

---

## Quick Start

```bash
# Full stack deployment (OCP + InfoScale)
make veritas

# Install on existing OCP cluster
make veritas TAGS=dependencies,install

# Test the installation
make veritas TAGS=test
```

---

## Available Operations

| Command | Description | Use Case |
|---------|-------------|----------|
| `make veritas` | Full deployment: OCP + dependencies + InfoScale | Fresh cluster setup |
| `make veritas TAGS=dependencies` | Install NFD, cert-manager, virtualization | Prerequisites only |
| `make veritas TAGS=install` | Install InfoScale operator + cluster (auto-detect) | InfoScale stack only |
| `make veritas TAGS=install -e manual_disk_selection=true` | Install with interactive disk selection | Choose specific disks |
| `make veritas TAGS=cluster-recreate` | Delete & recreate cluster (auto-detect) | Change disk config |
| `make veritas TAGS=cluster-recreate -e manual_disk_selection=true` | Interactive disk selection | Choose specific disks |
| `make veritas TAGS=test` | Run basic functionality test | Verify cluster health |
| `make veritas TAGS=ops -e operation=free-space` | Show available space in disk group | Check capacity |
| `make veritas TAGS=ops -e operation=clean` | Wipe all non-boot disks | Reset disks |
| `make veritas TAGS=cleanup` | Delete all InfoScale resources | Complete teardown |
| `make veritas TAGS=perf-test` | Performance testing (default 10 VMs) | Validate performance |

---

## Installation

### Full Automated Installation

**Command:**
```bash
make veritas
```

**Process:**
1. Provisions OCP cluster (3 masters + 3 workers by default)
2. Installs dependencies:
   - Node Feature Discovery (NFD)
   - Cert Manager
   - OpenShift Virtualization
3. Installs InfoScale operator
4. Creates Veritas license
5. Auto-detects all non-boot multi-attach volumes
6. Creates InfoScaleCluster with detected disks
7. Creates StorageClass (sets as default)
8. Creates VolumeSnapshotClass

**Disk Auto-Detection:**
- ✅ Scans all NVMe devices on worker nodes
- ✅ Automatically excludes boot disk
- ✅ Uses all remaining disks for InfoScale cluster
- ✅ No manual configuration needed

**Expected Duration:** 30-45 minutes (depending on OCP install time)

### Install on Existing OCP Cluster

**Auto-Detection Mode:**
```bash
make veritas TAGS=dependencies,install
```

**Manual Disk Selection Mode:**
```bash
make veritas TAGS=dependencies,install EXTRA_VARS="-e manual_disk_selection=true"
```

**Interactive Prompt:**
```
========================================================================
                    AVAILABLE DISKS
========================================================================
Num   Device Path (by-path)                             Size
------------------------------------------------------------------------
  1   /dev/disk/by-path/pci-0000:6c:00.0-nvme-1        250GB
  2   /dev/disk/by-path/pci-0000:77:00.0-nvme-1        250GB
  3   /dev/disk/by-path/pci-0000:69:00.0-nvme-1        500GB
========================================================================

Enter disk numbers to include (comma-separated, e.g., 1,2 or 1): 1,2
```

### Override with Configuration File

**In `overrides.yml`:**
```yaml
# Specify exact disks (bypasses auto-detection)
infoscale_include_devices:
  - "/dev/disk/by-path/pci-0000:6c:00.0-nvme-1"
  - "/dev/disk/by-path/pci-0000:77:00.0-nvme-1"

# StorageClass configuration (optional)
infoscale_layout: "stripe"
infoscale_nstripe: 2
```

**Then run:**
```bash
make veritas TAGS=install
```

---

## Cluster Management

### Recreate Cluster (Auto-Detection)

Delete and recreate InfoScaleCluster without reinstalling operator:

**Command:**
```bash
make veritas TAGS=cluster-recreate
```

**Process:**
1. Deletes InfoScaleCluster, StorageClass, VolumeSnapshotClass
2. Waits 10 seconds for cleanup
3. Gets worker node list
4. **Cleans all disk signatures** with `wipefs -a` on all nodes
5. Auto-detects available disks
6. Recreates InfoScaleCluster with detected disks
7. Recreates StorageClass and VolumeSnapshotClass
8. Patches StorageProfile for KubeVirt

**Preserves:** InfoScale operator, License, namespace

**Use Cases:**
- Change disk configuration
- Switch between cluster layouts
- Recover from unhealthy cluster state
- Test different storage configurations

### Recreate Cluster (Manual Selection)

**Command:**
```bash
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
```

**Interactive Flow:**
1. Displays available disks in formatted table
2. Prompts for disk numbers (comma-separated)
3. Confirms selection
4. Proceeds with cluster creation

**Example Session:**
```bash
$ make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"

Available Disks:
Num   Device Path                                       Size
  1   /dev/disk/by-path/pci-0000:6c:00.0-nvme-1        250GB
  2   /dev/disk/by-path/pci-0000:77:00.0-nvme-1        250GB
  3   /dev/disk/by-path/pci-0000:69:00.0-nvme-1        500GB

Enter disk numbers: 1,2

Selected Disks:
  1. /dev/disk/by-path/pci-0000:6c:00.0-nvme-1
  2. /dev/disk/by-path/pci-0000:77:00.0-nvme-1

Total Disks: 2

StorageClass configuration:
  Layout: stripe
  Stripe Columns: 2

Proceed? [Enter]
```

### Multiple Cluster Configurations

**Scenario:** Development license allows 1 cluster at a time. Use `cluster-recreate` to switch:

**Configuration A - Two 250GB Disks (RAID 0):**
```bash
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 1,2
# Result: 500GB capacity, stripe layout, high performance
```

**Configuration B - One 500GB Disk:**
```bash
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 3
# Result: 500GB capacity, single disk, simple layout
```

**Configuration C - All Three Disks (RAID 0):**
```bash
make veritas TAGS=cluster-recreate
# Auto-detects all 3 disks
# Result: 1TB capacity, stripe across 3 disks, maximum performance
```

---

## Operations & Maintenance

### Check Available Space

**Command:**
```bash
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"
```

**Output:**
```
========================================================================
           AVAILABLE SPACE SUMMARY
========================================================================
  Disk Group:     vrts_kube_dg-22241
  Total Sectors:  718535744 sectors (512 bytes/sector)
  Total Bytes:    367890300928 bytes
  Available:      342.62GB
========================================================================
```

**Use Cases:**
- Monitor capacity before running large VM tests
- Verify space after provisioning workloads
- Capacity planning

### Clean Disks

**Command:**
```bash
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"
```

**What It Does:**
- Runs `wipefs -a` on all non-boot NVMe devices
- Executes on all worker nodes
- Automatically excludes boot disk
- Removes all filesystem signatures

**Output:**
```
✓ Disk Cleanup Complete
All non-boot disks have been cleaned on all 3 worker nodes.
Disks are now ready for InfoScale initialization.
```

**Use Cases:**
- Before switching disk configurations
- Troubleshooting "online invalid" status
- Recovering from failed cluster creation
- Preparing disks for fresh cluster

**⚠️ Warning:** This destroys all data on non-boot disks. Use with caution.

---

## Testing & Verification

### Basic Functionality Test

**Command:**
```bash
make veritas TAGS=test
```

**Test Steps:**
1. Verifies InfoScaleCluster is Running and Healthy
2. Creates PVC: `infoscale-claim` (1Gi)
3. Deploys test workload: `containertools` Deployment
4. Waits for PVC to bind (max 60 seconds)
5. Waits for pod to run (max 60 seconds)
6. Cleans up test resources (deletes Deployment and PVC)

**Expected Output:**
```
TASK [Assert InfoScaleCluster is Running, Healthy] ****
ok: [localhost] => {
    "changed": false,
    "msg": "InfoScaleCluster is Running, Healthy, and has 1 diskgroup(s)"
}

✓ All assertions passed
```

**Exit Codes:**
- `0` = Success (cluster healthy, PVC provisioning works)
- `Non-zero` = Failure (check output for details)

### Manual Health Checks

**Check Cluster Status:**
```bash
# Quick status
oc get infoscalecluster -n infoscale-vtas

# Expected output:
# NAME                   VERSION   CLUSTERID   STATE     DISKGROUPS           STATUS
# infoscalecluster-dev   9.1.0     12345       Running   vrts_kube_dg-12345   Healthy
```

**Check Disk Status:**
```bash
# Get InfoScale pod
POD=$(oc get pods -n infoscale-vtas -l app.kubernetes.io/name=infoscale-sds -o jsonpath='{.items[0].metadata.name}')

# Check disks
oc exec -n infoscale-vtas $POD -- vxdisk list

# Expected output:
# DEVICE          TYPE         DISK         GROUP              STATUS
# node001_nvme1_0 auto:cdsdisk node000_...  vrts_kube_dg-...   online shared  ← ACTIVE
# node001_nvme2_0 auto:none    -            -                  online invalid ← UNUSED
```

**Check Disk Groups:**
```bash
oc exec -n infoscale-vtas $POD -- vxdg list

# Expected output:
# NAME               STATE                   ID
# vrts_kube_dg-12345 enabled,shared,cds      ...
```

**Check Storage Objects:**
```bash
# StorageClass
oc get sc infoscale

# VolumeSnapshotClass
oc get volumesnapshotclass infoscale-snapshot

# Check if default StorageClass
oc get sc | grep "(default)"
```

---

## Performance Testing (OCPNAS-312)

### Purpose

Validate Veritas InfoScale 9.1.0 resolves PV provisioning concurrency issues (race condition causing PVs to get stuck) when cloning large batches of VMs simultaneously.

**Target:** Successfully provision 200 VMs concurrently without stuck PVs

### Test Commands

**Baseline Tests:**
```bash
# 50 VMs (~5-15 minutes)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"

# 100 VMs (~15-30 minutes)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100"
```

**OCPNAS-312 Requirement:**
```bash
# 200 VMs (~30-60 minutes) - Primary validation
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"
```

**Stress Test:**
```bash
# 400 VMs (~60+ minutes)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=400"
```

**Debug/Development:**
```bash
# Quick test with clean results
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=10 -e clean_results=true"

# Default (10 VMs, keep existing results)
make veritas TAGS=perf-test
```

### Monitoring Tests

**Terminal 1 - Run Test:**
```bash
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"
```

**Terminal 2 - Watch Progress:**
```bash
watch -n 1 cat /tmp/veritas-vm-provisioning-status.log
```

**Real-Time Status:**
```
========================================================================
  VERITAS INFOSCALE PERFORMANCE TEST - VM Cloning Monitor
  OCPNAS-312 Concurrency Validation
========================================================================
Elapsed Time: [15:23] | Last Updated: 14:30:45

STATUS SUMMARY:
  Running:        180
  Stopped:        0
  Provisioning:   20
  Target:         200 VMs Running

  Time-series samples collected: 15
  Press Ctrl+C to interrupt and generate partial report
========================================================================
```

### Test Features

**Infinite Timeout:**
- No 600-second limit
- Runs until all VMs reach Running state
- Or user interrupts with Ctrl+C

**Graceful Interruption:**
- Press `Ctrl+C` to stop
- Ansible handles interruption gracefully
- Generates partial report with current state
- Creates CSV and TXT files with collected data
- Preserves `test-vms` namespace for inspection

**Time-Series Data Collection:**
- Sampled every 1 minute throughout test
- Only collected for 50, 100, 200, 400 VM tests
- Other VM counts (e.g., 10) skip time-series
- Saved to shared CSV for comparison graphing

### Test Results

**Results Location:** `results-veritas-9.1/` directory at project root

**Generated Files:**

#### 1. Summary CSV
**Filename:** `veritas-9.1-ga-perf-test-{num_vms}vms.csv`

**Format:**
```csv
num_vms_requested,num_vms_running,duration_seconds,avg_seconds_per_vm,success_rate_percent,test_status
200,200,1847,9.24,100.0,SUCCESS
```

**Columns:**
- `num_vms_requested`: Target VM count
- `num_vms_running`: VMs that reached Running state
- `duration_seconds`: Total test duration
- `avg_seconds_per_vm`: Average provisioning time
- `success_rate_percent`: Success percentage
- `test_status`: PASSED, PARTIAL, or FAILED

#### 2. Cluster Information Text
**Filename:** `veritas-9.1-ga-perf-test-{num_vms}vms-cluster-info.txt`

**Contents:**
- Test execution information (date, status, duration)
- OpenShift cluster configuration (nodes, CPU, memory)
- InfoScale storage configuration (version, disk groups, disks)
- Resource utilization analysis (CPU, memory, pods, storage)
- VM specifications
- Test parameters

**Example:**
```
========================================================================
VERITAS INFOSCALE 9.1 GA - PERFORMANCE TEST CLUSTER INFORMATION
OCPNAS-312 Concurrency Validation
========================================================================

TEST EXECUTION INFORMATION
------------------------------------------------------------------------
Test Date:               2025-12-12 16:54:43 UTC
Test Status:             SUCCESS
VMs Requested:           200
VMs Successfully Running:200
Success Rate:            100.0%
Total Duration:          1847s (30.8 minutes)
Avg Time per VM:         9.24s

OPENSHIFT CLUSTER CONFIGURATION
------------------------------------------------------------------------
Worker Nodes:            3
Instance Type:           c5n.metal
vCPU per Node:           72 cores
Memory per Node:         192 GB
...
```

#### 3. Time-Series CSV (Shared)
**Filename:** `veritas-9.1-ga-perf-test-summary-timeseries.csv`

**Purpose:** Compare provisioning timelines across different VM counts

**Format:**
```csv
elapsed_minutes,vms_50,vms_100,vms_200,vms_400
0,0,0,0,0
1,10,20,40,78
2,25,45,88,165
3,40,75,145,268
4,50,95,185,352
5,50,100,200,388
6,,,200,400
```

**Usage:** Import to Google Sheets → Create line chart

**Note:** Only populated for 50, 100, 200, 400 VM tests

### Checking Test Status

**View VMs:**
```bash
oc get vms -n test-vms
oc get vms -n test-vms -o wide
```

**Check PVCs:**
```bash
oc get pvc -n test-vms
oc get pvc -n test-vms | grep -v Bound  # Should be empty
```

**Check DataVolumes:**
```bash
oc get datavolumes -n test-vms
```

**Verify No Stuck PVs (OCPNAS-312 validation):**
```bash
oc get pvc -n test-vms --no-headers | grep -v Bound | wc -l
# Should return: 0
```

### Cleanup After Tests

**Automatic Cleanup:**
- On successful tests (100% completion), `test-vms` namespace is automatically deleted

**Manual Cleanup:**
```bash
# For interrupted or failed tests
oc delete namespace test-vms
```

**Clean Results Directory:**
```bash
# Before starting fresh comparison tests
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=10 -e clean_results=true"

# Or manually
rm -rf results-veritas-9.1/*
```

### Success Criteria

**OCPNAS-312 Validation:**
- ✅ All 200 VMs reach "Running" state
- ✅ Zero PVCs stuck in Pending/Provisioning
- ✅ 100% success rate
- ✅ No manual intervention required
- ✅ Consistent provisioning time (~9-10s per VM)

**Expected Results:**
- **50 VMs:** ~10 seconds per VM average
- **100 VMs:** ~10 seconds per VM average
- **200 VMs:** ~9-10 seconds per VM average
- **400 VMs:** ~10-15 seconds per VM average (may vary with single disk)

---

## StorageClass Configuration

### Overview

InfoScale StorageClass parameters control how volumes are laid out across disks.

**Template:** `templates/veritas/storageclass.yaml.j2`

### Available Parameters

| Parameter | Description | Example Values |
|-----------|-------------|----------------|
| `layout` | Volume layout type | stripe, mirror, stripe-mirror |
| `nstripe` | Number of stripe columns | 2, 3, 4 |
| `faultTolerance` | Failure tolerance level | 0, 1, 2 |
| `stripeUnit` | Stripe unit size | 64k, 128k, 256k |
| `mediaType` | Disk type preference | SSD, HDD |

### Storage Layouts

**Stripe (RAID 0):**
- **Performance:** ⚡⚡⚡ Maximum
- **Redundancy:** ❌ None
- **Capacity:** 100%
- **Use Case:** Performance-critical, non-critical data
- **Example:** `infoscale_layout: stripe`, `infoscale_nstripe: 2`

**Mirror (RAID 1):**
- **Performance:** ⚡⚡ Good reads
- **Redundancy:** ✅✅✅ High
- **Capacity:** 50%
- **Use Case:** High availability, critical data
- **Example:** `infoscale_layout: mirror`

**Stripe-Mirror (RAID 10):**
- **Performance:** ⚡⚡⚡ Very fast
- **Redundancy:** ✅✅ Medium
- **Capacity:** 50%
- **Use Case:** Production databases, critical apps
- **Example:** `infoscale_layout: stripe-mirror`

**Concat:**
- **Performance:** ⚡ Normal
- **Redundancy:** ❌ None
- **Capacity:** 100%
- **Use Case:** Simple capacity expansion
- **Example:** `infoscale_layout: concat`

### Configuration Methods

#### Method 1: Auto-Configuration (Recommended)

**Behavior:**
- **2+ disks:** Automatically sets `layout: stripe`, `nstripe: <disk_count>`
- **1 disk:** No layout specified (InfoScale defaults)

```bash
# Auto-configures based on disk count
make veritas TAGS=install
make veritas TAGS=cluster-recreate
```

#### Method 2: overrides.yml

```yaml
infoscale_layout: "stripe"
infoscale_nstripe: 2
infoscale_fault_tolerance: 0
infoscale_media_type: "SSD"
```

```bash
make veritas TAGS=install
```

#### Method 3: Command-Line Override

```bash
# Stripe configuration
make veritas TAGS=install EXTRA_VARS="-e infoscale_layout=stripe -e infoscale_nstripe=2"

# Mirror configuration
make veritas TAGS=cluster-recreate EXTRA_VARS="-e infoscale_layout=mirror"

# RAID 10 configuration
make veritas TAGS=cluster-recreate EXTRA_VARS="-e infoscale_layout=stripe-mirror -e infoscale_nstripe=2"
```

### Verify StorageClass Configuration

```bash
# View StorageClass
oc get sc infoscale -o yaml

# Check parameters section
oc get sc infoscale -o jsonpath='{.parameters}' | jq '.'
```

**Example Output:**
```json
{
  "fstype": "vxfs",
  "layout": "stripe",
  "nstripe": "2"
}
```

---

## Advanced Configuration

### Override Variables

**File:** `overrides.yml`

**Common Overrides:**
```yaml
# Disk configuration
infoscale_include_devices:
  - "/dev/disk/by-path/pci-0000:6c:00.0-nvme-1"
  - "/dev/disk/by-path/pci-0000:77:00.0-nvme-1"

# StorageClass parameters
infoscale_layout: "stripe"
infoscale_nstripe: 2
infoscale_fault_tolerance: 0
infoscale_media_type: "SSD"
infoscale_stripe_unit: "128k"

# Cluster settings
ocp_cluster_name: "my-infoscale-cluster"
ocp_region: "us-east-1"
ocp_worker_count: 3
ocp_worker_type: "c5n.metal"
```

### InfoScale 9.1.0 Features

**includeDevices (New in 9.1):**
```yaml
spec:
  isSharedStorage: true
  clusterInfo:
    - nodeName: node1
      includeDevices:
        - "/dev/disk/by-path/pci-0000:6c:00.0-nvme-1"
    - nodeName: node2
    - nodeName: node3
```

**Benefits:**
- Only specify devices on one node
- Cleaner than old `excludeDevice` approach
- Automatic sharing across nodes with `isSharedStorage: true`

**Old Method (InfoScale 8.x):**
```yaml
spec:
  clusterInfo:
    - nodeName: node1
      excludeDevice: ["/dev/disk/by-path/boot-disk"]
    - nodeName: node2
      excludeDevice: ["/dev/disk/by-path/boot-disk"]
    - nodeName: node3
      excludeDevice: ["/dev/disk/by-path/boot-disk"]
```

---

## Common Workflows

### Workflow 1: First-Time Setup
```bash
# Step 1: Deploy everything
make veritas

# Step 2: Verify installation
make veritas TAGS=test

# Step 3: Check capacity
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"

# Step 4: Run baseline performance test
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"
```

### Workflow 2: Test Different Disk Configurations
```bash
# Configuration A: 2x250GB disks (stripe)
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 1,2
make veritas TAGS=test
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"

# Configuration B: 1x500GB disk (single)
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 3
make veritas TAGS=test
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"
```

### Workflow 3: OCPNAS-312 Full Validation
```bash
# Ensure cluster is healthy
make veritas TAGS=test

# Run all comparison tests (time-series data collection)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=400"

# Review results
ls -lh results-veritas-9.1/
cat results-veritas-9.1/veritas-9.1-ga-perf-test-summary-timeseries.csv

# Import to Google Sheets for graphing
```

### Workflow 4: Troubleshooting Unhealthy Cluster
```bash
# Check current status
oc get infoscalecluster -n infoscale-vtas
oc describe infoscalecluster -n infoscale-vtas infoscalecluster-dev

# Clean and recreate
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"
make veritas TAGS=cluster-recreate

# Verify
make veritas TAGS=test
```

### Workflow 5: Complete Teardown and Reinstall
```bash
# Full cleanup
make veritas TAGS=cleanup

# Clean disks
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"

# Fresh install with specific configuration
cat > overrides.yml << 'YAML'
infoscale_layout: "stripe-mirror"
infoscale_nstripe: 2
YAML

make veritas TAGS=dependencies,install
make veritas TAGS=test
```

---

## Troubleshooting

### Issue: Cluster shows "Not Healthy" or "Out of Cluster"

**Symptom:**
```bash
$ oc get infoscalecluster -n infoscale-vtas
NAME                 STATE        STATUS
infoscalecluster-dev Not Healthy  Error
```

**Cause:** Disks have stale VxVM metadata from previous cluster

**Solution:**
```bash
# Option 1: cluster-recreate (includes automatic cleaning)
make veritas TAGS=cluster-recreate

# Option 2: Manual cleaning then recreate
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"
make veritas TAGS=cluster-recreate
```

### Issue: Disks show "online invalid" status

**Symptom:**
```bash
$ oc exec -n infoscale-vtas $POD -- vxdisk list
DEVICE          TYPE         DISK    GROUP    STATUS
node001_nvme0_0 auto:none    -       -        online invalid
node001_nvme2_0 auto:none    -       -        online invalid
```

**Explanation:** This is **NORMAL** for disks NOT in `includeDevices`:

| Status | Type | Group | Meaning |
|--------|------|-------|---------|
| `online invalid` | `auto:none` | `-` | Visible but **NOT USABLE** (safe) |
| `online shared` | `auto:cdsdisk` | `vrts_kube_dg-XXX` | **ACTIVE IN CLUSTER** ✓ |

**What's Happening:**
- InfoScale's DMP layer scans ALL block devices
- Only disks in `includeDevices` are initialized
- Other disks remain "invalid" and cannot be used
- Boot disk and non-selected disks are safe

**Action Needed:** None - this is correct behavior

### Issue: Performance Test Timeout

**Old Behavior (Before Fix):**
- 600-second timeout caused failures for large VM counts

**New Behavior:**
- Infinite timeout
- Press Ctrl+C to interrupt and get partial results

**No Action Needed:** Tests now run until completion

### Issue: Kubeconfig Errors

**Symptom:**
```
Could not find or access '/path/to/kubeconfig'
```

**Solution 1 - Login to OCP:**
```bash
oc login https://api.cluster.domain:6443
oc whoami  # Verify
```

**Solution 2 - Set KUBECONFIG:**
```bash
export KUBECONFIG=/path/to/kubeconfig
```

**Solution 3 - Update overrides.yml:**
```yaml
kubeconfig: "/path/to/your/kubeconfig"
```

### Issue: "Unable to retrieve image pull secret (infoscale-imgpuller)"

**Symptom:**
```
Warning  FailedToRetrieveImagePullSecret  Unable to retrieve some image pull secrets (infoscale-imgpuller)
```

**Cause:** InfoScale references a secret that may not exist, but images are cached

**Impact:** None - this is just a warning. Pods run fine with cached images.

**Action Needed:** None (safe to ignore if pods are Running)

### Issue: Disk Cleanup Doesn't Work

**Symptoms:**
- Disks still show old VxVM metadata after cleanup
- lsblk shows partitions (p3, p8) after wipefs

**Solution:**
```bash
# More aggressive cleanup (if wipefs alone doesn't work)
oc debug node/<node-name> -- chroot /host bash -c '
  dd if=/dev/zero of=/dev/nvme3n1 bs=1M count=100
  wipefs -a /dev/nvme3n1
  partprobe /dev/nvme3n1
'
```

### Issue: VxVM Commands Fail Inside Pod

**Symptom:**
```
command terminated with exit code 11
```

**Cause:** Trying to access disk group that doesn't exist or VxVM not initialized

**Check:**
```bash
POD=$(oc get pods -n infoscale-vtas -l app.kubernetes.io/name=infoscale-sds -o jsonpath='{.items[0].metadata.name}')
oc exec -n infoscale-vtas $POD -- vxdctl mode
# Should return: mode: enabled
```

---

## Best Practices

### Disk Requirements

**EBS Volume Configuration:**
- Type: `io2` (recommended for performance and multi-attach)
- Multi-Attach: **Enabled** (required)
- IOPS: 5000+ recommended for production
- Size: Based on workload (250GB-500GB+ per disk)
- Attached: To all worker nodes

**Create Multi-Attach EBS Volumes:**
```bash
aws ec2 create-volume \
  --region <region> \
  --availability-zone <az> \
  --size 250 \
  --volume-type io2 \
  --iops 5000 \
  --multi-attach-enabled \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=infoscale-disk-1}]'
```

### Cluster Sizing

**For 400 VM Tests:**
- **Worker Nodes:** 3+ bare metal (c5n.metal recommended)
- **Pod Capacity:** 110-250 pods per node
- **Storage:** 500GB+ total capacity
- **Layout:** Stripe across multiple disks for better I/O

**Resource Requirements per VM:**
- vCPU: 0.1 cores
- Memory: 128 MiB
- Storage: 1 GiB

**Example Calculation:**
- 400 VMs × 1 GiB = 400 GB storage needed
- 400 VMs × 0.1 cores = 40 vCPU needed
- 400 VMs × 128 MiB = 51.2 GB memory needed

### Performance Optimization

**For Best Performance:**
1. Use multiple disks in stripe layout
2. Set `nstripe` equal to disk count
3. Use io2 volumes with high IOPS
4. Ensure sufficient network bandwidth
5. Monitor disk group free space

**Check Performance:**
```bash
# Before test
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"

# Run test
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"

# After test (check if capacity was bottleneck)
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"
```

---

## Reference

### File Locations

**Playbooks:**
- `playbooks/veritas/veritas.yml` - Main entry point
- `playbooks/veritas/dependencies.yml` - NFD, cert-manager, virtualization
- `playbooks/veritas/install.yml` - InfoScale operator and cluster
- `playbooks/veritas/cluster-recreate.yml` - Cluster recreation
- `playbooks/veritas/test.yml` - Basic functionality test
- `playbooks/veritas/ops.yml` - Operations (clean, free-space)
- `playbooks/veritas/perf-test.yml` - Performance testing
- `playbooks/veritas/cleanup.yml` - Complete teardown
- `playbooks/veritas/monitor-vms.sh` - VM monitoring script

**Templates:**
- `templates/veritas/infoscale-cluster.yaml.j2` - InfoScaleCluster CR
- `templates/veritas/storageclass.yaml.j2` - StorageClass definition
- `templates/veritas/snapshotclass.yaml` - VolumeSnapshotClass
- `templates/veritas/license.yaml` - Veritas license
- `templates/veritas/perf-test-source-vm.yaml` - Source VM for cloning
- `templates/veritas/perf-test-clone-vm.yaml.j2` - Clone VM template

**Results:**
- `results-veritas-9.1/` - All test results and reports

### Important Kubernetes Resources

**Namespaces:**
- `infoscale-vtas` - InfoScale operator and cluster
- `test-vms` - Performance test VMs (created/deleted by tests)

**Custom Resources:**
- `InfoScaleCluster` - Main cluster configuration
- `License` - Veritas license

**Standard Resources:**
- `StorageClass: infoscale` - CSI storage provider
- `VolumeSnapshotClass: infoscale-snapshot` - Snapshot provider

### Command Quick Reference

```bash
# Installation
make veritas                                                    # Full install
make veritas TAGS=dependencies,install                          # Skip OCP install
make veritas TAGS=install -e manual_disk_selection=true         # Interactive disk selection

# Cluster Management
make veritas TAGS=cluster-recreate                              # Auto-detect disks
make veritas TAGS=cluster-recreate -e manual_disk_selection=true # Interactive
make veritas TAGS=cluster-recreate -e infoscale_layout=stripe   # With layout

# Operations
make veritas TAGS=ops -e operation=free-space                   # Check space
make veritas TAGS=ops -e operation=clean                        # Clean disks
make veritas TAGS=test                                          # Test cluster

# Performance Testing
make veritas TAGS=perf-test -e num_vms=200                      # 200 VMs
make veritas TAGS=perf-test -e num_vms=50                       # 50 VMs
make veritas TAGS=perf-test -e clean_results=true               # Clean results first

# Cleanup
make veritas TAGS=cleanup                                       # Complete teardown
oc delete namespace test-vms                                    # Delete test VMs only
```

---

## Additional Resources

**Veritas InfoScale Documentation:**
- [InfoScale 9.1 Release Notes](https://www.veritas.com/support/en_US/doc/infoscale)
- [Veritas Container Storage Documentation](https://www.veritas.com/support/en_US/article.100052362)

**OpenShift Documentation:**
- [OpenShift Virtualization](https://docs.openshift.com/container-platform/latest/virt/about_virt/about-virt.html)
- [CSI Drivers](https://docs.openshift.com/container-platform/latest/storage/container_storage_interface/persistent-storage-csi.html)

**Related Issues:**
- OCPNAS-312: Validate Arctera Concurrency Fix
- OCPNAS-141: PV provisioning race condition (original issue)

---

**Document Version:** 1.0  
**InfoScale Version:** 9.1.0  
**Last Updated:** December 2025







