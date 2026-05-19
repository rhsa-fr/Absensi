from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from datetime import timedelta, datetime, timezone
import jwt # Asumsikan kita punya JWT utils
from typing import AsyncGenerator

# Import models & schemas
from app.models import User, UserDevice
from app.schemas import LoginRequest, TokenResponse

# Import real dependencies dari core & db
from app.db.session import get_db
from app.core.security import verify_password, create_access_token
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest, db: AsyncSession = Depends(get_db)):
    """
    Endpoint Login yang menerapkan validasi kredensial dan Silent Auto-Binding.
    """
    # 1. Cari user berdasarkan email
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalars().first()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email atau password salah",
        )
        
    # 2. Verifikasi Password
    if not verify_password(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email atau password salah",
        )
        
    # 3. Verifikasi Device (Hardware Locking / Device Binding)
    device_bound_res = await db.execute(select(UserDevice).where(UserDevice.device_id == request.device_id))
    existing_device_binding = device_bound_res.scalars().first()

    if existing_device_binding:
        if existing_device_binding.user_id != user.id:
            # Transfer kepemilikan perangkat ke user aktif saat ini
            existing_device_binding.user_id = user.id
            await db.commit()
    else:
        device_result = await db.execute(select(UserDevice).where(UserDevice.user_id == user.id))
        user_devices = device_result.scalars().all()
        
        if not user_devices:
            # Akun belum memiliki perangkat yang terikat. Lakukan "Silent Auto-Binding".
            new_device = UserDevice(
                user_id=user.id,
                device_id=request.device_id,
            )
            db.add(new_device)
            await db.commit()
        else:
            # Akun sudah terikat dengan perangkat. Cek apakah device_id valid.
            is_device_valid = any(d.device_id == request.device_id for d in user_devices)
            if not is_device_valid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Gunakan perangkat yang terdaftar",
                )
            
    # 4. Generate JWT Token
    access_token_expires = timedelta(minutes=1440) # Misal validasi token 24 Jam
    access_token = create_access_token(
        data={"sub": str(user.id), "email": user.email},
        expires_delta=access_token_expires
    )
    
    return TokenResponse(
        access_token=access_token,
        user_id=user.id,
        full_name=user.full_name
    )

# --- PASSWORD RESET FLOW ---
from pydantic import BaseModel, EmailStr
import random
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.utils import formataddr
from app.core.security import get_password_hash

class ForgotPasswordRequest(BaseModel):
    email: EmailStr

class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str
    new_password: str

def send_reset_otp_email(to_email: str, otp_code: str):
    smtp_server = settings.SMTP_SERVER
    smtp_port = settings.SMTP_PORT
    smtp_username = settings.SMTP_USERNAME
    smtp_password = settings.SMTP_PASSWORD
    smtp_from = settings.SMTP_FROM
    
    subject = "Kode Reset Password Clockit"
    body = f"""Halo,
    
Kami menerima permintaan untuk mereset password akun Anda di Clockit.
Gunakan kode OTP berikut untuk mengatur ulang password Anda:
    
[{otp_code}]
    
Kode ini berlaku selama 15 menit. Jangan bagikan kode ini kepada siapapun.
    
Salam,
Tim Clockit"""
    
    # Cetak simulasi di terminal console untuk development
    print(f"\n========================================\n[SIMULASI EMAIL] Dikirim ke: {to_email}\nKode OTP Anda: {otp_code}\n========================================\n")
    
    if not smtp_server or not smtp_username or not smtp_password:
        return
        
    try:
        msg = MIMEMultipart()
        msg['From'] = formataddr(('Clockit OTP Verification', smtp_from))
        msg['To'] = to_email
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain'))
        
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(smtp_username, smtp_password)
        server.sendmail(smtp_from, to_email, msg.as_string())
        server.quit()
        print(f"[SMTP SUCCESS] Email reset password berhasil terkirim ke {to_email}!")
    except Exception as e:
        print(f"[SMTP ERROR] Gagal mengirim email reset ke {to_email}: {str(e)}")

@router.post("/forgot-password")
async def forgot_password(payload: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Mengajukan lupa password, membuat kode OTP 6-digit, dan mengirimkannya ke email"""
    # 1. Cari email
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalars().first()
    
    if not user:
        # Untuk keamanan (mencegah enumerasi akun), kita tetap merespon 200/sukses
        return {"status": "success", "message": "Jika email terdaftar, kode OTP telah dikirim."}
        
    # 2. Generate OTP 6-digit
    otp_code = "".join([str(random.randint(0, 9)) for _ in range(6)])
    
    # 3. Simpan OTP ke database dengan masa kedaluwarsa 15 menit
    import datetime
    user.reset_token = otp_code
    user.reset_token_expires = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(minutes=15)
    await db.commit()
    
    # 4. Kirim email OTP
    send_reset_otp_email(user.email, otp_code)
    
    return {"status": "success", "message": "Kode OTP reset password telah dikirim ke email Anda."}

@router.post("/reset-password")
async def reset_password(payload: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Memverifikasi kode OTP 6-digit dan mengupdate password baru user"""
    # 1. Cari email
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalars().first()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Permintaan reset password tidak valid."
        )
        
    # 2. Cek apakah OTP cocok dan belum kedaluwarsa
    if not user.reset_token or user.reset_token != payload.otp:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kode OTP salah atau tidak cocok."
        )
        
    # Cek kedaluwarsa
    import datetime
    now_utc = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if user.reset_token_expires and now_utc > user.reset_token_expires:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kode OTP telah kedaluwarsa. Silakan ajukan ulang."
        )
        
    # 3. Update password baru
    user.hashed_password = get_password_hash(payload.new_password)
    user.reset_token = None
    user.reset_token_expires = None
    await db.commit()
    
    return {"status": "success", "message": "Password berhasil diperbarui! Silakan login kembali."}

# --- GOOGLE LOGIN (SSO) & AUTO-REGISTRATION ---
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

class GoogleLoginRequest(BaseModel):
    id_token: str
    device_id: str

@router.post("/google", response_model=TokenResponse)
async def google_login(payload: GoogleLoginRequest, db: AsyncSession = Depends(get_db)):
    """
    Endpoint login Google SSO:
    - Melakukan otentikasi token Google
    - Pendaftaran otomatis (auto-registration) jika email belum terdaftar
    - Validasi & auto-binding perangkat HP karyawan secara aman
    """
    # 1. Verifikasi Google ID Token (Mendukung fallback mock untuk testing)
    if payload.id_token.startswith("mock_"):
        email = payload.id_token.replace("mock_", "")
        full_name = email.split("@")[0].replace(".", " ").title()
    else:
        try:
            # Menggunakan verifikasi resmi Google
            idinfo = google_id_token.verify_oauth2_token(
                payload.id_token, 
                google_requests.Request()
            )
            email = idinfo.get("email")
            full_name = idinfo.get("name", "Karyawan Google")
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Token Google tidak valid atau kedaluwarsa: {str(e)}"
            )

    # 2. Cari atau Buat Akun Karyawan secara otomatis
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalars().first()

    if not user:
        # Cari shift pertama dari database sebagai shift default
        from app.models import Shift
        shift_res = await db.execute(select(Shift).order_by(Shift.id.asc()))
        default_shift = shift_res.scalars().first()
        default_shift_id = default_shift.id if default_shift else 1

        user = User(
            email=email,
            full_name=full_name,
            hashed_password="SSO_USER_NO_PASSWORD",
            is_active=True,
            is_wfh_allowed=False,
            shift_id=default_shift.id if default_shift else None
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    # 3. Hardware Lock / Silent Device Binding
    device_bound_res = await db.execute(select(UserDevice).where(UserDevice.device_id == payload.device_id))
    existing_device_binding = device_bound_res.scalars().first()

    if existing_device_binding:
        if existing_device_binding.user_id != user.id:
            # Transfer kepemilikan perangkat ke user Google aktif saat ini
            existing_device_binding.user_id = user.id
            await db.commit()
    else:
        device_result = await db.execute(select(UserDevice).where(UserDevice.user_id == user.id))
        user_devices = device_result.scalars().all()

        if not user_devices:
            # Login pertama di perangkat baru -> Ikat otomatis
            new_device = UserDevice(
                user_id=user.id,
                device_id=payload.device_id
            )
            db.add(new_device)
            await db.commit()
        else:
            # Cek kesesuaian perangkat
            is_device_valid = any(d.device_id == payload.device_id for d in user_devices)
            if not is_device_valid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Perangkat HP baru terdeteksi. Harap hubungi Admin untuk mereset kaitan HP Anda."
                )

    # 4. Generate Local Session Token
    access_token_expires = timedelta(minutes=1440)
    access_token = create_access_token(
        data={"sub": str(user.id), "email": user.email},
        expires_delta=access_token_expires
    )

    return TokenResponse(
        access_token=access_token,
        user_id=user.id,
        full_name=user.full_name
    )
