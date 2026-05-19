from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func

from app.db.session import get_db
from app.models import User, UserDevice, Attendance, Notification
from app.schemas import UserCreate, UserResponse, UserUpdate
from app.core.security import get_password_hash

from typing import List

router = APIRouter(prefix="/users", tags=["User Management (Admin)"])

@router.get("/", response_model=List[UserResponse])
async def get_users(db: AsyncSession = Depends(get_db)):
    """Mendapatkan daftar semua karyawan beserta statistik absensi"""
    result = await db.execute(select(User))
    users = result.scalars().all()
    
    user_list = []
    for user in users:
        # Hitung jumlah absen tepat waktu yang valid
        pres_res = await db.execute(
            select(func.count(Attendance.id))
            .where(Attendance.user_id == user.id)
            .where(Attendance.status.like("%Tepat Waktu%"))
            .where(Attendance.is_valid == True)
        )
        total_present = pres_res.scalar() or 0
        
        # Hitung jumlah absen terlambat yang valid
        late_res = await db.execute(
            select(func.count(Attendance.id))
            .where(Attendance.user_id == user.id)
            .where(Attendance.status.like("%Terlambat%"))
            .where(Attendance.is_valid == True)
        )
        total_late = late_res.scalar() or 0
        
        # Buat dictionary user dengan data tambahan
        user_dict = {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "is_active": user.is_active,
            "is_wfh_allowed": user.is_wfh_allowed,
            "role_id": user.role_id,
            "department_id": user.department_id,
            "shift_id": user.shift_id,
            "total_present": total_present,
            "total_late": total_late
        }
        user_list.append(user_dict)
        
    return user_list

@router.post("/", response_model=UserResponse)
async def create_user(request: UserCreate, db: AsyncSession = Depends(get_db)):
    """Menambahkan data Karyawan baru (oleh Admin)"""
    # Cek apakah email sudah terdaftar
    result = await db.execute(select(User).where(User.email == request.email))
    existing_user = result.scalars().first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email sudah terdaftar.")
        
    new_user = User(
        email=request.email,
        full_name=request.full_name,
        hashed_password=get_password_hash(request.password),
        is_active=request.is_active,
        role_id=request.role_id,
        department_id=request.department_id,
        shift_id=request.shift_id
    )
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    
    return new_user

@router.put("/{user_id}", response_model=UserResponse)
async def update_user(user_id: int, request: UserUpdate, db: AsyncSession = Depends(get_db)):
    """Mengubah data karyawan oleh Admin"""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Karyawan tidak ditemukan.")
        
    # Cek duplikasi email jika email diubah
    if request.email != user.email:
        email_check = await db.execute(select(User).where(User.email == request.email))
        if email_check.scalars().first():
            raise HTTPException(status_code=400, detail="Email sudah digunakan oleh akun lain.")
            
    user.email = request.email
    user.full_name = request.full_name
    user.is_active = request.is_active
    
    if request.password:
        user.hashed_password = get_password_hash(request.password)
        
    await db.commit()
    await db.refresh(user)
    return user

@router.delete("/{user_id}/device", status_code=status.HTTP_204_NO_CONTENT)
async def reset_device(user_id: int, db: AsyncSession = Depends(get_db)):
    """Fitur Reset Device: Menghapus ikatan perangkat pada akun (digunakan saat ganti HP)"""
    # Cari device milik user
    result = await db.execute(select(UserDevice).where(UserDevice.user_id == user_id))
    user_devices = result.scalars().all()
    
    if not user_devices:
        raise HTTPException(status_code=404, detail="Akun ini belum memiliki perangkat yang terikat.")
        
    for device in user_devices:
        await db.delete(device)
        
    await db.commit()
    return

@router.put("/{user_id}/toggle-wfh")
async def toggle_wfh(user_id: int, db: AsyncSession = Depends(get_db)):
    """Mengaktifkan/menonaktifkan izin WFH karyawan"""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Karyawan tidak ditemukan.")
    user.is_wfh_allowed = not user.is_wfh_allowed
    await db.commit()
    await db.refresh(user)
    return {"status": "success", "is_wfh_allowed": user.is_wfh_allowed}

@router.put("/{user_id}/assign-shift/{shift_id}")
async def assign_shift(user_id: int, shift_id: int, db: AsyncSession = Depends(get_db)):
    """Mengubah shift kerja karyawan"""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Karyawan tidak ditemukan.")
    
    from app.models import Shift
    shift_result = await db.execute(select(Shift).where(Shift.id == shift_id))
    shift = shift_result.scalars().first()
    if not shift:
        raise HTTPException(status_code=404, detail="Shift tidak ditemukan.")
        
    user.shift_id = shift_id
    await db.commit()
    await db.refresh(user)
    return {"status": "success", "shift_id": user.shift_id}

@router.get("/{user_id}/notifications")
async def get_user_notifications(user_id: int, db: AsyncSession = Depends(get_db)):
    """Mendapatkan daftar notifikasi untuk karyawan tertentu"""
    result = await db.execute(
        select(Notification)
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at.desc())
    )
    notifs = result.scalars().all()
    return [
        {
            "id": n.id,
            "user_id": n.user_id,
            "title": n.title,
            "message": n.message,
            "created_at": n.created_at.isoformat(),
            "is_read": n.is_read
        } for n in notifs
    ]

@router.put("/notifications/{notif_id}/read")
async def mark_notification_as_read(notif_id: int, db: AsyncSession = Depends(get_db)):
    """Menandai notifikasi sebagai sudah dibaca"""
    result = await db.execute(select(Notification).where(Notification.id == notif_id))
    notif = result.scalars().first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notifikasi tidak ditemukan.")
    notif.is_read = True
    await db.commit()
    return {"status": "success", "message": "Notifikasi ditandai sebagai dibaca."}

from pydantic import BaseModel
class FcmTokenRequest(BaseModel):
    fcm_token: str

@router.post("/{user_id}/fcm-token")
async def bind_fcm_token(user_id: int, payload: FcmTokenRequest, db: AsyncSession = Depends(get_db)):
    """Menyimpan FCM Token HP karyawan untuk Push Notifications"""
    # Self-healing migration: Pastikan kolom fcm_token ada di database
    try:
        from sqlalchemy import text
        await db.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(255)"))
        await db.commit()
    except Exception:
        await db.rollback()
        try:
            await db.execute(text("ALTER TABLE users ADD COLUMN fcm_token VARCHAR(255)"))
            await db.commit()
        except Exception:
            await db.rollback()

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Karyawan tidak ditemukan.")
    
    user.fcm_token = payload.fcm_token
    await db.commit()
    return {"status": "success", "message": "FCM Token berhasil diikat dengan akun karyawan."}
