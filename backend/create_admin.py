import urllib.request
import json
import urllib.error

data = json.dumps({
    "email": "admin@perusahaan.com",
    "full_name": "Super Admin HR",
    "password": "admin123",
    "is_active": True
}).encode("utf-8")

req = urllib.request.Request("http://localhost:8000/api/v1/users/", data=data, headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req) as response:
        print("SUCCESS:", response.read().decode())
except urllib.error.HTTPError as e:
    print("ERROR:", e.read().decode())
except Exception as e:
    print("UNKNOWN ERROR:", str(e))
