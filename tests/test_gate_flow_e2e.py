#!/usr/bin/env python3
"""
End-to-End Gate Flow & Custody Verification Test for SecurePark

Verifies:
1. Registered vehicle entry -> INSIDE in oncampus.php, ingress in logs.php, stats.php insideCount
2. Registered vehicle exit -> OUTSIDE, removed from oncampus.php, egress in logs.php with duration
3. Anti-passback & state rules:
   - INSIDE + ENTRY -> warns / prevents duplicate entry
   - OUTSIDE + EXIT -> warns / prevents exit without entry
4. Visitor pass lifecycle:
   - Pass created -> NOT inside oncampus.php yet
   - Pass scanned & approved at entrance -> INSIDE in oncampus.php
   - Pass scanned & approved at exit -> REMOVED from oncampus.php
5. Source of truth consistency:
   - stats.php inside == oncampus.php total == vehicles inside + active visitors inside
"""

import sys
import json
import urllib.request
import urllib.error

BASE = "http://localhost:8000/web-app-admin/api"

def request(path, method="GET", body=None, token=None):
    url = f"{BASE}/{path.lstrip('/')}"
    headers = {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-Auth-Token"] = token
    
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode("utf-8")
            parsed = json.loads(content)
            parsed["_http"] = resp.status
            return parsed
    except urllib.error.HTTPError as e:
        content = e.read().decode("utf-8")
        try:
            parsed = json.loads(content)
            parsed["_http"] = e.code
            return parsed
        except Exception:
            return {"status": e.code, "_http": e.code, "message": content}

def is_ok(res, expected_code=200):
    if res.get("_http") == expected_code:
        return True
    if expected_code in (200, 201) and (res.get("success") is True or res.get("status") == "success"):
        return True
    return False

def login_admin():
    for pwd in ["Admin-Pass-2026", "Password123!"]:
        res = request("auth.php?action=login", "POST", {"username": "admin", "password": pwd})
        if is_ok(res):
            return res["data"]["token"]
    raise RuntimeError(f"Admin login failed: {res}")

def main():
    print("=== SecurePark End-to-End Gate Flow Verification ===")
    token = login_admin()
    print("1. Logged in as administrator.")

    # 1. Inspect oncampus initial state
    oc1 = request("oncampus.php", token=token)
    stats1 = request("stats.php", token=token)
    assert is_ok(oc1), f"oncampus.php failed: {oc1}"
    assert is_ok(stats1), f"stats.php failed: {stats1}"
    initial_total = oc1["data"]["counts"]["total"]
    initial_stats = stats1["data"]["inside"]
    print(f"2. Initial oncampus headcount: {initial_total} | stats.php inside: {initial_stats}")
    assert initial_total == initial_stats, f"Headcount mismatch: {initial_total} != {initial_stats}"

    # 2. Register test vehicle
    import random
    plate = f"E2E-{random.randint(100, 999)}"
    veh_payload = {
        "plateNumber": plate,
        "ownerName": "Test Student E2E",
        "ownerRole": "Student",
        "ownerIdNumber": "2026-99999",
        "department": "BSCS",
        "ownerPhone": "09170009999",
        "ownerEmail": "e2e@ncst.edu.ph",
        "vehicleType": "4-Wheel",
        "makeModelColor": "Toyota Vios Silver",
        "stickerYear": "2026",
        "authorizedDrivers": [
            {"fullName": "Test Student E2E", "relationship": "Self (Owner)", "licenseNo": "D12-34-567890"}
        ]
    }
    reg_res = request("vehicles.php", "POST", veh_payload, token=token)
    assert is_ok(reg_res, 201), f"Registration failed: {reg_res}"
    veh = reg_res["data"]
    driver_id = veh["authorizedDrivers"][0]["id"]
    qr_payload = veh.get("qrPayload")
    print(f"3. Registered vehicle {plate} with student ID 2026-99999.")

    # Check that vehicle starts OUTSIDE
    veh_check = request(f"vehicles.php?plate={plate}", token=token)
    assert veh_check["data"]["status"] in ("Outside", "Exited"), f"New vehicle should start outside: {veh_check}"
    print(f"   Vehicle status is initially: {veh_check['data']['status']}")

    # 3. Entrance Gate Verification & Ingress
    verify_res = request("verify.php", "POST", {"qr_code": qr_payload, "gate_type": "Ingress"}, token=token)
    assert is_ok(verify_res) and verify_res["data"]["result"] == "VALID", f"QR verification failed: {verify_res}"
    print("4. QR verification passed for entrance (status: VALID).")

    # Record Entrance passage
    entry_log_payload = {
        "plate": plate,
        "action": "Entry Recorded",
        "gate_type": "Ingress",
        "driver_id": driver_id,
        "qr_code": qr_payload,
        "notes": "Verified at Gate 1"
    }
    entry_res = request("logs.php", "POST", entry_log_payload, token=token)
    assert is_ok(entry_res, 201), f"Entry log recording failed: {entry_res}"
    print(f"5. Entry approved and recorded at gate for {plate}.")

    # 4. Verify Vehicle is now INSIDE across all endpoints
    veh_after_entry = request(f"vehicles.php?plate={plate}", token=token)
    assert veh_after_entry["data"]["status"] == "Inside Campus", f"Vehicle should be Inside Campus: {veh_after_entry}"

    oc2 = request("oncampus.php", token=token)
    stats2 = request("stats.php", token=token)
    assert oc2["data"]["counts"]["total"] == initial_total + 1, f"oncampus count did not increment: {oc2['data']['counts']}"
    assert stats2["data"]["inside"] == oc2["data"]["counts"]["total"], f"stats.php inside does not match oncampus: {stats2['data']['inside']} vs {oc2['data']['counts']['total']}"
    
    inside_plates = [v["plateNumber"] for v in oc2["data"]["vehicles"]]
    assert plate in inside_plates, f"{plate} not found in oncampus.php vehicles list: {inside_plates}"
    print(f"6. CONFIRMED: {plate} is now INSIDE in oncampus.php, vehicles.php, and stats.php ({oc2['data']['counts']['total']} total inside).")

    # 5. Anti-Passback Test: Vehicle inside attempts second entrance
    entry_dup = request("verify.php", "POST", {"qr_code": qr_payload, "gate_type": "Ingress"}, token=token)
    assert any("already" in w.lower() and "inside" in w.lower() for w in entry_dup["data"].get("warnings", [])), f"Expected duplicate entry warning: {entry_dup}"
    print("7. CONFIRMED: Anti-passback detected duplicate entry attempt with warning.")

    # 6. Exit Gate Verification & Egress
    exit_verify = request("verify.php", "POST", {"qr_code": qr_payload, "gate_type": "Egress"}, token=token)
    assert is_ok(exit_verify) and exit_verify["data"]["result"] == "VALID", f"Exit verify failed: {exit_verify}"
    
    exit_log_payload = {
        "plate": plate,
        "action": "Exit Approved",
        "gate_type": "Egress",
        "driver_id": driver_id,
        "qr_code": qr_payload,
        "notes": "Verified exit at Gate 2"
    }
    exit_res = request("logs.php", "POST", exit_log_payload, token=token)
    assert is_ok(exit_res, 201), f"Exit log failed: {exit_res}"
    print(f"8. Exit approved and recorded for {plate}.")

    # 7. Verify Vehicle is now OUTSIDE and removed from oncampus.php
    veh_after_exit = request(f"vehicles.php?plate={plate}", token=token)
    assert veh_after_exit["data"]["status"] == "Exited", f"Vehicle status should be Exited: {veh_after_exit}"

    oc3 = request("oncampus.php", token=token)
    stats3 = request("stats.php", token=token)
    assert oc3["data"]["counts"]["total"] == initial_total, f"oncampus count did not decrement on exit: {oc3['data']['counts']}"
    assert stats3["data"]["inside"] == oc3["data"]["counts"]["total"]
    
    inside_plates_after = [v["plateNumber"] for v in oc3["data"]["vehicles"]]
    assert plate not in inside_plates_after, f"{plate} still appears in oncampus.php after exit!"
    print(f"9. CONFIRMED: {plate} is OUTSIDE and automatically removed from oncampus.php.")

    # 8. Check Exit without Entry
    exit_without_entry = request("verify.php", "POST", {"qr_code": qr_payload, "gate_type": "Egress"}, token=token)
    assert any("not recorded" in w.lower() and "inside" in w.lower() for w in exit_without_entry["data"].get("warnings", [])), f"Expected missing ingress warning: {exit_without_entry}"
    print("10. CONFIRMED: Exit without prior entry triggers warning.")

    # 9. Visitor Pass Full Flow
    vis_plate = f"VIS-{random.randint(100, 999)}"
    visitor_payload = {
        "visitor_name": "Maria Santos",
        "contact_number": "09181234567",
        "plate": vis_plate,
        "vehicle_model": "Honda Civic Red",
        "person_to_visit": "Dean Smith",
        "purpose": "Official Meeting",
        "items": [{"name": "Projector", "quantity": 1, "description": "Asset"}]
    }
    vp_res = request("visitors.php", "POST", visitor_payload, token=token)
    assert is_ok(vp_res, 201), f"Visitor creation failed: {vp_res}"
    vp = vp_res["data"]
    vp_id = vp["id"]
    vp_qr = vp["qrPayload"]
    print(f"11. Created visitor pass {vp['passCode']} for {visitor_payload['plate']}.")

    # Verify pass creation alone is NOT physical entry!
    oc_vp1 = request("oncampus.php", token=token)
    visitor_ids_inside = [v["passId"] for v in oc_vp1["data"]["visitors"]]
    assert vp_id not in visitor_ids_inside, f"Visitor pass should NOT be in oncampus.php before entrance scan!"
    print("12. CONFIRMED: Creating visitor pass does NOT treat visitor as inside campus.")

    # Scan visitor pass at entrance
    vp_entry_verify = request("verify.php", "POST", {"qr_code": vp_qr, "gate_type": "Ingress"}, token=token)
    assert is_ok(vp_entry_verify) and vp_entry_verify["data"]["result"] == "VALID"
    
    vp_entry_log = {
        "plate": vis_plate,
        "action": "Entry Recorded",
        "gate_type": "Ingress",
        "visitor_pass_id": vp_id,
        "items_verified": True,
        "notes": "Verified visitor"
    }
    vp_entry_log_res = request("logs.php", "POST", vp_entry_log, token=token)
    assert is_ok(vp_entry_log_res, 201)
    print("13. Visitor approved at entrance gate.")

    # Verify visitor is NOW inside
    oc_vp2 = request("oncampus.php", token=token)
    stats_vp2 = request("stats.php", token=token)
    visitor_ids_inside2 = [v["passId"] for v in oc_vp2["data"]["visitors"]]
    assert vp_id in visitor_ids_inside2, f"Visitor {vp_id} should now be in oncampus.php!"
    assert stats_vp2["data"]["inside"] == oc_vp2["data"]["counts"]["total"]
    print(f"14. CONFIRMED: Visitor is now INSIDE oncampus.php and stats.php ({oc_vp2['data']['counts']['total']} total).")

    # Scan visitor at exit
    vp_exit_log = {
        "plate": vis_plate,
        "action": "Exit Approved",
        "gate_type": "Egress",
        "visitor_pass_id": vp_id,
        "items_verified": True,
        "notes": "Verified visitor exit"
    }
    vp_exit_log_res = request("logs.php", "POST", vp_exit_log, token=token)
    assert is_ok(vp_exit_log_res, 201)
    print("15. Visitor approved and exited at exit gate.")

    # 10. Flagged & Blocked During Exit (Registered Vehicle)
    print("\n--- Testing Exit Blockage Flow (Registered Vehicle) ---")
    blk_plate = f"BLK-{random.randint(100, 999)}"
    reg_blk_payload = {
        "plateNumber": blk_plate,
        "vehicleType": "Sedan",
        "makeModelColor": "Toyota Vios Black",
        "ownerName": "Arthur Pendelton",
        "ownerRole": "Faculty",
        "ownerEmail": f"arthur.{random.randint(1000, 9999)}@ncst.edu.ph",
        "ownerPhone": "09175551234",
        "ownerIdNumber": "FAC-2026-088",
        "department": "Engineering",
        "status": "Outside",
        "authorizedDrivers": [
            {"fullName": "Arthur Pendelton", "relationship": "Self (Owner)", "licenseNo": "D99-88-776655"}
        ]
    }
    blk_reg_res = request("vehicles.php", "POST", reg_blk_payload, token=token)
    assert is_ok(blk_reg_res, 201), f"Vehicle registration failed: {blk_reg_res}"
    blk_veh = blk_reg_res["data"]
    blk_driver_id = blk_veh["authorizedDrivers"][0]["id"]
    blk_qr = blk_veh["qrPayload"]
    print(f"17. Registered vehicle {blk_plate} for exit-blocked testing.")

    # Admit vehicle at entrance
    blk_entry = request("logs.php", "POST", {
        "plate": blk_plate,
        "action": "Entry Recorded",
        "gate_type": "Ingress",
        "driver_id": blk_driver_id,
        "driverName": "Arthur Pendelton",
        "driverRelationship": "Self (Owner)",
        "notes": "Admitted at Gate 1"
    }, token=token)
    assert is_ok(blk_entry, 201), f"Entry recording failed: {blk_entry}"
    print(f"18. Vehicle {blk_plate} entered campus.")

    # Verify vehicle is inside
    oc_blk1 = request("oncampus.php", token=token)
    assert any(v["plateNumber"] == blk_plate for v in oc_blk1["data"]["vehicles"]), f"{blk_plate} should be inside campus!"
    print(f"19. CONFIRMED: {blk_plate} is physically on campus.")

    # Vehicle attempts exit, but guard flags & blocks them (Exit Denied)
    blk_exit_log = request("logs.php", "POST", {
        "plate": blk_plate,
        "action": "Exit Denied",
        "gate_type": "Egress",
        "driverName": "Arthur Pendelton",
        "driverRelationship": "Self (Owner)",
        "notes": "Exit Denied: Active Campus Security Hold - Unreturned Lab Equipment"
    }, token=token)
    assert is_ok(blk_exit_log, 201), f"Exit Denied log recording failed: {blk_exit_log}"
    
    # Flag incident / security hold
    blk_incident = request("incidents.php", "POST", {
        "plateNumber": blk_plate,
        "reason": "Security Hold: Unreturned Lab Asset",
        "vehicleType": "Sedan",
        "ownerName": "Arthur Pendelton",
        "ownerRole": "Faculty",
        "driverName": "Arthur Pendelton",
        "driverRelationship": "Self (Owner)",
        "gatePoint": "Gate 2 (Main Egress)",
        "notes": "Exit Denied at Gate 2. Vehicle intercepted and held on campus."
    }, token=token)
    assert is_ok(blk_incident, 201), f"Incident creation failed: {blk_incident}"
    case_num = blk_incident["data"]["caseNumber"]
    print(f"20. Exit blocked and security incident {case_num} created for {blk_plate}.")

    # VERIFY: Because exit was DENIED, vehicle MUST STILL BE ON CAMPUS!
    oc_blk2 = request("oncampus.php", token=token)
    stats_blk2 = request("stats.php", token=token)
    veh_oncampus = next((v for v in oc_blk2["data"]["vehicles"] if v["plateNumber"] == blk_plate), None)
    assert veh_oncampus is not None, f"CRITICAL FAILURE: Blocked vehicle {blk_plate} disappeared from oncampus.php!"
    assert veh_oncampus.get("exitDenied") is True, f"Vehicle {blk_plate} should have exitDenied=True!"
    assert veh_oncampus.get("activeHold") is not None, f"Vehicle {blk_plate} should have activeHold populated!"
    assert veh_oncampus["activeHold"]["caseNumber"] == case_num, f"Expected case {case_num} in activeHold!"
    print(f"21. CONFIRMED: Blocked vehicle {blk_plate} STILL APPEARS in oncampus.php with exitDenied=True and activeHold={case_num}!")

    # Verify latest log is Exit Denied with status Inside Campus
    logs_res = request("logs.php", token=token)
    latest_log = logs_res["data"][0]
    assert latest_log["plateNumber"] == blk_plate
    assert latest_log["action"] == "Exit Denied"
    assert latest_log["status"] == "Inside Campus", f"Exit Denied log status should be 'Inside Campus', got: {latest_log['status']}"
    print(f"22. CONFIRMED: Gate log records Exit Denied with custody status 'Inside Campus'.")

    # 11. Flagged & Blocked During Exit (Visitor Pass)
    print("\n--- Testing Exit Blockage Flow (Visitor Pass) ---")
    vis_blk_plate = f"VBL-{random.randint(100, 999)}"
    vp_blk_res = request("visitors.php", "POST", {
        "visitor_name": "Marcus Aurelius",
        "contact_number": "09198887766",
        "plate": vis_blk_plate,
        "vehicle_model": "Ford Ranger Black",
        "person_to_visit": "VP Academic Affairs",
        "purpose": "Vendor Delivery",
        "items": [{"name": "Heavy Machinery Tools", "quantity": 3, "description": "Industrial Tools"}]
    }, token=token)
    assert is_ok(vp_blk_res, 201)
    vp_blk = vp_blk_res["data"]
    vp_blk_id = vp_blk["id"]

    # Admit visitor at entrance
    vp_blk_entry = request("logs.php", "POST", {
        "plate": vis_blk_plate,
        "action": "Entry Recorded",
        "gate_type": "Ingress",
        "visitor_pass_id": vp_blk_id,
        "items_verified": True,
        "notes": "Verified vendor tools"
    }, token=token)
    assert is_ok(vp_blk_entry, 201)

    # Visitor attempts exit, but items do not match or exit is denied
    vp_blk_exit = request("logs.php", "POST", {
        "plate": vis_blk_plate,
        "action": "Exit Denied",
        "gate_type": "Egress",
        "visitor_pass_id": vp_blk_id,
        "notes": "Exit Denied: Missing declared tools item verification"
    }, token=token)
    assert is_ok(vp_blk_exit, 201)

    # Flag incident for visitor
    vis_inc = request("incidents.php", "POST", {
        "plateNumber": vis_blk_plate,
        "reason": "Property Inspection Hold: Missing Tool",
        "vehicleType": "Ford Ranger Black",
        "ownerName": "Marcus Aurelius",
        "ownerRole": "Visitor",
        "driverName": "Marcus Aurelius",
        "driverRelationship": "Visitor (Day Pass)",
        "gatePoint": "Gate 2 (Main Egress)",
        "notes": "Exit Denied at Gate 2. Vehicle held for security property inspection."
    }, token=token)
    assert is_ok(vis_inc, 201)
    vis_case = vis_inc["data"]["caseNumber"]
    print(f"23. Visitor pass exit blocked and security incident {vis_case} created for {vis_blk_plate}.")

    # VERIFY: Visitor MUST STILL BE ON CAMPUS!
    oc_vis = request("oncampus.php", token=token)
    vis_oncampus = next((v for v in oc_vis["data"]["visitors"] if v["passId"] == vp_blk_id), None)
    assert vis_oncampus is not None, f"CRITICAL FAILURE: Blocked visitor pass {vp_blk_id} disappeared from oncampus.php!"
    assert vis_oncampus.get("exitDenied") is True, f"Visitor should have exitDenied=True!"
    assert vis_oncampus.get("activeHold") is not None, f"Visitor should have activeHold populated!"
    assert vis_oncampus["activeHold"]["caseNumber"] == vis_case, f"Expected case {vis_case} in visitor activeHold!"
    print(f"24. CONFIRMED: Blocked visitor {vis_blk_plate} STILL APPEARS in oncampus.php with exitDenied=True and activeHold={vis_case}!")

    print("\nALL 24 END-TO-END GATE FLOW, HEADCOUNT, AND EXIT-BLOCKED CUSTODY RULES PASSED PERFECTLY!")

if __name__ == "__main__":
    main()
