from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import List
import os
import shutil
import datetime

from app.db.session import get_db
from app.models import LeaveRequest, LeaveBalance, User, Notification
from app.schemas import LeaveRequestCreate, LeaveRequestResponse, LeaveBalanceResponse

router = APIRouter(prefix="/leaves", tags=["Leave Management (Fase 3)"])

# Dependency Mock: Di project asli, ini akan mengambil user_id dari validasi JWT (Bearer Token)
# Diperbarui agar mendukung parameter user_id secara dinamis agar klop dengan multi-user sesi mobile
async def get_current_user_id(user_id: int = 1) -> int:
    return user_id

@router.post("/upload")
async def upload_leave_document(file: UploadFile = File(...)):
    """Upload dokumen pendukung cuti / surat keterangan sakit"""
    os.makedirs("uploads", exist_ok=True)
    # Membuat nama file unik berbasis timestamp untuk keamanan data
    timestamp = int(datetime.datetime.now().timestamp())
    safe_filename = f"{timestamp}_{file.filename.replace(' ', '_')}"
    file_path = os.path.join("uploads", safe_filename)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    return {
        "status": "success",
        "document_url": f"http://192.168.1.7:8000/uploads/{safe_filename}"
    }

@router.get("/me", response_model=List[LeaveRequestResponse])
async def get_my_leaves(user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """Mendapatkan daftar pengajuan cuti milik karyawan yang sedang login"""
    result = await db.execute(select(LeaveRequest).where(LeaveRequest.user_id == user_id).order_by(LeaveRequest.start_date.desc()))
    leaves = result.scalars().all()
    return leaves

@router.get("/balance", response_model=LeaveBalanceResponse)
async def get_my_leave_balance(user_id: int = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """Mendapatkan sisa kuota cuti karyawan tahun ini"""
    current_year = datetime.datetime.now().year
    
    result = await db.execute(
        select(LeaveBalance).where(LeaveBalance.user_id == user_id, LeaveBalance.year == current_year)
    )
    balance = result.scalars().first()
    
    if not balance:
        # Auto-initialize default 12 days quota for new users (self-healing architecture)
        balance = LeaveBalance(
            user_id=user_id,
            year=current_year,
            total_quota=12,
            used_quota=0
        )
        db.add(balance)
        await db.commit()
        await db.refresh(balance)
        
    return balance

@router.post("/", response_model=LeaveRequestResponse)
async def create_leave_request(
    request: LeaveRequestCreate, 
    user_id: int = Depends(get_current_user_id), 
    db: AsyncSession = Depends(get_db)
):
    """Karyawan mengajukan cuti baru"""
    # 1. Cek kuota cuti
    current_year = datetime.datetime.now().year
    balance_result = await db.execute(
        select(LeaveBalance).where(LeaveBalance.user_id == user_id, LeaveBalance.year == current_year)
    )
    balance = balance_result.scalars().first()
    
    if not balance:
        # Auto-initialize default 12 days quota if not exists
        balance = LeaveBalance(
            user_id=user_id,
            year=current_year,
            total_quota=12,
            used_quota=0
        )
        db.add(balance)
        await db.commit()
        await db.refresh(balance)
        
    if balance.total_quota - balance.used_quota <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Kuota cuti Anda sudah habis.")
        
    new_leave = LeaveRequest(
        user_id=user_id,
        start_date=request.start_date.replace(tzinfo=None),
        end_date=request.end_date.replace(tzinfo=None),
        reason=request.reason,
        document_url=request.document_url,
        status="Pending"
    )
    db.add(new_leave)
    
    # 3. Trigger Notifikasi Terkirim Ke Karyawan (In-App)
    start_str = request.start_date.strftime("%d/%m/%Y")
    end_str = request.end_date.strftime("%d/%m/%Y")
    notif = Notification(
        user_id=user_id,
        title="Pengajuan Cuti Terkirim",
        message=f"Pengajuan cuti/izin Anda ({start_str} s/d {end_str}) berhasil dikirim ke HRD. Status: Pending."
    )
    db.add(notif)
    await db.commit()
    await db.refresh(new_leave)

    # 4. Trigger Push Notification Nyata ke HP
    try:
        user_res = await db.execute(select(User).where(User.id == user_id))
        user = user_res.scalars().first()
        if user and user.fcm_token:
            from app.core.notifications import send_push_notification
            await send_push_notification(
                fcm_token=user.fcm_token,
                title="Pengajuan Cuti Terkirim 📅",
                body=f"Pengajuan cuti Anda ({start_str} s/d {end_str}) berhasil dikirim ke HRD."
            )
    except Exception:
        pass
    
    return new_leave

@router.put("/{leave_id}/approve")
async def approve_leave(leave_id: int, db: AsyncSession = Depends(get_db)):
    """Endpoint untuk HR menyetujui cuti dan memotong kuota"""
    # 1. Ambil data pengajuan
    leave_result = await db.execute(select(LeaveRequest).where(LeaveRequest.id == leave_id))
    leave_req = leave_result.scalars().first()
    
    if not leave_req:
        raise HTTPException(status_code=404, detail="Pengajuan cuti tidak ditemukan.")
    if leave_req.status != "Pending":
        raise HTTPException(status_code=400, detail="Pengajuan ini sudah diproses.")
        
    # 2. Kurangi kuota cuti
    current_year = leave_req.start_date.year
    balance_result = await db.execute(
        select(LeaveBalance).where(LeaveBalance.user_id == leave_req.user_id, LeaveBalance.year == current_year)
    )
    balance = balance_result.scalars().first()
    
    if balance:
        days = (leave_req.end_date - leave_req.start_date).days + 1
        balance.used_quota += days
        
    # 3. Update status
    leave_req.status = "Approved"
    
    # 4. Trigger Notifikasi Disetujui Ke Karyawan
    start_str = leave_req.start_date.strftime("%d/%m/%Y")
    end_str = leave_req.end_date.strftime("%d/%m/%Y")
    notif = Notification(
        user_id=leave_req.user_id,
        title="Pengajuan Cuti Disetujui",
        message=f"Selamat! Pengajuan cuti/izin Anda untuk tanggal {start_str} s/d {end_str} telah DISETUJUI oleh HRD."
    )
    db.add(notif)
    await db.commit()

    # 5. Trigger Real-Time Push Notification ke HP Karyawan
    try:
        user_res = await db.execute(select(User).where(User.id == leave_req.user_id))
        user = user_res.scalars().first()
        if user and user.fcm_token:
            from app.core.notifications import send_push_notification
            await send_push_notification(
                fcm_token=user.fcm_token,
                title="Pengajuan Cuti Disetujui 🎉",
                body=f"Selamat! Pengajuan cuti Anda ({start_str} s/d {end_str}) telah DISETUJUI oleh HRD."
            )
    except Exception:
        pass
    
    return {"message": "Cuti disetujui dan kuota telah dipotong."}

@router.get("/")
async def get_all_leaves(db: AsyncSession = Depends(get_db)):
    """Mendapatkan semua pengajuan cuti karyawan (untuk HRD)"""
    result = await db.execute(
        select(LeaveRequest, User.full_name, User.email)
        .join(User, LeaveRequest.user_id == User.id)
        .order_by(LeaveRequest.start_date.desc())
    )
    rows = result.all()
    return [
        {
            "id": r.LeaveRequest.id,
            "user_id": r.LeaveRequest.user_id,
            "full_name": r.full_name,
            "email": r.email,
            "start_date": r.LeaveRequest.start_date.isoformat() if r.LeaveRequest.start_date else None,
            "end_date": r.LeaveRequest.end_date.isoformat() if r.LeaveRequest.end_date else None,
            "reason": r.LeaveRequest.reason,
            "document_url": r.LeaveRequest.document_url,
            "status": r.LeaveRequest.status
        } for r in rows
    ]

@router.put("/{leave_id}/reject")
async def reject_leave(leave_id: int, db: AsyncSession = Depends(get_db)):
    """Menolak pengajuan cuti"""
    leave_result = await db.execute(select(LeaveRequest).where(LeaveRequest.id == leave_id))
    leave_req = leave_result.scalars().first()
    
    if not leave_req:
        raise HTTPException(status_code=404, detail="Pengajuan cuti tidak ditemukan.")
    if leave_req.status != "Pending":
        raise HTTPException(status_code=400, detail="Pengajuan ini sudah diproses.")
        
    leave_req.status = "Rejected"
    
    # Trigger Notifikasi Ditolak Ke Karyawan
    start_str = leave_req.start_date.strftime("%d/%m/%Y")
    end_str = leave_req.end_date.strftime("%d/%m/%Y")
    notif = Notification(
        user_id=leave_req.user_id,
        title="Pengajuan Cuti Ditolak",
        message=f"Mohon maaf, pengajuan cuti/izin Anda ({start_str} s/d {end_str}) telah DITOLAK oleh HRD."
    )
    db.add(notif)
    await db.commit()

    # Trigger Real-Time Push Notification ke HP Karyawan
    try:
        user_res = await db.execute(select(User).where(User.id == leave_req.user_id))
        user = user_res.scalars().first()
        if user and user.fcm_token:
            from app.core.notifications import send_push_notification
            await send_push_notification(
                fcm_token=user.fcm_token,
                title="Pengajuan Cuti Ditolak ⚠️",
                body=f"Mohon maaf, pengajuan cuti Anda ({start_str} s/d {end_str}) DITOLAK oleh HRD."
            )
    except Exception:
        pass
    
    return {"message": "Pengajuan cuti ditolak."}
