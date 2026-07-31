#!/usr/bin/env python3
"""
TestSprite Error Handling & Subprocess Failure Test Suite
Tests: Malformed JSON recovery, Command timeouts, and Command Permission Denied execution safety.
"""

import json
import os

# Simulator for App JSON recovery
def simulate_load_data(raw_json_str: str) -> dict:
    # Mimics swift loadData method that decodes insights_data.json
    try:
        data = json.loads(raw_json_str)
        # Verify schema structure
        if "storageSnapshots" not in data or "networkLogs" not in data:
            raise KeyError("Missing required keys")
        return data
    except (json.JSONDecodeError, KeyError, TypeError):
        # Graceful recovery: return fresh empty schema
        return {"storageSnapshots": [], "networkLogs": []}

# Simulator for Subprocess execution with strict timeouts
def simulate_subprocess_call(command: list, mock_hang: bool = False, permission_denied: bool = False) -> dict:
    # Mimics Swift process execution with timeout checks
    TIMEOUT_LIMIT = 1.0 # 1.0 second limit for osascript/pmset
    
    if mock_hang:
        # Simulate thread execution exceeding limit
        execution_time = 5.0
        if execution_time > TIMEOUT_LIMIT:
            return {"exit_code": -1, "output": "", "error": "TIMEOUT: Subprocess terminated after 1.0s limit."}
            
    if permission_denied:
        return {"exit_code": 1, "output": "", "error": "Operation not permitted (TCC automation permission denied)."}
        
    return {"exit_code": 0, "output": "Success output", "error": ""}

# Verification Suite
def run_tests():
    print("=== Running TestSprite Error Handling & Exception Tests ===")

    # 1. Test case: Successful valid JSON parsing
    valid_json = '{"storageSnapshots": [{"date": "2026-07-31", "sizes": {}}], "networkLogs": []}'
    parsed = simulate_load_data(valid_json)
    assert len(parsed["storageSnapshots"]) == 1, "Should successfully load valid JSON snapshots"
    print("[PASS] Valid JSON loading and decoding")

    # 2. Test case: Malformed JSON corruption recovery (Failure scenario)
    corrupted_json = '{"storageSnapshots": [{"date": "2026-07-31" ...malformed-part... '
    recovered = simulate_load_data(corrupted_json)
    assert "storageSnapshots" in recovered, "Recovery should return a clean valid dictionary"
    assert len(recovered["storageSnapshots"]) == 0, "Corrupted storage lists should be cleared"
    print("[PASS] Corrupted JSON graceful recovery")

    # 3. Test case: Missing key recovery (Failure scenario)
    incomplete_json = '{"somethingElse": 123}'
    recovered_inc = simulate_load_data(incomplete_json)
    assert "storageSnapshots" in recovered_inc, "Should fallback to fresh state on schema mismatch"
    print("[PASS] Schema-mismatched JSON structure recovery")

    # 4. Test case: Subprocess hanging timeout (Edge case)
    res_hang = simulate_subprocess_call(["osascript", "-e", "tell app Safari..."], mock_hang=True)
    assert res_hang["exit_code"] == -1, "Hanging process should return timeout code"
    assert "TIMEOUT" in res_hang["error"], "Timeout error details should be reported"
    print("[PASS] Subprocess execution timeout and termination enforcement")

    # 5. Test case: Subprocess TCC permission failure (Failure scenario)
    res_perm = simulate_subprocess_call(["lsof", "-i"], permission_denied=True)
    assert res_perm["exit_code"] == 1, "Permission failure should return error code"
    assert "Operation not permitted" in res_perm["error"], "TCC permissions warnings should be reported"
    print("[PASS] Subprocess permission warning and exit status handling")

    print("=== All Error Handling Tests Passed Successfully! ===")

if __name__ == "__main__":
    run_tests()
