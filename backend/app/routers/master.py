from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from typing import List

from app.db.session import get_db
from app.models import Geofence, Shift
from app.schemas import GeofenceCreate, GeofenceResponse, ShiftCreate, ShiftResponse

router = APIRouter(prefix="/master", tags=["Master Data Management (Admin)"])

# --- GEOFENCE CRUD ---
@router.post("/geofences", response_model=GeofenceResponse)
async def create_geofence(request: GeofenceCreate, db: AsyncSession = Depends(get_db)):
    """Menambahkan titik Geofence baru (Lokasi Kantor/Proyek)"""
    new_geofence = Geofence(
        name=request.name,
        location=f"SRID=4326;POINT({request.longitude} {request.latitude})",
        radius_meters=request.radius_meters
    )
    db.add(new_geofence)
    await db.commit()
    await db.refresh(new_geofence)
    
    return {
        "id": new_geofence.id,
        "name": new_geofence.name,
        "radius_meters": new_geofence.radius_meters,
        "latitude": request.latitude,
        "longitude": request.longitude
    }

@router.get("/geofences", response_model=List[GeofenceResponse])
async def get_geofences(db: AsyncSession = Depends(get_db)):
    """Mendapatkan daftar semua lokasi geofence"""
    query = select(
        Geofence.id,
        Geofence.name,
        Geofence.radius_meters,
        func.ST_Y(Geofence.location).label("latitude"),
        func.ST_X(Geofence.location).label("longitude")
    )
    result = await db.execute(query)
    rows = result.all()
    
    return [
        {
            "id": r.id, 
            "name": r.name, 
            "radius_meters": r.radius_meters, 
            "latitude": r.latitude, 
            "longitude": r.longitude
        } for r in rows
    ]

@router.put("/geofences/{geofence_id}", response_model=GeofenceResponse)
async def update_geofence(geofence_id: int, request: GeofenceCreate, db: AsyncSession = Depends(get_db)):
    """Mengubah data Geofence yang sudah ada"""
    result = await db.execute(select(Geofence).where(Geofence.id == geofence_id))
    geofence = result.scalars().first()
    if not geofence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Geofence tidak ditemukan."
        )
    geofence.name = request.name
    geofence.location = f"SRID=4326;POINT({request.longitude} {request.latitude})"
    geofence.radius_meters = request.radius_meters
    await db.commit()
    await db.refresh(geofence)
    
    return {
        "id": geofence.id,
        "name": geofence.name,
        "radius_meters": geofence.radius_meters,
        "latitude": request.latitude,
        "longitude": request.longitude
    }

from sqlalchemy.exc import IntegrityError

@router.delete("/geofences/{geofence_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_geofence(geofence_id: int, db: AsyncSession = Depends(get_db)):
    """Menghapus titik Geofence"""
    result = await db.execute(select(Geofence).where(Geofence.id == geofence_id))
    geofence = result.scalars().first()
    if not geofence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Geofence tidak ditemukan."
        )
    try:
        await db.delete(geofence)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tidak dapat menghapus lokasi ini karena terdapat data absensi karyawan yang terikat pada lokasi ini."
        )
    return None

# --- SHIFT CRUD ---
@router.post("/shifts", response_model=ShiftResponse)
async def create_shift(request: ShiftCreate, db: AsyncSession = Depends(get_db)):
    """Menambahkan jam kerja Shift baru"""
    new_shift = Shift(
        name=request.name,
        start_time=request.start_time,
        end_time=request.end_time,
        tolerance_minutes=request.tolerance_minutes
    )
    db.add(new_shift)
    await db.commit()
    await db.refresh(new_shift)
    
    return new_shift

@router.get("/shifts", response_model=List[ShiftResponse])
async def get_shifts(db: AsyncSession = Depends(get_db)):
    """Mendapatkan daftar semua shift kerja"""
    result = await db.execute(select(Shift))
    shifts = result.scalars().all()
    return shifts

@router.put("/shifts/{shift_id}", response_model=ShiftResponse)
async def update_shift(shift_id: int, request: ShiftCreate, db: AsyncSession = Depends(get_db)):
    """Mengubah data Shift yang sudah ada"""
    result = await db.execute(select(Shift).where(Shift.id == shift_id))
    shift = result.scalars().first()
    if not shift:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Shift tidak ditemukan."
        )
    shift.name = request.name
    shift.start_time = request.start_time
    shift.end_time = request.end_time
    shift.tolerance_minutes = request.tolerance_minutes
    await db.commit()
    await db.refresh(shift)
    return shift

@router.delete("/shifts/{shift_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_shift(shift_id: int, db: AsyncSession = Depends(get_db)):
    """Menghapus data Shift"""
    result = await db.execute(select(Shift).where(Shift.id == shift_id))
    shift = result.scalars().first()
    if not shift:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Shift tidak ditemukan."
        )
    try:
        await db.delete(shift)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tidak dapat menghapus shift ini karena terdapat karyawan yang terikat pada shift ini."
        )
    return None
