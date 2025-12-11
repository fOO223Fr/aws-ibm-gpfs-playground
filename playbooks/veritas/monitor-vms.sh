#!/bin/bash
# VM Monitoring Script for Veritas InfoScale Performance Test
# Arguments: $1=OC_BIN, $2=start_time, $3=num_vms, $4=results_dir

OC_BIN="$1"
start_time="$2"
num_vms="$3"
results_dir="$4"

STATUS_FILE="/tmp/veritas-vm-provisioning-status.log"
TIMESERIES_CSV="${results_dir}/veritas-9.1-ga-perf-test-summary-timeseries.csv"
> "$STATUS_FILE"  # Clear the file

last_sample_time=-1
interrupted=0

# Trap SIGINT/SIGTERM for graceful shutdown
trap 'interrupted=1' INT TERM

# Initialize time-series CSV if it doesn't exist
if [ ! -f "$TIMESERIES_CSV" ]; then
  echo "elapsed_minutes,vms_50,vms_100,vms_200,vms_400" > "$TIMESERIES_CSV"
fi

# Function to determine if we should sample at this elapsed time
should_sample() {
  local elapsed_min=$1
  local last_sampled=$2
  
  # Sample every 1 minute
  if [ "$elapsed_min" -gt "$last_sampled" ]; then
    return 0
  fi
  
  return 1
}

# Function to update time-series CSV
update_timeseries() {
  local elapsed_min=$1
  local running_count=$2
  local vm_count=$3
  
  # Only collect time-series for comparison test sizes (50, 100, 200, 400)
  case "$vm_count" in
    50|100|200|400) ;;
    *) return 0 ;;  # Skip time-series for other VM counts
  esac
  
  # Determine which column to update based on num_vms
  local col_name="vms_${vm_count}"
  
  # Create temp file
  local temp_file="${TIMESERIES_CSV}.tmp"
  
  # Check if this elapsed_min already exists
  if grep -q "^${elapsed_min}," "$TIMESERIES_CSV"; then
    # Update existing row
    awk -F',' -v min="$elapsed_min" -v col="$col_name" -v val="$running_count" '
      BEGIN { OFS="," }
      NR==1 {
        # Find column index
        for(i=1; i<=NF; i++) {
          if($i == col) col_idx=i
        }
        print
      }
      NR>1 {
        if($1 == min) {
          $col_idx = val
        }
        print
      }
    ' "$TIMESERIES_CSV" > "$temp_file"
  else
    # Add new row
    local new_row="${elapsed_min},"
    case "$vm_count" in
      50)  new_row="${new_row}${running_count},,," ;;
      100) new_row="${new_row},${running_count},," ;;
      200) new_row="${new_row},,${running_count}," ;;
      400) new_row="${new_row},,,${running_count}" ;;
    esac
    
    # Append and sort by elapsed_minutes
    (cat "$TIMESERIES_CSV"; echo "$new_row") | awk -F',' 'NR==1 {print; next} NR>1' | sort -t',' -k1 -n | awk 'NR==1 || !seen[$1]++ {print}' > "$temp_file"
    # Add header back
    head -1 "$TIMESERIES_CSV" > "${temp_file}.header"
    tail -n +2 "$temp_file" | sort -t',' -k1 -n >> "${temp_file}.header"
    mv "${temp_file}.header" "$temp_file"
  fi
  
  mv "$temp_file" "$TIMESERIES_CSV"
}

while true; do
  # Get elapsed time
  current_time=$(date +%s)
  elapsed=$(( current_time - start_time ))
  elapsed_minutes=$((elapsed / 60))
  minutes=$((elapsed / 60))
  seconds=$((elapsed % 60))
  
  # Count VM statuses
  vm_data=$($OC_BIN get vms -n test-vms -o json 2>/dev/null)
  running=$(echo "$vm_data" | jq '[.items[] | select(.status.printableStatus == "Running")] | length')
  stopped=$(echo "$vm_data" | jq '[.items[] | select(.status.printableStatus == "Stopped" or .status.printableStatus == "Stopping")] | length')
  provisioning=$(echo "$vm_data" | jq '[.items[] | select(.status.printableStatus == "Provisioning" or .status.printableStatus == "Starting" or .status.printableStatus == "WaitingForVolumeBinding")] | length')
  
  # Sample time-series data if needed
  if should_sample "$elapsed_minutes" "$last_sample_time"; then
    update_timeseries "$elapsed_minutes" "$running" "$num_vms"
    last_sample_time=$elapsed_minutes
  fi
  
  # Write dashboard to file (overwrite each time for clean display)
  {
    echo "========================================================================"
    echo "  VERITAS INFOSCALE PERFORMANCE TEST - VM Cloning Monitor"
    echo "  OCPNAS-312 Concurrency Validation"
    echo "========================================================================"
    printf "Elapsed Time: [%02d:%02d] | Last Updated: %s\n" $minutes $seconds "$(date '+%H:%M:%S')"
    echo ""
    echo "STATUS SUMMARY:"
    echo "  Running:        $running"
    echo "  Stopped:        $stopped"
    echo "  Provisioning:   $provisioning"
    echo "  Target:         $num_vms VMs Running"
    echo ""
        if [ "$last_sample_time" -ge 0 ]; then
          samples_collected=$((last_sample_time + 1))
        else
          samples_collected=0
        fi
        echo "  Time-series samples collected: $samples_collected"
        echo "  Press Ctrl+C to interrupt and generate partial report"
        echo "========================================================================"
    echo ""
      } > "$STATUS_FILE"
      
      # Check for interruption
      if [ "$interrupted" -eq 1 ]; then
    # Final sample before exit
    update_timeseries "$elapsed_minutes" "$running" "$num_vms"
    echo "✗ INTERRUPTED: Test stopped by user. Collected $running/$num_vms running VMs." >> "$STATUS_FILE"
    echo "PARTIAL:$running" > /tmp/veritas-test-result.txt
    exit 2
  fi
  
  # Check success condition
  if [ "$running" -eq "$num_vms" ]; then
    # Final sample at completion
    update_timeseries "$elapsed_minutes" "$running" "$num_vms"
    echo "✓ SUCCESS: All $num_vms VMs are now Running!" >> "$STATUS_FILE"
    echo "SUCCESS:$running" > /tmp/veritas-test-result.txt
    exit 0
  fi
  
  sleep 15
done

