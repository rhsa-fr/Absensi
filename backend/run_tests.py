import urllib.request
import urllib.error
import json
import time

BASE_URL = "http://localhost:8000/api/v1"

def request(endpoint, method="POST", data=None):
    url = f"{BASE_URL}{endpoint}"
    req = urllib.request.Request(url, method=method)
    req.add_header('Content-Type', 'application/json')
    if data is not None:
        json_data = json.dumps(data).encode('utf-8')
        req.data = json_data
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        raw_error = e.read().decode()
        try:
            return {"error_code": e.code, "detail": json.loads(raw_error)}
        except json.JSONDecodeError:
            return {"error_code": e.code, "raw_error": raw_error}

print("=== MEMULAI PENGUJIAN API OTOMATIS ===")

# 1. Buat Geofence
print("\n[1] Membuat Titik Geofence (Admin)...")
geo_res = request("/master/geofences", data={
    "name": "Kantor Pusat",
    "latitude": -6.200000,
    "longitude": 106.816666,
    "radius_meters": 50
})
print(" => Hasil:", geo_res)

# 2. Buat User Baru
print("\n[2] Membuat Akun Karyawan Baru (HR)...")
user_res = request("/users/", data={
    "email": "karyawan@perusahaan.com",
    "full_name": "Budi Santoso",
    "password": "rahasia123",
    "is_active": True
})
print(" => Hasil:", user_res)

# 3. Login & Auto-Binding
print("\n[3] Karyawan Budi Login (Silent Auto-Binding ke HP-SAMSUNG-BUDI-123)...")
login_res = request("/auth/login", data={
    "email": "karyawan@perusahaan.com",
    "password": "rahasia123",
    "device_id": "HP-SAMSUNG-BUDI-123"
})
if "access_token" in login_res:
    print(" => Hasil: Sukses! Token JWT diterima dan Device ID berhasil diikat.")
else:
    print(" => Hasil:", login_res)

# 4. Tes Negative: Device ID Salah
print("\n[4] SKENARIO KECURANGAN: Budi mencoba login dari HP Lain (HP-IPHONE-LAIN-456)...")
login_fail = request("/auth/login", data={
    "email": "karyawan@perusahaan.com",
    "password": "rahasia123",
    "device_id": "HP-IPHONE-LAIN-456"
})
print(" => Hasil (Diharapkan ERROR 403):", login_fail)

# 5. Generate QR Token
print("\n[5] Layar Lobi menghasilkan Dynamic QR Code...")
qr_res = request("/attendance/qr-generate", data={
    "geofence_id": 1
})
if "qr_token" in qr_res:
    print(" => Hasil: Sukses! Token QR dengan batas waktu 15 detik tercipta.")
    qr_token = qr_res["qr_token"]
else:
    print(" => Hasil:", qr_res)
    qr_token = ""

# 6. Scan QR
print("\n[6] Budi menscan QR tersebut di Lobi dengan HP aslinya...")
scan_res = request("/attendance/scan", data={
    "qr_token": qr_token,
    "latitude": -6.200000,
    "longitude": 106.816666,
    "device_id": "HP-SAMSUNG-BUDI-123",
    "user_id": 1
})
print(" => Hasil:", scan_res)

# 7. Tes Negative: QR Kedaluwarsa
print("\n[7] SKENARIO KECURANGAN: Budi memfoto QR, mengirimkannya ke temannya via WA.")
print("    Sistem menunggu 16 detik (simulasi waktu pengiriman foto)...")
time.sleep(16)
scan_fail = request("/attendance/scan", data={
    "qr_token": qr_token,
    "latitude": -6.200000,
    "longitude": 106.816666,
    "device_id": "HP-SAMSUNG-BUDI-123", # Anggap saja bisa memalsukan device ID
    "user_id": 1
})
print(" => Hasil (Diharapkan ERROR 400):", scan_fail)

print("\n=== PENGUJIAN SELESAI ===")
