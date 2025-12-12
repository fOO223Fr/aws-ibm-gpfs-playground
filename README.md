# Scripts to deploy AWS OCP cluster + GPFS

## Installation

Here are the steps to deploy OCP + GPFS. These steps will create an OCP
cluster with 3 master + 3 workers by default and then will create a multiattach
EBS volume and attach it to the three workers.

1. Make sure you have the right ansible dependencies via `ansible-galaxy collection install -r requirements.yml` and also that you have the httpd tools installed
 (httpd-tools on Fedora or `brew install httpd` on MacOSX)
2. Make sure your aws credentials and aws cli are in place and working
3. Run the following to create an `overrides.yml`. 
```
cat > overrides.yml<<EOF
# ocp_domain: "fusionaccess.devcluster.openshift.com"
ocp_cluster_name: "gpfs-bandini"
gpfs_volume_name: "bandini-volume"
# ocp_worker_count: 3
# ocp_worker_type: "m5.2xlarge"
# ocp_master_count: 3
# ocp_master_type: "m5.2xlarge"
# ocp_az: "eu-central-1a"
# ocp_region: "eu-central-1"

# gpfs_version: "v5.2.2.x"
# ssh_pubkey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO8CumOo7uGDhSG5gzRdMkej/dBZ3YhhpKweKeyW+iCK michele@oshie"
EOF
```

Change it by uncommenting and tweaking at least the following lines:
   - `ocp_domain`
   - `ocp_cluster_name`
   - `ocp_az`
   - `ocp_region`
4. Make sure you read `group_vars/all` and have all the files with the secret material done
5. Run `make ocp-clients`. This will download the needed oc + openshift-install version
   in your home folder under `~/aws-gpfs-playground/<ocp_version>`
6. Run `make install` to install the openshift-fusion-access operator


## Deletion

To delete the cluster and the EBS volume, run `make destroy`

## Health Check

Run `make gpfs-health` to run some GPFS healthcheck commands

## Delete GPFS objects

Run `make gpfs-clean` to remove all the gpfs objects we know about

## Test
   - Run `make test-help` to see available tests
   - Run `make test FUNC=<available test functions>` to test a testable function

## Veritas InfoScale (Arctera) - Complete Guide

### Quick Start

```bash
# Full stack: OCP cluster + dependencies + InfoScale (auto-detects disks)
make veritas

# Already have OCP? Just install InfoScale stack
make veritas TAGS=dependencies,install
```

---

### 📋 Available Operations

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `make veritas` | Full deployment: OCP + dependencies + InfoScale | Fresh cluster setup |
| `make veritas TAGS=dependencies` | Install NFD, cert-manager, virtualization | Prerequisites only |
| `make veritas TAGS=install` | Install InfoScale operator + cluster | InfoScale stack only |
| `make veritas TAGS=cluster-recreate` | Delete & recreate cluster (auto-detect disks) | Change disk configuration |
| `make veritas TAGS=cluster-recreate -e manual_disk_selection=true` | Interactive disk selection | Choose specific disks |
| `make veritas TAGS=test` | Run basic functionality test | Verify cluster health |
| `make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"` | Show available space in disk group | Check capacity |
| `make veritas TAGS=ops EXTRA_VARS="-e operation=clean"` | Wipe all non-boot disks | Reset disks |
| `make veritas TAGS=cleanup` | Delete all InfoScale resources | Complete teardown |
| `make veritas TAGS=perf-test` | Performance testing (default 10 VMs) | Validate performance |

---

### 1️⃣ Initial Installation

**Full Automated Installation:**
```bash
make veritas
```

**What happens:**
1. Provisions OCP cluster (if not using existing TAGS)
2. Installs dependencies: NFD, cert-manager, OpenShift Virtualization
3. Installs InfoScale operator and creates license
4. **Auto-detects** all non-boot multi-attach volumes
5. Creates InfoScaleCluster with detected disks
6. Creates StorageClass (sets as default) and VolumeSnapshotClass

**Disk Auto-Detection:**
- ✅ Scans all NVMe devices on worker nodes
- ✅ Automatically excludes boot disk
- ✅ Uses all remaining disks for InfoScale cluster
- ✅ No manual configuration needed

**Skip OCP Installation:**
```bash
# Use existing OCP cluster
make veritas TAGS=dependencies,install
```

**Override Auto-Detection** (in `overrides.yml`):
```yaml
# Specify exact disks (bypasses auto-detection)
infoscale_include_devices:
  - "/dev/disk/by-path/pci-0000:6c:00.0-nvme-1"
  - "/dev/disk/by-path/pci-0000:77:00.0-nvme-1"
```

---

### 2️⃣ Cluster Management

#### Recreate Cluster (Auto-Detection)

Change disk configuration without reinstalling operator:

```bash
make veritas TAGS=cluster-recreate
```

**Process:**
1. Deletes InfoScaleCluster, StorageClass, VolumeSnapshotClass
2. Cleans disk signatures with `wipefs -a` (removes stale metadata)
3. Auto-detects all available disks
4. Recreates cluster with detected disks
5. Recreates StorageClass and VolumeSnapshotClass

**Preserves:** InfoScale operator, License, namespace

#### Recreate Cluster (Manual Selection)

Choose specific disks interactively:

```bash
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
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

Enter disk numbers to include (comma-separated, e.g., 1,2 or 1): 
```

**Example Use Cases:**
```bash
# Scenario A: Test with 2x250GB disks (500GB total)
Enter: 1,2

# Scenario B: Test with 1x500GB disk (500GB total)  
Enter: 3

# Scenario C: Use all disks (1TB total)
Enter: 1,2,3
```

**Note:** Development license allows only 1 cluster at a time. Use `cluster-recreate` to switch configurations.

---

### 3️⃣ Operations & Maintenance

#### Check Available Space

View free space in InfoScale disk group:

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

**Use case:** Monitor capacity before running large VM tests

#### Clean Disks

Wipe all non-boot disk signatures (removes stale metadata):

```bash
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"
```

**What it does:**
- Runs `wipefs -a` on all non-boot NVMe devices
- Executes on all worker nodes
- Automatically excludes boot disk
- Prepares disks for fresh InfoScale initialization

**Output:**
```
✓ Disk Cleanup Complete
All non-boot disks have been cleaned on all 3 worker nodes.
Disks are now ready for InfoScale initialization.
```

**Use case:** Before switching disk configurations or troubleshooting cluster issues

**Warning:** This will destroy all data on non-boot disks. Use with caution.

---

### 4️⃣ Testing & Verification

#### Basic Functionality Test

```bash
make veritas TAGS=test
```

**What it tests:**
1. Verifies InfoScaleCluster is Running and Healthy
2. Creates PVC with InfoScale StorageClass
3. Deploys test workload (containertools Deployment)
4. Waits for PVC to bind and pod to run
5. Cleans up test resources
6. **Exits with success/failure** based on results

**Expected output:**
```
InfoScaleCluster is Running, Healthy, and has 1 diskgroup(s)
✓ PVC bound successfully
✓ Pod running successfully
```

#### Check Cluster Health Manually

```bash
# Quick status
oc get infoscalecluster -n infoscale-vtas

# Detailed info
oc describe infoscalecluster -n infoscale-vtas infoscalecluster-dev

# Check disk status from InfoScale pod
POD=$(oc get pods -n infoscale-vtas -l app.kubernetes.io/name=infoscale-sds -o jsonpath='{.items[0].metadata.name}')
oc exec -n infoscale-vtas $POD -- vxdisk list
oc exec -n infoscale-vtas $POD -- vxdg list
```

**Expected healthy output:**
```
NAME                   VERSION   CLUSTERID   STATE     DISKGROUPS           STATUS
infoscalecluster-dev   9.1.0     12345       Running   vrts_kube_dg-12345   Healthy
```

---

### 4️⃣ Performance Testing (OCPNAS-312 Validation)

**Purpose:** Validate InfoScale 9.1.0 resolves PV provisioning race conditions during concurrent VM cloning.

#### Standard Performance Tests

```bash
# Baseline test (50 VMs, ~5-15 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"

# Scaling test (100 VMs, ~15-30 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100"

# OCPNAS-312 requirement (200 VMs, ~30-60 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"

# Stress test (400 VMs, ~60+ min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=400"
```

#### Development/Debug Tests

```bash
# Quick test (10 VMs, clean previous results)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=10 -e clean_results=true"

# Quick test (keep existing results)
make veritas TAGS=perf-test
```

**Flags:**
- `num_vms`: Number of VMs to clone (default: 10)
- `clean_results`: Remove all previous results before running (default: false)

#### Monitor Test Progress

**Terminal 1 - Run test:**
```bash
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"
```

**Terminal 2 - Watch progress:**
```bash
watch -n 1 cat /tmp/veritas-vm-provisioning-status.log
```

**Sample output:**
```
========================================================================
  VERITAS INFOSCALE PERFORMANCE TEST - VM Cloning Monitor
  OCPNAS-312 Concurrency Validation
========================================================================
Elapsed Time: [12:34] | Last Updated: 15:30:45

STATUS SUMMARY:
  Running:        150
  Stopped:        0
  Provisioning:   50
  Target:         200 VMs Running

  Time-series samples collected: 12
  Press Ctrl+C to interrupt and generate partial report
========================================================================
```

#### Interrupt Test Gracefully

Press `Ctrl+C` during the test to stop and generate partial results:
- Partial report with current VM state
- CSV and TXT files with collected data
- Resources preserved in `test-vms` namespace

#### Test Results

**Location:** `results-veritas-9.1/` directory

**Generated Files:**
1. **Summary CSV:** `veritas-9.1-ga-perf-test-{num_vms}vms.csv`
   ```csv
   num_vms_requested,num_vms_running,duration_seconds,avg_seconds_per_vm,success_rate_percent,test_status
   200,200,1847,9.24,100.0,SUCCESS
   ```

2. **Cluster Info:** `veritas-9.1-ga-perf-test-{num_vms}vms-cluster-info.txt`
   - Test execution summary
   - Cluster configuration (nodes, CPU, memory)
   - InfoScale configuration (version, disk groups, storage)
   - Resource utilization

3. **Time-Series CSV:** `veritas-9.1-ga-perf-test-summary-timeseries.csv` (shared)
   - **Only for 50, 100, 200, 400 VM tests** (comparison data)
   - Sampled every 1 minute
   - Ready for graphing in Google Sheets
   ```csv
   elapsed_minutes,vms_50,vms_100,vms_200,vms_400
   0,0,0,0,0
   1,10,20,40,80
   2,20,40,80,160
   ```

**Check test status:**
```bash
# View test VMs
oc get vms -n test-vms

# Check PVC status
oc get pvc -n test-vms

# Verify no stuck PVs
oc get pvc -n test-vms --no-headers | grep -v Bound | wc -l  # Should return 0
```

**Manual cleanup (if needed):**
```bash
oc delete namespace test-vms
```

**Success Criteria:**
- ✅ All VMs reach "Running" state
- ✅ No PVCs stuck in Pending/Provisioning
- ✅ 100% success rate
- ✅ No race conditions (OCPNAS-312 validation)

---

### 5️⃣ Maintenance & Cleanup

#### Complete Teardown

Remove all InfoScale resources including operator:

```bash
make veritas TAGS=cleanup
```

**Deletes:**
- All VMs in test-vms namespace
- All PVCs in test-vms namespace
- InfoScale StorageClass
- InfoScaleCluster
- Veritas License
- infoscale-vtas namespace

**Does NOT delete:** OCP cluster, worker nodes, EBS volumes

#### Partial Cleanup

```bash
# Delete only the cluster (keeps operator)
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Then press Ctrl+C after deletion step

# Delete test VMs only
oc delete namespace test-vms
```

---

### 🔧 Advanced Configuration

#### Override Variables (overrides.yml)

```yaml
# Specify exact disks for InfoScale
infoscale_include_devices:
  - "/dev/disk/by-path/pci-0000:6c:00.0-nvme-1"
  - "/dev/disk/by-path/pci-0000:77:00.0-nvme-1"

# Custom cluster settings (optional)
ocp_cluster_name: "my-cluster"
ocp_region: "us-east-1"
```

#### Command-Line Overrides

```bash
# Override disk selection at runtime
make veritas TAGS=cluster-recreate EXTRA_VARS="-e infoscale_include_devices=['dev1','dev2']"

# Multiple parameters
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100 -e clean_results=true"
```

---

### 📊 Common Workflows

#### Workflow 1: First-Time Setup
```bash
# Step 1: Deploy everything
make veritas

# Step 2: Verify installation
make veritas TAGS=test

# Step 3: Run performance baseline
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"
```

#### Workflow 2: Test Different Disk Configurations
```bash
# Check available space first
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"

# Test with 2 disks (500GB total)
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 1,2
make veritas TAGS=test
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"

# Switch to 1 disk (500GB total)
make veritas TAGS=cluster-recreate EXTRA_VARS="-e manual_disk_selection=true"
# Enter: 3
make veritas TAGS=test
make veritas TAGS=ops EXTRA_VARS="-e operation=free-space"
```

#### Workflow 3: OCPNAS-312 Full Validation
```bash
# Run all comparison tests
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=400"

# Review results
ls -lh results-veritas-9.1/
cat results-veritas-9.1/veritas-9.1-ga-perf-test-summary-timeseries.csv
```

---

### 🐛 Troubleshooting

#### Issue: Cluster shows "Not Healthy" or "Out of Cluster"

**Solution:** Disks have stale metadata. Clean and recreate:
```bash
# Option 1: cluster-recreate (includes automatic disk cleaning)
make veritas TAGS=cluster-recreate

# Option 2: Manual cleaning then recreate
make veritas TAGS=ops EXTRA_VARS="-e operation=clean"
make veritas TAGS=cluster-recreate
```

#### Issue: "online invalid" status on disks

**Explanation:** This is normal for disks NOT in `includeDevices`:
```
node001_nvme0_0  auto:none  -  -                  online invalid  ← Boot disk (safe)
node001_nvme1_0  auto:cdsdisk  disk1  vrts_kube_dg  online shared   ← IN USE ✓
node001_nvme2_0  auto:none  -  -                  online invalid  ← Not selected (safe)
```

Only disks with `auto:cdsdisk` type and a GROUP name are actively used.

#### Issue: Kubeconfig errors

**Solution:** Ensure you're logged in to OCP:
```bash
oc login <cluster-url>
oc whoami  # Verify login
```

Or set kubeconfig:
```bash
export KUBECONFIG=/path/to/kubeconfig
```

#### Issue: Performance test timeout

**Solution:** Tests have infinite timeout now. Press Ctrl+C to interrupt gracefully and get partial results.

---

### 📝 Notes

**InfoScale 9.1.0 Features:**
- Uses `includeDevices` (cleaner than old `excludeDevice`)
- `isSharedStorage: true` (only specify disks on one node)
- Improved concurrency handling (OCPNAS-312 fix)

**Disk Requirements:**
- Multi-attach enabled EBS volumes (io2 type recommended)
- Attached to all worker nodes
- Non-boot disks only

**Development License:**
- Allows **1 InfoScaleCluster** at a time
- Use `cluster-recreate` to switch between configurations
- No need to reinstall operator/license

