#!/usr/bin/env python3
"""
TestSprite Mock Authentication Simulation Suite
Tests: User Signup, User Login, Session Validation, CRUD on user profile, Edge Cases, and Failure Scenarios.
"""

import sys
import hashlib
import uuid

# In-memory mock database
MOCK_USER_DB = {}
ACTIVE_SESSIONS = set()

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode('utf-8')).hexdigest()

def signup(username: str, password: str, email: str) -> dict:
    # Validation: empty values
    if not username or not password or not email:
        return {"success": False, "message": "All fields are required."}
    
    # Validation: email format check (basic)
    if "@" not in email or "." not in email:
        return {"success": False, "message": "Invalid email address format."}
        
    # Validation: password strength check
    if len(password) < 8:
        return {"success": False, "message": "Password must be at least 8 characters long."}
        
    # Validation: duplicate username
    if username in MOCK_USER_DB:
        return {"success": False, "message": "Username is already taken."}
        
    # Create user
    user_id = str(uuid.uuid4())
    MOCK_USER_DB[username] = {
        "id": user_id,
        "username": username,
        "password_hash": hash_password(password),
        "email": email,
        "profile": {"fullName": "", "theme": "system"}
    }
    return {"success": True, "user_id": user_id, "message": "User registered successfully."}

def login(username: str, password: str) -> dict:
    if not username or not password:
        return {"success": False, "message": "Username and password are required."}
        
    user = MOCK_USER_DB.get(username)
    if not user:
        return {"success": False, "message": "Invalid username or password."}
        
    if user["password_hash"] != hash_password(password):
        return {"success": False, "message": "Invalid username or password."}
        
    session_token = str(uuid.uuid4())
    ACTIVE_SESSIONS.add(session_token)
    return {"success": True, "token": session_token, "message": "Login successful."}

def update_profile(username: str, session_token: str, full_name: str, theme: str) -> dict:
    if session_token not in ACTIVE_SESSIONS:
        return {"success": False, "message": "Unauthorized: Invalid or expired session."}
        
    user = MOCK_USER_DB.get(username)
    if not user:
        return {"success": False, "message": "User not found."}
        
    user["profile"]["fullName"] = full_name
    user["profile"]["theme"] = theme
    return {"success": True, "profile": user["profile"], "message": "Profile updated successfully."}

# Verification Suite
def run_tests():
    print("=== Running TestSprite Mock Authentication Simulation Tests ===")
    
    # 1. Test case: Successful Signup (Signup flow)
    res = signup("testuser", "securepass123", "test@example.com")
    assert res["success"] is True, f"Failed normal signup: {res}"
    print("[PASS] Successful Signup test")

    # 2. Test case: Duplicate Signup (Failure scenario)
    res = signup("testuser", "anotherpass", "dup@example.com")
    assert res["success"] is False, "Duplicate signup should fail"
    assert res["message"] == "Username is already taken.", f"Incorrect err msg: {res}"
    print("[PASS] Duplicate Signup validation test")

    # 3. Test case: Weak Password (Form validation)
    res = signup("weakuser", "short", "weak@example.com")
    assert res["success"] is False, "Weak password signup should fail"
    assert "at least 8 characters" in res["message"], f"Incorrect password validation: {res}"
    print("[PASS] Password length validation test")

    # 4. Test case: Invalid Email (Form validation)
    res = signup("bademail", "securepass123", "notanemail")
    assert res["success"] is False, "Invalid email signup should fail"
    assert "Invalid email" in res["message"], f"Incorrect email validation: {res}"
    print("[PASS] Email format validation test")

    # 5. Test case: Successful Login (Login flow)
    res = login("testuser", "securepass123")
    assert res["success"] is True, f"Failed normal login: {res}"
    token = res["token"]
    print("[PASS] Successful Login test")

    # 6. Test case: Wrong Password Login (Failure scenario)
    res = login("testuser", "wrongpass")
    assert res["success"] is False, "Login with wrong password should fail"
    print("[PASS] Wrong password login validation test")

    # 7. Test case: Profile Update CRUD (Authorized)
    res = update_profile("testuser", token, "Mohak Singhal", "dark")
    assert res["success"] is True, f"Failed profile update: {res}"
    assert res["profile"]["fullName"] == "Mohak Singhal"
    print("[PASS] Profile CRUD Update (Authorized) test")

    # 8. Test case: Profile Update CRUD (Unauthorized/Failure)
    res = update_profile("testuser", "fake-token-xyz", "Imposter", "light")
    assert res["success"] is False, "Unauthorized profile update should fail"
    print("[PASS] Profile CRUD Update (Unauthorized) test")
    
    print("=== All Authentication Simulation Tests Passed Successfully! ===")

if __name__ == "__main__":
    run_tests()
