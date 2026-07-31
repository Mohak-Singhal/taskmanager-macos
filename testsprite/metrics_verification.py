#!/usr/bin/env python3
"""
TestSprite System Metrics & Telemetry Calculation Test Suite
Tests: CPU percentage calculations, Memory sizing math, Network delta aggregation, and Bottleneck threshold alerts.
"""

# Mocking the math formulas used in Swift host_statistics64 and proc_pidinfo calls
def calculate_cpu_percentage(delta_user: int, delta_system: int, delta_idle: int) -> dict:
    total_ticks = delta_user + delta_system + delta_idle
    if total_ticks == 0:
        return {"user": 0.0, "system": 0.0, "total": 0.0}
    
    user_pct = (delta_user / total_ticks) * 100.0
    sys_pct = (delta_system / total_ticks) * 100.0
    return {
        "user": round(user_pct, 2),
        "system": round(sys_pct, 2),
        "total": round(user_pct + sys_pct, 2)
    }

def format_memory_size(bytes_val: int) -> str:
    # Mimics the Swift memory formatter logic in MemoryDetailView/AppHistoryView
    kb = 1024
    mb = kb * 1024
    gb = mb * 1024
    
    if bytes_val >= gb:
        return f"{round(bytes_val / gb, 1)} GB"
    elif bytes_val >= mb:
        return f"{round(bytes_val / mb, 1)} MB"
    elif bytes_val >= kb:
        return f"{round(bytes_val / kb, 1)} KB"
    else:
        return f"{bytes_val} Bytes"

def check_bottleneck_rules(cpu_temp: float, cpu_total: float, memory_pressure: float, swap_used_bytes: int) -> list:
    bottlenecks = []
    
    # 1. Thermal Throttling
    if cpu_temp > 85.0:
        bottlenecks.append({"severity": "CRITICAL", "type": "thermal", "title": "Thermal Throttling Active"})
    elif cpu_temp > 70.0:
        bottlenecks.append({"severity": "WARNING", "type": "thermal", "title": "CPU Temperature is High"})
        
    # 2. CPU Overload
    if cpu_total > 80.0:
        bottlenecks.append({"severity": "CRITICAL", "type": "cpu", "title": "CPU Capacity Saturated"})
        
    # 3. RAM pressure
    if memory_pressure > 80.0:
        bottlenecks.append({"severity": "CRITICAL", "type": "memory", "title": "Critical Memory Pressure"})
    elif memory_pressure > 60.0:
        bottlenecks.append({"severity": "WARNING", "type": "memory", "title": "Elevated Memory Pressure"})
        
    # 4. Excessive Swapping
    if swap_used_bytes > 2 * 1024 * 1024 * 1024: # > 2 GB swap
        bottlenecks.append({"severity": "CRITICAL", "type": "swap", "title": "Excessive SSD Swapping"})
        
    return bottlenecks

# Verification Suite
def run_tests():
    print("=== Running TestSprite Metrics & Telemetry Calculation Tests ===")

    # 1. Test CPU math calculation
    # Normal usage case
    metrics = calculate_cpu_percentage(20, 10, 70)
    assert metrics["user"] == 20.0, f"Expected 20.0 user CPU, got {metrics['user']}"
    assert metrics["system"] == 10.0, f"Expected 10.0 system CPU, got {metrics['system']}"
    assert metrics["total"] == 30.0, f"Expected 30.0 total CPU, got {metrics['total']}"
    
    # Division-by-zero safety check
    metrics_zero = calculate_cpu_percentage(0, 0, 0)
    assert metrics_zero["total"] == 0.0, "Zero ticks should result in 0.0% CPU"
    print("[PASS] CPU percentage math and division-by-zero checks")

    # 2. Test memory formatting string representation
    assert format_memory_size(500) == "500 Bytes"
    assert format_memory_size(2048) == "2.0 KB"
    assert format_memory_size(1572864) == "1.5 MB"
    assert format_memory_size(10737418240) == "10.0 GB"
    print("[PASS] Memory size string formatter representations")

    # 3. Test bottleneck thresholds
    # Normal system state
    b_normal = check_bottleneck_rules(cpu_temp=55.0, cpu_total=15.0, memory_pressure=30.0, swap_used_bytes=0)
    assert len(b_normal) == 0, f"Normal system should have 0 bottlenecks, found: {b_normal}"
    
    # Critical state: Thermal, CPU, and Swap
    b_critical = check_bottleneck_rules(cpu_temp=92.0, cpu_total=85.0, memory_pressure=88.0, swap_used_bytes=3 * 1024 * 1024 * 1024)
    types = [b["type"] for b in b_critical]
    assert "thermal" in types, "Should trigger thermal warning"
    assert "cpu" in types, "Should trigger CPU capacity saturated warning"
    assert "memory" in types, "Should trigger memory pressure warning"
    assert "swap" in types, "Should trigger SSD swap alert"
    assert len(b_critical) == 4, f"Expected 4 warnings, got {len(b_critical)}"
    print("[PASS] Bottleneck alert threshold rule matching")

    print("=== All Metrics Calculation Tests Passed Successfully! ===")

if __name__ == "__main__":
    run_tests()
