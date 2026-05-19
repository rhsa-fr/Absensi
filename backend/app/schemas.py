from pydantic import BaseModel, EmailStr, Field, ConfigDict
from datetime import time, datetime
from typing import Optional, List

# --- SHIFTS ---
class ShiftBase(BaseModel):
    name: str
    start_time: time
    end_time: time
    tolerance_minutes: int = 0

class ShiftCreate(ShiftBase):
    pass

class ShiftResponse(ShiftBase):
    id: int
    
    model_config = ConfigDict(from_attributes=True)

# --- USER DEVICES ---
class UserDeviceBase(BaseModel):
    device_id: str = Field(..., description="Unique Device ID / IMEI")
    device_model: Optional[str] = None

class UserDeviceCreate(UserDeviceBase):
    user_id: int

class UserDeviceResponse(UserDeviceBase):
    id: int
    user_id: int
    registered_at: datetime
    
    model_config = ConfigDict(from_attributes=True)

# --- USERS ---
class UserBase(BaseModel):
    email: EmailStr
    full_name: str
    is_active: bool = True
    is_wfh_allowed: bool = False
    role_id: Optional[int] = None
    department_id: Optional[int] = None
    shift_id: Optional[int] = None

class UserCreate(UserBase):
    password: str

class UserUpdate(UserBase):
    password: Optional[str] = None

class UserResponse(UserBase):
    id: int
    total_present: Optional[int] = 0
    total_late: Optional[int] = 0
    
    model_config = ConfigDict(from_attributes=True)

# --- AUTH (Requests/Responses) ---
class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    device_id: str = Field(..., description="Device ID unik (IMEI/UUID) untuk verifikasi atau auto-binding")

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    full_name: str

# --- LEAVES ---
class LeaveRequestCreate(BaseModel):
    start_date: datetime
    end_date: datetime
    reason: Optional[str] = None
    document_url: Optional[str] = None

class LeaveRequestResponse(BaseModel):
    id: int
    user_id: int
    start_date: datetime
    end_date: datetime
    reason: Optional[str]
    document_url: Optional[str]
    status: str
    
    model_config = ConfigDict(from_attributes=True)

class LeaveBalanceResponse(BaseModel):
    id: int
    year: int
    total_quota: int
    used_quota: int
    
    model_config = ConfigDict(from_attributes=True)

# --- GEOFENCES ---
class GeofenceCreate(BaseModel):
    name: str
    latitude: float
    longitude: float
    radius_meters: float

class GeofenceResponse(BaseModel):
    id: int
    name: str
    radius_meters: float
    latitude: float
    longitude: float
    
    model_config = ConfigDict(from_attributes=True)
