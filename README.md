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

## Veritas InfoScale Performance Testing (OCPNAS-312)

### Purpose
Validate Veritas InfoScale 9.1.0 resolves PV provisioning concurrency issues when cloning large batches of VMs simultaneously.

### Commands

Test with different VM counts to validate performance and concurrency:

```bash
# Test 1: 50 VMs (baseline, ~5-15 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=50"

# Test 2: 100 VMs (scaling, ~15-30 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=100"

# Test 3: 200 VMs (OCPNAS-312 requirement, ~30-60 min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=200"

# Test 4: 400 VMs (stress test, ~60+ min)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=400"

# Debug/Development: Clean results before running (wipes all previous data)
make veritas TAGS=perf-test EXTRA_VARS="-e num_vms=10 -e clean_results=true"
```

**Note:** 
- Results are saved in `results-veritas-9.1/` directory at the project root
- Time-series data is sampled every 1 minute throughout the test

### Monitor Progress

In a separate terminal, watch real-time status:
```bash
watch -n 1 cat /tmp/veritas-vm-provisioning-status.log
```

### Interrupt Test

Press `Ctrl+C` to interrupt the test gracefully. Ansible will prompt:
```
^C [ERROR]: User interrupted execution
```

Then it will:
- Stop the monitoring loop gracefully
- Generate partial report with current state
- Create CSV and TXT files with collected data
- Preserve resources in `test-vms` namespace for inspection

### Expected Output Files

After each test completes, these files are generated in `results-veritas-9.1/`:

1. **Summary CSV**: `veritas-9.1-ga-perf-test-{num_vms}vms.csv`
   ```csv
   num_vms_requested,num_vms_running,duration_seconds,avg_seconds_per_vm,success_rate_percent,test_status
   200,200,1847,9.24,100.0,SUCCESS
   ```

2. **Cluster Info**: `veritas-9.1-ga-perf-test-{num_vms}vms-cluster-info.txt`
   - Test execution details
   - OpenShift cluster configuration
   - InfoScale storage configuration
   - Resource utilization analysis

3. **Time-Series Data** (shared): `veritas-9.1-ga-perf-test-summary-timeseries.csv`
   - Only collected for 50, 100, 200, 400 VM tests (for comparison)
   - Other VM counts (e.g., 10) skip time-series collection
   ```csv
   elapsed_minutes,vms_50,vms_100,vms_200,vms_400
   0,0,0,0,0
   2,15,28,52,98
   4,32,61,118,223
   6,45,89,175,342
   8,50,98,195,385
   10,50,100,200,398
   ```

### Check Test Status

```bash
# View all VMs
oc get vms -n test-vms

# Check PVC status
oc get pvc -n test-vms

# Verify no stuck PVs (should return 0)
oc get pvc -n test-vms | grep -v Bound | wc -l
```

### Cleanup (if needed)

On successful tests, cleanup is automatic. For interrupted/failed tests:
```bash
oc delete namespace test-vms
```

### Success Criteria

- ✅ All requested VMs reach "Running" state
- ✅ No PVCs stuck in Pending/Provisioning
- ✅ Success rate: 100%
- ✅ Consistent average provisioning time (~9-10s per VM)

