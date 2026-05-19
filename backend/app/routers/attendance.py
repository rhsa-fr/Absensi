from fastapi import APIRouter, Depends, HTTPException, status
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from datetime import datetime, timezone, timedelta
from pydantic import BaseModel
import jwt

from app.models import UserDevice, Geofence, Attendance, User, Shift
from app.db.session import get_db
from app.core.config import settings

router = APIRouter(prefix="/attendance", tags=["Attendance (Phase 2)"])

class QRGenerateRequest(BaseModel):
    # Dihasilkan oleh admin/sistem untuk ditampilkan di lobi
    geofence_id: int

class QRScanRequest(BaseModel):
    qr_token: str
    latitude: float
    longitude: float
    device_id: str
    user_id: int # Pada praktiknya, user_id ini didapat dari Bearer Token JWT (Auth)
    is_wfh: bool = False

@router.post("/qr-generate")
async def generate_qr(request: QRGenerateRequest):
    """
    Endpoint untuk Web Admin: Menghasilkan token QR Dinamis setiap 15 detik.
    """
    # Token berisi geofence_id dan timestamp saat dibuat
    payload = {
        "geofence_id": request.geofence_id,
        "exp": datetime.now(timezone.utc) + timedelta(seconds=15),
        "iat": datetime.now(timezone.utc)
    }
    
    qr_token = jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return {"qr_token": qr_token, "expires_in_seconds": 15}

@router.post("/scan")
async def scan_qr(request: QRScanRequest, db: AsyncSession = Depends(get_db)):
    """
    Endpoint untuk Mobile App: Menerima hasil scan QR beserta GPS & Device ID.
    (Menerapkan Validasi 3 Lapis: QR, Device ID, GPS Geofencing)
    """
    # 1. Validasi Token QR (Layer 1)
    if request.is_wfh:
        geo_fallback_query = select(Geofence)
        geo_fallback_res = await db.execute(geo_fallback_query)
        geo_fallback = geo_fallback_res.scalars().first()
        if not geo_fallback:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail="Silakan daftarkan minimal satu lokasi kantor di Web Admin terlebih dahulu."
            )
        geofence_id = geo_fallback.id
    else:
        try:
            payload = jwt.decode(request.qr_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
            geofence_id = payload.get("geofence_id")
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail="QR Code sudah kedaluwarsa. Silakan scan ulang di layar lobi."
            )
        except jwt.InvalidTokenError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail="QR Code tidak valid."
            )

    # Ambil data User beserta Shift-nya untuk pengecekan awal
    user_query = select(User).where(User.id == request.user_id)
    user_result = await db.execute(user_query)
    user = user_result.scalars().first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Karyawan tidak ditemukan."
        )

    # 2. Validasi Device ID (Layer 2 - Hardware Locking)
    device_result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == request.user_id, 
            UserDevice.device_id == request.device_id
        )
    )
    user_device = device_result.scalars().first()
    if not user_device:
         raise HTTPException(
             status_code=status.HTTP_403_FORBIDDEN, 
             detail="Gunakan perangkat (HP) yang sudah didaftarkan untuk akun ini."
         )

    # Validasi Akses WFH (Mencegah Kecurangan Presensi WFH)
    if request.is_wfh and not user.is_wfh_allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, 
            detail="Akses WFH ditolak. Anda tidak memiliki izin WFH aktif dari HRD hari ini."
        )

    # 3. Validasi Geofencing menggunakan PostGIS / GeoAlchemy2 (Layer 3 - GPS)
    geofence_query = select(
        Geofence.id,
        Geofence.name,
        Geofence.radius_meters,
        func.ST_Y(Geofence.location).label("latitude"),
        func.ST_X(Geofence.location).label("longitude")
    ).where(Geofence.id == geofence_id)
    geofence_result = await db.execute(geofence_query)
    geofence = geofence_result.first()
    if not geofence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Lokasi geofence tidak ditemukan di database."
        )
    
    # Hitung jarak fisik (dalam meter) antara koordinat HP dan koordinat Geofence menggunakan Haversine
    from math import radians, cos, sin, asin, sqrt
    lon1, lat1, lon2, lat2 = map(radians, [request.longitude, request.latitude, geofence.longitude, geofence.latitude])
    dlon = lon2 - lon1 
    dlat = lat2 - lat1 
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * asin(sqrt(a)) 
    r = 6371000  # Radius Bumi dalam meter
    distance = c * r
    
    is_within_radius = distance <= geofence.radius_meters
    
    if not is_within_radius and not request.is_wfh:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail=f"Posisi Anda ({distance:.1f}m) berada di luar radius sah kantor ({geofence.radius_meters:.1f}m). Presensi dibatalkan."
        )

    # Ambil Shift user atau gunakan fallback standard
    start_time = None
    tolerance_minutes = 0
    if user.shift_id:
        shift_query = select(Shift).where(Shift.id == user.shift_id)
        shift_result = await db.execute(shift_query)
        shift = shift_result.scalars().first()
        if shift:
            start_time = shift.start_time
            tolerance_minutes = shift.tolerance_minutes

    if not start_time:
        from datetime import time
        start_time = time(8, 0, 0)
        tolerance_minutes = 15

    # Bandingkan jam & menit dari waktu scan lokal dengan batas shift
    local_now = datetime.now()
    scan_minutes = local_now.hour * 60 + local_now.minute
    limit_minutes = start_time.hour * 60 + start_time.minute + tolerance_minutes

    suffix = " (WFH)" if request.is_wfh else ""
    if scan_minutes <= limit_minutes:
        attendance_status = f"Tepat Waktu{suffix}"
    else:
        attendance_status = f"Terlambat{suffix}"

    # Jika SEMUA layer validasi lulus, catat absensi ke database
    new_attendance = Attendance(
        user_id=request.user_id,
        geofence_id=geofence_id,
        device_id=request.device_id,
        # GeoAlchemy2 menerima input point dalam format WKT (Well-Known Text)
        actual_location=f"SRID=4326;POINT({request.longitude} {request.latitude})", 
        status=attendance_status,
        is_valid=True
    )
    db.add(new_attendance)
    await db.commit()
    await db.refresh(new_attendance)

    return {
        "message": "Absensi berhasil diverifikasi!", 
        "attendance_id": new_attendance.id,
        "status": new_attendance.status
    }

@router.get("/logs")
async def get_attendance_logs(user_id: Optional[int] = None, db: AsyncSession = Depends(get_db)):
    """Mendapatkan riwayat absensi terbaru"""
    query = select(
        Attendance, 
        User.full_name, 
        Geofence.name.label("geofence_name"),
        func.ST_Y(Attendance.actual_location).label("actual_latitude"),
        func.ST_X(Attendance.actual_location).label("actual_longitude")
    ).join(User, Attendance.user_id == User.id).join(Geofence, Attendance.geofence_id == Geofence.id)
    
    if user_id is not None:
        query = query.where(Attendance.user_id == user_id)
        
    query = query.order_by(Attendance.scan_time.desc()).limit(100)
    result = await db.execute(query)
    
    rows = result.all()
    return [
        {
            "id": r.Attendance.id,
            "user_id": r.Attendance.user_id,
            "full_name": r.full_name,
            "geofence_name": r.geofence_name,
            "scanned_at": r.Attendance.scan_time.isoformat() if r.Attendance.scan_time else None,
            "status": r.Attendance.status,
            "is_valid": r.Attendance.is_valid,
            "device_id": r.Attendance.device_id,
            "latitude": r.actual_latitude,
            "longitude": r.actual_longitude
        } for r in rows
    ]
