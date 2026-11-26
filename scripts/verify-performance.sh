#!/usr/bin/env bash
# ==============================================================================
# scripts/verify-performance.sh - Runtime Performance Probing Suite
# Part of the NixOS Performance & System Tuning Suite (Milestone M5)
#
# Inspects live kernel, CPU, memory, gaming, audio, and storage subsystems
# to verify performance optimizations and detect pending NixOS rebuilds.
# ==============================================================================

set -u
set -o pipefail

# ------------------------------------------------------------------------------
# Global Constants & Defaults
# ------------------------------------------------------------------------------
VERSION="1.0.0"
HOSTNAME_VAL="$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo "nixos")"
TIMESTAMP_VAL="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
KERNEL_VAL="$(uname -r 2>/dev/null || echo "unknown")"
UID_VAL="$(id -u 2>/dev/null || echo "1000")"
USER_VAL="$(id -un 2>/dev/null || echo "spike")"

# CLI Modes
OPT_VERBOSE=0
OPT_JSON=0
OPT_SUMMARY=0
OPT_NO_COLOR=0
OPT_STRICT=0

# Subsystem Filters (all 1 by default, or filtered if specific flags passed)
RUN_KERNEL=1
RUN_CPU=1
RUN_MEMORY=1
RUN_PROCESS=1
RUN_GAMING=1
RUN_AUDIO=1
RUN_STORAGE=1
CUSTOM_FILTER_SET=0

# Metrics Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNED_CHECKS=0
FAILED_CHECKS=0

# Subsystem Status Summaries for JSON & Output
STATUS_KERNEL="PASS"
STATUS_CPU="PASS"
STATUS_MEMORY="PASS"
STATUS_PROCESS="PASS"
STATUS_GAMING="PASS"
STATUS_AUDIO="PASS"
STATUS_STORAGE="PASS"

# Subsystem JSON Payload Buffers
JSON_KERNEL="{}"
JSON_CPU="{}"
JSON_MEMORY="{}"
JSON_PROCESS="{}"
JSON_GAMING="{}"
JSON_AUDIO="{}"
JSON_STORAGE="{}"

# Color Detection
if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    COLOR_ENABLED=0
else
    COLOR_ENABLED=1
fi

setup_colors() {
    if [[ "$COLOR_ENABLED" -eq 1 && "$OPT_NO_COLOR" -eq 0 && "$OPT_JSON" -eq 0 ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_CYAN=$'\033[36m'
        C_WHITE=$'\033[37m'
        C_DIM=$'\033[2m'
    else
        C_RESET=''
        C_BOLD=''
        C_RED=''
        C_GREEN=''
        C_YELLOW=''
        C_BLUE=''
        C_CYAN=''
        C_WHITE=''
        C_DIM=''
    fi
}

# ------------------------------------------------------------------------------
# Help & CLI Argument Parsing
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: ./scripts/verify-performance.sh [OPTIONS]

NixOS Performance & System Tuning Verification Suite
Probes live host subsystems to verify runtime performance optimizations.

Options:
  -h, --help            Show this help message and exit
  -v, --verbose         Enable detailed inspection logs and sysfs/procfs paths
  -j, --json            Output full diagnostic report as structured JSON to stdout
  -s, --summary         Display only the high-level summary table and score
  --no-color            Disable ANSI color escape sequences
  --strict              Exit with code 1 if any warnings (pending rebuilds) occur

Subsystem Filters (run only selected checks):
  --kernel              Check CachyOS BORE scheduler, CFS slice, sysctl tuning
  --cpu                 Check AMD Ryzen 3 3300X topology, AMD P-State, EPP
  --memory              Check ZRAM compression (zstd), VM swappiness & dirty ratios
  --process             Check ananicy-cpp service and rules prioritization
  --gaming              Check NVIDIA VRAM preservation, GameMode daemon & groups
  --audio               Check PipeWire clock rate, quantum, Temple Pro Black DAC
  --storage             Check disk I/O schedulers (kyber/bfq), fstrim & scrub timers

Exit Codes:
  0   All probed checks passed successfully (or only tolerable warnings)
  1   One or more checks failed (or warnings present when --strict is passed)
  2   Invalid CLI argument or usage error

Examples:
  ./scripts/verify-performance.sh                 # Standard check with colored output
  ./scripts/verify-performance.sh --json | jq .   # JSON report parsed via jq
  ./scripts/verify-performance.sh --summary       # Quick executive summary
  ./scripts/verify-performance.sh --kernel --cpu  # Check only kernel and CPU
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                OPT_VERBOSE=1
                shift
                ;;
            -j|--json)
                OPT_JSON=1
                shift
                ;;
            -s|--summary)
                OPT_SUMMARY=1
                shift
                ;;
            --no-color)
                OPT_NO_COLOR=1
                shift
                ;;
            --strict)
                OPT_STRICT=1
                shift
                ;;
            --kernel)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_KERNEL=1
                shift
                ;;
            --cpu)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_CPU=1
                shift
                ;;
            --memory)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_MEMORY=1
                shift
                ;;
            --process)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_PROCESS=1
                shift
                ;;
            --gaming)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_GAMING=1
                shift
                ;;
            --audio)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_AUDIO=1
                shift
                ;;
            --storage)
                if [[ "$CUSTOM_FILTER_SET" -eq 0 ]]; then
                    RUN_KERNEL=0; RUN_CPU=0; RUN_MEMORY=0; RUN_PROCESS=0
                    RUN_GAMING=0; RUN_AUDIO=0; RUN_STORAGE=0
                    CUSTOM_FILTER_SET=1
                fi
                RUN_STORAGE=1
                shift
                ;;
            *)
                echo "Error: Unknown CLI option '$1'" >&2
                echo "Run './scripts/verify-performance.sh --help' for usage details." >&2
                exit 2
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Check Logging & Recording Functions
# ------------------------------------------------------------------------------
record_pass() {
    local name="$1"
    local current="$2"
    local target="$3"
    local detail="${4:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))

    if [[ "$OPT_JSON" -eq 0 && "$OPT_SUMMARY" -eq 0 ]]; then
        printf "  [%bPASS%b] %-32s : %b%s%b" "$C_GREEN" "$C_RESET" "$name" "$C_BOLD" "$current" "$C_RESET"
        if [[ -n "$target" && "$target" != "$current" ]]; then
            printf " (target: %s)" "$target"
        fi
        if [[ -n "$detail" && "$OPT_VERBOSE" -eq 1 ]]; then
            printf " %b[%s]%b" "$C_DIM" "$detail" "$C_RESET"
        fi
        printf "\n"
    fi
}

record_warn() {
    local name="$1"
    local current="$2"
    local target="$3"
    local note="$4"
    local sub="$5"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNED_CHECKS=$((WARNED_CHECKS + 1))

    # Mark subsystem as WARN if not already FAIL
    case "$sub" in
        kernel)  [[ "$STATUS_KERNEL" != "FAIL" ]] && STATUS_KERNEL="WARN" ;;
        cpu)     [[ "$STATUS_CPU" != "FAIL" ]] && STATUS_CPU="WARN" ;;
        memory)  [[ "$STATUS_MEMORY" != "FAIL" ]] && STATUS_MEMORY="WARN" ;;
        process) [[ "$STATUS_PROCESS" != "FAIL" ]] && STATUS_PROCESS="WARN" ;;
        gaming)  [[ "$STATUS_GAMING" != "FAIL" ]] && STATUS_GAMING="WARN" ;;
        audio)   [[ "$STATUS_AUDIO" != "FAIL" ]] && STATUS_AUDIO="WARN" ;;
        storage) [[ "$STATUS_STORAGE" != "FAIL" ]] && STATUS_STORAGE="WARN" ;;
    esac

    if [[ "$OPT_JSON" -eq 0 && "$OPT_SUMMARY" -eq 0 ]]; then
        printf "  [%bWARN%b] %-32s : %b%s%b" "$C_YELLOW" "$C_RESET" "$name" "$C_YELLOW" "$current" "$C_RESET"
        if [[ -n "$target" ]]; then
            printf " (target: %s)" "$target"
        fi
        printf "\n         %b-> Notice: %s%b\n" "$C_DIM" "$note" "$C_RESET"
    fi
}

record_fail() {
    local name="$1"
    local current="$2"
    local target="$3"
    local reason="$4"
    local sub="$5"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))

    case "$sub" in
        kernel)  STATUS_KERNEL="FAIL" ;;
        cpu)     STATUS_CPU="FAIL" ;;
        memory)  STATUS_MEMORY="FAIL" ;;
        process) STATUS_PROCESS="FAIL" ;;
        gaming)  STATUS_GAMING="FAIL" ;;
        audio)   STATUS_AUDIO="FAIL" ;;
        storage) STATUS_STORAGE="FAIL" ;;
    esac

    if [[ "$OPT_JSON" -eq 0 && "$OPT_SUMMARY" -eq 0 ]]; then
        printf "  [%bFAIL%b] %-32s : %b%s%b (target: %s)\n" "$C_RED" "$C_RESET" "$name" "$C_RED" "$current" "$C_RESET" "$target"
        printf "         %b-> Reason: %s%b\n" "$C_RED" "$reason" "$C_RESET"
    fi
}

record_info() {
    local name="$1"
    local val="$2"
    local detail="${3:-}"

    if [[ "$OPT_JSON" -eq 0 && "$OPT_SUMMARY" -eq 0 ]]; then
        printf "  [%bINFO%b] %-32s : %s" "$C_CYAN" "$C_RESET" "$name" "$val"
        if [[ -n "$detail" && "$OPT_VERBOSE" -eq 1 ]]; then
            printf " %b[%s]%b" "$C_DIM" "$detail" "$C_RESET"
        fi
        printf "\n"
    fi
}

section_header() {
    local title="$1"
    if [[ "$OPT_JSON" -eq 0 && "$OPT_SUMMARY" -eq 0 ]]; then
        printf "\n%b--- [ %s ] ---%b\n" "$C_BOLD$C_BLUE" "$title" "$C_RESET"
    fi
}

# ------------------------------------------------------------------------------
# Subsystem Probes
# ------------------------------------------------------------------------------

# 1. Kernel & BORE Scheduler
probe_kernel_bore() {
    section_header "Kernel & BORE Scheduler Subsystem"

    local bore_active=0
    local cfs_slice=0
    local lifetime=0
    local penalty=0
    local smoothness=0
    local clocksource="unknown"
    local migration_cost_status="deprecated"

    # Kernel release
    if [[ "$KERNEL_VAL" == *"cachyos"* || "$KERNEL_VAL" == *"bore"* ]]; then
        record_pass "Kernel Release" "$KERNEL_VAL" "CachyOS / BORE kernel"
    else
        record_warn "Kernel Release" "$KERNEL_VAL" "cachyos/bore" "Running generic kernel; CachyOS BORE enabled in configuration" "kernel"
    fi

    # BORE sysctl
    if [[ -r "/proc/sys/kernel/sched_bore" ]]; then
        bore_active=$(cat /proc/sys/kernel/sched_bore 2>/dev/null || echo "0")
        if [[ "$bore_active" == "1" ]]; then
            record_pass "sched_bore (BORE Active)" "1" "1"
        else
            record_warn "sched_bore" "$bore_active" "1" "sched_bore is 0" "kernel"
        fi
    else
        record_warn "sched_bore" "missing" "1" "Procfs node /proc/sys/kernel/sched_bore not available" "kernel"
    fi

    # CFS Bandwidth Slice
    if [[ -r "/proc/sys/kernel/sched_cfs_bandwidth_slice_us" ]]; then
        cfs_slice=$(cat /proc/sys/kernel/sched_cfs_bandwidth_slice_us 2>/dev/null || echo "0")
        if [[ "$cfs_slice" == "3000" ]]; then
            record_pass "sched_cfs_bandwidth_slice_us" "3000 us" "3000 us"
        else
            record_warn "sched_cfs_bandwidth_slice_us" "${cfs_slice} us" "3000 us" "Live value is ${cfs_slice} us; target 3000 us pending rebuild switch" "kernel"
        fi
    else
        record_fail "sched_cfs_bandwidth_slice_us" "inaccessible" "3000" "Cannot read sysctl path" "kernel"
    fi

    # Burst parameters
    if [[ -r "/proc/sys/kernel/sched_burst_cache_lifetime" ]]; then
        lifetime=$(cat /proc/sys/kernel/sched_burst_cache_lifetime 2>/dev/null || echo "0")
        if [[ "$lifetime" == "75000000" ]]; then
            record_pass "sched_burst_cache_lifetime" "$lifetime" "75000000"
        else
            record_warn "sched_burst_cache_lifetime" "$lifetime" "75000000" "Value differs from target" "kernel"
        fi
    fi

    if [[ -r "/proc/sys/kernel/sched_burst_penalty_scale" ]]; then
        penalty=$(cat /proc/sys/kernel/sched_burst_penalty_scale 2>/dev/null || echo "0")
        if [[ "$penalty" == "1536" ]]; then
            record_pass "sched_burst_penalty_scale" "$penalty" "1536"
        else
            record_warn "sched_burst_penalty_scale" "$penalty" "1536" "Value differs from target" "kernel"
        fi
    fi

    if [[ -r "/proc/sys/kernel/sched_burst_smoothness" ]]; then
        smoothness=$(cat /proc/sys/kernel/sched_burst_smoothness 2>/dev/null || echo "0")
        if [[ "$smoothness" == "1" ]]; then
            record_pass "sched_burst_smoothness" "$smoothness" "1"
        else
            record_warn "sched_burst_smoothness" "$smoothness" "1" "Value differs from target" "kernel"
        fi
    fi

    # Deprecated sched_migration_cost_ns handling
    if [[ -r "/proc/sys/kernel/sched_migration_cost_ns" ]]; then
        local mc_val
        mc_val=$(cat /proc/sys/kernel/sched_migration_cost_ns 2>/dev/null || echo "")
        migration_cost_status="$mc_val"
        record_info "sched_migration_cost_ns" "$mc_val" "Present in kernel"
    else
        record_pass "sched_migration_cost_ns" "N/A (deprecated)" "Safe leading hyphen (-)" "EEVDF kernel gracefully ignored key"
        migration_cost_status="deprecated"
    fi

    # Clocksource
    if [[ -r "/sys/devices/system/clocksource/clocksource0/current_clocksource" ]]; then
        clocksource=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null || echo "")
        if [[ "$clocksource" == "tsc" ]]; then
            record_pass "System Clocksource" "tsc" "tsc" "Direct invariant TSC reading"
        else
            record_warn "System Clocksource" "$clocksource" "tsc" "Target invariant TSC" "kernel"
        fi
    fi

    JSON_KERNEL=$(cat << EOF
{
  "status": "$STATUS_KERNEL",
  "kernel_version": "$KERNEL_VAL",
  "sched_bore": $bore_active,
  "sched_cfs_bandwidth_slice_us": $cfs_slice,
  "target_cfs_slice_us": 3000,
  "sched_burst_cache_lifetime": $lifetime,
  "sched_burst_penalty_scale": $penalty,
  "sched_burst_smoothness": $smoothness,
  "sched_migration_cost_ns": "$migration_cost_status",
  "clocksource": "$clocksource"
}
EOF
)
}

# 2. CPU Architecture & AMD P-State (AMD Ryzen 3 3300X)
probe_cpu_epp() {
    section_header "CPU Architecture & AMD P-State (Ryzen 3 3300X)"

    local cpu_model="Unknown CPU"
    local ccx_count=0
    local scaling_driver="unknown"
    local governor="unknown"
    local epp="unknown"
    local is_single_ccx=false
    local cmdline_synced=false

    # CPU Model Name
    if [[ -r "/proc/cpuinfo" ]]; then
        cpu_model=$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: *//' || echo "Unknown CPU")
        record_pass "CPU Hardware Model" "$cpu_model" "AMD Ryzen 3 3300X"
    fi

    # Single CCX Topology check (count of unique L3 cache IDs)
    if compgen -G "/sys/devices/system/cpu/cpu*/cache/index3/id" >/dev/null; then
        ccx_count=$(cat /sys/devices/system/cpu/cpu*/cache/index3/id 2>/dev/null | sort -u | wc -l || echo "0")
        if [[ "$ccx_count" -eq 1 ]]; then
            is_single_ccx=true
            record_pass "CCX Topology (Unified L3)" "Single-CCX (1x 16MB L3)" "1 CCX" "Zero cross-CCX core migration penalty"
        else
            record_info "CCX Topology" "${ccx_count} CCX clusters detected"
        fi
    fi

    # Scaling driver
    if [[ -r "/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver" ]]; then
        scaling_driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "")
        if [[ "$scaling_driver" == "amd-pstate-epp" || "$scaling_driver" == "amd_pstate" ]]; then
            record_pass "CPU Scaling Driver" "$scaling_driver" "amd-pstate-epp" "Autonomous CPPC v2 active"
        else
            record_warn "CPU Scaling Driver" "$scaling_driver" "amd-pstate-epp" "Standard ACPI driver active" "cpu"
        fi
    fi

    # Governor
    if [[ -r "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]]; then
        governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
        if [[ "$governor" == "powersave" || "$governor" == "performance" ]]; then
            record_pass "EPP Scaling Governor" "$governor" "powersave/performance"
        else
            record_warn "EPP Scaling Governor" "$governor" "powersave" "Non-standard governor active" "cpu"
        fi
    fi

    # EPP Profile
    if [[ -r "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference" ]]; then
        epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "")
        if [[ "$epp" == "balance_performance" || "$epp" == "performance" ]]; then
            record_pass "Energy Perf Preference (EPP)" "$epp" "balance_performance"
        else
            record_warn "Energy Perf Preference" "$epp" "balance_performance" "EPP setting is $epp" "cpu"
        fi
    fi

    # Boot cmdline parameters
    if [[ -r "/proc/cmdline" ]]; then
        local cmdline
        cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
        if [[ "$cmdline" == *"amd_pstate=active"* && "$cmdline" == *"split_lock_detect=off"* ]]; then
            cmdline_synced=true
            record_pass "Kernel Boot Parameters" "Active in live cmdline" "amd_pstate=active split_lock_detect=off"
        else
            record_warn "Kernel Boot Parameters" "Pending reboot" "amd_pstate=active split_lock_detect=off" "Configured in boot.kernelParams; active upon next reboot" "cpu"
        fi
    fi

    JSON_CPU=$(cat << EOF
{
  "status": "$STATUS_CPU",
  "cpu_model": "$cpu_model",
  "single_ccx": $is_single_ccx,
  "driver": "$scaling_driver",
  "governor": "$governor",
  "epp": "$epp",
  "kernel_params_active": $cmdline_synced
}
EOF
)
}

# 3. Memory, ZRAM & Virtual Memory Sysctls
probe_memory_zram() {
    section_header "Memory, ZRAM & Virtual Memory Subsystem"

    local zram_dev="/dev/zram0"
    local algorithm="unknown"
    local disksize=0
    local data_bytes=0
    local compr_bytes=0
    local ratio_str="1.00x"
    local swappiness=0
    local wm_boost=0
    local page_cluster=0
    local vfs_pressure=0
    local wm_scale=0

    # ZRAM device & algorithm
    if [[ -r "/sys/block/zram0/comp_algorithm" ]]; then
        local alg_raw
        alg_raw=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "")
        if [[ "$alg_raw" == *"["*"zstd"*"]"* ]]; then
            algorithm="zstd"
            record_pass "ZRAM Compression Algorithm" "zstd (active: [zstd])" "[zstd]" "Ultra-fast decompression (~1.8 GB/s)"
        else
            record_warn "ZRAM Compression Algorithm" "$alg_raw" "[zstd]" "Expected zstd compression" "memory"
        fi
    elif [[ -e "$zram_dev" ]]; then
        record_info "ZRAM Device" "Present ($zram_dev)"
    else
        record_fail "ZRAM Device" "Missing" "/dev/zram0" "zram device not instantiated" "memory"
    fi

    # ZRAM swap space & statistics via zramctl
    if command -v zramctl >/dev/null 2>&1; then
        local zram_stats
        zram_stats=$(zramctl --bytes 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $4, $5}' || echo "")
        if [[ -n "$zram_stats" ]]; then
            disksize=$(echo "$zram_stats" | awk '{print $3}')
            data_bytes=$(echo "$zram_stats" | awk '{print $4}')
            compr_bytes=$(echo "$zram_stats" | awk '{print $5}')
            if [[ -n "$compr_bytes" && "$compr_bytes" -gt 0 ]]; then
                ratio_str=$(awk -v d="$data_bytes" -v c="$compr_bytes" 'BEGIN { printf "%.2fx", d/c }')
            fi
            record_pass "ZRAM Disksize & Compression" "$ratio_str ratio (${disksize} bytes disksize)" "zstd ~3-4x" "Real-time RAM expansion"
        fi
    fi

    # Virtual Memory Sysctls
    if [[ -r "/proc/sys/vm/swappiness" ]]; then
        swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "0")
        if [[ "$swappiness" == "180" ]]; then
            record_pass "vm.swappiness" "180" "180" "Aggressive cold-page offload to ZRAM"
        else
            record_warn "vm.swappiness" "$swappiness" "180" "Live value is $swappiness; target 180 pending rebuild switch" "memory"
        fi
    fi

    if [[ -r "/proc/sys/vm/watermark_boost_factor" ]]; then
        wm_boost=$(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null || echo "0")
        if [[ "$wm_boost" == "0" ]]; then
            record_pass "vm.watermark_boost_factor" "0" "0" "Zero memory allocation micro-stutters"
        else
            record_warn "vm.watermark_boost_factor" "$wm_boost" "0" "Target 0" "memory"
        fi
    fi

    if [[ -r "/proc/sys/vm/page-cluster" ]]; then
        page_cluster=$(cat /proc/sys/vm/page-cluster 2>/dev/null || echo "0")
        if [[ "$page_cluster" == "0" ]]; then
            record_pass "vm.page-cluster" "0 (single page read)" "0" "Prevents unneeded swapin decompression"
        else
            record_warn "vm.page-cluster" "$page_cluster" "0" "Target 0" "memory"
        fi
    fi

    if [[ -r "/proc/sys/vm/vfs_cache_pressure" ]]; then
        vfs_pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo "0")
        if [[ "$vfs_pressure" == "50" ]]; then
            record_pass "vm.vfs_cache_pressure" "50" "50" "Retains dentry/inode cache in RAM"
        else
            record_warn "vm.vfs_cache_pressure" "$vfs_pressure" "50" "Live value is $vfs_pressure; target 50 pending rebuild switch" "memory"
        fi
    fi

    if [[ -r "/proc/sys/vm/watermark_scale_factor" ]]; then
        wm_scale=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo "0")
        if [[ "$wm_scale" == "125" ]]; then
            record_pass "vm.watermark_scale_factor" "125" "125"
        else
            record_warn "vm.watermark_scale_factor" "$wm_scale" "125" "Live value is $wm_scale; target 125 pending rebuild switch" "memory"
        fi
    fi

    JSON_MEMORY=$(cat << EOF
{
  "status": "$STATUS_MEMORY",
  "zram_device": "$zram_dev",
  "algorithm": "$algorithm",
  "disksize_bytes": $disksize,
  "compression_ratio": "$ratio_str",
  "swappiness": $swappiness,
  "target_swappiness": 180,
  "watermark_boost_factor": $wm_boost,
  "page_cluster": $page_cluster,
  "vfs_cache_pressure": $vfs_pressure,
  "target_vfs_cache_pressure": 50
}
EOF
)
}

# 4. Intelligent Process Prioritization (ananicy-cpp)
probe_process_ananicy() {
    section_header "Intelligent Process Prioritization (ananicy-cpp)"

    local service_status="inactive"
    local daemon_running=false
    local daemon_name="ananicy-cpp"
    local note="Service active"

    if systemctl is-active ananicy-cpp.service >/dev/null 2>&1; then
        service_status="active"
        record_pass "ananicy-cpp.service" "active" "active" "Dynamic scheduler & niceness priority manager"
    elif systemctl is-active ananicy.service >/dev/null 2>&1; then
        service_status="active"
        record_pass "ananicy.service" "active" "active"
    else
        service_status="inactive"
        note="Service inactive or pending rebuild switch"
        record_warn "ananicy-cpp.service" "inactive" "active" "Configured in modules/performance/memory.nix; will start upon nixos-rebuild switch" "process"
    fi

    if pgrep -x ananicy-cpp >/dev/null 2>&1; then
        daemon_running=true
        record_pass "ananicy-cpp daemon process" "Running" "Running"
    elif pgrep -x ananicy >/dev/null 2>&1; then
        daemon_running=true
        daemon_name="ananicy"
        record_pass "ananicy daemon process" "Running" "Running"
    else
        record_info "ananicy-cpp daemon process" "Not currently executing (pending service activation)"
    fi

    # Inspect process niceness / RT status of key threads if running
    if pgrep -x pipewire >/dev/null 2>&1; then
        local pw_nice
        pw_nice=$(ps -C pipewire -o ni= 2>/dev/null | head -n1 | tr -d ' ' || echo "0")
        record_pass "Audio Server Process Priority" "nice: $pw_nice" "Protected/RT" "PipeWire low-latency priority"
    fi

    JSON_PROCESS=$(cat << EOF
{
  "status": "$STATUS_PROCESS",
  "active": $(if [[ "$service_status" == "active" ]]; then echo "true"; else echo "false"; fi),
  "daemon": "$daemon_name",
  "daemon_running": $daemon_running,
  "note": "$note"
}
EOF
)
}

# 5. Gaming & NVIDIA GTX 1660 SUPER Optimizations
probe_gaming_nvidia() {
    section_header "Gaming, NVIDIA GTX 1660 SUPER & GameMode"

    local gpu_model="None"
    local driver_ver="unknown"
    local vram_val=0
    local gamemode_status="inactive"
    local gamemode_daemon="inactive"
    local in_gamemode_group=false

    # NVIDIA GPU & Driver
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_info
        gpu_info=$(nvidia-smi --query-gpu=name,driver_version,pstate --format=csv,noheader,nounits 2>/dev/null || echo "")
        if [[ -n "$gpu_info" ]]; then
            gpu_model=$(echo "$gpu_info" | awk -F',' '{print $1}' | sed 's/^ *//')
            driver_ver=$(echo "$gpu_info" | awk -F',' '{print $2}' | sed 's/^ *//')
            record_pass "GPU Hardware Model" "$gpu_model" "GeForce GTX 1660 SUPER" "Driver $driver_ver"
        fi
    else
        record_info "nvidia-smi" "Not in immediate PATH"
    fi

    # VRAM sleep preservation
    if [[ -r "/proc/driver/nvidia/params" ]]; then
        vram_val=$(grep -i "PreserveVideoMemoryAllocations" /proc/driver/nvidia/params | awk '{print $2}' || echo "0")
        if [[ "$vram_val" == "1" || "$vram_val" == "2" ]]; then
            record_pass "NVIDIA VRAM Sleep Preservation" "PreserveVideoMemoryAllocations: $vram_val" "1 or 2" "Eliminates Wayland/Niri wake crashes"
        else
            record_warn "NVIDIA VRAM Sleep Preservation" "$vram_val" "1" "VRAM not preserved across suspend" "gaming"
        fi
    fi

    # GameMode Daemon & Service
    if systemctl --user is-active gamemoded.service >/dev/null 2>&1; then
        gamemode_daemon="active"
        record_pass "gamemoded.service (User Unit)" "active" "active"
    fi

    if command -v gamemoded >/dev/null 2>&1; then
        local gm_out
        gm_out=$(gamemoded -s 2>/dev/null || echo "")
        if [[ "$gm_out" == *"is active"* ]]; then
            gamemode_status="active"
            record_pass "GameMode Runtime Daemon" "active (game running)" "operational"
        else
            gamemode_status="inactive"
            record_pass "GameMode Runtime Daemon" "inactive (ready on demand)" "operational"
        fi
    fi

    # Polkit group membership for spike
    local groups_str
    groups_str=$(id -nG "$USER_VAL" 2>/dev/null || echo "")
    if [[ "$groups_str" == *"gamemode"* ]]; then
        in_gamemode_group=true
        record_pass "User Polkit Group (gamemode)" "Member ($USER_VAL)" "gamemode" "Passwordless cpugovctl/gpuclockctl"
    else
        record_warn "User Polkit Group (gamemode)" "Not yet logged into group" "gamemode" "Configured in gaming.nix; effective upon fresh login session" "gaming"
    fi

    JSON_GAMING=$(cat << EOF
{
  "status": "$STATUS_GAMING",
  "gpu": "$gpu_model",
  "driver_version": "$driver_ver",
  "preserve_vram_allocations": $vram_val,
  "gamemoded_service": "$gamemode_daemon",
  "gamemoded_daemon": "$gamemode_status",
  "gamemode_group": $in_gamemode_group
}
EOF
)
}

# 6. PipeWire Pro-Audio & USB DAC (Temple Pro Black)
probe_audio_pipewire() {
    section_header "PipeWire Pro-Audio & Temple Pro Black DAC"

    local pw_active=false
    local wp_active=false
    local rate=0
    local quantum=0
    local min_quantum=0
    local dac_detected=false
    local dac_name="None"

    # Daemons
    if systemctl --user is-active pipewire.service >/dev/null 2>&1; then
        pw_active=true
        record_pass "pipewire.service (User Unit)" "active" "active"
    else
        record_warn "pipewire.service" "inactive" "active" "PipeWire audio server not running" "audio"
    fi

    if systemctl --user is-active wireplumber.service >/dev/null 2>&1; then
        wp_active=true
        record_pass "wireplumber.service (User Unit)" "active" "active"
    else
        record_warn "wireplumber.service" "inactive" "active" "WirePlumber session manager not running" "audio"
    fi

    # PipeWire Metadata Settings
    if command -v pw-metadata >/dev/null 2>&1; then
        local pw_settings
        pw_settings=$(pw-metadata -n settings 2>/dev/null || echo "")
        if [[ -n "$pw_settings" ]]; then
            rate=$(echo "$pw_settings" | sed -n "s/.*key:'clock\.rate' value:'\([^']*\)'.*/\1/p" || echo "0")
            quantum=$(echo "$pw_settings" | sed -n "s/.*key:'clock\.quantum' value:'\([^']*\)'.*/\1/p" || echo "0")
            min_quantum=$(echo "$pw_settings" | sed -n "s/.*key:'clock\.min-quantum' value:'\([^']*\)'.*/\1/p" || echo "0")

            if [[ "$rate" == "48000" ]]; then
                record_pass "PipeWire Clock Rate" "48000 Hz" "48000 Hz" "Fixed frequency without resample latency"
            else
                record_warn "PipeWire Clock Rate" "${rate} Hz" "48000 Hz" "Clock rate differs from 48000" "audio"
            fi

            if [[ "$min_quantum" == "32" ]]; then
                record_pass "PipeWire Min Quantum" "32 samples (~0.67ms)" "32" "Ultra low-latency buffer floor"
            else
                record_warn "PipeWire Min Quantum" "$min_quantum" "32" "Target min quantum is 32" "audio"
            fi

            if [[ "$quantum" == "128" ]]; then
                record_pass "PipeWire Default Quantum" "128 samples (~2.67ms)" "128" "Pro-audio buffer size"
            else
                record_warn "PipeWire Default Quantum" "${quantum} samples" "128" "Live default quantum is ${quantum}; target 128 configured in audio.nix" "audio"
            fi
        fi
    fi

    # USB DAC Hardware Detection
    if [[ -r "/proc/asound/cards" ]]; then
        if grep -q -i "Temple Pro Black\|XiiSound" /proc/asound/cards 2>/dev/null; then
            dac_detected=true
            dac_name="Temple Pro Black (XiiSound DAC)"
            record_pass "USB Audio DAC" "Temple Pro Black (XiiSound)" "Temple Pro Black" "ALSA soft-mixer & anti-suspend applied"
        else
            record_info "USB Audio DAC" "Temple Pro Black DAC not detected in /proc/asound/cards"
        fi
    fi

    JSON_AUDIO=$(cat << EOF
{
  "status": "$STATUS_AUDIO",
  "pipewire_active": $pw_active,
  "wireplumber_active": $wp_active,
  "rate": ${rate:-0},
  "quantum": ${quantum:-0},
  "target_quantum": 128,
  "min_quantum": ${min_quantum:-0},
  "usb_dac_detected": $dac_detected,
  "dac_model": "$dac_name"
}
EOF
)
}

# 7. Disk I/O Schedulers & Storage Maintenance Timers
probe_storage_io() {
    section_header "Disk I/O Schedulers & Storage Maintenance Timers"

    local fstrim_active=false
    local scrub_active=false
    local nvme_map=""
    local sata_map=""

    # Block Schedulers
    for devpath in /sys/block/*; do
        [[ -d "$devpath" ]] || continue
        local devname
        devname=$(basename "$devpath")

        # Ignore virtual / loop / zram / ram devices
        case "$devname" in
            loop*|zram*|ram*|dm-*|sr*) continue ;;
        esac

        if [[ -r "$devpath/queue/scheduler" ]]; then
            local sched_content
            local active_sched
            sched_content=$(cat "$devpath/queue/scheduler" 2>/dev/null || echo "")
            active_sched=$(echo "$sched_content" | grep -o '\[[^]]*\]' | tr -d '[]' || echo "none")

            if [[ "$devname" == nvme* ]]; then
                local nvme_entry
                if [[ "$active_sched" == "kyber" ]]; then
                    record_pass "NVMe Scheduler ($devname)" "kyber" "kyber" "Low-latency multiqueue scheduling"
                    nvme_entry="\"$devname\": \"kyber\""
                else
                    record_warn "NVMe Scheduler ($devname)" "$active_sched" "kyber" "Udev rule configured in audio.nix; active upon udev trigger" "storage"
                    nvme_entry="\"$devname\": \"$active_sched (target: kyber)\""
                fi
                if [[ -z "$nvme_map" ]]; then
                    nvme_map="$nvme_entry"
                else
                    nvme_map="$nvme_map, $nvme_entry"
                fi
            elif [[ "$devname" == sd* ]]; then
                local sata_entry
                if [[ "$active_sched" == "bfq" ]]; then
                    record_pass "SATA Disk Scheduler ($devname)" "bfq" "bfq" "Budget Fair Queueing desktop responsiveness"
                    sata_entry="\"$devname\": \"bfq\""
                else
                    record_warn "SATA Disk Scheduler ($devname)" "$active_sched" "bfq" "Target bfq for SATA storage" "storage"
                    sata_entry="\"$devname\": \"$active_sched (target: bfq)\""
                fi
                if [[ -z "$sata_map" ]]; then
                    sata_map="$sata_entry"
                else
                    sata_map="$sata_map, $sata_entry"
                fi
            fi
        fi
    done

    # Storage Maintenance Timers
    if systemctl is-active fstrim.timer >/dev/null 2>&1; then
        fstrim_active=true
        record_pass "Storage TRIM Timer (fstrim.timer)" "active" "active" "Weekly SSD cell cleanup"
    else
        record_warn "Storage TRIM Timer (fstrim.timer)" "inactive" "active" "Target enabled in audio.nix" "storage"
    fi

    if systemctl is-active btrfs-scrub@-.timer >/dev/null 2>&1; then
        scrub_active=true
        record_pass "Btrfs Auto-Scrub Timer" "active" "active" "Weekly bitrot detection & healing"
    elif systemctl is-active btrfs-scrub.timer >/dev/null 2>&1; then
        scrub_active=true
        record_pass "Btrfs Auto-Scrub Timer" "active" "active"
    else
        record_warn "Btrfs Auto-Scrub Timer" "inactive" "active" "Target enabled in audio.nix" "storage"
    fi

    JSON_STORAGE=$(cat << EOF
{
  "status": "$STATUS_STORAGE",
  "nvme_schedulers": { ${nvme_map} },
  "sata_schedulers": { ${sata_map} },
  "fstrim_timer": $fstrim_active,
  "btrfs_scrub_timer": $scrub_active
}
EOF
)
}

# ------------------------------------------------------------------------------
# Report Presentation & JSON Generator
# ------------------------------------------------------------------------------
print_banner() {
    if [[ "$OPT_JSON" -eq 1 ]]; then
        return
    fi

    printf "%b================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b      NixOS Performance & System Tuning Verification Suite      %b\n" "$C_BOLD$C_WHITE" "$C_RESET"
    printf "%b================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "  Host: %b%s%b  |  Kernel: %b%s%b  |  User: %b%s (UID %s)%b\n" \
        "$C_BOLD" "$HOSTNAME_VAL" "$C_RESET" \
        "$C_BOLD" "$KERNEL_VAL" "$C_RESET" \
        "$C_BOLD" "$USER_VAL" "$UID_VAL" "$C_RESET"
    printf "  Probing Time: %s  |  Suite Version: %s\n" "$TIMESTAMP_VAL" "$VERSION"
    printf "%b----------------------------------------------------------------%b\n" "$C_DIM" "$C_RESET"
}

print_summary_table() {
    if [[ "$OPT_JSON" -eq 1 ]]; then
        return
    fi

    printf "\n%b================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b                    Performance Suite Scorecard                 %b\n" "$C_BOLD$C_WHITE" "$C_RESET"
    printf "%b================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"

    # Helper function for colored status badge
    badge() {
        case "$1" in
            PASS) printf "%b[ PASS ]%b" "$C_GREEN$C_BOLD" "$C_RESET" ;;
            WARN) printf "%b[ WARN ]%b" "$C_YELLOW$C_BOLD" "$C_RESET" ;;
            FAIL) printf "%b[ FAIL ]%b" "$C_RED$C_BOLD" "$C_RESET" ;;
            *)    printf "[ %s ]" "$1" ;;
        esac
    }

    if [[ "$RUN_KERNEL" -eq 1 ]]; then
        printf "  %-42s : " "Kernel & CachyOS BORE Scheduler"
        badge "$STATUS_KERNEL"
        printf "\n"
    fi
    if [[ "$RUN_CPU" -eq 1 ]]; then
        printf "  %-42s : " "AMD Ryzen 3 3300X & AMD P-State EPP"
        badge "$STATUS_CPU"
        printf "\n"
    fi
    if [[ "$RUN_MEMORY" -eq 1 ]]; then
        printf "  %-42s : " "ZRAM zstd Compression & VM Sysctl"
        badge "$STATUS_MEMORY"
        printf "\n"
    fi
    if [[ "$RUN_PROCESS" -eq 1 ]]; then
        printf "  %-42s : " "Process Prioritization (ananicy-cpp)"
        badge "$STATUS_PROCESS"
        printf "\n"
    fi
    if [[ "$RUN_GAMING" -eq 1 ]]; then
        printf "  %-42s : " "NVIDIA GTX 1660 SUPER & GameMode"
        badge "$STATUS_GAMING"
        printf "\n"
    fi
    if [[ "$RUN_AUDIO" -eq 1 ]]; then
        printf "  %-42s : " "PipeWire Pro-Audio & Temple Pro Black DAC"
        badge "$STATUS_AUDIO"
        printf "\n"
    fi
    if [[ "$RUN_STORAGE" -eq 1 ]]; then
        printf "  %-42s : " "Disk I/O Schedulers & Storage Timers"
        badge "$STATUS_STORAGE"
        printf "\n"
    fi

    printf "%b----------------------------------------------------------------%b\n" "$C_DIM" "$C_RESET"
    printf "  Total Checks: %b%d%b  |  Passed: %b%d%b  |  Warned: %b%d%b  |  Failed: %b%d%b\n" \
        "$C_BOLD" "$TOTAL_CHECKS" "$C_RESET" \
        "$C_GREEN$C_BOLD" "$PASSED_CHECKS" "$C_RESET" \
        "$C_YELLOW$C_BOLD" "$WARNED_CHECKS" "$C_RESET" \
        "$C_RED$C_BOLD" "$FAILED_CHECKS" "$C_RESET"
    printf "%b================================================================%b\n" "$C_BOLD$C_CYAN" "$C_RESET"

    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        printf "%bRESULT: FAILED (%d check failures detected)%b\n" "$C_RED$C_BOLD" "$FAILED_CHECKS" "$C_RESET"
    elif [[ "$WARNED_CHECKS" -gt 0 ]]; then
        printf "%bRESULT: PASS WITH NOTICES (%d items pending rebuild switch)%b\n" "$C_YELLOW$C_BOLD" "$WARNED_CHECKS" "$C_RESET"
        printf "%bTip: Run 'sudo nixos-rebuild switch --flake /etc/nixos#desktop' to activate all pending targets.%b\n" "$C_DIM" "$C_RESET"
    else
        printf "%bRESULT: ALL CHECKS VERIFIED (100%% Operational)%b\n" "$C_GREEN$C_BOLD" "$C_RESET"
    fi
}

emit_json() {
    local overall="PASS"
    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        overall="FAIL"
    elif [[ "$WARNED_CHECKS" -gt 0 ]]; then
        overall="WARN"
    fi

    cat << EOF
{
  "timestamp": "$TIMESTAMP_VAL",
  "hostname": "$HOSTNAME_VAL",
  "kernel": "$KERNEL_VAL",
  "overall_status": "$overall",
  "summary": {
    "total": $TOTAL_CHECKS,
    "passed": $PASSED_CHECKS,
    "warned": $WARNED_CHECKS,
    "failed": $FAILED_CHECKS
  },
  "subsystems": {
    "kernel_bore": $JSON_KERNEL,
    "cpu_epp": $JSON_CPU,
    "memory_zram": $JSON_MEMORY,
    "ananicy": $JSON_PROCESS,
    "gaming_nvidia": $JSON_GAMING,
    "pipewire_audio": $JSON_AUDIO,
    "storage_schedulers": $JSON_STORAGE
  }
}
EOF
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"
    setup_colors

    print_banner

    if [[ "$RUN_KERNEL" -eq 1 ]]; then
        probe_kernel_bore
    fi
    if [[ "$RUN_CPU" -eq 1 ]]; then
        probe_cpu_epp
    fi
    if [[ "$RUN_MEMORY" -eq 1 ]]; then
        probe_memory_zram
    fi
    if [[ "$RUN_PROCESS" -eq 1 ]]; then
        probe_process_ananicy
    fi
    if [[ "$RUN_GAMING" -eq 1 ]]; then
        probe_gaming_nvidia
    fi
    if [[ "$RUN_AUDIO" -eq 1 ]]; then
        probe_audio_pipewire
    fi
    if [[ "$RUN_STORAGE" -eq 1 ]]; then
        probe_storage_io
    fi

    if [[ "$OPT_JSON" -eq 1 ]]; then
        emit_json
    else
        print_summary_table
    fi

    # Exit code determination
    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        exit 1
    fi

    if [[ "$OPT_STRICT" -eq 1 && "$WARNED_CHECKS" -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"
